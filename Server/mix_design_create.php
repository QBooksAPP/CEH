<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/job_context.php';

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

$name        = trim((string)($input['name'] ?? ''));
$description = trim((string)($input['description'] ?? ''));
$designMode  = strtoupper(trim((string)($input['design_mode'] ?? 'CLIENT')));
$clientId = (int)($input['client_id'] ?? 0);
$projectId = (int)($input['project_id'] ?? 0);
$stoneSize = qbook_stone_size($input['stone_size'] ?? '');

$isActive = array_key_exists('is_active', $input)
    ? ((bool)$input['is_active'] ? 1 : 0)
    : 1;

$cementKg  = (float)($input['cement_kg'] ?? 0);
$graniteKg = (float)($input['granite_kg'] ?? 0);
$waterL    = (float)($input['water_l'] ?? 0);

$airPct    = (float)($input['air_pct'] ?? 0);
$cementSg  = (float)($input['cement_sg'] ?? 3.15);
$sandSg    = (float)($input['sand_sg'] ?? 2.60);
$graniteSg = (float)($input['granite_sg'] ?? 2.70);

$batchVolume = 1.0000;

if ($name === '') {
    qbook_json([
        'ok' => false,
        'error' => 'NAME_REQUIRED'
    ], 400);
}

if (!in_array($designMode, ['CLIENT', 'CALCULATED'], true)) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_DESIGN_MODE'
    ], 400);
}

if ($cementKg <= 0 || $graniteKg <= 0 || $waterL <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_MIX_QUANTITIES'
    ], 400);
}

if ($cementSg <= 0 || $sandSg <= 0 || $graniteSg <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_SPECIFIC_GRAVITY'
    ], 400);
}

if ($airPct < 0 || $airPct >= 1) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_AIR_PERCENT'
    ], 400);
}

/*
 * CLIENT:
 * Preserve the client's supplied sand quantity exactly.
 *
 * CALCULATED:
 * Calculate sand from the remaining absolute volume.
 */
if ($designMode === 'CLIENT') {

    if (
        !array_key_exists('sand_kg', $input) ||
        !is_numeric($input['sand_kg']) ||
        (float)$input['sand_kg'] <= 0
    ) {
        qbook_json([
            'ok' => false,
            'error' => 'SAND_REQUIRED_FOR_CLIENT_MIX'
        ], 400);
    }

    $sandKg = (float)$input['sand_kg'];

} else {

    $cementVolume  = $cementKg / ($cementSg * 1000);
    $graniteVolume = $graniteKg / ($graniteSg * 1000);
    $waterVolume   = $waterL / 1000;
    $airVolume     = $airPct * $batchVolume;

    $sandVolume =
        $batchVolume
        - $cementVolume
        - $graniteVolume
        - $waterVolume
        - $airVolume;

    if ($sandVolume <= 0) {
        qbook_json([
            'ok' => false,
            'error' => 'INVALID_REMAINING_SAND_VOLUME'
        ], 400);
    }

    $sandKg = $sandVolume * $sandSg * 1000;
}

/*
 * Absolute-volume reference.
 */
$cementVolume  = $cementKg / ($cementSg * 1000);
$sandVolume    = $sandKg / ($sandSg * 1000);
$graniteVolume = $graniteKg / ($graniteSg * 1000);
$waterVolume   = $waterL / 1000;
$airVolume     = $airPct * $batchVolume;

$calculatedVolume =
    $cementVolume +
    $sandVolume +
    $graniteVolume +
    $waterVolume +
    $airVolume;

$db = qbook_db();
$context = qbook_active_job_context($db, $clientId, $projectId);
$clientName = (string)$context['client_name'];
$projectName = (string)$context['project_name'];
$validationStatus = $designMode === 'CLIENT' ? 'PENDING_VALIDATION' : null;
$deviation = qbook_absolute_volume_deviation($calculatedVolume);

try {

    $stmt = $db->prepare(
        "INSERT INTO qbook_mix_designs
        (
            name,
            description,
            design_mode,
            client_id,
            project_id,
            stone_size,
            client_validation_status,
            client_name,
            project_name,
            cement_kg,
            granite_kg,
            water_l,
            sand_kg,
            air_pct,
            cement_sg,
            sand_sg,
            granite_sg,
            batch_volume_m3,
            is_active,
            version_no,
            created_by,
            updated_by
        )
        VALUES
        (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1.0000, ?, 1, ?, ?)"
    );

    $stmt->execute([
        $name,
        $description !== '' ? $description : null,
        $designMode,
        $clientId,
        $projectId,
        $stoneSize,
        $validationStatus,
        $clientName !== '' ? $clientName : null,
        $projectName !== '' ? $projectName : null,
        $cementKg,
        $graniteKg,
        $waterL,
        $sandKg,
        $airPct,
        $cementSg,
        $sandSg,
        $graniteSg,
        $isActive,
        (int)$user['id'],
        (int)$user['id']
    ]);

    $mixId = (int)$db->lastInsertId();

    /*
     * Audit successful creation.
     */
    qbook_audit(
        $user,
        'MIX_CREATED',
        'MIX_DESIGN',
        $mixId,
        [
            'name' => $name,
            'design_mode' => $designMode,
            'client_id' => $clientId,
            'project_id' => $projectId,
            'stone_size' => $stoneSize,
            'client_validation_status' => $validationStatus,

            'client_name' =>
                $clientName !== '' ? $clientName : null,

            'project_name' =>
                $projectName !== '' ? $projectName : null,

            'cement_kg' =>
                round($cementKg, 2),

            'sand_kg' =>
                round($sandKg, 2),

            'granite_kg' =>
                round($graniteKg, 2),

            'water_l' =>
                round($waterL, 2),

            'air_pct' =>
                round($airPct, 4),

            'cement_sg' =>
                round($cementSg, 3),

            'sand_sg' =>
                round($sandSg, 3),

            'granite_sg' =>
                round($graniteSg, 3),

            'calculated_absolute_volume_m3' =>
                round($calculatedVolume, 4),
            'absolute_volume_deviation_m3' => round($deviation['deviation_m3'], 4),
            'absolute_volume_deviation_status' => $deviation['deviation_status'],

            'is_active' =>
                (bool)$isActive,

            'version_no' =>
                1
        ]
    );

    if ($isActive === 1) {
        qbook_audit(
            $user,
            'MIX_ACTIVATED',
            'MIX_DESIGN',
            $mixId,
            [
                'name' => $name,
                'client_name' =>
                    $clientName !== '' ? $clientName : null,
                'project_name' =>
                    $projectName !== '' ? $projectName : null,
                'version_no' => 1
            ]
        );
    }

    qbook_json([
        'ok' => true,
        'mix_design' => [
            'id' => $mixId,
            'name' => $name,
            'design_mode' => $designMode,
            'client_id' => $clientId,
            'project_id' => $projectId,
            'stone_size' => $stoneSize,
            'client_validation_status' => $validationStatus,
            'client_name' =>
                $clientName !== '' ? $clientName : null,
            'project_name' =>
                $projectName !== '' ? $projectName : null,
            'batch_volume_m3' => 1.00,
            'cement_kg' => round($cementKg, 2),
            'sand_kg' => round($sandKg, 2),
            'granite_kg' => round($graniteKg, 2),
            'water_l' => round($waterL, 2),
            'air_pct' => round($airPct, 4),
            'cement_sg' => round($cementSg, 3),
            'sand_sg' => round($sandSg, 3),
            'granite_sg' => round($graniteSg, 3),
            'calculated_absolute_volume_m3' =>
                round($calculatedVolume, 4),
            'absolute_volume_deviation_m3' => round($deviation['deviation_m3'], 4),
            'absolute_volume_deviation_status' => $deviation['deviation_status'],
            'is_active' => (bool)$isActive,
            'version_no' => 1
        ]
    ], 201);

} catch (PDOException $e) {

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}
