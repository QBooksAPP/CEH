<?php
declare(strict_types=1);
// Only a disposable loopback database is accepted. No deployed credentials.
require_once __DIR__.'/../Server/customer_payment_post_common.php';
require_once __DIR__.'/../Server/general_expense_refunds_common.php';
production_discard_output();
set_exception_handler(static function(Throwable $e):void {production_discard_output();fwrite(STDERR,$e->getMessage()."\n".$e->getTraceAsString()."\n");exit(1);});
$db=new PDO('mysql:host=127.0.0.1;port=33318;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);
if((int)$db->query('SELECT @@port')->fetchColumn()!==33318)throw new RuntimeException('Wrong disposable server');
$name='ceh_bank_payment_disposable_test';
if(($argv[1]??'')==='claim-worker'){
 $db->exec("USE $name");$user=$db->query('SELECT id,company_id,role FROM qbook_users WHERE id=1')->fetch();
 try{
  $result=$argv[2]==='refund'?general_expense_link_refund($db,$user,(int)$argv[4],(int)$argv[3]):bank_payment_draft($db,$user,['statement_row_id'=>(int)$argv[3],'client_id'=>1,'request_key'=>hash('sha256','race'.$argv[3])]);
  echo json_encode(['ok'=>true,'result'=>$result]);
 }catch(AccountsApiError $e){echo json_encode(['ok'=>false,'error'=>$e->errorCode]);}
 exit;
}
if(($argv[1]??'')==='post-worker'){
 $db->exec("USE $name");
 $user=$db->query('SELECT id,company_id,role FROM qbook_users WHERE id=1')->fetch();
 echo json_encode(customer_payment_post($db,$user,json_decode($argv[2],true,512,JSON_THROW_ON_ERROR)));exit;
}
if((int)$db->query("SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$name'")->fetchColumn())throw new RuntimeException('Refusing existing database');
$checks=0;
function payment_check(bool $ok,string $message):void {global $checks;$checks++;if(!$ok)throw new RuntimeException($message);}
function payment_reject(callable $f,string $code):void {try{$f();}catch(AccountsApiError $e){payment_check($e->errorCode===$code,'Expected '.$code.' got '.$e->errorCode);return;}throw new RuntimeException('Missing rejection '.$code);}
$db->exec("CREATE DATABASE $name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
try {
 $db->exec("USE $name");
 $db->exec(file_get_contents(__DIR__.'/fixtures/credit_note_schema.sql'));
 foreach(['v1_22_credit_note_issuance','v1_23_bank_import_foundation','v1_24_bank_expense_reservation','v1_25_bank_payment_reservation'] as $migration)$db->exec(file_get_contents(__DIR__.'/../Server/migration_'.$migration.'.sql'));
 $db->exec("INSERT INTO qbook_companies(id,company_code,display_name) VALUES(1,'LOCAL-PAYMENT-QA','LOCAL QA'); INSERT INTO qbook_users(id,company_id,full_name,role) VALUES(1,1,'LOCAL ADMIN','ADMIN'); INSERT INTO qbook_clients(id,name) VALUES(1,'LOCAL CLIENT'),(2,'OTHER CLIENT')");
 $db->exec("INSERT INTO qbook_company_regional_settings(company_id,time_zone,date_format,time_format,base_currency) VALUES(1,'Africa/Lagos','DD-MM-YYYY','24_HOUR','NGN'); INSERT INTO qbook_invoice_settings(id,company_legal_name,company_address,tax_identifier,payment_bank_details) VALUES(1,'LOCAL QA','LOCAL ADDRESS','QA-TAX','QA BANK')");
 $db->exec("INSERT INTO qbook_accounts_chart(id,code,name,account_type) VALUES(1,'QA-AR','Receivables','ASSET'),(2,'QA-REV','Revenue','INCOME'),(3,'QA-VAT','VAT','LIABILITY'),(4,'QA-BANK','Bank','ASSET'),(5,'QA-WHT','WHT','ASSET'),(6,'QA-ADV','Advances','LIABILITY'); INSERT INTO qbook_financial_account_roles(role_code,account_id) VALUES('TRADE_RECEIVABLES',1),('OUTPUT_VAT_PAYABLE',3),('WHT_RECEIVABLE',5),('CUSTOMER_ADVANCES',6); INSERT INTO qbook_bank_accounts(id,name,bank_name,ledger_account_id) VALUES(1,'QA BANK','QA BANK',4)");
 $db->exec("INSERT INTO qbook_bank_import_batches(id,bank_account_id,original_filename,file_type,file_sha256,imported_by) VALUES(1,1,'local.csv','CSV',SHA2('local',256),1)");
 foreach([1=>'100.00',2=>'40.00',3=>'100.00',4=>'75.00',5=>'102.50',6=>'-10.00',7=>'20.00'] as $row=>$amount)$db->prepare("INSERT INTO qbook_bank_statement_rows(id,import_batch_id,bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint) VALUES(?,1,1,'2026-09-01',?,?,'LOCAL ONLY',SHA2(?,256))")->execute([$row,$amount,'QA-'.$row,'row'.$row]);
 for($id=1;$id<=5;$id++){
  $ref=billing_allocate_reference($db,'qbook_invoice_references');$net=$id===5?'100.00':'100.00';$vat=$id===5?'7.50':'0.00';$gross=$id===5?'107.50':'100.00';
  $db->prepare("INSERT INTO qbook_invoices(id,reference_no,client_id,client_name_snapshot,invoice_date,status,net_amount,vat_amount,total_amount,created_by) VALUES(?,?,1,'LOCAL CLIENT','2026-09-01','ISSUED',?,?,?,1)")->execute([$id,$ref,$net,$vat,$gross]);
 }
 $db->exec("INSERT INTO qbook_tax_codes(id,code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from) VALUES(1,'QA-WHT','QA WHT','WHT',5,'NET','WHT_RECEIVABLE','2026-01-01')");
 $user=$db->query('SELECT id,company_id,role FROM qbook_users WHERE id=1')->fetch();
 payment_check((int)$user['company_id']===1,'Fixture Admin company identity missing');
 $regional=company_regional_settings($db,$user);
 payment_check($regional['time_zone']==='Africa/Lagos'&&$regional['base_currency']==='NGN','Fixture Regional Settings invalid');
 $create=fn(int $row,string $key)=>['statement_row_id'=>$row,'client_id'=>1,'request_key'=>hash('sha256',$key)];
 $immutable=$db->query('SELECT id,bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint FROM qbook_bank_statement_rows ORDER BY id')->fetchAll();
 payment_reject(fn()=>bank_payment_draft($db,['id'=>1,'role'=>'OPERATOR'],$create(1,'forbidden')),'FORBIDDEN');
 payment_reject(fn()=>bank_payment_draft($db,$user,$create(6,'debit')),'UNMATCHED_BANK_CREDIT_REQUIRED');
 payment_reject(fn()=>bank_payment_draft($db,$user,$create(1,'bank')+['bank_account_id'=>2]),'STATEMENT_FIELDS_LOCKED');
 $cancel=bank_payment_draft($db,$user,$create(7,'cancel'))['receipt'];
 payment_check(bank_payment_draft($db,$user,$create(7,'cancel'))['replayed']===true,'Create retry not idempotent');
 payment_reject(fn()=>bank_payment_draft($db,$user,$create(7,'other')),'BANK_ROW_USED_AS_RECEIPT');
 bank_payment_edit($db,$user,['receipt_id'=>$cancel['id'],'draft_revision'=>0,'reason'=>'LOCAL CANCEL'],true);
 $reuse=bank_payment_draft($db,$user,$create(7,'reuse'))['receipt'];
 payment_check($reuse['id']!==$cancel['id'],'Cancellation did not allow reuse');
 payment_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===0,'Draft/cancel posted journal');
 $cases=[1=>[['invoice_id'=>1,'cash_amount'=>'100.00']],2=>[['invoice_id'=>2,'cash_amount'=>'40.00']],3=>[['invoice_id'=>3,'cash_amount'=>'60.00'],['invoice_id'=>4,'cash_amount'=>'40.00']],4=>[],5=>[['invoice_id'=>5,'cash_amount'=>'102.50','wht_amount'=>'5.00','wht_tax_code_id'=>1,'wht_calculation_base_amount'=>'100.00','wht_suggested_amount'=>'5.00','certificate_status'=>'CERTIFICATE_PENDING']]];
 foreach($cases as $row=>$allocations){
  $receipt=bank_payment_draft($db,$user,$create($row,'post'.$row))['receipt'];
  $request=['receipt_id'=>$receipt['id'],'draft_revision'=>0,'allocations'=>$allocations];
  customer_payment_post($db,$user,$request);
  payment_check(bank_payment_read($db,$user,$row)['receipt']['status']==='POSTED','Posted state missing');
  payment_check(customer_payment_post($db,$user,$request)['replayed']===true,'Post replay not idempotent');
  payment_reject(fn()=>customer_payment_post($db,$user,$request+['unexpected_change'=>true]),'PAYMENT_RETRY_PAYLOAD_MISMATCH');
 }
 payment_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===5,'Exactly one journal per payment');
 payment_check((int)$db->query('SELECT COUNT(*) FROM qbook_bank_matches')->fetchColumn()===5,'Exactly one reconciliation per payment');
 payment_check((int)$db->query('SELECT COUNT(*) FROM (SELECT journal_id FROM qbook_financial_journal_lines GROUP BY journal_id HAVING SUM(debit)<>SUM(credit)) x')->fetchColumn()===0,'Unbalanced payment');
 foreach([1=>0,2=>6000,3=>4000,4=>6000,5=>0] as $invoice=>$expected)payment_check(billing_invoice_outstanding($db,$invoice)['outstanding_minor']===$expected,'Incorrect invoice balance '.$invoice);
 payment_check($immutable===$db->query('SELECT id,bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint FROM qbook_bank_statement_rows ORDER BY id')->fetchAll(),'Statement provenance changed');
 // A saved intent must still be rejected after another payment settles its invoice.
 $stale=['receipt_id'=>$reuse['id'],'draft_revision'=>0,'allocations'=>[['invoice_id'=>1,'cash_amount'=>'20.00']]];
 bank_payment_edit($db,$user,$stale);
 $stale['draft_revision']=1;
 payment_reject(fn()=>customer_payment_post($db,$user,$stale),'INVOICE_OVERALLOCATION');
 payment_check(bank_payment_read($db,$user,7)['receipt']['draft_payload'][0]['cash_amount']==='20.00','Rejected post lost saved intent');
 payment_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===5,'Rejected stale post created journal');
 // Explicitly revised intent: leave this cash as credit. Two simultaneous retries
 // must produce one journal and one match, with the second response a replay.
 $request=['receipt_id'=>$reuse['id'],'draft_revision'=>1,'allocations'=>[]];
 $db->beginTransaction();$db->query('SELECT id FROM qbook_bank_statement_rows WHERE id=7 FOR UPDATE')->fetch();
 $workers=[];
 for($i=0;$i<2;$i++){
  $process=proc_open([PHP_BINARY,'-d','extension_dir='.ini_get('extension_dir'),'-d','extension=pdo_mysql','-d','extension=mbstring',__FILE__,'post-worker',json_encode($request)], [0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
  if(!is_resource($process))throw new RuntimeException('Cannot start payment worker');
  fclose($pipes[0]);$workers[]=[$process,$pipes];
 }
 usleep(300000);$db->commit();$replays=0;
 foreach($workers as [$process,$pipes]){
  $output=stream_get_contents($pipes[1]);$errors=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);
  payment_check(proc_close($process)===0&&$errors==='','Concurrent worker failed: '.$errors);
  $result=json_decode($output,true,512,JSON_THROW_ON_ERROR);if($result['replayed']??false)$replays++;
 }
 payment_check($replays===1,'Concurrent retry did not return one replay');
 payment_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===6,'Concurrent payment duplicated journal');
 payment_check((int)$db->query('SELECT COUNT(*) FROM qbook_bank_matches')->fetchColumn()===6,'Concurrent payment duplicated match');
 // Shared read/write eligibility, including cancellation and simultaneous claims.
 $db->exec("INSERT INTO qbook_accounts_chart(id,code,name,account_type) VALUES(7,'QA-EXP','QA Expense','EXPENSE')");
 $expenseJournal=accounts_transaction($db,fn()=>accounts_post_journal($db,$user,[
  'transaction_date'=>'2026-09-01','source_module'=>'GENERAL_EXPENSE','source_record_id'=>1,
  'description'=>'LOCAL ONLY refund prerequisite'],[
   ['account_id'=>7,'debit_minor'=>100000,'credit_minor'=>0],
   ['account_id'=>4,'debit_minor'=>0,'credit_minor'=>100000]
 ]));
 $db->prepare("INSERT INTO qbook_general_expenses(id,bank_account_id,expense_date,amount,status,journal_id,created_by) VALUES(1,1,'2026-09-01','1000.00','APPROVED',?,1)")->execute([$expenseJournal['id']]);
 $db->exec('INSERT INTO qbook_general_expense_references(expense_id) VALUES(1)');
 foreach(range(8,12) as $row)$db->prepare("INSERT INTO qbook_bank_statement_rows(id,import_batch_id,bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint) VALUES(?,1,1,'2026-09-01','10.00','QA repeated','LOCAL repeated',SHA2(?,256))")->execute([$row,'row'.$row]);
 $eligible=fn()=>array_map('intval',array_column(general_expense_refunds_read($db,1,['view'=>'eligible','page_size'=>100])['rows'],'statement_row_id'));
 payment_check(in_array(8,$eligible(),true),'Available credit missing from refunds');
 $reserved=bank_payment_draft($db,$user,$create(8,'eligibility'))['receipt'];
 payment_check(!in_array(8,$eligible(),true),'Payment draft still offered for refund');
 payment_reject(fn()=>general_expense_link_refund($db,$user,1,8),'BANK_ROW_USED_AS_RECEIPT');
 bank_payment_edit($db,$user,['receipt_id'=>$reserved['id'],'draft_revision'=>0,'reason'=>'QA release'],true);
 payment_check(in_array(8,$eligible(),true),'Cancelled payment still excludes refund');
 $beforeJ=(int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn();
 $beforeL=(int)$db->query('SELECT COUNT(*) FROM qbook_financial_journal_lines')->fetchColumn();
 general_expense_link_refund($db,$user,1,8);
 payment_reject(fn()=>bank_payment_draft($db,$user,$create(8,'after-refund')),'BANK_ROW_USED_AS_REFUND');
 payment_reject(fn()=>general_expense_link_refund($db,$user,1,8),'REFUND_ALREADY_LINKED');
 payment_check(!in_array(7,$eligible(),true),'Posted payment offered for refund');
 foreach(range(9,12) as $row){
  $db->beginTransaction();$db->query("SELECT id FROM qbook_bank_statement_rows WHERE id=$row FOR UPDATE")->fetch();$workers=[];
  foreach(['payment','refund'] as $kind){
   $process=proc_open([PHP_BINARY,'-d','extension_dir='.ini_get('extension_dir'),'-d','extension=pdo_mysql','-d','extension=mbstring',__FILE__,'claim-worker',$kind,(string)$row,'1'],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
   if(!is_resource($process))throw new RuntimeException('Cannot start claim worker');fclose($pipes[0]);$workers[]=[$process,$pipes];
  }
  usleep(300000);$db->commit();$results=[];
  foreach($workers as [$process,$pipes]){
   $raw=stream_get_contents($pipes[1]);$error=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);
   payment_check(proc_close($process)===0&&$error==='','Claim worker failed '.$error);$results[]=json_decode($raw,true,512,JSON_THROW_ON_ERROR);
  }
  payment_check(count(array_filter($results,fn($r)=>$r['ok']))===1,'Claim race must have exactly one winner');
  $loser=array_values(array_filter($results,fn($r)=>!$r['ok']))[0];
  payment_check(in_array($loser['error'],['BANK_ROW_USED_AS_REFUND','BANK_ROW_USED_AS_RECEIPT'],true),'Non-authoritative conflict '.$loser['error']);
  $owners=(int)$db->query("SELECT (SELECT COUNT(*) FROM qbook_general_expense_refunds WHERE statement_row_id=$row)+(SELECT COUNT(*) FROM qbook_customer_receipts WHERE statement_row_id=$row AND ".bank_payment_active_owner_sql().')')->fetchColumn();
  payment_check($owners===1,'Ambiguous statement ownership');
  payment_check(!in_array($row,$eligible(),true),'Claimed credit offered for refund');
 }
 payment_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===$beforeJ,'Claim/refund posted journal');
 payment_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journal_lines')->fetchColumn()===$beforeL,'Claim/refund posted journal lines');
 payment_check((int)$db->query("SELECT COUNT(*) FROM qbook_bank_statement_rows WHERE bank_reference='QA repeated' AND amount=10.00")->fetchColumn()===5,'Repeated legitimate rows changed');
 echo "BANK_PAYMENT_MYSQL_PASSED checks=$checks\n";
} finally {
 if($db->inTransaction())$db->rollBack();
 $db->exec("DROP DATABASE $name");
 echo "DISPOSABLE_PAYMENT_DATABASE_REMOVED\n";
}
