<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('POST'); $input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $custodian=(int)($input['custodian_user_id']??$user['id']); if(!accounts_can_access_custodian($user,$custodian)) accounts_fail('FORBIDDEN',403);
    $minor=accounts_money_minor($input['amount']??'');$date=accounts_date($input['expense_date']??'');$account=(int)($input['expense_account_id']??0);if($account<=0) accounts_fail('EXPENSE_ACCOUNT_REQUIRED');
    $supplier=production_clean_text($input['supplier_paid_to']??'',200,'SUPPLIER_REQUIRED');$description=production_clean_text($input['description']??'',500,'DESCRIPTION_REQUIRED');
    $client=accounts_nullable_id($input['client_id']??null);$project=accounts_nullable_id($input['project_id']??null);$mixer=accounts_nullable_id($input['mixer_id']??null);
    $reason=production_clean_text($input['no_receipt_reason']??'',500,'INVALID_NO_RECEIPT_REASON',false);
    $db=production_db();
    return accounts_transaction($db,function() use($db,$user,$custodian,$minor,$date,$account,$supplier,$description,$client,$project,$mixer,$reason): array {
        accounts_custodian($db,$custodian,true);accounts_validate_dimensions($db,$client,$project,$mixer);
        $s=$db->prepare("SELECT id FROM qbook_accounts_chart WHERE id=? AND account_type='EXPENSE' AND is_active=1 AND is_postable=1");$s->execute([$account]);if(!$s->fetch()) accounts_fail('EXPENSE_ACCOUNT_REQUIRED');
        $db->prepare("INSERT INTO qbook_petty_cash_expenses(custodian_user_id,expense_date,amount,expense_account_id,supplier_paid_to,description,client_id,project_id,mixer_id,no_receipt_reason,created_by) VALUES(?,?,?,?,?,?,?,?,?,?,?)")->execute([$custodian,$date,accounts_minor_decimal($minor),$account,$supplier,$description,$client,$project,$mixer,$reason?:null,(int)$user['id']]);
        $id=(int)$db->lastInsertId();accounts_audit($db,$user,'PETTY_CASH_EXPENSE_DRAFTED','PETTY_CASH_EXPENSE',$id,['custodian_user_id'=>$custodian,'amount'=>accounts_minor_decimal($minor)]);
        return ['expense'=>['id'=>$id,'status'=>'DRAFT']];
    });
});
