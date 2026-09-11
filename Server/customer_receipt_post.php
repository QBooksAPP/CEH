<?php
declare(strict_types=1);
require_once __DIR__.'/customer_payment_post_common.php';
$user=billing_require_admin();
production_require_method('POST');
$input=production_input();
accounts_endpoint(fn():array => customer_payment_post(production_db(),$user,$input));
