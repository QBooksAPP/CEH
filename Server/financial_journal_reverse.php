<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('POST'); $input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $id=(int)($input['journal_id']??0); if($id<=0) accounts_fail('JOURNAL_REQUIRED');
    $reason=production_clean_text($input['reason']??'',500,'REVERSAL_REASON_REQUIRED');
    $date=accounts_date($input['transaction_date']??''); $db=production_db();
    return ['journal'=>accounts_transaction($db,fn()=>accounts_reverse_journal($db,$user,$id,$reason,$date))];
});
