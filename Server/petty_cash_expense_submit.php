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
        if($e['expense_date']===null||trim((string)$e['supplier_paid_to'])===''||trim((string)$e['description'])===''||$e['amount']===null) accounts_fail('EXPENSE_SUBMISSION_INCOMPLETE');
        $amount=accounts_money_minor($e['amount'],false);
        if((int)$e['line_model_version']===1){$lines=accounts_load_expense_lines($db,'qbook_petty_cash_expense_lines',$id,true);$lineMinor=0;foreach($lines as $line){$lineMinor+=accounts_money_minor($line['amount'],false);accounts_expense_lines($db,[['amount'=>$line['amount'],'expense_account_id'=>$line['expense_account_id'],'description'=>$line['item_description'],'quantity'=>$line['quantity'],'unit_price'=>$line['unit_price'],'cost_centre_id'=>$line['cost_centre_id'],'client_id'=>$line['client_id'],'project_id'=>$line['project_id'],'mixer_id'=>$line['mixer_id']]]);}if($lines===[]||$lineMinor!==$amount) accounts_fail('EXPENSE_LINE_TOTAL_MISMATCH');}
        $available=accounts_custodian_balance($db,$custodian)['_available_minor'];if($e['status']==='CORRECTION_REQUIRED')$available+=accounts_money_minor($e['amount'],false);if($amount>$available) accounts_fail('INSUFFICIENT_PETTY_CASH',409);
        $db->prepare("UPDATE qbook_petty_cash_expenses SET status='SUBMITTED',submitted_at=UTC_TIMESTAMP(),reviewed_by=NULL,reviewed_at=NULL WHERE id=?")->execute([$id]);accounts_audit($db,$user,'PETTY_CASH_EXPENSE_SUBMITTED','PETTY_CASH_EXPENSE',$id,['amount'=>$e['amount']]);
        return ['expense'=>['id'=>$id,'status'=>'SUBMITTED'],'balance'=>accounts_public_balance(accounts_custodian_balance($db,$custodian))];
    });
});
