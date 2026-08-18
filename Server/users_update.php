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

$input = json_decode(
    file_get_contents('php://input'),
    true
);

if (!is_array($input)) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_JSON'
    ], 400);
}

$targetUserId = (int)($input['user_id'] ?? 0);

if ($targetUserId <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'USER_REQUIRED'
    ], 400);
}

$db = qbook_db();

/*
 * Load existing user.
 */
$stmt = $db->prepare(
    "SELECT
        id,
        full_name,
        email,
        phone,
        role,
        is_active
     FROM qbook_users
     WHERE id = ?
     LIMIT 1"
);

$stmt->execute([$targetUserId]);
$existing = $stmt->fetch();

if (!$existing) {
    qbook_json([
        'ok' => false,
        'error' => 'USER_NOT_FOUND'
    ], 404);
}

/*
 * Fields not supplied keep their existing values.
 */
$fullName = array_key_exists('full_name', $input)
    ? trim((string)$input['full_name'])
    : (string)$existing['full_name'];

$email = array_key_exists('email', $input)
    ? strtolower(trim((string)$input['email']))
    : strtolower((string)$existing['email']);

$phone = array_key_exists('phone', $input)
    ? trim((string)$input['phone'])
    : (string)($existing['phone'] ?? '');

$role = array_key_exists('role', $input)
    ? strtoupper(trim((string)$input['role']))
    : (string)$existing['role'];

$isActive = array_key_exists('is_active', $input)
    ? ((bool)$input['is_active'] ? 1 : 0)
    : (int)$existing['is_active'];

/*
 * Validation.
 */
if ($fullName === '') {
    qbook_json([
        'ok' => false,
        'error' => 'FULL_NAME_REQUIRED'
    ], 400);
}

if (
    $email === '' ||
    !filter_var($email, FILTER_VALIDATE_EMAIL)
) {
    qbook_json([
        'ok' => false,
        'error' => 'VALID_EMAIL_REQUIRED'
    ], 400);
}

if (!in_array(
    $role,
    ['ADMIN', 'SUPERVISOR', 'OPERATOR'],
    true
)) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_ROLE'
    ], 400);
}

/*
 * Protect the currently logged-in ADMIN from
 * accidentally locking themselves out.
 */
$isSelf =
    ((int)$user['id'] === $targetUserId);

if ($isSelf && $isActive === 0) {
    qbook_json([
        'ok' => false,
        'error' => 'CANNOT_DEACTIVATE_OWN_ACCOUNT'
    ], 409);
}

if ($isSelf && $role !== 'ADMIN') {
    qbook_json([
        'ok' => false,
        'error' => 'CANNOT_REMOVE_OWN_ADMIN_ROLE'
    ], 409);
}

/*
 * Prevent duplicate email address on another user.
 */
$stmt = $db->prepare(
    "SELECT id
     FROM qbook_users
     WHERE LOWER(email) = ?
       AND id <> ?
     LIMIT 1"
);

$stmt->execute([
    $email,
    $targetUserId
]);

if ($stmt->fetch()) {
    qbook_json([
        'ok' => false,
        'error' => 'EMAIL_ALREADY_EXISTS'
    ], 409);
}

try {

    $db->beginTransaction();

    $stmt = $db->prepare(
        "UPDATE qbook_users
         SET
            full_name = ?,
            email = ?,
            phone = ?,
            role = ?,
            is_active = ?,
            updated_at = CURRENT_TIMESTAMP
         WHERE id = ?"
    );

    $stmt->execute([
        $fullName,
        $email,
        $phone !== '' ? $phone : null,
        $role,
        $isActive,
        $targetUserId
    ]);

    /*
     * If another user's account is deactivated,
     * revoke all existing login tokens immediately.
     */
    if (
        !$isSelf &&
        (int)$existing['is_active'] === 1 &&
        $isActive === 0
    ) {
        $stmt = $db->prepare(
            "UPDATE qbook_auth_tokens
             SET revoked_at = UTC_TIMESTAMP()
             WHERE user_id = ?
               AND revoked_at IS NULL"
        );

        $stmt->execute([$targetUserId]);
    }

    $db->commit();

    /*
     * Audit the user change.
     * Never log passwords or password hashes.
     */
    qbook_audit(
        $user,
        'USER_UPDATED',
        'USER',
        $targetUserId,
        [
            'old_values' => [
                'full_name' =>
                    $existing['full_name'],

                'email' =>
                    $existing['email'],

                'phone' =>
                    $existing['phone'],

                'role' =>
                    $existing['role'],

                'is_active' =>
                    (bool)$existing['is_active']
            ],

            'new_values' => [
                'full_name' =>
                    $fullName,

                'email' =>
                    $email,

                'phone' =>
                    $phone !== '' ? $phone : null,

                'role' =>
                    $role,

                'is_active' =>
                    (bool)$isActive
            ]
        ]
    );

    /*
     * Separate audit events for especially important
     * permission/status changes.
     */
    if (
        (string)$existing['role'] !== $role
    ) {
        qbook_audit(
            $user,
            'USER_ROLE_CHANGED',
            'USER',
            $targetUserId,
            [
                'old_role' =>
                    $existing['role'],

                'new_role' =>
                    $role
            ]
        );
    }

    if (
        (int)$existing['is_active'] === 0 &&
        $isActive === 1
    ) {
        qbook_audit(
            $user,
            'USER_ACTIVATED',
            'USER',
            $targetUserId,
            [
                'full_name' =>
                    $fullName,

                'role' =>
                    $role
            ]
        );
    }

    if (
        (int)$existing['is_active'] === 1 &&
        $isActive === 0
    ) {
        qbook_audit(
            $user,
            'USER_DEACTIVATED',
            'USER',
            $targetUserId,
            [
                'full_name' =>
                    $fullName,

                'role' =>
                    $role
            ]
        );
    }

    qbook_json([
        'ok' => true,

        'user' => [
            'id' =>
                $targetUserId,

            'full_name' =>
                $fullName,

            'email' =>
                $email,

            'phone' =>
                $phone !== '' ? $phone : null,

            'role' =>
                $role,

            'is_active' =>
                (bool)$isActive
        ]
    ]);

} catch (Throwable $e) {

    if ($db->inTransaction()) {
        $db->rollBack();
    }

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}