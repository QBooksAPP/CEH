<?php
declare(strict_types=1);
require_once __DIR__.'/../Server/bank_workspace_common.php';
production_discard_output();restore_exception_handler();
set_exception_handler(function(Throwable $e):never{fwrite(STDERR,$e->getMessage().' line '.$e->getLine()."\n");exit(1);});
$db=new PDO('mysql:host=127.0.0.1;port=33318;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);
if((int)$db->query('SELECT @@port')->fetchColumn()!==33318)exit('Wrong local server');
$name='ceh_bank_workspace_disposable_test';$q=$db->prepare('SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=?');$q->execute([$name]);if($q->fetchColumn())throw new RuntimeException('Test database exists');
$checks=0;function check_ws(bool $ok,string $why):void{global $checks;$checks++;if(!$ok)throw new RuntimeException($why);}
$db->exec("CREATE DATABASE $name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
try {
 $db->exec("USE $name");$db->exec(file_get_contents(__DIR__.'/fixtures/credit_note_schema.sql'));$db->exec(file_get_contents(__DIR__.'/../Server/migration_v1_23_bank_import_foundation.sql'));
 $db->exec("INSERT INTO qbook_companies(id,company_code,display_name) VALUES(1,'QA','QA')");$db->exec("INSERT INTO qbook_users(id,company_id,full_name,role)VALUES(1,1,'QA','ADMIN')");
 $db->exec("INSERT INTO qbook_accounts_chart(id,code,name,account_type)VALUES(1,'QA1','QA','ASSET'),(2,'QA2','QA','ASSET')");$db->exec("INSERT INTO qbook_bank_accounts(id,name,bank_name,ledger_account_id)VALUES(1,'QA Bank','QA',1),(2,'Other Bank','QA',2)");
 $db->exec("INSERT INTO qbook_bank_import_batches(id,bank_account_id,original_filename,file_type,file_sha256,imported_by)VALUES(1,1,'local.csv','CSV',SHA2('local',256),1),(2,2,'other.csv','CSV',SHA2('other',256),1)");
 $amounts=array_merge(array_fill(0,258,'-50.00'),array_fill(0,3,'50.00'),array_fill(0,100,'-53.75'),array_fill(0,2,'53.75'),array_fill(0,69,'-26.88'),array_fill(0,279,'-100.00'),array_fill(0,8,'100.00'));
 $q=$db->prepare("INSERT INTO qbook_bank_statement_rows(import_batch_id,bank_account_id,transaction_date,amount,narration,bank_reference,row_fingerprint,source_sheet,source_row,occurrence_number)VALUES(1,1,'2026-08-01',?,'Repeated legitimate charge',?,SHA2('same content',256),'Sheet',?,?)");
 foreach($amounts as $i=>$a)$q->execute([$a,'REF-'.$i,$i+2,$i+1]);
 $db->exec("INSERT INTO qbook_bank_statement_rows(import_batch_id,bank_account_id,transaction_date,amount,narration,row_fingerprint)VALUES(2,2,'2026-07-01',-50,'Other bank',SHA2('other',256))");
 $before=$db->query('SELECT * FROM qbook_bank_statement_rows ORDER BY id')->fetchAll();
 $p=bank_workspace_register($db,['bank_account_id'=>1]);check_ws($p['total']===719&&count($p['transactions'])===50,'Pagination default');check_ws((int)$p['summary']['debit_count']===706&&(int)$p['summary']['credit_count']===13,'Directions');
 $ids=[];for($page=1;$page<=15;$page++){$p=bank_workspace_register($db,['bank_account_id'=>1,'page'=>$page]);$ids=array_merge($ids,array_column($p['transactions'],'id'));}
 check_ws(count($ids)===719&&count(array_unique($ids))===719,'All 719 visible once');check_ws($ids===array_reverse(range(1,719)),'Stable date/id order');check_ws(!$p['has_more']&&count($p['transactions'])===19,'Last page');
 foreach(['50.00'=>261,'53.75'=>102,'26.88'=>69] as $a=>$n)check_ws(bank_workspace_register($db,['bank_account_id'=>1,'amount'=>$a])['total']===$n,'All physical fee rows');
 check_ws(bank_workspace_register($db,['bank_account_id'=>2])['total']===1,'Cross-bank isolation');
 check_ws(bank_workspace_register($db,['bank_account_id'=>1,'search'=>'REF-0'])['total']===1,'Search beyond first page');
 check_ws(bank_workspace_register($db,['bank_account_id'=>1,'direction'=>'CREDIT'])['total']===13,'Credit filter');
 check_ws(bank_workspace_register($db,['bank_account_id'=>1,'direction'=>'DEBIT'])['total']===706,'Debit filter');
 check_ws(bank_workspace_register($db,['bank_account_id'=>1,'date_to'=>'2026-07-31'])['total']===0,'Date boundary');
 check_ws(bank_workspace_register($db,['bank_account_id'=>1,'date_from'=>'2026-08-01','date_to'=>'2026-08-01'])['total']===719,'Inclusive dates');
 check_ws(bank_workspace_register($db,['bank_account_id'=>1,'usage'=>'AVAILABLE'])['total']===719,'Available');
 $history=bank_workspace_imports($db,['bank_account_id'=>1]);check_ws($history['total']===1&&(int)$history['imports'][0]['transaction_count']===719,'History counts');
 check_ws($before===$db->query('SELECT * FROM qbook_bank_statement_rows ORDER BY id')->fetchAll(),'Reads immutable');
 $db->exec("INSERT INTO qbook_general_expenses(id,created_by,created_from_statement_row_id,bank_account_id,amount,status)VALUES(1,1,1,1,50,'DRAFT'),(2,1,2,1,50,'APPROVED')");
 check_ws(bank_workspace_register($db,['bank_account_id'=>1,'usage'=>'RESERVED_EXPENSE'])['total']===1,'Reserved ownership');check_ws(bank_workspace_register($db,['bank_account_id'=>1,'usage'=>'EXPENSE'])['total']===1,'Expense ownership');
 $db->exec("INSERT INTO qbook_general_expense_refunds(expense_id,statement_row_id,amount,linked_by)VALUES(1,3,50,1)");check_ws(bank_workspace_register($db,['bank_account_id'=>1,'usage'=>'REFUND'])['total']===1,'Refund ownership');
 $db->exec("INSERT INTO qbook_bank_matches(statement_row_id,source_type,source_record_id,matched_by)VALUES(4,'GENERAL_EXPENSE',2,1)");check_ws(bank_workspace_register($db,['bank_account_id'=>1,'usage'=>'RECONCILED'])['total']===1,'Match ownership');
 check_ws(bank_workspace_owner($db,3)['id']===1,'Refund source');check_ws(bank_workspace_owner($db,4)['id']===2,'Reconciled source');
 check_ws((int)$db->query('SELECT COUNT(*) FROM qbook_financial_journals')->fetchColumn()===0,'No journals');
 echo "BANK_WORKSPACE_MYSQL_PASSED checks=$checks\n";
}finally{$db->exec("DROP DATABASE $name");echo "DISPOSABLE_WORKSPACE_DATABASE_REMOVED\n";}
