<?php
declare(strict_types=1);
// Disposable local database ONLY. No application credentials or staging data.
require_once __DIR__.'/../Server/invoice_void_common.php';
restore_exception_handler();
function db():PDO{return new PDO('mysql:host=127.0.0.1;port=33317;dbname=ceh_invoice_void_test;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);}
function settlement(PDO $db,int $id,string $type):void{
    // Exercise the same current invoice lock/eligibility gate as settlement
    // endpoints; insert only the settlement rows consumed by the void contract.
    accounts_transaction($db,function()use($db,$id,$type){
        $i=billing_invoice_outstanding($db,$id,true);
        if($i['status']!=='ISSUED'||$i['outstanding_minor']<100)accounts_fail('INVOICE_ALLOCATION_MISMATCH',409);
        if($type==='advance')$db->exec("INSERT INTO qbook_advance_applications(invoice_id,amount) VALUES($id,1)");
        elseif($type==='credit'){$db->exec("INSERT INTO qbook_credit_notes(status) VALUES('ISSUED')");$n=$db->lastInsertId();$db->exec("INSERT INTO qbook_credit_note_allocations(invoice_id,credit_note_id,amount) VALUES($id,$n,1)");}
        else {$db->exec("INSERT INTO qbook_customer_receipts(status) VALUES('POSTED')");$n=$db->lastInsertId();$cash=$type==='wht'?0:1;$wht=$type==='wht'?1:0;$db->exec("INSERT INTO qbook_customer_receipt_allocations(invoice_id,receipt_id,cash_amount,wht_amount) VALUES($id,$n,$cash,$wht)");}
    });
}
if(($argv[1]??'')==='worker'){
    try {if($argv[2]==='void')invoice_void_execute(db(),['id'=>1,'role'=>'ADMIN'],['invoice_id'=>(int)$argv[3],'reason'=>'QA concurrency','void_date'=>'2026-09-07']);else settlement(db(),(int)$argv[3],$argv[2]);echo 'OK';}
    catch(AccountsApiError $e){echo $e->errorCode;}exit;
}
$checks=0;
function check(bool $ok,string $name):void{global $checks;if(!$ok)throw new RuntimeException($name);$checks++;}
function invoice(PDO $db):int{
    $db->exec("INSERT INTO qbook_invoices(status,total_amount) VALUES('ISSUED',100)");$id=(int)$db->lastInsertId();
    $db->beginTransaction();$j=accounts_post_journal($db,['id'=>1],['transaction_date'=>'2026-01-01','description'=>'QA invoice','source_module'=>'INVOICE','source_record_id'=>$id],[['account_id'=>1,'debit_minor'=>10000,'client_id'=>1,'project_id'=>1,'mixer_id'=>1,'cost_centre_id'=>1,'custodian_user_id'=>1],['account_id'=>2,'credit_minor'=>10000,'client_id'=>1,'project_id'=>1,'mixer_id'=>1,'cost_centre_id'=>1,'custodian_user_id'=>1]]);$db->commit();
    $db->exec("UPDATE qbook_invoices SET journal_id={$j['id']} WHERE id=$id");$db->exec("INSERT INTO qbook_invoice_lines(invoice_id) VALUES($id)");$l=$db->lastInsertId();$db->exec("INSERT INTO qbook_invoice_production_allocations(invoice_line_id,production_session_id,status) VALUES($l,1,'COMMITTED')");return $id;
}
function getInvoice(PDO $db,int $id):array{return $db->query("SELECT * FROM qbook_invoices WHERE id=$id")->fetch();}
function voidIt(PDO $db,int $id,array $extra=[]):array{return invoice_void_execute($db,['id'=>1,'role'=>'ADMIN'],array_merge(['invoice_id'=>$id,'reason'=>'QA void reason','void_date'=>'2026-09-07'],$extra));}
function rejects(callable $f,string $code):void{try{$f();throw new RuntimeException('Expected '.$code);}catch(AccountsApiError $e){check($e->errorCode===$code,$code);}}
function race(PDO $db,int $id,string $first,string $second):array{
    $db->beginTransaction();$db->query("SELECT id FROM qbook_invoices WHERE id=$id FOR UPDATE");$jobs=[];
    foreach([$first,$second] as $type){$p=proc_open([PHP_BINARY,'-d','extension_dir='.ini_get('extension_dir'),'-d','extension=pdo_mysql','-d','extension=mbstring',__FILE__,'worker',$type,(string)$id],[1=>['pipe','w'],2=>['pipe','w']],$pipes);$jobs[]=[$p,$pipes];usleep(200000);}
    $db->commit();$results=[];
    foreach($jobs as [$p,$pipes]){$results[]=stream_get_contents($pipes[1]);$err=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);check(proc_close($p)===0&&$err==='','race worker');}return $results;
}
try{
    $db=db();check($db->query('SELECT DATABASE()')->fetchColumn()==='ceh_invoice_void_test','local DB');
    check((int)$db->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE()')->fetchColumn()===0,'empty DB required');
    foreach([
      'CREATE TABLE qbook_users(id INT PRIMARY KEY,full_name VARCHAR(100))',
      'CREATE TABLE qbook_clients(id INT PRIMARY KEY)',
      'CREATE TABLE qbook_projects(id INT PRIMARY KEY,client_id INT)',
      'CREATE TABLE qbook_mixers(id INT PRIMARY KEY)',
      'CREATE TABLE qbook_cost_centres(id INT PRIMARY KEY,is_active INT)',
      'CREATE TABLE qbook_accounts_chart(id INT PRIMARY KEY,is_active INT,is_postable INT)',
      'CREATE TABLE qbook_invoices(id INT PRIMARY KEY AUTO_INCREMENT,status VARCHAR(20),total_amount DECIMAL(18,2),journal_id INT,voided_by INT,voided_at DATETIME,void_reason VARCHAR(500))',
      'CREATE TABLE qbook_invoice_lines(id INT PRIMARY KEY AUTO_INCREMENT,invoice_id INT)',
      'CREATE TABLE qbook_production_sessions(id INT PRIMARY KEY,description VARCHAR(100))',
      'CREATE TABLE qbook_invoice_production_allocations(id INT PRIMARY KEY AUTO_INCREMENT,invoice_line_id INT,production_session_id INT,status VARCHAR(20))',
      'CREATE TABLE qbook_customer_receipts(id INT PRIMARY KEY AUTO_INCREMENT,status VARCHAR(20))',
      'CREATE TABLE qbook_customer_receipt_allocations(id INT PRIMARY KEY AUTO_INCREMENT,invoice_id INT,receipt_id INT,cash_amount DECIMAL(18,2),wht_amount DECIMAL(18,2),KEY(invoice_id))',
      'CREATE TABLE qbook_advance_applications(id INT PRIMARY KEY AUTO_INCREMENT,invoice_id INT,amount DECIMAL(18,2),KEY(invoice_id))',
      'CREATE TABLE qbook_credit_notes(id INT PRIMARY KEY AUTO_INCREMENT,status VARCHAR(20))',
      'CREATE TABLE qbook_credit_note_allocations(id INT PRIMARY KEY AUTO_INCREMENT,invoice_id INT,credit_note_id INT,amount DECIMAL(18,2),KEY(invoice_id))',
      "CREATE TABLE qbook_financial_journals(id INT PRIMARY KEY AUTO_INCREMENT,reference_no VARCHAR(40) UNIQUE,transaction_date DATE,description VARCHAR(500),source_module VARCHAR(60),source_record_id INT,entry_kind VARCHAR(20) DEFAULT 'ORIGINAL',status VARCHAR(20) DEFAULT 'POSTED',reversal_of_id INT UNIQUE,created_by INT,approved_by INT,reversed_at DATETIME,UNIQUE(source_module,source_record_id,entry_kind))",
      'CREATE TABLE qbook_financial_journal_lines(id INT PRIMARY KEY AUTO_INCREMENT,journal_id INT,line_no INT,account_id INT,description VARCHAR(500),debit DECIMAL(18,2),credit DECIMAL(18,2),cost_centre_id INT,client_id INT,project_id INT,mixer_id INT,custodian_user_id INT)',
      'CREATE TABLE qbook_financial_audit(id INT PRIMARY KEY AUTO_INCREMENT,event_type VARCHAR(60),source_type VARCHAR(60),source_record_id INT,actor_user_id INT,details_json JSON)',
    ] as $sql)$db->exec($sql.' ENGINE=InnoDB');
    $db->exec("INSERT INTO qbook_users VALUES(1,'QA Admin');INSERT INTO qbook_clients VALUES(1);INSERT INTO qbook_projects VALUES(1,1);INSERT INTO qbook_mixers VALUES(1);INSERT INTO qbook_cost_centres VALUES(1,1);INSERT INTO qbook_accounts_chart VALUES(1,1,1),(2,1,1);INSERT INTO qbook_production_sessions VALUES(1,'Preserved QA production')");
    $id=invoice($db);$original=getInvoice($db,$id);check(invoice_void_contract($db,$original)['can_void'],'unpaid');
    rejects(fn()=>invoice_void_execute($db,['id'=>1,'role'=>'OPERATOR'],['invoice_id'=>$id]),'FORBIDDEN');
    rejects(fn()=>voidIt($db,$id,['reason'=>' ']),'REASON_REQUIRED');rejects(fn()=>voidIt($db,$id,['void_date'=>'2026-02-30']),'INVALID_DATE');
    foreach(['DRAFT','VOID'] as $status){$db->exec("UPDATE qbook_invoices SET status='$status' WHERE id=$id");rejects(fn()=>voidIt($db,$id),'ONLY_UNPAID_INVOICE_CAN_BE_VOIDED');}$db->exec("UPDATE qbook_invoices SET status='ISSUED' WHERE id=$id");
    $lines=$db->query("SELECT * FROM qbook_financial_journal_lines WHERE journal_id={$original['journal_id']} ORDER BY line_no")->fetchAll();
    $production=$db->query('SELECT * FROM qbook_production_sessions')->fetchAll();
    $result=voidIt($db,$id);$rev=$result['reversal']['id'];check(getInvoice($db,$id)['status']==='VOID','void status');
    $new=$db->query("SELECT * FROM qbook_financial_journal_lines WHERE journal_id=$rev ORDER BY line_no")->fetchAll();
    foreach($lines as $n=>$line){check($line['debit']===$new[$n]['credit']&&$line['credit']===$new[$n]['debit'],'sides reversed');foreach(['account_id','client_id','project_id','mixer_id','custodian_user_id','cost_centre_id'] as $dim)check($line[$dim]===$new[$n][$dim],'dimension '.$dim);}
    check($lines===$db->query("SELECT * FROM qbook_financial_journal_lines WHERE journal_id={$original['journal_id']} ORDER BY line_no")->fetchAll(),'original lines preserved');
    check($production===$db->query('SELECT * FROM qbook_production_sessions')->fetchAll(),'production preserved');
    check($db->query('SELECT status FROM qbook_invoice_production_allocations WHERE id=1')->fetchColumn()==='REVERSED','allocation reversed');
    $contract=invoice_void_contract($db,getInvoice($db,$id));check(!$contract['can_void']&&$contract['effective_void_date']==='2026-09-07'&&$contract['reversal_journal_id']===$rev&&$contract['voided_by_name']==='QA Admin','history');
    rejects(fn()=>voidIt($db,$id),'ONLY_UNPAID_INVOICE_CAN_BE_VOIDED');
    check((int)$db->query("SELECT COUNT(*) FROM qbook_financial_journals WHERE reversal_of_id={$original['journal_id']}")->fetchColumn()===1,'exactly one reversal');
    $audit=json_decode($db->query("SELECT details_json FROM qbook_financial_audit WHERE event_type='INVOICE_VOIDED' AND source_record_id=$id")->fetchColumn(),true);
    check($audit['reversed_allocation_ids']===[1]&&$audit['reversal_journal_id']===$rev,'audit metadata');
    foreach(['cash','wht','advance','credit'] as $type){$x=invoice($db);settlement($db,$x,$type);check(!invoice_void_contract($db,getInvoice($db,$x))['can_void'],'settlement block '.$type);rejects(fn()=>voidIt($db,$x),'ONLY_UNPAID_INVOICE_CAN_BE_VOIDED');}
    $x=invoice($db);settlement($db,$x,'cash');$db->exec("UPDATE qbook_customer_receipt_allocations SET cash_amount=100 WHERE invoice_id=$x");rejects(fn()=>voidIt($db,$x),'ONLY_UNPAID_INVOICE_CAN_BE_VOIDED');
    $x=invoice($db);$db->exec("INSERT INTO qbook_customer_receipts(status) VALUES('DRAFT')");$r=$db->lastInsertId();$db->exec("INSERT INTO qbook_customer_receipt_allocations(invoice_id,receipt_id,cash_amount,wht_amount) VALUES($x,$r,100,0)");check(invoice_void_contract($db,getInvoice($db,$x))['can_void'],'draft ignored');
    $db->exec("INSERT INTO qbook_customer_receipts(status) VALUES('POSTED')");check(invoice_void_contract($db,getInvoice($db,$x))['can_void'],'unallocated ignored');
    $x=invoice($db);$before=$db->query('SELECT * FROM qbook_financial_journals ORDER BY id')->fetchAll();
    $db->exec("CREATE TRIGGER qa_fail BEFORE UPDATE ON qbook_invoices FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='QA rollback'");
    try{voidIt($db,$x);throw new RuntimeException('rollback expected');}catch(PDOException $e){check(getInvoice($db,$x)['status']==='ISSUED','status rolled back');}
    $db->exec('DROP TRIGGER qa_fail');check($before===$db->query('SELECT * FROM qbook_financial_journals ORDER BY id')->fetchAll(),'reversal rolled back');
    foreach(['cash','advance','credit'] as $type){foreach([[$type,'void'],['void',$type]] as [$first,$second]){$x=invoice($db);$out=race($db,$x,$first,$second);check(count(array_filter($out,fn($r)=>$r==='OK'))===1,'one winner '.$type);$i=getInvoice($db,$x);$c=invoice_void_contract($db,$i);check(!$c['can_void'],'race authoritative outcome');}}
    $x=invoice($db);$out=race($db,$x,'void','void');check(count(array_filter($out,fn($r)=>$r==='OK'))===1,'duplicate void race');
    echo "INVOICE_VOID_MYSQL_PASSED assertions=$checks\n";
}catch(Throwable $e){fwrite(STDERR,$e->getMessage()."\n");exit(1);}
