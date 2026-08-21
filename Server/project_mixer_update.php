<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}
$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
$projectId = (int)($input['project_id'] ?? 0);
$mixerId = (int)($input['mixer_id'] ?? 0);
$active = filter_var($input['is_active'] ?? true, FILTER_VALIDATE_BOOLEAN);
if ($projectId <= 0 || $mixerId <= 0) {
    qbook_json(['ok' => false, 'error' => 'PROJECT_AND_MIXER_REQUIRED'], 422);
}
$db = qbook_db();
$stmt = $db->prepare(
    "SELECT p.id FROM qbook_projects p
     JOIN qbook_clients c ON c.id=p.client_id
     JOIN qbook_mixers m ON m.id=?
     WHERE p.id=? AND p.is_active=1 AND p.archived_at IS NULL
       AND c.is_active=1 AND c.archived_at IS NULL
       AND m.is_active=1 LIMIT 1"
);
$stmt->execute([$mixerId, $projectId]);
if (!$stmt->fetch()) qbook_json(['ok' => false, 'error' => 'PROJECT_OR_MIXER_NOT_FOUND'], 404);
$db->beginTransaction();
try {
$lock=$db->prepare("SELECT id FROM qbook_mixers WHERE id=? FOR UPDATE");
$lock->execute([$mixerId]);
if ($active) {
    /* One current assignment per mixer; prior rows remain inactive history. */
    $db->prepare("UPDATE qbook_project_mixers SET is_active=0,
        assigned_by=?,updated_at=UTC_TIMESTAMP()
        WHERE mixer_id=? AND project_id<>? AND is_active=1")
       ->execute([(int)$user['id'],$mixerId,$projectId]);
}
$stmt = $db->prepare(
    "INSERT INTO qbook_project_mixers
       (project_id,mixer_id,is_active,assigned_by,created_at,updated_at)
     VALUES(?,?,?,?,UTC_TIMESTAMP(),UTC_TIMESTAMP())
     ON DUPLICATE KEY UPDATE is_active=VALUES(is_active),
       assigned_by=VALUES(assigned_by),updated_at=UTC_TIMESTAMP()"
);
$stmt->execute([$projectId, $mixerId, $active ? 1 : 0, (int)$user['id']]);
qbook_audit($user, 'PROJECT_MIXER_ALLOCATION_UPDATED', 'PROJECT', $projectId,
    ['mixer_id' => $mixerId, 'is_active' => $active]);
$db->commit();
} catch (Throwable $e) {
    if ($db->inTransaction()) $db->rollBack();
    qbook_json(['ok'=>false,'error'=>'SERVER_ERROR'],500);
}
qbook_json(['ok' => true, 'project_id' => $projectId, 'mixer_id' => $mixerId,
    'is_active' => $active]);
