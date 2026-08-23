<?php
declare(strict_types=1);

require_once __DIR__ . '/production_log_common.php';

final class AccountsApiError extends RuntimeException {
    public function __construct(public readonly string $errorCode, public readonly int $httpStatus = 422) {
        parent::__construct($errorCode);
    }
}

function accounts_fail(string $code, int $status = 422): never {
    throw new AccountsApiError($code, $status);
}

function accounts_endpoint(callable $action): never {
    try {
        $payload = $action();
        qbook_json(['ok' => true] + (is_array($payload) ? $payload : []));
    } catch (AccountsApiError $e) {
        qbook_json(['ok' => false, 'error' => $e->errorCode], $e->httpStatus);
    } catch (Throwable $e) {
        $endpoint = basename((string)($_SERVER['SCRIPT_NAME'] ?? 'unknown'));
        $sqlState = $e instanceof PDOException && isset($e->errorInfo[0])
            ? (string)$e->errorInfo[0]
            : '-';
        $driverCode = $e instanceof PDOException && isset($e->errorInfo[1])
            ? (string)$e->errorInfo[1]
            : '-';
        error_log(sprintf(
            'CEH Accounts endpoint failure endpoint=%s type=%s sqlstate=%s driver=%s file=%s line=%d message=%s',
            $endpoint,
            get_class($e),
            $sqlState,
            $driverCode,
            basename($e->getFile()),
            $e->getLine(),
            $e->getMessage()
        ));
        qbook_json(['ok' => false, 'error' => 'SERVER_ERROR'], 500);
    }
}

function accounts_transaction(PDO $db, callable $action): mixed {
    $db->beginTransaction();
    try {
        $result = $action();
        $db->commit();
        return $result;
    } catch (Throwable $e) {
        if ($db->inTransaction()) $db->rollBack();
        throw $e;
    }
}

function accounts_money_minor(mixed $value, bool $positive = true): int {
    $raw = trim((string)$value);
    if (!preg_match('/\A([+-]?)(\d{1,16})(?:\.(\d{1,2}))?\z/', $raw, $m)) {
        accounts_fail('INVALID_AMOUNT');
    }
    $minor = ((int)$m[2] * 100) + (int)str_pad($m[3] ?? '', 2, '0');
    if (($m[1] ?? '') === '-') $minor *= -1;
    if ($positive && $minor <= 0) {
        accounts_fail('INVALID_AMOUNT');
    }
    return $minor;
}

function accounts_minor_decimal(int $minor): string {
    $sign = $minor < 0 ? '-' : '';
    $absolute = abs($minor);
    return sprintf('%s%d.%02d', $sign, intdiv($absolute, 100), $absolute % 100);
}

function accounts_date(mixed $value): string {
    $date = trim((string)$value);
    $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $date, new DateTimeZone('UTC'));
    if (!$parsed || $parsed->format('Y-m-d') !== $date) accounts_fail('INVALID_DATE');
    return $date;
}

function accounts_nullable_id(mixed $value): ?int {
    if ($value === null || $value === '') return null;
    $id = (int)$value;
    if ($id <= 0) accounts_fail('INVALID_REFERENCE');
    return $id;
}

function accounts_reference(string $prefix): string {
    return $prefix . '-' . gmdate('YmdHis') . '-' . strtoupper(bin2hex(random_bytes(4)));
}

function accounts_petty_cash_reference(mixed $number): ?string {
    if ($number === null || $number === '') return null;
    $value = (int)$number;
    if ($value <= 0) accounts_fail('INVALID_PETTY_CASH_REFERENCE', 500);
    return 'CEH-PC-' . str_pad((string)$value, 6, '0', STR_PAD_LEFT);
}

function accounts_general_expense_reference(mixed $number): ?string {
    if ($number === null || $number === '') return null;
    $value = (int)$number;
    if ($value <= 0) accounts_fail('INVALID_GENERAL_EXPENSE_REFERENCE', 500);
    return 'CEH-EX-' . str_pad((string)$value, 6, '0', STR_PAD_LEFT);
}

function accounts_normalized_name(mixed $value): string {
    $name = production_clean_text($value, 200, 'SUPPLIER_REQUIRED');
    $collapsed = trim((string)preg_replace('/\s+/u', ' ', $name));
    $normalized = function_exists('mb_strtolower')
        ? mb_strtolower($collapsed, 'UTF-8')
        : strtolower($collapsed);
    if ($normalized === '') accounts_fail('SUPPLIER_REQUIRED');
    return $normalized;
}

function accounts_supplier(PDO $db, mixed $supplierId, bool $active = true): array {
    $id = (int)$supplierId;
    if ($id <= 0) accounts_fail('SUPPLIER_REQUIRED');
    $sql = "SELECT * FROM qbook_suppliers WHERE id=?" . ($active ? " AND is_active=1" : "");
    $stmt = $db->prepare($sql);
    $stmt->execute([$id]);
    $supplier = $stmt->fetch();
    if (!$supplier) accounts_fail('ACTIVE_SUPPLIER_REQUIRED', 409);
    return $supplier;
}

function accounts_cost_centre(PDO $db, mixed $costCentreId, bool $active = true): ?int {
    $id = accounts_nullable_id($costCentreId);
    if ($id === null) return null;
    $sql = "SELECT id FROM qbook_cost_centres WHERE id=?" . ($active ? " AND is_active=1" : "");
    $stmt = $db->prepare($sql);
    $stmt->execute([$id]);
    if (!$stmt->fetch()) accounts_fail('ACTIVE_COST_CENTRE_REQUIRED', 409);
    return $id;
}

/** Validate and normalize submitted expense lines. Monetary calculations use minor units. */
function accounts_expense_lines(PDO $db, mixed $value, bool $require = true): array {
    if (!is_array($value) || ($require && $value === [])) accounts_fail('EXPENSE_LINES_REQUIRED');
    if (count($value) > 100) accounts_fail('TOO_MANY_EXPENSE_LINES');
    $result = [];
    foreach (array_values($value) as $index => $line) {
        if (!is_array($line)) accounts_fail('INVALID_EXPENSE_LINE');
        $amount = accounts_money_minor($line['amount'] ?? '');
        $accountId = (int)($line['expense_account_id'] ?? 0);
        $account = $db->prepare("SELECT id FROM qbook_accounts_chart WHERE id=? AND account_type='EXPENSE' AND is_active=1 AND is_postable=1");
        $account->execute([$accountId]);
        if (!$account->fetch()) accounts_fail('EXPENSE_ACCOUNT_REQUIRED');
        $quantityRaw = trim((string)($line['quantity'] ?? ''));
        $unitRaw = trim((string)($line['unit_price'] ?? ''));
        if (($quantityRaw === '') !== ($unitRaw === '')) accounts_fail('QUANTITY_UNIT_PRICE_PAIR_REQUIRED');
        $quantity = null; $unitPrice = null;
        if ($quantityRaw !== '') {
            if (!preg_match('/\A\d{1,12}(?:\.\d{1,4})?\z/', $quantityRaw) || (float)$quantityRaw <= 0) accounts_fail('INVALID_QUANTITY');
            $quantity = number_format((float)$quantityRaw, 4, '.', '');
            $unitPrice = accounts_money_minor($unitRaw);
            $calculated = (int)round((float)$quantity * $unitPrice);
            if ($calculated !== $amount) accounts_fail('LINE_QUANTITY_TOTAL_MISMATCH');
        }
        $costCentre = accounts_cost_centre($db, $line['cost_centre_id'] ?? null);
        if ($costCentre === null) accounts_fail('COST_CENTRE_REQUIRED');
        $client = accounts_nullable_id($line['client_id'] ?? null);
        $project = accounts_nullable_id($line['project_id'] ?? null);
        $mixer = accounts_nullable_id($line['mixer_id'] ?? null);
        accounts_validate_dimensions($db, $client, $project, $mixer);
        $result[] = [
            'line_no' => $index + 1,
            'item_description' => production_clean_text($line['description'] ?? $line['item_description'] ?? '', 500, 'LINE_DESCRIPTION_REQUIRED'),
            'expense_account_id' => $accountId,
            'amount_minor' => $amount,
            'quantity' => $quantity,
            'unit_price_minor' => $unitPrice,
            'cost_centre_id' => $costCentre,
            'client_id' => $client, 'project_id' => $project, 'mixer_id' => $mixer,
        ];
    }
    return $result;
}

function accounts_expense_lines_total(array $lines): int {
    return array_reduce($lines, fn(int $sum, array $line): int => $sum + (int)$line['amount_minor'], 0);
}

function accounts_require_line_total(array $lines, int $headerMinor): void {
    if ($lines === [] || accounts_expense_lines_total($lines) !== $headerMinor) accounts_fail('EXPENSE_LINE_TOTAL_MISMATCH');
}

function accounts_replace_expense_lines(PDO $db, string $table, int $expenseId, array $lines): void {
    if (!in_array($table, ['qbook_petty_cash_expense_lines','qbook_general_expense_lines'], true)) accounts_fail('INVALID_LINE_TABLE', 500);
    $db->prepare("DELETE FROM {$table} WHERE expense_id=?")->execute([$expenseId]);
    $insert = $db->prepare("INSERT INTO {$table}(expense_id,line_no,item_description,expense_account_id,amount,quantity,unit_price,cost_centre_id,client_id,project_id,mixer_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)");
    foreach ($lines as $line) {
        $insert->execute([$expenseId,$line['line_no'],$line['item_description'],$line['expense_account_id'],accounts_minor_decimal($line['amount_minor']),$line['quantity'],$line['unit_price_minor']===null?null:accounts_minor_decimal($line['unit_price_minor']),$line['cost_centre_id'],$line['client_id'],$line['project_id'],$line['mixer_id']]);
    }
}

function accounts_load_expense_lines(PDO $db, string $table, int $expenseId, bool $lock = false): array {
    if (!in_array($table, ['qbook_petty_cash_expense_lines','qbook_general_expense_lines'], true)) accounts_fail('INVALID_LINE_TABLE', 500);
    $stmt=$db->prepare("SELECT * FROM {$table} WHERE expense_id=? ORDER BY line_no" . ($lock ? " FOR UPDATE" : ""));
    $stmt->execute([$expenseId]);
    return $stmt->fetchAll();
}

function accounts_audit(PDO $db, array $user, string $event, string $sourceType, int $sourceId, array $details = []): void {
    $json = $details === [] ? null : json_encode($details, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
    if ($details !== [] && $json === false) accounts_fail('AUDIT_SERIALIZATION_FAILED', 500);
    $stmt = $db->prepare("INSERT INTO qbook_financial_audit(event_type,source_type,source_record_id,actor_user_id,details_json) VALUES(?,?,?,?,?)");
    $stmt->execute([strtoupper($event), strtoupper($sourceType), $sourceId, (int)$user['id'], $json]);
}

function accounts_account_id(PDO $db, string $code): int {
    $stmt = $db->prepare("SELECT id FROM qbook_accounts_chart WHERE code=? AND is_active=1 AND is_postable=1");
    $stmt->execute([$code]);
    $id = $stmt->fetchColumn();
    if (!$id) accounts_fail('ACCOUNT_NOT_AVAILABLE', 409);
    return (int)$id;
}

function accounts_validate_dimensions(PDO $db, ?int $clientId, ?int $projectId, ?int $mixerId): void {
    if ($projectId !== null) {
        if ($clientId === null) accounts_fail('PROJECT_REQUIRES_CLIENT');
        $stmt = $db->prepare("SELECT id FROM qbook_projects WHERE id=? AND client_id=?");
        $stmt->execute([$projectId, $clientId]);
        if (!$stmt->fetch()) accounts_fail('PROJECT_CLIENT_MISMATCH');
    } elseif ($clientId !== null) {
        $stmt = $db->prepare("SELECT id FROM qbook_clients WHERE id=?");
        $stmt->execute([$clientId]);
        if (!$stmt->fetch()) accounts_fail('CLIENT_NOT_FOUND', 404);
    }
    if ($mixerId !== null) {
        $stmt = $db->prepare("SELECT id FROM qbook_mixers WHERE id=?");
        $stmt->execute([$mixerId]);
        if (!$stmt->fetch()) accounts_fail('EQUIPMENT_NOT_FOUND', 404);
    }
}

function accounts_custodian(PDO $db, int $userId, bool $lock = false): array {
    $sql = "SELECT c.id,c.user_id,c.is_active,u.full_name,u.role,u.is_active AS user_active FROM qbook_petty_cash_custodians c JOIN qbook_users u ON u.id=c.user_id WHERE c.user_id=?" . ($lock ? " FOR UPDATE" : "");
    $stmt = $db->prepare($sql);
    $stmt->execute([$userId]);
    $row = $stmt->fetch();
    if (!$row || !(bool)$row['is_active'] || !(bool)$row['user_active']) accounts_fail('ACTIVE_CUSTODIAN_REQUIRED', 403);
    return $row;
}

function accounts_can_access_custodian(array $user, int $custodianUserId): bool {
    return strtoupper((string)$user['role']) === 'ADMIN' || (int)$user['id'] === $custodianUserId;
}

function accounts_custodian_balance(PDO $db, int $custodianUserId): array {
    $funded = $db->prepare("SELECT COALESCE(SUM(f.amount),0) FROM qbook_petty_cash_fundings f JOIN qbook_financial_journals j ON j.id=f.journal_id AND j.status='POSTED' WHERE f.custodian_user_id=?");
    $funded->execute([$custodianUserId]);
    $accounted = $db->prepare("SELECT COALESCE(SUM(e.amount),0) FROM qbook_petty_cash_expenses e JOIN qbook_financial_journals j ON j.id=e.journal_id AND j.status='POSTED' WHERE e.custodian_user_id=? AND e.status IN ('APPROVED','VOIDED')");
    $accounted->execute([$custodianUserId]);
    $pending = $db->prepare("SELECT COALESCE(SUM(amount),0) FROM qbook_petty_cash_expenses WHERE custodian_user_id=? AND status IN ('SUBMITTED','CORRECTION_REQUIRED')");
    $pending->execute([$custodianUserId]);
    $fundedMinor = accounts_money_minor((string)$funded->fetchColumn(), false);
    $accountedRaw = (string)$accounted->fetchColumn();
    $pendingRaw = (string)$pending->fetchColumn();
    $accountedMinor = $accountedRaw === '0' || $accountedRaw === '0.00' ? 0 : accounts_money_minor($accountedRaw, false);
    $pendingMinor = $pendingRaw === '0' || $pendingRaw === '0.00' ? 0 : accounts_money_minor($pendingRaw, false);
    $balanceMinor = $fundedMinor - $accountedMinor;
    return [
        'funds_received' => accounts_minor_decimal($fundedMinor),
        'accounted' => accounts_minor_decimal($accountedMinor),
        'pending' => accounts_minor_decimal($pendingMinor),
        'balance' => accounts_minor_decimal($balanceMinor),
        'available' => accounts_minor_decimal($balanceMinor - $pendingMinor),
        '_available_minor' => $balanceMinor - $pendingMinor,
    ];
}

function accounts_post_journal(PDO $db, array $user, array $header, array $lines): array {
    if (!$db->inTransaction()) accounts_fail('JOURNAL_TRANSACTION_REQUIRED', 500);
    if (count($lines) < 2) accounts_fail('JOURNAL_LINES_REQUIRED');
    $debits = 0;
    $credits = 0;
    foreach ($lines as $line) {
        $debit = (int)($line['debit_minor'] ?? 0);
        $credit = (int)($line['credit_minor'] ?? 0);
        if (($debit > 0) === ($credit > 0)) accounts_fail('INVALID_JOURNAL_LINE');
        $debits += $debit;
        $credits += $credit;
    }
    if ($debits <= 0 || $debits !== $credits) accounts_fail('UNBALANCED_JOURNAL');

    $sourceModule = strtoupper(production_clean_text($header['source_module'] ?? '', 60, 'SOURCE_MODULE_REQUIRED'));
    $sourceId = (int)($header['source_record_id'] ?? 0);
    if ($sourceId <= 0) accounts_fail('SOURCE_RECORD_REQUIRED');
    $entryKind = strtoupper((string)($header['entry_kind'] ?? 'ORIGINAL'));
    if (!in_array($entryKind, ['ORIGINAL','REVERSAL','REPLACEMENT'], true)) accounts_fail('INVALID_ENTRY_KIND');
    $duplicate = $db->prepare("SELECT id FROM qbook_financial_journals WHERE source_module=? AND source_record_id=? AND entry_kind=?");
    $duplicate->execute([$sourceModule, $sourceId, $entryKind]);
    if ($duplicate->fetch()) accounts_fail('SOURCE_ALREADY_POSTED', 409);

    $reference = accounts_reference('CEH-JRN');
    $stmt = $db->prepare("INSERT INTO qbook_financial_journals(reference_no,transaction_date,description,source_module,source_record_id,entry_kind,reversal_of_id,created_by,approved_by) VALUES(?,?,?,?,?,?,?,?,?)");
    $stmt->execute([
        $reference,
        accounts_date($header['transaction_date'] ?? ''),
        production_clean_text($header['description'] ?? '', 500, 'DESCRIPTION_REQUIRED'),
        $sourceModule,
        $sourceId,
        $entryKind,
        accounts_nullable_id($header['reversal_of_id'] ?? null),
        (int)$user['id'],
        accounts_nullable_id($header['approved_by'] ?? null),
    ]);
    $journalId = (int)$db->lastInsertId();
    $insert = $db->prepare("INSERT INTO qbook_financial_journal_lines(journal_id,line_no,account_id,description,debit,credit,cost_centre_id,client_id,project_id,mixer_id,custodian_user_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)");
    foreach ($lines as $index => $line) {
        $accountId = (int)($line['account_id'] ?? 0);
        $check = $db->prepare("SELECT id FROM qbook_accounts_chart WHERE id=? AND is_active=1 AND is_postable=1");
        $check->execute([$accountId]);
        if (!$check->fetch()) accounts_fail('ACCOUNT_NOT_AVAILABLE', 409);
        $costCentreId = accounts_cost_centre($db, $line['cost_centre_id'] ?? null, false);
        $clientId = accounts_nullable_id($line['client_id'] ?? null);
        $projectId = accounts_nullable_id($line['project_id'] ?? null);
        $mixerId = accounts_nullable_id($line['mixer_id'] ?? null);
        accounts_validate_dimensions($db, $clientId, $projectId, $mixerId);
        $insert->execute([
            $journalId, $index + 1, $accountId,
            production_clean_text($line['description'] ?? '', 500, 'INVALID_LINE_DESCRIPTION', false) ?: null,
            accounts_minor_decimal((int)($line['debit_minor'] ?? 0)),
            accounts_minor_decimal((int)($line['credit_minor'] ?? 0)),
            $costCentreId, $clientId, $projectId, $mixerId,
            accounts_nullable_id($line['custodian_user_id'] ?? null),
        ]);
    }
    accounts_audit($db, $user, 'JOURNAL_POSTED', 'JOURNAL', $journalId, ['reference_no' => $reference, 'source_module' => $sourceModule, 'source_record_id' => $sourceId]);
    return ['id' => $journalId, 'reference_no' => $reference, 'debit' => accounts_minor_decimal($debits), 'credit' => accounts_minor_decimal($credits), 'status' => 'POSTED'];
}

function accounts_reverse_journal(PDO $db, array $user, int $journalId, string $reason, string $date): array {
    $stmt = $db->prepare("SELECT * FROM qbook_financial_journals WHERE id=? FOR UPDATE");
    $stmt->execute([$journalId]);
    $original = $stmt->fetch();
    if (!$original) accounts_fail('JOURNAL_NOT_FOUND', 404);
    if ($original['status'] !== 'POSTED') accounts_fail('JOURNAL_NOT_REVERSIBLE', 409);
    $lineStmt = $db->prepare("SELECT * FROM qbook_financial_journal_lines WHERE journal_id=? ORDER BY line_no");
    $lineStmt->execute([$journalId]);
    $lines = [];
    foreach ($lineStmt->fetchAll() as $line) {
        $lines[] = [
            'account_id' => (int)$line['account_id'],
            'debit_minor' => accounts_money_minor((string)$line['credit'], false),
            'credit_minor' => accounts_money_minor((string)$line['debit'], false),
            'description' => 'Reversal: ' . $reason,
            'cost_centre_id' => $line['cost_centre_id'],
            'client_id' => $line['client_id'], 'project_id' => $line['project_id'],
            'mixer_id' => $line['mixer_id'], 'custodian_user_id' => $line['custodian_user_id'],
        ];
    }
    $reversal = accounts_post_journal($db, $user, [
        'transaction_date' => $date, 'description' => 'Reversal of ' . $original['reference_no'] . ': ' . $reason,
        'source_module' => 'JOURNAL_REVERSAL', 'source_record_id' => $journalId,
        'entry_kind' => 'REVERSAL', 'reversal_of_id' => $journalId, 'approved_by' => (int)$user['id'],
    ], $lines);
    $db->prepare("UPDATE qbook_financial_journals SET status='REVERSED',reversed_at=UTC_TIMESTAMP() WHERE id=? AND status='POSTED'")->execute([$journalId]);
    accounts_audit($db, $user, 'JOURNAL_REVERSED', 'JOURNAL', $journalId, ['reversal_journal_id' => $reversal['id'], 'reason' => $reason]);
    return $reversal;
}

function accounts_public_balance(array $balance): array {
    unset($balance['_available_minor']);
    return $balance;
}
