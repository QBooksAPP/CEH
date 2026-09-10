<?php
declare(strict_types=1);
require_once __DIR__.'/bank_workspace_common.php';
require_once __DIR__.'/bank_statement_parser.php';
function bank_transaction_detail_read(PDO $db,array $user,array $input):array {
 if(($user['role']??'')!=='ADMIN')accounts_fail('FORBIDDEN',403);
 return accounts_transaction($db,function()use($db,$input):array{
 $id=(int)($input['statement_row_id']??0);$bank=bank_workspace_bank($db,(int)($input['bank_account_id']??0));
 $usage=bank_workspace_usage_sql();
 $q=$db->prepare("SELECT r.*,($usage) usage_state FROM qbook_bank_statement_rows r WHERE r.id=? AND r.bank_account_id=?");$q->execute([$id,$bank['id']]);$row=$q->fetch();if(!$row)accounts_fail('BANK_ROW_NOT_FOUND',404);
 $owner=bank_workspace_owner($db,$id);$row['owner']=$owner;
 $q=$db->prepare("SELECT a.event_type action,a.created_at timestamp,u.full_name actor,a.source_type,a.source_record_id,a.details_json FROM qbook_financial_audit a LEFT JOIN qbook_users u ON u.id=a.actor_user_id WHERE (a.source_type='GENERAL_EXPENSE' AND a.source_record_id IN (SELECT e.id FROM qbook_general_expenses e WHERE e.created_from_statement_row_id=? UNION SELECT f.expense_id FROM qbook_general_expense_refunds f WHERE f.statement_row_id=?)) OR (a.source_type='BANK_MATCH' AND a.source_record_id IN (SELECT m.id FROM qbook_bank_matches m WHERE m.statement_row_id=?)) ORDER BY a.id DESC LIMIT 100");$q->execute([$id,$id,$id]);$history=$q->fetchAll();
 foreach($history as &$event){
  $details=json_decode((string)$event['details_json'],true)??[];
  $event['source_reference']=$details['reference_no']??null;
  $event['method']=$event['action']==='BANK_ROW_RECONCILED'?'ADMIN_CONFIRMED':($event['action']==='GENERAL_EXPENSE_APPROVED'?'EXPENSE_APPROVAL':null);
  $type=$event['source_type'];$sourceId=(int)$event['source_record_id'];
  if($type==='BANK_MATCH'){$lookup=$db->prepare('SELECT source_type,source_record_id,match_method FROM qbook_bank_matches WHERE id=?');$lookup->execute([$sourceId]);$match=$lookup->fetch();if($match){$type=$match['source_type'];$sourceId=(int)$match['source_record_id'];$event['method']=$match['match_method'];}}
  if($type==='GENERAL_EXPENSE'){$lookup=$db->prepare('SELECT reference_no FROM qbook_general_expense_references WHERE expense_id=?');$lookup->execute([$sourceId]);$ref=$lookup->fetchColumn();if($ref!==false)$event['source_reference']=accounts_general_expense_reference($ref);}
  elseif($type==='PETTY_CASH_FUNDING'){$lookup=$db->prepare('SELECT bank_reference FROM qbook_petty_cash_fundings WHERE id=?');$lookup->execute([$sourceId]);$event['source_reference']=$lookup->fetchColumn()?:null;}
  unset($event['details_json'],$event['source_record_id']);
 }unset($event);
 return ['bank'=>$bank,'transaction'=>$row,'history'=>$history,'can_create_expense'=>$owner===null&&$row['usage_state']==='AVAILABLE'&&accounts_money_minor($row['amount'],false)<0,'can_match'=>$owner===null&&$row['usage_state']==='AVAILABLE'&&accounts_money_minor($row['amount'],false)<0,'can_link_refund'=>$owner===null&&$row['usage_state']==='AVAILABLE'&&accounts_money_minor($row['amount'],false)>0];
 });
}
