<?php
declare(strict_types=1);
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/user_common.php';
$admin = qbook_require_user();
qbook_require_role($admin, ['ADMIN']);
if ($_SERVER['REQUEST_METHOD'] !== 'GET') qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
$rows = qbook_db()->query(
    "SELECT id, full_name, username, email, phone, role, is_active, created_at, updated_at
     FROM qbook_users ORDER BY is_active DESC, full_name, id"
)->fetchAll();
$users = array_map(static function (array $row): array {
    return qbook_public_user($row) + ['created_at' => $row['created_at'], 'updated_at' => $row['updated_at']];
}, $rows);
qbook_json(['ok' => true, 'users' => $users]);
