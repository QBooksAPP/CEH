<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $id=(int)($input['expense_id']??0);if($id<=0) accounts_fail('EXPENSE_REQUIRED');$db=production_db();
    return accounts_transaction($db,function() use($db,$user,$id): array {
        $s=$db->prepare("SELECT * FROM qbook_petty_cash_expenses WHERE id=? FOR UPDATE");$s->execute([$id]);$e=$s->fetch();if(!$e) accounts_fail('EXPENSE_NOT_FOUND',404);
        $custodian=(int)$e['custodian_user_id'];if(!accounts_can_access_custodian($user,$custodian)) accounts_fail('FORBIDDEN',403);if(!in_array($e['status'],['DRAFT','CORRECTION_REQUIRED'],true)) accounts_fail('EXPENSE_LOCKED',409);
        accounts_custodian($db,$custodian,true);$receipt=$db->prepare("SELECT id FROM qbook_financial_evidence WHERE source_type='PETTY_CASH_EXPENSE' AND source_record_id=? LIMIT 1");$receipt->execute([$id]);if(!$receipt->fetch()&&trim((string)$e['no_receipt_reason'])==='') accounts_fail('RECEIPT_OR_REASON_REQUIRED');
        $amount=accounts_money_minor($e['amount'],false);$available=accounts_custodian_balance($db,$custodian)['_available_minor'];if($e['status']==='CORRECTION_REQUIRED')$available+=accounts_money_minor($e['amount'],false);if($amount>$available) accounts_fail('INSUFFICIENT_PETTY_CASH',409);
        $db->prepare("UPDATE qbook_petty_cash_expenses SET status='SUBMITTED',submitted_at=UTC_TIMESTAMP(),reviewed_by=NULL,reviewed_at=NULL WHERE id=?")->execute([$id]);accounts_audit($db,$user,'PETTY_CASH_EXPENSE_SUBMITTED','PETTY_CASH_EXPENSE',$id,['amount'=>$e['amount']]);
        return ['expense'=>['id'=>$id,'status'=>'SUBMITTED'],'balance'=>accounts_public_balance(accounts_custodian_balance($db,$custodian))];
    });
});
