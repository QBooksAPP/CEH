<?php
declare(strict_types=1);
require_once __DIR__ . '/general_expense_refunds_common.php';
$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
production_require_method('POST');
$input = production_input();
accounts_endpoint(fn(): array => general_expense_link_refund(production_db(), $user,
    (int)($input['expense_id'] ?? 0), (int)($input['statement_row_id'] ?? 0)));
