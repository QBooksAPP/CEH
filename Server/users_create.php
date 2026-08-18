<?php
declare(strict_types=1);
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/user_common.php';
$admin = qbook_require_user();
qbook_require_role($admin, ['ADMIN']);
if ($_SERVER['REQUEST_METHOD'] !== 'POST') qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
$fullName = trim((string)($input['full_name'] ?? ''));
$username = qbook_normalize_username($input['username'] ?? '');
$email = strtolower(trim((string)($input['email'] ?? '')));
$phone = trim((string)($input['phone'] ?? ''));
$password = (string)($input['password'] ?? '');
if ($fullName === '') qbook_json(['ok' => false, 'error' => 'FULL_NAME_REQUIRED'], 422);
qbook_validate_username($username);
if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) qbook_json(['ok' => false, 'error' => 'INVALID_EMAIL'], 422);
if (strlen($password) < 8) qbook_json(['ok' => false, 'error' => 'PASSWORD_MINIMUM_8_CHARACTERS'], 422);
$db = qbook_db();
$duplicate = $db->prepare("SELECT id FROM qbook_users WHERE LOWER(username) = LOWER(?) LIMIT 1");
$duplicate->execute([$username]);
if ($duplicate->fetch()) qbook_json(['ok' => false, 'error' => 'USERNAME_ALREADY_EXISTS'], 409);
if ($email !== '') {
    $duplicate = $db->prepare("SELECT id FROM qbook_users WHERE LOWER(email) = LOWER(?) LIMIT 1");
    $duplicate->execute([$email]);
    if ($duplicate->fetch()) qbook_json(['ok' => false, 'error' => 'EMAIL_ALREADY_EXISTS'], 409);
}
$hash = password_hash($password, PASSWORD_DEFAULT);
if ($hash === false) qbook_json(['ok' => false, 'error' => 'PASSWORD_HASH_FAILED'], 500);
try {
    $stmt = $db->prepare(
        "INSERT INTO qbook_users (full_name, username, email, phone, role, password_hash, is_active)
         VALUES (?, ?, ?, ?, 'OPERATOR', ?, 1)"
    );
    $stmt->execute([$fullName, $username, $email !== '' ? $email : null, $phone !== '' ? $phone : null, $hash]);
    $id = (int)$db->lastInsertId();
    $result = ['id' => $id, 'full_name' => $fullName, 'username' => $username,
        'email' => $email !== '' ? $email : null, 'phone' => $phone !== '' ? $phone : null,
        'role' => 'OPERATOR', 'is_active' => true];
    qbook_audit($admin, 'USER_CREATED', 'USER', $id, [
        'full_name' => $fullName, 'username' => $username, 'email' => $result['email'],
        'role' => 'OPERATOR', 'is_active' => true,
    ]);
    qbook_json(['ok' => true, 'user' => $result], 201);
} catch (PDOException $exception) {
    if ((string)$exception->getCode() === '23000') qbook_json(['ok' => false, 'error' => 'USERNAME_ALREADY_EXISTS'], 409);
    qbook_json(['ok' => false, 'error' => 'SERVER_ERROR'], 500);
}
