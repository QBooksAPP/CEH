<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/calibration_math.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR']);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$input = json_decode(file_get_contents('php://input'), true);

if (!is_array($input)) {
    qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
}

$calibrationId = (int)($input['calibration_id'] ?? 0);

if ($calibrationId <= 0) {
    qbook_json(['ok' => false, 'error' => 'CALIBRATION_REQUIRED'], 400);
}

$db = qbook_db();
$stmt = $db->prepare(
    "SELECT id, entered_by, status
     FROM qbook_calibrations
     WHERE id = ?
     LIMIT 1"
);
$stmt->execute([$calibrationId]);
$calibration = $stmt->fetch();

if (!$calibration) {
    qbook_json(['ok' => false, 'error' => 'CALIBRATION_NOT_FOUND'], 404);
}

$isAdmin = $user['role'] === 'ADMIN';

if (!$isAdmin && (int)$calibration['entered_by'] !== (int)$user['id']) {
    qbook_json(['ok' => false, 'error' => 'FORBIDDEN'], 403);
}

if ($calibration['status'] !== 'DRAFT') {
    qbook_json(['ok' => false, 'error' => 'CALIBRATION_LOCKED'], 409);
}

try {
    $db->beginTransaction();
    qbook_recalculate_calibration_results($db, $calibrationId);
    $db->commit();

    $stmt = $db->prepare(
        "SELECT
            r.material,
            r.gate_cm,
            r.avg_total_weight_kg,
            r.avg_counts,
            r.moisture_pct,
            r.net_dry_weight_kg,
            r.kg_per_count,
            COUNT(t.trial_no) AS trial_count
         FROM qbook_calibration_results r
         LEFT JOIN qbook_calibration_trials t
           ON t.calibration_id = r.calibration_id
          AND t.material = r.material
          AND (t.gate_cm = r.gate_cm OR (t.gate_cm IS NULL AND r.gate_cm IS NULL))
         WHERE r.calibration_id = ?
         GROUP BY
            r.material, r.gate_cm, r.avg_total_weight_kg, r.avg_counts,
            r.moisture_pct, r.net_dry_weight_kg, r.kg_per_count
         ORDER BY r.material, r.gate_cm"
    );
    $stmt->execute([$calibrationId]);

    $results = [];
    foreach ($stmt->fetchAll() as $row) {
        $results[] = [
            'material' => (string)$row['material'],
            'gate_cm' => $row['gate_cm'] === null
                ? null
                : round((float)$row['gate_cm'], 1),
            'trial_count' => (int)$row['trial_count'],
            'avg_total_weight_kg' => round((float)$row['avg_total_weight_kg'], 2),
            'avg_counts' => round((float)$row['avg_counts'], 2),
            'moisture_pct' => round((float)$row['moisture_pct'], 2),
            'net_dry_weight_kg' => round((float)$row['net_dry_weight_kg'], 2),
            'kg_per_count' => round((float)$row['kg_per_count'], 6),
        ];
    }

    qbook_json([
        'ok' => true,
        'calibration_id' => $calibrationId,
        'status' => 'DRAFT',
        'results' => $results,
    ]);
} catch (RuntimeException $e) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json(['ok' => false, 'error' => $e->getMessage()], 400);
} catch (Throwable $e) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json(['ok' => false, 'error' => 'SERVER_ERROR'], 500);
}
