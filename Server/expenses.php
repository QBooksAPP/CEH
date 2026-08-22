<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
production_require_method('GET');

accounts_endpoint(function(): array {
    $db = production_db();
    $sql = "SELECT e.id,r.reference_no,e.expense_date,e.amount,
                   a.code AS account_code,a.name AS category,
                   e.supplier_paid_to,e.description,
                   c.name AS client_name,p.name AS project_name,m.code AS mixer_code,
                   'PETTY_CASH' AS source_type,u.full_name AS source_name,
                   j.status AS journal_status,
                   (SELECT COUNT(*) FROM qbook_financial_evidence v
                    WHERE v.source_type='PETTY_CASH_EXPENSE'
                      AND v.source_record_id=e.id) AS evidence_count
              FROM qbook_petty_cash_expenses e
              JOIN qbook_users u ON u.id=e.custodian_user_id
              JOIN qbook_accounts_chart a ON a.id=e.expense_account_id
              JOIN qbook_financial_journals j ON j.id=e.journal_id
         LEFT JOIN qbook_petty_cash_expense_references r ON r.expense_id=e.id
         LEFT JOIN qbook_clients c ON c.id=e.client_id
         LEFT JOIN qbook_projects p ON p.id=e.project_id
         LEFT JOIN qbook_mixers m ON m.id=e.mixer_id
             WHERE e.status='APPROVED'
          ORDER BY e.expense_date DESC,e.id DESC
             LIMIT 500";
    $rows = $db->query($sql)->fetchAll();
    foreach ($rows as &$row) {
        $row['reference_no'] = accounts_petty_cash_reference($row['reference_no']);
        $row['posting_status'] = $row['journal_status'] === 'POSTED'
            ? 'APPROVED / POSTED'
            : 'APPROVED / ' . $row['journal_status'];
        unset($row['journal_status']);
    }
    unset($row);
    return ['expenses' => $rows];
});
