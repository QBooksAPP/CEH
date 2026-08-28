<?php
declare(strict_types=1);
require_once __DIR__.'/report_pdf_common.php';
$user=billing_require_admin();production_require_method('GET');
$data=reports_receivables(production_db(),reports_filters($_GET));
reports_pdf_output('CEH-Receivables-Report.pdf',reports_pdf_receivables($data));
