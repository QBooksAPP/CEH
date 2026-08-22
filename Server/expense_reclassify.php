<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $type=strtoupper(trim((string)($input['source_type']??'')));$id=(int)($input['source_record_id']??0);
    if($type!=='PETTY_CASH_EXPENSE'||$id<=0) accounts_fail('EXPENSE_SOURCE_NOT_SUPPORTED');
    $reason=production_clean_text($input['reason']??'',500,'RECLASSIFICATION_REASON_REQUIRED');$db=production_db();
    return accounts_transaction($db,function() use($db,$user,$input,$id,$type,$reason): array {
        $s=$db->prepare("SELECT e.*,r.reference_no,j.status AS journal_status FROM qbook_petty_cash_expenses e LEFT JOIN qbook_petty_cash_expense_references r ON r.expense_id=e.id LEFT JOIN qbook_financial_journals j ON j.id=e.journal_id WHERE e.id=? FOR UPDATE");$s->execute([$id]);$expense=$s->fetch();if(!$expense) accounts_fail('EXPENSE_NOT_FOUND',404);
        if($expense['status']!=='APPROVED'||$expense['journal_id']===null||$expense['journal_status']!=='POSTED') accounts_fail('EXPENSE_NOT_RECLASSIFIABLE',409);
        $latest=$db->prepare("SELECT * FROM qbook_petty_cash_expense_reclassifications WHERE expense_id=? ORDER BY id DESC LIMIT 1 FOR UPDATE");$latest->execute([$id]);$previous=$latest->fetch()?:null;
        $oldAccount=(int)($previous['new_expense_account_id']??$expense['expense_account_id']);$oldSupplier=(string)($previous['new_supplier_paid_to']??$expense['supplier_paid_to']);$oldDescription=(string)($previous['new_description']??$expense['description']);
        $oldClient=$previous?accounts_nullable_id($previous['new_client_id']):accounts_nullable_id($expense['client_id']);$oldProject=$previous?accounts_nullable_id($previous['new_project_id']):accounts_nullable_id($expense['project_id']);$oldMixer=$previous?accounts_nullable_id($previous['new_mixer_id']):accounts_nullable_id($expense['mixer_id']);
        $newAccount=(int)($input['expense_account_id']??0);if($newAccount<=0) accounts_fail('EXPENSE_ACCOUNT_REQUIRED');$a=$db->prepare("SELECT id FROM qbook_accounts_chart WHERE id=? AND account_type='EXPENSE' AND is_active=1 AND is_postable=1");$a->execute([$newAccount]);if(!$a->fetch()) accounts_fail('EXPENSE_ACCOUNT_REQUIRED');
        $newSupplier=production_clean_text($input['supplier_paid_to']??'',200,'SUPPLIER_REQUIRED');$newDescription=production_clean_text($input['description']??'',500,'DESCRIPTION_REQUIRED');$newClient=accounts_nullable_id($input['client_id']??null);$newProject=accounts_nullable_id($input['project_id']??null);$newMixer=accounts_nullable_id($input['mixer_id']??null);accounts_validate_dimensions($db,$newClient,$newProject,$newMixer);
        $insert=$db->prepare("INSERT INTO qbook_petty_cash_expense_reclassifications(expense_id,prior_expense_account_id,new_expense_account_id,prior_supplier_paid_to,new_supplier_paid_to,prior_description,new_description,prior_client_id,new_client_id,prior_project_id,new_project_id,prior_mixer_id,new_mixer_id,reason,reclassified_by) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
        $insert->execute([$id,$oldAccount,$newAccount,$oldSupplier,$newSupplier,$oldDescription,$newDescription,$oldClient,$newClient,$oldProject,$newProject,$oldMixer,$newMixer,$reason,(int)$user['id']]);$correctionId=(int)$db->lastInsertId();$minor=accounts_money_minor($expense['amount'],false);
        $journal=accounts_post_journal($db,$user,['transaction_date'=>gmdate('Y-m-d'),'description'=>'Reclassify '.accounts_petty_cash_reference($expense['reference_no']).': '.$reason,'source_module'=>'PETTY_CASH_RECLASSIFICATION','source_record_id'=>$correctionId,'entry_kind'=>'REPLACEMENT','approved_by'=>(int)$user['id']],[
          ['account_id'=>$newAccount,'debit_minor'=>$minor,'credit_minor'=>0,'client_id'=>$newClient,'project_id'=>$newProject,'mixer_id'=>$newMixer,'description'=>$newDescription],
          ['account_id'=>$oldAccount,'debit_minor'=>0,'credit_minor'=>$minor,'client_id'=>$oldClient,'project_id'=>$oldProject,'mixer_id'=>$oldMixer,'description'=>'Reclassify from: '.$oldDescription],
        ]);
        $db->prepare("UPDATE qbook_petty_cash_expense_reclassifications SET journal_id=? WHERE id=? AND journal_id IS NULL")->execute([$journal['id'],$correctionId]);
        accounts_audit($db,$user,'EXPENSE_RECLASSIFIED',$type,$id,['reference_no'=>accounts_petty_cash_reference($expense['reference_no']),'original_journal_id'=>(int)$expense['journal_id'],'reclassification_journal_id'=>$journal['id'],'reason'=>$reason,'prior'=>['expense_account_id'=>$oldAccount,'supplier_paid_to'=>$oldSupplier,'description'=>$oldDescription,'client_id'=>$oldClient,'project_id'=>$oldProject,'mixer_id'=>$oldMixer],'corrected'=>['expense_account_id'=>$newAccount,'supplier_paid_to'=>$newSupplier,'description'=>$newDescription,'client_id'=>$newClient,'project_id'=>$newProject,'mixer_id'=>$newMixer]]);
        return ['expense'=>['id'=>$id,'source_type'=>$type,'reference_no'=>accounts_petty_cash_reference($expense['reference_no']),'status'=>'APPROVED'],'reclassification'=>['id'=>$correctionId,'journal_id'=>$journal['id'],'journal_reference'=>$journal['reference_no'],'reason'=>$reason],'asset_impact'=>accounts_minor_decimal(0)];
    });
});
