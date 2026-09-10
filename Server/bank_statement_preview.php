<?php
declare(strict_types=1);
require_once __DIR__.'/bank_import_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('GET');
accounts_endpoint(function(){
 $p=bank_import_plan(production_db(),(int)($_GET['document_id']??0));$page=max(1,(int)($_GET['page']??1));
 $p['rows']=array_slice($p['rows'],($page-1)*100,100);$p['page']=$page;$p['page_size']=100;return $p;
});
