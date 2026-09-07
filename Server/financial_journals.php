<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('GET');
accounts_endpoint(function(): array {
    $db=production_db();
    $sourceReferenceSql="CASE j.source_module WHEN 'INVOICE' THEN (SELECT CONCAT('CEH-INV-',LPAD(i.reference_no,6,'0')) FROM qbook_invoices i WHERE i.id=j.source_record_id) WHEN 'CUSTOMER_RECEIPT' THEN (SELECT CONCAT('CEH-RCP-',LPAD(cr.reference_no,6,'0')) FROM qbook_customer_receipts cr WHERE cr.id=j.source_record_id) WHEN 'CREDIT_NOTE' THEN (SELECT CONCAT('CEH-CN-',LPAD(cn.reference_no,6,'0')) FROM qbook_credit_notes cn WHERE cn.id=j.source_record_id) WHEN 'PETTY_CASH_EXPENSE' THEN (SELECT CONCAT('CEH-PC-',LPAD(pr.reference_no,6,'0')) FROM qbook_petty_cash_expense_references pr WHERE pr.expense_id=j.source_record_id) WHEN 'GENERAL_EXPENSE' THEN (SELECT CONCAT('CEH-EX-',LPAD(gr.reference_no,6,'0')) FROM qbook_general_expense_references gr WHERE gr.expense_id=j.source_record_id) WHEN 'PETTY_CASH_FUNDING' THEN (SELECT f.bank_reference FROM qbook_petty_cash_fundings f WHERE f.id=j.source_record_id) ELSE NULL END";
    $journalId=(int)($_GET['journal_id']??0);
    $lineSql="SELECT l.id,l.line_no,c.code AS account_code,c.name AS account_name,l.description,l.debit,l.credit,l.cost_centre_id,cc.code AS cost_centre_code,cc.name AS cost_centre_name,l.client_id,cl.name AS client_name,l.project_id,p.name AS project_name,l.mixer_id,m.code AS mixer_code,l.custodian_user_id,cu.full_name AS custodian_name FROM qbook_financial_journal_lines l JOIN qbook_accounts_chart c ON c.id=l.account_id LEFT JOIN qbook_cost_centres cc ON cc.id=l.cost_centre_id LEFT JOIN qbook_clients cl ON cl.id=l.client_id LEFT JOIN qbook_projects p ON p.id=l.project_id LEFT JOIN qbook_mixers m ON m.id=l.mixer_id LEFT JOIN qbook_users cu ON cu.id=l.custodian_user_id WHERE l.journal_id=? ORDER BY l.line_no";
    if($journalId>0){
        $s=$db->prepare("SELECT j.*,{$sourceReferenceSql} source_reference,u.full_name created_by_name,a.full_name approved_by_name,o.reference_no original_reference,r.id reversal_id,r.reference_no reversal_reference FROM qbook_financial_journals j JOIN qbook_users u ON u.id=j.created_by LEFT JOIN qbook_users a ON a.id=j.approved_by LEFT JOIN qbook_financial_journals o ON o.id=j.reversal_of_id LEFT JOIN qbook_financial_journals r ON r.reversal_of_id=j.id WHERE j.id=?");$s->execute([$journalId]);$row=$s->fetch();if(!$row)accounts_fail('JOURNAL_NOT_FOUND',404);
        $line=$db->prepare($lineSql);$line->execute([$journalId]);$row['lines']=$line->fetchAll();unset($row['created_by'],$row['approved_by']);return ['journal'=>$row];
    }
    $page=max(1,(int)($_GET['page']??1));$pageSize=min(100,max(10,(int)($_GET['page_size']??25)));$offset=($page-1)*$pageSize;
    $where=[];$params=[];
    $from=trim((string)($_GET['date_from']??''));$to=trim((string)($_GET['date_to']??''));
    if($from!==''){$where[]='j.transaction_date>=?';$params[]=accounts_date($from);}if($to!==''){$where[]='j.transaction_date<=?';$params[]=accounts_date($to);}if($from!==''&&$to!==''&&$from>$to)accounts_fail('INVALID_DATE_RANGE');
    $source=strtoupper(trim((string)($_GET['source_type']??'')));if($source!==''){$where[]='j.source_module=?';$params[]=$source;}
    $userId=(int)($_GET['user_id']??0);if($userId>0){$where[]='(j.created_by=? OR j.approved_by=?)';$params[]=$userId;$params[]=$userId;}
    $search=trim((string)($_GET['search']??''));if($search!==''){$where[]='(j.reference_no LIKE ? OR j.description LIKE ? OR j.source_module LIKE ?)';$like='%'.$search.'%';array_push($params,$like,$like,$like);}
    foreach(['account_id','project_id','mixer_id','client_id','cost_centre_id'] as $key){$value=(int)($_GET[$key]??0);if($value>0){$where[]="EXISTS(SELECT 1 FROM qbook_financial_journal_lines fx WHERE fx.journal_id=j.id AND fx.{$key}=?)";$params[]=$value;}}
    $whereSql=$where?'WHERE '.implode(' AND ',$where):'';
    $count=$db->prepare("SELECT COUNT(*) FROM qbook_financial_journals j {$whereSql}");$count->execute($params);$total=(int)$count->fetchColumn();
    $sql="SELECT j.id,j.reference_no,j.transaction_date,j.description,j.source_module,j.source_record_id,{$sourceReferenceSql} source_reference,j.entry_kind,j.status,j.reversal_of_id,j.created_at,j.posted_at,j.reversed_at,u.full_name created_by_name,a.full_name approved_by_name,COALESCE(SUM(l.debit),0) total_debit,COALESCE(SUM(l.credit),0) total_credit FROM qbook_financial_journals j JOIN qbook_users u ON u.id=j.created_by LEFT JOIN qbook_users a ON a.id=j.approved_by JOIN qbook_financial_journal_lines l ON l.journal_id=j.id {$whereSql} GROUP BY j.id ORDER BY j.transaction_date DESC,j.id DESC LIMIT {$pageSize} OFFSET {$offset}";
    $s=$db->prepare($sql);$s->execute($params);
    return ['journals'=>$s->fetchAll(),'pagination'=>['page'=>$page,'page_size'=>$pageSize,'total'=>$total,'total_pages'=>(int)ceil($total/$pageSize)]];
});
