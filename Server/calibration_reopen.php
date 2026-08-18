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
$reason = trim((string)($body['reason'] ?? 'Reopened by Admin'));

if ($id <= 0) {
    qbook_json(['ok' => false, 'error' => 'CALIBRATION_ID_REQUIRED'], 422);
}

$db = qbook_db();

try {
    $db->beginTransaction();

    $stmt = $db->prepare(
        "SELECT id, status FROM qbook_calibrations WHERE id=? FOR UPDATE"
    );
    $stmt->execute([$id]);
    $cal = $stmt->fetch();

    if (!$cal) throw new RuntimeException('CALIBRATION_NOT_FOUND');
    if ((string)$cal['status'] !== 'APPROVED') {
        throw new RuntimeException('ONLY_APPROVED_CAN_BE_REOPENED');
    }

    $stmt = $db->prepare(
        "UPDATE qbook_calibrations
         SET status='SUBMITTED', reviewed_by=NULL, reviewed_at=NULL,
             rejection_reason=NULL
         WHERE id=? AND status='APPROVED'"
    );
    $stmt->execute([$id]);

    if ($stmt->rowCount() !== 1) {
        throw new RuntimeException('REOPEN_FAILED');
    }

    /* Repair the stored results using the corrected formula at the same time. */
    qbook_recalculate_calibration_results($db, $id);

    $db->commit();

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
