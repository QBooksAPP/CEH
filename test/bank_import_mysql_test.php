<?php
declare(strict_types=1);
require_once __DIR__.'/../Server/bank_import_common.php';
require_once __DIR__.'/../Server/bank_row_usage.php';
production_discard_output();restore_exception_handler();
set_exception_handler(function(Throwable $e):never{fwrite(STDERR,$e->getMessage().' at '.$e->getLine()."\n");exit(1);});
function bm_db():PDO{return new PDO('mysql:host=127.0.0.1;port=33318;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);}
$db=bm_db();if((int)$db->query('SELECT @@port')->fetchColumn()!==33318)exit('Wrong local server');
$name='ceh_bank_import_disposable_test';$user=['id'=>1,'role'=>'ADMIN'];
if(($argv[1]??'')==='child'){$db->exec("USE $name");echo json_encode(bank_import_commit($db,$user,(int)$argv[2],$argv[3]));exit;}
if(($argv[1]??'')==='claim'){
 $db->exec("USE $name");try{accounts_transaction($db,function()use($db,$argv){bank_row_available($db,(int)$argv[2]);$db->prepare("INSERT INTO qbook_bank_matches(statement_row_id,source_type,source_record_id,matched_by)VALUES(?,'GENERAL_EXPENSE',?,1)")->execute([(int)$argv[2],(int)$argv[3]]);});echo 'CLAIMED';}catch(AccountsApiError $e){echo $e->errorCode;}exit;
}
$checks=0;function bm_check(bool $ok,string $m):void{global $checks;$checks++;if(!$ok)throw new RuntimeException($m);}
function bm_reject(callable $f,string $code):void{try{$f();}catch(AccountsApiError $e){bm_check($e->errorCode===$code,'Unexpected '.$e->errorCode);return;}throw new RuntimeException('Expected '.$code);}
$q=$db->prepare('SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=?');$q->execute([$name]);if($q->fetchColumn())exit('Disposable database exists; refusing overwrite');
$db->exec("CREATE DATABASE $name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");$tmp=tempnam(sys_get_temp_dir(),'ceh-bank-');
try{
 $db->exec("USE $name");$db->exec(file_get_contents(__DIR__.'/fixtures/credit_note_schema.sql'));
 $db->exec("INSERT INTO qbook_companies(id,company_code,display_name)VALUES(1,'LOCAL-BANK-QA','LOCAL BANK QA')");
 $db->exec("INSERT INTO qbook_users(id,company_id,full_name,role)VALUES(1,1,'LOCAL QA ADMIN','ADMIN')");
 $db->exec("INSERT INTO qbook_accounts_chart(id,code,name,account_type)VALUES(1,'QA-BANK','QA Bank','ASSET'),(2,'QA-BANK2','QA Bank 2','ASSET')");
 $db->exec("INSERT INTO qbook_bank_accounts(id,name,bank_name,ledger_account_id)VALUES(1,'QA Bank','Zenith',1),(2,'QA Bank 2','Other',2)");
 $db->exec("INSERT INTO qbook_bank_import_batches(id,bank_account_id,original_filename,file_type,file_sha256,imported_by)VALUES(101,1,'legacy.csv','CSV',SHA2('legacy',256),1)");
 $db->exec("INSERT INTO qbook_bank_statement_rows(id,import_batch_id,bank_account_id,transaction_date,amount,narration,row_fingerprint)VALUES(101,101,1,'2020-01-01',-1,'Legacy',SHA2('legacy-row',256))");
 $legacy=$db->query('SELECT * FROM qbook_bank_statement_rows WHERE id=101')->fetch();
 $db->exec(file_get_contents(__DIR__.'/../Server/migration_v1_23_bank_import_foundation.sql'));
 $after=$db->query('SELECT * FROM qbook_bank_statement_rows WHERE id=101')->fetch();
 bm_check(array_intersect_key($after,$legacy)===$legacy&&$after['source_row']===null,'Migration changed legacy row');
 $csv="Create Date,Effective Date,Description/Payee/Memo,Debit Amount,Credit Amount,Balance,Transaction Ref\n01/09/2026,01/09/2026,Charge,50,,950,\n01/09/2026,01/09/2026,Charge,50,,900,\n01/09/2026,01/09/2026,Charge,53.75,,846.25,SAME\n01/09/2026,01/09/2026,Charge,53.75,,792.50,SAME\n";
 file_put_contents($tmp,$csv);
 $d=bank_import_preview($db,$user,1,'qa.csv',$tmp,'ZENITH_ACTIVITY_V1');$id=$d['document_id'];$p=bank_import_plan($db,$id);
 bm_check(count($p['rows'])===4&&$p['summary']['can_import'],'Preview rows');
 bm_check((int)$db->query('SELECT COUNT(*) FROM qbook_bank_statement_rows')->fetchColumn()===1,'Upload imported rows');
 bm_check(bank_import_preview($db,$user,1,'renamed.csv',$tmp,'ZENITH_ACTIVITY_V1')['document_id']===$id,'Upload retry');
 bm_reject(fn()=>bank_import_commit($db,$user,$id,'bad'),'PREVIEW_CHANGED');
 $result=bank_import_commit($db,$user,$id,$p['confirmation_sha256']);bm_check($result['imported']===4,'Import discarded identical rows');
 bm_check(bank_import_commit($db,$user,$id,$p['confirmation_sha256'])['replayed'],'Timeout retry duplicated');
 bm_check(bank_import_plan($db,$id)['summary']['already_imported_source_rows']===4,'Replay outcomes');
 bm_check($db->query('SELECT SHA2(document_data,256)=sha256 FROM qbook_bank_statement_documents WHERE id='.$id)->fetchColumn()==1,'Original file hash');
 bm_check($db->query('SELECT document_data FROM qbook_bank_statement_documents WHERE id='.$id)->fetchColumn()===$csv,'Original file bytes');
 bm_check((int)$db->query("SELECT COUNT(*) FROM qbook_financial_audit WHERE event_type='BANK_STATEMENT_IMPORTED'")->fetchColumn()===1,'Audit replay');
 file_put_contents($tmp,$csv."\n");$over=bank_import_preview($db,$user,1,'overlap.csv',$tmp,'ZENITH_ACTIVITY_V1')['document_id'];
 bm_check(!bank_import_plan($db,$over)['summary']['can_import'],'Ambiguous overlap accepted');bm_reject(fn()=>bank_import_commit($db,$user,$over,'x'),'STATEMENT_REVIEW_REQUIRED');
 $other=bank_import_preview($db,$user,2,'qa.csv',$tmp,'ZENITH_ACTIVITY_V1')['document_id'];$plan=bank_import_plan($db,$other);
 $children=[];for($i=0;$i<2;$i++){$proc=proc_open([PHP_BINARY,'-d','extension_dir='.ini_get('extension_dir'),'-d','extension=pdo_mysql','-d','extension=mbstring',__FILE__,'child',(string)$other,$plan['confirmation_sha256']],[['pipe','r'],['pipe','w'],['pipe','w']],$pipes);fclose($pipes[0]);$children[]=[$proc,$pipes];}
 foreach($children as [$proc,$pipes]){$out=stream_get_contents($pipes[1]);$err=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);bm_check(proc_close($proc)===0,'Concurrent import failed '.$err);bm_check(isset(json_decode($out,true)['batch_id']),'Concurrent result');}
 bm_check((int)$db->query('SELECT COUNT(*) FROM qbook_bank_statement_rows WHERE bank_account_id=2')->fetchColumn()===4,'Concurrent duplicates');
 bm_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===0,'Import posted journal');
 $row=(int)$db->query('SELECT MIN(id) FROM qbook_bank_statement_rows WHERE import_batch_id='.(int)$result['batch_id'])->fetchColumn();
 $db->beginTransaction();bm_check(bank_row_available($db,$row)['id']==$row,'Unused row unavailable');$db->rollBack();
 $db->exec("INSERT INTO qbook_bank_matches(statement_row_id,source_type,source_record_id,matched_by)VALUES($row,'GENERAL_EXPENSE',99,1)");
 $db->beginTransaction();bm_reject(fn()=>bank_row_available($db,$row),'BANK_ROW_ALREADY_MATCHED');$db->rollBack();
 $free=$row+1;
 $db->exec("INSERT INTO qbook_general_expenses(id,created_by,created_from_statement_row_id,bank_account_id,amount,status)VALUES(101,1,$free,1,50,'DRAFT')");
 $db->beginTransaction();bm_reject(fn()=>bank_row_available($db,$free),'BANK_ROW_RESERVED_BY_EXPENSE');bm_check(bank_row_available($db,$free,'GENERAL_EXPENSE',101)['id']==$free,'Owning expense excluded');$db->rollBack();
 $db->exec("INSERT INTO qbook_general_expense_refunds(expense_id,statement_row_id,amount,linked_by)VALUES(101,".($row+2).",50,1)");
 $db->beginTransaction();bm_reject(fn()=>bank_row_available($db,$row+2),'BANK_ROW_USED_AS_REFUND');$db->rollBack();
 $db->exec("INSERT INTO qbook_clients(id,name)VALUES(101,'LOCAL QA')");
 $db->exec("INSERT INTO qbook_customer_receipt_references(reference_no)VALUES(101)");
 $db->exec("INSERT INTO qbook_customer_receipts(id,reference_no,client_id,client_name_snapshot,bank_account_id,receipt_date,cash_amount,destination,status,statement_row_id,created_by)VALUES(101,101,101,'LOCAL QA',1,'2026-09-01',50,'TRADE_RECEIVABLES','POSTED',".($row+3).",1)");
 $db->beginTransaction();bm_reject(fn()=>bank_row_available($db,$row+3),'BANK_ROW_USED_AS_RECEIPT');$db->rollBack();
 $claimRow=(int)$db->query('SELECT MIN(id) FROM qbook_bank_statement_rows WHERE bank_account_id=2')->fetchColumn();$children=[];$results=[];
 for($i=0;$i<2;$i++){$proc=proc_open([PHP_BINARY,'-d','extension_dir='.ini_get('extension_dir'),'-d','extension=pdo_mysql','-d','extension=mbstring',__FILE__,'claim',(string)$claimRow,(string)(200+$i)],[['pipe','r'],['pipe','w'],['pipe','w']],$pipes);fclose($pipes[0]);$children[]=[$proc,$pipes];}
 foreach($children as [$proc,$pipes]){$results[]=stream_get_contents($pipes[1]);$err=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);bm_check(proc_close($proc)===0,'Concurrent claim failed '.$err);}
 sort($results);bm_check($results===['BANK_ROW_ALREADY_MATCHED','CLAIMED'],'Two incompatible consumers acquired row');
 bm_reject(fn()=>bank_import_commit($db,['id'=>1,'role'=>'OPERATOR'],$id,''),'FORBIDDEN');
 bm_check((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===0,'Ownership check posted journal');
 echo "BANK_IMPORT_MYSQL_PASSED checks=$checks\n";
}finally{if($db->inTransaction())$db->rollBack();$db->exec("DROP DATABASE $name");if(is_file($tmp))unlink($tmp);echo "DISPOSABLE_BANK_DATABASE_REMOVED\n";}
