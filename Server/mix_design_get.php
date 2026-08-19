<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/job_context.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json([
        'ok' => false,
        'error' => 'METHOD_NOT_ALLOWED'
    ], 405);
}

$mixDesignId = (int)($_GET['mix_design_id'] ?? 0);

if ($mixDesignId <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'MIX_DESIGN_REQUIRED'
    ], 400);
}

$db = qbook_db();

/*
 * Load mix design.
 */
$stmt = $db->prepare(
    "SELECT
        id,
        name,
        description,
        design_mode,
        client_id, project_id, stone_size, client_validation_status,
        client_name,
        project_name,
        batch_volume_m3,
        cement_kg,
        sand_kg,
        granite_kg,
        water_l,
        air_pct,
        cement_sg,
        sand_sg,
        granite_sg,
        is_active,
        version_no,
        created_at,
        updated_at
     FROM qbook_mix_designs
     WHERE id = ?
     LIMIT 1"
);

$stmt->execute([$mixDesignId]);
$mix = $stmt->fetch();

if (!$mix) {
    qbook_json([
        'ok' => false,
        'error' => 'MIX_DESIGN_NOT_FOUND'
    ], 404);
}

/*
 * Load all admixtures.
 *
 * ADMIN sees inactive admixtures as well so they can
 * be edited/reactivated from the management screen.
 */
$stmt = $db->prepare(
    "SELECT
        id,
        name,
        dosage_cc_per_100kg,
        dilution_factor,
        sort_order,
        is_active
     FROM qbook_mix_admixtures
     WHERE mix_design_id = ?
     ORDER BY sort_order, id"
);

$stmt->execute([$mixDesignId]);
$admixRows = $stmt->fetchAll();

$admixtures = [];

foreach ($admixRows as $admix) {

    $admixtures[] = [
        'id' => (int)$admix['id'],
        'name' => $admix['name'],

        'dosage_cc_per_100kg' =>
            round((float)$admix['dosage_cc_per_100kg'], 2),

        'dilution_factor' =>
            round((float)$admix['dilution_factor'], 2),

        'sort_order' =>
            (int)$admix['sort_order'],

        'is_active' =>
            (bool)$admix['is_active']
    ];
}

/*
 * Absolute-volume calculation for ADMIN reference.
 */
$cementKg  = (float)$mix['cement_kg'];
$sandKg    = (float)$mix['sand_kg'];
$graniteKg = (float)$mix['granite_kg'];
$waterL    = (float)$mix['water_l'];

$cementSg  = (float)$mix['cement_sg'];
$sandSg    = (float)$mix['sand_sg'];
$graniteSg = (float)$mix['granite_sg'];
$airPct    = (float)$mix['air_pct'];

$calculatedVolume =
    ($cementKg / ($cementSg * 1000))
    + ($sandKg / ($sandSg * 1000))
    + ($graniteKg / ($graniteSg * 1000))
    + ($waterL / 1000)
    + $airPct;
$deviation=qbook_absolute_volume_deviation($calculatedVolume);

qbook_json([
    'ok' => true,

    'mix_design' => [
        'id' => (int)$mix['id'],

        'name' => $mix['name'],
        'description' => $mix['description'],
        'design_mode' => $mix['design_mode'],
        'client_id'=>$mix['client_id']===null?null:(int)$mix['client_id'],
        'project_id'=>$mix['project_id']===null?null:(int)$mix['project_id'],
        'stone_size'=>$mix['stone_size'],
        'client_validation_status'=>$mix['client_validation_status'],

        'client_name' => $mix['client_name'],
        'project_name' => $mix['project_name'],

        /*
         * QBook production mixes are always based on 1 m3.
         */
        'batch_volume_m3' => 1.00,

        'cement_kg' =>
            round($cementKg, 2),

        'sand_kg' =>
            round($sandKg, 2),

        'granite_kg' =>
            round($graniteKg, 2),

        'water_l' =>
            round($waterL, 2),

        'air_pct' =>
            round($airPct, 4),

        'cement_sg' =>
            round($cementSg, 3),

        'sand_sg' =>
            round($sandSg, 3),

        'granite_sg' =>
            round($graniteSg, 3),

        'calculated_absolute_volume_m3' =>
            round($calculatedVolume, 4),
        'absolute_volume_deviation_m3'=>round($deviation['deviation_m3'],4),
        'absolute_volume_deviation_status'=>$deviation['deviation_status'],

        'is_active' =>
            (bool)$mix['is_active'],

        'version_no' =>
            (int)$mix['version_no'],

        'created_at' =>
            $mix['created_at'],

        'updated_at' =>
            $mix['updated_at'],

        'admixtures' =>
            $admixtures
    ]
]);
