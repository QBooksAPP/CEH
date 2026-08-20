<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$db = qbook_db();
$stmt = $db->prepare(
    "SELECT c.id, c.mixer_id, c.client_id, c.project_id,
            c.client_name_snapshot, c.project_name_snapshot, c.stone_size,
            c.calibration_date, c.calibration_notes,
            c.container_weight_kg, c.stone_moisture_pct,
            c.sand_moisture_pct, c.cement_safety_factor_pct,
            c.status, c.submitted_at, c.reviewed_at, c.rejection_reason,
            c.revision_no, c.created_at, c.updated_at,
            m.code AS mixer_code, m.name AS mixer_name
     FROM qbook_calibrations c
     JOIN qbook_mixers m ON m.id = c.mixer_id
     WHERE c.entered_by = ? AND c.archived_at IS NULL
       AND (c.project_id IS NULL OR EXISTS(
         SELECT 1 FROM qbook_projects p JOIN qbook_clients cl ON cl.id=p.client_id
         WHERE p.id=c.project_id AND p.is_active=1 AND p.archived_at IS NULL
           AND cl.is_active=1 AND cl.archived_at IS NULL))
     ORDER BY c.updated_at DESC, c.id DESC
     LIMIT 250"
);
$stmt->execute([(int)$user['id']]);
$rows = $stmt->fetchAll();

$trialStmt = $db->prepare(
    "SELECT material, gate_cm, trial_no, total_weight_kg, counts
     FROM qbook_calibration_trials
     WHERE calibration_id = ?
     ORDER BY material, gate_cm, trial_no"
);

$records = [];
foreach ($rows as $row) {
    $trialStmt->execute([(int)$row['id']]);
    $trials = [];
    foreach ($trialStmt->fetchAll() as $trial) {
        $trials[] = [
            'material' => $trial['material'],
            'gate_cm' => $trial['gate_cm'] !== null ? (float)$trial['gate_cm'] : null,
            'trial_no' => (int)$trial['trial_no'],
            'total_weight_kg' => $trial['total_weight_kg'] !== null ? (float)$trial['total_weight_kg'] : null,
            'counts' => $trial['counts'] !== null ? (float)$trial['counts'] : null
        ];
    }

    $records[] = [
        'calibration_id' => (int)$row['id'],
        'mixer' => [
            'id' => (int)$row['mixer_id'],
            'code' => $row['mixer_code'],
            'name' => $row['mixer_name']
        ],
        'client_id' => $row['client_id'] === null ? null : (int)$row['client_id'],
        'project_id' => $row['project_id'] === null ? null : (int)$row['project_id'],
        'client_name' => $row['client_name_snapshot'],
        'project_name' => $row['project_name_snapshot'],
        'stone_size' => $row['stone_size'],
        'calibration_date' => $row['calibration_date'],
        'calibration_notes' => $row['calibration_notes'],
        'container_weight_kg' => (float)$row['container_weight_kg'],
        'stone_moisture_pct' => (float)$row['stone_moisture_pct'],
        'sand_moisture_pct' => (float)$row['sand_moisture_pct'],
        'cement_safety_factor_pct' => (float)$row['cement_safety_factor_pct'],
        'status' => $row['status'],
        'submitted_at' => $row['submitted_at'],
        'reviewed_at' => $row['reviewed_at'],
        'rejection_reason' => $row['rejection_reason'],
        'revision_no' => (int)$row['revision_no'],
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at'],
        'trials' => $trials
    ];
}

qbook_json(['ok' => true, 'count' => count($records), 'calibrations' => $records]);
