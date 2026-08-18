<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
production_require_method('GET');
$where = [];
$params = [];
if ($user['role'] !== 'ADMIN') { $where[] = 'operator_id = ?'; $params[] = (int)$user['id']; }
$status = strtoupper(trim((string)($_GET['status'] ?? '')));
if ($status !== '') { if (!in_array($status, ['OPEN', 'SIGNED'], true)) qbook_json(['ok' => false, 'error' => 'INVALID_STATUS'], 422); $where[] = 'status = ?'; $params[] = $status; }
foreach (['production_date' => 'production_date', 'client' => 'client_name', 'mixer_id' => 'mixer_id'] as $query => $column) {
    $v = trim((string)($_GET[$query] ?? ''));
    if ($v !== '') { $where[] = $query === 'client' ? "$column LIKE ?" : "$column = ?"; $params[] = $query === 'client' ? "%$v%" : $v; }
}
$sql = "SELECT * FROM qbook_production_sessions" . ($where ? ' WHERE ' . implode(' AND ', $where) : '') . " ORDER BY production_date DESC, id DESC LIMIT 200";
$stmt = production_db()->prepare($sql); $stmt->execute($params);
$items = array_map(static function(array $r): array {
    return ['id'=>(int)$r['id'], 'production_date'=>$r['production_date'], 'client_id'=>$r['client_id'] !== null ? (int)$r['client_id'] : null, 'client_name'=>$r['client_name'],
        'project_site'=>$r['project_site'], 'mixer'=>['id'=>(int)$r['mixer_id'], 'code'=>$r['mixer_code_snapshot'], 'name'=>$r['mixer_name_snapshot']],
        'operator'=>['id'=>(int)$r['operator_id'], 'name'=>$r['operator_name_snapshot']], 'status'=>$r['status'], 'signed_at'=>$r['signed_at']];
}, $stmt->fetchAll());
qbook_json(['ok'=>true, 'sessions'=>$items]);
