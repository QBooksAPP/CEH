<?php
declare(strict_types=1);
require_once __DIR__.'/bank_payment_common.php';
$user=billing_require_admin();
accounts_endpoint(function()use($user):array {
    $db=production_db();
    if(($_SERVER['REQUEST_METHOD']??'')==='GET')return bank_payment_read($db,$user,(int)($_GET['statement_row_id']??0));
    production_require_method('POST');$in=production_input();
    return match($in['action']??''){
        'CREATE'=>bank_payment_draft($db,$user,$in),
        'SAVE'=>bank_payment_edit($db,$user,$in),
        'CANCEL'=>bank_payment_edit($db,$user,$in,true),
        default=>accounts_fail('INVALID_PAYMENT_ACTION')};
});
