<?php
declare(strict_types=1);
require_once __DIR__.'/bank_import_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$input=production_input();
// Never accept caller-normalized rows/hash as evidence of source identity.
accounts_endpoint(fn():array=>bank_import_commit(production_db(),$user,(int)($input['document_id']??0),(string)($input['confirmation_sha256']??'')));
