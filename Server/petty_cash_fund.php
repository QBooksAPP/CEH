<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('POST'); $input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $bankId=(int)($input['bank_account_id']??0);$custodian=(int)($input['custodian_user_id']??0);if($bankId<=0||$custodian<=0) accounts_fail('BANK_AND_CUSTODIAN_REQUIRED');
    $minor=accounts_money_minor($input['amount']??'');$date=accounts_date($input['funding_date']??'');
    $reference=production_clean_text($input['bank_reference']??'',150,'BANK_REFERENCE_REQUIRED');$description=production_clean_text($input['description']??'',500,'INVALID_DESCRIPTION',false);
    $db=production_db();
    $funding=accounts_transaction($db,function() use($db,$user,$bankId,$custodian,$minor,$date,$reference,$description): array {
        accounts_custodian($db,$custodian,true);
        $s=$db->prepare("SELECT b.id,b.ledger_account_id FROM qbook_bank_accounts b WHERE b.id=? AND b.is_active=1 FOR UPDATE");$s->execute([$bankId]);$bank=$s->fetch();if(!$bank) accounts_fail('ACTIVE_BANK_ACCOUNT_REQUIRED');
        $duplicate=$db->prepare("SELECT id FROM qbook_petty_cash_fundings WHERE bank_account_id=? AND funding_date=? AND bank_reference=? AND amount=?");$duplicate->execute([$bankId,$date,$reference,accounts_minor_decimal($minor)]);if($duplicate->fetch()) accounts_fail('FUNDING_ALREADY_RECORDED',409);
        $db->prepare("INSERT INTO qbook_petty_cash_fundings(bank_account_id,custodian_user_id,amount,funding_date,bank_reference,description,created_by) VALUES(?,?,?,?,?,?,?)")->execute([$bankId,$custodian,accounts_minor_decimal($minor),$date,$reference,$description?:null,(int)$user['id']]);
        $id=(int)$db->lastInsertId();$petty=accounts_account_id($db,'1200');
        $journal=accounts_post_journal($db,$user,['transaction_date'=>$date,'description'=>'Petty cash funding: '.$reference,'source_module'=>'PETTY_CASH_FUNDING','source_record_id'=>$id,'approved_by'=>(int)$user['id']],[
          ['account_id'=>$petty,'debit_minor'=>$minor,'credit_minor'=>0,'custodian_user_id'=>$custodian,'description'=>$description],
          ['account_id'=>(int)$bank['ledger_account_id'],'debit_minor'=>0,'credit_minor'=>$minor,'description'=>$description],
        ]);
        $db->prepare("UPDATE qbook_petty_cash_fundings SET journal_id=? WHERE id=? AND journal_id IS NULL")->execute([$journal['id'],$id]);
        accounts_audit($db,$user,'PETTY_CASH_FUNDED','PETTY_CASH_FUNDING',$id,['custodian_user_id'=>$custodian,'amount'=>accounts_minor_decimal($minor),'bank_reference'=>$reference,'journal_id'=>$journal['id']]);
        return ['id'=>$id,'journal'=>$journal,'balance'=>accounts_public_balance(accounts_custodian_balance($db,$custodian))];
    });
    return ['funding'=>$funding];
});
