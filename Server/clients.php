<?php
declare(strict_types=1);

require_once __DIR__ . '/production_log_common.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
production_require_method('GET');

$activeOnly = $user['role'] !== 'ADMIN' || (string)($_GET['active_only'] ?? '') === '1';
$sql = "SELECT id, name, is_active, created_at, updated_at
        FROM qbook_clients" . ($activeOnly ? " WHERE is_active = 1" : "") . "
        ORDER BY name";
$rows = production_db()->query($sql)->fetchAll();

$clients = array_map(static fn(array $row): array => [
    'id' => (int)$row['id'],
    'name' => (string)$row['name'],
    'is_active' => (bool)$row['is_active'],
    'created_at' => $row['created_at'],
    'updated_at' => $row['updated_at'],
], $rows);

qbook_json(['ok' => true, 'clients' => $clients]);
