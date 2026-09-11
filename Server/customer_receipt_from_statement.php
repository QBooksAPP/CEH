<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';
$user=billing_require_admin();
production_require_method('POST');
// The legacy direct-AR shortcut cannot represent the current allocation/WHT
// contract. Fail closed; only the reviewed draft/post lifecycle may post.
accounts_endpoint(function():array {accounts_fail('USE_STATEMENT_CLIENT_PAYMENT_WORKFLOW',409);});
