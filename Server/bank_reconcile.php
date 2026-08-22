<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $rowId=(int)($input['statement_row_id']??0);$sourceType=strtoupper(trim((string)($input['source_type']??'')));$sourceId=(int)($input['source_record_id']??0);if($rowId<=0||$sourceId<=0||$sourceType!=='PETTY_CASH_FUNDING')accounts_fail('INVALID_BANK_MATCH');$db=production_db();
    return accounts_transaction($db,function() use($db,$user,$rowId,$sourceType,$sourceId): array {
        $s=$db->prepare("SELECT * FROM qbook_bank_statement_rows WHERE id=? FOR UPDATE");$s->execute([$rowId]);$row=$s->fetch();if(!$row)accounts_fail('BANK_ROW_NOT_FOUND',404);if(in_array($row['status'],['MATCHED','RECONCILED'],true))accounts_fail('BANK_ROW_ALREADY_MATCHED',409);
        $f=$db->prepare("SELECT * FROM qbook_petty_cash_fundings WHERE id=? AND journal_id IS NOT NULL");$f->execute([$sourceId]);$fund=$f->fetch();if(!$fund)accounts_fail('FUNDING_NOT_FOUND',404);
        $rowMinor=accounts_money_minor($row['amount'],false);$fundMinor=accounts_money_minor($fund['amount'],false);$days=abs((new DateTimeImmutable($row['transaction_date']))->diff(new DateTimeImmutable($fund['funding_date']))->days);
        if((int)$fund['bank_account_id']!==(int)$row['bank_account_id']||$rowMinor!==-$fundMinor||$days>3)accounts_fail('BANK_MATCH_MISMATCH',409);
        $db->prepare("INSERT INTO qbook_bank_matches(statement_row_id,source_type,source_record_id,matched_by) VALUES(?,?,?,?)")->execute([$rowId,$sourceType,$sourceId,(int)$user['id']]);$match=(int)$db->lastInsertId();$db->prepare("UPDATE qbook_bank_statement_rows SET status='RECONCILED',potential_source_type=?,potential_source_id=? WHERE id=?")->execute([$sourceType,$sourceId,$rowId]);accounts_audit($db,$user,'BANK_ROW_RECONCILED','BANK_MATCH',$match,['statement_row_id'=>$rowId,'source_type'=>$sourceType,'source_record_id'=>$sourceId]);return ['match'=>['id'=>$match,'status'=>'RECONCILED']];
    });
});
