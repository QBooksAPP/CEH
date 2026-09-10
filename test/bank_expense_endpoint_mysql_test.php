<?php
declare(strict_types=1);
if(($argv[1]??'')==='approve-worker'){
 echo json_encode(ep_request('general_expense_review.php',['expense_id'=>(int)$argv[2],'action'=>'APPROVE'],'local-admin',(int)$argv[3]));exit;
}
// Actual HTTP endpoint lifecycle. Only the disposable loopback MySQL is allowed.
// The repository's config.php is NEVER read or copied.
$db=new PDO('mysql:host=127.0.0.1;port=33318;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
if((int)$db->query('SELECT @@port')->fetchColumn()!==33318)throw new RuntimeException('Wrong test server');
$name='ceh_bank_expense_endpoint_test';$login='ceh_endpoint_test';
if($db->query("SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$name'")->fetchColumn())throw new RuntimeException('Test database already exists');
if($db->query("SELECT COUNT(*) FROM mysql.user WHERE User='$login'")->fetchColumn())throw new RuntimeException('Test user already exists');
$root=sys_get_temp_dir().DIRECTORY_SEPARATOR.'ceh-endpoint-'.bin2hex(random_bytes(8));
mkdir($root,0700);$server=null;$secondServer=null;$checks=0;
function ep_check(bool $condition,string $message):void{global $checks;$checks++;if(!$condition)throw new RuntimeException($message);}
function ep_request(string $endpoint,array $body,string $token='local-admin',int $port=33319):array {
 if(!in_array($port,[33319,33320],true))throw new RuntimeException('Loopback test port required');
 $context=stream_context_create(['http'=>['method'=>'POST','header'=>"Content-Type: application/json\r\nAuthorization: Bearer $token\r\n",'content'=>json_encode($body),'ignore_errors'=>true,'timeout'=>15]]);
 $raw=file_get_contents('http://127.0.0.1:'.$port.'/'.$endpoint,false,$context);
 $json=json_decode((string)$raw,true);if(!is_array($json))throw new RuntimeException('Non-JSON response from '.$endpoint);
 return $json;
}
function ep_ok(string $endpoint,array $body):array{$r=ep_request($endpoint,$body);ep_check(($r['ok']??false)===true,$endpoint.': '.($r['error']??'failed'));return $r;}
try {
 $db->exec("CREATE DATABASE $name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");$db->exec("USE $name");
 $db->exec(file_get_contents(__DIR__.'/fixtures/credit_note_schema.sql'));
 $db->exec(file_get_contents(__DIR__.'/../Server/migration_v1_23_bank_import_foundation.sql'));
 $db->exec(file_get_contents(__DIR__.'/../Server/migration_v1_24_bank_expense_reservation.sql'));
 $password=bin2hex(random_bytes(24));
 $db->exec("CREATE USER '$login'@'127.0.0.1' IDENTIFIED BY ".$db->quote($password));
 $db->exec("GRANT ALL ON $name.* TO '$login'@'127.0.0.1'");
 foreach(glob(__DIR__.'/../Server/*.php') as $file){if(basename($file)!=='config.php')copy($file,$root.DIRECTORY_SEPARATOR.basename($file));}
 file_put_contents($root.'/config.php','<?php return '.var_export(['db'=>['host'=>'127.0.0.1','port'=>33318,'name'=>$name,'charset'=>'utf8mb4','user'=>$login,'password'=>$password]],true).';');
 $db->exec("INSERT INTO qbook_companies(id,company_code,display_name)VALUES(1,'LOCAL-ENDPOINT','LOCAL QA'); INSERT INTO qbook_company_regional_settings(company_id,time_zone,date_format,time_format,base_currency)VALUES(1,'Africa/Lagos','DD-MM-YYYY','24_HOUR','NGN')");
 $db->exec("INSERT INTO qbook_users(id,company_id,full_name,role)VALUES(1,1,'Local Admin','ADMIN'),(2,1,'Local Operator','OPERATOR')");
 $db->exec("INSERT INTO qbook_auth_tokens(user_id,token_hash,expires_at)VALUES(1,SHA2('local-admin',256),DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 HOUR)),(2,SHA2('local-operator',256),DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 HOUR))");
 $db->exec("INSERT INTO qbook_accounts_chart(id,code,name,account_type)VALUES(1,'QA-BANK','Bank','ASSET'),(2,'QA-EXPENSE','Expense','EXPENSE'); INSERT INTO qbook_bank_accounts(id,name,bank_name,ledger_account_id)VALUES(1,'QA Bank','QA Bank',1); INSERT INTO qbook_cost_centres(id,code,name)VALUES(1,'QA','QA')");
 $db->exec("INSERT INTO qbook_bank_import_batches(id,bank_account_id,original_filename,file_type,file_sha256,imported_by)VALUES(1,1,'local.csv','CSV',SHA2('local',256),1)");
 $db->exec("INSERT INTO qbook_bank_statement_rows(id,import_batch_id,bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint)VALUES(1,1,1,'2026-09-01',-50,'QA-1','QA charge',SHA2('row1',256))");
 $immutable=$db->query('SELECT bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint FROM qbook_bank_statement_rows')->fetchAll();
 $server=proc_open([PHP_BINARY,'-d','extension_dir='.ini_get('extension_dir'),'-d','extension=pdo_mysql','-d','extension=mbstring','-S','127.0.0.1:33319','-t',$root],[0=>['pipe','r'],1=>['file',$root.'/http.log','a'],2=>['file',$root.'/http.log','a']],$pipes);
 if(!is_resource($server))throw new RuntimeException('HTTP server unavailable');fclose($pipes[0]);
 for($i=0;$i<30;$i++){$socket=@fsockopen('127.0.0.1',33319,$errno,$errstr,0.1);if($socket){fclose($socket);break;}usleep(100000);}
 $body=['statement_row_id'=>1,'is_bank_charge'=>true,'description'=>'QA charge','lines'=>[['expense_account_id'=>2,'cost_centre_id'=>1,'description'=>'QA charge','amount'=>'50.00']]];
 ep_check(ep_request('general_expense_create.php',$body,'local-operator')['error']==='FORBIDDEN','Non-admin create permitted');
 ep_check(ep_request('general_expense_create.php',$body,'invalid')['error']==='UNAUTHORIZED','Unauthenticated create permitted');
 $id=ep_ok('general_expense_create.php',$body)['expense']['id'];
 ep_check(ep_request('general_expense_create.php',$body)['error']==='BANK_ROW_RESERVED_BY_EXPENSE','Duplicate draft claim accepted');
 foreach([['bank_account_id'=>2],['expense_date'=>'2026-09-02'],['amount'=>'51.00'],['bank_reference'=>'wrong']] as $change){ep_check(ep_request('general_expense_update.php',['expense_id'=>$id]+$change)['error']==='STATEMENT_FIELDS_LOCKED','Statement field editable');}
 ep_ok('general_expense_update.php',['expense_id'=>$id]+$body);
 ep_ok('general_expense_submit.php',['expense_id'=>$id]);
 ep_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===0,'Draft/update/submit posted journal');
 ep_ok('general_expense_review.php',['expense_id'=>$id,'action'=>'CANCELLED_NOT_SPENT','reason'=>'Local cancelled draft test']);
 ep_check($db->query("SELECT active_statement_row_id FROM qbook_general_expenses WHERE id=$id")->fetchColumn()===null,'Cancelled reservation retained');
 $second=ep_ok('general_expense_create.php',$body)['expense']['id'];
 ep_check((int)$db->query("SELECT created_from_statement_row_id FROM qbook_general_expenses WHERE id=$id")->fetchColumn()===1,'Cancelled provenance erased');
 ep_ok('general_expense_submit.php',['expense_id'=>$second]);
 // Separate HTTP servers are necessary: Windows PHP's built-in server is single-threaded.
 $secondServer=proc_open([PHP_BINARY,'-d','extension_dir='.ini_get('extension_dir'),'-d','extension=pdo_mysql','-d','extension=mbstring','-S','127.0.0.1:33320','-t',$root],[0=>['pipe','r'],1=>['file',$root.'/http2.log','a'],2=>['file',$root.'/http2.log','a']],$pipes);
 if(!is_resource($secondServer))throw new RuntimeException('Second HTTP server unavailable');fclose($pipes[0]);
 for($i=0;$i<30;$i++){$socket=@fsockopen('127.0.0.1',33320,$errno,$errstr,0.1);if($socket){fclose($socket);break;}usleep(100000);}
 $db->beginTransaction();$db->query('SELECT id FROM qbook_bank_statement_rows WHERE id=1 FOR UPDATE')->fetch();$workers=[];
 foreach([33319,33320] as $port){$process=proc_open([PHP_BINARY,__FILE__,'approve-worker',(string)$second,(string)$port],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$workerPipes);fclose($workerPipes[0]);$workers[]=[$process,$workerPipes];}
 usleep(400000);$db->commit();$outcomes=[];
 foreach($workers as [$process,$workerPipes]){$raw=stream_get_contents($workerPipes[1]);$error=stream_get_contents($workerPipes[2]);fclose($workerPipes[1]);fclose($workerPipes[2]);ep_check(proc_close($process)===0&&$error==='','Approval worker failed');$outcomes[]=json_decode($raw,true);}
 ep_check(count(array_filter($outcomes,fn($r)=>($r['ok']??false)===true))===1,'Concurrent approvals did not produce exactly one winner');
 ep_check(count(array_filter($outcomes,fn($r)=>($r['error']??'')==='EXPENSE_NOT_REVIEWABLE'))===1,'Concurrent loser did not refresh safely');
 ep_check(ep_request('general_expense_review.php',['expense_id'=>$second,'action'=>'APPROVE'])['error']==='EXPENSE_NOT_REVIEWABLE','Approval replay not rejected safely');
 ep_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===1,'Approval journal count');
 ep_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journal_lines')->fetchColumn()===2,'Approval journal line count');
 $totals=$db->query('SELECT SUM(debit) d,SUM(credit) c FROM qbook_financial_journal_lines')->fetch();ep_check($totals['d']==='50.00'&&$totals['c']==='50.00','Unbalanced approval');
 ep_check((int)$db->query('SELECT COUNT(*) FROM qbook_bank_matches')->fetchColumn()===1,'Approval reconciliation count');
 ep_check($db->query('SELECT status FROM qbook_bank_statement_rows WHERE id=1')->fetchColumn()==='RECONCILED','Missing reconciled state');
 ep_check($immutable===$db->query('SELECT bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint FROM qbook_bank_statement_rows')->fetchAll(),'Immutable statement changed');
 ep_check((int)$db->query("SELECT COUNT(*) FROM qbook_financial_audit WHERE event_type='GENERAL_EXPENSE_APPROVED'")->fetchColumn()===1,'Duplicate approval audit');
 echo "BANK_EXPENSE_ENDPOINTS_PASSED checks=$checks\n";
} finally {
 if(is_resource($server)){proc_terminate($server);proc_close($server);}
 if(is_resource($secondServer)){proc_terminate($secondServer);proc_close($secondServer);}
 if($db->inTransaction())$db->rollBack();
 $db->exec("DROP DATABASE IF EXISTS $name");$db->exec("DROP USER IF EXISTS '$login'@'127.0.0.1'");
 foreach(new DirectoryIterator($root) as $file){if($file->isFile())unlink($file->getPathname());}rmdir($root);
 echo "DISPOSABLE_ENDPOINT_DATABASE_USER_AND_FILES_REMOVED\n";
}
