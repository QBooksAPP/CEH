<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
production_require_method('GET');

accounts_endpoint(function(): array {
    $db = production_db();
    $sql = "SELECT e.id,e.id AS source_record_id,r.reference_no,e.expense_date,e.amount,
                   a.code AS account_code,a.name AS category,
                   COALESCE(rc.new_supplier_paid_to,e.supplier_paid_to) AS supplier_paid_to,COALESCE(rc.new_description,e.description) AS description,
                   c.name AS client_name,p.name AS project_name,m.code AS mixer_code,
                   'PETTY_CASH' AS source_type,u.full_name AS source_name,
                   e.status AS lifecycle_status,e.journal_id,
                   j.reference_no AS original_journal_reference,j.status AS journal_status,
                   e.reversal_journal_id,rj.reference_no AS reversal_journal_reference,
                   rc.journal_id AS reclassification_journal_id,rcj.reference_no AS reclassification_journal_reference,
                   rc.reason AS reclassification_reason,rc.reclassified_at,rcu.full_name AS reclassified_by_name,
                   e.void_reason,e.voided_at,vu.full_name AS voided_by_name,
                   (SELECT COUNT(*) FROM qbook_financial_evidence v
                    WHERE v.source_type='PETTY_CASH_EXPENSE'
                      AND v.source_record_id=e.id) AS evidence_count,
                   (SELECT MIN(v.id) FROM qbook_financial_evidence v
                    WHERE v.source_type='PETTY_CASH_EXPENSE'
                      AND v.source_record_id=e.id) AS evidence_id
              FROM qbook_petty_cash_expenses e
              JOIN qbook_users u ON u.id=e.custodian_user_id
         LEFT JOIN qbook_petty_cash_expense_reclassifications rc ON rc.id=(SELECT MAX(rc2.id) FROM qbook_petty_cash_expense_reclassifications rc2 WHERE rc2.expense_id=e.id)
              JOIN qbook_accounts_chart a ON a.id=COALESCE(rc.new_expense_account_id,e.expense_account_id)
         LEFT JOIN qbook_financial_journals j ON j.id=e.journal_id
         LEFT JOIN qbook_financial_journals rj ON rj.id=e.reversal_journal_id
         LEFT JOIN qbook_financial_journals rcj ON rcj.id=rc.journal_id
         LEFT JOIN qbook_users rcu ON rcu.id=rc.reclassified_by
         LEFT JOIN qbook_users vu ON vu.id=e.voided_by
         LEFT JOIN qbook_petty_cash_expense_references r ON r.expense_id=e.id
         LEFT JOIN qbook_clients c ON c.id=COALESCE(rc.new_client_id,e.client_id)
         LEFT JOIN qbook_projects p ON p.id=COALESCE(rc.new_project_id,e.project_id)
         LEFT JOIN qbook_mixers m ON m.id=COALESCE(rc.new_mixer_id,e.mixer_id)
          ORDER BY e.expense_date DESC,e.id DESC
             LIMIT 500";
    $rows = $db->query($sql)->fetchAll();
    foreach ($rows as &$row) {
        $row['reference_no'] = accounts_petty_cash_reference($row['reference_no']);
        if ($row['lifecycle_status'] === 'VOIDED') {
            $row['posting_status'] = 'VOIDED / REVERSED';
        } elseif ($row['lifecycle_status'] === 'APPROVED') {
            $row['posting_status'] = $row['journal_status'] === 'POSTED'
                ? 'APPROVED / POSTED'
                : 'APPROVED / ' . ($row['journal_status'] ?? 'JOURNAL MISSING');
        } else {
            $row['posting_status'] = $row['lifecycle_status'] . ' / NOT POSTED';
        }
        unset($row['journal_status']);
    }
    unset($row);
    return ['expenses' => $rows];
});
