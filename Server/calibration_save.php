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
$adminReason = substr(trim((string)($input['admin_edit_reason'] ?? '')), 0, 500);
$adminChanges = [];
$originalStatus = null;

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
    qbook_require_project_mixer($db, $projectId, $mixerId);
} catch (RuntimeException $e) {
    qbook_json(['ok' => false, 'error' => $e->getMessage()], 409);
}

try {
    $db->beginTransaction();

    if ($id > 0) {
        $stmt = $db->prepare(
            "SELECT *
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

        $originalStatus = (string)$existing['status'];
        $adminAllowed = $user['role'] === 'ADMIN' &&
            in_array($originalStatus, ['DRAFT', 'REJECTED', 'SUBMITTED'], true);
        $operatorAllowed = $user['role'] !== 'ADMIN' &&
            in_array($originalStatus, ['DRAFT', 'REJECTED'], true);
        if (!$adminAllowed && !$operatorAllowed) {
            throw new RuntimeException('CALIBRATION_LOCKED');
        }

        if ($user['role'] === 'ADMIN') {
            $oldTrialsStmt = $db->prepare(
                "SELECT material,gate_cm,trial_no,total_weight_kg,counts
                 FROM qbook_calibration_trials WHERE calibration_id=?
                 ORDER BY material,gate_cm,trial_no"
            );
            $oldTrialsStmt->execute([$id]);
            $oldValues = [
                'mixer_id'=>(int)$existing['mixer_id'], 'client_id'=>$existing['client_id'],
                'project_id'=>$existing['project_id'], 'stone_size'=>$existing['stone_size'],
                'calibration_date'=>$existing['calibration_date'],
                'calibration_notes'=>$existing['calibration_notes'],
                'container_weight_kg'=>(float)$existing['container_weight_kg'],
                'stone_moisture_pct'=>(float)$existing['stone_moisture_pct'],
                'sand_moisture_pct'=>(float)$existing['sand_moisture_pct'],
                'cement_safety_factor_pct'=>(float)$existing['cement_safety_factor_pct'],
                'trials'=>$oldTrialsStmt->fetchAll(),
            ];
        }

        $stmt = $db->prepare(
            "UPDATE qbook_calibrations
             SET mixer_id=?, client_id=?, project_id=?, client_name_snapshot=?,
                 project_name_snapshot=?, stone_size=?, calibration_date=?, calibration_notes=?,
                 container_weight_kg=?, stone_moisture_pct=?, sand_moisture_pct=?,
                 cement_safety_factor_pct=?, status=?,
                 submitted_at=?, reviewed_by=NULL, reviewed_at=NULL,
                 rejection_reason=?,
                 revision_no=revision_no + ?
             WHERE id=?"
        );
        $stmt->execute([
            $mixerId, $clientId, $projectId, $context['client_name'],
            $context['project_name'], $stoneSize, $date, $notes, $container, $stoneMoisture,
            $sandMoisture, $cementSafety,
            $originalStatus === 'SUBMITTED' ? 'SUBMITTED' : 'DRAFT',
            $originalStatus === 'SUBMITTED' ? $existing['submitted_at'] : null,
            $originalStatus === 'SUBMITTED' ? $existing['rejection_reason'] : null,
            $originalStatus === 'REJECTED' ? 1 : 0,
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

    if ($user['role'] === 'ADMIN' && isset($oldValues)) {
        $newTrialsStmt = $db->prepare(
            "SELECT material,gate_cm,trial_no,total_weight_kg,counts
             FROM qbook_calibration_trials WHERE calibration_id=?
             ORDER BY material,gate_cm,trial_no"
        );
        $newTrialsStmt->execute([$id]);
        $newValues = [
            'mixer_id'=>$mixerId, 'client_id'=>$clientId, 'project_id'=>$projectId,
            'stone_size'=>$stoneSize, 'calibration_date'=>$date,
            'calibration_notes'=>$notes, 'container_weight_kg'=>$container,
            'stone_moisture_pct'=>$stoneMoisture,
            'sand_moisture_pct'=>$sandMoisture,
            'cement_safety_factor_pct'=>$cementSafety,
            'trials'=>$newTrialsStmt->fetchAll(),
        ];
        foreach ($newValues as $field => $newValue) {
            $oldValue = $oldValues[$field] ?? null;
            if (json_encode($oldValue) !== json_encode($newValue)) {
                $adminChanges[] = ['field'=>$field,'old'=>$oldValue,'new'=>$newValue];
            }
        }
    }

    if ($adminChanges !== []) {
        $auditDetails = [
            'revision_no'=>(int)($existing['revision_no'] ?? 1),
            'status'=>$originalStatus, 'reason'=>$adminReason,
            'changed_at_utc'=>gmdate('Y-m-d\TH:i:s\Z'),
            'changes'=>$adminChanges,
        ];
        $auditStmt = $db->prepare(
            "INSERT INTO qbook_audit_log
             (user_id,event_type,source_type,source_id,details,ip_address)
             VALUES(?,'CALIBRATION_ADMIN_CORRECTED','CALIBRATION',?,?,?)"
        );
        $auditStmt->execute([(int)$user['id'], $id,
            json_encode($auditDetails, JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_SUBSTITUTE),
            qbook_client_ip()]);
    }

    $db->commit();

    qbook_json([
        'ok' => true,
        'calibration_id' => $id,
        'status' => $originalStatus === 'SUBMITTED' ? 'SUBMITTED' : 'DRAFT',
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
