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
        $this->Image('@' . $png, 15, 12, 65, 0, 'PNG');
        if (count($this->images) <= $before) {
            throw new RuntimeException('PDF_LOGO_EMBED_FAILED');
        }
    }

    public function Footer(): void {
        $this->SetY(-14);
        $this->SetDrawColor(165, 165, 165);
        $this->SetLineWidth(0.2);
        $this->Line(15, $this->GetY(), 195, $this->GetY());
        $this->Ln(1.5);
        $this->SetFont('dejavusans', '', 7.5);
        $this->SetTextColor(89, 89, 89);
        $this->Cell(
            0,
            7,
            $this->invoiceReference . '  |  Page ' . $this->getAliasNumPage() . '/' . $this->getAliasNbPages(),
            0,
            0,
            'C'
        );
    }
}

$reference = billing_ref('INVOICE', $invoice['reference_no']);
$money = static fn(mixed $value): string => '₦' . number_format((float)$value, 2);
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
    $pdf->SetAutoPageBreak(true, 22);
    $pdf->setFontSubsetting(true);
    $pdf->AddPage();

    $black = [0, 0, 0];
    $darkGray = [89, 89, 89];
    $midGray = [165, 165, 165];
    $lightGray = [244, 244, 244];
    $white = [255, 255, 255];

    $pdf->embedLogo($logoPng);
    $pdf->SetXY(86, 12);
    $pdf->SetFont('dejavusans', 'B', 11);
    $pdf->SetTextColor(...$black);
    $pdf->MultiCell(109, 6, (string)$invoice['company_legal_name_snapshot'], 0, 'R', false, 1);
    $pdf->SetX(86);
    $pdf->SetFont('dejavusans', '', 8);
    $pdf->SetTextColor(...$darkGray);
    $pdf->MultiCell(109, 4.5, (string)$invoice['company_address_snapshot'], 0, 'R', false, 1);
    $pdf->SetX(86);
    $pdf->MultiCell(109, 4.5, 'TIN: ' . (string)$invoice['tax_identifier_snapshot'], 0, 'R', false, 1);

    $headerBottom = max(39.0, $pdf->GetY() + 2.0);
    $pdf->SetDrawColor(...$black);
    $pdf->SetLineWidth(0.55);
    $pdf->Line(15, $headerBottom, 195, $headerBottom);
    $pdf->SetY($headerBottom + 6);

    $pdf->SetFont('dejavusans', 'B', 22);
    $pdf->SetTextColor(...$black);
    $pdf->Cell(95, 10, 'INVOICE', 0, 0, 'L');
    $pdf->SetFont('dejavusans', 'B', 11);
    $pdf->Cell(85, 10, $reference, 0, 1, 'R');
    $pdf->Ln(3);

    $meta = [
        ['BILL TO', (string)$invoice['client_name_snapshot']],
        ['INVOICE DATE', $date((string)$invoice['invoice_date'])],
        ['PAYMENT TERMS', str_replace('_', ' ', (string)$invoice['payment_term'])],
    ];
    if ($invoice['due_date']) $meta[] = ['DUE DATE', $date((string)$invoice['due_date'])];
    foreach ($meta as [$label, $value]) {
        $pdf->SetFont('dejavusans', 'B', 7.5);
        $pdf->SetTextColor(...$darkGray);
        $pdf->Cell(38, 6, $label, 0, 0);
        $pdf->SetFont('dejavusans', '', 9);
        $pdf->SetTextColor(...$black);
        $pdf->MultiCell(142, 6, $value, 0, 'L', false, 1);
    }
    $pdf->Ln(6);

    $drawTableHeader = static function (CehInvoicePdf $document) use ($black, $white): void {
        $document->SetFillColor(...$black);
        $document->SetDrawColor(...$black);
        $document->SetTextColor(...$white);
        $document->SetFont('dejavusans', 'B', 8);
        $document->Cell(70, 8, 'DESCRIPTION', 1, 0, 'L', true);
        $document->Cell(25, 8, 'QUANTITY', 1, 0, 'R', true);
        $document->Cell(30, 8, 'RATE', 1, 0, 'R', true);
        $document->Cell(30, 8, 'NET', 1, 0, 'R', true);
        $document->Cell(25, 8, 'VAT', 1, 1, 'R', true);
    };
    $drawTableHeader($pdf);

    foreach ($lines as $line) {
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
        $rowHeight = max(9.0, $pdf->getStringHeight(70, $description) + 3.0);
        if ($pdf->GetY() + $rowHeight > 258) {
            $pdf->AddPage();
            $drawTableHeader($pdf);
        }
        $x = $pdf->GetX();
        $y = $pdf->GetY();
        $pdf->SetDrawColor(...$midGray);
        $pdf->SetTextColor(...$black);
        $pdf->SetFont('dejavusans', '', 8);
        $pdf->MultiCell(70, $rowHeight, $description, 1, 'L', false, 0, $x, $y, true, 0, false, true, $rowHeight, 'M');
        $pdf->MultiCell(25, $rowHeight, $quantity, 1, 'R', false, 0, $x + 70, $y, true, 0, false, true, $rowHeight, 'M');
        $pdf->MultiCell(30, $rowHeight, $rate, 1, 'R', false, 0, $x + 95, $y, true, 0, false, true, $rowHeight, 'M');
        $pdf->MultiCell(30, $rowHeight, $money($line['net_amount']), 1, 'R', false, 0, $x + 125, $y, true, 0, false, true, $rowHeight, 'M');
        $pdf->MultiCell(25, $rowHeight, $money($line['vat_amount']), 1, 'R', false, 0, $x + 155, $y, true, 0, false, true, $rowHeight, 'M');
        $pdf->SetXY(15, $y + $rowHeight);
    }

    $pdf->Ln(5);
    if ($pdf->GetY() > 221) $pdf->AddPage();
    $pdf->SetX(118);
    $pdf->SetFillColor(...$lightGray);
    $pdf->SetTextColor(...$black);
    $pdf->SetFont('dejavusans', '', 9);
    $pdf->Cell(39, 8, 'Net', 0, 0, 'L', true);
    $pdf->Cell(38, 8, $money($invoice['net_amount']), 0, 1, 'R', true);
    $pdf->SetX(118);
    $vatLabel = 'VAT ' . billing_format_percent($invoice['vat_rate_snapshot'] ?? 0);
    $pdf->Cell(39, 8, $vatLabel, 0, 0, 'L', true);
    $pdf->Cell(38, 8, $money($invoice['vat_amount']), 0, 1, 'R', true);
    $pdf->SetX(118);
    $pdf->SetFillColor(...$black);
    $pdf->SetTextColor(...$white);
    $pdf->SetFont('dejavusans', 'B', 12);
    $pdf->Cell(39, 11, 'TOTAL', 0, 0, 'L', true);
    $pdf->Cell(38, 11, $money($invoice['total_amount']), 0, 1, 'R', true);

    $pdf->Ln(8);
    if ($pdf->GetY() > 225) $pdf->AddPage();
    $pdf->SetTextColor(...$black);
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->Cell(0, 6, 'PAYMENT DETAILS', 0, 1);
    $pdf->SetDrawColor(...$midGray);
    $pdf->Line(15, $pdf->GetY(), 195, $pdf->GetY());
    $pdf->Ln(3);
    $pdf->SetFont('dejavusans', '', 8.5);
    $pdf->MultiCell(180, 5, (string)$invoice['payment_bank_details_snapshot'], 0, 'L', false, 1);
    $pdf->Ln(5);
    $pdf->SetFont('dejavusans', 'B', 9);
    $pdf->Cell(0, 5, 'TERMS', 0, 1);
    $pdf->SetFont('dejavusans', '', 8.5);
    $pdf->MultiCell(180, 5, (string)$invoice['terms_snapshot'], 0, 'L', false, 1);

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
