<?php
declare(strict_types=1);

require_once __DIR__ . '/production_log_common.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
production_require_method('POST');
$input = production_input();
$name = production_clean_text($input['name'] ?? '', 150, 'CLIENT_NAME_REQUIRED');
$db = production_db();

$duplicate = $db->prepare("SELECT id FROM qbook_clients WHERE LOWER(name) = LOWER(?) LIMIT 1");
$duplicate->execute([$name]);
if ($duplicate->fetch()) {
    qbook_json(['ok' => false, 'error' => 'CLIENT_NAME_EXISTS'], 409);
}

$stmt = $db->prepare("INSERT INTO qbook_clients (name, is_active) VALUES (?, 1)");
$stmt->execute([$name]);
$id = (int)$db->lastInsertId();
qbook_audit($user, 'CLIENT_CREATED', 'CLIENT', $id, ['name' => $name]);
qbook_json(['ok' => true, 'client' => ['id' => $id, 'name' => $name, 'is_active' => true]], 201);
