<?php
declare(strict_types=1);

require_once __DIR__ . '/billing_common.php';
$user = billing_require_admin();
production_require_method('POST');
$input = production_input();

accounts_endpoint(function () use ($user, $input): array {
    $db = production_db();
    return accounts_transaction($db, function () use ($db, $user, $input): array {
        $id = (int)($input['invoice_id'] ?? 0);
        $invoice = billing_invoice_outstanding($db, $id, true);
        if ($invoice['status'] !== 'DRAFT'
            || !$invoice['invoice_date']
            || accounts_money_minor($invoice['total_amount'], false) <= 0) {
            accounts_fail('INVOICE_NOT_ISSUABLE', 409);
        }

        // Lock the singleton with the invoice Issue transaction. This ensures
        // the exact settings validated here are the values snapshotted below.
        $settingsStatement = $db->query('SELECT * FROM qbook_invoice_settings WHERE id=1 FOR UPDATE');
        $settings = $settingsStatement->fetch();
        $snapshotFields = [
            'company_legal_name',
            'company_address',
            'tax_identifier',
            'payment_bank_details',
        ];
        foreach ($snapshotFields as $field) {
            if (trim((string)($settings[$field] ?? '')) === '') {
                accounts_fail('INVOICE_SETTINGS_INCOMPLETE', 409);
            }
        }
        if (trim((string)($invoice['terms_snapshot'] ?? '')) === '') {
            accounts_fail('INVOICE_TERMS_REQUIRED', 409);
        }

        $productionStatement = $db->prepare(
            'SELECT pa.* FROM qbook_invoice_production_allocations pa '
            . 'JOIN qbook_invoice_lines l ON l.id=pa.invoice_line_id '
            . 'WHERE l.invoice_id=? ORDER BY pa.id FOR UPDATE'
        );
        $productionStatement->execute([$id]);
        $allocations = $productionStatement->fetchAll();
        $lockedSessions = [];
        foreach ($allocations as $allocation) {
            $sessionId = (int)$allocation['production_session_id'];
            if (!isset($lockedSessions[$sessionId])) {
                $lock = $db->prepare(
                    'SELECT id FROM qbook_invoice_production_allocations '
                    . 'WHERE production_session_id=? ORDER BY id FOR UPDATE'
                );
                $lock->execute([$sessionId]);
                $lock->fetchAll();
                $lockedSessions[$sessionId] = true;
            }
            $sum = $db->prepare(
                "SELECT COALESCE((SELECT SUM(pa.billed_m3) FROM qbook_invoice_production_allocations pa JOIN qbook_invoice_lines l ON l.id=pa.invoice_line_id JOIN qbook_invoices i ON i.id=l.invoice_id WHERE pa.production_session_id=? AND pa.status='COMMITTED' AND i.status='ISSUED'),0)-COALESCE((SELECT SUM(cr.released_m3) FROM qbook_credit_note_production_releases cr JOIN qbook_credit_note_lines cl ON cl.id=cr.credit_note_line_id JOIN qbook_credit_notes cn ON cn.id=cl.credit_note_id AND cn.status='ISSUED' JOIN qbook_invoice_production_allocations pa2 ON pa2.id=cr.invoice_production_allocation_id WHERE pa2.production_session_id=?),0)"
            );
            $sum->execute([$sessionId, $sessionId]);
            if ((float)$sum->fetchColumn() + (float)$allocation['billed_m3']
                > (float)$allocation['signed_m3_snapshot']) {
                accounts_fail('PRODUCTION_M3_EXCEEDED', 409);
            }
        }

        // Accounting construction below is unchanged: one AR debit, line-level
        // Revenue credits and, where applicable, one Output VAT credit.
        $ar = billing_account_role($db,'TRADE_RECEIVABLES');
        $vat = billing_account_role($db,'OUTPUT_VAT_PAYABLE');
        $lineStatement = $db->prepare(
            'SELECT * FROM qbook_invoice_lines WHERE invoice_id=? ORDER BY line_no FOR UPDATE'
        );
        $lineStatement->execute([$id]);
        $journalLines = [[
            'account_id' => $ar,
            'debit_minor' => accounts_money_minor($invoice['total_amount'], false),
            'credit_minor' => 0,
            'description' => billing_ref('INVOICE', $invoice['reference_no']),
            'client_id' => (int)$invoice['client_id'],
        ]];
        foreach ($lineStatement->fetchAll() as $line) {
            $journalLines[] = [
                'account_id' => (int)$line['revenue_account_id'],
                'debit_minor' => 0,
                'credit_minor' => accounts_money_minor($line['net_amount'], false),
                'description' => $line['description'],
                'client_id'=>(int)$invoice['client_id'],
                'project_id' => $line['project_id'],
                'mixer_id' => $line['mixer_id'],
            ];
        }
        $vatMinor = accounts_money_minor($invoice['vat_amount'], false);
        if ($vatMinor > 0) {
            $journalLines[] = [
                'account_id' => $vat,
                'debit_minor' => 0,
                'credit_minor' => $vatMinor,
                'description' => 'Output VAT ' . billing_ref('INVOICE', $invoice['reference_no']),
                'client_id' => (int)$invoice['client_id'],
            ];
        }
        $journal = accounts_post_journal($db, $user, [
            'transaction_date' => $invoice['invoice_date'],
            'description' => 'Invoice ' . billing_ref('INVOICE', $invoice['reference_no']),
            'source_module'=>'INVOICE',
            'source_record_id' => $id,
            'approved_by' => $user['id'],
        ], $journalLines);

        $issue = $db->prepare(
            "UPDATE qbook_invoices SET status='ISSUED',journal_id=?,issued_at=UTC_TIMESTAMP(),issued_by=?,"
            . 'company_legal_name_snapshot=?,company_address_snapshot=?,tax_identifier_snapshot=?,payment_bank_details_snapshot=? '
            . "WHERE id=? AND status='DRAFT'"
        );
        $issue->execute([
            $journal['id'],
            $user['id'],
            trim((string)$settings['company_legal_name']),
            trim((string)$settings['company_address']),
            trim((string)$settings['tax_identifier']),
            trim((string)$settings['payment_bank_details']),
            $id,
        ]);
        if ($issue->rowCount() !== 1) accounts_fail('INVOICE_ISSUE_CONFLICT', 409);

        $db->prepare(
            "UPDATE qbook_invoice_production_allocations pa JOIN qbook_invoice_lines l ON l.id=pa.invoice_line_id SET pa.status='COMMITTED' WHERE l.invoice_id=?"
        )->execute([$id]);
        accounts_audit($db, $user, 'INVOICE_ISSUED', 'INVOICE', $id, [
            'journal_id' => $journal['id'],
            'issued_company_settings_snapshotted' => true,
        ]);
        return [
            'invoice' => [
                'id' => $id,
                'reference' => billing_ref('INVOICE', $invoice['reference_no']),
                'status' => 'ISSUED',
            ],
            'journal' => $journal,
        ];
    });
});
