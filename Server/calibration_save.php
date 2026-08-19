<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/calibration_math.php';
require_once __DIR__ . '/job_context.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR']);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) {
    qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
}

$db = qbook_db();

$id = (int)($input['calibration_id'] ?? 0);
$clientId = (int)($input['client_id'] ?? 0);
$projectId = (int)($input['project_id'] ?? 0);
$stoneSize = qbook_stone_size($input['stone_size'] ?? '');
$mixerCode = trim((string)($input['mixer_code'] ?? ''));
$date = trim((string)($input['calibration_date'] ?? ''));
$notes = trim((string)($input['calibration_notes'] ?? ''));
$container = (float)($input['container_weight_kg'] ?? 0);
$stoneMoisture = (float)($input['stone_moisture_pct'] ?? 0);
$sandMoisture = (float)($input['sand_moisture_pct'] ?? 0);
$cementSafety = $user['role'] === 'ADMIN'
    ? (float)($input['cement_safety_factor_pct'] ?? 2.0)
    : 2.0;
$trials = $input['trials'] ?? [];

if ($mixerCode === '' || $date === '') {
    qbook_json(['ok' => false, 'error' => 'MIXER_AND_DATE_REQUIRED'], 422);
}
if (!is_array($trials)) {
    qbook_json(['ok' => false, 'error' => 'TRIALS_INVALID'], 422);
}
if ($container < 0 || $stoneMoisture < 0 || $sandMoisture < 0 || $cementSafety < 0) {
    qbook_json(['ok' => false, 'error' => 'NEGATIVE_CALIBRATION_VALUE'], 422);
}
if ($stoneMoisture > 10 || $sandMoisture > 10) {
    qbook_json(['ok' => false, 'error' => 'MOISTURE_MUST_BE_0_TO_10_PERCENT'], 422);
}

$stmt = $db->prepare(
    "SELECT id FROM qbook_mixers WHERE code = ? AND is_active = 1 LIMIT 1"
);
$stmt->execute([$mixerCode]);
$mixer = $stmt->fetch();
if (!$mixer) {
    qbook_json(['ok' => false, 'error' => 'MIXER_NOT_FOUND'], 404);
}
$mixerId = (int)$mixer['id'];
$context = qbook_active_job_context($db, $clientId, $projectId);

try {
    $db->beginTransaction();

    if ($id > 0) {
        $stmt = $db->prepare(
            "SELECT entered_by, status
             FROM qbook_calibrations
             WHERE id = ?
             FOR UPDATE"
        );
        $stmt->execute([$id]);
        $existing = $stmt->fetch();

        if (!$existing) {
            throw new RuntimeException('CALIBRATION_NOT_FOUND');
        }

        if ($user['role'] !== 'ADMIN' &&
            (int)$existing['entered_by'] !== (int)$user['id']) {
            throw new RuntimeException('FORBIDDEN');
        }

        if (!in_array((string)$existing['status'], ['DRAFT', 'REJECTED'], true)) {
            throw new RuntimeException('CALIBRATION_LOCKED');
        }

        $stmt = $db->prepare(
            "UPDATE qbook_calibrations
             SET mixer_id=?, client_id=?, project_id=?, client_name_snapshot=?,
                 project_name_snapshot=?, stone_size=?, calibration_date=?, calibration_notes=?,
                 container_weight_kg=?, stone_moisture_pct=?, sand_moisture_pct=?,
                 cement_safety_factor_pct=?, status='DRAFT',
                 submitted_at=NULL, reviewed_by=NULL, reviewed_at=NULL,
                 rejection_reason=NULL,
                 revision_no=revision_no + ?
             WHERE id=?"
        );
        $stmt->execute([
            $mixerId, $clientId, $projectId, $context['client_name'],
            $context['project_name'], $stoneSize, $date, $notes, $container, $stoneMoisture,
            $sandMoisture, $cementSafety,
            (string)$existing['status'] === 'REJECTED' ? 1 : 0,
            $id
        ]);
    } else {
        $stmt = $db->prepare(
            "INSERT INTO qbook_calibrations
             (mixer_id, client_id, project_id, client_name_snapshot,
              project_name_snapshot, stone_size, calibration_date, calibration_notes, container_weight_kg,
              stone_moisture_pct, sand_moisture_pct, cement_safety_factor_pct,
              status, entered_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'DRAFT', ?)"
        );
        $stmt->execute([
            $mixerId, $clientId, $projectId, $context['client_name'],
            $context['project_name'], $stoneSize, $date, $notes, $container, $stoneMoisture,
            $sandMoisture, $cementSafety, (int)$user['id']
        ]);
        $id = (int)$db->lastInsertId();
    }

    $db->prepare("DELETE FROM qbook_calibration_trials WHERE calibration_id=?")
       ->execute([$id]);

    $insert = $db->prepare(
        "INSERT INTO qbook_calibration_trials
         (calibration_id, material, gate_cm, trial_no, total_weight_kg, counts)
         VALUES (?, ?, ?, ?, ?, ?)"
    );

    foreach ($trials as $trial) {
        if (!is_array($trial)) continue;

        $material = strtoupper(trim((string)($trial['material'] ?? '')));
        if (!in_array($material, ['CEMENT_FULL','CEMENT_HALF','STONE','SAND'], true)) {
            continue;
        }

        $trialNo = (int)($trial['trial_no'] ?? 0);
        if ($trialNo < 1 || $trialNo > 6) continue;

        $gate = null;
        if ($material === 'STONE' || $material === 'SAND') {
            if (!isset($trial['gate_cm']) || !is_numeric($trial['gate_cm'])) continue;
            $gate = (float)$trial['gate_cm'];
            if (!in_array((int)round($gate), [5,8,11], true)) continue;
        }

        $weight = isset($trial['total_weight_kg']) && is_numeric($trial['total_weight_kg'])
            ? (float)$trial['total_weight_kg'] : null;
        $counts = isset($trial['counts']) && is_numeric($trial['counts'])
            ? (float)$trial['counts'] : null;

        if ($weight === null && $counts === null) continue;

        $insert->execute([$id, $material, $gate, $trialNo, $weight, $counts]);
    }

    qbook_recalculate_calibration_results($db, $id);

    $db->commit();

    qbook_json([
        'ok' => true,
        'calibration_id' => $id,
        'status' => 'DRAFT',
        'message' => 'Calibration draft saved and recalculated.'
    ]);
} catch (RuntimeException $e) {
    if ($db->inTransaction()) $db->rollBack();

    $code = $e->getMessage();
    $status = match ($code) {
        'CALIBRATION_NOT_FOUND' => 404,
        'FORBIDDEN' => 403,
        'CALIBRATION_LOCKED' => 409,
        default => 400,
    };
    qbook_json(['ok' => false, 'error' => $code], $status);
} catch (Throwable $e) {
    if ($db->inTransaction()) $db->rollBack();
    qbook_json(['ok' => false, 'error' => 'SERVER_ERROR'], 500);
}
