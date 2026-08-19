<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/job_context.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$input = json_decode(file_get_contents('php://input'), true);

if (!is_array($input)) {
    qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
}

$mixId = (int)($input['mix_design_id'] ?? 0);

if ($mixId <= 0) {
    qbook_json(['ok' => false, 'error' => 'MIX_DESIGN_REQUIRED'], 400);
}

$db = qbook_db();

/*
 * Load existing design.
 */
$stmt = $db->prepare(
    "SELECT *
     FROM qbook_mix_designs
     WHERE id = ?
     LIMIT 1"
);

$stmt->execute([$mixId]);
$existing = $stmt->fetch();

if (!$existing) {
    qbook_json(['ok' => false, 'error' => 'MIX_DESIGN_NOT_FOUND'], 404);
}

/*
 * Fields not supplied retain their existing values.
 */
$name = array_key_exists('name', $input)
    ? trim((string)$input['name'])
    : (string)$existing['name'];

$description = array_key_exists('description', $input)
    ? trim((string)$input['description'])
    : (string)($existing['description'] ?? '');

$designMode = array_key_exists('design_mode', $input)
    ? strtoupper(trim((string)$input['design_mode']))
    : (string)$existing['design_mode'];
$clientId = array_key_exists('client_id',$input) ? (int)$input['client_id'] : (int)($existing['client_id']??0);
$projectId = array_key_exists('project_id',$input) ? (int)$input['project_id'] : (int)($existing['project_id']??0);
$stoneSize = qbook_stone_size(array_key_exists('stone_size',$input) ? $input['stone_size'] : ($existing['stone_size']??''));

$clientName = array_key_exists('client_name', $input)
    ? trim((string)$input['client_name'])
    : (string)($existing['client_name'] ?? '');

$projectName = array_key_exists('project_name', $input)
    ? trim((string)$input['project_name'])
    : (string)($existing['project_name'] ?? '');

$cementKg = array_key_exists('cement_kg', $input)
    ? (float)$input['cement_kg']
    : (float)$existing['cement_kg'];

$graniteKg = array_key_exists('granite_kg', $input)
    ? (float)$input['granite_kg']
    : (float)$existing['granite_kg'];

$waterL = array_key_exists('water_l', $input)
    ? (float)$input['water_l']
    : (float)$existing['water_l'];

$airPct = array_key_exists('air_pct', $input)
    ? (float)$input['air_pct']
    : (float)$existing['air_pct'];

$cementSg = array_key_exists('cement_sg', $input)
    ? (float)$input['cement_sg']
    : (float)$existing['cement_sg'];

$sandSg = array_key_exists('sand_sg', $input)
    ? (float)$input['sand_sg']
    : (float)$existing['sand_sg'];

$graniteSg = array_key_exists('granite_sg', $input)
    ? (float)$input['granite_sg']
    : (float)$existing['granite_sg'];

$isActive = array_key_exists('is_active', $input)
    ? ((bool)$input['is_active'] ? 1 : 0)
    : (int)$existing['is_active'];

/*
 * Validation.
 */
if ($name === '') {
    qbook_json(['ok' => false, 'error' => 'NAME_REQUIRED'], 400);
}

if (!in_array($designMode, ['CLIENT', 'CALCULATED'], true)) {
    qbook_json(['ok' => false, 'error' => 'INVALID_DESIGN_MODE'], 400);
}

if ($cementKg <= 0 || $graniteKg <= 0 || $waterL <= 0) {
    qbook_json(['ok' => false, 'error' => 'INVALID_MIX_QUANTITIES'], 400);
}

if ($cementSg <= 0 || $sandSg <= 0 || $graniteSg <= 0) {
    qbook_json(['ok' => false, 'error' => 'INVALID_SPECIFIC_GRAVITY'], 400);
}

if ($airPct < 0 || $airPct >= 1) {
    qbook_json(['ok' => false, 'error' => 'INVALID_AIR_PERCENT'], 400);
}

/*
 * Determine sand.
 *
 * CLIENT:
 * - use supplied sand if provided
 * - otherwise preserve existing sand
 *
 * CALCULATED:
 * - always recalculate sand from the remaining volume
 */
if ($designMode === 'CLIENT') {

    $sandKg = array_key_exists('sand_kg', $input)
        ? (float)$input['sand_kg']
        : (float)$existing['sand_kg'];

    if ($sandKg <= 0) {
        qbook_json([
            'ok' => false,
            'error' => 'SAND_REQUIRED_FOR_CLIENT_MIX'
        ], 400);
    }

} else {

    $batchVolume = 1.0;

    $cementVolume =
        $cementKg / ($cementSg * 1000);

    $graniteVolume =
        $graniteKg / ($graniteSg * 1000);

    $waterVolume =
        $waterL / 1000;

    $airVolume =
        $airPct * $batchVolume;

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

    $sandKg =
        $sandVolume * $sandSg * 1000;
}

/*
 * Absolute-volume check.
 */
$cementVolume =
    $cementKg / ($cementSg * 1000);

$sandVolume =
    $sandKg / ($sandSg * 1000);

$graniteVolume =
    $graniteKg / ($graniteSg * 1000);

$waterVolume =
    $waterL / 1000;

$airVolume =
    $airPct;

$calculatedVolume =
    $cementVolume
    + $sandVolume
    + $graniteVolume
    + $waterVolume
    + $airVolume;
$context = qbook_active_job_context($db,$clientId,$projectId);
$clientName=(string)$context['client_name']; $projectName=(string)$context['project_name'];
$validationChanged =
    $designMode !== (string)$existing['design_mode'] ||
    $clientId !== (int)($existing['client_id'] ?? 0) ||
    $projectId !== (int)($existing['project_id'] ?? 0) ||
    $stoneSize !== (string)($existing['stone_size'] ?? '') ||
    abs($cementKg - (float)$existing['cement_kg']) > 0.000001 ||
    abs($sandKg - (float)$existing['sand_kg']) > 0.000001 ||
    abs($graniteKg - (float)$existing['granite_kg']) > 0.000001 ||
    abs($waterL - (float)$existing['water_l']) > 0.000001 ||
    abs($airPct - (float)$existing['air_pct']) > 0.000001 ||
    abs($cementSg - (float)$existing['cement_sg']) > 0.000001 ||
    abs($sandSg - (float)$existing['sand_sg']) > 0.000001 ||
    abs($graniteSg - (float)$existing['granite_sg']) > 0.000001;
$validationStatus = $designMode === 'CLIENT'
    ? ($validationChanged ? 'PENDING_VALIDATION' : (string)($existing['client_validation_status']??'PENDING_VALIDATION'))
    : null;
$validatedBy = $validationChanged || $designMode !== 'CLIENT' ? null : $existing['client_validated_by'];
$validatedAt = $validationChanged || $designMode !== 'CLIENT' ? null : $existing['client_validated_at'];
$deviation=qbook_absolute_volume_deviation($calculatedVolume);

$oldVersion = (int)$existing['version_no'];
$newVersion = $oldVersion + 1;

$oldIsActive = (int)$existing['is_active'];
$newIsActive = $isActive;

try {

    $stmt = $db->prepare(
        "UPDATE qbook_mix_designs
         SET
            name = ?,
            description = ?,
            design_mode = ?,
            client_id = ?, project_id = ?, stone_size = ?,
            client_validation_status = ?, client_validated_by = ?, client_validated_at = ?,
            client_name = ?,
            project_name = ?,
            cement_kg = ?,
            sand_kg = ?,
            granite_kg = ?,
            water_l = ?,
            air_pct = ?,
            cement_sg = ?,
            sand_sg = ?,
            granite_sg = ?,
            batch_volume_m3 = 1.0000,
            is_active = ?,
            version_no = ?,
            updated_by = ?,
            updated_at = UTC_TIMESTAMP()
         WHERE id = ?"
    );

    $stmt->execute([
        $name,
        $description !== '' ? $description : null,
        $designMode,
        $clientId,$projectId,$stoneSize,$validationStatus,$validatedBy,$validatedAt,
        $clientName !== '' ? $clientName : null,
        $projectName !== '' ? $projectName : null,
        $cementKg,
        $sandKg,
        $graniteKg,
        $waterL,
        $airPct,
        $cementSg,
        $sandSg,
        $graniteSg,
        $isActive,
        $newVersion,
        (int)$user['id'],
        $mixId
    ]);

    /*
     * Every successful edit gets MIX_UPDATED.
     */
    qbook_audit(
        $user,
        'MIX_UPDATED',
        'MIX_DESIGN',
        $mixId,
        [
            'old_version_no' => $oldVersion,
            'new_version_no' => $newVersion,

            'name' => $name,
            'design_mode' => $designMode,
            'client_id'=>$clientId,'project_id'=>$projectId,'stone_size'=>$stoneSize,
            'old_client_validation_status'=>$existing['client_validation_status'],
            'client_validation_status'=>$validationStatus,
            'client_validation_reset'=>$designMode === 'CLIENT' && $validationChanged,

            'client_name' =>
                $clientName !== '' ? $clientName : null,

            'project_name' =>
                $projectName !== '' ? $projectName : null,

            'old_mix' => [
                'cement_kg' =>
                    round((float)$existing['cement_kg'], 2),

                'sand_kg' =>
                    round((float)$existing['sand_kg'], 2),

                'granite_kg' =>
                    round((float)$existing['granite_kg'], 2),

                'water_l' =>
                    round((float)$existing['water_l'], 2)
            ],

            'new_mix' => [
                'cement_kg' =>
                    round($cementKg, 2),

                'sand_kg' =>
                    round($sandKg, 2),

                'granite_kg' =>
                    round($graniteKg, 2),

                'water_l' =>
                    round($waterL, 2)
            ],

            'specific_gravity' => [
                'cement_sg' =>
                    round($cementSg, 3),

                'sand_sg' =>
                    round($sandSg, 3),

                'granite_sg' =>
                    round($graniteSg, 3)
            ],

            'calculated_absolute_volume_m3' =>
                round($calculatedVolume, 4),
            'absolute_volume_deviation_m3'=>round($deviation['deviation_m3'],4),
            'absolute_volume_deviation_status'=>$deviation['deviation_status'],

            'old_is_active' =>
                (bool)$oldIsActive,

            'new_is_active' =>
                (bool)$newIsActive
        ]
    );

    /*
     * If active status changed, create a separate audit event.
     * This makes activation/deactivation very easy to find later.
     */
    if ($oldIsActive === 0 && $newIsActive === 1) {

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
                'version_no' => $newVersion
            ]
        );

    } elseif ($oldIsActive === 1 && $newIsActive === 0) {

        qbook_audit(
            $user,
            'MIX_DEACTIVATED',
            'MIX_DESIGN',
            $mixId,
            [
                'name' => $name,
                'client_name' =>
                    $clientName !== '' ? $clientName : null,
                'project_name' =>
                    $projectName !== '' ? $projectName : null,
                'version_no' => $newVersion
            ]
        );
    }

    qbook_json([
        'ok' => true,

        'mix_design' => [
            'id' => $mixId,
            'name' => $name,
            'design_mode' => $designMode,
            'client_id'=>$clientId,'project_id'=>$projectId,'stone_size'=>$stoneSize,
            'client_validation_status'=>$validationStatus,

            'client_name' =>
                $clientName !== '' ? $clientName : null,

            'project_name' =>
                $projectName !== '' ? $projectName : null,

            'batch_volume_m3' => 1.00,

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
            'absolute_volume_deviation_m3'=>round($deviation['deviation_m3'],4),
            'absolute_volume_deviation_status'=>$deviation['deviation_status'],

            'is_active' =>
                (bool)$isActive,

            'version_no' =>
                $newVersion
        ]
    ]);

} catch (Throwable $e) {

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}
