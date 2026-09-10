<?php
declare(strict_types=1);
require_once __DIR__.'/bank_workspace_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('GET');
accounts_endpoint(function():array {
 $db=production_db();$bank=bank_workspace_bank($db,(int)($_GET['bank_account_id']??0));$id=(int)($_GET['statement_row_id']??0);
 $q=$db->prepare('SELECT id FROM qbook_bank_statement_rows WHERE id=? AND bank_account_id=?');$q->execute([$id,$bank['id']]);if(!$q->fetch())accounts_fail('BANK_ROW_NOT_FOUND',404);
 $owner=bank_workspace_owner($db,$id);if(!$owner)accounts_fail('NO_LINKED_RECORD',404);
 $sql=match($owner['type']) {
 'GENERAL_EXPENSE'=>"SELECT e.expense_date date,e.amount,e.description,e.status,e.journal_id,CONCAT('CEH-EX-',LPAD(f.reference_no,6,'0')) reference FROM qbook_general_expenses e LEFT JOIN qbook_general_expense_references f ON f.expense_id=e.id WHERE e.id=?",
 'CUSTOMER_RECEIPT'=>"SELECT receipt_date date,cash_amount amount,narration description,status,journal_id,CONCAT('CEH-RCP-',LPAD(reference_no,6,'0')) reference,client_name_snapshot client FROM qbook_customer_receipts WHERE id=?",
 'PETTY_CASH_FUNDING'=>"SELECT funding_date date,amount,description,bank_reference reference,journal_id FROM qbook_petty_cash_fundings WHERE id=?",
 default=>null};
 if($sql===null)accounts_fail('SOURCE_VIEW_NOT_SUPPORTED',409);$q=$db->prepare($sql);$q->execute([$owner['id']]);$record=$q->fetch();if(!$record)accounts_fail('SOURCE_NOT_FOUND',404);return ['owner'=>$owner,'record'=>$record];
});
