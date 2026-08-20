<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
production_require_method('GET');
$clientId = (int)($_GET['client_id'] ?? 0);
if ($clientId <= 0) qbook_json(['ok' => false, 'error' => 'CLIENT_REQUIRED'], 422);
$filter=strtoupper((string)($_GET['status']??''));
if($user['role']==='ADMIN' && $filter!=='' && !in_array($filter,['ACTIVE','ARCHIVED','ALL'],true)){
    qbook_json(['ok'=>false,'error'=>'INVALID_LIFECYCLE_FILTER'],422);
}
$activeOnly = $user['role'] !== 'ADMIN' || (string)($_GET['active_only'] ?? '') === '1';
$lifecycle=$user['role']!=='ADMIN'||$activeOnly||$filter==='ACTIVE'
    ? " AND p.is_active=1 AND p.archived_at IS NULL AND c.is_active=1 AND c.archived_at IS NULL"
    : ($filter==='ARCHIVED'?" AND p.archived_at IS NOT NULL":"");
$sql = "SELECT p.id, p.client_id, p.name, p.is_active, p.archived_at, p.archived_by, p.created_at, p.updated_at
        FROM qbook_projects p JOIN qbook_clients c ON c.id = p.client_id
        WHERE p.client_id = ?" . $lifecycle . " ORDER BY p.name";
$stmt = production_db()->prepare($sql); $stmt->execute([$clientId]);
$projects = array_map(static fn(array $r): array => [
    'id'=>(int)$r['id'], 'client_id'=>(int)$r['client_id'], 'name'=>(string)$r['name'],
    'is_active'=>(bool)$r['is_active'], 'created_at'=>$r['created_at'], 'updated_at'=>$r['updated_at'],
    'archived_at'=>$r['archived_at'], 'archived_by'=>$r['archived_by']===null?null:(int)$r['archived_by'],
], $stmt->fetchAll());
qbook_json(['ok'=>true, 'projects'=>$projects]);
