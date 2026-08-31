<?php
declare(strict_types=1);

// Technical production-equivalent regression. These are explicit QA fixtures.
$repository = dirname(__DIR__);
$output = $argv[1] ?? sys_get_temp_dir().DIRECTORY_SEPARATOR.'ceh-report-regression';
if (!is_dir($output) && !mkdir($output, 0700, true) && !is_dir($output)) throw new RuntimeException('REGRESSION_OUTPUT_UNAVAILABLE');
chdir($output);
require_once $repository.DIRECTORY_SEPARATOR.'Server'.DIRECTORY_SEPARATOR.'report_pdf_common.php';
$rendererSource = (string)file_get_contents($repository.DIRECTORY_SEPARATOR.'Server'.DIRECTORY_SEPARATOR.'report_pdf_common.php');
if (str_contains($rendererSource, 'SetFillColor(...REPORT_PDF_ALT)')) {
    throw new RuntimeException('REGRESSION_ACCOUNTING_REPORT_ZEBRA_FILL_PRESENT');
}
if (!preg_match('/SetY\(38\);\s*\$pdf->SetFillColor\(255,\s*255,\s*255\);\s*\$pdf->SetDrawColor\(\.\.\.REPORT_PDF_BORDER\)/', $rendererSource)) {
    throw new RuntimeException('REGRESSION_ACCOUNTING_REPORT_FILTER_PANEL_NOT_WHITE');
}

// Established Invoice-preview identity fixture. Production reports instead read
// qbook_invoice_settings and qbook_company_regional_settings.
$company = [
    'company_legal_name' => 'Concrete Equipment Hire Limited',
    'company_address' => "12 Agbado Road\nIju Ishaga\nLagos, Nigeria.",
    'tax_identifier' => '0000000001', 'time_zone' => 'Africa/Lagos',
    'date_format' => 'DD-MM-YYYY', 'time_format' => '12_HOUR', 'base_currency' => 'NGN',
];
$filters = [
    'date_from' => '2026-08-01', 'date_to' => '2026-08-29', 'as_of' => '2026-08-29',
    'qa_notice' => 'QA SAMPLE / NOT PRODUCTION DATA',
    'source' => 'ALL', 'status' => '', 'reference' => '', 'paid_to' => '',
    'custodian' => '', 'category' => '', 'client' => '', 'project' => '',
    'equipment' => '', 'cost_centre' => '', 'evidence' => 'ALL',
    'account_id' => 0, 'client_id' => 0, 'project_id' => 0, 'mixer_id' => 0, 'cost_centre_id' => 0,
];

function regression_receipt_jpeg(): string {
    $image = imagecreatetruecolor(1800, 2500);
    $white = imagecolorallocate($image, 255, 255, 255); $ink = imagecolorallocate($image, 18, 18, 18); $grey = imagecolorallocate($image, 75, 75, 75);
    imagefill($image, 0, 0, $white); imagerectangle($image, 70, 70, 1728, 2428, $ink);
    imagestring($image, 5, 720, 170, 'QA SAMPLE RECEIPT', $ink); imagestring($image, 5, 700, 250, 'NOT PRODUCTION DATA', $ink);
    imageline($image, 170, 360, 1630, 360, $grey);
    $lines = ['Supplier: Example Industrial Supplies (Fictional)', 'Receipt: QA-RECEIPT-0001', 'Date: 29-08-2026', 'Item: Fictional maintenance consumables', 'Amount: NGN 125,000.00', 'This document exists only to verify evidence rendering.'];
    foreach ($lines as $index => $line) imagestring($image, 5, 190, 500 + ($index * 140), $line, $index === 5 ? $grey : $ink);
    mt_srand(960829);
    for ($index = 0; $index < 160000; $index++) {
        $shade = mt_rand(210, 252);
        imagesetpixel($image, mt_rand(80, 1718), mt_rand(80, 2418), imagecolorallocate($image, $shade, $shade, $shade));
    }
    ob_start(); imagejpeg($image, null, 94); $bytes = (string)ob_get_clean(); imagedestroy($image);
    if (strlen($bytes) < 500000) throw new RuntimeException('REGRESSION_JPEG_NOT_REAL_SIZE');
    return $bytes;
}

function regression_receipt_pdf(): string {
    $pdf = new class('P', 'mm', 'A4', true, 'UTF-8', false) extends TCPDF { public function disableAttribution(): void { $this->tcpdflink = false; } };
    $pdf->disableAttribution(); $pdf->setPrintHeader(false); $pdf->setPrintFooter(false);
    for ($page = 1; $page <= 2; $page++) {
        $pdf->AddPage(); $pdf->SetTextColor(18, 18, 18); $pdf->SetDrawColor(75, 75, 75); $pdf->SetFont('dejavusans', 'B', 18);
        $pdf->Cell(0, 12, 'QA SAMPLE EVIDENCE - NOT PRODUCTION DATA', 0, 1, 'C');
        $pdf->SetFont('dejavusans', 'B', 13); $pdf->Cell(0, 10, 'Fictional multi-page receipt - page '.$page.' of 2', 0, 1, 'C');
        $pdf->Line(20, 42, 190, 42); $pdf->Ln(12); $pdf->SetFont('dejavusans', '', 11);
        $pdf->MultiCell(0, 8, "Supplier: Example Equipment Services (Fictional)\nEvidence reference: QA-PDF-0002\nDate: 29-08-2026\nLine item: Fictional service evidence page {$page}\nAmount: NGN 75,000.00\n\nThis page is synthetic and exists only to validate PDF evidence importing.");
    }
    return $pdf->Output('qa-evidence.pdf', 'S');
}

function regression_expenses(array $filters, string $source, string $prefix, int $count): array {
    $rows = [];
    $total = 0.0;
    for ($id = 1; $id <= $count; $id++) {
        $amount = number_format(12500 + (($id * 13750) % 185000), 2, '.', '');
        $total += (float)$amount;
        $rows[] = [
            'id' => $id, 'source_type' => $source, 'reference_no' => sprintf('%s%06d', $prefix, $id), 'expense_date' => '2026-08-29',
            'source_name' => $source === 'BANK' ? 'Zenith QA Operating Account' : 'Segun Adeyemi - QA Custodian', 'custodian_name' => 'Segun Adeyemi - QA Custodian',
            'supplier_paid_to' => $id % 4 === 0 ? 'Fictional Industrial Hydraulics and Engineering Services Limited' : 'Fictional QA Supplier '.$id,
            'description' => $id % 5 === 0 ? 'QA SAMPLE / NOT PRODUCTION DATA - emergency hydraulic hose, fittings and site maintenance consumables for uninterrupted mixer operations' : 'QA SAMPLE / NOT PRODUCTION DATA - operational expense '.$id,
            'client_name' => $id % 6 === 0 ? 'Fictional Long Client Name for Multi-Project Operations Limited' : 'Fictional QA Client',
            'project_name' => $id % 3 === 0 ? 'QA Sample High-Density Concrete Production Project - Phase Two' : 'QA Sample Project',
            'mixer_code' => 'MIXER-'.(300 + ($id % 8)), 'status' => 'APPROVED',
            'original_journal_reference' => sprintf('CEH-JRN-20260829%06d-%08X', $id, 0x8A098550 + $id), 'amount' => $amount, 'matched_amount' => $amount,
            'no_receipt_reason' => $id % 7 === 0 ? 'Fictional supplier could not issue a receipt; QA reason retained for long missing-evidence pagination coverage.' : '',
        ];
    }
    $decimal = number_format($total, 2, '.', '');
    return ['filters' => $filters, 'rows' => $rows, 'totals' => ['transaction_count' => $count, 'header_amount' => $decimal, 'matched_amount' => $decimal]];
}

function regression_staging_shape_expenses(array $filters): array {
    $sourceRows = [
        ['CEH-PC-000010', '27-08-2026', 'Felix', 'Site Expenses', 'ABC Construction', 'Epe', 'Not allocated', 'APPROVED', 'CEH-JRN-20260827134452-96AE2C59', '30000.00', 'Site Expense'],
        ['CEH-PC-000006', '24-08-2026', 'Not allocated', 'Victor to ilasa', 'Not allocated', 'Not allocated', 'Not allocated', 'DRAFT', '', '3000.00', 'none'],
        ['CEH-PC-000009', '24-08-2026', 'Victor', 'Transport to lekki', 'ABC Construction', 'Epe', '307', 'APPROVED', 'CEH-JRN-20260827134504-7DDD4FF6', '5000.00', 'none'],
        ['CEH-PC-000008', '24-08-2026', 'Victor', 'Victor to ilasa', 'Not allocated', 'Not allocated', 'Not allocated', 'SUBMITTED', '', '3000.00', 'none'],
        ['CEH-PC-000007', '24-08-2026', 'Not allocated', 'Victor to ilasa', 'Not allocated', 'Not allocated', 'Not allocated', 'DRAFT', '', '3000.00', 'none'],
        ['CEH-PC-000004', '23-08-2026', 'rain oil', '30 litres diesep', 'Not allocated', 'Not allocated', 'Not allocated', 'APPROVED', 'CEH-JRN-20260822234633-1AB721C8', '50000.00', 'none'],
        ['CEH-PC-000002', '22-08-2026', 'Vulcaniser', 'Repair of back tyre', 'ABC Construction', 'Epe', '307', 'APPROVED', 'CEH-JRN-20260822152759-A8AE8CEA', '10000.00', 'none'],
        ['CEH-PC-000001', '22-08-2026', 'Rain oil', 'for mixer', 'ABC Construction', 'Epe', '307', 'APPROVED', 'CEH-JRN-20260822124340-8A09855C', '40000.00', ''],
        ['Reference pending', '22-08-2026', 'CJ', '2 solenoids', 'ABC Construction', 'Epe', '307', 'APPROVED', 'CEH-JRN-20260822112812-D3175583', '100000.00', 'none'],
        ['Reference pending', '22-08-2026', 'CJ', '2 solenoids', 'ABC Construction', 'Epe', '307', 'VOIDED', 'CEH-JRN-20260822135719-2EE66C44', '130000.00', 'none'],
        ['Reference pending', '22-08-2026', 'Rain Oil', '25 litres', 'ABC Construction', 'Epe', '307', 'APPROVED', 'CEH-JRN-20260822112341-8DD10704', '30000.00', 'Test'],
    ];
    $rows = [];
    foreach ($sourceRows as $offset => $sourceRow) {
        [$reference, $date, $supplier, $description, $client, $project, $mixer, $status, $journal, $amount, $reason] = $sourceRow;
        $rows[] = [
            'id' => $offset + 1, 'source_type' => 'PETTY_CASH', 'reference_no' => $reference,
            'expense_date' => DateTimeImmutable::createFromFormat('d-m-Y', $date)->format('Y-m-d'),
            'source_name' => 'Segun', 'custodian_name' => 'Segun', 'supplier_paid_to' => $supplier,
            'description' => $description, 'client_name' => $client, 'project_name' => $project,
            'mixer_code' => $mixer, 'status' => $status, 'original_journal_reference' => $journal,
            'amount' => $amount, 'matched_amount' => $amount, 'no_receipt_reason' => $reason,
        ];
    }
    return ['filters' => $filters, 'rows' => $rows, 'totals' => ['transaction_count' => 11, 'header_amount' => '404000.00', 'matched_amount' => '404000.00']];
}

// Measured from the fresh staging PDF's rendered table rectangles. The natural
// allocation is 10+1; the production planner must rebalance it to 9+2 while
// retaining enough continuation-page capacity for the totals block.
$stagingRowHeights = [13.47, 7.47, 12.94, 7.47, 7.47, 12.94, 12.94, 12.94, 12.94, 12.94, 12.94];
$stagingNaturalPages = [range(0, 9), [10]];
$stagingBalancedPages = reports_pdf_balance_final_register_page($stagingNaturalPages, $stagingRowHeights, 167.0, 25.0);
if (array_map('count', $stagingNaturalPages) !== [10, 1] || array_map('count', $stagingBalancedPages) !== [9, 2]) {
    throw new RuntimeException('REGRESSION_STAGING_EXPLICIT_10_1_BALANCE_FAILED');
}
$stagingPlannedPages = reports_pdf_paginate_rows($stagingRowHeights, 116.0, 167.0, 25.0);
if (array_map('count', $stagingPlannedPages) !== [9, 2]) {
    throw new RuntimeException('REGRESSION_STAGING_SINGLETON_REGISTER_PAGE: '.json_encode(array_map('count', $stagingPlannedPages)));
}

$jpeg = regression_receipt_jpeg(); $evidencePdf = regression_receipt_pdf();
$evidence = static function(array $row) use ($jpeg, $evidencePdf): array {
    $id = (int)$row['id'];
    if ($id !== 1 && $id !== 2 && $id % 5 !== 0) return [];
    $bytes = $id === 2 ? $evidencePdf : $jpeg; $mime = $id === 2 ? 'application/pdf' : 'image/jpeg';
    return [['storage_driver' => 'MYSQL_BLOB', 'evidence_data' => $bytes, 'sha256' => hash('sha256', $bytes), 'mime_type' => $mime,
        'byte_size' => strlen($bytes), 'original_filename' => $id === 2 ? 'qa-sample-evidence-two-pages.pdf' : 'qa-real-size-sample-receipt.jpg']];
};
$pettyOne = regression_expenses($filters, 'PETTY_CASH', 'CEH-PC-', 1);
$pettyEleven = regression_expenses($filters, 'PETTY_CASH', 'CEH-PC-', 11);
$pettyDense = regression_expenses($filters, 'PETTY_CASH', 'CEH-PC-', 27);
$stagingShapeFilters = $filters;
unset($stagingShapeFilters['qa_notice']);
$stagingShapeFilters['date_from'] = '';
$stagingShapeFilters['date_to'] = '';
$pettyStagingShape = regression_staging_shape_expenses($stagingShapeFilters);
$stagingShapeEvidence = static function(array $row) use ($jpeg): array {
    if ((int)$row['id'] !== 8) return [];
    return [['storage_driver' => 'MYSQL_BLOB', 'evidence_data' => $jpeg, 'sha256' => hash('sha256', $jpeg), 'mime_type' => 'image/jpeg',
        'byte_size' => strlen($jpeg), 'original_filename' => 'qa-real-size-staging-shape-receipt.jpg']];
};
$full = regression_expenses($filters, 'BANK', 'CEH-EX-', 18);
$receivableRows = [];
$receivableOriginal = 0.0; $receivablePaid = 0.0; $receivableOutstanding = 0.0;
for ($id = 1; $id <= 18; $id++) {
    $original = 275000 + ($id * 48750); $paid = $id % 4 === 0 ? $original * 0.55 : $original * 0.2; $outstanding = $original - $paid;
    $receivableOriginal += $original; $receivablePaid += $paid; $receivableOutstanding += $outstanding;
    $days = $id * 7;
    $receivableRows[] = [
        'client_name_snapshot' => $id % 5 === 0 ? 'Fictional Long Client Name for Multi-Project Operations Limited' : 'Fictional QA Client '.(($id % 4) + 1),
        'reference' => sprintf('CEH-INV-%06d', $id), 'invoice_date' => '2026-08-01', 'due_date' => '2026-08-15',
        'original_amount' => number_format($original, 2, '.', ''), 'payments_credits_applied' => number_format($paid, 2, '.', ''),
        'outstanding' => number_format($outstanding, 2, '.', ''), 'days_overdue' => $days,
        'bucket' => $days <= 30 ? '1_30' : ($days <= 60 ? '31_60' : ($days <= 90 ? '61_90' : '90_PLUS')),
    ];
}
$receivables = ['filters' => $filters, 'invoices' => $receivableRows, 'totals' => [
    'invoice_count' => count($receivableRows), 'original_amount' => number_format($receivableOriginal, 2, '.', ''),
    'payments_credits_applied' => number_format($receivablePaid, 2, '.', ''), 'outstanding' => number_format($receivableOutstanding, 2, '.', ''),
]];

$pettyOneBytes = reports_pdf_expenses('Petty Cash Audit Pack', $pettyOne, true, $evidence, $company);
$pettyElevenBytes = reports_pdf_expenses('Petty Cash Audit Pack', $pettyEleven, true, $evidence, $company);
$pettyDenseBytes = reports_pdf_expenses('Petty Cash Audit Pack', $pettyDense, true, $evidence, $company);
$documents = [
    'QA REALISTIC - CEH Receivables Report - NOT PRODUCTION DATA.pdf' => reports_pdf_receivables($receivables, $company),
    'QA REALISTIC - CEH Petty Cash 1 Transaction - NOT PRODUCTION DATA.pdf' => $pettyOneBytes,
    'QA REALISTIC - CEH Petty Cash 11 Transactions - NOT PRODUCTION DATA.pdf' => $pettyElevenBytes,
    'QA REALISTIC - CEH Petty Cash 27 Transactions - NOT PRODUCTION DATA.pdf' => $pettyDenseBytes,
    'QA STAGING-SHAPE - CEH Petty Cash 11 Transactions - NOT PRODUCTION DATA.pdf' => reports_pdf_expenses('Petty Cash Audit Pack', $pettyStagingShape, true, $stagingShapeEvidence, $company),
    'QA REALISTIC - CEH Full Expense 18 Transactions - NOT PRODUCTION DATA.pdf' => reports_pdf_expenses('Full Expense Audit Pack', $full, true, $evidence, $company),
];
foreach ($documents as $name => $bytes) {
    if (!str_starts_with($bytes, '%PDF-') || substr_count($bytes, '/Subtype /Image') < 1) throw new RuntimeException('REGRESSION_PDF_OR_LOGO_MISSING: '.$name);
    if (str_contains($bytes, 'Powered by TCPDF')) throw new RuntimeException('REGRESSION_TCPDF_BRANDING_PRESENT: '.$name);
    file_put_contents($output.DIRECTORY_SEPARATOR.$name, $bytes);
}
file_put_contents($output.DIRECTORY_SEPARATOR.'QA SAMPLE RECEIPT - NOT PRODUCTION DATA.jpg', $jpeg);
file_put_contents($output.DIRECTORY_SEPARATOR.'QA SAMPLE EVIDENCE - NOT PRODUCTION DATA.pdf', $evidencePdf);
echo "REPORT_PDF_PRODUCTION_REGRESSION_OK\n";
