<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json([
        'ok' => false,
        'error' => 'METHOD_NOT_ALLOWED'
    ], 405);
}

$db = qbook_db();

$isAdmin = ($user['role'] === 'ADMIN');

$sql = "
    SELECT
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
        air_pct,
        cement_sg,
        sand_sg,
        granite_sg,
        batch_volume_m3,
        is_active,
        version_no
    FROM qbook_mix_designs
";

if (!$isAdmin) {
    $sql .= " WHERE is_active = 1";
}

$sql .= "
    ORDER BY
        client_name IS NULL,
        client_name,
        project_name,
        name,
        id
";

$stmt = $db->prepare($sql);
$stmt->execute();

$rows = $stmt->fetchAll();

$mixes = [];

foreach ($rows as $row) {

    /*
     * Load admixtures belonging to this mix.
     */
    $admixStmt = $db->prepare(
        "SELECT
            id,
            name,
            dosage_cc_per_100kg,
            dilution_factor,
            is_active
         FROM qbook_mix_admixtures
         WHERE mix_design_id = ?
         ORDER BY sort_order, id"
    );

    $admixStmt->execute([(int)$row['id']]);
    $admixRows = $admixStmt->fetchAll();

    $admixtures = [];

    foreach ($admixRows as $admix) {

        if (!$isAdmin && !(bool)$admix['is_active']) {
            continue;
        }

        $admixtures[] = [
            'id' => (int)$admix['id'],
            'name' => $admix['name'],
            'dosage_cc_per_100kg' =>
                round((float)$admix['dosage_cc_per_100kg'], 2),
            'dilution_factor' =>
                round((float)$admix['dilution_factor'], 2),
            'is_active' =>
                (bool)$admix['is_active']
        ];
    }

    $mixes[] = [
        'id' => (int)$row['id'],
        'name' => $row['name'],
        'description' => $row['description'],
        'design_mode' => $row['design_mode'],
        'client_name' => $row['client_name'],
        'project_name' => $row['project_name'],

        'batch_volume_m3' => 1.00,

        'cement_kg' =>
            round((float)$row['cement_kg'], 2),

        'sand_kg' =>
            round((float)$row['sand_kg'], 2),

        'granite_kg' =>
            round((float)$row['granite_kg'], 2),

        'water_l' =>
            round((float)$row['water_l'], 2),

        'air_pct' =>
            round((float)$row['air_pct'], 4),

        'cement_sg' =>
            round((float)$row['cement_sg'], 3),

        'sand_sg' =>
            round((float)$row['sand_sg'], 3),

        'granite_sg' =>
            round((float)$row['granite_sg'], 3),

        'is_active' =>
            (bool)$row['is_active'],

        'version_no' =>
            (int)$row['version_no'],

        'admixtures' =>
            $admixtures
    ];
}

qbook_json([
    'ok' => true,
    'mix_designs' => $mixes
]);