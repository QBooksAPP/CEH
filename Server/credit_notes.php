<?php
declare(strict_types=1);
require_once __DIR__.'/credit_note_common.php';
$user=billing_require_admin();production_require_method('GET');
accounts_endpoint(function()use($user):array{
 $db=production_db();
 if(isset($_GET['request_key'])){
  $key=(string)$_GET['request_key'];if(!preg_match('/\A[a-zA-Z0-9-]{32,80}\z/',$key))accounts_fail('IDEMPOTENCY_KEY_REQUIRED');
  $r=credit_note_rows($db,'SELECT result_json FROM qbook_credit_note_requests WHERE actor_id=? AND request_key=?',[$user['id'],$key]);
  return ['completed'=>(bool)$r,'result'=>$r?json_decode($r[0]['result_json'],true,512,JSON_THROW_ON_ERROR):null];
 }
 if(($id=(int)($_GET['id']??0))>0){
  $rows=credit_note_rows($db,'SELECT c.*,u.full_name issued_by_name,j.reference_no journal_reference,i.reference_no invoice_reference_no,i.client_name_snapshot client FROM qbook_credit_notes c JOIN qbook_invoices i ON i.id=c.invoice_id LEFT JOIN qbook_users u ON u.id=c.issued_by LEFT JOIN qbook_financial_journals j ON j.id=c.journal_id WHERE c.id=?',[$id]);
  if(!$rows)accounts_fail('CREDIT_NOTE_NOT_FOUND',404);$c=$rows[0];$c['reference']=billing_ref('CREDIT_NOTE',$c['reference_no']);$c['invoice_reference']=billing_ref('INVOICE',$c['invoice_reference_no']);
  $c['document']=$c['document_snapshot']?json_decode($c['document_snapshot'],true,512,JSON_THROW_ON_ERROR):null;unset($c['document_snapshot']);
  $c['lines']=credit_note_rows($db,'SELECT * FROM qbook_credit_note_lines WHERE credit_note_id=? ORDER BY line_no',[$id]);
  $c['production_releases']=credit_note_rows($db,'SELECT r.*,a.report_reference_snapshot FROM qbook_credit_note_production_releases r JOIN qbook_credit_note_lines l ON l.id=r.credit_note_line_id JOIN qbook_invoice_production_allocations a ON a.id=r.invoice_production_allocation_id WHERE l.credit_note_id=? ORDER BY r.id',[$id]);
  $c['evidence']=credit_note_rows($db,"SELECT id,original_filename,mime_type,byte_size,sha256,uploaded_at FROM qbook_financial_evidence WHERE source_type='CREDIT_NOTE' AND source_record_id=? ORDER BY id",[$id]);
  $i=billing_invoice_outstanding($db,(int)$c['invoice_id']);$c['current_invoice_outstanding']=accounts_minor_decimal($i['outstanding_minor']);return ['credit_note'=>$c];
 }
 $invoiceId=(int)($_GET['invoice_id']??0);if($invoiceId<=0)accounts_fail('INVOICE_REQUIRED');
 $db->exec('START TRANSACTION READ ONLY');
 try{$contract=credit_note_contract($db,$invoiceId);$notes=credit_note_rows($db,'SELECT id,reference_no,credit_date,reason,total_amount,journal_id,status FROM qbook_credit_notes WHERE invoice_id=? ORDER BY id DESC',[$invoiceId]);foreach($notes as &$n)$n['reference']=billing_ref('CREDIT_NOTE',$n['reference_no']);unset($n);$db->commit();return $contract+['credit_notes'=>$notes];}
 catch(Throwable $e){if($db->inTransaction())$db->rollBack();throw $e;}
});
