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
$newPassword = (string)($input['new_password'] ?? '');

if ($targetUserId <= 0) {
    qbook_json([
        'ok' => false,
        'error' => 'USER_REQUIRED'
    ], 400);
}

if (strlen($newPassword) < 8) {
    qbook_json([
        'ok' => false,
        'error' => 'PASSWORD_MINIMUM_8_CHARACTERS'
    ], 400);
}

$db = qbook_db();

/*
 * Confirm user exists.
 */
$stmt = $db->prepare(
    "SELECT
        id,
        full_name,
        username,
        email,
        role,
        is_active
     FROM qbook_users
     WHERE id = ?
     LIMIT 1"
);

$stmt->execute([$targetUserId]);
$target = $stmt->fetch();

if (!$target) {
    qbook_json([
        'ok' => false,
        'error' => 'USER_NOT_FOUND'
    ], 404);
}

/*
 * Create a new password hash compatible with login.php.
 */
$passwordHash = password_hash(
    $newPassword,
    PASSWORD_DEFAULT
);

if ($passwordHash === false) {
    qbook_json([
        'ok' => false,
        'error' => 'PASSWORD_HASH_FAILED'
    ], 500);
}

try {

    $db->beginTransaction();

    /*
     * Replace password.
     */
    $stmt = $db->prepare(
        "UPDATE qbook_users
         SET
            password_hash = ?,
            updated_at = CURRENT_TIMESTAMP
         WHERE id = ?"
    );

    $stmt->execute([
        $passwordHash,
        $targetUserId
    ]);

    /*
     * Revoke ALL existing sessions for this account.
     *
     * This is important: after an ADMIN resets someone's
     * password, a phone already logged into the old account
     * should no longer remain authenticated.
     */
    $stmt = $db->prepare(
        "UPDATE qbook_auth_tokens
         SET revoked_at = UTC_TIMESTAMP()
         WHERE user_id = ?
           AND revoked_at IS NULL"
    );

    $stmt->execute([$targetUserId]);

    $db->commit();

    /*
     * Never audit the password or its hash.
     */
    qbook_audit(
        $user,
        'USER_PASSWORD_RESET',
        'USER',
        $targetUserId,
        [
            'full_name' =>
                $target['full_name'],

            'email' =>
                $target['email'],

            'username' =>
                $target['username'],

            'role' =>
                $target['role'],

            'sessions_revoked' =>
                true
        ]
    );

    qbook_json([
        'ok' => true,
        'user_id' => $targetUserId,
        'message' => 'Password reset successfully. Existing sessions have been revoked.'
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
