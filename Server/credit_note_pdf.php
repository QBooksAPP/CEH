<?php
declare(strict_types=1);
require_once __DIR__.'/credit_note_common.php';
require_once __DIR__.'/credit_note_pdf_common.php';
$user=billing_require_admin();production_require_method('GET');
try{
 $db=production_db();$id=(int)($_GET['id']??0);
 $rows=credit_note_rows($db,"SELECT * FROM qbook_credit_notes WHERE id=? AND status='ISSUED'",[$id]);
 if(!$rows)accounts_fail('CREDIT_NOTE_NOT_FOUND',404);$note=$rows[0];$note['reference']=billing_ref('CREDIT_NOTE',$note['reference_no']);
 if(empty($note['document_snapshot']))accounts_fail('CREDIT_NOTE_DOCUMENT_SNAPSHOT_MISSING',409);
 $bytes=credit_note_pdf_bytes($note,json_decode($note['document_snapshot'],true,512,JSON_THROW_ON_ERROR),(string)($user['date_format']??'DD-MM-YYYY'));
 production_discard_output();header('Content-Type: application/pdf');header('Cache-Control: no-store');header('Content-Disposition: attachment; filename="'.$note['reference'].'.pdf"');header('Content-Length: '.strlen($bytes));echo $bytes;
}catch(AccountsApiError $e){production_discard_output();qbook_json(['ok'=>false,'error'=>$e->errorCode],$e->httpStatus);}
catch(Throwable $e){error_log('CEH Credit Note PDF failed type='.get_class($e));production_discard_output();qbook_json(['ok'=>false,'error'=>'CREDIT_NOTE_PDF_FAILED'],500);}
