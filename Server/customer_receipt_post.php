<?php
declare(strict_types=1);

require_once __DIR__ . '/billing_common.php';
$user = billing_require_admin();
production_require_method('POST');
$input = production_input();

accounts_endpoint(function () use ($user, $input): array {
    $db = production_db();
    return accounts_transaction($db, function () use ($db, $user, $input): array {
        $id = (int)($input['receipt_id'] ?? 0);
        $statement = $db->prepare('SELECT * FROM qbook_customer_receipts WHERE id=? FOR UPDATE');
        $statement->execute([$id]);
        $receipt = $statement->fetch();
        if (!$receipt) accounts_fail('RECEIPT_NOT_FOUND', 404);
        if ($receipt['status'] !== 'DRAFT') accounts_fail('RECEIPT_ALREADY_POSTED', 409);

        $cash = accounts_money_minor($receipt['cash_amount'], false);
        $wht = 0;
        $whtCode = null;
        $certificateStatus = 'NOT_APPLICABLE';
        if (isset($input['wht_amount']) && trim((string)$input['wht_amount']) !== '') {
            $wht = accounts_money_minor($input['wht_amount']);
            $whtCode = billing_tax_code($db, $input['wht_tax_code_id'] ?? 0, 'WHT', $receipt['receipt_date']);
            $certificateStatus = strtoupper((string)($input['certificate_status'] ?? 'CERTIFICATE_PENDING'));
            if (!in_array($certificateStatus, ['CERTIFICATE_PENDING', 'CERTIFICATE_RECEIVED'], true)) {
                accounts_fail('INVALID_WHT_CERTIFICATE_STATUS');
            }
        }

        $allocations = $input['allocations'] ?? [];
        if (!is_array($allocations)) accounts_fail('INVALID_ALLOCATIONS');
        $cashAllocated = 0;
        $whtAllocated = 0;
        $normalized = [];
        $invoiceIds = [];
        foreach ($allocations as $allocation) {
            if (!is_array($allocation)) accounts_fail('INVALID_ALLOCATION');
            $invoiceId = (int)($allocation['invoice_id'] ?? 0);
            if (isset($invoiceIds[$invoiceId])) accounts_fail('DUPLICATE_INVOICE_ALLOCATION', 409);
            $invoiceIds[$invoiceId] = true;
            $invoice = billing_invoice_outstanding($db, $invoiceId, true);
            if ($invoice['status'] !== 'ISSUED' || (int)$invoice['client_id'] !== (int)$receipt['client_id']) {
                accounts_fail('INVOICE_ALLOCATION_MISMATCH', 409);
            }
            $cashAmount = isset($allocation['cash_amount']) && trim((string)$allocation['cash_amount']) !== ''
                ? accounts_money_minor($allocation['cash_amount'], false) : 0;
            $whtAmount = isset($allocation['wht_amount']) && trim((string)$allocation['wht_amount']) !== ''
                ? accounts_money_minor($allocation['wht_amount'], false) : 0;
            if ($cashAmount + $whtAmount <= 0 || $cashAmount + $whtAmount > $invoice['outstanding_minor']) {
                accounts_fail('INVOICE_OVERALLOCATION', 409);
            }
            $cashAllocated += $cashAmount;
            $whtAllocated += $whtAmount;
            $normalized[] = [$invoice, $cashAmount, $whtAmount];
        }
        if ($cashAllocated > $cash || $whtAllocated > $wht) accounts_fail('RECEIPT_OVERALLOCATION', 409);
        if ($whtAllocated !== $wht) accounts_fail('WHT_MUST_BE_FULLY_ALLOCATED', 409);
        $unallocatedCash = $cash - $cashAllocated;
        if ($unallocatedCash < 0) accounts_fail('RECEIPT_OVERALLOCATION', 409);

        if ($certificateStatus === 'CERTIFICATE_RECEIVED') {
            $evidence = $db->prepare("SELECT id FROM qbook_financial_evidence WHERE source_type='WHT_CERTIFICATE' AND source_record_id=? LIMIT 1");
            $evidence->execute([$id]);
            if (!$evidence->fetch()) accounts_fail('WHT_CERTIFICATE_EVIDENCE_REQUIRED', 409);
        }

        $bank = $db->prepare('SELECT ledger_account_id FROM qbook_bank_accounts WHERE id=?');
        $bank->execute([$receipt['bank_account_id']]);
        $bankAccount = (int)$bank->fetchColumn();
        $reference = billing_ref('RECEIPT', $receipt['reference_no']);
        $lines = [[
            'account_id' => $bankAccount, 'debit_minor' => $cash, 'credit_minor' => 0,
            'description' => $reference, 'client_id' => (int)$receipt['client_id'],
        ]];
        if ($wht > 0) {
            $lines[] = [
                'account_id' => billing_account_role($db,'WHT_RECEIVABLE'),
                'debit_minor' => $wht, 'credit_minor' => 0,
                'description' => 'Accepted WHT ' . $reference,
                'client_id' => (int)$receipt['client_id'],
            ];
        }
        $arCredit = $cashAllocated + $whtAllocated;
        if ($arCredit > 0) {
            $lines[] = [
                'account_id' => billing_account_role($db,'TRADE_RECEIVABLES'),
                'debit_minor' => 0, 'credit_minor' => $arCredit,
                'description' => 'Invoice allocation ' . $reference,
                'client_id' => (int)$receipt['client_id'],
            ];
        }
        if ($unallocatedCash > 0) {
            $lines[] = [
                'account_id' => billing_account_role($db,'CUSTOMER_ADVANCES'),
                'debit_minor' => 0, 'credit_minor' => $unallocatedCash,
                'description' => 'Customer credit / advance ' . $reference,
                'client_id' => (int)$receipt['client_id'],
            ];
        }

        $journal = accounts_post_journal($db, $user, [
            'transaction_date' => $receipt['receipt_date'],
            'description' => 'Customer payment ' . $reference,
            'source_module' => 'CUSTOMER_RECEIPT', 'source_record_id' => $id,
            'approved_by' => $user['id'],
        ], $lines);

        $insertAllocation = $db->prepare('INSERT INTO qbook_customer_receipt_allocations(receipt_id,invoice_id,cash_amount,wht_amount,allocated_by)VALUES(?,?,?,?,?)');
        foreach ($normalized as [$invoice, $cashAmount, $whtAmount]) {
            $insertAllocation->execute([$id, $invoice['id'], accounts_minor_decimal($cashAmount), accounts_minor_decimal($whtAmount), $user['id']]);
        }
        if ($wht > 0) {
            $db->prepare('INSERT INTO qbook_receipt_wht(receipt_id,tax_code_id,rate_snapshot,calculation_base_snapshot,accepted_amount,certificate_status,certificate_received_at)VALUES(?,?,?,?,?,?,?)')
                ->execute([$id, $whtCode['id'], $whtCode['rate_percent'], $whtCode['calculation_base'], accounts_minor_decimal($wht), $certificateStatus, $certificateStatus === 'CERTIFICATE_RECEIVED' ? gmdate('Y-m-d H:i:s') : null]);
        }
        // Retained for compatibility only. Allocation and journal lines are authoritative.
        $legacyDestination = $arCredit > 0 ? 'TRADE_RECEIVABLES' : 'CUSTOMER_ADVANCES';
        $db->prepare("UPDATE qbook_customer_receipts SET destination=?,status='POSTED',journal_id=?,posted_by=?,posted_at=UTC_TIMESTAMP() WHERE id=?")
            ->execute([$legacyDestination, $journal['id'], $user['id'], $id]);
        accounts_audit($db, $user, 'CUSTOMER_RECEIPT_POSTED', 'CUSTOMER_RECEIPT', $id, [
            'journal_id' => $journal['id'],
            'cash_allocated' => accounts_minor_decimal($cashAllocated),
            'wht_allocated' => accounts_minor_decimal($whtAllocated),
            'unallocated_cash' => accounts_minor_decimal($unallocatedCash),
        ]);
        return [
            'receipt' => [
                'id' => $id, 'reference' => $reference, 'status' => 'POSTED',
                'cash_allocated' => accounts_minor_decimal($cashAllocated),
                'unallocated_cash' => accounts_minor_decimal($unallocatedCash),
            ],
            'journal' => $journal,
        ];
    });
});
