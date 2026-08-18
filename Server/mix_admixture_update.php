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

$admixtureId = (int)($input['admixture_id'] ?? 0);

if ($admixtureId <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'ADMIXTURE_REQUIRED'
    ], 400);
}

$db = qbook_db();

/*
 * Load existing admixture.
 */
$stmt = $db->prepare(
    "SELECT
        id,
        mix_design_id,
        sort_order,
        name,
        dosage_cc_per_100kg,
        dilution_factor,
        is_active
     FROM qbook_mix_admixtures
     WHERE id = ?
     LIMIT 1"
);

$stmt->execute([$admixtureId]);
$existing = $stmt->fetch();

if (!$existing) {
    qbook_json([
        'ok' => false,
        'error' => 'ADMIXTURE_NOT_FOUND'
    ], 404);
}

/*
 * Keep existing values when a field is not supplied.
 */
$name = array_key_exists('name', $input)
    ? trim((string)$input['name'])
    : (string)$existing['name'];

$dosage = array_key_exists('dosage_cc_per_100kg', $input)
    ? (float)$input['dosage_cc_per_100kg']
    : (float)$existing['dosage_cc_per_100kg'];

$dilution = array_key_exists('dilution_factor', $input)
    ? (float)$input['dilution_factor']
    : (float)$existing['dilution_factor'];

$sortOrder = array_key_exists('sort_order', $input)
    ? (int)$input['sort_order']
    : (int)$existing['sort_order'];

$isActive = array_key_exists('is_active', $input)
    ? ((bool)$input['is_active'] ? 1 : 0)
    : (int)$existing['is_active'];

/*
 * Validation.
 */
if ($name === '') {
    qbook_json([
        'ok' => false,
        'error' => 'ADMIXTURE_NAME_REQUIRED'
    ], 400);
}

if ($dosage < 0) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_ADMIXTURE_DOSAGE'
    ], 400);
}

if ($dilution <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_DILUTION_FACTOR'
    ], 400);
}

if ($sortOrder < 1) {
    $sortOrder = 1;
}

$oldIsActive = (int)$existing['is_active'];
$newIsActive = $isActive;

/*
 * Update admixture.
 */
$stmt = $db->prepare(
    "UPDATE qbook_mix_admixtures
     SET
        name = ?,
        dosage_cc_per_100kg = ?,
        dilution_factor = ?,
        sort_order = ?,
        is_active = ?
     WHERE id = ?"
);

$stmt->execute([
    $name,
    $dosage,
    $dilution,
    $sortOrder,
    $isActive,
    $admixtureId
]);

/*
 * Record every successful admixture edit.
 */
qbook_audit(
    $user,
    'ADMIXTURE_UPDATED',
    'MIX_ADMIXTURE',
    $admixtureId,
    [
        'mix_design_id' =>
            (int)$existing['mix_design_id'],

        'old_values' => [
            'name' =>
                $existing['name'],

            'dosage_cc_per_100kg' =>
                round((float)$existing['dosage_cc_per_100kg'], 2),

            'dilution_factor' =>
                round((float)$existing['dilution_factor'], 2),

            'sort_order' =>
                (int)$existing['sort_order'],

            'is_active' =>
                (bool)$oldIsActive
        ],

        'new_values' => [
            'name' =>
                $name,

            'dosage_cc_per_100kg' =>
                round($dosage, 2),

            'dilution_factor' =>
                round($dilution, 2),

            'sort_order' =>
                $sortOrder,

            'is_active' =>
                (bool)$newIsActive
        ]
    ]
);

/*
 * Separate activation/deactivation events make these
 * important changes easy to find in Audit History.
 */
if ($oldIsActive === 0 && $newIsActive === 1) {

    qbook_audit(
        $user,
        'ADMIXTURE_ACTIVATED',
        'MIX_ADMIXTURE',
        $admixtureId,
        [
            'mix_design_id' =>
                (int)$existing['mix_design_id'],

            'name' =>
                $name,

            'dosage_cc_per_100kg' =>
                round($dosage, 2),

            'dilution_factor' =>
                round($dilution, 2)
        ]
    );

} elseif ($oldIsActive === 1 && $newIsActive === 0) {

    qbook_audit(
        $user,
        'ADMIXTURE_DEACTIVATED',
        'MIX_ADMIXTURE',
        $admixtureId,
        [
            'mix_design_id' =>
                (int)$existing['mix_design_id'],

            'name' =>
                $name,

            'dosage_cc_per_100kg' =>
                round($dosage, 2),

            'dilution_factor' =>
                round($dilution, 2)
        ]
    );
}

qbook_json([
    'ok' => true,

    'admixture' => [
        'id' =>
            $admixtureId,

        'mix_design_id' =>
            (int)$existing['mix_design_id'],

        'name' =>
            $name,

        'dosage_cc_per_100kg' =>
            round($dosage, 2),

        'dilution_factor' =>
            round($dilution, 2),

        'sort_order' =>
            $sortOrder,

        'is_active' =>
            (bool)$isActive
    ]
]);