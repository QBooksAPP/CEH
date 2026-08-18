<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json([
        'ok' => false,
        'error' => 'METHOD_NOT_ALLOWED'
    ], 405);
}

$input = json_decode(file_get_contents('php://input'), true);

if (!is_array($input)) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_JSON'
    ], 400);
}

$calibrationId = (int)($input['calibration_id'] ?? 0);
$action = strtoupper(trim((string)($input['action'] ?? '')));
$reason = trim((string)($input['reason'] ?? ''));

if ($calibrationId <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_REQUIRED'
    ], 400);
}

if (!in_array($action, ['APPROVE', 'REJECT'], true)) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_ACTION'
    ], 400);
}

if ($action === 'REJECT' && $reason === '') {
    qbook_json([
        'ok' => false,
        'error' => 'REJECTION_REASON_REQUIRED'
    ], 400);
}

$db = qbook_db();

/*
 * Load the submitted calibration before changing it.
 */
$stmt = $db->prepare(
    "SELECT
        c.id,
        c.status,
        c.mixer_id,
        c.entered_by,
        c.revision_no,
        c.calibration_date,
        c.calibration_notes,
        c.stone_moisture_pct,
        c.sand_moisture_pct,

        m.code AS mixer_code,
        m.name AS mixer_name

     FROM qbook_calibrations c

     JOIN qbook_mixers m
        ON m.id = c.mixer_id

     WHERE c.id = ?
     LIMIT 1"
);

$stmt->execute([$calibrationId]);
$calibration = $stmt->fetch();

if (!$calibration) {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_NOT_FOUND'
    ], 404);
}

if ($calibration['status'] !== 'SUBMITTED') {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_NOT_SUBMITTED',
        'status' => $calibration['status']
    ], 409);
}

try {

    $db->beginTransaction();

    /*
     * APPROVE
     */
    if ($action === 'APPROVE') {

        $stmt = $db->prepare(
            "UPDATE qbook_calibrations
             SET
                status = 'APPROVED',
                reviewed_by = ?,
                reviewed_at = UTC_TIMESTAMP(),
                rejection_reason = NULL
             WHERE id = ?
               AND status = 'SUBMITTED'"
        );

        $stmt->execute([
            (int)$user['id'],
            $calibrationId
        ]);

        if ($stmt->rowCount() !== 1) {
            throw new RuntimeException('APPROVAL_FAILED');
        }

        $newStatus = 'APPROVED';

    /*
     * REJECT
     */
    } else {

        $stmt = $db->prepare(
            "UPDATE qbook_calibrations
             SET
                status = 'REJECTED',
                reviewed_by = ?,
                reviewed_at = UTC_TIMESTAMP(),
                rejection_reason = ?
             WHERE id = ?
               AND status = 'SUBMITTED'"
        );

        $stmt->execute([
            (int)$user['id'],
            $reason,
            $calibrationId
        ]);

        if ($stmt->rowCount() !== 1) {
            throw new RuntimeException('REJECTION_FAILED');
        }

        $newStatus = 'REJECTED';
    }

    /*
     * Commit the calibration decision first.
     */
    $db->commit();

    /*
     * Audit only after the real action has committed.
     */
    if ($action === 'APPROVE') {

        qbook_audit(
            $user,
            'CALIBRATION_APPROVED',
            'CALIBRATION',
            $calibrationId,
            [
                'mixer_id' =>
                    (int)$calibration['mixer_id'],

                'mixer_code' =>
                    $calibration['mixer_code'],

                'calibration_date' =>
                    $calibration['calibration_date'],

                'calibration_notes' =>
                    $calibration['calibration_notes'],

                'revision_no' =>
                    (int)$calibration['revision_no'],

                'entered_by' =>
                    (int)$calibration['entered_by'],

                'sand_moisture_pct' =>
                    (float)$calibration['sand_moisture_pct'],

                'stone_moisture_pct' =>
                    (float)$calibration['stone_moisture_pct'],

                'previous_status' =>
                    'SUBMITTED',

                'new_status' =>
                    'APPROVED'
            ]
        );

    } else {

        qbook_audit(
            $user,
            'CALIBRATION_REJECTED',
            'CALIBRATION',
            $calibrationId,
            [
                'mixer_id' =>
                    (int)$calibration['mixer_id'],

                'mixer_code' =>
                    $calibration['mixer_code'],

                'calibration_date' =>
                    $calibration['calibration_date'],

                'calibration_notes' =>
                    $calibration['calibration_notes'],

                'revision_no' =>
                    (int)$calibration['revision_no'],

                'entered_by' =>
                    (int)$calibration['entered_by'],

                'previous_status' =>
                    'SUBMITTED',

                'new_status' =>
                    'REJECTED',

                'reason' =>
                    $reason
            ]
        );
    }

    qbook_json([
        'ok' =>
            true,

        'calibration_id' =>
            $calibrationId,

        'mixer' => [
            'id' =>
                (int)$calibration['mixer_id'],

            'code' =>
                $calibration['mixer_code'],

            'name' =>
                $calibration['mixer_name']
        ],

        'action' =>
            $action,

        'status' =>
            $newStatus,

        'reviewed_by' => [
            'id' =>
                (int)$user['id'],

            'name' =>
                $user['full_name']
        ],

        'reason' =>
            $action === 'REJECT'
                ? $reason
                : null
    ]);

} catch (RuntimeException $e) {

    if ($db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json([
        'ok' => false,
        'error' => $e->getMessage()
    ], 409);

} catch (Throwable $e) {

    if ($db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}