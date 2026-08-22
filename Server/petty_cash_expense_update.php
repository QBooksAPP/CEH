<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $id=(int)($input['expense_id']??0);if($id<=0) accounts_fail('EXPENSE_REQUIRED');$db=production_db();
    return accounts_transaction($db,function() use($db,$user,$input,$id): array {
        $s=$db->prepare("SELECT * FROM qbook_petty_cash_expenses WHERE id=? FOR UPDATE");$s->execute([$id]);$old=$s->fetch();if(!$old) accounts_fail('EXPENSE_NOT_FOUND',404);
        $custodian=(int)$old['custodian_user_id'];if(!accounts_can_access_custodian($user,$custodian)) accounts_fail('FORBIDDEN',403);
        if(!in_array($old['status'],['DRAFT','CORRECTION_REQUIRED'],true)) accounts_fail('EXPENSE_LOCKED',409);
        accounts_custodian($db,$custodian,true);$minor=accounts_money_minor($input['amount']??$old['amount']);$account=(int)($input['expense_account_id']??$old['expense_account_id']);
        $accountCheck=$db->prepare("SELECT id FROM qbook_accounts_chart WHERE id=? AND account_type='EXPENSE' AND is_active=1 AND is_postable=1");$accountCheck->execute([$account]);if(!$accountCheck->fetch()) accounts_fail('EXPENSE_ACCOUNT_REQUIRED');
        $client=accounts_nullable_id($input['client_id']??$old['client_id']);$project=accounts_nullable_id($input['project_id']??$old['project_id']);$mixer=accounts_nullable_id($input['mixer_id']??$old['mixer_id']);accounts_validate_dimensions($db,$client,$project,$mixer);
        if($old['status']==='CORRECTION_REQUIRED'){$available=accounts_custodian_balance($db,$custodian)['_available_minor']+accounts_money_minor($old['amount'],false);if($minor>$available) accounts_fail('INSUFFICIENT_PETTY_CASH',409);}
        $db->prepare("UPDATE qbook_petty_cash_expenses SET expense_date=?,amount=?,expense_account_id=?,supplier_paid_to=?,description=?,client_id=?,project_id=?,mixer_id=?,no_receipt_reason=? WHERE id=?")->execute([
          accounts_date($input['expense_date']??$old['expense_date']),accounts_minor_decimal($minor),$account,
          production_clean_text($input['supplier_paid_to']??$old['supplier_paid_to'],200,'SUPPLIER_REQUIRED'),production_clean_text($input['description']??$old['description'],500,'DESCRIPTION_REQUIRED'),$client,$project,$mixer,
          production_clean_text($input['no_receipt_reason']??($old['no_receipt_reason']??''),500,'INVALID_NO_RECEIPT_REASON',false)?:null,$id]);
        accounts_audit($db,$user,'PETTY_CASH_EXPENSE_UPDATED','PETTY_CASH_EXPENSE',$id,['previous_status'=>$old['status'],'amount'=>accounts_minor_decimal($minor)]);return ['expense'=>['id'=>$id,'status'=>$old['status']]];
    });
});
