<?php
declare(strict_types=1);

require_once __DIR__ . '/production_log_common.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
production_require_method('GET');

$filter = strtoupper((string)($_GET['status'] ?? ''));
if($user['role']==='ADMIN' && $filter!=='' && !in_array($filter,['ACTIVE','ARCHIVED','ALL'],true)){
    qbook_json(['ok'=>false,'error'=>'INVALID_LIFECYCLE_FILTER'],422);
}
$activeOnly = $user['role'] !== 'ADMIN' || (string)($_GET['active_only'] ?? '') === '1';
$where = $user['role'] !== 'ADMIN' || $activeOnly || $filter === 'ACTIVE'
    ? " WHERE is_active=1 AND archived_at IS NULL"
    : ($filter === 'ARCHIVED' ? " WHERE archived_at IS NOT NULL" : "");
$sql = "SELECT id, name, is_active, archived_at, archived_by, created_at, updated_at
        FROM qbook_clients" . $where . "
        ORDER BY name";
$rows = production_db()->query($sql)->fetchAll();

$clients = array_map(static fn(array $row): array => [
    'id' => (int)$row['id'],
    'name' => (string)$row['name'],
    'is_active' => (bool)$row['is_active'],
    'archived_at' => $row['archived_at'],
    'archived_by' => $row['archived_by']===null?null:(int)$row['archived_by'],
    'created_at' => $row['created_at'],
    'updated_at' => $row['updated_at'],
], $rows);

qbook_json(['ok' => true, 'clients' => $clients]);
