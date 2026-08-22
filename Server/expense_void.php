<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $type=strtoupper(trim((string)($input['source_type']??'')));$id=(int)($input['source_record_id']??0);
    if($type!=='PETTY_CASH_EXPENSE'||$id<=0) accounts_fail('EXPENSE_SOURCE_NOT_SUPPORTED');
    $reason=production_clean_text($input['reason']??'',500,'VOID_REASON_REQUIRED');
    $date=accounts_date($input['void_date']??gmdate('Y-m-d'));
    $db=production_db();
    return accounts_transaction($db,function() use($db,$user,$id,$type,$reason,$date): array {
        $s=$db->prepare("SELECT e.*,r.reference_no,j.reference_no AS original_journal_reference FROM qbook_petty_cash_expenses e LEFT JOIN qbook_petty_cash_expense_references r ON r.expense_id=e.id LEFT JOIN qbook_financial_journals j ON j.id=e.journal_id WHERE e.id=? FOR UPDATE");$s->execute([$id]);$expense=$s->fetch();
        if(!$expense) accounts_fail('EXPENSE_NOT_FOUND',404);
        if($expense['status']==='VOIDED'||$expense['reversal_journal_id']!==null) accounts_fail('EXPENSE_ALREADY_VOIDED',409);
        if($expense['status']!=='APPROVED'||$expense['journal_id']===null) accounts_fail('EXPENSE_NOT_VOIDABLE',409);
        $correctionReversals=[];$corrections=$db->prepare("SELECT id,journal_id FROM qbook_petty_cash_expense_reclassifications WHERE expense_id=? AND journal_id IS NOT NULL AND reversal_journal_id IS NULL ORDER BY id DESC FOR UPDATE");$corrections->execute([$id]);
        foreach($corrections->fetchAll() as $correction){$cr=accounts_reverse_journal($db,$user,(int)$correction['journal_id'],$reason,$date);$db->prepare("UPDATE qbook_petty_cash_expense_reclassifications SET reversal_journal_id=? WHERE id=? AND reversal_journal_id IS NULL")->execute([$cr['id'],(int)$correction['id']]);$correctionReversals[]=$cr;}
        $reversal=accounts_reverse_journal($db,$user,(int)$expense['journal_id'],$reason,$date);
        $db->prepare("UPDATE qbook_petty_cash_expenses SET status='VOIDED',reversal_journal_id=?,voided_by=?,voided_at=UTC_TIMESTAMP(),void_reason=? WHERE id=? AND status='APPROVED' AND reversal_journal_id IS NULL")->execute([$reversal['id'],(int)$user['id'],$reason,$id]);
        $match=$db->prepare("SELECT COUNT(*) FROM qbook_bank_matches WHERE source_type=? AND source_record_id=?");$match->execute([$type,$id]);$matches=(int)$match->fetchColumn();
        $reference=accounts_petty_cash_reference($expense['reference_no']);
        accounts_audit($db,$user,'EXPENSE_VOIDED',$type,$id,['reference_no'=>$reference,'original_journal_id'=>(int)$expense['journal_id'],'original_journal_reference'=>$expense['original_journal_reference'],'reversal_journal_id'=>$reversal['id'],'reversal_journal_reference'=>$reversal['reference_no'],'reclassification_reversals'=>$correctionReversals,'reason'=>$reason,'bank_matches_preserved'=>$matches]);
        return ['expense'=>['id'=>$id,'source_type'=>$type,'reference_no'=>$reference,'status'=>'VOIDED','original_journal_id'=>(int)$expense['journal_id'],'reversal_journal_id'=>$reversal['id'],'void_reason'=>$reason],'reversal'=>$reversal,'bank_matches_preserved'=>$matches];
    });
});
