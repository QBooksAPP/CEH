<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('GET');
accounts_endpoint(function(): array {
    $bankId=(int)($_GET['bank_account_id']??0); if($bankId<=0) accounts_fail('BANK_ACCOUNT_REQUIRED');
    $stmt=production_db()->prepare("SELECT id,transaction_date,amount,bank_reference,narration,status,potential_source_type,potential_source_id FROM qbook_bank_statement_rows WHERE bank_account_id=? ORDER BY transaction_date DESC,id DESC LIMIT 500");
    $stmt->execute([$bankId]); return ['transactions'=>$stmt->fetchAll()];
});
