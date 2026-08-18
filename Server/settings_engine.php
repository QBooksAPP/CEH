<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

/*
 * Excel TREND equivalent.
 *
 * The 5 / 8 / 11 cm gate readings are calibration reference points,
 * not minimum/maximum operating limits. Extrapolation is allowed.
 */
function qbook_settings_trend_gate(array $points, float $target): float
{
    $n = count($points);

    if ($n < 2) {
        throw new RuntimeException('INSUFFICIENT_TREND_POINTS');
    }

    $sumX = 0.0;
    $sumY = 0.0;
    $sumXY = 0.0;
    $sumXX = 0.0;

    foreach ($points as $point) {
        $x = (float)$point['kg_per_count'];
        $y = (float)$point['gate'];

        $sumX += $x;
        $sumY += $y;
        $sumXY += $x * $y;
        $sumXX += $x * $x;
    }

    $denominator = ($n * $sumXX) - ($sumX * $sumX);

    if (abs($denominator) < 0.0000000001) {
        throw new RuntimeException('INVALID_CALIBRATION_CURVE');
    }

    $slope =
        (($n * $sumXY) - ($sumX * $sumY))
        / $denominator;

    $intercept =
        ($sumY - ($slope * $sumX))
        / $n;

    return $intercept + ($slope * $target);
}


/*
 * Main QBook settings calculation.
 *
 * Returns full-precision calculation values.
 * Display rounding is handled by Preview / Apply endpoints.
 */
function qbook_calculate_settings(
    int $mixerId,
    int $mixDesignId,
    float $conveyorSpeed
): array {

    if ($mixerId <= 0) {
        throw new RuntimeException('MIXER_REQUIRED');
    }

    if ($mixDesignId <= 0) {
        throw new RuntimeException('MIX_DESIGN_REQUIRED');
    }

    if ($conveyorSpeed <= 0) {
        throw new RuntimeException('INVALID_CONVEYOR_SPEED');
    }

    $db = qbook_db();

    /*
     * Active mixer.
     */
    $stmt = $db->prepare(
        "SELECT
            id,
            code,
            name,
            model,
            truck_number
         FROM qbook_mixers
         WHERE id = ?
           AND is_active = 1
         LIMIT 1"
    );

    $stmt->execute([$mixerId]);
    $mixer = $stmt->fetch();

    if (!$mixer) {
        throw new RuntimeException('MIXER_NOT_FOUND');
    }

    /*
     * Active mix design only.
     *
     * Inactive templates therefore cannot be used by operators.
     */
    $stmt = $db->prepare(
        "SELECT
            id,
            name,
            description,
            design_mode,
            client_name,
            project_name,
            cement_kg,
            sand_kg,
            granite_kg,
            water_l,
            batch_volume_m3,
            version_no
         FROM qbook_mix_designs
         WHERE id = ?
           AND is_active = 1
         LIMIT 1"
    );

    $stmt->execute([$mixDesignId]);
    $mix = $stmt->fetch();

    if (!$mix) {
        throw new RuntimeException('MIX_DESIGN_NOT_FOUND_OR_INACTIVE');
    }

    /*
     * Batch volume is always 1.00 m3.
     */
    if (abs((float)$mix['batch_volume_m3'] - 1.0) > 0.0001) {
        throw new RuntimeException('INVALID_BATCH_VOLUME');
    }

    /*
     * Latest approved calibration for the selected mixer.
     */
    $stmt = $db->prepare(
        "SELECT
            id,
            mixer_id,
            calibration_date,
            stone_moisture_pct,
            sand_moisture_pct,
            reviewed_at
         FROM qbook_calibrations
         WHERE mixer_id = ?
           AND status = 'APPROVED'
         ORDER BY reviewed_at DESC, id DESC
         LIMIT 1"
    );

    $stmt->execute([$mixerId]);
    $calibration = $stmt->fetch();

    if (!$calibration) {
        throw new RuntimeException('NO_APPROVED_CALIBRATION');
    }

    /*
     * Calibration results.
     */
    $stmt = $db->prepare(
        "SELECT
            material,
            gate_cm,
            kg_per_count
         FROM qbook_calibration_results
         WHERE calibration_id = ?
         ORDER BY material, gate_cm"
    );

    $stmt->execute([(int)$calibration['id']]);
    $rows = $stmt->fetchAll();

    $cementKgPerCount = null;
    $sandPoints = [];
    $stonePoints = [];

    foreach ($rows as $row) {

        $material = (string)$row['material'];
        $kgPerCount = (float)$row['kg_per_count'];

        if ($material === 'CEMENT_FULL') {
            $cementKgPerCount = $kgPerCount;
        }

        if ($material === 'SAND' && $row['gate_cm'] !== null) {
            $sandPoints[] = [
                'gate' => (float)$row['gate_cm'],
                'kg_per_count' => $kgPerCount
            ];
        }

        if ($material === 'STONE' && $row['gate_cm'] !== null) {
            $stonePoints[] = [
                'gate' => (float)$row['gate_cm'],
                'kg_per_count' => $kgPerCount
            ];
        }
    }

    if ($cementKgPerCount === null || $cementKgPerCount <= 0) {
        throw new RuntimeException('CEMENT_CALIBRATION_MISSING');
    }

    if (count($sandPoints) !== 3 || count($stonePoints) !== 3) {
        throw new RuntimeException('AGGREGATE_CALIBRATION_INCOMPLETE');
    }

    $cementKg  = (float)$mix['cement_kg'];
    $sandKg    = (float)$mix['sand_kg'];
    $graniteKg = (float)$mix['granite_kg'];
    $waterL    = (float)$mix['water_l'];

    /*
     * Workbook relationships.
     */
    $countsPerM3 =
        $cementKg / $cementKgPerCount;

    if ($countsPerM3 <= 0) {
        throw new RuntimeException('INVALID_COUNTS_PER_M3');
    }

    $m3PerMin =
        $conveyorSpeed
        * (1 / $cementKg)
        * $cementKgPerCount
        * 16;

    $sandTargetKgPerCount =
        $sandKg / $countsPerM3;

    $graniteTargetKgPerCount =
        $graniteKg / $countsPerM3;

    /*
     * Extrapolation outside 5–11 cm is intentional.
     */
    $sandGateCm =
        qbook_settings_trend_gate(
            $sandPoints,
            $sandTargetKgPerCount
        );

    $graniteGateCm =
        qbook_settings_trend_gate(
            $stonePoints,
            $graniteTargetKgPerCount
        );

    /*
     * Moisture correction.
     */
    $sandMoistureFraction =
        (float)$calibration['sand_moisture_pct'] / 100;

    $graniteMoistureFraction =
        (float)$calibration['stone_moisture_pct'] / 100;

    $sandMoistureL =
        $sandKg * $sandMoistureFraction;

    $graniteMoistureL =
        $graniteKg * $graniteMoistureFraction;

    $additionalWaterL =
        $waterL
        - $sandMoistureL
        - $graniteMoistureL;

    if ($additionalWaterL < 0) {
        throw new RuntimeException('MOISTURE_EXCEEDS_DESIGN_WATER');
    }

    $waterFlowLpm =
        $m3PerMin * $additionalWaterL;

    /*
     * Admixtures.
     */
    $stmt = $db->prepare(
        "SELECT
            id,
            name,
            dosage_cc_per_100kg,
            dilution_factor
         FROM qbook_mix_admixtures
         WHERE mix_design_id = ?
           AND is_active = 1
         ORDER BY sort_order, id"
    );

    $stmt->execute([$mixDesignId]);
    $admixtures = $stmt->fetchAll();

    $admixtureResults = [];

    foreach ($admixtures as $admix) {

        $dosageCcPer100Kg = (float)$admix['dosage_cc_per_100kg'];
        $dosageLitresPer100Kg = $dosageCcPer100Kg / 1000;

        $dilution =
            (float)$admix['dilution_factor'];

        $admixtureLPerM3 = ($cementKg / 100) * $dosageLitresPer100Kg;
        $pureFlowLpm = $admixtureLPerM3 * $m3PerMin;
        $flowLpm = $pureFlowLpm * $dilution;

        $admixtureResults[] = [
            'id' => (int)$admix['id'],
            'name' => $admix['name'],
            'dosage_cc_per_100kg' => $dosageCcPer100Kg,
            'dosage_l_per_100kg' => $dosageLitresPer100Kg,
            'cement_kg_per_m3' => $cementKg,
            'admixture_l_per_m3' => $admixtureLPerM3,
            'dilution_factor' => $dilution,
            'pure_flow_lpm' => $pureFlowLpm,
            'metered_flow_lpm' => $flowLpm,
            'flow_lpm' => $flowLpm
        ];
    }

    return [
        'mixer' => $mixer,

        'calibration' => [
            'id' => (int)$calibration['id'],
            'date' => $calibration['calibration_date'],
            'reviewed_at' => $calibration['reviewed_at']
        ],

        'mix_design' => [
            'id' => (int)$mix['id'],
            'name' => $mix['name'],
            'client_name' => $mix['client_name'],
            'project_name' => $mix['project_name'],
            'version_no' => (int)$mix['version_no'],
            'design_mode' => $mix['design_mode']
        ],

        'batch_volume_m3' => 1.0,

        'conveyor_speed' => $conveyorSpeed,

        'cement_kg' => $cementKg,
        'sand_kg' => $sandKg,
        'granite_kg' => $graniteKg,
        'design_water_l' => $waterL,

        'cement_kg_per_count' => $cementKgPerCount,
        'counts_per_m3' => $countsPerM3,
        'm3_per_min' => $m3PerMin,

        'sand_target_kg_per_count' =>
            $sandTargetKgPerCount,

        'granite_target_kg_per_count' =>
            $graniteTargetKgPerCount,

        'sand_gate_cm' => $sandGateCm,
        'granite_gate_cm' => $graniteGateCm,

        'sand_moisture_l' => $sandMoistureL,
        'granite_moisture_l' => $graniteMoistureL,

        'additional_water_l' => $additionalWaterL,
        'water_flow_lpm' => $waterFlowLpm,
        'sand_moisture_pct' => (float)$calibration['sand_moisture_pct'],
        'granite_moisture_pct' => (float)$calibration['stone_moisture_pct'],

        'admixtures' => $admixtureResults
    ];
}
