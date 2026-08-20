<?php
declare(strict_types=1);

require_once __DIR__ . '/production_log_common.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
production_require_method('POST');
$input = production_input();
$id = (int)($input['client_id'] ?? 0);
$name = production_clean_text($input['name'] ?? '', 150, 'CLIENT_NAME_REQUIRED');
$isActive = filter_var($input['is_active'] ?? null, FILTER_VALIDATE_BOOL, FILTER_NULL_ON_FAILURE);
if ($id <= 0 || $isActive === null) {
    qbook_json(['ok' => false, 'error' => 'INVALID_CLIENT'], 422);
}

$db = production_db();
$existing = $db->prepare("SELECT id, name, is_active FROM qbook_clients WHERE id = ?");
$existing->execute([$id]);
$before = $existing->fetch();
if (!$before) {
    qbook_json(['ok' => false, 'error' => 'CLIENT_NOT_FOUND'], 404);
}
$duplicate = $db->prepare("SELECT id FROM qbook_clients WHERE LOWER(name) = LOWER(?) AND id <> ? LIMIT 1");
$duplicate->execute([$name, $id]);
if ($duplicate->fetch()) {
    qbook_json(['ok' => false, 'error' => 'CLIENT_NAME_EXISTS'], 409);
}

$db->prepare("UPDATE qbook_clients SET name=?,is_active=?,
    archived_at=IF(?=1,NULL,UTC_TIMESTAMP()),archived_by=IF(?=1,NULL,?) WHERE id=?")
   ->execute([$name,$isActive?1:0,$isActive?1:0,$isActive?1:0,(int)$user['id'],$id]);
qbook_audit($user, 'CLIENT_UPDATED', 'CLIENT', $id, [
    'old_name' => $before['name'], 'name' => $name,
    'old_is_active' => (bool)$before['is_active'], 'is_active' => $isActive,
]);
qbook_json(['ok' => true, 'client' => ['id' => $id, 'name' => $name, 'is_active' => $isActive]]);
