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

$mixDesignId = (int)($input['mix_design_id'] ?? 0);
$name = trim((string)($input['name'] ?? ''));
$dosage = (float)($input['dosage_cc_per_100kg'] ?? 0);
$dilution = (float)($input['dilution_factor'] ?? 1);
$sortOrder = (int)($input['sort_order'] ?? 1);

if ($mixDesignId <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'MIX_DESIGN_REQUIRED'
    ], 400);
}

if ($name === '') {
    qbook_json([
        'ok' => false,
        'error' => 'ADMIXTURE_NAME_REQUIRED'
    ], 400);
}

if ($dosage < 0 || $dilution <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_ADMIXTURE_VALUES'
    ], 400);
}

if ($sortOrder < 1) {
    $sortOrder = 1;
}

$db = qbook_db();

/*
 * Confirm that the parent mix design exists.
 * We also load its name/client/project so the audit trail
 * is easier to understand later.
 */
$stmt = $db->prepare(
    "SELECT
        id,
        name,
        client_name,
        project_name,
        version_no,
        is_active
     FROM qbook_mix_designs
     WHERE id = ?
     LIMIT 1"
);

$stmt->execute([$mixDesignId]);
$mixDesign = $stmt->fetch();

if (!$mixDesign) {
    qbook_json([
        'ok' => false,
        'error' => 'MIX_DESIGN_NOT_FOUND'
    ], 404);
}

/*
 * Create admixture.
 *
 * New admixtures remain active by default,
 * preserving the existing QBook behavior.
 */
$stmt = $db->prepare(
    "INSERT INTO qbook_mix_admixtures
    (
        mix_design_id,
        sort_order,
        name,
        dosage_cc_per_100kg,
        dilution_factor,
        is_active
    )
    VALUES (?, ?, ?, ?, ?, 1)"
);

$stmt->execute([
    $mixDesignId,
    $sortOrder,
    $name,
    $dosage,
    $dilution
]);

$admixtureId = (int)$db->lastInsertId();

/*
 * Audit successful creation.
 */
qbook_audit(
    $user,
    'ADMIXTURE_CREATED',
    'MIX_ADMIXTURE',
    $admixtureId,
    [
        'mix_design_id' =>
            $mixDesignId,

        'mix_name' =>
            $mixDesign['name'],

        'mix_version_no' =>
            (int)$mixDesign['version_no'],

        'client_name' =>
            $mixDesign['client_name'],

        'project_name' =>
            $mixDesign['project_name'],

        'name' =>
            $name,

        'dosage_cc_per_100kg' =>
            round($dosage, 2),

        'dilution_factor' =>
            round($dilution, 2),

        'sort_order' =>
            $sortOrder,

        'is_active' =>
            true
    ]
);

qbook_json([
    'ok' => true,

    'admixture' => [
        'id' =>
            $admixtureId,

        'mix_design_id' =>
            $mixDesignId,

        'name' =>
            $name,

        'dosage_cc_per_100kg' =>
            round($dosage, 2),

        'dilution_factor' =>
            round($dilution, 2),

        'sort_order' =>
            $sortOrder,

        'is_active' =>
            true
    ]
], 201);