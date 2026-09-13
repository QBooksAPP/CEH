<?php
declare(strict_types=1);
if(gethostname()!=='ceh-production-01')throw new RuntimeException('Wrong hostname');
require_once __DIR__.'/../Server/customer_payment_review_common.php';
require_once __DIR__.'/../Server/customer_payment_post_common.php';
production_discard_output();
set_exception_handler(static function(Throwable $e):void {production_discard_output();fwrite(STDERR,'STOP: '.$e->getMessage()."\n");exit(1);});
$cfg=parse_ini_file('/var/backups/ceh-production/restore-tests/legacy-draft-disposable/qa-db.cnf',true,INI_SCANNER_RAW)['client'];
$db=new PDO('mysql:unix_socket=/run/mysqld/mysqld.sock;dbname=ceh_legacy_draft_disposable;charset=utf8mb4',$cfg['user'],$cfg['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);
if($db->query('SELECT DATABASE()')->fetchColumn()!=='ceh_legacy_draft_disposable')throw new RuntimeException('Wrong disposable database');
$user=$db->query("SELECT id,company_id,role FROM qbook_users WHERE role='ADMIN' AND is_active=1 ORDER BY id LIMIT 1")->fetch();
function receipt(PDO $db,int $id):array {$s=$db->prepare('SELECT * FROM qbook_customer_receipts WHERE id=?');$s->execute([$id]);return $s->fetch();}
if(($argv[1]??'')==='post-worker'){
    $r=receipt($db,5);$intent=customer_payment_reviewed_intent($r);
    echo json_encode(customer_payment_post($db,$user,['receipt_id'=>5,'draft_revision'=>(int)$r['draft_revision'],'allocations'=>$intent['allocations']]));exit;
}
$checks=0;
function check(bool $ok,string $why):void {global $checks;$checks++;if(!$ok)throw new RuntimeException($why);}
function reject(callable $f,string $code):void {try{$f();}catch(AccountsApiError $e){check($e->errorCode===$code,'Expected '.$code.' got '.$e->errorCode);return;}throw new RuntimeException('Missing rejection '.$code);}
function all_hashes(PDO $db):array {
    $out=[];foreach($db->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN) as $t){
        if(!preg_match('/^[a-z0-9_]+$/D',$t))throw new RuntimeException('Unexpected table');
        $hashes=[];$q=$db->query("SELECT * FROM `$t`");while($r=$q->fetch(PDO::FETCH_NUM))$hashes[]=hash('sha256',serialize($r));sort($hashes,SORT_STRING);
        $out[$t]=hash('sha256',implode("\n",$hashes));
    }ksort($out);return $out;
}
function journals(PDO $db):int{return(int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn();}
function invoice(PDO $db,array $user,string $amount):int {
    $r=$db->query("SELECT * FROM qbook_invoices WHERE status='ISSUED' ORDER BY id LIMIT 1")->fetch();
    unset($r['id']);$r['reference_no']=billing_allocate_reference($db,'qbook_invoice_references');
    $r['client_id']=2;$r['client_name_snapshot']='DISPOSABLE LEGACY REVIEW QA';$r['invoice_date']='2026-08-24';
    $r['net_amount']=$amount;$r['vat_amount']='0.00';$r['total_amount']=$amount;$r['journal_id']=null;
    $cols=array_keys($r);$db->prepare('INSERT INTO qbook_invoices (`'.implode('`,`',$cols).'`) VALUES('.implode(',',array_fill(0,count($cols),'?')).')')->execute(array_values($r));
    return(int)$db->lastInsertId();
}
function review(PDO $db,array $user,int $id,array $alloc,bool $credit=false):array {
    $r=receipt($db,$id);
    $in=['action'=>'SAVE_REVIEW','receipt_id'=>$id,'draft_revision'=>(int)$r['draft_revision'],'request_key'=>bin2hex(random_bytes(32)),
        'review_completed'=>true,'client_credit_confirmed'=>$credit,'allocations'=>$alloc];
    $before=journals($db);$out=customer_payment_review_edit($db,$user,$in);
    check(journals($db)===$before,'Saving review posted journal');
    check((customer_payment_review_edit($db,$user,$in)['replayed']??false)===true,'Save retry not idempotent');
    return $out['receipt'];
}
function post_review(PDO $db,array $user,int $id):array {
    $r=receipt($db,$id);$intent=customer_payment_reviewed_intent($r);
    $in=['receipt_id'=>$id,'draft_revision'=>(int)$r['draft_revision'],'allocations'=>$intent['allocations']];
    $before=journals($db);$out=customer_payment_post($db,$user,$in);
    check(journals($db)===$before+1,'Expected exactly one payment journal');
    check((customer_payment_post($db,$user,$in)['replayed']??false)===true,'Posting retry not idempotent');
    check(journals($db)===$before+1,'Posting retry duplicated journal');return $out;
}
check(journals($db)===28,'Not a fresh clone');
$original=all_hashes($db);
foreach([1=>'5000000.00',2=>'483750.00',3=>'483750.00',4=>'483750.00',5=>'485000.00'] as $id=>$amount){
    $r=customer_payment_review_read($db,$user,$id)['receipt'];
    check($r['cash_amount']===$amount && $r['review_required']===true,'Wrong legacy draft '.$id);
    check(all_hashes($db)===$original,'Opening mutated database '.$id);
    reject(fn()=>customer_payment_post($db,$user,['receipt_id'=>$id]),'LEGACY_PAYMENT_REVIEW_REQUIRED');
    reject(fn()=>customer_payment_post($db,$user,['receipt_id'=>$id,'allocations'=>[]]),'LEGACY_PAYMENT_REVIEW_REQUIRED');
    check(all_hashes($db)===$original,'Rejected posting mutated database '.$id);
    echo 'draft_'.$id."_read_only_open_and_post_guard=passed\n";
}
reject(fn()=>customer_payment_review_read($db,['id'=>1,'role'=>'OPERATOR'],1),'FORBIDDEN');
reject(fn()=>customer_payment_review_edit($db,['id'=>1,'role'=>'OPERATOR'],[]),'FORBIDDEN');
$modern=receipt($db,1);$modern['creation_request_key']=str_repeat('a',64);
check(!customer_payment_legacy_review_required($modern),'Modern draft misclassified');
reject(fn()=>customer_payment_review_edit($db,$user,['receipt_id'=>3,'action'=>'SAVE_REVIEW','draft_revision'=>0,'request_key'=>bin2hex(random_bytes(32)),'review_completed'=>true,'allocations'=>[]]),'EXPLICIT_CLIENT_CREDIT_DECISION_REQUIRED');
$i=invoice($db,$user,'5000000.00');review($db,$user,1,[['invoice_id'=>$i,'cash_amount'=>'5000000.00']]);post_review($db,$user,1);
check(billing_invoice_outstanding($db,$i)['outstanding_minor']===0,'Invoice not settled');
review($db,$user,3,[],true);post_review($db,$user,3);
$cancel=['action'=>'CANCEL','receipt_id'=>4,'draft_revision'=>0,'request_key'=>bin2hex(random_bytes(32)),'reason'=>'Disposable QA cancellation'];
$before=journals($db);customer_payment_review_edit($db,$user,$cancel);customer_payment_review_edit($db,$user,$cancel);
check(receipt($db,4)['status']==='CANCELLED' && journals($db)===$before,'Cancellation accounting/idempotency failure');
$code=$db->query("SELECT * FROM qbook_tax_codes WHERE tax_type='WHT' AND is_active=1 AND effective_from<='2026-08-24' AND (effective_to IS NULL OR effective_to>='2026-08-24') AND rate_percent>0 ORDER BY id LIMIT 1")->fetch();
check((bool)$code,'No effective WHT code in copied configuration');
$wht=billing_percent_amount(100000,(string)$code['rate_percent']);$i=invoice($db,$user,accounts_minor_decimal(48375000+$wht));
$allocation=['invoice_id'=>$i,'cash_amount'=>'483750.00','wht_amount'=>accounts_minor_decimal($wht),'wht_tax_code_id'=>$code['id'],'wht_calculation_base_amount'=>'1000.00','certificate_status'=>'CERTIFICATE_PENDING'];
$invalid=$allocation;$invalid['wht_tax_code_id']=0;
reject(fn()=>review($db,$user,2,[$invalid]),'EFFECTIVE_TAX_CODE_REQUIRED');
review($db,$user,2,[$allocation]);post_review($db,$user,2);
check(billing_invoice_outstanding($db,$i)['outstanding_minor']===0,'WHT settlement failed');
$i=invoice($db,$user,'485000.00');review($db,$user,5,[['invoice_id'=>$i,'cash_amount'=>'485000.00']]);
$db->prepare('UPDATE qbook_invoices SET total_amount=? WHERE id=?')->execute(['484999.00',$i]);
reject(fn()=>post_review($db,$user,5),'PAYMENT_ALLOCATION_REVIEW_REQUIRED');
$db->prepare('UPDATE qbook_invoices SET total_amount=? WHERE id=?')->execute(['485000.00',$i]);
$workers=[];$before=journals($db);
for($n=0;$n<2;$n++){
    $p=proc_open([PHP_BINARY,__FILE__,'post-worker'],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
    check(is_resource($p),'Worker start failed');fclose($pipes[0]);$workers[]=[$p,$pipes];
}
$replays=0;foreach($workers as [$p,$pipes]){
    $out=stream_get_contents($pipes[1]);$err=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);
    check(proc_close($p)===0 && $err==='','Concurrent posting failed');$r=json_decode($out,true,512,JSON_THROW_ON_ERROR);
    if($r['replayed']??false)$replays++;
}
check($replays===1 && journals($db)===$before+1,'Concurrent posting duplicated journal');
check((int)$db->query('SELECT COUNT(*) FROM (SELECT journal_id FROM qbook_financial_journal_lines GROUP BY journal_id HAVING SUM(debit)<>SUM(credit)) x')->fetchColumn()===0,'Unbalanced journals');
check((int)$db->query('SELECT COUNT(*) FROM qbook_bank_matches')->fetchColumn()===0,'Unexpected reconciliation');
check((int)$db->query('SELECT COUNT(*) FROM qbook_customer_receipts WHERE statement_row_id IS NOT NULL OR active_statement_row_id IS NOT NULL')->fetchColumn()===0,'Unexpected statement ownership');
echo 'checks='.$checks."\nLEGACY_PAYMENT_DISPOSABLE_LIFECYCLE_PASSED\n";
