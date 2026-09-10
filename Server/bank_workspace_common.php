<?php
declare(strict_types=1);
require_once __DIR__.'/accounts_common.php';
function bank_workspace_bank(PDO $db,int $id):array {
 $q=$db->prepare('SELECT id,name,bank_name,currency,account_reference FROM qbook_bank_accounts WHERE id=?');$q->execute([$id]);$b=$q->fetch();if(!$b)accounts_fail('BANK_ACCOUNT_NOT_FOUND',404);$ref=trim((string)$b['account_reference']);$b['masked_account_reference']=$ref===''?null:'•••• '.substr($ref,-4);unset($b['account_reference']);return $b;
}
function bank_workspace_page(array $in):array {
 $p=filter_var($in['page']??1,FILTER_VALIDATE_INT);$s=filter_var($in['page_size']??50,FILTER_VALIDATE_INT);
 if($p===false||$p<1||$p>1000000||$s===false||$s<1||$s>100)accounts_fail('INVALID_PAGE');return [$p,$s,($p-1)*$s];
}
function bank_workspace_usage_sql():string {
 return "CASE WHEN EXISTS(SELECT 1 FROM qbook_general_expense_refunds f WHERE f.statement_row_id=r.id) THEN 'REFUND'
 WHEN EXISTS(SELECT 1 FROM qbook_bank_matches m WHERE m.statement_row_id=r.id) OR r.status IN('MATCHED','RECONCILED') THEN 'RECONCILED'
 WHEN EXISTS(SELECT 1 FROM qbook_customer_receipts c WHERE c.statement_row_id=r.id AND c.status='POSTED') THEN 'PAYMENT'
 WHEN EXISTS(SELECT 1 FROM qbook_general_expenses e WHERE e.created_from_statement_row_id=r.id AND e.status='APPROVED') THEN 'EXPENSE'
 WHEN EXISTS(SELECT 1 FROM qbook_general_expenses e WHERE e.created_from_statement_row_id=r.id AND e.status<>'APPROVED' AND NOT(e.status='CANCELLED_NOT_SPENT' AND e.journal_id IS NULL)) THEN 'RESERVED_EXPENSE'
 ELSE 'AVAILABLE' END";
}
function bank_workspace_owner(PDO $db,int $row):?array {
 $q=$db->prepare('SELECT expense_id id FROM qbook_general_expense_refunds WHERE statement_row_id=?');$q->execute([$row]);if($v=$q->fetch())return ['type'=>'GENERAL_EXPENSE','id'=>(int)$v['id'],'relationship'=>'Refund'];
 $q=$db->prepare('SELECT source_type type,source_record_id id FROM qbook_bank_matches WHERE statement_row_id=?');$q->execute([$row]);if($v=$q->fetch())return ['type'=>$v['type'],'id'=>(int)$v['id'],'relationship'=>'Reconciled'];
 $q=$db->prepare("SELECT id FROM qbook_customer_receipts WHERE statement_row_id=? AND status='POSTED'");$q->execute([$row]);if($v=$q->fetch())return ['type'=>'CUSTOMER_RECEIPT','id'=>(int)$v['id'],'relationship'=>'Client Payment'];
 $q=$db->prepare("SELECT id,status FROM qbook_general_expenses WHERE created_from_statement_row_id=? AND NOT(status='CANCELLED_NOT_SPENT' AND journal_id IS NULL) ORDER BY id LIMIT 1");$q->execute([$row]);if($v=$q->fetch())return ['type'=>'GENERAL_EXPENSE','id'=>(int)$v['id'],'relationship'=>$v['status']==='APPROVED'?'Expense':'Reserved for Expense'];return null;
}
function bank_workspace_register(PDO $db,array $in):array {
 $bank=bank_workspace_bank($db,(int)($in['bank_account_id']??0));[$page,$size,$offset]=bank_workspace_page($in);
 $where=['r.bank_account_id=?'];$args=[(int)$bank['id']];$dir=$in['direction']??'ALL';if(!in_array($dir,['ALL','DEBIT','CREDIT'],true))accounts_fail('INVALID_DIRECTION');if($dir!=='ALL')$where[]=$dir==='DEBIT'?'r.amount<0':'r.amount>0';
 foreach(['date_from'=>'>=','date_to'=>'<='] as $key=>$op)if(trim((string)($in[$key]??''))!==''){$where[]="r.transaction_date $op ?";$args[]=accounts_date($in[$key]);}
 if(!empty($in['date_from'])&&!empty($in['date_to'])&&$in['date_from']>$in['date_to'])accounts_fail('INVALID_DATE_RANGE');
 if(trim((string)($in['amount']??''))!==''){$where[]='ABS(r.amount)=?';$args[]=accounts_minor_decimal(accounts_money_minor($in['amount']));}
 $search=trim((string)($in['search']??''));if(strlen($search)>200)accounts_fail('SEARCH_TOO_LONG');if($search!==''){$where[]="(LOCATE(?,r.narration)>0 OR LOCATE(?,COALESCE(r.bank_reference,''))>0)";$args[]=$search;$args[]=$search;}
 $usage=bank_workspace_usage_sql();$state=$in['usage']??'ALL';if(!in_array($state,['ALL','AVAILABLE','RESERVED_EXPENSE','EXPENSE','REFUND','PAYMENT','RECONCILED'],true))accounts_fail('INVALID_USAGE');if($state!=='ALL'){$where[]="($usage)=?";$args[]=$state;}
 $from=' FROM qbook_bank_statement_rows r WHERE '.implode(' AND ',$where);
 $q=$db->prepare("SELECT COUNT(*) total,COALESCE(SUM(r.amount<0),0) debit_count,COALESCE(SUM(r.amount>0),0) credit_count,COALESCE(SUM(CASE WHEN r.amount<0 THEN -r.amount ELSE 0 END),0) debit_total,COALESCE(SUM(CASE WHEN r.amount>0 THEN r.amount ELSE 0 END),0) credit_total".$from);$q->execute($args);$summary=$q->fetch();
 $q=$db->prepare("SELECT r.id,r.bank_account_id,r.transaction_date,r.value_date,r.amount,r.bank_reference,r.narration,r.statement_balance,r.import_batch_id,r.source_sheet,r.source_row,r.occurrence_number,($usage) usage_state".$from." ORDER BY r.transaction_date DESC,r.id DESC LIMIT $size OFFSET $offset");$q->execute($args);$rows=$q->fetchAll();foreach($rows as &$row)$row['owner']=bank_workspace_owner($db,(int)$row['id']);unset($row);
 return ['bank'=>$bank,'transactions'=>$rows,'summary'=>$summary,'page'=>$page,'page_size'=>$size,'total'=>(int)$summary['total'],'has_more'=>$offset+count($rows)<(int)$summary['total']];
}
function bank_workspace_imports(PDO $db,array $in):array {
 $bank=bank_workspace_bank($db,(int)($in['bank_account_id']??0));[$page,$size,$offset]=bank_workspace_page($in);$q=$db->prepare('SELECT COUNT(*) FROM qbook_bank_import_batches WHERE bank_account_id=?');$q->execute([$bank['id']]);$total=(int)$q->fetchColumn();
 $q=$db->prepare("SELECT b.*,u.full_name imported_by_name,up.full_name uploaded_by_name,ba.name account_name,ba.bank_name,ba.currency,d.uploaded_at,d.uploaded_by,d.adapter,d.byte_size,d.file_type document_type,
 (SELECT COUNT(*) FROM qbook_bank_statement_rows r WHERE r.import_batch_id=b.id) transaction_count,
 (SELECT COUNT(*) FROM qbook_bank_statement_rows r WHERE r.import_batch_id=b.id AND r.amount<0) debit_count,
 (SELECT COUNT(*) FROM qbook_bank_statement_rows r WHERE r.import_batch_id=b.id AND r.amount>0) credit_count,
 (SELECT COALESCE(SUM(-r.amount),0) FROM qbook_bank_statement_rows r WHERE r.import_batch_id=b.id AND r.amount<0) debit_total,
 (SELECT COALESCE(SUM(r.amount),0) FROM qbook_bank_statement_rows r WHERE r.import_batch_id=b.id AND r.amount>0) credit_total
 FROM qbook_bank_import_batches b JOIN qbook_bank_accounts ba ON ba.id=b.bank_account_id LEFT JOIN qbook_users u ON u.id=b.imported_by LEFT JOIN qbook_bank_statement_documents d ON d.id=b.document_id LEFT JOIN qbook_users up ON up.id=d.uploaded_by WHERE b.bank_account_id=? ORDER BY b.imported_at DESC,b.id DESC LIMIT $size OFFSET $offset");$q->execute([$bank['id']]);return ['bank'=>$bank,'imports'=>$q->fetchAll(),'page'=>$page,'total'=>$total,'has_more'=>$offset+$size<$total];
}
