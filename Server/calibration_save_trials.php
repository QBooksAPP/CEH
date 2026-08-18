<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

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
$trials = $input['trials'] ?? null;

if ($calibrationId <= 0) {
    qbook_json(['ok' => false, 'error' => 'CALIBRATION_REQUIRED'], 400);
}

if (!is_array($trials) || count($trials) === 0) {
    qbook_json(['ok' => false, 'error' => 'TRIALS_REQUIRED'], 400);
}

/*
 * Check calibration ownership/status.
 */
$stmt = qbook_db()->prepare(
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

$isAdmin = ($user['role'] === 'ADMIN');

if (!$isAdmin && (int)$calibration['entered_by'] !== (int)$user['id']) {
    qbook_json(['ok' => false, 'error' => 'FORBIDDEN'], 403);
}

if ($calibration['status'] !== 'DRAFT') {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_LOCKED'
    ], 409);
}

/*
 * Valid field-sheet sections.
 */
$allowed = [
    'CEMENT_FULL' => null,
    'CEMENT_HALF' => null,

    'STONE_5'  => 5.000,
    'STONE_8'  => 8.000,
    'STONE_11' => 11.000,

    'SAND_5'  => 5.000,
    'SAND_8'  => 8.000,
    'SAND_11' => 11.000
];

$db = qbook_db();

try {
    $db->beginTransaction();

    $sql = "
        INSERT INTO qbook_calibration_trials
            (
                calibration_id,
                material,
                gate_cm,
                trial_no,
                total_weight_kg,
                counts
            )
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            total_weight_kg = VALUES(total_weight_kg),
            counts = VALUES(counts),
            updated_at = CURRENT_TIMESTAMP
    ";

    $save = $db->prepare($sql);

    $saved = 0;

    foreach ($trials as $trial) {

        if (!is_array($trial)) {
            throw new RuntimeException('INVALID_TRIAL');
        }

        $section = strtoupper(trim((string)($trial['section'] ?? '')));
        $trialNo = (int)($trial['trial_no'] ?? 0);

        if (!array_key_exists($section, $allowed)) {
            throw new RuntimeException('INVALID_SECTION');
        }

        if ($trialNo < 1 || $trialNo > 6) {
            throw new RuntimeException('INVALID_TRIAL_NUMBER');
        }

        if (
            !array_key_exists('total_weight_kg', $trial) ||
            !array_key_exists('counts', $trial) ||
            !is_numeric($trial['total_weight_kg']) ||
            !is_numeric($trial['counts'])
        ) {
            throw new RuntimeException('INVALID_TRIAL_VALUES');
        }

        $weight = (float)$trial['total_weight_kg'];
        $counts = (float)$trial['counts'];

        if ($weight <= 0 || $counts <= 0) {
            throw new RuntimeException('INVALID_TRIAL_VALUES');
        }

        /*
         * Store material separately from gate.
         */
        if (str_starts_with($section, 'STONE')) {
            $material = 'STONE';
        } elseif (str_starts_with($section, 'SAND')) {
            $material = 'SAND';
        } else {
            $material = $section;
        }

        $gate = $allowed[$section];

        $save->execute([
            $calibrationId,
            $material,
            $gate,
            $trialNo,
            $weight,
            $counts
        ]);

        $saved++;
    }

    $db->commit();

    qbook_json([
        'ok' => true,
        'calibration_id' => $calibrationId,
        'status' => 'DRAFT',
        'trials_saved' => $saved
    ]);

} catch (RuntimeException $e) {

    if ($db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json([
        'ok' => false,
        'error' => $e->getMessage()
    ], 400);

} catch (Throwable $e) {

    if ($db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}