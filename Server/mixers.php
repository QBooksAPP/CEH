<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR', 'VIEWER']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$projectId = (int)($_GET['project_id'] ?? 0);
$includeAllocation = ($_GET['include_allocation'] ?? '') === '1';
if ($includeAllocation && $user['role'] !== 'ADMIN') {
    qbook_json(['ok' => false, 'error' => 'FORBIDDEN'], 403);
}
$db = qbook_db();
if ($projectId > 0 && !$includeAllocation) {
    $stmt = $db->prepare(
        "SELECT m.id,m.code,m.name,m.notes,1 AS is_allocated
         FROM qbook_project_mixers pm JOIN qbook_mixers m ON m.id=pm.mixer_id
         JOIN qbook_projects p ON p.id=pm.project_id
         JOIN qbook_clients c ON c.id=p.client_id
         WHERE pm.project_id=? AND pm.is_active=1 AND m.is_active=1 AND p.is_active=1
           AND p.archived_at IS NULL AND c.is_active=1 AND c.archived_at IS NULL
         ORDER BY m.code"
    );
    $stmt->execute([$projectId]);
} elseif ($projectId > 0) {
    $stmt = $db->prepare(
        "SELECT m.id,m.code,m.name,m.notes,COALESCE(pm.is_active,0) AS is_allocated
         FROM qbook_mixers m LEFT JOIN qbook_project_mixers pm
           ON pm.mixer_id=m.id AND pm.project_id=?
         WHERE m.is_active=1 ORDER BY m.code"
    );
    $stmt->execute([$projectId]);
} else {
    $stmt = $db->query(
        "SELECT id,code,name,notes,0 AS is_allocated FROM qbook_mixers
         WHERE is_active=1 ORDER BY code"
    );
}

$mixers = [];

foreach ($stmt->fetchAll() as $row) {
    $mixers[] = [
        'id' => (int)$row['id'],
        'code' => (string)$row['code'],
        'name' => (string)$row['name'],
        'notes' => $row['notes'],
        'is_allocated' => (bool)$row['is_allocated'],
    ];
}

qbook_json([
    'ok' => true,
    'mixers' => $mixers,
]);
