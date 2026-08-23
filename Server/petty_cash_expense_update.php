<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $id=(int)($input['expense_id']??0);if($id<=0) accounts_fail('EXPENSE_REQUIRED');$db=production_db();
    return accounts_transaction($db,function() use($db,$user,$input,$id): array {
        $s=$db->prepare("SELECT * FROM qbook_petty_cash_expenses WHERE id=? FOR UPDATE");$s->execute([$id]);$old=$s->fetch();if(!$old) accounts_fail('EXPENSE_NOT_FOUND',404);
        $custodian=(int)$old['custodian_user_id'];if(!accounts_can_access_custodian($user,$custodian)) accounts_fail('FORBIDDEN',403);
        if(!in_array($old['status'],['DRAFT','CORRECTION_REQUIRED'],true)) accounts_fail('EXPENSE_LOCKED',409); accounts_custodian($db,$custodian,true);
        $dateRaw=trim((string)($input['expense_date']??($old['expense_date']??'')));$date=$dateRaw===''?null:accounts_date($dateRaw);
        $amountRaw=trim((string)($input['amount']??($old['amount']??'')));$minor=$amountRaw===''?null:accounts_money_minor($amountRaw);
        $supplierId=accounts_nullable_id($input['supplier_id']??$old['supplier_id']);$supplier=$supplierId===null?null:accounts_supplier($db,$supplierId);
        $supplierSnapshot=$supplier?$supplier['canonical_name']:production_clean_text($input['supplier_paid_to']??($old['supplier_paid_to']??''),200,'INVALID_SUPPLIER',false);
        if($supplierId===null&&$supplierSnapshot!==''&&strtoupper((string)$user['role'])!=='ADMIN'&&(int)$old['line_model_version']===1) accounts_fail('ONE_OFF_PAYEE_ADMIN_ONLY',403);
        $description=production_clean_text($input['description']??($old['description']??''),500,'INVALID_DESCRIPTION',false);
        $lines=accounts_expense_lines($db,$input['lines']??[],false);
        if($minor!==null&&$lines!==[]) accounts_require_line_total($lines,$minor);
        if($old['status']==='CORRECTION_REQUIRED'&&$minor!==null){$available=accounts_custodian_balance($db,$custodian)['_available_minor']+accounts_money_minor($old['amount'],false);if($minor>$available) accounts_fail('INSUFFICIENT_PETTY_CASH',409);}
        $legacyAccount=$lines[0]['expense_account_id']??$old['expense_account_id'];
        $db->prepare("UPDATE qbook_petty_cash_expenses SET expense_date=?,amount=?,line_model_version=1,expense_account_id=?,supplier_id=?,supplier_paid_to=?,description=?,client_id=NULL,project_id=NULL,mixer_id=NULL,no_receipt_reason=? WHERE id=?")
           ->execute([$date,$minor===null?null:accounts_minor_decimal($minor),$legacyAccount,$supplierId,$supplierSnapshot?:null,$description?:null,production_clean_text($input['no_receipt_reason']??($old['no_receipt_reason']??''),500,'INVALID_NO_RECEIPT_REASON',false)?:null,$id]);
        accounts_replace_expense_lines($db,'qbook_petty_cash_expense_lines',$id,$lines);
        accounts_audit($db,$user,'PETTY_CASH_EXPENSE_UPDATED','PETTY_CASH_EXPENSE',$id,['previous_status'=>$old['status'],'amount'=>$minor===null?null:accounts_minor_decimal($minor),'line_count'=>count($lines)]);
        return ['expense'=>['id'=>$id,'status'=>$old['status']]];
    });
});
