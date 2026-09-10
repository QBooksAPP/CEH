<?php
declare(strict_types=1);
require_once __DIR__.'/bank_reconcile_common.php';
require_once __DIR__.'/bank_row_usage.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$input=production_input();
accounts_endpoint(fn():array=>bank_reconcile_existing(production_db(),$user,$input));
