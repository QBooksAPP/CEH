<?php
declare(strict_types=1);

require_once __DIR__ . '/billing_common.php';
require_once __DIR__ . '/company_regional_common.php';
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
        $legacyWht = isset($input['wht_amount']) && trim((string)$input['wht_amount']) !== '';
        if ($legacyWht) {
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
        $allocationWhtMode = false;
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
            $allocationWht = null;
            if ($whtAmount > 0 && isset($allocation['wht_tax_code_id'])) {
                $allocationWhtMode = true;
                if ($legacyWht) accounts_fail('MIXED_WHT_CONTRACT_NOT_ALLOWED', 409);
                $code = billing_tax_code($db, $allocation['wht_tax_code_id'], 'WHT', $receipt['receipt_date']);
                $baseAmount = accounts_money_minor($allocation['wht_calculation_base_amount'] ?? '');
                $suggestedWht = billing_percent_amount($baseAmount, (string)$code['rate_percent']);
                if (isset($allocation['wht_suggested_amount'])) {
                    $clientSuggested = accounts_money_minor($allocation['wht_suggested_amount']);
                    if ($clientSuggested !== $suggestedWht) {
                        accounts_fail('WHT_SUGGESTION_MISMATCH', 409);
                    }
                }
                $overrideReasonRaw = trim((string)($allocation['wht_override_reason'] ?? ''));
                $isOverride = $suggestedWht !== $whtAmount;
                if ($isOverride && $overrideReasonRaw === '') {
                    accounts_fail('WHT_OVERRIDE_REASON_REQUIRED', 409);
                }
                if (!$isOverride && $overrideReasonRaw !== '') {
                    accounts_fail('WHT_OVERRIDE_REASON_NOT_ALLOWED', 409);
                }
                $overrideReason = $isOverride
                    ? production_clean_text($overrideReasonRaw, 500, 'INVALID_WHT_OVERRIDE_REASON')
                    : null;
                $status = strtoupper((string)($allocation['certificate_status'] ?? 'CERTIFICATE_PENDING'));
                if (!in_array($status, ['CERTIFICATE_PENDING', 'CERTIFICATE_RECEIVED'], true)) {
                    accounts_fail('INVALID_WHT_CERTIFICATE_STATUS');
                }
                $evidenceId = accounts_nullable_id($allocation['wht_certificate_evidence_id'] ?? null);
                if ($evidenceId !== null) {
                    $evidence = $db->prepare("SELECT id FROM qbook_financial_evidence WHERE id=? AND source_type='WHT_CERTIFICATE' AND source_record_id=?");
                    $evidence->execute([$evidenceId, $id]);
                    if (!$evidence->fetch()) accounts_fail('WHT_CERTIFICATE_EVIDENCE_INVALID', 409);
                }
                if ($status === 'CERTIFICATE_RECEIVED' && $evidenceId === null) {
                    accounts_fail('WHT_CERTIFICATE_EVIDENCE_REQUIRED', 409);
                }
                $allocationWht = [
                    'code' => $code,
                    'base_minor' => $baseAmount,
                    'suggested_minor' => $suggestedWht,
                    'override_reason' => $overrideReason,
                    'status' => $status,
                    'evidence_id' => $evidenceId,
                ];
            } elseif ($whtAmount > 0 && !$legacyWht) {
                accounts_fail('WHT_CODE_REQUIRED', 409);
            } elseif ($whtAmount === 0 && (isset($allocation['wht_tax_code_id']) || isset($allocation['wht_calculation_base_amount']))) {
                accounts_fail('WHT_AMOUNT_REQUIRED', 409);
            }
            if ($cashAmount + $whtAmount <= 0 || $cashAmount + $whtAmount > $invoice['outstanding_minor']) {
                accounts_fail('INVOICE_OVERALLOCATION', 409);
            }
            $cashAllocated += $cashAmount;
            $whtAllocated += $whtAmount;
            $normalized[] = [$invoice, $cashAmount, $whtAmount, $allocationWht];
        }
        if ($allocationWhtMode) $wht = $whtAllocated;
        if ($cashAllocated > $cash || $whtAllocated > $wht) accounts_fail('RECEIPT_OVERALLOCATION', 409);
        if ($whtAllocated !== $wht) accounts_fail('WHT_MUST_BE_FULLY_ALLOCATED', 409);
        $unallocatedCash = $cash - $cashAllocated;
        if ($unallocatedCash < 0) accounts_fail('RECEIPT_OVERALLOCATION', 409);

        $certificateReceived = $certificateStatus === 'CERTIFICATE_RECEIVED';
        if ($certificateReceived) {
            $evidence = $db->prepare("SELECT id FROM qbook_financial_evidence WHERE source_type='WHT_CERTIFICATE' AND source_record_id=? LIMIT 1");
            $evidence->execute([$id]);
            if (!$evidence->fetch()) accounts_fail('WHT_CERTIFICATE_EVIDENCE_REQUIRED', 409);
        }

        $settingsStatement = $db->query('SELECT * FROM qbook_invoice_settings WHERE id=1 FOR UPDATE');
        $settings = $settingsStatement->fetch();
        $regional = company_regional_settings($db, $user, true);
        foreach (['company_legal_name','company_address','tax_identifier'] as $field) {
            if (trim((string)($settings[$field] ?? '')) === '') {
                accounts_fail('CLIENT_PAYMENT_SETTINGS_INCOMPLETE', 409);
            }
        }

        $bank = $db->prepare('SELECT ledger_account_id,name FROM qbook_bank_accounts WHERE id=? AND is_active=1 FOR UPDATE');
        $bank->execute([$receipt['bank_account_id']]);
        $bankRow = $bank->fetch();
        if (!$bankRow) accounts_fail('ACTIVE_BANK_ACCOUNT_REQUIRED', 409);
        $bankAccount = (int)$bankRow['ledger_account_id'];
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
        $insertAllocationWht = $db->prepare('INSERT INTO qbook_customer_receipt_allocation_wht(receipt_allocation_id,tax_code_id,rate_snapshot,calculation_base_snapshot,calculation_base_amount,suggested_amount,accepted_amount,override_reason,certificate_status,certificate_evidence_id,certificate_received_at)VALUES(?,?,?,?,?,?,?,?,?,?,?)');
        foreach ($normalized as [$invoice, $cashAmount, $whtAmount, $allocationWht]) {
            $insertAllocation->execute([$id, $invoice['id'], accounts_minor_decimal($cashAmount), accounts_minor_decimal($whtAmount), $user['id']]);
            if ($allocationWht !== null) {
                $allocationId = (int)$db->lastInsertId();
                $code = $allocationWht['code'];
                $status = $allocationWht['status'];
                $insertAllocationWht->execute([
                    $allocationId, $code['id'], $code['rate_percent'], $code['calculation_base'],
                    accounts_minor_decimal($allocationWht['base_minor']), accounts_minor_decimal($allocationWht['suggested_minor']),
                    accounts_minor_decimal($whtAmount), $allocationWht['override_reason'],
                    $status, $allocationWht['evidence_id'], $status === 'CERTIFICATE_RECEIVED' ? gmdate('Y-m-d H:i:s') : null,
                ]);
            }
        }
        if ($legacyWht && $wht > 0) {
            $db->prepare('INSERT INTO qbook_receipt_wht(receipt_id,tax_code_id,rate_snapshot,calculation_base_snapshot,accepted_amount,certificate_status,certificate_received_at)VALUES(?,?,?,?,?,?,?)')
                ->execute([$id, $whtCode['id'], $whtCode['rate_percent'], $whtCode['calculation_base'], accounts_minor_decimal($wht), $certificateStatus, $certificateStatus === 'CERTIFICATE_RECEIVED' ? gmdate('Y-m-d H:i:s') : null]);
        }
        // Retained for compatibility only. Allocation and journal lines are authoritative.
        $legacyDestination = $arCredit > 0 ? 'TRADE_RECEIVABLES' : 'CUSTOMER_ADVANCES';
        $db->prepare("UPDATE qbook_customer_receipts SET destination=?,status='POSTED',journal_id=?,posted_by=?,posted_at=UTC_TIMESTAMP(),company_legal_name_snapshot=?,company_address_snapshot=?,tax_identifier_snapshot=?,payment_bank_details_snapshot=?,received_into_snapshot=?,currency_code_snapshot=?,pdf_template_version='CLIENT_PAYMENT_V1' WHERE id=?")
            ->execute([$legacyDestination, $journal['id'], $user['id'], trim((string)$settings['company_legal_name']), trim((string)$settings['company_address']), trim((string)$settings['tax_identifier']), trim((string)($settings['payment_bank_details'] ?? '')) ?: null, trim((string)$bankRow['name']), $regional['base_currency'], $id]);
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
