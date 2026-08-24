<?php
declare(strict_types=1);

require_once __DIR__ . '/billing_common.php';
require_once __DIR__ . '/production_report_common.php';

$user = billing_require_admin();
production_require_method('GET');
$id = (int)($_GET['invoice_id'] ?? 0);
if ($id <= 0) qbook_json(['ok' => false, 'error' => 'INVOICE_REQUIRED'], 422);

$db = production_db();
$statement = $db->prepare("SELECT * FROM qbook_invoices WHERE id=? AND status='ISSUED'");
$statement->execute([$id]);
$invoice = $statement->fetch();
if (!$invoice) qbook_json(['ok' => false, 'error' => 'ISSUED_INVOICE_NOT_FOUND'], 404);

$lineStatement = $db->prepare(
    'SELECT l.*,a.name revenue_account FROM qbook_invoice_lines l '
    . 'JOIN qbook_accounts_chart a ON a.id=l.revenue_account_id '
    . 'WHERE l.invoice_id=? ORDER BY line_no'
);
$lineStatement->execute([$id]);
$lines = $lineStatement->fetchAll();
$settings = $db->query('SELECT * FROM qbook_invoice_settings WHERE id=1')->fetch();

$requiredSettings = [
    'company_legal_name' => 'Company Legal Name',
    'company_address' => 'Company Address',
    'tax_identifier' => 'Tax Identifier / TIN',
    'payment_bank_details' => 'Payment Bank Details',
];
$missingSettings = [];
foreach ($requiredSettings as $field => $label) {
    if (trim((string)($settings[$field] ?? '')) === '') $missingSettings[] = $label;
}
if ($missingSettings !== []) {
    qbook_json(['ok' => false, 'error' => 'INVOICE_SETTINGS_INCOMPLETE', 'missing' => $missingSettings], 409);
}

$cache = production_report_cache_directory();
if (!defined('K_PATH_CACHE')) define('K_PATH_CACHE', $cache);
require_once __DIR__ . '/vendor/tcpdf/tcpdf.php';

$reference = billing_ref('INVOICE', $invoice['reference_no']);
$pdf = new TCPDF('P', 'mm', 'A4', true, 'UTF-8', false);
$pdf->SetCreator('CEH Accounts');
$pdf->SetTitle($reference);
$pdf->SetPrintHeader(false);
$pdf->SetPrintFooter(false);
$pdf->SetMargins(15, 15, 15);
$pdf->AddPage();
$pdf->SetFont('dejavusans', 'B', 18);
$pdf->Cell(0, 10, (string)$settings['company_legal_name'], 0, 1);
$pdf->SetFont('dejavusans', '', 9);
$pdf->MultiCell(0, 6, (string)$settings['company_address'], 0, 'L');
$pdf->Cell(0, 6, 'TIN: ' . (string)$settings['tax_identifier'], 0, 1);
$pdf->Ln(5);
$pdf->SetFont('dejavusans', 'B', 16);
$pdf->Cell(0, 9, 'INVOICE ' . $reference, 0, 1, 'R');
$pdf->SetFont('dejavusans', '', 10);
$pdf->Cell(0, 6, 'Client: ' . $invoice['client_name_snapshot'], 0, 1);
$pdf->Cell(0, 6, 'Invoice date: ' . date('d-m-Y', strtotime((string)$invoice['invoice_date'])), 0, 1);
$pdf->Cell(0, 6, 'Terms: ' . ($invoice['terms_snapshot'] ?: $invoice['payment_term']), 0, 1);
if ($invoice['due_date']) $pdf->Cell(0, 6, 'Due date: ' . date('d-m-Y', strtotime((string)$invoice['due_date'])), 0, 1);
$pdf->Ln(4);
$pdf->SetFont('dejavusans', 'B', 8);
$pdf->Cell(10, 7, '#', 1);
$pdf->Cell(64, 7, 'Description', 1);
$pdf->Cell(25, 7, 'Quantity', 1, 0, 'R');
$pdf->Cell(27, 7, 'Rate', 1, 0, 'R');
$pdf->Cell(27, 7, 'Net', 1, 0, 'R');
$pdf->Cell(27, 7, 'VAT', 1, 1, 'R');
$pdf->SetFont('dejavusans', '', 8);
foreach ($lines as $line) {
    $unit = trim((string)($line['unit_name'] ?? ''));
    $description = (string)$line['description'];
    if ($line['source_type'] === 'PRODUCTION_REPORT' || (($unit === '' || strtolower($unit) === 'unit') && (stripos($description, 'concrete') !== false || stripos($description, 'batch') !== false))) $unit = 'm³';
    if ($unit === '') $unit = 'unit';
    $quantity = $line['quantity'] === null ? '—' : number_format((float)$line['quantity'], 2) . ' ' . $unit;
    $rate = $line['unit_price'] === null ? '—' : number_format((float)$line['unit_price'], 2);
    $pdf->Cell(10, 7, (string)$line['line_no'], 1);
    $pdf->Cell(64, 7, $description, 1);
    $pdf->Cell(25, 7, $quantity, 1, 0, 'R');
    $pdf->Cell(27, 7, $rate, 1, 0, 'R');
    $pdf->Cell(27, 7, number_format((float)$line['net_amount'], 2), 1, 0, 'R');
    $pdf->Cell(27, 7, number_format((float)$line['vat_amount'], 2), 1, 1, 'R');
}
$pdf->Ln(3);
$pdf->SetFont('dejavusans', 'B', 10);
$pdf->Cell(0, 6, 'Net: NGN ' . number_format((float)$invoice['net_amount'], 2), 0, 1, 'R');
$pdf->Cell(0, 6, 'VAT (' . billing_format_percent($invoice['vat_rate_snapshot'] ?? 0) . '): NGN ' . number_format((float)$invoice['vat_amount'], 2), 0, 1, 'R');
$pdf->Cell(0, 7, 'TOTAL: NGN ' . number_format((float)$invoice['total_amount'], 2), 0, 1, 'R');
$pdf->Ln(8);
$pdf->SetFont('dejavusans', '', 8);
$pdf->MultiCell(0, 6, (string)$settings['payment_bank_details'], 0, 'L');

$bytes = $pdf->Output($reference . '.pdf', 'S');
production_discard_output();
header('Content-Type: application/pdf');
header('Content-Length: ' . strlen($bytes));
header('Content-Disposition: attachment; filename="' . $reference . '.pdf"');
header('Cache-Control: private, no-store');
header('X-Content-Type-Options: nosniff');
echo $bytes;
exit;
