<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$input=production_input();

function bank_normalize_text(mixed $value,int $max): string {
    $text=production_clean_text($value,$max,'INVALID_BANK_TEXT',false);
    return strtolower(trim((string)preg_replace('/\s+/u',' ',$text)));
}

accounts_endpoint(function() use($user,$input): array {
    $bankId=(int)($input['bank_account_id']??0);if($bankId<=0)accounts_fail('BANK_ACCOUNT_REQUIRED');
    $filename=production_clean_text($input['filename']??'',255,'STATEMENT_FILENAME_REQUIRED');$type=strtoupper(trim((string)($input['file_type']??'')));if(!in_array($type,['CSV','XLSX'],true))accounts_fail('UNSUPPORTED_STATEMENT_TYPE');
    $hash=strtolower(trim((string)($input['file_sha256']??'')));if(!preg_match('/\A[a-f0-9]{64}\z/',$hash))accounts_fail('INVALID_STATEMENT_HASH');$rows=$input['rows']??null;if(!is_array($rows)||$rows===[]||count($rows)>10000)accounts_fail('STATEMENT_ROWS_REQUIRED');
    $from=isset($input['statement_from'])?accounts_date($input['statement_from']):null;$to=isset($input['statement_to'])?accounts_date($input['statement_to']):null;
    $opening=isset($input['opening_balance'])?accounts_minor_decimal(accounts_money_minor($input['opening_balance'],false)):null;$closing=isset($input['closing_balance'])?accounts_minor_decimal(accounts_money_minor($input['closing_balance'],false)):null;
    $db=production_db();return accounts_transaction($db,function() use($db,$user,$bankId,$filename,$type,$hash,$rows,$from,$to,$opening,$closing): array {
        $b=$db->prepare("SELECT id FROM qbook_bank_accounts WHERE id=? AND is_active=1 FOR UPDATE");$b->execute([$bankId]);if(!$b->fetch())accounts_fail('ACTIVE_BANK_ACCOUNT_REQUIRED');
        $d=$db->prepare("SELECT id FROM qbook_bank_import_batches WHERE bank_account_id=? AND file_sha256=?");$d->execute([$bankId,$hash]);if($d->fetch())accounts_fail('STATEMENT_ALREADY_IMPORTED',409);
        $db->prepare("INSERT INTO qbook_bank_import_batches(bank_account_id,original_filename,file_type,file_sha256,statement_from,statement_to,opening_balance,closing_balance,imported_by) VALUES(?,?,?,?,?,?,?,?,?)")->execute([$bankId,$filename,$type,$hash,$from,$to,$opening,$closing,(int)$user['id']]);$batch=(int)$db->lastInsertId();
        $insert=$db->prepare("INSERT INTO qbook_bank_statement_rows(import_batch_id,bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint,status,potential_source_type,potential_source_id) VALUES(?,?,?,?,?,?,?,?,?,?)");$inserted=0;$skipped=0;$potential=0;$possible=0;
        foreach($rows as $row){if(!is_array($row))accounts_fail('INVALID_STATEMENT_ROW');$date=accounts_date($row['date']??'');$minor=accounts_money_minor($row['amount']??'',false);if($minor===0)accounts_fail('INVALID_AMOUNT');$reference=production_clean_text($row['reference']??'',150,'INVALID_BANK_REFERENCE',false);$narration=production_clean_text($row['narration']??'',500,'BANK_NARRATION_REQUIRED');
            $fingerprint=hash('sha256',$date.'|'.$minor.'|'.bank_normalize_text($reference,150).'|'.bank_normalize_text($narration,500));$x=$db->prepare("SELECT id FROM qbook_bank_statement_rows WHERE bank_account_id=? AND row_fingerprint=?");$x->execute([$bankId,$fingerprint]);if($x->fetch()){$skipped++;continue;}
            $status='UNMATCHED';$sourceType=null;$sourceId=null;
            if($minor<0&&$reference!==''){$start=(new DateTimeImmutable($date))->modify('-3 days')->format('Y-m-d');$end=(new DateTimeImmutable($date))->modify('+3 days')->format('Y-m-d');$m=$db->prepare("SELECT id FROM qbook_petty_cash_fundings WHERE bank_account_id=? AND amount=? AND funding_date BETWEEN ? AND ? AND LOWER(TRIM(bank_reference))=LOWER(TRIM(?)) AND journal_id IS NOT NULL LIMIT 2");$m->execute([$bankId,accounts_minor_decimal(abs($minor)),$start,$end,$reference]);$candidates=$m->fetchAll();if(count($candidates)===1){$status='POTENTIAL_MATCH';$sourceType='PETTY_CASH_FUNDING';$sourceId=(int)$candidates[0]['id'];$potential++;}}
            if($minor<0&&$status==='UNMATCHED'){$start=(new DateTimeImmutable($date))->modify('-3 days')->format('Y-m-d');$end=(new DateTimeImmutable($date))->modify('+3 days')->format('Y-m-d');$m=$db->prepare("SELECT id FROM qbook_general_expenses WHERE bank_account_id=? AND amount=? AND expense_date BETWEEN ? AND ? AND status='APPROVED' AND journal_id IS NOT NULL AND ((?<>'' AND LOWER(TRIM(COALESCE(bank_reference,'')))=LOWER(TRIM(?))) OR (?='' AND supplier_name_snapshot IS NOT NULL AND LOWER(?) LIKE CONCAT('%',LOWER(supplier_name_snapshot),'%'))) LIMIT 2");$m->execute([$bankId,accounts_minor_decimal(abs($minor)),$start,$end,$reference,$reference,$reference,$narration]);$candidates=$m->fetchAll();if(count($candidates)===1){$status='POTENTIAL_MATCH';$sourceType='GENERAL_EXPENSE';$sourceId=(int)$candidates[0]['id'];$potential++;}}
            if($status==='UNMATCHED'){$start=(new DateTimeImmutable($date))->modify('-3 days')->format('Y-m-d');$end=(new DateTimeImmutable($date))->modify('+3 days')->format('Y-m-d');$dup=$db->prepare("SELECT id FROM qbook_bank_statement_rows WHERE bank_account_id=? AND amount=? AND transaction_date BETWEEN ? AND ? AND LOWER(TRIM(COALESCE(bank_reference,'')))=LOWER(TRIM(?)) LIMIT 1");$dup->execute([$bankId,accounts_minor_decimal($minor),$start,$end,$reference]);if($dup->fetch()){$status='POSSIBLE_DUPLICATE';$possible++;}}
            $insert->execute([$batch,$bankId,$date,accounts_minor_decimal($minor),$reference?:null,$narration,$fingerprint,$status,$sourceType,$sourceId]);$inserted++;
        }
        accounts_audit($db,$user,'BANK_STATEMENT_IMPORTED','BANK_IMPORT',$batch,['bank_account_id'=>$bankId,'inserted'=>$inserted,'duplicates_skipped'=>$skipped,'potential_matches'=>$potential]);
        return ['import'=>['id'=>$batch,'inserted'=>$inserted,'duplicates_skipped'=>$skipped,'potential_matches'=>$potential,'possible_duplicates'=>$possible]];
    });
});
