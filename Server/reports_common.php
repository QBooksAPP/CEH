<?php
declare(strict_types=1);

require_once __DIR__.'/billing_common.php';

function reports_filters(array $input): array {
    $dateFrom=trim((string)($input['date_from']??''));
    $dateTo=trim((string)($input['date_to']??''));
    if($dateFrom!=='')$dateFrom=accounts_date($dateFrom);
    if($dateTo!=='')$dateTo=accounts_date($dateTo);
    if($dateFrom!==''&&$dateTo!==''&&$dateFrom>$dateTo)accounts_fail('INVALID_DATE_RANGE');
    $text=static fn(string $key):string=>trim((string)($input[$key]??''));
    $id=static fn(string $key):int=>max(0,(int)($input[$key]??0));
    return [
        'date_from'=>$dateFrom,'date_to'=>$dateTo,'source'=>strtoupper($text('source')),
        'status'=>strtoupper($text('status')),'reference'=>$text('reference'),
        'paid_to'=>$text('paid_to'),'custodian'=>$text('custodian'),'custodian_id'=>$id('custodian_id'),
        'category'=>$text('category'),'client'=>$text('client'),'project'=>$text('project'),
        'equipment'=>$text('equipment'),'cost_centre'=>$text('cost_centre'),
        'account_id'=>$id('account_id'),'client_id'=>$id('client_id'),
        'project_id'=>$id('project_id'),'mixer_id'=>$id('mixer_id'),
        'cost_centre_id'=>$id('cost_centre_id'),'evidence'=>strtoupper($text('evidence')),
        'as_of'=>$text('as_of')===''?gmdate('Y-m-d'):accounts_date($text('as_of')),
        'client_filter_id'=>$id('client_filter_id'),
    ];
}

function reports_evidence(PDO $db,string $sourceType,int $sourceId): array {
    $s=$db->prepare("SELECT id,original_filename,mime_type,byte_size,sha256,storage_driver,storage_key,evidence_data,uploaded_at FROM qbook_financial_evidence WHERE source_type=? AND source_record_id=? ORDER BY id");
    $s->execute([$sourceType,$sourceId]);
    return $s->fetchAll();
}

function reports_line_matches(array $line,array $f): bool {
    foreach(['account_id'=>'expense_account_id','client_id'=>'client_id','project_id'=>'project_id','mixer_id'=>'mixer_id','cost_centre_id'=>'cost_centre_id'] as $filter=>$field){
        if($f[$filter]>0&&(int)($line[$field]??0)!==$f[$filter])return false;
    }
    foreach(['category'=>'category','client'=>'client_name','project'=>'project_name','equipment'=>'mixer_code','cost_centre'=>'cost_centre_name'] as $filter=>$field)if($f[$filter]!==''&&stripos((string)($line[$field]??''),$f[$filter])===false)return false;
    return true;
}

function reports_row_matches(array $row,array $f,string $source): bool {
    if($f['date_from']!==''&&($row['expense_date']??'')<$f['date_from'])return false;
    if($f['date_to']!==''&&($row['expense_date']??'')>$f['date_to'])return false;
    if($f['source']!==''&&$f['source']!=='ALL'&&$f['source']!==$source)return false;
    if($f['status']!==''&&strtoupper((string)($row['status']??''))!==$f['status'])return false;
    if($f['reference']!==''&&stripos((string)($row['reference_no']??''),$f['reference'])===false)return false;
    if($f['paid_to']!==''&&stripos((string)($row['supplier_paid_to']??''),$f['paid_to'])===false)return false;
    if($f['custodian_id']>0&&(int)($row['custodian_user_id']??0)!==$f['custodian_id'])return false;
    if($f['custodian']!==''&&stripos((string)($row['custodian_name']??''),$f['custodian'])===false)return false;
    $count=(int)($row['evidence_count']??0);
    if($f['evidence']==='ATTACHED'&&$count===0)return false;
    if($f['evidence']==='MISSING'&&$count>0)return false;
    return true;
}

function reports_expense_rows(PDO $db,array $f,bool $pettyOnly=false): array {
    $rows=[];
    $lineSql="SELECT l.*,a.code AS account_code,a.name AS category,cc.name AS cost_centre_name,c.name AS client_name,p.name AS project_name,m.code AS mixer_code FROM %s l JOIN qbook_accounts_chart a ON a.id=l.expense_account_id LEFT JOIN qbook_cost_centres cc ON cc.id=l.cost_centre_id LEFT JOIN qbook_clients c ON c.id=l.client_id LEFT JOIN qbook_projects p ON p.id=l.project_id LEFT JOIN qbook_mixers m ON m.id=l.mixer_id WHERE l.expense_id=? ORDER BY l.line_no";
    $petty=$db->query("SELECT e.id,e.custodian_user_id,u.full_name AS custodian_name,e.expense_date,e.amount,e.line_model_version,COALESCE(e.supplier_paid_to,'') supplier_paid_to,COALESCE(e.description,'') description,e.status,e.no_receipt_reason,e.journal_id,j.reference_no original_journal_reference,r.reference_no,(SELECT COUNT(*) FROM qbook_financial_evidence v WHERE v.source_type='PETTY_CASH_EXPENSE' AND v.source_record_id=e.id) evidence_count,e.expense_account_id,e.client_id,e.project_id,e.mixer_id,a.code account_code,a.name category,c.name client_name,p.name project_name,m.code mixer_code FROM qbook_petty_cash_expenses e JOIN qbook_users u ON u.id=e.custodian_user_id LEFT JOIN qbook_petty_cash_expense_references r ON r.expense_id=e.id LEFT JOIN qbook_financial_journals j ON j.id=e.journal_id LEFT JOIN qbook_accounts_chart a ON a.id=e.expense_account_id LEFT JOIN qbook_clients c ON c.id=e.client_id LEFT JOIN qbook_projects p ON p.id=e.project_id LEFT JOIN qbook_mixers m ON m.id=e.mixer_id ORDER BY e.expense_date DESC,e.id DESC")->fetchAll();
    $pettyLines=$db->prepare(sprintf($lineSql,'qbook_petty_cash_expense_lines'));
    foreach($petty as $row){
        $row['reference_no']=accounts_petty_cash_reference($row['reference_no'])??'Reference pending';
        if(!reports_row_matches($row,$f,'PETTY_CASH'))continue;
        $pettyLines->execute([(int)$row['id']]);$lines=$pettyLines->fetchAll();
        if((int)$row['line_model_version']===0&&$lines===[]){$lines=[['id'=>null,'line_no'=>1,'item_description'=>$row['description'],'expense_account_id'=>$row['expense_account_id'],'amount'=>$row['amount'],'cost_centre_id'=>null,'client_id'=>$row['client_id'],'project_id'=>$row['project_id'],'mixer_id'=>$row['mixer_id'],'account_code'=>$row['account_code'],'category'=>$row['category'],'cost_centre_name'=>null,'client_name'=>$row['client_name'],'project_name'=>$row['project_name'],'mixer_code'=>$row['mixer_code'],'legacy_compatibility'=>true]];}
        $matched=array_values(array_filter($lines,fn(array $line):bool=>reports_line_matches($line,$f)));
        if($matched===[])continue;
        $row['source_type']='PETTY_CASH';$row['source_name']=$row['custodian_name'];$row['lines']=$lines;$row['matched_lines']=$matched;
        $row['matched_amount']=accounts_minor_decimal(array_sum(array_map(fn(array $line):int=>accounts_money_minor($line['amount'],false),$matched)));
        accounts_apply_expense_allocation_summary($row,$lines);$rows[]=$row;
    }
    if(!$pettyOnly){
        $general=$db->query("SELECT e.id,e.expense_date,e.amount,COALESCE(e.supplier_name_snapshot,'') supplier_paid_to,COALESCE(e.description,'') description,e.status,e.no_receipt_reason,e.journal_id,j.reference_no original_journal_reference,r.reference_no,(SELECT COUNT(*) FROM qbook_financial_evidence v WHERE v.source_type='GENERAL_EXPENSE' AND v.source_record_id=e.id) evidence_count,b.name source_name FROM qbook_general_expenses e LEFT JOIN qbook_general_expense_references r ON r.expense_id=e.id LEFT JOIN qbook_financial_journals j ON j.id=e.journal_id LEFT JOIN qbook_bank_accounts b ON b.id=e.bank_account_id ORDER BY e.expense_date DESC,e.id DESC")->fetchAll();
        $generalLines=$db->prepare(sprintf($lineSql,'qbook_general_expense_lines'));
        foreach($general as $row){
            $row['reference_no']=accounts_general_expense_reference($row['reference_no']);
            if(!reports_row_matches($row,$f,'BANK'))continue;
            $generalLines->execute([(int)$row['id']]);$lines=$generalLines->fetchAll();$matched=array_values(array_filter($lines,fn(array $line):bool=>reports_line_matches($line,$f)));
            if($matched===[])continue;
            $row['source_type']='BANK';$row['lines']=$lines;$row['matched_lines']=$matched;
            $row['matched_amount']=accounts_minor_decimal(array_sum(array_map(fn(array $line):int=>accounts_money_minor($line['amount'],false),$matched)));
            accounts_apply_expense_allocation_summary($row,$lines);$rows[]=$row;
        }
    }
    usort($rows,fn(array $a,array $b):int=>strcmp(($b['expense_date']??'').'|'.$b['id'],($a['expense_date']??'').'|'.$a['id']));
    $header=$matched=0;foreach($rows as $row){$header+=accounts_money_minor($row['amount'],false);$matched+=accounts_money_minor($row['matched_amount'],false);}
    return ['filters'=>$f,'rows'=>$rows,'totals'=>['transaction_count'=>count($rows),'header_amount'=>accounts_minor_decimal($header),'matched_amount'=>accounts_minor_decimal($matched)]];
}

function reports_receivables(PDO $db,array $f): array {
    $asOf=$f['as_of'];$asOfDate=new DateTimeImmutable($asOf);
    $sql="SELECT i.id,i.reference_no,i.client_id,i.client_name_snapshot,i.invoice_date,i.due_date,i.total_amount,COALESCE((SELECT SUM(a.cash_amount+a.wht_amount) FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED' WHERE a.invoice_id=i.id),0)+COALESCE((SELECT SUM(a.amount) FROM qbook_advance_applications a WHERE a.invoice_id=i.id),0)+COALESCE((SELECT SUM(ca.amount) FROM qbook_credit_note_allocations ca JOIN qbook_credit_notes c ON c.id=ca.credit_note_id AND c.status='ISSUED' WHERE ca.invoice_id=i.id),0) settled FROM qbook_invoices i WHERE i.status='ISSUED' AND i.invoice_date<=?";
    $params=[$asOf];if($f['client_filter_id']>0){$sql.=" AND i.client_id=?";$params[]=$f['client_filter_id'];}$sql.=" ORDER BY i.client_name_snapshot,i.invoice_date,i.id";
    $stmt=$db->prepare($sql);$stmt->execute($params);$buckets=['CURRENT'=>0,'1_30'=>0,'31_60'=>0,'61_90'=>0,'OVER_90'=>0];$rows=[];$originalTotal=$settledTotal=$outstandingTotal=0;
    foreach($stmt->fetchAll() as $row){$original=accounts_money_minor($row['total_amount'],false);$settled=accounts_money_minor((string)$row['settled'],false);$outstanding=$original-$settled;if($outstanding<=0)continue;$daysOutstanding=max(0,(int)(new DateTimeImmutable($row['invoice_date']))->diff($asOfDate)->format('%r%a'));$daysOverdue=0;if($row['due_date']!==null)$daysOverdue=max(0,(int)(new DateTimeImmutable($row['due_date']))->diff($asOfDate)->format('%r%a'));$bucket=$row['due_date']===null||$daysOverdue===0?'CURRENT':($daysOverdue<=30?'1_30':($daysOverdue<=60?'31_60':($daysOverdue<=90?'61_90':'OVER_90')));$buckets[$bucket]+=$outstanding;$originalTotal+=$original;$settledTotal+=$settled;$outstandingTotal+=$outstanding;$row['reference']=billing_ref('INVOICE',$row['reference_no']);$row['original_amount']=accounts_minor_decimal($original);$row['payments_credits_applied']=accounts_minor_decimal($settled);$row['outstanding']=accounts_minor_decimal($outstanding);$row['days_outstanding']=$daysOutstanding;$row['days_overdue']=$daysOverdue;$row['bucket']=$bucket;$rows[]=$row;}
    return ['as_of'=>$asOf,'filters'=>$f,'buckets'=>array_map('accounts_minor_decimal',$buckets),'totals'=>['invoice_count'=>count($rows),'original_amount'=>accounts_minor_decimal($originalTotal),'payments_credits_applied'=>accounts_minor_decimal($settledTotal),'outstanding'=>accounts_minor_decimal($outstandingTotal)],'invoices'=>$rows];
}

function reports_overview(PDO $db): array {
    $bank=(string)$db->query("SELECT COALESCE(SUM(l.debit-l.credit),0) FROM qbook_bank_accounts b JOIN qbook_financial_journal_lines l ON l.account_id=b.ledger_account_id JOIN qbook_financial_journals j ON j.id=l.journal_id AND j.status='POSTED' WHERE b.is_active=1")->fetchColumn();
    $petty=0;$s=$db->query("SELECT user_id FROM qbook_petty_cash_custodians WHERE is_active=1");foreach($s->fetchAll() as $r)$petty+=accounts_money_minor(accounts_custodian_balance($db,(int)$r['user_id'])['balance'],false);
    $receivables=reports_receivables($db,reports_filters(['as_of'=>gmdate('Y-m-d')]))['totals']['outstanding'];
    $start=gmdate('Y-m-01');$end=(new DateTimeImmutable($start))->modify('first day of next month')->format('Y-m-d');
    $q=$db->prepare("SELECT COALESCE(SUM(amount),0) FROM (SELECT e.amount FROM qbook_general_expenses e JOIN qbook_financial_journals j ON j.id=e.journal_id AND j.status='POSTED' WHERE e.status='APPROVED' AND e.expense_date>=? AND e.expense_date<? UNION ALL SELECT e.amount FROM qbook_petty_cash_expenses e JOIN qbook_financial_journals j ON j.id=e.journal_id AND j.status='POSTED' WHERE e.status='APPROVED' AND e.expense_date>=? AND e.expense_date<?) x");$q->execute([$start,$end,$start,$end]);
    return ['bank_balance'=>accounts_minor_decimal(accounts_money_minor($bank,false)),'petty_cash_outstanding'=>accounts_minor_decimal($petty),'trade_receivables'=>accounts_minor_decimal(accounts_money_minor($receivables,false)),'expenses_this_month'=>(string)$q->fetchColumn(),'period_start'=>$start,'period_end_exclusive'=>$end,'date_basis'=>'EXPENSE_DOCUMENT_DATE'];
}
