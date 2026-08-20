<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/calibration_math.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$body = json_decode(file_get_contents('php://input'), true);
if (!is_array($body)) {
    qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
}

$id = (int)($body['calibration_id'] ?? 0);
$reason = substr(trim((string)($body['reason'] ?? 'Reopened by Admin')), 0, 500);

if ($id <= 0) {
    qbook_json(['ok' => false, 'error' => 'CALIBRATION_ID_REQUIRED'], 422);
}

$db = qbook_db();

try {
    $db->beginTransaction();

    $stmt = $db->prepare(
        "SELECT * FROM qbook_calibrations WHERE id=? FOR UPDATE"
    );
    $stmt->execute([$id]);
    $cal = $stmt->fetch();

    if (!$cal) throw new RuntimeException('CALIBRATION_NOT_FOUND');
    if ((string)$cal['status'] !== 'APPROVED') {
        throw new RuntimeException('ONLY_APPROVED_CAN_BE_REOPENED');
    }

    $trialStmt = $db->prepare(
        "SELECT material,gate_cm,trial_no,total_weight_kg,counts
         FROM qbook_calibration_trials WHERE calibration_id=?
         ORDER BY material,gate_cm,trial_no"
    );
    $trialStmt->execute([$id]);
    $resultStmt = $db->prepare(
        "SELECT material,gate_cm,avg_total_weight_kg,avg_counts,moisture_pct,
                net_dry_weight_kg,kg_per_count,calculated_at
         FROM qbook_calibration_results WHERE calibration_id=?
         ORDER BY material,gate_cm"
    );
    $resultStmt->execute([$id]);
    $snapshot = ['calibration'=>$cal, 'trials'=>$trialStmt->fetchAll(),
        'results'=>$resultStmt->fetchAll()];
    $db->prepare(
        "INSERT INTO qbook_calibration_revision_snapshots
         (calibration_id,revision_no,status,snapshot_json,reason,captured_by,captured_at)
         VALUES(?,?,'APPROVED',?,?,?,UTC_TIMESTAMP())"
    )->execute([$id, (int)$cal['revision_no'], json_encode($snapshot, JSON_THROW_ON_ERROR),
        $reason === '' ? null : $reason, (int)$user['id']]);

    $stmt = $db->prepare(
        "UPDATE qbook_calibrations
         SET status='SUBMITTED', reviewed_by=NULL, reviewed_at=NULL,
             rejection_reason=NULL, revision_no=revision_no + 1
         WHERE id=? AND status='APPROVED'"
    );
    $stmt->execute([$id]);

    if ($stmt->rowCount() !== 1) {
        throw new RuntimeException('REOPEN_FAILED');
    }

    /* Repair the stored results using the corrected formula at the same time. */
    qbook_recalculate_calibration_results($db, $id);

    $db->commit();

    qbook_audit($user, 'CALIBRATION_APPROVAL_REOPENED', 'CALIBRATION', $id, [
        'previous_revision_no'=>(int)$cal['revision_no'],
        'new_revision_no'=>(int)$cal['revision_no'] + 1,
        'reason'=>$reason,
    ]);

    qbook_json([
        'ok' => true,
        'calibration_id' => $id,
        'status' => 'SUBMITTED',
        'reason' => $reason,
        'message' => 'Approval reopened and calibration results recalculated.'
    ]);
} catch (RuntimeException $e) {
    if ($db->inTransaction()) $db->rollBack();

    $code = $e->getMessage();
    $status = match ($code) {
        'CALIBRATION_NOT_FOUND' => 404,
        'ONLY_APPROVED_CAN_BE_REOPENED' => 409,
        default => 409,
    };
    qbook_json(['ok' => false, 'error' => $code], $status);
} catch (Throwable $e) {
    if ($db->inTransaction()) $db->rollBack();
    qbook_json(['ok' => false, 'error' => 'SERVER_ERROR'], 500);
}
