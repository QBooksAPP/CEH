<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $type=strtoupper(trim((string)($input['source_type']??'')));$id=(int)($input['source_record_id']??0);
    if($type!=='PETTY_CASH_EXPENSE'||$id<=0) accounts_fail('EXPENSE_SOURCE_NOT_SUPPORTED');
    $db=production_db();
    return accounts_transaction($db,function() use($db,$user,$id,$type): array {
        $s=$db->prepare("SELECT e.*,r.reference_no FROM qbook_petty_cash_expenses e LEFT JOIN qbook_petty_cash_expense_references r ON r.expense_id=e.id WHERE e.id=? FOR UPDATE");$s->execute([$id]);$expense=$s->fetch();
        if(!$expense) accounts_fail('EXPENSE_NOT_FOUND',404);
        if($expense['status']!=='DRAFT') accounts_fail('EXPENSE_NOT_DELETABLE',409);
        if($expense['journal_id']!==null||$expense['reversal_journal_id']!==null) accounts_fail('POSTED_EXPENSE_NOT_DELETABLE',409);
        $posted=$db->prepare("SELECT id FROM qbook_financial_journals WHERE source_module='PETTY_CASH_EXPENSE' AND source_record_id=? LIMIT 1");$posted->execute([$id]);
        if($posted->fetch()) accounts_fail('POSTED_EXPENSE_NOT_DELETABLE',409);
        $reference=accounts_petty_cash_reference($expense['reference_no']);
        $evidence=$db->prepare("SELECT COUNT(*) FROM qbook_financial_evidence WHERE source_type='PETTY_CASH_EXPENSE' AND source_record_id=?");$evidence->execute([$id]);$evidenceCount=(int)$evidence->fetchColumn();
        accounts_audit($db,$user,'EXPENSE_DRAFT_DELETED',$type,$id,['reference_no'=>$reference,'status'=>'DRAFT','evidence_removed'=>$evidenceCount]);
        $db->prepare("DELETE FROM qbook_financial_evidence WHERE source_type='PETTY_CASH_EXPENSE' AND source_record_id=?")->execute([$id]);
        $delete=$db->prepare("DELETE FROM qbook_petty_cash_expenses WHERE id=? AND status='DRAFT' AND journal_id IS NULL AND reversal_journal_id IS NULL");$delete->execute([$id]);
        if($delete->rowCount()!==1) accounts_fail('EXPENSE_DELETE_FAILED',500);
        return ['deleted'=>true,'source_type'=>$type,'source_record_id'=>$id,'reference_no'=>$reference,'evidence_removed'=>$evidenceCount];
    });
});
