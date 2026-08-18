<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/user_common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
$input = json_decode(file_get_contents('php://input'), true) ?: [];
// Keep accepting `email` while installed pre-v1.5 apps are upgraded.
$login = trim((string)($input['login'] ?? $input['email'] ?? ''));
$password = (string)($input['password'] ?? '');
if ($login === '' || $password === '') qbook_json(['ok' => false, 'error' => 'LOGIN_AND_PASSWORD_REQUIRED'], 400);

$db = qbook_db();
$stmt = $db->prepare(
    "SELECT id, full_name, username, email, phone, role, password_hash, is_active
     FROM qbook_users
     WHERE LOWER(username) = LOWER(?) OR LOWER(email) = LOWER(?)
     LIMIT 1"
);
$stmt->execute([$login, $login]);
$user = $stmt->fetch();
if (!$user || !(bool)$user['is_active'] || empty($user['password_hash']) ||
    !password_verify($password, (string)$user['password_hash'])) {
    qbook_json(['ok' => false, 'error' => 'INVALID_CREDENTIALS'], 401);
}

if (password_needs_rehash((string)$user['password_hash'], PASSWORD_DEFAULT)) {
    $newHash = password_hash($password, PASSWORD_DEFAULT);
    if ($newHash !== false) {
        $db->prepare("UPDATE qbook_users SET password_hash = ? WHERE id = ?")
           ->execute([$newHash, (int)$user['id']]);
    }
}

$token = bin2hex(random_bytes(32));
$expires = gmdate('Y-m-d H:i:s', time() + 2592000);
$db->prepare("INSERT INTO qbook_auth_tokens(user_id, token_hash, expires_at, created_ip, user_agent) VALUES (?, ?, ?, ?, ?)")
   ->execute([(int)$user['id'], qbook_token_hash($token), $expires, qbook_client_ip(), substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 255)]);
qbook_json([
    'ok' => true, 'token' => $token, 'tokenType' => 'Bearer', 'expiresAt' => $expires . 'Z',
    'user' => qbook_public_user($user),
]);
