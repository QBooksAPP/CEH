<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';

// UI guidance only; the POST rechecks using current/locking reads.
function invoice_void_contract(PDO $db,array $i,bool $lock=false):array {
    $suffix=$lock?' FOR UPDATE':'';$reasons=[];$settled=0;
    if($i['status']!=='ISSUED')$reasons[]='ISSUED_INVOICE_REQUIRED';
    $queries=[
        'CLIENT_PAYMENT_SETTLEMENT_EXISTS'=>"SELECT a.cash_amount amount FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id WHERE a.invoice_id=? AND r.status='POSTED'",
        'WHT_SETTLEMENT_EXISTS'=>"SELECT a.wht_amount amount FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id WHERE a.invoice_id=? AND r.status='POSTED'",
        'CLIENT_CREDIT_SETTLEMENT_EXISTS'=>'SELECT amount FROM qbook_advance_applications WHERE invoice_id=?',
        'CREDIT_NOTE_SETTLEMENT_EXISTS'=>"SELECT ca.amount FROM qbook_credit_note_allocations ca JOIN qbook_credit_notes c ON c.id=ca.credit_note_id WHERE ca.invoice_id=? AND c.status='ISSUED'",
    ];
    foreach($queries as $reason=>$sql){$q=$db->prepare($sql.$suffix);$q->execute([$i['id']]);foreach($q->fetchAll() as $r){$m=accounts_money_minor($r['amount'],false);$settled+=$m;if($m>0)$reasons[]=$reason;}}
    if($settled!==0)$reasons[]='ONLY_UNPAID_INVOICE_CAN_BE_VOIDED';
    $q=$db->prepare('SELECT * FROM qbook_financial_journals WHERE id=?'.$suffix);$q->execute([(int)($i['journal_id']??0)]);$j=$q->fetch();
    $q=$db->prepare('SELECT id,reference_no,transaction_date FROM qbook_financial_journals WHERE reversal_of_id=?'.$suffix);$q->execute([(int)($i['journal_id']??0)]);$rev=$q->fetch();
    if(!$j||$j['status']!=='POSTED'||$rev)$reasons[]='JOURNAL_NOT_REVERSIBLE';
    if($j){
        $q=$db->prepare('SELECT l.*,a.is_active,a.is_postable FROM qbook_financial_journal_lines l JOIN qbook_accounts_chart a ON a.id=l.account_id WHERE l.journal_id=? ORDER BY l.line_no'.$suffix);$q->execute([$j['id']]);$lines=$q->fetchAll();$d=$c=0;$valid=count($lines)>=2;
        foreach($lines as $l){$debit=accounts_money_minor($l['debit'],false);$credit=accounts_money_minor($l['credit'],false);$d+=$debit;$c+=$credit;$valid=$valid&&$debit>=0&&$credit>=0&&(($debit>0)!==($credit>0))&&(bool)$l['is_active']&&(bool)$l['is_postable'];
            try{accounts_cost_centre($db,$l['cost_centre_id'],false);accounts_validate_dimensions($db,accounts_nullable_id($l['client_id']),accounts_nullable_id($l['project_id']),accounts_nullable_id($l['mixer_id']));}catch(AccountsApiError $e){$valid=false;}
        }
        if(!$valid||$d<=0||$d!==$c)$reasons[]='JOURNAL_NOT_REVERSIBLE';
    }
    $actor=null;if(!empty($i['voided_by'])){$q=$db->prepare('SELECT full_name FROM qbook_users WHERE id=?');$q->execute([$i['voided_by']]);$actor=$q->fetchColumn()?:null;}
    return ['raw_status'=>$i['status'],'can_void'=>$reasons===[],'void_blocking_reasons'=>array_values(array_unique($reasons)),
        'original_journal_reference'=>$j['reference_no']??null,'reversal_journal_id'=>$rev?(int)$rev['id']:null,'reversal_journal_reference'=>$rev['reference_no']??null,'effective_void_date'=>$rev['transaction_date']??null,'voided_by_name'=>$actor];
}

function invoice_void_execute(PDO $db,array $user,array $input):array {
    if(strtoupper((string)($user['role']??''))!=='ADMIN')accounts_fail('FORBIDDEN',403);
    return accounts_transaction($db,function()use($db,$user,$input):array{
        $q=$db->prepare('SELECT * FROM qbook_invoices WHERE id=? FOR UPDATE');$q->execute([(int)($input['invoice_id']??0)]);$i=$q->fetch();if(!$i)accounts_fail('INVOICE_NOT_FOUND',404);
        $contract=invoice_void_contract($db,$i,true);
        if(!$contract['can_void'])accounts_fail(count(array_diff($contract['void_blocking_reasons'],['JOURNAL_NOT_REVERSIBLE']))>0?'ONLY_UNPAID_INVOICE_CAN_BE_VOIDED':'JOURNAL_NOT_REVERSIBLE',409);
        if(!is_string($input['reason']??null)||trim($input['reason'])==='')accounts_fail('REASON_REQUIRED');
        if(mb_strlen(trim($input['reason']))>500)accounts_fail('REASON_REQUIRED');
        $reason=production_clean_text($input['reason'],500,'REASON_REQUIRED');$date=accounts_date($input['void_date']??gmdate('Y-m-d'));
        $q=$db->prepare("SELECT pa.id FROM qbook_invoice_production_allocations pa JOIN qbook_invoice_lines l ON l.id=pa.invoice_line_id WHERE l.invoice_id=? AND pa.status='COMMITTED' ORDER BY pa.id FOR UPDATE");$q->execute([$i['id']]);$ids=array_map('intval',$q->fetchAll(PDO::FETCH_COLUMN));
        $rev=accounts_reverse_journal($db,$user,(int)$i['journal_id'],$reason,$date);
        $db->prepare("UPDATE qbook_invoices SET status='VOID',voided_at=UTC_TIMESTAMP(),voided_by=?,void_reason=? WHERE id=?")->execute([$user['id'],$reason,$i['id']]);
        $db->prepare("UPDATE qbook_invoice_production_allocations pa JOIN qbook_invoice_lines l ON l.id=pa.invoice_line_id SET pa.status='REVERSED' WHERE l.invoice_id=? AND pa.status='COMMITTED'")->execute([$i['id']]);
        accounts_audit($db,$user,'INVOICE_VOIDED','INVOICE',(int)$i['id'],['reversal_journal_id'=>$rev['id'],'reason'=>$reason,'void_date'=>$date,'reversed_allocation_ids'=>$ids,'reversed_allocation_count'=>count($ids)]);
        return ['invoice'=>['id'=>(int)$i['id'],'status'=>'VOID'],'reversal'=>$rev];
    });
}
