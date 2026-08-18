<?php
declare(strict_types=1); require __DIR__.'/bootstrap.php'; require __DIR__.'/auth.php';
$u=qbook_require_user(); $t=qbook_bearer_token();
qbook_db()->prepare("UPDATE qbook_auth_tokens SET revoked_at=UTC_TIMESTAMP() WHERE token_hash=? AND user_id=?")->execute([qbook_token_hash($t),$u['id']]);
qbook_json(['ok'=>true]);
