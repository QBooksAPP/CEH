<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('POST'); $input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $db=production_db(); $raw=$input['lines']??null;
    if(!is_array($raw)) accounts_fail('JOURNAL_LINES_REQUIRED');
    $lines=[];
    foreach($raw as $line){
        if(!is_array($line)) accounts_fail('INVALID_JOURNAL_LINE');
        $debit=isset($line['debit'])?accounts_money_minor($line['debit'],false):0;
        $credit=isset($line['credit'])?accounts_money_minor($line['credit'],false):0;
        $lines[]=$line+['debit_minor'=>$debit,'credit_minor'=>$credit];
        $lines[array_key_last($lines)]['debit_minor']=$debit;
        $lines[array_key_last($lines)]['credit_minor']=$credit;
    }
    $journal=accounts_transaction($db,fn()=>accounts_post_journal($db,$user,[
        'transaction_date'=>$input['transaction_date']??'', 'description'=>$input['description']??'',
        'source_module'=>$input['source_module']??'MANUAL','source_record_id'=>$input['source_record_id']??0,
        'entry_kind'=>'ORIGINAL','approved_by'=>(int)$user['id'],
    ],$lines));
    return ['journal'=>$journal];
});
