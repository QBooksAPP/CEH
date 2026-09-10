<?php
declare(strict_types=1);
require_once __DIR__.'/accounts_common.php';
/** Explicit row locks are the ownership authority. READ COMMITTED avoids
 * unrelated missing-owner next-key locks; retry only rolled-back DB work.
 * Callbacks must contain database work only, never uploads or external effects.
 */
function bank_ownership_transaction(PDO $db,callable $action):mixed {
 if($db->inTransaction())throw new LogicException('Ownership transaction must be outermost');
 for($attempt=0;$attempt<3;$attempt++){
  $db->exec('SET TRANSACTION ISOLATION LEVEL READ COMMITTED');
  try{return accounts_transaction($db,$action);}
  catch(PDOException $e){
   if(!in_array((int)($e->errorInfo[1]??0),[1205,1213],true))throw $e;
   if($attempt===2)accounts_fail('BANK_OWNERSHIP_CHANGED_REFRESH',409);
  }
 }
 throw new LogicException('Unreachable');
}
/** All consumers lock this physical row before inspecting existing ownership. */
function bank_row_available(PDO $db,int $id,string $ownType='',int $ownId=0):array {
 if(!$db->inTransaction())throw new LogicException('Bank row ownership requires a transaction');
 $s=$db->prepare('SELECT * FROM qbook_bank_statement_rows WHERE id=? FOR UPDATE');$s->execute([$id]);$r=$s->fetch();if(!$r)accounts_fail('BANK_ROW_NOT_FOUND',404);
 $s=$db->prepare('SELECT id FROM qbook_general_expense_refunds WHERE statement_row_id=? FOR UPDATE');$s->execute([$id]);if($s->fetch())accounts_fail('BANK_ROW_USED_AS_REFUND',409);
 $s=$db->prepare('SELECT source_type,source_record_id FROM qbook_bank_matches WHERE statement_row_id=? FOR UPDATE');$s->execute([$id]);if($s->fetch())accounts_fail('BANK_ROW_ALREADY_MATCHED',409);
 if(in_array($r['status'],['MATCHED','RECONCILED'],true))accounts_fail('BANK_ROW_ALREADY_MATCHED',409);
 $s=$db->prepare("SELECT id FROM qbook_general_expenses WHERE created_from_statement_row_id=? AND NOT(status='CANCELLED_NOT_SPENT' AND journal_id IS NULL) FOR UPDATE");$s->execute([$id]);
 foreach($s->fetchAll() as $e)if($ownType!=='GENERAL_EXPENSE'||(int)$e['id']!==$ownId)accounts_fail('BANK_ROW_RESERVED_BY_EXPENSE',409);
 $s=$db->prepare("SELECT id FROM qbook_customer_receipts WHERE statement_row_id=? AND status='POSTED' FOR UPDATE");$s->execute([$id]);
 foreach($s->fetchAll() as $e)if($ownType!=='CUSTOMER_RECEIPT'||(int)$e['id']!==$ownId)accounts_fail('BANK_ROW_USED_AS_RECEIPT',409);
 return $r;
}
