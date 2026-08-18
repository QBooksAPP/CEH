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
$calibrationId = (int)($input['calibration_id'] ?? 0);

if ($calibrationId > 0 && $user['role'] !== 'ADMIN') {
    qbook_json(['ok' => false, 'error' => 'CALIBRATION_OVERRIDE_FORBIDDEN'], 403);
}

try {

    $settings = qbook_calculate_settings(
        $mixerId,
        $mixDesignId,
        $conveyorSpeed,
        $calibrationId
    );

    $admixtures = [];

    foreach ($settings['admixtures'] as $admix) {
        $admixtures[] = [
            'id' => (int)$admix['id'],
            'name' => $admix['name'],
            'dosage_l_per_100kg' => round((float)$admix['dosage_l_per_100kg'], 4),
            'cement_kg_per_m3' => round((float)$admix['cement_kg_per_m3'], 2),
            'admixture_l_per_m3' => round((float)$admix['admixture_l_per_m3'], 4),
            'dilution_factor' => round((float)$admix['dilution_factor'], 4),
            'pure_flow_lpm' => round((float)$admix['pure_flow_lpm'], 4),
            'metered_flow_lpm' => round((float)$admix['metered_flow_lpm'], 4),
            'flow_lpm' => round((float)$admix['flow_lpm'], 4)
        ];
    }

    qbook_json([
        'ok' => true,
        'mode' => 'PREVIEW',
        'saved' => false,

        'mixer' => [
            'id' => (int)$settings['mixer']['id'],
            'code' => $settings['mixer']['code'],
            'name' => $settings['mixer']['name'],
            'model' => $settings['mixer']['model'],
            'truck_number' => $settings['mixer']['truck_number']
        ],

        'calibration' => $settings['calibration'],

        'mix_design' => $settings['mix_design'],

        'batch_volume_m3' => 1.00,

        'mix' => [
            'cement_kg' => (int)round($settings['cement_kg']),
            'sand_kg' => (int)round($settings['sand_kg']),
            'granite_kg' => (int)round($settings['granite_kg']),
            'water_l' => (int)round($settings['design_water_l'])
        ],

        'settings' => [
            'sand_gate_cm' => round($settings['sand_gate_cm'], 1),
            'granite_gate_cm' => round($settings['granite_gate_cm'], 1),
            'conveyor_speed' => (int)round($settings['conveyor_speed']),
            'production_rate_m3_per_min' => round($settings['m3_per_min'], 2),
            'water_flow_lpm' => round($settings['water_flow_lpm'], 1),
            'cement_kg_per_count' => round($settings['cement_kg_per_count'], 4),
            'counts_per_m3' => round($settings['counts_per_m3'], 4),
            'sand_target_kg_per_count' => round($settings['sand_target_kg_per_count'], 4),
            'granite_target_kg_per_count' => round($settings['granite_target_kg_per_count'], 4),
            'sand_moisture_pct' => round($settings['sand_moisture_pct'], 2),
            'granite_moisture_pct' => round($settings['granite_moisture_pct'], 2),
            'sand_moisture_l' => round($settings['sand_moisture_l'], 2),
            'granite_moisture_l' => round($settings['granite_moisture_l'], 2),
            'additional_water_l' => round($settings['additional_water_l'], 2),
            'admixtures' => $admixtures
        ]
    ]);

} catch (RuntimeException $e) {

    $error = $e->getMessage();

    $status = in_array($error, [
        'MIXER_REQUIRED',
        'MIX_DESIGN_REQUIRED',
        'INVALID_CONVEYOR_SPEED'
    ], true) ? 400 : 409;

    qbook_json([
        'ok' => false,
        'error' => $error
    ], $status);

} catch (Throwable $e) {

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}
