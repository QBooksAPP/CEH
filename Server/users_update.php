<?php
declare(strict_types=1);
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/user_common.php';
$admin = qbook_require_user();
qbook_require_role($admin, ['ADMIN']);
if ($_SERVER['REQUEST_METHOD'] !== 'POST') qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
$id = (int)($input['user_id'] ?? 0);
if ($id <= 0) qbook_json(['ok' => false, 'error' => 'USER_REQUIRED'], 422);
$db = qbook_db();
$stmt = $db->prepare("SELECT id, full_name, username, email, phone, role, is_active FROM qbook_users WHERE id = ? LIMIT 1");
$stmt->execute([$id]);
$existing = $stmt->fetch();
if (!$existing) qbook_json(['ok' => false, 'error' => 'USER_NOT_FOUND'], 404);
$fullName = trim((string)($input['full_name'] ?? $existing['full_name']));
$username = array_key_exists('username', $input) ? qbook_normalize_username($input['username'])
    : ($existing['username'] !== null ? (string)$existing['username'] : '');
$isActive = array_key_exists('is_active', $input) ? (bool)$input['is_active'] : (bool)$existing['is_active'];
$isSelf = (int)$admin['id'] === $id;
if ($fullName === '') qbook_json(['ok' => false, 'error' => 'FULL_NAME_REQUIRED'], 422);
if ($username !== '') qbook_validate_username($username);
if ((string)$existing['role'] === 'OPERATOR' && $username === '') qbook_json(['ok' => false, 'error' => 'USERNAME_REQUIRED'], 422);
if ($isSelf && !$isActive) qbook_json(['ok' => false, 'error' => 'CANNOT_DEACTIVATE_OWN_ACCOUNT'], 409);
if (array_key_exists('role', $input) && strtoupper(trim((string)$input['role'])) !== (string)$existing['role']) {
    qbook_json(['ok' => false, 'error' => $isSelf ? 'CANNOT_REMOVE_OWN_ADMIN_ROLE' : 'ROLE_CHANGE_NOT_ALLOWED'], 409);
}
if ($username !== '') {
    $duplicate = $db->prepare("SELECT id FROM qbook_users WHERE LOWER(username) = LOWER(?) AND id <> ? LIMIT 1");
    $duplicate->execute([$username, $id]);
    if ($duplicate->fetch()) qbook_json(['ok' => false, 'error' => 'USERNAME_ALREADY_EXISTS'], 409);
}
try {
    $db->beginTransaction();
    $db->prepare("UPDATE qbook_users SET full_name = ?, username = ?, is_active = ? WHERE id = ?")
       ->execute([$fullName, $username !== '' ? $username : null, $isActive ? 1 : 0, $id]);
    if (!$isSelf && (bool)$existing['is_active'] && !$isActive) {
        $db->prepare("UPDATE qbook_auth_tokens SET revoked_at = UTC_TIMESTAMP() WHERE user_id = ? AND revoked_at IS NULL")
           ->execute([$id]);
    }
    $db->commit();
    $result = ['id' => $id, 'full_name' => $fullName, 'username' => $username !== '' ? $username : null,
        'email' => $existing['email'], 'phone' => $existing['phone'], 'role' => $existing['role'], 'is_active' => $isActive];
    qbook_audit($admin, 'USER_UPDATED', 'USER', $id, [
        'old_values' => ['full_name' => $existing['full_name'], 'username' => $existing['username'], 'is_active' => (bool)$existing['is_active']],
        'new_values' => ['full_name' => $fullName, 'username' => $result['username'], 'is_active' => $isActive],
    ]);
    qbook_json(['ok' => true, 'user' => $result]);
} catch (Throwable $exception) {
    if ($db->inTransaction()) $db->rollBack();
    if ($exception instanceof PDOException && (string)$exception->getCode() === '23000') qbook_json(['ok' => false, 'error' => 'USERNAME_ALREADY_EXISTS'], 409);
    qbook_json(['ok' => false, 'error' => 'SERVER_ERROR'], 500);
}
