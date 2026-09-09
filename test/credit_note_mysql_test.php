<?php
declare(strict_types=1);
// Deliberately fixed local-only disposable database. Never accepts a remote host.
require_once __DIR__.'/../Server/credit_note_common.php';
production_discard_output();
set_exception_handler(static function(Throwable $e):void {production_discard_output();fwrite(STDERR,$e->getMessage()."\n".$e->getTraceAsString()."\n");exit(1);});
$db=new PDO('mysql:host=127.0.0.1;port=33318;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);
if((int)$db->query('SELECT @@port')->fetchColumn()!==33318)throw new RuntimeException('Unexpected server');
$name='ceh_credit_note_disposable_test';
$q=$db->prepare('SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=?');$q->execute([$name]);
if((int)$q->fetchColumn()!==0)throw new RuntimeException('Test database already exists; refusing overwrite');
$db->exec("CREATE DATABASE `$name` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
$checks=0;
$cgi=null;
function check(bool $ok,string $why):void {global $checks;$checks++;if(!$ok)throw new RuntimeException($why);}
function reject(callable $f,string $code):void {try{$f();}catch(AccountsApiError $e){check($e->errorCode===$code,'Wrong rejection '.$e->errorCode);return;}throw new RuntimeException('Missing rejection '.$code);}
try{
 $db->exec("USE `$name`");
 $schema=file_get_contents(__DIR__.'/fixtures/credit_note_schema.sql');
 if(preg_match('/^INSERT\s/im',$schema))throw new RuntimeException('Schema contains records');
 $db->exec($schema);
 $db->exec(file_get_contents(__DIR__.'/../Server/migration_v1_22_credit_note_issuance.sql'));
 $db->exec("INSERT INTO qbook_companies(id,company_code,display_name) VALUES(1,'LOCAL-CN-QA','LOCAL QA ONLY')");
 $db->exec("INSERT INTO qbook_users(id,company_id,full_name,role) VALUES(1,1,'LOCAL QA ADMIN','ADMIN')");
 $db->exec("INSERT INTO qbook_clients(id,name) VALUES(1,'LOCAL QA CLIENT')");
 $db->exec("INSERT INTO qbook_accounts_chart(id,code,name,account_type) VALUES(1,'QA-AR','QA Receivables','ASSET'),(2,'QA-REV','QA Revenue','INCOME'),(3,'QA-VAT','QA VAT','LIABILITY')");
 $db->exec("INSERT INTO qbook_financial_account_roles(role_code,account_id) VALUES('TRADE_RECEIVABLES',1),('OUTPUT_VAT_PAYABLE',3)");
 $ref=billing_allocate_reference($db,'qbook_invoice_references');
 $db->prepare("INSERT INTO qbook_invoices(id,reference_no,client_id,client_name_snapshot,invoice_date,status,net_amount,vat_amount,total_amount,created_by) VALUES(1,?,1,'LOCAL QA CLIENT','2026-09-07','ISSUED','100.00','7.50','107.50',1)")->execute([$ref]);
 $db->exec("INSERT INTO qbook_invoice_lines(id,invoice_id,line_no,source_type,description,entered_amount,net_amount,vat_amount,gross_amount,revenue_account_id) VALUES(1,1,1,'SERVICE','LOCAL QA SERVICE','107.50','100.00','7.50','107.50',2)");
 $user=['id'=>1,'role'=>'ADMIN'];
 $base=['invoice_id'=>1,'credit_date'=>'2026-09-07','reason'=>'LOCAL QA ONLY'];
 $request=fn(string $key,string $amount)=>$base+['request_key'=>$key,'lines'=>[['invoice_line_id'=>1,'gross_amount'=>$amount]]];
 reject(fn()=>credit_note_issue_execute($db,['id'=>1,'role'=>'USER'],$request(str_repeat('a',32),'1.00')),'FORBIDDEN');
 reject(fn()=>credit_note_issue_execute($db,$user,$base+['request_key'=>str_repeat('a',32),'lines'=>[['invoice_line_id'=>1,'gross_amount'=>'1.00'],['invoice_line_id'=>1,'gross_amount'=>'1.00']]]),'DUPLICATE_CREDIT_INVOICE_LINE');
 check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===0,'Invalid request mutated journals');
 $r=credit_note_issue_execute($db,$user,$request(str_repeat('a',32),'30.00'));
 $repeat=credit_note_issue_execute($db,$user,$request(str_repeat('a',32),'30.00'));
 // MySQL JSON canonicalizes object-key order; compare the complete values.
 check($r==$repeat,'Replay result differs');
 check((int)$db->query('SELECT COUNT(*) FROM qbook_credit_notes')->fetchColumn()===1,'Replay created note');
 reject(fn()=>credit_note_issue_execute($db,$user,$request(str_repeat('a',32),'31.00')),'IDEMPOTENCY_PAYLOAD_MISMATCH');
 credit_note_issue_execute($db,$user,$request(str_repeat('b',32),'20.01'));
 reject(fn()=>credit_note_issue_execute($db,$user,$request(str_repeat('c',32),'57.50')),'CREDIT_EXCEEDS_INVOICE_LINE');
 credit_note_issue_execute($db,$user,$request(str_repeat('c',32),'57.49'));
 $s=$db->query('SELECT SUM(net_amount) n,SUM(vat_amount) v,SUM(total_amount) g FROM qbook_credit_notes')->fetch();
 check($s===['n'=>'100.00','v'=>'7.50','g'=>'107.50'],'Final components differ');
 check(billing_invoice_outstanding($db,1)['outstanding_minor']===0,'Outstanding does not reconcile');
 check((int)$db->query('SELECT COUNT(*) FROM qbook_credit_note_production_releases')->fetchColumn()===0,'Price-only note released production');
 check((int)$db->query('SELECT COUNT(*) FROM qbook_credit_note_requests')->fetchColumn()===3,'Persistent request evidence missing');
 check((int)$db->query("SELECT COUNT(*) FROM qbook_financial_audit WHERE event_type='CREDIT_NOTE_ISSUED'")->fetchColumn()===3,'Audit count wrong');
 $balances=$db->query('SELECT account_id,SUM(debit) d,SUM(credit) c FROM qbook_financial_journal_lines GROUP BY account_id ORDER BY account_id')->fetchAll();
 check($balances===[['account_id'=>1,'d'=>'0.00','c'=>'107.50'],['account_id'=>2,'d'=>'100.00','c'=>'0.00'],['account_id'=>3,'d'=>'7.50','c'=>'0.00']],'Exact journal accounts/amounts wrong');
 require_once __DIR__.'/credit_note_cgi_harness.php';
 $db->exec("INSERT INTO qbook_company_regional_settings(company_id,time_zone,date_format,time_format,base_currency) VALUES(1,'Africa/Lagos','DD-MM-YYYY','24_HOUR','NGN')");
 $db->exec("INSERT INTO qbook_invoice_settings(id,company_legal_name,company_address,tax_identifier,payment_bank_details) VALUES(1,'LOCAL QA','LOCAL QA ADDRESS','QA-TAX','QA BANK')");
 $db->exec("INSERT INTO qbook_accounts_chart(id,code,name,account_type) VALUES(4,'QA-BANK','QA Bank','ASSET'),(5,'QA-WHT','QA WHT','ASSET'),(6,'QA-ADV','QA Advances','LIABILITY')");
 $db->exec("INSERT INTO qbook_financial_account_roles(role_code,account_id) VALUES('WHT_RECEIVABLE',5),('CUSTOMER_ADVANCES',6)");
 $db->exec("INSERT INTO qbook_bank_accounts(id,name,bank_name,ledger_account_id) VALUES(1,'QA BANK','QA BANK',4)");
 $db->exec("INSERT INTO qbook_tax_codes(id,code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from) VALUES(1,'QA-WHT','QA WHT','WHT',5,'NET','WHT_RECEIVABLE','2026-01-01')");
 $cgi=new CreditNoteCgiHarness($db);
 foreach(['payment','wht','advance','credit','void','payment','wht','advance','credit','void'] as $iteration=>$race){
  $ref=billing_allocate_reference($db,'qbook_invoice_references');
  $db->prepare("INSERT INTO qbook_invoices(reference_no,client_id,client_name_snapshot,invoice_date,status,net_amount,vat_amount,total_amount,created_by) VALUES(?,1,'LOCAL QA CLIENT','2026-09-07','ISSUED','100.00','7.50','107.50',1)")->execute([$ref]);$iid=(int)$db->lastInsertId();
  $db->prepare("INSERT INTO qbook_invoice_lines(invoice_id,line_no,source_type,description,entered_amount,net_amount,vat_amount,gross_amount,revenue_account_id) VALUES(?,1,'SERVICE','LOCAL QA RACE','107.50','100.00','7.50','107.50',2)")->execute([$iid]);$lid=(int)$db->lastInsertId();
  $original=accounts_transaction($db,fn()=>accounts_post_journal($db,$user,['transaction_date'=>'2026-09-07','description'=>'LOCAL QA INVOICE','source_module'=>'INVOICE','source_record_id'=>$iid],[['account_id'=>1,'debit_minor'=>10750,'client_id'=>1],['account_id'=>2,'credit_minor'=>10000,'client_id'=>1],['account_id'=>3,'credit_minor'=>750,'client_id'=>1]]));
  $db->prepare('UPDATE qbook_invoices SET journal_id=? WHERE id=?')->execute([$original['id'],$iid]);
  $cn=['invoice_id'=>$iid,'credit_date'=>'2026-09-07','reason'=>'LOCAL QA CONCURRENT '.$race,'request_key'=>bin2hex(random_bytes(20)),'lines'=>[['invoice_line_id'=>$lid,'gross_amount'=>'100.00']]];
  $journalBeforeQuote=$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn();
  $quote=$cgi->call('credit_note_quote.php',$cn);
  check($quote['ok']===true&&$quote['quote']['total_amount']==='100.00','Read-only quote failed');
  check($db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===$journalBeforeQuote,'Quote created a journal');
  if(in_array($race,['payment','wht','advance'],true)){
   $rr=billing_allocate_reference($db,'qbook_customer_receipt_references');$cash=$race==='wht'?'1.00':'100.00';
   $db->prepare("INSERT INTO qbook_customer_receipts(reference_no,client_id,client_name_snapshot,bank_account_id,receipt_date,cash_amount,destination,created_by) VALUES(?,1,'LOCAL QA CLIENT',1,'2026-09-07',?,'TRADE_RECEIVABLES',1)")->execute([$rr,$cash]);$rid=(int)$db->lastInsertId();
   if($race==='advance'){
    $posted=$cgi->call('customer_receipt_post.php',['receipt_id'=>$rid,'allocations'=>[]]);check($posted['ok']===true,'Advance setup posting failed '.json_encode($posted));
    $endpoint='customer_advance_apply.php';$other=['receipt_id'=>$rid,'invoice_id'=>$iid,'amount'=>'100.00','application_date'=>'2026-09-07'];
   }else{
    $endpoint='customer_receipt_post.php';$allocation=['invoice_id'=>$iid,'cash_amount'=>$cash];
    if($race==='wht')$allocation+=['wht_amount'=>'99.00','wht_tax_code_id'=>1,'wht_calculation_base_amount'=>'1980.00','certificate_status'=>'CERTIFICATE_PENDING'];
    $other=['receipt_id'=>$rid,'allocations'=>[$allocation]];
   }
  }elseif($race==='void'){$endpoint='invoice_void.php';$other=['invoice_id'=>$iid,'void_date'=>'2026-09-07','reason'=>'LOCAL QA VOID RACE'];}
  else{$endpoint='credit_note_issue.php';$other=$cn;$other['request_key']=bin2hex(random_bytes(20));}
  $db->beginTransaction();$db->query("SELECT id FROM qbook_invoices WHERE id=$iid FOR UPDATE")->fetchAll();
  if($iteration<5){$first=$cgi->start('credit_note_issue.php',$cn);usleep(200000);$second=$cgi->start($endpoint,$other);}
  else{$second=$cgi->start($endpoint,$other);usleep(200000);$first=$cgi->start('credit_note_issue.php',$cn);}
  usleep(250000);$db->commit();
  $a=$cgi->finish($first);$b=$cgi->finish($second);
  check((int)$a['ok']+(int)$b['ok']===1,'Race must have exactly one success '.$race.' '.json_encode([$a,$b]));
  $failure=$a['ok']?$b:$a;
  check(in_array($failure['error']??'', ['CREDIT_EXCEEDS_OUTSTANDING','CREDIT_EXCEEDS_INVOICE_LINE','ISSUED_INVOICE_REQUIRED','INVOICE_OVERALLOCATION','ONLY_UNPAID_INVOICE_CAN_BE_VOIDED'],true),'Unexpected race failure '.$race.' '.json_encode($failure));
  $state=billing_invoice_outstanding($db,$iid);check($state['outstanding_minor']>=0,'Race over-settled invoice '.$race);
  $count=$db->query("SELECT COUNT(*) FROM qbook_credit_notes WHERE invoice_id=$iid")->fetchColumn();check((int)$count<=1,'Race duplicated credit note');
  if($state['status']==='VOID')check((int)$count===0,'Void and credit both committed');
  check((int)$db->query('SELECT COUNT(*) FROM (SELECT journal_id FROM qbook_financial_journal_lines GROUP BY journal_id HAVING SUM(debit)<>SUM(credit)) broken')->fetchColumn()===0,'Race unbalanced journal');
  echo "ACTUAL_ENDPOINT_RACE_PASSED $race credit_committed=".($a['ok']?'yes':'no')." competing_committed=".($b['ok']?'yes':'no')." rejection=".$failure['error']."\n";
 }
 // Two invoices share one synthetic production session. Credit may free an
 // explicit quantity while a second invoice tries to commit that capacity.
 $db->exec("INSERT INTO qbook_mixers(id,code,name) VALUES(1,'QA-ONLY','QA MIXER')");
 $db->exec("INSERT INTO qbook_production_sessions(id,production_date,client_id,client_name,project_site,mixer_id,mixer_code_snapshot,mixer_name_snapshot,loading_point,discharge_point,operator_id,operator_name_snapshot,status) VALUES(1,'2026-09-07',1,'LOCAL QA CLIENT','QA',1,'QA-ONLY','QA MIXER','QA','QA',1,'QA','SIGNED')");
 $db->exec("INSERT INTO qbook_production_reports(report_no,production_session_id,issued_at) VALUES(1,1,UTC_TIMESTAMP())");
 $pair=[];
 foreach(['ISSUED','DRAFT'] as $state){
  $ref=billing_allocate_reference($db,'qbook_invoice_references');
  $db->prepare("INSERT INTO qbook_invoices(reference_no,client_id,client_name_snapshot,invoice_date,status,terms_snapshot,net_amount,vat_amount,total_amount,created_by) VALUES(?,1,'LOCAL QA CLIENT','2026-09-07',?,'QA TERMS','100.00','0.00','100.00',1)")->execute([$ref,$state]);$iid=(int)$db->lastInsertId();
  $db->prepare("INSERT INTO qbook_invoice_lines(invoice_id,line_no,source_type,description,entered_amount,net_amount,vat_amount,gross_amount,revenue_account_id) VALUES(?,1,'PRODUCTION_REPORT','LOCAL QA PRODUCTION','100.00','100.00','0.00','100.00',2)")->execute([$iid]);$lid=(int)$db->lastInsertId();
  $db->prepare("INSERT INTO qbook_invoice_production_allocations(invoice_line_id,production_session_id,production_report_no,report_reference_snapshot,signed_m3_snapshot,billed_m3,rate_snapshot,status) VALUES(?,1,1,'QA-REPORT',10,?,10,?)")->execute([$lid,$state==='ISSUED'?10:4,$state==='ISSUED'?'COMMITTED':'DRAFT']);
  $pair[]=['invoice'=>$iid,'line'=>$lid,'allocation'=>(int)$db->lastInsertId()];
 }
 $cn=['invoice_id'=>$pair[0]['invoice'],'credit_date'=>'2026-09-07','reason'=>'LOCAL QA EXPLICIT RELEASE','request_key'=>bin2hex(random_bytes(20)),'lines'=>[['invoice_line_id'=>$pair[0]['line'],'gross_amount'=>'50.00','production_releases'=>[['invoice_production_allocation_id'=>$pair[0]['allocation'],'released_m3'=>'4.00']]]]];
 $beforeProduction=$db->query('SELECT * FROM qbook_production_sessions WHERE id=1')->fetch();
 $db->beginTransaction();$db->query('SELECT id FROM qbook_invoice_production_allocations WHERE production_session_id=1 ORDER BY id FOR UPDATE')->fetchAll();
 $a=$cgi->start('credit_note_issue.php',$cn);$b=$cgi->start('invoice_issue.php',['invoice_id'=>$pair[1]['invoice']]);usleep(250000);$db->commit();
 $ar=$cgi->finish($a);$br=$cgi->finish($b);
 if(!$ar['ok']){
  check(str_contains($ar['_test_diagnostic']??'','driver=1213'),'Unexpected production credit failure '.json_encode($ar));
  check((int)$db->query('SELECT COUNT(*) FROM qbook_credit_note_production_releases')->fetchColumn()===0,'Deadlock left release behind');
  $ar=$cgi->call('credit_note_issue.php',$cn); // Same idempotency key, never a new issuance.
 }
 check($ar['ok']===true,'Production credit retry failed '.json_encode($ar));
 if(!$br['ok']){
  $deadlock=str_contains($br['_test_diagnostic']??'','driver=1213');
  check(($br['error']??'')==='PRODUCTION_M3_EXCEEDED'||$deadlock,'Unexpected rebilling failure '.json_encode($br));
  check($db->query('SELECT status FROM qbook_invoices WHERE id='.$pair[1]['invoice'])->fetchColumn()==='DRAFT','Failed rebill mutated invoice');
  check((int)$db->query("SELECT COUNT(*) FROM qbook_financial_journals WHERE source_module='INVOICE' AND source_record_id=".$pair[1]['invoice'])->fetchColumn()===0,'Failed rebill left journal behind');
  echo 'REBILL_RETRY_AFTER_SAFE_ROLLBACK reason='.($deadlock?'MYSQL_DEADLOCK_1213':'CAPACITY_NOT_YET_RELEASED')."\n";
  $br=$cgi->call('invoice_issue.php',['invoice_id'=>$pair[1]['invoice']]);
 }
 check($br['ok']===true,'Rebilling after explicit release failed '.json_encode($br));
 check($db->query("SELECT SUM(billed_m3)-(SELECT SUM(released_m3) FROM qbook_credit_note_production_releases) FROM qbook_invoice_production_allocations WHERE status='COMMITTED'")->fetchColumn()==='10.00','Rebilling quantity does not reconcile');
 check($db->query('SELECT * FROM qbook_production_sessions WHERE id=1')->fetch()===$beforeProduction,'Physical production mutated');
 $cn['request_key']=bin2hex(random_bytes(20));$cn['lines'][0]['production_releases'][0]['released_m3']='7.00';
 $bad=$cgi->call('credit_note_issue.php',$cn);check(($bad['error']??'')==='QUANTITY_RELEASE_EXCEEDS_ALLOCATION_M3','Excess release accepted');
 echo "ACTUAL_ENDPOINT_PRODUCTION_REBILL_RACE_PASSED\n";
 $cn['request_key']=bin2hex(random_bytes(20));$cn['lines'][0]['production_releases']=[];
 $one=$cgi->start('credit_note_issue.php',$cn);$two=$cgi->start('credit_note_issue.php',$cn);
 $one=$cgi->finish($one);$two=$cgi->finish($two);
 check($one['ok']===true&&$two['ok']===true&&$one==$two,'Concurrent same-key retry differs');
 check((int)$db->query('SELECT COUNT(*) FROM qbook_credit_notes WHERE invoice_id='.$pair[0]['invoice'])->fetchColumn()===2,'Concurrent retry duplicated note');
 check((int)$db->query('SELECT COUNT(*) FROM qbook_credit_note_production_releases')->fetchColumn()===1,'Concurrent price-only retry added release');
 echo "ACTUAL_ENDPOINT_CONCURRENT_IDEMPOTENT_REPLAY_PASSED\n";
 $journalsBeforeEvidence=$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn();
 $png=file_get_contents(__DIR__.'/../Server/assets/ceh_logo.png');
 $evidence=$cgi->call('financial_evidence_upload.php',['source_type'=>'CREDIT_NOTE','source_record_id'=>$r['credit_note']['id'],'filename'=>'LOCAL-QA-evidence.png','mime_type'=>'image/png','data_base64'=>base64_encode($png)]);
 check($evidence['ok']===true,'Credit Note evidence upload failed');
 check($evidence['evidence']['sha256']===hash('sha256',$png),'Evidence bytes mismatch');
 check($db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===$journalsBeforeEvidence,'Evidence created journal');
 $invalid=$cgi->call('financial_evidence_upload.php',['source_type'=>'CREDIT_NOTE','source_record_id'=>999999,'filename'=>'LOCAL-QA-evidence.png','mime_type'=>'image/png','data_base64'=>base64_encode($png)]);
 check(($invalid['error']??'')==='BILLING_SOURCE_NOT_FOUND','Wrong note evidence relation accepted');
 $db->exec("UPDATE qbook_users SET role='OPERATOR' WHERE id=1");
 $denied=$cgi->call('credit_note_issue.php',$cn);check(($denied['error']??'')==='FORBIDDEN','Endpoint allowed non-Admin');
 $db->exec("UPDATE qbook_users SET role='ADMIN' WHERE id=1");
 $ref=billing_allocate_reference($db,'qbook_invoice_references');
 $db->prepare("INSERT INTO qbook_invoices(reference_no,client_id,client_name_snapshot,invoice_date,status,net_amount,vat_amount,total_amount,created_by) VALUES(?,1,'LOCAL MULTI-LINE QA','2026-09-07','ISSUED','100.00','7.50','107.50',1)")->execute([$ref]);$iid=(int)$db->lastInsertId();$ids=[];
 foreach([1,2] as $number){$db->prepare("INSERT INTO qbook_invoice_lines(invoice_id,line_no,source_type,description,entered_amount,net_amount,vat_amount,gross_amount,revenue_account_id) VALUES(?,?,'SERVICE','LOCAL MULTI-LINE QA','53.75','50.00','3.75','53.75',2)")->execute([$iid,$number]);$ids[]=(int)$db->lastInsertId();}
 $multi=['invoice_id'=>$iid,'credit_date'=>'2026-09-07','reason'=>'LOCAL MULTI-LINE QA','request_key'=>bin2hex(random_bytes(20)),'lines'=>[['invoice_line_id'=>$ids[0],'gross_amount'=>'20.00'],['invoice_line_id'=>$ids[1],'gross_amount'=>'30.00']]];
 $result=credit_note_issue_execute($db,$user,$multi);check($result['outstanding_after']==='57.50','Multi-line outstanding mismatch');
 $snapshot=$db->query('SELECT document_snapshot FROM qbook_credit_notes WHERE id='.$result['credit_note']['id'])->fetchColumn();
 $snapshot=json_decode($snapshot,true);check(count($snapshot['lines'])===2&&$snapshot['invoice']['client_name_snapshot']==='LOCAL MULTI-LINE QA','Frozen document snapshot incomplete');
 $multi['request_key']=bin2hex(random_bytes(20));$multi['lines'][0]['gross_amount']='33.75';$multi['lines'][1]['gross_amount']='23.75';
 $result=credit_note_issue_execute($db,$user,$multi);check($result['outstanding_after']==='0.00','Final multi-line residual mismatch');
 production_discard_output();echo "CREDIT_NOTE_MYSQL_BASIC_LIFECYCLE_PASSED checks=$checks\n";
}finally{
 if($db->inTransaction())$db->rollBack();
 if($cgi!==null)$cgi->close();
 $db->exec("DROP DATABASE `$name`");
 echo "DISPOSABLE_DATABASE_REMOVED\n";
}
