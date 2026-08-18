<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
production_require_method('POST');
$in = production_input();
$date = (string)($in['production_date'] ?? '');
$parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $date);
if (!$parsed || $parsed->format('Y-m-d') !== $date) qbook_json(['ok' => false, 'error' => 'INVALID_PRODUCTION_DATE'], 422);
$mixerId = (int)($in['mixer_id'] ?? 0);
$db = production_db();
$stmt = $db->prepare("SELECT id, code, name FROM qbook_mixers WHERE id = ? AND is_active = 1");
$stmt->execute([$mixerId]);
$mixer = $stmt->fetch();
if (!$mixer) qbook_json(['ok' => false, 'error' => 'INVALID_MIXER'], 422);
$values = [
    $date,
    production_clean_text($in['client_name'] ?? '', 150, 'CLIENT_REQUIRED'),
    production_clean_text($in['project_site'] ?? '', 200, 'PROJECT_SITE_REQUIRED'),
    $mixerId, $mixer['code'], $mixer['name'],
    production_clean_text($in['loading_point'] ?? '', 200, 'LOADING_POINT_REQUIRED'),
    production_clean_text($in['discharge_point'] ?? '', 200, 'DISCHARGE_POINT_REQUIRED'),
    (int)$user['id'], $user['full_name'],
    production_clean_text($in['notes'] ?? '', 2000, 'NOTES_TOO_LONG', false),
];
$stmt = $db->prepare("INSERT INTO qbook_production_sessions (production_date, client_name, project_site, mixer_id, mixer_code_snapshot, mixer_name_snapshot, loading_point, discharge_point, operator_id, operator_name_snapshot, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
$stmt->execute($values);
$id = (int)$db->lastInsertId();
qbook_audit($user, 'PRODUCTION_SESSION_CREATED', 'PRODUCTION_SESSION', $id, ['mixer_id' => $mixerId]);
qbook_json(['ok' => true, 'session' => production_payload($db, production_session_row($db, $id))], 201);
