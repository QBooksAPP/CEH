<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/job_context.php';

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
$clientId = (int)($_GET['client_id'] ?? 0);
$projectId = (int)($_GET['project_id'] ?? 0);
$lifecycle = strtoupper((string)($_GET['status'] ?? ($isAdmin ? 'ALL' : 'ACTIVE')));
if (!in_array($lifecycle, ['ACTIVE','ARCHIVED','ALL'], true)) {
    qbook_json(['ok'=>false,'error'=>'INVALID_LIFECYCLE_FILTER'],422);
}

$sql = "
    SELECT
        id,
        name,
        description,
        design_mode,
        client_id, project_id, stone_size, client_validation_status,
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
        archived_at,
        version_no
    FROM qbook_mix_designs
";

$conditions = [];
$params = [];
if (!$isAdmin) {
    $conditions[] = "is_active = 1
               AND client_id IS NOT NULL
               AND project_id IS NOT NULL
               AND stone_size IS NOT NULL
               AND (design_mode = 'CALCULATED' OR client_validation_status = 'VALIDATED')
               AND EXISTS(SELECT 1 FROM qbook_projects p JOIN qbook_clients c ON c.id=p.client_id
                 WHERE p.id=qbook_mix_designs.project_id AND p.is_active=1 AND p.archived_at IS NULL
                   AND c.is_active=1 AND c.archived_at IS NULL)";
}
if ($lifecycle === 'ACTIVE') $conditions[] = 'is_active=1 AND archived_at IS NULL';
if ($lifecycle === 'ARCHIVED') $conditions[] = '(is_active=0 OR archived_at IS NOT NULL)';
if ($clientId > 0) { $conditions[] = 'client_id = ?'; $params[] = $clientId; }
if ($projectId > 0) { $conditions[] = 'project_id = ?'; $params[] = $projectId; }
if ($conditions !== []) $sql .= ' WHERE ' . implode(' AND ', $conditions);

$sql .= "
    ORDER BY
        client_name IS NULL,
        client_name,
        project_name,
        name,
        id
";

$stmt = $db->prepare($sql);
$stmt->execute($params);

$rows = $stmt->fetchAll();

$mixes = [];

foreach ($rows as $row) {
    $absoluteVolume=(float)$row['cement_kg']/((float)$row['cement_sg']*1000)+(float)$row['sand_kg']/((float)$row['sand_sg']*1000)+(float)$row['granite_kg']/((float)$row['granite_sg']*1000)+(float)$row['water_l']/1000+(float)$row['air_pct'];
    $deviation=qbook_absolute_volume_deviation($absoluteVolume);

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
        'client_id'=>$row['client_id']===null?null:(int)$row['client_id'],
        'project_id'=>$row['project_id']===null?null:(int)$row['project_id'],
        'stone_size'=>$row['stone_size'],
        'client_validation_status'=>$row['client_validation_status'],
        'archived_at'=>$row['archived_at'],
        'client_name' => $row['client_name'],
        'project_name' => $row['project_name'],

        'batch_volume_m3' => 1.00,
        'calculated_absolute_volume_m3'=>round($absoluteVolume,4),
        'absolute_volume_deviation_m3'=>round($deviation['deviation_m3'],4),
        'absolute_volume_deviation_status'=>$deviation['deviation_status'],

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
