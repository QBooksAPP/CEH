<?php
declare(strict_types=1);

// Technical production-equivalent regression. These are explicit QA fixtures.
$repository = dirname(__DIR__);
$output = $argv[1] ?? sys_get_temp_dir().DIRECTORY_SEPARATOR.'ceh-report-regression';
if (!is_dir($output) && !mkdir($output, 0700, true) && !is_dir($output)) throw new RuntimeException('REGRESSION_OUTPUT_UNAVAILABLE');
chdir($output);
require_once $repository.DIRECTORY_SEPARATOR.'Server'.DIRECTORY_SEPARATOR.'report_pdf_common.php';

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
    $image = imagecreatetruecolor(900, 1250);
    $white = imagecolorallocate($image, 255, 255, 255); $ink = imagecolorallocate($image, 18, 18, 18); $grey = imagecolorallocate($image, 75, 75, 75);
    imagefill($image, 0, 0, $white); imagerectangle($image, 35, 35, 864, 1214, $ink);
    imagestring($image, 5, 285, 85, 'QA SAMPLE RECEIPT', $ink); imagestring($image, 5, 275, 125, 'NOT PRODUCTION DATA', $ink);
    imageline($image, 85, 180, 815, 180, $grey);
    $lines = ['Supplier: Example Industrial Supplies (Fictional)', 'Receipt: QA-RECEIPT-0001', 'Date: 29-08-2026', 'Item: Fictional maintenance consumables', 'Amount: NGN 125,000.00', 'This document exists only to verify evidence rendering.'];
    foreach ($lines as $index => $line) imagestring($image, 5, 95, 250 + ($index * 70), $line, $index === 5 ? $grey : $ink);
    ob_start(); imagejpeg($image, null, 92); $bytes = (string)ob_get_clean(); imagedestroy($image); return $bytes;
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

function regression_expenses(array $filters, string $source, string $prefix): array {
    $rows = [];
    foreach ([1 => '125000.00', 2 => '75000.00', 3 => '50000.00'] as $id => $amount) {
        $rows[] = [
            'id' => $id, 'source_type' => $source, 'reference_no' => sprintf('%s%06d', $prefix, $id), 'expense_date' => '2026-08-29',
            'source_name' => $source === 'BANK' ? 'QA Sample Bank' : 'QA Sample Petty Cash', 'custodian_name' => 'QA Sample Custodian',
            'supplier_paid_to' => 'Fictional QA Supplier '.$id, 'description' => 'QA SAMPLE / NOT PRODUCTION DATA - evidence scenario '.$id,
            'client_name' => 'Fictional QA Client', 'project_name' => 'QA Sample Project', 'mixer_code' => 'QA-MX-01', 'status' => 'APPROVED',
            'original_journal_reference' => sprintf('QA-JRN-%06d', $id), 'amount' => $amount, 'matched_amount' => $amount,
            'no_receipt_reason' => $id === 3 ? 'QA sample: fictional supplier issued no receipt.' : '',
        ];
    }
    return ['filters' => $filters, 'rows' => $rows, 'totals' => ['transaction_count' => 3, 'header_amount' => '250000.00', 'matched_amount' => '250000.00']];
}

$jpeg = regression_receipt_jpeg(); $evidencePdf = regression_receipt_pdf();
$evidence = static function(array $row) use ($jpeg, $evidencePdf): array {
    if ((int)$row['id'] === 3) return [];
    $bytes = (int)$row['id'] === 1 ? $jpeg : $evidencePdf; $mime = (int)$row['id'] === 1 ? 'image/jpeg' : 'application/pdf';
    return [['storage_driver' => 'MYSQL_BLOB', 'evidence_data' => $bytes, 'sha256' => hash('sha256', $bytes), 'mime_type' => $mime,
        'byte_size' => strlen($bytes), 'original_filename' => (int)$row['id'] === 1 ? 'qa-sample-receipt.jpg' : 'qa-sample-evidence-two-pages.pdf']];
};
$petty = regression_expenses($filters, 'PETTY_CASH', 'CEH-PC-'); $full = regression_expenses($filters, 'BANK', 'CEH-EX-');
$receivables = ['filters' => $filters, 'invoices' => [[
    'client_name_snapshot' => 'Fictional QA Client', 'reference' => 'QA-INV-000001', 'invoice_date' => '2026-08-01', 'due_date' => '2026-08-15',
    'original_amount' => '1798040.00', 'payments_credits_applied' => '0.00', 'outstanding' => '1798040.00', 'days_overdue' => 14, 'bucket' => '1_30',
]], 'totals' => ['invoice_count' => 1, 'original_amount' => '1798040.00', 'payments_credits_applied' => '0.00', 'outstanding' => '1798040.00']];

$pettyBytes = reports_pdf_expenses('Petty Cash Audit Pack', $petty, true, $evidence, $company);
$documents = [
    'QA SAMPLE - CEH Receivables Report - NOT PRODUCTION DATA.pdf' => reports_pdf_receivables($receivables, $company),
    'QA SAMPLE - CEH Petty Cash Audit Pack - NOT PRODUCTION DATA.pdf' => $pettyBytes,
    'QA SAMPLE - CEH Full Expense Audit Pack - NOT PRODUCTION DATA.pdf' => reports_pdf_expenses('Full Expense Audit Pack', $full, true, $evidence, $company),
    'QA SAMPLE - Multi-page Evidence Audit Pack - NOT PRODUCTION DATA.pdf' => $pettyBytes,
];
foreach ($documents as $name => $bytes) {
    if (!str_starts_with($bytes, '%PDF-') || substr_count($bytes, '/Subtype /Image') < 1) throw new RuntimeException('REGRESSION_PDF_OR_LOGO_MISSING: '.$name);
    if (str_contains($bytes, 'Powered by TCPDF')) throw new RuntimeException('REGRESSION_TCPDF_BRANDING_PRESENT: '.$name);
    file_put_contents($output.DIRECTORY_SEPARATOR.$name, $bytes);
}
file_put_contents($output.DIRECTORY_SEPARATOR.'QA SAMPLE RECEIPT - NOT PRODUCTION DATA.jpg', $jpeg);
file_put_contents($output.DIRECTORY_SEPARATOR.'QA SAMPLE EVIDENCE - NOT PRODUCTION DATA.pdf', $evidencePdf);
echo "REPORT_PDF_PRODUCTION_REGRESSION_OK\n";
