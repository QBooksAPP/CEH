<?php
declare(strict_types=1);
require_once __DIR__.'/bank_import_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');
accounts_endpoint(function()use($user){
 $f=$_FILES['statement']??null;
 if(!$f||$f['error']!==UPLOAD_ERR_OK||!is_uploaded_file($f['tmp_name']))accounts_fail('STATEMENT_UPLOAD_REQUIRED');
 return bank_import_preview(production_db(),$user,(int)($_POST['bank_account_id']??0),$f['name'],$f['tmp_name'],(string)($_POST['adapter']??''));
});
