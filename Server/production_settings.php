<?php
declare(strict_types=1);

/*
 * LEGACY / DEPRECATED ENDPOINT.
 *
 * Retained temporarily while production usage is verified. New clients must
 * use settings_preview.php and settings_apply.php, which share the canonical
 * calculation implementation in settings_engine.php.
 */

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR']);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$input = json_decode(file_get_contents('php://input'), true);

if (!is_array($input)) {
    qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
}

$mixerId = (int)($input['mixer_id'] ?? 0);
$mixDesignId = (int)($input['mix_design_id'] ?? 0);
$conveyorSpeed = (float)($input['conveyor_speed'] ?? 0);

if ($mixerId <= 0) {
    qbook_json(['ok' => false, 'error' => 'MIXER_REQUIRED'], 400);
}

if ($mixDesignId <= 0) {
    qbook_json(['ok' => false, 'error' => 'MIX_DESIGN_REQUIRED'], 400);
}

if ($conveyorSpeed <= 0) {
    qbook_json(['ok' => false, 'error' => 'INVALID_CONVEYOR_SPEED'], 400);
}

$db = qbook_db();

/*
 * Load selected active mixer.
 */
$stmt = $db->prepare(
    "SELECT id, code, name, model, truck_number
     FROM qbook_mixers
     WHERE id = ?
       AND is_active = 1
     LIMIT 1"
);

$stmt->execute([$mixerId]);
$mixer = $stmt->fetch();

if (!$mixer) {
    qbook_json(['ok' => false, 'error' => 'MIXER_NOT_FOUND'], 404);
}

/*
 * Load active mix design.
 */
$stmt = $db->prepare(
    "SELECT
        id,
        name,
        design_mode,
        client_name,
        project_name,
        cement_kg,
        sand_kg,
        granite_kg,
        water_l,
        batch_volume_m3
     FROM qbook_mix_designs
     WHERE id = ?
       AND is_active = 1
     LIMIT 1"
);

$stmt->execute([$mixDesignId]);
$mix = $stmt->fetch();

if (!$mix) {
    qbook_json(['ok' => false, 'error' => 'MIX_DESIGN_NOT_FOUND'], 404);
}

/*
 * QBook production batch volume is always 1.00 m3.
 */
if (abs((float)$mix['batch_volume_m3'] - 1.0) > 0.0001) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_BATCH_VOLUME'
    ], 409);
}

/*
 * Find the latest APPROVED calibration for this mixer.
 */
$stmt = $db->prepare(
    "SELECT
        id,
        mixer_id,
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
    qbook_json([
        'ok' => false,
        'error' => 'NO_APPROVED_CALIBRATION'
    ], 409);
}

/*
 * Load the approved calibration values.
 */
$stmt = $db->prepare(
    "SELECT material, gate_cm, kg_per_count
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
    qbook_json([
        'ok' => false,
        'error' => 'CEMENT_CALIBRATION_MISSING'
    ], 409);
}

if (count($sandPoints) !== 3 || count($stonePoints) !== 3) {
    qbook_json([
        'ok' => false,
        'error' => 'AGGREGATE_CALIBRATION_INCOMPLETE'
    ], 409);
}

/*
 * Linear TREND equivalent:
 *
 * Excel is effectively calculating:
 * gate = intercept + slope * target_kg_per_count
 *
 * using the 5 / 8 / 11 cm calibration points.
 */
function qbook_trend_gate(array $points, float $target): float
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

$cementKg = (float)$mix['cement_kg'];
$sandKg = (float)$mix['sand_kg'];
$graniteKg = (float)$mix['granite_kg'];
$designWaterL = (float)$mix['water_l'];

/*
 * Workbook relationships.
 */
$countsPerM3 = $cementKg / $cementKgPerCount;

if ($countsPerM3 <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_COUNTS_PER_M3'
    ], 409);
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

try {
    $sandGateCm =
        qbook_trend_gate($sandPoints, $sandTargetKgPerCount);

    $graniteGateCm =
        qbook_trend_gate($stonePoints, $graniteTargetKgPerCount);
} catch (RuntimeException $e) {
    qbook_json([
        'ok' => false,
        'error' => $e->getMessage()
    ], 409);
}

/*
 * Moisture correction.
 */
$sandMoistureFraction =
    (float)$calibration['sand_moisture_pct'] / 100;

$stoneMoistureFraction =
    (float)$calibration['stone_moisture_pct'] / 100;

$sandMoistureL =
    $sandKg * $sandMoistureFraction;

$graniteMoistureL =
    $graniteKg * $stoneMoistureFraction;

$additionalWaterL =
    $designWaterL
    - $sandMoistureL
    - $graniteMoistureL;

if ($additionalWaterL < 0) {
    qbook_json([
        'ok' => false,
        'error' => 'MOISTURE_EXCEEDS_DESIGN_WATER'
    ], 409);
}

$waterFlowLpm =
    $m3PerMin * $additionalWaterL;

/*
 * Load active admixtures for this mix.
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

    $dosage =
        (float)$admix['dosage_cc_per_100kg'];

    $dilution =
        (float)$admix['dilution_factor'];

    /*
     * Workbook admixture relationship.
     * Fly ash intentionally excluded from QBook Nigeria.
     */
    $flowLpm =
        $dosage
        * $conveyorSpeed
        * $cementKgPerCount
        / 6250
        * $dilution;

    $admixtureResults[] = [
        'id' => (int)$admix['id'],
        'name' => $admix['name'],
        'flow_lpm' => round($flowLpm, 2)
    ];
}

/*
 * Save production/settings snapshot.
 */
try {

    $db->beginTransaction();

    $stmt = $db->prepare(
        "INSERT INTO qbook_production_settings
        (
            mixer_id,
            calibration_id,
            mix_design_id,
            operator_id,
            conveyor_speed,
            cement_kg_per_count,
            counts_per_m3,
            m3_per_min,
            sand_target_kg_per_count,
            granite_target_kg_per_count,
            sand_gate_cm,
            granite_gate_cm,
            sand_moisture_l,
            granite_moisture_l,
            water_additional_l,
            water_flow_lpm
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    );

    $stmt->execute([
        $mixerId,
        (int)$calibration['id'],
        $mixDesignId,
        (int)$user['id'],
        $conveyorSpeed,
        $cementKgPerCount,
        $countsPerM3,
        $m3PerMin,
        $sandTargetKgPerCount,
        $graniteTargetKgPerCount,
        $sandGateCm,
        $graniteGateCm,
        $sandMoistureL,
        $graniteMoistureL,
        $additionalWaterL,
        $waterFlowLpm
    ]);

    $settingId =
        (int)$db->lastInsertId();

    if ($admixtureResults) {

        $saveAdmix = $db->prepare(
            "INSERT INTO qbook_production_setting_admixtures
            (
                production_setting_id,
                mix_admixture_id,
                flow_lpm
            )
            VALUES (?, ?, ?)"
        );

        foreach ($admixtureResults as $index => $result) {

            $admix = $admixtures[$index];

            $dosage =
                (float)$admix['dosage_cc_per_100kg'];

            $dilution =
                (float)$admix['dilution_factor'];

            $flowLpm =
                $dosage
                * $conveyorSpeed
                * $cementKgPerCount
                / 6250
                * $dilution;

            $saveAdmix->execute([
                $settingId,
                (int)$admix['id'],
                $flowLpm
            ]);
        }
    }

    $db->commit();

} catch (Throwable $e) {

    if ($db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}

/*
 * Operator-facing result.
 * Full precision remains stored in MySQL.
 */
qbook_json([
    'ok' => true,

    'setting_id' => $settingId,

    'mixer' => [
        'id' => (int)$mixer['id'],
        'code' => $mixer['code'],
        'name' => $mixer['name'],
        'model' => $mixer['model']
    ],

    'calibration_id' =>
        (int)$calibration['id'],

    'mix_design' => [
        'id' => (int)$mix['id'],
        'name' => $mix['name'],
        'client_name' => $mix['client_name'],
        'project_name' => $mix['project_name']
    ],

    'batch_volume_m3' => 1.00,

    'conveyor_speed' =>
        round($conveyorSpeed, 2),

    'cement_kg_per_count' =>
        round($cementKgPerCount, 2),

    'counts_per_m3' =>
        round($countsPerM3, 2),

    'production_rate_m3_per_min' =>
        round($m3PerMin, 2),

    'sand' => [
        'kg_per_m3' => round($sandKg, 2),
        'target_kg_per_count' =>
            round($sandTargetKgPerCount, 2),
        'gate_cm' =>
            round($sandGateCm, 2)
    ],

    'granite' => [
        'kg_per_m3' => round($graniteKg, 2),
        'target_kg_per_count' =>
            round($graniteTargetKgPerCount, 2),
        'gate_cm' =>
            round($graniteGateCm, 2)
    ],

    'water' => [
        'design_l_per_m3' =>
            round($designWaterL, 2),

        'sand_moisture_l' =>
            round($sandMoistureL, 2),

        'granite_moisture_l' =>
            round($graniteMoistureL, 2),

        'additional_water_l_per_m3' =>
            round($additionalWaterL, 2),

        'flow_lpm' =>
            round($waterFlowLpm, 2)
    ],

    'admixtures' =>
        $admixtureResults
]);
