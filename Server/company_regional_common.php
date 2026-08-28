<?php
declare(strict_types=1);

require_once __DIR__.'/accounts_common.php';

const COMPANY_DATE_FORMATS = ['DD-MM-YYYY','MM-DD-YYYY','YYYY-MM-DD'];
const COMPANY_TIME_FORMATS = ['24_HOUR','12_HOUR'];
const COMPANY_CURRENCIES = [
    'NGN'=>['name'=>'Nigerian Naira','symbol'=>'₦'],
    'GBP'=>['name'=>'Pound Sterling','symbol'=>'£'],
    'USD'=>['name'=>'US Dollar','symbol'=>'$'],
    'EUR'=>['name'=>'Euro','symbol'=>'€'],
    'AED'=>['name'=>'UAE Dirham','symbol'=>'AED'],
];

function company_regional_settings(PDO $db,array $user,bool $lock=false):array {
    $sql='SELECT c.id company_id,c.company_code,c.display_name,c.is_active,'
        .'r.time_zone,r.date_format,r.time_format,r.base_currency,r.updated_at '
        .'FROM qbook_companies c JOIN qbook_company_regional_settings r ON r.company_id=c.id '
        .'WHERE c.id=?'.($lock?' FOR UPDATE':'');
    $s=$db->prepare($sql);$s->execute([(int)$user['company_id']]);$row=$s->fetch();
    if(!$row||(int)$row['is_active']!==1) accounts_fail('COMPANY_SETTINGS_UNAVAILABLE',409);
    $currency=COMPANY_CURRENCIES[(string)$row['base_currency']]??null;
    if($currency===null) accounts_fail('COMPANY_CURRENCY_UNSUPPORTED',500);
    return $row+['currency_name'=>$currency['name'],'currency_symbol'=>$currency['symbol']];
}

function company_document_currency(mixed $snapshot):string {
    $code=strtoupper(trim((string)$snapshot));
    if($code==='') return 'NGN'; // Explicit pre-v1.21 CEH compatibility.
    if(!isset(COMPANY_CURRENCIES[$code])) accounts_fail('DOCUMENT_CURRENCY_UNSUPPORTED',409);
    return $code;
}

function company_money(mixed $amount,string $currency):string {
    $code=company_document_currency($currency);
    return COMPANY_CURRENCIES[$code]['symbol'].number_format((float)$amount,2);
}

function company_has_financial_activity(PDO $db):bool {
    return (bool)$db->query("SELECT EXISTS(SELECT 1 FROM qbook_financial_journals WHERE status IN('POSTED','REVERSED') LIMIT 1)")->fetchColumn();
}
