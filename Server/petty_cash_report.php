<?php
declare(strict_types=1);
require_once __DIR__.'/reports_common.php';
$user=billing_require_admin();production_require_method('GET');
accounts_endpoint(fn():array=>reports_expense_rows(production_db(),reports_filters($_GET),true));
