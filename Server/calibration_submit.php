<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/job_context.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR']);

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

if ($calibrationId <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_REQUIRED'
    ], 400);
}

$db = qbook_db();

/*
 * Load calibration.
 */
$stmt = $db->prepare(
    "SELECT
        c.id,
        c.mixer_id,
        c.client_id,
        c.project_id,
        c.stone_size,
        c.entered_by,
        c.status,
        c.calibration_date,
        c.calibration_notes,
        c.stone_moisture_pct,
        c.sand_moisture_pct,
        c.revision_no,

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

/*
 * Operators/Supervisors may only submit calibrations
 * that they originally entered.
 *
 * ADMIN may submit any draft calibration.
 */
$isAdmin = ($user['role'] === 'ADMIN');

if (
    !$isAdmin &&
    (int)$calibration['entered_by'] !== (int)$user['id']
) {
    qbook_json([
        'ok' => false,
        'error' => 'FORBIDDEN'
    ], 403);
}

if ($calibration['status'] !== 'DRAFT') {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_NOT_DRAFT',
        'status' => $calibration['status']
    ], 409);
}
if ($calibration['client_id'] === null || $calibration['project_id'] === null
    || !in_array((string)$calibration['stone_size'], ['3/8"','1/2"','3/4 Down'], true)) {
    qbook_json(['ok'=>false,'error'=>'CALIBRATION_CONTEXT_REQUIRED'],422);
}
try {
    qbook_require_project_mixer($db, (int)$calibration['project_id'],
        (int)$calibration['mixer_id']);
} catch (RuntimeException $e) {
    qbook_json(['ok'=>false,'error'=>$e->getMessage()],409);
}
if ((float)$calibration['sand_moisture_pct'] < 0 || (float)$calibration['sand_moisture_pct'] > 10
    || (float)$calibration['stone_moisture_pct'] < 0 || (float)$calibration['stone_moisture_pct'] > 10) {
    qbook_json(['ok'=>false,'error'=>'MOISTURE_MUST_BE_0_TO_10_PERCENT'],422);
}

/*
 * Verify required calculated calibration results.
 *
 * Required:
 * - CEMENT_FULL
 * - STONE 5 / 8 / 11
 * - SAND 5 / 8 / 11
 */
$stmt = $db->prepare(
    "SELECT
        material,
        gate_cm,
        kg_per_count
     FROM qbook_calibration_results
     WHERE calibration_id = ?"
);

$stmt->execute([$calibrationId]);
$results = $stmt->fetchAll();

$found = [];

foreach ($results as $result) {

    $material = (string)$result['material'];

    if ($material === 'CEMENT_FULL') {

        $key = 'CEMENT_FULL';

    } else {

        $gate = (int)round(
            (float)$result['gate_cm']
        );

        $key = $material . '_' . $gate;
    }

    if (
        $result['kg_per_count'] !== null &&
        (float)$result['kg_per_count'] > 0
    ) {
        $found[$key] = true;
    }
}

$required = [
    'CEMENT_FULL',
    'STONE_5',
    'STONE_8',
    'STONE_11',
    'SAND_5',
    'SAND_8',
    'SAND_11'
];

$missing = [];

foreach ($required as $key) {

    if (!isset($found[$key])) {
        $missing[] = $key;
    }
}

if ($missing) {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_INCOMPLETE',
        'missing' => $missing
    ], 400);
}

/*
 * Submit and lock calibration.
 */
$stmt = $db->prepare(
    "UPDATE qbook_calibrations
     SET
        status = 'SUBMITTED',
        submitted_at = UTC_TIMESTAMP(),
        rejection_reason = NULL
     WHERE id = ?
       AND status = 'DRAFT'"
);

$stmt->execute([$calibrationId]);

if ($stmt->rowCount() !== 1) {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_SUBMIT_FAILED'
    ], 409);
}

/*
 * Audit only after successful submission.
 */
qbook_audit(
    $user,
    'CALIBRATION_SUBMITTED',
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

        'submitted_by' =>
            (int)$user['id'],

        'sand_moisture_pct' =>
            (float)$calibration['sand_moisture_pct'],

        'stone_moisture_pct' =>
            (float)$calibration['stone_moisture_pct'],

        'previous_status' =>
            'DRAFT',

        'new_status' =>
            'SUBMITTED'
    ]
);

qbook_json([
    'ok' => true,

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

    'status' =>
        'SUBMITTED',

    'message' =>
        'Calibration submitted for admin approval.'
]);
