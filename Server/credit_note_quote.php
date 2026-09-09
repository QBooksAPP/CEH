<?php
declare(strict_types=1);
require_once __DIR__.'/credit_note_common.php';
$user=billing_require_admin();production_require_method('POST');$input=production_input();
accounts_endpoint(function()use($input):array{
 $input=credit_note_input($input);
 $db=production_db();$db->exec('START TRANSACTION READ ONLY');
 try{$plan=credit_note_plan($db,$input);$db->commit();return ['quote'=>$plan];}
 catch(Throwable $e){if($db->inTransaction())$db->rollBack();throw $e;}
});
