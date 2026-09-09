<?php
declare(strict_types=1);
require_once __DIR__.'/credit_note_common.php';
$user=billing_require_admin();production_require_method('POST');$input=production_input();
accounts_endpoint(fn():array=>credit_note_issue_execute(production_db(),$user,$input));
