<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$db = qbook_db();

$stmt = $db->query(
    "SELECT
        c.id,
        c.calibration_date,
        c.calibration_notes,
        c.container_weight_kg,
        c.stone_moisture_pct,
        c.sand_moisture_pct,
        c.cement_safety_factor_pct,
        c.revision_no,
        c.reviewed_at,
        m.id AS mixer_id,
        m.code AS mixer_code,
        m.name AS mixer_name,
        entrant.full_name AS entered_by_name,
        reviewer.full_name AS reviewed_by_name
     FROM qbook_calibrations c
     JOIN qbook_mixers m ON m.id = c.mixer_id
     JOIN qbook_users entrant ON entrant.id = c.entered_by
     LEFT JOIN qbook_users reviewer ON reviewer.id = c.reviewed_by
     WHERE c.status = 'APPROVED'
     ORDER BY m.code ASC, c.reviewed_at DESC, c.id DESC"
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
foreach ($stmt->fetchAll() as $c) {
    $id = (int)$c['id'];
    $resultStmt->execute([$id]);

    $results = array_map(static function (array $r): array {
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
    }, $resultStmt->fetchAll());

    $items[] = [
        'id' => $id,
        'calibration_date' => (string)$c['calibration_date'],
        'calibration_notes' => $c['calibration_notes'],
        'container_weight_kg' => (float)$c['container_weight_kg'],
        'stone_moisture_pct' => (float)$c['stone_moisture_pct'],
        'sand_moisture_pct' => (float)$c['sand_moisture_pct'],
        'cement_safety_factor_pct' => (float)$c['cement_safety_factor_pct'],
        'revision_no' => (int)$c['revision_no'],
        'reviewed_at' => $c['reviewed_at'],
        'mixer_id' => (int)$c['mixer_id'],
        'mixer_code' => (string)$c['mixer_code'],
        'mixer_name' => (string)$c['mixer_name'],
        'entered_by_name' => (string)$c['entered_by_name'],
        'reviewed_by_name' => $c['reviewed_by_name'],
        'results' => $results,
    ];
}

qbook_json(['ok' => true, 'calibrations' => $items]);
