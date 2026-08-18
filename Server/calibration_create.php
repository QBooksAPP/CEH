<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

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

$mixerId = (int)($input['mixer_id'] ?? 0);
$calibrationDate = trim((string)($input['calibration_date'] ?? ''));
$notes = trim((string)($input['calibration_notes'] ?? ''));

$containerWeight = (float)($input['container_weight_kg'] ?? 0);
$stoneMoisture = (float)($input['stone_moisture_pct'] ?? 0);
$sandMoisture = (float)($input['sand_moisture_pct'] ?? 0);
$cementSafetyFactor = (float)($input['cement_safety_factor_pct'] ?? 0);

if ($mixerId <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'MIXER_REQUIRED'
    ], 400);
}

if ($calibrationDate === '') {
    qbook_json([
        'ok' => false,
        'error' => 'CALIBRATION_DATE_REQUIRED'
    ], 400);
}

$date = DateTime::createFromFormat('Y-m-d', $calibrationDate);

if (!$date || $date->format('Y-m-d') !== $calibrationDate) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_CALIBRATION_DATE'
    ], 400);
}

if (
    $containerWeight < 0 ||
    $stoneMoisture < 0 ||
    $sandMoisture < 0 ||
    $cementSafetyFactor < 0
) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_CALIBRATION_VALUES'
    ], 400);
}

/* Confirm that the mixer exists and is active. */
$stmt = qbook_db()->prepare(
    "SELECT id, code, name, model, truck_number
     FROM qbook_mixers
     WHERE id = ?
       AND is_active = 1
     LIMIT 1"
);

$stmt->execute([$mixerId]);
$mixer = $stmt->fetch();

if (!$mixer) {
    qbook_json([
        'ok' => false,
        'error' => 'MIXER_NOT_FOUND'
    ], 404);
}

/* Create the DRAFT calibration. */
$stmt = qbook_db()->prepare(
    "INSERT INTO qbook_calibrations
        (
            mixer_id,
            calibration_date,
            calibration_notes,
            container_weight_kg,
            stone_moisture_pct,
            sand_moisture_pct,
            cement_safety_factor_pct,
            status,
            entered_by
        )
     VALUES (?, ?, ?, ?, ?, ?, ?, 'DRAFT', ?)"
);

$stmt->execute([
    $mixerId,
    $calibrationDate,
    $notes !== '' ? $notes : null,
    $containerWeight,
    $stoneMoisture,
    $sandMoisture,
    $cementSafetyFactor,
    (int)$user['id']
]);

$calibrationId = (int)qbook_db()->lastInsertId();

qbook_json([
    'ok' => true,
    'calibration' => [
        'id' => $calibrationId,
        'status' => 'DRAFT',
        'mixer' => $mixer,
        'calibration_date' => $calibrationDate,
        'calibration_notes' => $notes !== '' ? $notes : null,
        'container_weight_kg' => $containerWeight,
        'stone_moisture_pct' => $stoneMoisture,
        'sand_moisture_pct' => $sandMoisture,
        'cement_safety_factor_pct' => $cementSafetyFactor,
        'entered_by' => [
            'id' => (int)$user['id'],
            'name' => $user['full_name']
        ]
    ]
], 201);