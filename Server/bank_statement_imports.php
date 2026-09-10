<?php
declare(strict_types=1);
require_once __DIR__.'/bank_workspace_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('GET');
accounts_endpoint(fn():array=>bank_workspace_imports(production_db(),$_GET));
