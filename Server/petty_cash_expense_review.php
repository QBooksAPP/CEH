<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $id=(int)($input['expense_id']??0);$action=strtoupper(trim((string)($input['action']??'')));if($id<=0||!in_array($action,['APPROVE','CORRECTION_REQUIRED','CANCELLED_NOT_SPENT'],true)) accounts_fail('INVALID_REVIEW_ACTION');
    $reason=production_clean_text($input['reason']??'',500,'REVIEW_REASON_REQUIRED',$action!=='APPROVE');$db=production_db();
    return accounts_transaction($db,function() use($db,$user,$id,$action,$reason): array {
        $s=$db->prepare("SELECT * FROM qbook_petty_cash_expenses WHERE id=? FOR UPDATE");$s->execute([$id]);$e=$s->fetch();if(!$e) accounts_fail('EXPENSE_NOT_FOUND',404);accounts_custodian($db,(int)$e['custodian_user_id'],true);
        if($action==='CORRECTION_REQUIRED'){
            if($e['status']!=='SUBMITTED') accounts_fail('EXPENSE_NOT_REVIEWABLE',409);$db->prepare("UPDATE qbook_petty_cash_expenses SET status='CORRECTION_REQUIRED',reviewed_by=?,reviewed_at=UTC_TIMESTAMP(),review_reason=? WHERE id=?")->execute([(int)$user['id'],$reason,$id]);$status='CORRECTION_REQUIRED';
        }elseif($action==='CANCELLED_NOT_SPENT'){
            if(!in_array($e['status'],['SUBMITTED','CORRECTION_REQUIRED'],true)) accounts_fail('EXPENSE_NOT_CANCELLABLE',409);$db->prepare("UPDATE qbook_petty_cash_expenses SET status='CANCELLED_NOT_SPENT',reviewed_by=?,reviewed_at=UTC_TIMESTAMP(),review_reason=? WHERE id=?")->execute([(int)$user['id'],$reason,$id]);$status='CANCELLED_NOT_SPENT';
        }else{
            if($e['status']!=='SUBMITTED') accounts_fail('EXPENSE_NOT_REVIEWABLE',409);if($e['journal_id']!==null) accounts_fail('SOURCE_ALREADY_POSTED',409);
            $minor=accounts_money_minor($e['amount'],false);$petty=accounts_account_id($db,'1200');
            $journal=accounts_post_journal($db,$user,['transaction_date'=>$e['expense_date'],'description'=>'Petty cash expense: '.$e['description'],'source_module'=>'PETTY_CASH_EXPENSE','source_record_id'=>$id,'approved_by'=>(int)$user['id']],[
              ['account_id'=>(int)$e['expense_account_id'],'debit_minor'=>$minor,'credit_minor'=>0,'client_id'=>$e['client_id'],'project_id'=>$e['project_id'],'mixer_id'=>$e['mixer_id'],'description'=>$e['description']],
              ['account_id'=>$petty,'debit_minor'=>0,'credit_minor'=>$minor,'custodian_user_id'=>(int)$e['custodian_user_id'],'description'=>$e['description']],
            ]);
            $db->prepare("UPDATE qbook_petty_cash_expenses SET status='APPROVED',journal_id=?,reviewed_by=?,reviewed_at=UTC_TIMESTAMP(),review_reason=NULL WHERE id=? AND journal_id IS NULL")->execute([$journal['id'],(int)$user['id'],$id]);$status='APPROVED';
        }
        accounts_audit($db,$user,'PETTY_CASH_EXPENSE_'.$status,'PETTY_CASH_EXPENSE',$id,['reason'=>$reason]);return ['expense'=>['id'=>$id,'status'=>$status],'balance'=>accounts_public_balance(accounts_custodian_balance($db,(int)$e['custodian_user_id']))];
    });
});
