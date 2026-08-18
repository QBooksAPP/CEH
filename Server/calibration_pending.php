<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$db = qbook_db();

$stmt = $db->query(
    "SELECT
        c.id,
        c.calibration_date,
        c.calibration_notes,
        c.status,
        c.revision_no,
        c.submitted_at,
        m.id AS mixer_id,
        m.code AS mixer_code,
        m.name AS mixer_name,
        u.full_name AS entered_by_name,
        COUNT(r.id) AS result_count
     FROM qbook_calibrations c
     JOIN qbook_mixers m ON m.id = c.mixer_id
     JOIN qbook_users u ON u.id = c.entered_by
     LEFT JOIN qbook_calibration_results r ON r.calibration_id = c.id
     WHERE c.status = 'SUBMITTED'
     GROUP BY
        c.id, c.calibration_date, c.calibration_notes, c.status,
        c.revision_no, c.submitted_at,
        m.id, m.code, m.name, u.full_name
     ORDER BY c.submitted_at ASC, c.id ASC"
);

$items = [];
foreach ($stmt->fetchAll() as $row) {
    $items[] = [
        'id' => (int)$row['id'],
        'calibration_date' => (string)$row['calibration_date'],
        'calibration_notes' => $row['calibration_notes'],
        'status' => (string)$row['status'],
        'revision_no' => (int)$row['revision_no'],
        'submitted_at' => $row['submitted_at'],
        'mixer_id' => (int)$row['mixer_id'],
        'mixer_code' => (string)$row['mixer_code'],
        'mixer_name' => (string)$row['mixer_name'],
        'entered_by_name' => (string)$row['entered_by_name'],
        'result_count' => (int)$row['result_count'],
    ];
}

qbook_json([
    'ok' => true,
    'calibrations' => $items,
]);
