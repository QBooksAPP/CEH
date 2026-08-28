<?php
declare(strict_types=1);
require_once __DIR__.'/report_pdf_common.php';
$user=billing_require_admin();production_require_method('GET');
$data=reports_expense_rows(production_db(),reports_filters($_GET),false);
reports_pdf_output('CEH-Full-Expense-Audit-Pack.pdf',reports_pdf_expenses('Full Expense Audit Pack',$data,true));
