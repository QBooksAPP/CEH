<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';
$user=billing_require_admin();$db=production_db();
if($_SERVER['REQUEST_METHOD']==='GET') accounts_endpoint(function()use($db):array{
    $codes=$db->query("SELECT * FROM qbook_tax_codes ORDER BY tax_type,code,effective_from DESC,id DESC")->fetchAll();
    $roles=$db->query("SELECT r.role_code,r.account_id,a.code account_code,a.name account_name,r.is_active FROM qbook_financial_account_roles r JOIN qbook_accounts_chart a ON a.id=r.account_id ORDER BY r.role_code")->fetchAll();
    $settings=$db->query("SELECT * FROM qbook_invoice_settings WHERE id=1")->fetch();
    return ['tax_codes'=>$codes,'account_roles'=>$roles,'invoice_settings'=>$settings];
});
production_require_method('POST');$in=production_input();
accounts_endpoint(function()use($db,$user,$in):array{return accounts_transaction($db,function()use($db,$user,$in):array{
    $action=strtoupper(trim((string)($in['action']??'CREATE')));
    if($action==='SET_ACTIVE'){
        $id=(int)($in['tax_code_id']??0);$active=filter_var($in['is_active']??null,FILTER_VALIDATE_BOOL,FILTER_NULL_ON_FAILURE);
        if($id<=0||$active===null) accounts_fail('INVALID_TAX_STATUS');
        $s=$db->prepare("SELECT id,code FROM qbook_tax_codes WHERE id=? FOR UPDATE");$s->execute([$id]);$row=$s->fetch();if(!$row)accounts_fail('TAX_CODE_NOT_FOUND',404);
        $db->prepare("UPDATE qbook_tax_codes SET is_active=? WHERE id=?")->execute([$active?1:0,$id]);
        accounts_audit($db,$user,$active?'TAX_CODE_ACTIVATED':'TAX_CODE_DEACTIVATED','TAX_CODE',$id,['code'=>$row['code']]);
        return ['tax_code'=>['id'=>$id,'is_active'=>$active]];
    }
    if($action!=='CREATE') accounts_fail('INVALID_TAX_ACTION');
    $type=strtoupper((string)($in['tax_type']??''));if(!in_array($type,['VAT','WHT'],true)) accounts_fail('INVALID_TAX_TYPE');
    // Ledger mappings are server-owned; clients cannot select arbitrary accounts.
    $role=$type==='VAT'?'OUTPUT_VAT_PAYABLE':'WHT_RECEIVABLE';
    $rate=trim((string)($in['rate_percent']??''));if(!preg_match('/\A\d{1,3}(?:\.\d{1,6})?\z/',$rate)||(float)$rate<0||(float)$rate>100) accounts_fail('INVALID_TAX_RATE');
    $base=strtoupper((string)($in['calculation_base']??($type==='VAT'?'NET':'GROSS')));if(!in_array($base,['NET','GROSS','MANUAL'],true)) accounts_fail('INVALID_TAX_BASE');
    $from=accounts_date($in['effective_from']??'');$to=isset($in['effective_to'])&&trim((string)$in['effective_to'])!==''?accounts_date($in['effective_to']):null;if($to!==null&&$to<$from) accounts_fail('INVALID_TAX_EFFECTIVE_DATES');
    $active=filter_var($in['is_active']??true,FILTER_VALIDATE_BOOL,FILTER_NULL_ON_FAILURE);if($active===null) accounts_fail('INVALID_TAX_STATUS');
    $db->prepare("INSERT INTO qbook_tax_codes(code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from,effective_to,is_active,created_by)VALUES(?,?,?,?,?,?,?,?,?,?)")->execute([strtoupper(production_clean_text($in['code']??'',40,'TAX_CODE_REQUIRED')),production_clean_text($in['name']??'',150,'TAX_NAME_REQUIRED'),$type,$rate,$base,$role,$from,$to,$active?1:0,$user['id']]);
    $id=(int)$db->lastInsertId();accounts_audit($db,$user,'TAX_CODE_CREATED','TAX_CODE',$id,['tax_type'=>$type,'rate_percent'=>$rate,'effective_from'=>$from,'effective_to'=>$to]);return ['tax_code'=>['id'=>$id]];
});});
