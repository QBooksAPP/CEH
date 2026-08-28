<?php
declare(strict_types=1);
require_once __DIR__.'/company_regional_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$in=production_input();
accounts_endpoint(function()use($user,$in):array{$db=production_db();return accounts_transaction($db,function()use($db,$user,$in):array{
    $old=company_regional_settings($db,$user,true);
    $zone=trim((string)($in['time_zone']??''));
    $date=strtoupper(trim((string)($in['date_format']??'')));
    $time=strtoupper(trim((string)($in['time_format']??'')));
    $currency=strtoupper(trim((string)($in['base_currency']??'')));
    $reason=production_clean_text($in['change_reason']??'',500,'INVALID_CHANGE_REASON',false)?:null;
    if(!in_array($zone,DateTimeZone::listIdentifiers(),true)) accounts_fail('INVALID_TIME_ZONE');
    if(!in_array($date,COMPANY_DATE_FORMATS,true)) accounts_fail('INVALID_DATE_FORMAT');
    if(!in_array($time,COMPANY_TIME_FORMATS,true)) accounts_fail('INVALID_TIME_FORMAT');
    if(!isset(COMPANY_CURRENCIES[$currency])) accounts_fail('INVALID_BASE_CURRENCY');
    if($currency!==$old['base_currency']&&company_has_financial_activity($db)) accounts_fail('BASE_CURRENCY_CHANGE_REQUIRES_CONTROLLED_MIGRATION',409);
    $changed=$zone!==$old['time_zone']||$date!==$old['date_format']||$time!==$old['time_format']||$currency!==$old['base_currency'];
    if($changed){
        $db->prepare('UPDATE qbook_company_regional_settings SET time_zone=?,date_format=?,time_format=?,base_currency=?,updated_by=? WHERE company_id=?')
            ->execute([$zone,$date,$time,$currency,(int)$user['id'],(int)$user['company_id']]);
        $db->prepare('INSERT INTO qbook_company_regional_settings_audit(company_id,changed_by,old_time_zone,new_time_zone,old_date_format,new_date_format,old_time_format,new_time_format,old_base_currency,new_base_currency,change_reason)VALUES(?,?,?,?,?,?,?,?,?,?,?)')
            ->execute([(int)$user['company_id'],(int)$user['id'],$old['time_zone'],$zone,$old['date_format'],$date,$old['time_format'],$time,$old['base_currency'],$currency,$reason]);
    }
    $settings=company_regional_settings($db,$user);
    $settings['base_currency_protected']=company_has_financial_activity($db);
    return['regional_settings'=>$settings,'changed'=>$changed];
});});
