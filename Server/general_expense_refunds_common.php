<?php
declare(strict_types=1);
require_once __DIR__ . '/bank_row_usage.php';

// Bank evidence linkage only: no journal posting, reversal or statement updates.
function general_expense_link_refund(PDO $db, array $user, int $expenseId, int $rowId): array {
    if ($expenseId <= 0 || $rowId <= 0) accounts_fail('REFUND_LINK_REQUIRED');
    return bank_ownership_transaction($db, function() use ($db, $user, $expenseId, $rowId): array {
        // Consistent ordering: statement row first, then source expense.
        $s = $db->prepare('SELECT * FROM qbook_bank_statement_rows WHERE id=? FOR UPDATE');
        $s->execute([$rowId]);
        $row = $s->fetch();
        if (!$row) accounts_fail('BANK_ROW_NOT_FOUND', 404);
        // Serialize partial refunds against the expense before reading its total.
        $e = $db->prepare("SELECT * FROM qbook_general_expenses WHERE id=? AND status='APPROVED' AND journal_id IS NOT NULL FOR UPDATE");
        $e->execute([$expenseId]);
        $expense = $e->fetch();
        if (!$expense) accounts_fail('EXPENSE_NOT_REFUNDABLE', 409);
        $minor = accounts_money_minor($row['amount'], false);
        if ($minor <= 0 || (int)$row['bank_account_id'] !== (int)$expense['bank_account_id']) accounts_fail('ACTUAL_BANK_CREDIT_REQUIRED', 409);
        $duplicate = $db->prepare('SELECT id FROM qbook_general_expense_refunds WHERE statement_row_id=? FOR UPDATE');
        $duplicate->execute([$rowId]);
        if ($duplicate->fetchColumn()) accounts_fail('REFUND_ALREADY_LINKED', 409);
        bank_row_available($db,$rowId);
        $already = $db->prepare('SELECT COALESCE(SUM(amount),0) FROM qbook_general_expense_refunds WHERE expense_id=?');
        $already->execute([$expenseId]);
        $existing = accounts_money_minor((string)$already->fetchColumn(), false);
        if ($existing + $minor > accounts_money_minor($expense['amount'], false)) accounts_fail('REFUND_EXCEEDS_EXPENSE', 409);
        $db->prepare('INSERT INTO qbook_general_expense_refunds(expense_id,statement_row_id,amount,linked_by) VALUES(?,?,?,?)')
            ->execute([$expenseId, $rowId, accounts_minor_decimal($minor), (int)$user['id']]);
        $id = (int)$db->lastInsertId();
        accounts_audit($db, $user, 'GENERAL_EXPENSE_REFUND_LINKED', 'GENERAL_EXPENSE', $expenseId,
            ['refund_link_id'=>$id, 'statement_row_id'=>$rowId, 'amount'=>accounts_minor_decimal($minor), 'statement_preserved'=>true, 'journal_posted'=>false]);
        return ['refund_link'=>['id'=>$id, 'expense_id'=>$expenseId, 'statement_row_id'=>$rowId, 'amount'=>accounts_minor_decimal($minor)], 'journal_posted'=>false];
    });
}

function general_expense_refunds_read(PDO $db, int $expenseId, array $input): array {
    if ($expenseId <= 0) accounts_fail('EXPENSE_REQUIRED');
    $view = (string)($input['view'] ?? 'history');
    if (!in_array($view, ['history', 'eligible'], true)) accounts_fail('INVALID_REFUND_VIEW');
    $page = max(1, (int)($input['page'] ?? 1));
    $size = max(1, min(100, (int)($input['page_size'] ?? 25)));
    $offset = ($page - 1) * $size;
    // One database snapshot keeps the summary, count and page consistent.
    return accounts_transaction($db, function() use ($db, $expenseId, $input, $view, $page, $size, $offset): array {
        $s = $db->prepare('SELECT e.id,e.amount,e.status,e.journal_id,e.bank_account_id,b.name bank_name,r.reference_no,
            (SELECT COALESCE(SUM(amount),0) FROM qbook_general_expense_refunds WHERE expense_id=e.id) linked_amount
            FROM qbook_general_expenses e LEFT JOIN qbook_bank_accounts b ON b.id=e.bank_account_id
            LEFT JOIN qbook_general_expense_references r ON r.expense_id=e.id WHERE e.id=?');
        $s->execute([$expenseId]);
        $expense = $s->fetch();
        if (!$expense) accounts_fail('EXPENSE_NOT_FOUND', 404);
        $amount = accounts_money_minor($expense['amount'], false);
        $linked = accounts_money_minor($expense['linked_amount'], false);
        $remaining = max(0, $amount - $linked);
        $canLink = $expense['status'] === 'APPROVED' && $expense['journal_id'] !== null && $remaining > 0;
        $expense['reference_no'] = accounts_general_expense_reference($expense['reference_no']);
        $expense['remaining_amount'] = accounts_minor_decimal($remaining);
        $expense['refund_status'] = $linked === 0 ? 'NONE' : ($linked >= $amount ? 'FULL' : 'PARTIAL');
        $expense['can_link'] = $canLink;
        unset($expense['journal_id']);
        if ($view === 'eligible') {
            $from = 'FROM qbook_bank_statement_rows s LEFT JOIN qbook_general_expense_refunds f ON f.statement_row_id=s.id';
            $where = ['s.bank_account_id=?', 's.amount>0', 's.amount<=?', 'f.id IS NULL', "s.status NOT IN ('MATCHED','RECONCILED')", 'NOT EXISTS(SELECT 1 FROM qbook_bank_matches bm WHERE bm.statement_row_id=s.id)', 'NOT EXISTS(SELECT 1 FROM qbook_customer_receipts cr WHERE cr.statement_row_id=s.id AND '.bank_payment_active_owner_sql('cr').')'];
            $params = [(int)$expense['bank_account_id'], accounts_minor_decimal($remaining)];
            if (!$canLink) $where[] = '1=0';
            $columns = 's.id statement_row_id,s.transaction_date,s.amount,s.bank_reference,s.narration,s.status statement_status,NULL linked_at,NULL linked_by_name';
        } else {
            $from = 'FROM qbook_general_expense_refunds f JOIN qbook_bank_statement_rows s ON s.id=f.statement_row_id LEFT JOIN qbook_users u ON u.id=f.linked_by';
            $where = ['f.expense_id=?'];
            $params = [$expenseId];
            $columns = 's.id statement_row_id,s.transaction_date,f.amount,s.bank_reference,s.narration,s.status statement_status,f.linked_at,u.full_name linked_by_name';
        }
        $search = trim((string)($input['search'] ?? ''));
        if (strlen($search) > 200) accounts_fail('SEARCH_TOO_LONG');
        if ($search !== '') {
            $where[] = '(s.narration LIKE ? OR s.bank_reference LIKE ?)';
            $params[] = '%'.$search.'%'; $params[] = '%'.$search.'%';
        }
        foreach (['date_from'=>'>=', 'date_to'=>'<='] as $key=>$operator) {
            if (!empty($input[$key])) { $where[] = "s.transaction_date {$operator} ?"; $params[] = accounts_date($input[$key]); }
        }
        if (!empty($input['date_from']) && !empty($input['date_to']) && $input['date_from'] > $input['date_to']) accounts_fail('INVALID_DATE_RANGE');
        $whereSql = ' WHERE '.implode(' AND ', $where);
        $count = $db->prepare("SELECT COUNT(*) {$from} {$whereSql}"); $count->execute($params);
        $total = (int)$count->fetchColumn();
        $rows = $db->prepare("SELECT {$columns} {$from} {$whereSql} ORDER BY s.transaction_date DESC,s.id DESC LIMIT {$size} OFFSET {$offset}");
        $rows->execute($params);
        return ['expense'=>$expense, 'view'=>$view, 'rows'=>$rows->fetchAll(), 'page'=>$page, 'page_size'=>$size, 'total'=>$total, 'total_pages'=>(int)ceil($total/$size)];
    });
}
