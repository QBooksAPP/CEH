<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json([
        'ok' => false,
        'error' => 'METHOD_NOT_ALLOWED'
    ], 405);
}

$db = qbook_db();

$stmt = $db->query(
    "SELECT
        id,
        full_name,
        email,
        phone,
        role,
        is_active,
        created_at,
        updated_at
     FROM qbook_users
     ORDER BY
        is_active DESC,
        full_name ASC,
        id ASC"
);

$rows = $stmt->fetchAll();

$users = [];

foreach ($rows as $row) {
    $users[] = [
        'id' => (int)$row['id'],
        'full_name' => $row['full_name'],
        'email' => $row['email'],
        'phone' => $row['phone'],
        'role' => $row['role'],
        'is_active' => (bool)$row['is_active'],
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at']
    ];
}

qbook_json([
    'ok' => true,
    'users' => $users
]);