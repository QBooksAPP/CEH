<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
$user = qbook_require_user(); qbook_require_role($user, ['ADMIN', 'OPERATOR']); production_require_method('GET');
$db = production_db(); $row = production_session_row($db, (int)($_GET['session_id'] ?? 0));
if (!production_can_access($user, $row)) qbook_json(['ok'=>false, 'error'=>'FORBIDDEN'], 403);
qbook_json(['ok'=>true, 'session'=>production_payload($db, $row, true)]);
