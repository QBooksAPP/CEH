<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('GET');
accounts_endpoint(function() use($user): array {
    $target=(int)($_GET['custodian_user_id']??$user['id']); if(!accounts_can_access_custodian($user,$target)) accounts_fail('FORBIDDEN',403);
    $db=production_db(); accounts_custodian($db,$target);
    $sql="SELECT id,'FUNDING' AS transaction_type,funding_date AS transaction_date,amount,description,'POSTED' AS status,bank_reference AS reference_no FROM qbook_petty_cash_fundings WHERE custodian_user_id=?
      UNION ALL SELECT e.id,'EXPENSE',e.expense_date,e.amount,e.description,e.status,CASE WHEN r.reference_no IS NULL THEN 'Reference pending' ELSE CONCAT('CEH-PC-',LPAD(r.reference_no,6,'0')) END FROM qbook_petty_cash_expenses e LEFT JOIN qbook_petty_cash_expense_references r ON r.expense_id=e.id WHERE e.custodian_user_id=? ORDER BY transaction_date DESC,id DESC";
    $s=$db->prepare($sql);$s->execute([$target,$target]); return ['transactions'=>$s->fetchAll()];
});
