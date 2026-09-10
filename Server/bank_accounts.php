<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('GET');
accounts_endpoint(function(): array {
    $db=production_db();
    $sql="SELECT b.id,b.name,b.bank_name,b.account_reference,b.currency,b.is_active,c.code AS ledger_code,
      COALESCE(SUM(l.debit-l.credit),0) AS current_balance,
      (SELECT ib.closing_balance FROM qbook_bank_import_batches ib WHERE ib.bank_account_id=b.id ORDER BY ib.statement_to DESC,ib.imported_at DESC,ib.id DESC LIMIT 1) AS statement_balance,
      (SELECT ib.statement_to FROM qbook_bank_import_batches ib WHERE ib.bank_account_id=b.id ORDER BY ib.statement_to DESC,ib.imported_at DESC,ib.id DESC LIMIT 1) AS statement_date,
      (SELECT COUNT(*) FROM qbook_bank_statement_rows r WHERE r.bank_account_id=b.id AND r.status IN('UNMATCHED','POTENTIAL_MATCH','POSSIBLE_DUPLICATE')) AS unreconciled_count
      FROM qbook_bank_accounts b JOIN qbook_accounts_chart c ON c.id=b.ledger_account_id
      LEFT JOIN qbook_financial_journal_lines l ON l.account_id=b.ledger_account_id
      GROUP BY b.id,b.name,b.bank_name,b.account_reference,b.currency,b.is_active,c.code ORDER BY b.name";
    $banks=$db->query($sql)->fetchAll();foreach($banks as &$bank){$ref=trim((string)$bank['account_reference']);$bank['masked_account_reference']=$ref===''?null:'•••• '.substr($ref,-4);unset($bank['account_reference']);}unset($bank);return ['bank_accounts'=>$banks];
});
