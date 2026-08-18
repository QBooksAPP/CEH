<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/calibration_math.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$db = qbook_db();

/*
 * Important repair step:
 * any SUBMITTED calibration may have been calculated by the old formula.
 * Recalculate it from raw trials before returning it for Admin review.
 */
$idStmt = $db->query(
    "SELECT id
     FROM qbook_calibrations
     WHERE status = 'SUBMITTED'
     ORDER BY id"
);

foreach ($idStmt->fetchAll() as $row) {
    qbook_recalculate_calibration_results($db, (int)$row['id']);
}

$stmt = $db->query(
    "SELECT
        c.id,
        c.calibration_date,
        c.calibration_notes,
        c.container_weight_kg,
        c.stone_moisture_pct,
        c.sand_moisture_pct,
        c.cement_safety_factor_pct,
        c.status,
        c.revision_no,
        c.submitted_at,
        c.reviewed_at,
        c.rejection_reason,
        m.id AS mixer_id,
        m.code AS mixer_code,
        m.name AS mixer_name,
        entrant.full_name AS entered_by_name,
        reviewer.full_name AS reviewed_by_name
     FROM qbook_calibrations c
     JOIN qbook_mixers m ON m.id = c.mixer_id
     JOIN qbook_users entrant ON entrant.id = c.entered_by
     LEFT JOIN qbook_users reviewer ON reviewer.id = c.reviewed_by
     WHERE c.status IN ('SUBMITTED', 'APPROVED')
     ORDER BY
        CASE WHEN c.status = 'SUBMITTED' THEN 0 ELSE 1 END,
        COALESCE(c.submitted_at, c.reviewed_at) DESC,
        c.id DESC"
);

$calibrations = $stmt->fetchAll();

$trialStmt = $db->prepare(
    "SELECT material, gate_cm, trial_no, total_weight_kg, counts
     FROM qbook_calibration_trials
     WHERE calibration_id = ?
     ORDER BY
        CASE material
          WHEN 'CEMENT_FULL' THEN 1
          WHEN 'CEMENT_HALF' THEN 2
          WHEN 'STONE' THEN 3
          WHEN 'SAND' THEN 4
          ELSE 9
        END,
        gate_cm,
        trial_no"
);

$resultStmt = $db->prepare(
    "SELECT material, gate_cm, avg_total_weight_kg, avg_counts,
            moisture_pct, net_dry_weight_kg, kg_per_count, calculated_at
     FROM qbook_calibration_results
     WHERE calibration_id = ?
     ORDER BY
        CASE material
          WHEN 'CEMENT_FULL' THEN 1
          WHEN 'CEMENT_HALF' THEN 2
          WHEN 'STONE' THEN 3
          WHEN 'SAND' THEN 4
          ELSE 9
        END,
        gate_cm"
);

$items = [];

foreach ($calibrations as $c) {
    $id = (int)$c['id'];

    $trialStmt->execute([$id]);
    $trials = $trialStmt->fetchAll();

    $resultStmt->execute([$id]);
    $results = $resultStmt->fetchAll();

    $items[] = [
        'id' => $id,
        'calibration_date' => (string)$c['calibration_date'],
        'calibration_notes' => $c['calibration_notes'],
        'container_weight_kg' => (float)$c['container_weight_kg'],
        'stone_moisture_pct' => (float)$c['stone_moisture_pct'],
        'sand_moisture_pct' => (float)$c['sand_moisture_pct'],
        'cement_safety_factor_pct' => (float)$c['cement_safety_factor_pct'],
        'status' => (string)$c['status'],
        'revision_no' => (int)$c['revision_no'],
        'submitted_at' => $c['submitted_at'],
        'reviewed_at' => $c['reviewed_at'],
        'rejection_reason' => $c['rejection_reason'],
        'mixer_id' => (int)$c['mixer_id'],
        'mixer_code' => (string)$c['mixer_code'],
        'mixer_name' => (string)$c['mixer_name'],
        'entered_by_name' => (string)$c['entered_by_name'],
        'reviewed_by_name' => $c['reviewed_by_name'],
        'trials' => array_map(static function (array $t): array {
            return [
                'material' => (string)$t['material'],
                'gate_cm' => $t['gate_cm'] === null ? null : (float)$t['gate_cm'],
                'trial_no' => (int)$t['trial_no'],
                'total_weight_kg' => $t['total_weight_kg'] === null
                    ? null : (float)$t['total_weight_kg'],
                'counts' => $t['counts'] === null ? null : (float)$t['counts'],
            ];
        }, $trials),
        'results' => array_map(static function (array $r): array {
            return [
                'material' => (string)$r['material'],
                'gate_cm' => $r['gate_cm'] === null ? null : (float)$r['gate_cm'],
                'avg_total_weight_kg' => $r['avg_total_weight_kg'] === null
                    ? null : (float)$r['avg_total_weight_kg'],
                'avg_counts' => $r['avg_counts'] === null
                    ? null : (float)$r['avg_counts'],
                'moisture_pct' => (float)$r['moisture_pct'],
                'net_dry_weight_kg' => $r['net_dry_weight_kg'] === null
                    ? null : (float)$r['net_dry_weight_kg'],
                'kg_per_count' => $r['kg_per_count'] === null
                    ? null : (float)$r['kg_per_count'],
                'calculated_at' => $r['calculated_at'],
            ];
        }, $results),
    ];
}

qbook_json([
    'ok' => true,
    'calibrations' => $items,
]);
