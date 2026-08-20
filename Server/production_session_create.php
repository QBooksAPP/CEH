<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
require_once __DIR__ . '/job_context.php';
$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
production_require_method('POST');
$in = production_input();
$date = (string)($in['production_date'] ?? '');
$parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $date);
if (!$parsed || $parsed->format('Y-m-d') !== $date) qbook_json(['ok' => false, 'error' => 'INVALID_PRODUCTION_DATE'], 422);
$mixerId = (int)($in['mixer_id'] ?? 0);
$clientId = (int)($in['client_id'] ?? 0);
$projectId = (int)($in['project_id'] ?? 0);
$db = production_db();
$stmt = $db->prepare("SELECT id, name FROM qbook_clients WHERE id = ? AND is_active = 1");
$stmt->execute([$clientId]);
$client = $stmt->fetch();
if (!$client) qbook_json(['ok' => false, 'error' => 'ACTIVE_CLIENT_REQUIRED'], 422);
$stmt=$db->prepare("SELECT id,name FROM qbook_projects WHERE id=? AND client_id=? AND is_active=1");
$stmt->execute([$projectId,$clientId]); $project=$stmt->fetch();
if(!$project) qbook_json(['ok'=>false,'error'=>'ACTIVE_CLIENT_PROJECT_REQUIRED'],422);
$stmt = $db->prepare("SELECT id, code, name FROM qbook_mixers WHERE id = ? AND is_active = 1");
$stmt->execute([$mixerId]);
$mixer = $stmt->fetch();
if (!$mixer) qbook_json(['ok' => false, 'error' => 'INVALID_MIXER'], 422);
try { qbook_require_project_mixer($db, $projectId, $mixerId); }
catch (RuntimeException $e) {
    qbook_json(['ok'=>false,'error'=>$e->getMessage()],409);
}
$values = [
    $date,
    $clientId,
    $projectId,
    $client['name'],
    $project['name'],
    $mixerId, $mixer['code'], $mixer['name'],
    '',
    '',
    (int)$user['id'], $user['full_name'],
    production_clean_text($in['notes'] ?? '', 2000, 'NOTES_TOO_LONG', false),
];
$stmt = $db->prepare("INSERT INTO qbook_production_sessions (production_date, client_id, project_id, client_name, project_site, mixer_id, mixer_code_snapshot, mixer_name_snapshot, loading_point, discharge_point, operator_id, operator_name_snapshot, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
$stmt->execute($values);
$id = (int)$db->lastInsertId();
qbook_audit($user, 'PRODUCTION_SESSION_CREATED', 'PRODUCTION_SESSION', $id, ['client_id' => $clientId, 'project_id'=>$projectId, 'mixer_id' => $mixerId]);
qbook_json(['ok' => true, 'session' => production_payload($db, production_session_row($db, $id))], 201);
