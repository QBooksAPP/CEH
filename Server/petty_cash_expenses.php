<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('GET');
accounts_endpoint(function() use($user): array {
    $db=production_db();$admin=strtoupper((string)$user['role'])==='ADMIN';$target=(int)($_GET['custodian_user_id']??0);
    if(!$admin){if($target>0&&$target!==(int)$user['id']) accounts_fail('FORBIDDEN',403);$target=(int)$user['id'];}
    $where=$target>0?'WHERE e.custodian_user_id=?':'';$params=$target>0?[$target]:[];
    $s=$db->prepare("SELECT e.id,r.reference_no,e.custodian_user_id,u.full_name AS custodian_name,e.expense_date,e.amount,e.expense_account_id,a.code AS account_code,a.name AS category,e.supplier_paid_to,e.description,e.client_id,c.name AS client_name,e.project_id,p.name AS project_name,e.mixer_id,m.code AS mixer_code,e.status,e.no_receipt_reason,e.submitted_at,e.reviewed_at,e.review_reason,e.created_at,(SELECT COUNT(*) FROM qbook_financial_evidence v WHERE v.source_type='PETTY_CASH_EXPENSE' AND v.source_record_id=e.id) AS evidence_count FROM qbook_petty_cash_expenses e JOIN qbook_users u ON u.id=e.custodian_user_id JOIN qbook_accounts_chart a ON a.id=e.expense_account_id LEFT JOIN qbook_petty_cash_expense_references r ON r.expense_id=e.id LEFT JOIN qbook_clients c ON c.id=e.client_id LEFT JOIN qbook_projects p ON p.id=e.project_id LEFT JOIN qbook_mixers m ON m.id=e.mixer_id $where ORDER BY e.expense_date DESC,e.id DESC LIMIT 500");$s->execute($params);
    $rows=$s->fetchAll();foreach($rows as &$row){$row['reference_no']=accounts_petty_cash_reference($row['reference_no']);}unset($row);
    return ['expenses'=>$rows];
});
