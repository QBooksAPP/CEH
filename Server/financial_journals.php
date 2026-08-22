<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('GET');
accounts_endpoint(function(): array {
    $db=production_db();
    $rows=$db->query("SELECT j.*,u.full_name AS created_by_name,a.full_name AS approved_by_name FROM qbook_financial_journals j JOIN qbook_users u ON u.id=j.created_by LEFT JOIN qbook_users a ON a.id=j.approved_by ORDER BY j.transaction_date DESC,j.id DESC LIMIT 500")->fetchAll();
    $line=$db->prepare("SELECT l.id,l.line_no,c.code AS account_code,c.name AS account_name,l.description,l.debit,l.credit,l.client_id,l.project_id,l.mixer_id,l.custodian_user_id FROM qbook_financial_journal_lines l JOIN qbook_accounts_chart c ON c.id=l.account_id WHERE l.journal_id=? ORDER BY l.line_no");
    foreach($rows as &$row){$line->execute([(int)$row['id']]);$row['lines']=$line->fetchAll();unset($row['created_by'],$row['approved_by']);}
    unset($row); return ['journals'=>$rows];
});
