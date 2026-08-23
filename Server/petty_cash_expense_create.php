<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('POST'); $input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $custodian=(int)($input['custodian_user_id']??$user['id']);
    if(!accounts_can_access_custodian($user,$custodian)) accounts_fail('FORBIDDEN',403);
    $db=production_db();
    return accounts_transaction($db,function() use($db,$user,$input,$custodian): array {
        accounts_custodian($db,$custodian,true);
        $dateRaw=trim((string)($input['expense_date']??'')); $date=$dateRaw===''?null:accounts_date($dateRaw);
        $amountRaw=trim((string)($input['amount']??'')); $minor=$amountRaw===''?null:accounts_money_minor($amountRaw);
        $supplierId=accounts_nullable_id($input['supplier_id']??null);
        $supplier=$supplierId===null?null:accounts_supplier($db,$supplierId);
        $supplierSnapshot=$supplier?production_clean_text($supplier['canonical_name'],200,'SUPPLIER_REQUIRED'):production_clean_text($input['supplier_paid_to']??'',200,'INVALID_SUPPLIER',false);
        if($supplierId===null&&$supplierSnapshot!==''&&strtoupper((string)$user['role'])!=='ADMIN') accounts_fail('ONE_OFF_PAYEE_ADMIN_ONLY',403);
        $description=production_clean_text($input['description']??'',500,'INVALID_DESCRIPTION',false);
        $reason=production_clean_text($input['no_receipt_reason']??'',500,'INVALID_NO_RECEIPT_REASON',false);
        $lines=accounts_expense_lines($db,$input['lines']??[],false);
        if($minor!==null&&$lines!==[]) accounts_require_line_total($lines,$minor);
        $legacyAccount=$lines[0]['expense_account_id']??accounts_nullable_id($input['expense_account_id']??null);
        $db->prepare("INSERT INTO qbook_petty_cash_expenses(custodian_user_id,expense_date,amount,line_model_version,expense_account_id,supplier_id,supplier_paid_to,description,no_receipt_reason,created_by) VALUES(?,?,?,1,?,?,?,?,?,?)")
           ->execute([$custodian,$date,$minor===null?null:accounts_minor_decimal($minor),$legacyAccount,$supplierId,$supplierSnapshot?:null,$description?:null,$reason?:null,(int)$user['id']]);
        $id=(int)$db->lastInsertId(); accounts_replace_expense_lines($db,'qbook_petty_cash_expense_lines',$id,$lines);
        $db->prepare("INSERT INTO qbook_petty_cash_expense_references(expense_id) VALUES(?)")->execute([$id]);
        $reference=accounts_petty_cash_reference((int)$db->lastInsertId());
        accounts_audit($db,$user,'PETTY_CASH_EXPENSE_DRAFTED','PETTY_CASH_EXPENSE',$id,['reference_no'=>$reference,'custodian_user_id'=>$custodian,'amount'=>$minor===null?null:accounts_minor_decimal($minor),'line_count'=>count($lines)]);
        return ['expense'=>['id'=>$id,'reference_no'=>$reference,'status'=>'DRAFT']];
    });
});
