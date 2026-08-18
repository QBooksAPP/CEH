<?php
declare(strict_types=1); require __DIR__.'/bootstrap.php'; require __DIR__.'/auth.php';
$u=qbook_require_user(); $u['id']=(int)$u['id']; $u['is_active']=(bool)$u['is_active'];
qbook_json(['ok'=>true,'user'=>$u]);
