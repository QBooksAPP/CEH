<?php
declare(strict_types=1);

require_once __DIR__ . '/settings_engine.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR']);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json([
        'ok' => false,
        'error' => 'METHOD_NOT_ALLOWED'
    ], 405);
}

$input = json_decode(file_get_contents('php://input'), true);

if (!is_array($input)) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_JSON'
    ], 400);
}

$mixerId = (int)($input['mixer_id'] ?? 0);
$mixDesignId = (int)($input['mix_design_id'] ?? 0);
$conveyorSpeed = (float)($input['conveyor_speed'] ?? 0);

try {

    /*
     * Always recalculate on the server at the exact moment
     * Apply is pressed.
     *
     * We never trust calculated values sent back by the app.
     */
    $settings = qbook_calculate_settings(
        $mixerId,
        $mixDesignId,
        $conveyorSpeed
    );

    $db = qbook_db();
    $db->beginTransaction();

    /*
     * Save a permanent production snapshot.
     *
     * We deliberately store both:
     *   - references to mixer/calibration/mix
     *   - the mix version
     *   - a snapshot of mix identity
     *   - a snapshot of material quantities
     *
     * Therefore historical production settings remain accurate
     * even if the mix design is edited later.
     */
    $stmt = $db->prepare(
        "INSERT INTO qbook_production_settings
        (
            mixer_id,
            calibration_id,
            mix_design_id,
            mix_version_no,

            mix_name,
            client_name,
            project_name,

            cement_kg,
            sand_kg,
            granite_kg,
            design_water_l,

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
        VALUES
        (
            ?, ?, ?, ?,
            ?, ?, ?,
            ?, ?, ?, ?,
            ?, ?,
            ?, ?, ?,
            ?, ?,
            ?, ?,
            ?, ?,
            ?, ?
        )"
    );

    $stmt->execute([
        (int)$settings['mixer']['id'],
        (int)$settings['calibration']['id'],
        (int)$settings['mix_design']['id'],
        (int)$settings['mix_design']['version_no'],

        $settings['mix_design']['name'],
        $settings['mix_design']['client_name'],
        $settings['mix_design']['project_name'],

        $settings['cement_kg'],
        $settings['sand_kg'],
        $settings['granite_kg'],
        $settings['design_water_l'],

        (int)$user['id'],
        $settings['conveyor_speed'],

        $settings['cement_kg_per_count'],
        $settings['counts_per_m3'],
        $settings['m3_per_min'],

        $settings['sand_target_kg_per_count'],
        $settings['granite_target_kg_per_count'],

        $settings['sand_gate_cm'],
        $settings['granite_gate_cm'],

        $settings['sand_moisture_l'],
        $settings['granite_moisture_l'],

        $settings['additional_water_l'],
        $settings['water_flow_lpm']
    ]);

    $settingId = (int)$db->lastInsertId();

    /*
     * Save the exact admixture flow snapshot used at Apply time.
     */
    if (!empty($settings['admixtures'])) {

        $saveAdmix = $db->prepare(
            "INSERT INTO qbook_production_setting_admixtures
            (
                production_setting_id,
                mix_admixture_id,
                flow_lpm
            )
            VALUES (?, ?, ?)"
        );

        foreach ($settings['admixtures'] as $admix) {

            $saveAdmix->execute([
                $settingId,
                (int)$admix['id'],
                $admix['flow_lpm']
            ]);
        }
    }

    /*
     * Commit the production settings first.
     */
    $db->commit();

    /*
     * AUDIT LOG
     *
     * This records that the operator/admin actually pressed Apply.
     *
     * Audit failure will not break the production action because
     * qbook_audit() is fail-safe.
     */
    qbook_audit(
        $user,
        'SETTINGS_APPLIED',
        'PRODUCTION_SETTING',
        $settingId,
        [
            'mixer_id' =>
                (int)$settings['mixer']['id'],

            'mixer_code' =>
                $settings['mixer']['code'],

            'calibration_id' =>
                (int)$settings['calibration']['id'],

            'mix_design_id' =>
                (int)$settings['mix_design']['id'],

            'mix_version_no' =>
                (int)$settings['mix_design']['version_no'],

            'mix_name' =>
                $settings['mix_design']['name'],

            'client_name' =>
                $settings['mix_design']['client_name'],

            'project_name' =>
                $settings['mix_design']['project_name'],

            'cement_kg' =>
                (int)round($settings['cement_kg']),

            'sand_kg' =>
                (int)round($settings['sand_kg']),

            'granite_kg' =>
                (int)round($settings['granite_kg']),

            'water_l' =>
                (int)round($settings['design_water_l']),

            'conveyor_speed' =>
                (int)round($settings['conveyor_speed']),

            'sand_gate_cm' =>
                round($settings['sand_gate_cm'], 1),

            'granite_gate_cm' =>
                round($settings['granite_gate_cm'], 1),

            'water_flow_lpm' =>
                round($settings['water_flow_lpm'], 1)
        ]
    );

    /*
     * Clean operator-facing admixture response.
     */
    $admixtures = [];

    foreach ($settings['admixtures'] as $admix) {

        $admixtures[] = [
            'id' =>
                (int)$admix['id'],

            'name' =>
                $admix['name'],

            'dosage_l_per_100kg' => round((float)$admix['dosage_l_per_100kg'], 4),
            'cement_kg_per_m3' => round((float)$admix['cement_kg_per_m3'], 2),
            'admixture_l_per_m3' => round((float)$admix['admixture_l_per_m3'], 4),
            'dilution_factor' => round((float)$admix['dilution_factor'], 4),
            'pure_flow_lpm' => round((float)$admix['pure_flow_lpm'], 4),
            'metered_flow_lpm' => round((float)$admix['metered_flow_lpm'], 4),

            'flow_lpm' =>
                round((float)$admix['flow_lpm'], 1)
        ];
    }

    /*
     * Clean operator-facing response.
     */
    qbook_json([
        'ok' => true,

        'mode' => 'APPLIED',
        'saved' => true,

        'setting_id' =>
            $settingId,

        'mixer' => [
            'id' =>
                (int)$settings['mixer']['id'],

            'code' =>
                $settings['mixer']['code'],

            'name' =>
                $settings['mixer']['name'],

            'model' =>
                $settings['mixer']['model'],

            'truck_number' =>
                $settings['mixer']['truck_number']
        ],

        'calibration' =>
            $settings['calibration'],

        'mix_design' => [
            'id' =>
                (int)$settings['mix_design']['id'],

            'name' =>
                $settings['mix_design']['name'],

            'client_name' =>
                $settings['mix_design']['client_name'],

            'project_name' =>
                $settings['mix_design']['project_name'],

            'version_no' =>
                (int)$settings['mix_design']['version_no']
        ],

        /*
         * QBook production settings are always based on 1 m3.
         */
        'batch_volume_m3' =>
            1.00,

        /*
         * Display material quantities as whole numbers.
         */
        'mix' => [
            'cement_kg' =>
                (int)round($settings['cement_kg']),

            'sand_kg' =>
                (int)round($settings['sand_kg']),

            'granite_kg' =>
                (int)round($settings['granite_kg']),

            'water_l' =>
                (int)round($settings['design_water_l'])
        ],

        /*
         * Operator machine settings.
         */
        'settings' => [
            'sand_gate_cm' =>
                round($settings['sand_gate_cm'], 1),

            'granite_gate_cm' =>
                round($settings['granite_gate_cm'], 1),

            'conveyor_speed' =>
                (int)round($settings['conveyor_speed']),

            'production_rate_m3_per_min' =>
                round($settings['m3_per_min'], 2),

            'water_flow_lpm' =>
                round($settings['water_flow_lpm'], 1),

            'cement_kg_per_count' => round($settings['cement_kg_per_count'], 4),
            'counts_per_m3' => round($settings['counts_per_m3'], 4),
            'sand_target_kg_per_count' => round($settings['sand_target_kg_per_count'], 4),
            'granite_target_kg_per_count' => round($settings['granite_target_kg_per_count'], 4),
            'sand_moisture_pct' => round($settings['sand_moisture_pct'], 2),
            'granite_moisture_pct' => round($settings['granite_moisture_pct'], 2),
            'sand_moisture_l' => round($settings['sand_moisture_l'], 2),
            'granite_moisture_l' => round($settings['granite_moisture_l'], 2),
            'additional_water_l' => round($settings['additional_water_l'], 2),

            'admixtures' =>
                $admixtures
        ],

        'applied_by' => [
            'id' =>
                (int)$user['id'],

            'name' =>
                $user['full_name']
        ]
    ]);

} catch (RuntimeException $e) {

    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json([
        'ok' => false,
        'error' => $e->getMessage()
    ], 409);

} catch (Throwable $e) {

    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}
