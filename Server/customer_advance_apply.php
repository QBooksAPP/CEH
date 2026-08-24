<?php
declare(strict_types=1);

require_once __DIR__ . '/billing_common.php';
$user = billing_require_admin();
production_require_method('POST');
$input = production_input();

accounts_endpoint(function () use ($user, $input): array {
    $db = production_db();
    return accounts_transaction($db, function () use ($db, $user, $input): array {
        $receiptId = (int)($input['receipt_id'] ?? 0);
        $statement = $db->prepare("SELECT * FROM qbook_customer_receipts WHERE id=? AND status='POSTED' FOR UPDATE");
        $statement->execute([$receiptId]);
        $receipt = $statement->fetch();
        if (!$receipt) accounts_fail('ADVANCE_RECEIPT_NOT_FOUND', 404);

        $invoice = billing_invoice_outstanding($db, (int)($input['invoice_id'] ?? 0), true);
        if ($invoice['status'] !== 'ISSUED' || (int)$invoice['client_id'] !== (int)$receipt['client_id']) {
            accounts_fail('INVOICE_ALLOCATION_MISMATCH', 409);
        }
        $amount = accounts_money_minor($input['amount'] ?? '');
        $allocated = $db->prepare('SELECT COALESCE(SUM(cash_amount),0) FROM qbook_customer_receipt_allocations WHERE receipt_id=?');
        $allocated->execute([$receiptId]);
        $allocatedMinor = accounts_money_minor((string)$allocated->fetchColumn(), false);
        $used = $db->prepare('SELECT COALESCE(SUM(amount),0) FROM qbook_advance_applications WHERE receipt_id=?');
        $used->execute([$receiptId]);
        $usedMinor = accounts_money_minor((string)$used->fetchColumn(), false);
        $availableMinor = accounts_money_minor($receipt['cash_amount'], false) - $allocatedMinor - $usedMinor;
        if ($availableMinor < 0) accounts_fail('CUSTOMER_CREDIT_INTEGRITY_ERROR', 500);
        if ($amount > $invoice['outstanding_minor'] || $amount > $availableMinor) {
            accounts_fail('ADVANCE_OVERALLOCATION', 409);
        }

        $db->prepare('INSERT INTO qbook_advance_applications(receipt_id,invoice_id,amount,applied_by)VALUES(?,?,?,?)')
            ->execute([$receiptId, $invoice['id'], accounts_minor_decimal($amount), $user['id']]);
        $applicationId = (int)$db->lastInsertId();
        $journal = accounts_post_journal($db, $user, [
            'transaction_date' => accounts_date($input['application_date'] ?? gmdate('Y-m-d')),
            'description' => 'Apply ' . billing_ref('RECEIPT', $receipt['reference_no']) . ' to ' . billing_ref('INVOICE', $invoice['reference_no']),
            'source_module' => 'CUSTOMER_ADVANCE_APPLICATION',
            'source_record_id' => $applicationId,
            'approved_by' => $user['id'],
        ], [
            [
                'account_id' => billing_account_role($db,'CUSTOMER_ADVANCES'),
                'debit_minor' => $amount, 'credit_minor' => 0,
                'description' => 'Apply customer credit / advance',
                'client_id' => (int)$receipt['client_id'],
            ],
            [
                'account_id' => billing_account_role($db,'TRADE_RECEIVABLES'),
                'debit_minor' => 0, 'credit_minor' => $amount,
                'description' => 'Settle invoice from customer credit',
                'client_id' => (int)$receipt['client_id'],
            ],
        ]);
        $db->prepare('UPDATE qbook_advance_applications SET journal_id=? WHERE id=?')
            ->execute([$journal['id'], $applicationId]);
        accounts_audit($db, $user, 'CUSTOMER_ADVANCE_APPLIED', 'CUSTOMER_RECEIPT', $receiptId, [
            'application_id' => $applicationId,
            'invoice_id' => $invoice['id'],
            'amount' => accounts_minor_decimal($amount),
            'remaining_customer_credit' => accounts_minor_decimal($availableMinor - $amount),
        ]);
        return [
            'application' => [
                'id' => $applicationId,
                'amount' => accounts_minor_decimal($amount),
                'remaining_customer_credit' => accounts_minor_decimal($availableMinor - $amount),
            ],
            'journal' => $journal,
        ];
    });
});
