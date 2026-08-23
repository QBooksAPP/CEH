<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('GET');
accounts_endpoint(function(): array {$db=production_db();$rows=$db->query("SELECT s.*,(SELECT COUNT(*) FROM qbook_general_expenses e WHERE e.supplier_id=s.id) AS transaction_count,(SELECT COALESCE(SUM(e.amount),0) FROM qbook_general_expenses e JOIN qbook_financial_journals j ON j.id=e.journal_id AND j.status='POSTED' WHERE e.supplier_id=s.id AND e.status='APPROVED') AS effective_spend,(SELECT MAX(e.expense_date) FROM qbook_general_expenses e WHERE e.supplier_id=s.id) AS last_used FROM qbook_suppliers s ORDER BY s.is_active DESC,s.canonical_name")->fetchAll();return ['suppliers'=>$rows];});
