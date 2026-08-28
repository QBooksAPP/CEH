<?php
declare(strict_types=1);

require_once __DIR__ . '/billing_common.php';
require_once __DIR__ . '/production_report_common.php';
require_once __DIR__ . '/company_regional_common.php';

$user = billing_require_admin();
production_require_method('GET');
$id = (int)($_GET['invoice_id'] ?? 0);
if ($id <= 0) qbook_json(['ok' => false, 'error' => 'INVOICE_REQUIRED'], 422);

$db = production_db();
$statement = $db->prepare("SELECT * FROM qbook_invoices WHERE id=? AND status='ISSUED'");
$statement->execute([$id]);
$invoice = $statement->fetch();
if (!$invoice) qbook_json(['ok' => false, 'error' => 'ISSUED_INVOICE_NOT_FOUND'], 404);

// Issued PDFs are rendered exclusively from the invoice row. Never fall back
// to current Billing Settings for a historical issued invoice.
$snapshotFields = [
    'company_legal_name_snapshot',
    'company_address_snapshot',
    'tax_identifier_snapshot',
    'payment_bank_details_snapshot',
];
foreach ($snapshotFields as $field) {
    if (trim((string)($invoice[$field] ?? '')) === '') {
        qbook_json(['ok' => false, 'error' => 'INVOICE_SETTINGS_SNAPSHOT_MISSING'], 409);
    }
}
if (trim((string)($invoice['terms_snapshot'] ?? '')) === '') {
    qbook_json(['ok' => false, 'error' => 'INVOICE_TERMS_SNAPSHOT_MISSING'], 409);
}

$lineStatement = $db->prepare(
    'SELECT l.*,a.name revenue_account FROM qbook_invoice_lines l '
    . 'JOIN qbook_accounts_chart a ON a.id=l.revenue_account_id '
    . 'WHERE l.invoice_id=? ORDER BY line_no'
);
$lineStatement->execute([$id]);
$lines = $lineStatement->fetchAll();

try {
    if (!extension_loaded('zlib') || !extension_loaded('gd')) {
        throw new RuntimeException('PDF_ENGINE_UNAVAILABLE');
    }
    $cacheDirectory = production_report_cache_directory();
    $logoOriginal = @file_get_contents(__DIR__ . '/assets/ceh_logo.png');
    if (!is_string($logoOriginal) || $logoOriginal === '') {
        throw new RuntimeException('PDF_LOGO_UNREADABLE');
    }
    $logoPng = production_report_normalize_png($logoOriginal);
} catch (Throwable $exception) {
    if (isset($cacheDirectory)) production_report_cleanup_cache_directory($cacheDirectory);
    error_log('CEH Invoice PDF preparation failed type=' . get_class($exception));
    qbook_json(['ok' => false, 'error' => 'INVOICE_PDF_FAILED'], 500);
}

if (!defined('K_PATH_CACHE')) define('K_PATH_CACHE', $cacheDirectory);
require_once __DIR__ . '/vendor/tcpdf/tcpdf.php';

final class CehInvoicePdf extends TCPDF {
    public string $invoiceReference = '';

    public function disableTcpdfAttribution(): void {
        $this->tcpdflink = false;
    }

    public function embedLogo(string $png): void {
        $before = count($this->images);
        $this->Image('@' . $png, 15, 13, 48, 0, 'PNG');
        if (count($this->images) <= $before) {
            throw new RuntimeException('PDF_LOGO_EMBED_FAILED');
        }
    }

    public function Footer(): void {
        $this->SetY(-13);
        $this->SetDrawColor(190, 190, 190);
        $this->Line(15, $this->GetY(), 195, $this->GetY());
        $this->Ln(2.5);
        $this->SetFont('dejavusans', '', 7);
        $this->SetTextColor(90, 90, 90);
        $this->Cell(130, 5, $this->invoiceReference, 0, 0, 'L');
        $this->Cell(50, 5, 'Page ' . $this->getAliasNumPage() . ' of ' . $this->getAliasNbPages(), 0, 0, 'R');
    }
}

$reference = billing_ref('INVOICE', $invoice['reference_no']);
$currency = company_document_currency($invoice['currency_code_snapshot'] ?? null);
$money = static fn(mixed $value): string => company_money($value, $currency);
$date = static fn(string $value): string => (new DateTimeImmutable($value))->format('d-m-Y');
$unitFor = static function (array $line): string {
    $unit = trim((string)($line['unit_name'] ?? ''));
    $description = strtolower((string)$line['description']);
    if ($line['source_type'] === 'PRODUCTION_REPORT'
        || (($unit === '' || strtolower($unit) === 'unit')
            && (str_contains($description, 'concrete') || str_contains($description, 'batch')))) {
        return 'm³';
    }
    return $unit === '' ? 'unit' : $unit;
};

try {
    $pdf = new CehInvoicePdf('P', 'mm', 'A4', true, 'UTF-8', false);
    $pdf->invoiceReference = $reference;
    $pdf->disableTcpdfAttribution();
    $pdf->SetCreator((string)$invoice['company_legal_name_snapshot']);
    $pdf->SetAuthor((string)$invoice['company_legal_name_snapshot']);
    $pdf->SetTitle($reference . ' Invoice');
    $pdf->SetPrintHeader(false);
    $pdf->SetPrintFooter(true);
    $pdf->SetMargins(15, 13, 15);
    $pdf->SetAutoPageBreak(true, 18);
    $pdf->setCellPaddings(1.8, 1.2, 1.8, 1.2);
    $pdf->setFontSubsetting(true);
    $pdf->AddPage();

    // Approved CEH customer-document palette, derived from the monochrome logo.
    $ink = [20, 20, 20];
    $primary = [18, 18, 18];
    $secondary = [75, 75, 75];
    $border = [190, 190, 190];
    $pale = [245, 245, 245];
    $background = [250, 250, 250];
    $white = [255, 255, 255];
    $pdf->SetTextColor(...$ink);
    $pdf->SetDrawColor(...$border);

    $pdf->embedLogo($logoPng);
    $pdf->SetXY(82, 13);
    $pdf->SetFont('dejavusans', 'B', 11);
    $pdf->SetTextColor(...$ink);
    $pdf->MultiCell(113, 5.6, (string)$invoice['company_legal_name_snapshot'], 0, 'R', false, 1);
    $pdf->SetX(90);
    $pdf->SetFont('dejavusans', '', 8);
    $pdf->SetTextColor(...$secondary);
    $pdf->MultiCell(105, 4.3, (string)$invoice['company_address_snapshot'], 0, 'R', false, 1);
    $pdf->SetX(90);
    $pdf->MultiCell(105, 4.3, 'TIN: ' . (string)$invoice['tax_identifier_snapshot'], 0, 'R', false, 1);

    $headerBottom = max(35.0, $pdf->GetY() + 2.0);
    $pdf->SetDrawColor(...$primary);
    $pdf->SetLineWidth(0.7);
    $pdf->Line(15, $headerBottom, 195, $headerBottom);
    $pdf->SetY($headerBottom + 6);

    $pdf->SetFont('dejavusans', 'B', 18);
    $pdf->SetTextColor(...$primary);
    $pdf->Cell(105, 9, 'INVOICE', 0, 0, 'L');
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->SetTextColor(...$secondary);
    $pdf->Cell(75, 9, $reference, 0, 1, 'R');
    $pdf->SetFont('dejavusans', '', 8);
    $pdf->Cell(105, 5, 'Tax invoice', 0, 0, 'L');
    $pdf->Cell(75, 5, 'Invoice date: ' . $date((string)$invoice['invoice_date']), 0, 1, 'R');
    $pdf->Ln(5);

    $meta = [
        ['Bill To', (string)$invoice['client_name_snapshot']],
        ['Invoice Date', $date((string)$invoice['invoice_date'])],
        ['Payment Terms', ucwords(strtolower(str_replace('_', ' ', (string)$invoice['payment_term'])))],
    ];
    if ($invoice['due_date']) $meta[] = ['Due Date', $date((string)$invoice['due_date'])];
    $panelY = $pdf->GetY();
    $rowY = $panelY + 3;
    foreach ($meta as [$unused, $value]) $rowY += max(6.0, $pdf->getStringHeight(134, $value) + 1);
    $panelHeight = max(24.0, $rowY - $panelY + 2);
    $pdf->SetFillColor(...$pale);
    $pdf->SetDrawColor(...$border);
    $pdf->RoundedRect(15, $panelY, 180, $panelHeight, 2, '1111', 'DF');
    $rowY = $panelY + 3;
    foreach ($meta as [$label, $value]) {
        $pdf->SetXY(20, $rowY);
        $pdf->SetFont('dejavusans', 'B', 7.5);
        $pdf->SetTextColor(...$secondary);
        $pdf->Cell(34, 5, strtoupper($label), 0, 0, 'L');
        $pdf->SetFont('dejavusans', '', 9);
        $pdf->SetTextColor(...$ink);
        $pdf->MultiCell(134, 5, $value, 0, 'L', false, 1);
        $rowY = max($rowY + 6, $pdf->GetY());
    }
    $pdf->SetY($panelY + $panelHeight + 5);

    $columns = [
        ['DESCRIPTION / PROJECT', 65, 'L'], ['QUANTITY', 24, 'R'], ['RATE', 31, 'R'],
        ['NET', 30, 'R'], ['VAT', 30, 'R'],
    ];
    $drawTableHeader = static function (CehInvoicePdf $document) use ($columns, $primary, $white): void {
        $document->SetFillColor(...$primary);
        $document->SetTextColor(...$white);
        $document->SetFont('dejavusans', 'B', 7.2);
        foreach ($columns as [$label, $width, $align]) $document->Cell($width, 8, $label, 0, 0, $align, true);
        $document->Ln();
    };
    $pdf->SetTextColor(...$ink);
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->Cell(180, 7, 'Invoice lines', 0, 1, 'L');
    $drawTableHeader($pdf);

    foreach ($lines as $index => $line) {
        $description = (string)$line['description'];
        if (trim((string)($line['project_snapshot'] ?? '')) !== '') {
            $description .= "\nProject: " . (string)$line['project_snapshot'];
        }
        if (trim((string)($line['mixer_snapshot'] ?? '')) !== '') {
            $description .= "\nEquipment: " . (string)$line['mixer_snapshot'];
        }
        $quantity = $line['quantity'] === null
            ? '—'
            : number_format((float)$line['quantity'], 2) . ' ' . $unitFor($line);
        $rate = $line['unit_price'] === null ? '—' : $money($line['unit_price']);
        $values = [$description, $quantity, $rate, $money($line['net_amount']), $money($line['vat_amount'])];
        $rowHeight = 10.0;
        foreach ($values as $cellIndex => $value) {
            $rowHeight = max($rowHeight, $pdf->getStringHeight($columns[$cellIndex][1] - 3, $value) + 3.5);
        }
        if ($pdf->GetY() + $rowHeight > 242) {
            $pdf->AddPage();
            $pdf->SetTextColor(...$ink);
            $pdf->SetFont('dejavusans', 'B', 10);
            $pdf->Cell(180, 7, 'Invoice lines (continued)', 0, 1, 'L');
            $drawTableHeader($pdf);
        }
        $fill = $index % 2 === 1;
        if ($fill) $pdf->SetFillColor(...$background);
        $pdf->SetDrawColor(...$border);
        $pdf->SetTextColor(...$ink);
        $pdf->SetFont('dejavusans', '', 7.6);
        foreach ($values as $cellIndex => $value) {
            [$unused, $width, $align] = $columns[$cellIndex];
            $pdf->MultiCell($width, $rowHeight, $value, 1, $align, $fill, ($cellIndex === count($values) - 1 ? 1 : 0), '', '', true, 0, false, true, $rowHeight, 'M');
        }
    }

    $vatLabel = 'VAT ' . billing_format_percent($invoice['vat_rate_snapshot'] ?? 0);
    $totals = [['Net', $invoice['net_amount']], [$vatLabel, $invoice['vat_amount']], ['TOTAL', $invoice['total_amount']]];
    if ($pdf->GetY() + 38 > 265) $pdf->AddPage();
    $pdf->Ln(6);
    $pdf->SetX(95);
    $pdf->SetFont('dejavusans', 'B', 9);
    $pdf->SetTextColor(...$primary);
    $pdf->Cell(100, 6, 'Invoice summary', 0, 1, 'L');
    foreach ($totals as [$label, $amount]) {
        $highlight = $label === 'TOTAL';
        $pdf->SetX(95);
        $pdf->SetFillColor(...($highlight ? $pale : $white));
        $pdf->SetFont('dejavusans', $highlight ? 'B' : '', 8.7);
        $pdf->SetTextColor(...($highlight ? $primary : $ink));
        $pdf->Cell(63, 7, $label, $highlight ? 'TB' : 'B', 0, 'L', $highlight);
        $pdf->Cell(37, 7, $money($amount), $highlight ? 'TB' : 'B', 1, 'R', $highlight);
    }

    $paymentDetails = trim((string)$invoice['payment_bank_details_snapshot']);
    $paymentHeight = max(12.0, $pdf->getStringHeight(176, $paymentDetails) + 5);
    $terms = trim((string)$invoice['terms_snapshot']);
    $termsHeight = max(12.0, $pdf->getStringHeight(176, $terms) + 5);
    if ($pdf->GetY() + $paymentHeight + $termsHeight + 29 > 265) $pdf->AddPage();
    $pdf->Ln(6);
    $pdf->SetTextColor(...$primary);
    $pdf->SetFont('dejavusans', 'B', 9);
    $pdf->Cell(0, 6, 'PAYMENT DETAILS', 0, 1);
    $pdf->SetFillColor(...$pale);
    $pdf->SetDrawColor(...$border);
    $pdf->SetTextColor(...$ink);
    $pdf->SetFont('dejavusans', '', 8.5);
    $pdf->MultiCell(180, 5, $paymentDetails, 1, 'L', true, 1);
    $pdf->Ln(6);
    $pdf->SetTextColor(...$primary);
    $pdf->SetFont('dejavusans', 'B', 9);
    $pdf->Cell(0, 5, 'TERMS', 0, 1);
    $pdf->SetFillColor(...$pale);
    $pdf->SetDrawColor(...$border);
    $pdf->SetTextColor(...$ink);
    $pdf->SetFont('dejavusans', '', 8.5);
    $pdf->MultiCell(180, 5, $terms, 1, 'L', true, 1);

    $bytes = $pdf->Output($reference . '.pdf', 'S');
    unset($pdf);
    production_report_cleanup_cache_directory($cacheDirectory);
    if (substr_count($bytes, '/Subtype /Image') < 1) {
        throw new RuntimeException('PDF_LOGO_MISSING');
    }
    production_discard_output();
    header('Content-Type: application/pdf');
    header('Content-Length: ' . strlen($bytes));
    header('Content-Disposition: attachment; filename="' . $reference . '.pdf"');
    header('Cache-Control: private, no-store, no-cache, must-revalidate');
    header('X-Content-Type-Options: nosniff');
    echo $bytes;
    exit;
} catch (Throwable $exception) {
    if (isset($pdf)) unset($pdf);
    if (isset($cacheDirectory)) production_report_cleanup_cache_directory($cacheDirectory);
    error_log('CEH Invoice PDF generation failed type=' . get_class($exception));
    qbook_json(['ok' => false, 'error' => 'INVOICE_PDF_FAILED'], 500);
}
