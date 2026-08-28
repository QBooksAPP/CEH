<?php
declare(strict_types=1);
require_once __DIR__.'/company_regional_common.php';
$user=qbook_require_user();production_require_method('GET');
accounts_endpoint(function()use($user):array{
    $db=production_db();$settings=company_regional_settings($db,$user);
    $settings['base_currency_protected']=company_has_financial_activity($db);
    return['regional_settings'=>$settings];
});
