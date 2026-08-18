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

/*
 * Input
 */
$fullName = trim(
    (string)($input['full_name'] ?? '')
);

$email = strtolower(trim(
    (string)($input['email'] ?? '')
));

$phone = trim(
    (string)($input['phone'] ?? '')
);

$role = strtoupper(trim(
    (string)($input['role'] ?? '')
));

$password = (string)(
    $input['password'] ?? ''
);

$isActive = array_key_exists('is_active', $input)
    ? ((bool)$input['is_active'] ? 1 : 0)
    : 1;

/*
 * Validation
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
 * Require a reasonable initial password.
 */
if (strlen($password) < 8) {
    qbook_json([
        'ok' => false,
        'error' => 'PASSWORD_MINIMUM_8_CHARACTERS'
    ], 400);
}

$db = qbook_db();

/*
 * Prevent duplicate email addresses.
 */
$stmt = $db->prepare(
    "SELECT id
     FROM qbook_users
     WHERE LOWER(email) = ?
     LIMIT 1"
);

$stmt->execute([$email]);

if ($stmt->fetch()) {
    qbook_json([
        'ok' => false,
        'error' => 'EMAIL_ALREADY_EXISTS'
    ], 409);
}

/*
 * Generate password using the same PHP password system
 * expected by login.php / password_verify().
 */
$passwordHash = password_hash(
    $password,
    PASSWORD_DEFAULT
);

if ($passwordHash === false) {
    qbook_json([
        'ok' => false,
        'error' => 'PASSWORD_HASH_FAILED'
    ], 500);
}

try {

    $stmt = $db->prepare(
        "INSERT INTO qbook_users
        (
            full_name,
            email,
            phone,
            role,
            password_hash,
            is_active
        )
        VALUES (?, ?, ?, ?, ?, ?)"
    );

    $stmt->execute([
        $fullName,
        $email,
        $phone !== '' ? $phone : null,
        $role,
        $passwordHash,
        $isActive
    ]);

    $newUserId = (int)$db->lastInsertId();

    /*
     * Never place the password or password hash
     * in the audit log.
     */
    qbook_audit(
        $user,
        'USER_CREATED',
        'USER',
        $newUserId,
        [
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
    );

    qbook_json([
        'ok' => true,

        'user' => [
            'id' =>
                $newUserId,

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
    ], 201);

} catch (PDOException $e) {

    qbook_json([
        'ok' => false,
        'error' => 'SERVER_ERROR'
    ], 500);
}