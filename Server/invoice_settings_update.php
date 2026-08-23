<?php
declare(strict_types=1);require_once __DIR__.'/billing_common.php';
$user=billing_require_admin();production_require_method('POST');$in=production_input();
accounts_endpoint(function()use($user,$in):array{$db=production_db();return accounts_transaction($db,function()use($db,$user,$in):array{
    $terms=strtoupper(trim((string)($in['default_terms']??'ADVANCE_PAYMENT')));if(!in_array($terms,['ADVANCE_PAYMENT','DUE_ON_ISSUE','NET_DAYS','FIXED_DUE_DATE','CUSTOM'],true)) accounts_fail('INVALID_PAYMENT_TERM');
    $legal=production_clean_text($in['company_legal_name']??'',200,'INVALID_COMPANY_NAME',false)?:null;$address=production_clean_text($in['company_address']??'',500,'INVALID_COMPANY_ADDRESS',false)?:null;$tin=production_clean_text($in['tax_identifier']??'',100,'INVALID_TAX_IDENTIFIER',false)?:null;$bank=production_clean_text($in['payment_bank_details']??'',500,'INVALID_PAYMENT_BANK_DETAILS',false)?:null;$text=production_clean_text($in['default_terms_text']??'Advance Payment',500,'DEFAULT_TERMS_TEXT_REQUIRED');
    $db->prepare("UPDATE qbook_invoice_settings SET company_legal_name=?,company_address=?,tax_identifier=?,payment_bank_details=?,default_terms=?,default_terms_text=?,updated_by=? WHERE id=1")->execute([$legal,$address,$tin,$bank,$terms,$text,$user['id']]);
    accounts_audit($db,$user,'INVOICE_SETTINGS_UPDATED','INVOICE_SETTINGS',1,['default_terms'=>$terms]);return ['invoice_settings'=>['id'=>1,'default_terms'=>$terms]];
});});
