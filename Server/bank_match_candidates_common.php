<?php
declare(strict_types=1);
require_once __DIR__.'/bank_workspace_common.php';
require_once __DIR__.'/bank_statement_parser.php';
function bank_match_candidates_read(PDO $db,array $user,array $input):array {
 if(($user['role']??'')!=='ADMIN')accounts_fail('FORBIDDEN',403);
 return accounts_transaction($db,function()use($db,$input):array{
 $id=(int)($input['statement_row_id']??0);[$page,$size,$offset]=bank_workspace_page($input);
 $bank=bank_workspace_bank($db,(int)($input['bank_account_id']??0));
 $q=$db->prepare('SELECT * FROM qbook_bank_statement_rows WHERE id=? AND bank_account_id=?');$q->execute([$id,(int)($input['bank_account_id']??0)]);$r=$q->fetch();if(!$r)accounts_fail('BANK_ROW_NOT_FOUND',404);
 if(bank_workspace_owner($db,$id)!==null||in_array($r['status'],['MATCHED','RECONCILED'],true))return ['candidates'=>[],'total'=>0,'page'=>$page,'has_more'=>false];
 if(accounts_money_minor($r['amount'],false)>0){
  $search=trim((string)($input['search']??''));if(strlen($search)>200)accounts_fail('SEARCH_TOO_LONG');
  $from=" FROM qbook_general_expenses e LEFT JOIN qbook_general_expense_references f ON f.expense_id=e.id WHERE e.status='APPROVED' AND e.journal_id IS NOT NULL AND e.bank_account_id=? AND e.amount-(SELECT COALESCE(SUM(rf.amount),0) FROM qbook_general_expense_refunds rf WHERE rf.expense_id=e.id)>=? AND (LOCATE(?,COALESCE(e.description,''))>0 OR LOCATE(?,CONCAT('CEH-EX-',LPAD(f.reference_no,6,'0')))>0)";
  $args=[$r['bank_account_id'],$r['amount'],$search,$search];$q=$db->prepare('SELECT COUNT(*)'.$from);$q->execute($args);$total=(int)$q->fetchColumn();
  $q=$db->prepare("SELECT e.id,'GENERAL_EXPENSE' source_type,e.expense_date source_date,e.amount,e.description,e.supplier_name_snapshot payee,CONCAT('CEH-EX-',LPAD(f.reference_no,6,'0')) reference".$from." ORDER BY e.expense_date DESC,e.id DESC LIMIT $size OFFSET $offset");$q->execute($args);
  return ['bank'=>$bank,'candidates'=>$q->fetchAll(),'total'=>$total,'page'=>$page,'has_more'=>$offset+$size<$total,'purpose'=>'REFUND'];
 }
 $sql="SELECT e.id,'GENERAL_EXPENSE' source_type,e.bank_account_id,e.expense_date source_date,e.amount,e.bank_reference,e.description,CONCAT('CEH-EX-',LPAD(f.reference_no,6,'0')) reference,e.supplier_name_snapshot payee FROM qbook_general_expenses e JOIN qbook_financial_journals j ON j.id=e.journal_id AND j.status='POSTED' LEFT JOIN qbook_general_expense_references f ON f.expense_id=e.id WHERE e.status='APPROVED' AND (e.created_from_statement_row_id IS NULL OR e.created_from_statement_row_id=:row)
 UNION ALL SELECT p.id,'PETTY_CASH_FUNDING',p.bank_account_id,p.funding_date,p.amount,p.bank_reference,p.description,p.bank_reference,u.full_name FROM qbook_petty_cash_fundings p JOIN qbook_financial_journals j ON j.id=p.journal_id AND j.status='POSTED' LEFT JOIN qbook_users u ON u.id=p.custodian_user_id";
 $search=trim((string)($input['search']??''));if(strlen($search)>200)accounts_fail('SEARCH_TOO_LONG');
 $where=" FROM ($sql) c WHERE c.bank_account_id=:bank AND c.amount=:amount AND ABS(DATEDIFF(c.source_date,:date))<=3 AND NOT EXISTS(SELECT 1 FROM qbook_bank_matches m WHERE m.source_type=c.source_type AND m.source_record_id=c.id)";
 $args=['row'=>$id,'bank'=>$r['bank_account_id'],'amount'=>accounts_minor_decimal(-accounts_money_minor($r['amount'],false)),'date'=>$r['transaction_date']];
 // Match the existing normalization: collapse whitespace and compare uppercase.
 $ref=bank_normalize_text($r['bank_reference']??'',150);if($ref!==''){$where.=" AND UPPER(TRIM(REGEXP_REPLACE(COALESCE(c.bank_reference,''),'[[:space:]]+',' ')))=:reference";$args['reference']=$ref;}
 if($search!==''){$where.=' AND (LOCATE(:search1,c.reference)>0 OR LOCATE(:search2,COALESCE(c.description,\'\'))>0 OR LOCATE(:search3,COALESCE(c.payee,\'\'))>0)';$args+=['search1'=>$search,'search2'=>$search,'search3'=>$search];}
 $q=$db->prepare('SELECT COUNT(*)'.$where);$q->execute($args);$total=(int)$q->fetchColumn();
 $q=$db->prepare('SELECT c.*'.$where." ORDER BY c.source_date,c.source_type,c.id LIMIT $size OFFSET $offset");$q->execute($args);
 return ['bank'=>$bank,'candidates'=>$q->fetchAll(),'total'=>$total,'page'=>$page,'has_more'=>$offset+$size<$total];
 });
}
