<?php
declare(strict_types=1);

require_once __DIR__ . '/billing_common.php';
$user = billing_require_admin();
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
if (!in_array($method, ['GET', 'POST'], true)) accounts_fail('METHOD_NOT_ALLOWED', 405);

/** @return array<int,array<string,mixed>> */
function customer_credit_sources(PDO $db, int $clientId, bool $lock): array
{
    $sql = "SELECT r.*,
              COALESCE((SELECT SUM(a.cash_amount) FROM qbook_customer_receipt_allocations a WHERE a.receipt_id=r.id),0) cash_allocated,
              COALESCE((SELECT SUM(x.amount) FROM qbook_advance_applications x WHERE x.receipt_id=r.id),0) credit_applied
            FROM qbook_customer_receipts r
            WHERE r.client_id=? AND r.status='POSTED'
            ORDER BY r.receipt_date,r.id" . ($lock ? ' FOR UPDATE' : '');
    $statement = $db->prepare($sql);
    $statement->execute([$clientId]);
    $sources = [];
    foreach ($statement->fetchAll() as $row) {
        $available = accounts_money_minor($row['cash_amount'], false)
            - accounts_money_minor((string)$row['cash_allocated'], false)
            - accounts_money_minor((string)$row['credit_applied'], false);
        if ($available < 0) accounts_fail('CUSTOMER_CREDIT_INTEGRITY_ERROR', 500);
        if ($available > 0) {
            $row['available_minor'] = $available;
            $sources[] = $row;
        }
    }
    return $sources;
}

function customer_credit_total(array $sources): int
{
    return array_reduce($sources,
        static fn(int $total, array $source): int => $total + (int)$source['available_minor'], 0);
}

if ($method === 'GET') {
    accounts_endpoint(function (): array {
        $db = production_db();
        $client = billing_client($db, $_GET['client_id'] ?? 0);
        $sources = customer_credit_sources($db, (int)$client['id'], false);
        return [
            'client_id' => (int)$client['id'],
            'available_customer_credit' => accounts_minor_decimal(customer_credit_total($sources)),
        ];
    });
    return;
}

$input = production_input();
accounts_endpoint(function () use ($user, $input): array {
    $db = production_db();
    return accounts_transaction($db, function () use ($db, $user, $input): array {
        // Retain the original single receipt/invoice request contract for compatibility.
        $legacy = isset($input['receipt_id']) && !isset($input['allocations']);
        $clientId = (int)($input['client_id'] ?? 0);
        if ($legacy) {
            $receiptId = (int)$input['receipt_id'];
            $statement = $db->prepare("SELECT client_id FROM qbook_customer_receipts WHERE id=? AND status='POSTED'");
            $statement->execute([$receiptId]);
            $clientId = (int)$statement->fetchColumn();
            if ($clientId <= 0) accounts_fail('ADVANCE_RECEIPT_NOT_FOUND', 404);
            $allocations = [[
                'invoice_id' => $input['invoice_id'] ?? 0,
                'amount' => $input['amount'] ?? '',
                'receipt_id' => $receiptId,
            ]];
        } else {
            billing_client($db, $clientId);
            $allocations = $input['allocations'] ?? [];
        }
        if (!is_array($allocations) || $allocations === []) accounts_fail('INVALID_ADVANCE_ALLOCATIONS');

        $sources = customer_credit_sources($db, $clientId, true);
        $availableBefore = customer_credit_total($sources);
        $requested = [];
        $requestedTotal = 0;
        foreach ($allocations as $allocation) {
            if (!is_array($allocation)) accounts_fail('INVALID_ADVANCE_ALLOCATION');
            $invoiceId = (int)($allocation['invoice_id'] ?? 0);
            if ($invoiceId <= 0 || isset($requested[$invoiceId])) accounts_fail('DUPLICATE_INVOICE_ALLOCATION', 409);
            $amount = accounts_money_minor($allocation['amount'] ?? '');
            $invoice = billing_invoice_outstanding($db, $invoiceId, true);
            if ($invoice['status'] !== 'ISSUED' || (int)$invoice['client_id'] !== $clientId
                || $invoice['outstanding_minor'] <= 0) accounts_fail('INVOICE_ALLOCATION_MISMATCH', 409);
            if ($amount > $invoice['outstanding_minor']) accounts_fail('INVOICE_OVERALLOCATION', 409);
            $requested[$invoiceId] = ['invoice' => $invoice, 'amount' => $amount,
                'receipt_id' => (int)($allocation['receipt_id'] ?? 0)];
            $requestedTotal += $amount;
        }
        if ($requestedTotal > $availableBefore) accounts_fail('ADVANCE_OVERALLOCATION', 409);

        $applications = [];
        foreach ($requested as $invoiceId => $request) {
            $remaining = $request['amount'];
            foreach ($sources as &$source) {
                if ($remaining <= 0) break;
                if ($source['available_minor'] <= 0) continue;
                if ($request['receipt_id'] > 0 && (int)$source['id'] !== $request['receipt_id']) continue;
                $duplicate = $db->prepare('SELECT id FROM qbook_advance_applications WHERE receipt_id=? AND invoice_id=?');
                $duplicate->execute([(int)$source['id'], $invoiceId]);
                if ($duplicate->fetchColumn()) continue;

                $amount = min($remaining, (int)$source['available_minor']);
                $db->prepare('INSERT INTO qbook_advance_applications(receipt_id,invoice_id,amount,applied_by)VALUES(?,?,?,?)')
                    ->execute([(int)$source['id'], $invoiceId, accounts_minor_decimal($amount), $user['id']]);
                $applicationId = (int)$db->lastInsertId();
                $journal = accounts_post_journal($db, $user, [
                    'transaction_date' => accounts_date($input['application_date'] ?? gmdate('Y-m-d')),
                    'description' => 'Apply ' . billing_ref('RECEIPT', $source['reference_no']) . ' to '
                        . billing_ref('INVOICE', $request['invoice']['reference_no']),
                    'source_module' => 'CUSTOMER_ADVANCE_APPLICATION',
                    'source_record_id' => $applicationId,
                    'approved_by' => $user['id'],
                ], [
                    ['account_id' => billing_account_role($db,'CUSTOMER_ADVANCES'),
                        'debit_minor' => $amount, 'credit_minor' => 0,
                        'description' => 'Apply customer credit / advance', 'client_id' => $clientId],
                    ['account_id' => billing_account_role($db,'TRADE_RECEIVABLES'),
                        'debit_minor' => 0, 'credit_minor' => $amount,
                        'description' => 'Settle invoice from customer credit', 'client_id' => $clientId],
                ]);
                $db->prepare('UPDATE qbook_advance_applications SET journal_id=? WHERE id=?')
                    ->execute([$journal['id'], $applicationId]);
                $source['available_minor'] -= $amount;
                $remaining -= $amount;
                $applications[] = ['id' => $applicationId, 'receipt_id' => (int)$source['id'],
                    'invoice_id' => $invoiceId, 'amount' => accounts_minor_decimal($amount),
                    'journal_id' => (int)$journal['id']];
                accounts_audit($db, $user, 'CUSTOMER_ADVANCE_APPLIED', 'CUSTOMER_RECEIPT', (int)$source['id'], [
                    'application_id' => $applicationId, 'invoice_id' => $invoiceId,
                    'amount' => accounts_minor_decimal($amount),
                ]);
            }
            unset($source);
            if ($remaining > 0) accounts_fail('ADVANCE_SOURCE_ALLOCATION_UNAVAILABLE', 409);
        }
        return ['applications' => $applications,
            'total_applied' => accounts_minor_decimal($requestedTotal),
            'remaining_customer_credit' => accounts_minor_decimal($availableBefore - $requestedTotal)];
    });
});
