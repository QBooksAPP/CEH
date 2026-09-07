<?php
declare(strict_types=1);
require_once __DIR__.'/invoice_void_common.php';
$user=billing_require_admin();
production_require_method('POST');
$input=production_input();
accounts_endpoint(fn():array=>invoice_void_execute(production_db(),$user,$input));
