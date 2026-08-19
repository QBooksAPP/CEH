<?php
declare(strict_types=1);

require_once __DIR__ . '/production_report_common.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
production_require_method('GET');
$sessionId = (int)($_GET['session_id'] ?? 0);
if ($sessionId <= 0) qbook_json(['ok' => false, 'error' => 'PRODUCTION_SESSION_REQUIRED'], 422);

// CEH renders only local/inline resources. zlib is required for compressed PDF
// streams, and GD is required to validate and normalize the required PNGs.
// Optional TCPDF remote-resource support is unused.
try {
    if (!extension_loaded('zlib') || !extension_loaded('gd')) {
        throw new RuntimeException('PDF_ENGINE_UNAVAILABLE');
    }
    $cacheDirectory = production_report_cache_directory();
} catch (Throwable $exception) {
    production_report_fail($user, $exception);
}
if (!defined('K_PATH_CACHE')) define('K_PATH_CACHE', $cacheDirectory);
require_once __DIR__ . '/vendor/tcpdf/tcpdf.php';

final class CehProductionReportPdf extends TCPDF {
    public string $reportReference = '';

    public function disableTcpdfAttribution(): void {
        $this->tcpdflink = false;
    }

    public function embedRequiredPng(
        string $png,
        float $x,
        float $y,
        float $width,
        float $height = 0
    ): void {
        $before = count($this->images);
        $this->Image('@' . $png, $x, $y, $width, $height, 'PNG');
        if (count($this->images) <= $before) {
            throw new RuntimeException('PDF_IMAGE_EMBED_FAILED');
        }
    }

    public function Footer(): void {
        $this->SetY(-14);
        $this->SetDrawColor(89, 89, 89);
        $this->SetLineWidth(0.25);
        $this->Line(15, $this->GetY(), 195, $this->GetY());
        $this->Ln(1.5);
        $this->SetFont('dejavusans', '', 8);
        $this->SetTextColor(89, 89, 89);
        $this->Cell(
            0,
            8,
            $this->reportReference . '  |  Page ' . $this->getAliasNumPage() . '/' . $this->getAliasNbPages(),
            0,
            0,
            'C'
        );
    }
}

$db = production_db();
try {
    $db->beginTransaction();
    $session = production_session_row($db, $sessionId, true);
    if (!production_can_access($user, $session)) {
        $db->rollBack();
        qbook_json(['ok' => false, 'error' => 'FORBIDDEN'], 403);
    }
    if ((string)$session['status'] !== 'SIGNED') {
        $db->rollBack();
        qbook_json(['ok' => false, 'error' => 'SIGNED_SESSION_REQUIRED'], 409);
    }

    $stmt = $db->prepare(
        "SELECT representative_name, signature_mime, signature_data,
                signature_sha256, load_count, total_m3, signed_at
         FROM qbook_production_signoffs
         WHERE production_session_id = ?
         LIMIT 1"
    );
    $stmt->execute([$sessionId]);
    $signoff = $stmt->fetch();
    if (!$signoff || (string)$signoff['signature_mime'] !== 'image/png') {
        throw new RuntimeException('PDF_SIGNATURE_MISSING');
    }
    try {
        $signatureOriginal = production_report_blob_bytes($signoff['signature_data']);
    } catch (Throwable) {
        throw new RuntimeException('PDF_SIGNATURE_MISSING');
    }
    if (!hash_equals((string)$signoff['signature_sha256'], hash('sha256', $signatureOriginal))) {
        throw new RuntimeException('PDF_SIGNATURE_HASH_MISMATCH');
    }

    $report = production_report_issue($db, $sessionId);
    $loads = production_loads($db, $sessionId);
    $db->commit();

    $reference = $report['reference'];
    $logoPath = __DIR__ . '/assets/ceh_logo.png';
    $logoOriginal = @file_get_contents($logoPath);
    if (!is_string($logoOriginal) || $logoOriginal === '') {
        throw new RuntimeException('PDF_LOGO_UNREADABLE');
    }
    try {
        $logoPng = production_report_normalize_png($logoOriginal);
    } catch (Throwable) {
        throw new RuntimeException('PDF_LOGO_INVALID');
    }
    try {
        $signaturePng = production_report_normalize_png($signatureOriginal);
    } catch (Throwable) {
        throw new RuntimeException('PDF_SIGNATURE_INVALID');
    }
    $pdf = new CehProductionReportPdf('P', 'mm', 'A4', true, 'UTF-8', false);
    $pdf->reportReference = $reference;
    $pdf->disableTcpdfAttribution();
    $pdf->SetCreator('Concrete Equipment Hire Limited');
    $pdf->SetAuthor('Concrete Equipment Hire Limited');
    $pdf->SetTitle($reference . ' Daily Production Report');
    $pdf->SetPrintHeader(false);
    $pdf->SetPrintFooter(true);
    $pdf->SetMargins(15, 14, 15);
    $pdf->SetAutoPageBreak(true, 22);
    $pdf->setFontSubsetting(true);
    $pdf->AddPage();

    // Palette sampled directly from the supplied monochrome CEH logo.
    $black = [0, 0, 0];
    $darkGray = [89, 89, 89];
    $midGray = [165, 165, 165];
    $white = [255, 255, 255];

    // Keep the supplied logo untouched and preserve its original aspect ratio.
    $pdf->embedRequiredPng($logoPng, 15, 12, 78);
    $pdf->SetXY(98, 13);
    $pdf->SetFont('dejavusans', 'B', 17);
    $pdf->SetTextColor(...$black);
    $pdf->Cell(97, 9, 'DAILY PRODUCTION REPORT', 0, 1, 'R');
    $pdf->SetX(98);
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->SetTextColor(...$darkGray);
    $pdf->Cell(97, 7, $reference, 0, 1, 'R');
    $pdf->SetDrawColor(...$black);
    $pdf->SetLineWidth(0.55);
    $pdf->Line(15, 35, 195, 35);
    $pdf->SetY(41);

    $drawSectionHeading = static function (
        CehProductionReportPdf $document,
        string $heading
    ) use ($black, $midGray): void {
        $document->SetTextColor(...$black);
        $document->SetFont('dejavusans', 'B', 10);
        $document->Cell(0, 6, $heading, 0, 1);
        $document->SetDrawColor(...$midGray);
        $document->SetLineWidth(0.25);
        $document->Line(15, $document->GetY(), 195, $document->GetY());
        $document->Ln(3);
    };

    $drawSectionHeading($pdf, 'PRODUCTION DETAILS');

    $meta = [
        ['Production Date', (new DateTimeImmutable((string)$session['production_date']))->format('d M Y')],
        ['Client', (string)$session['client_name']],
        ['Project / Site', (string)$session['project_site']],
        ['Mixer', (string)$session['mixer_code_snapshot'] . ' - ' . (string)$session['mixer_name_snapshot']],
        ['Operator', (string)$session['operator_name_snapshot']],
    ];
    foreach ($meta as [$label, $value]) {
        $pdf->SetFont('dejavusans', 'B', 8);
        $pdf->SetTextColor(...$darkGray);
        $pdf->Cell(38, 7, strtoupper($label), 0, 0);
        $pdf->SetFont('dejavusans', '', 9);
        $pdf->SetTextColor(...$black);
        $pdf->MultiCell(142, 7, $value, 0, 'L', false, 1);
    }
    $notes = trim((string)($session['notes'] ?? ''));
    if ($notes !== '') {
        $pdf->SetFont('dejavusans', 'B', 8);
        $pdf->SetTextColor(...$darkGray);
        $pdf->Cell(38, 7, 'NOTES', 0, 0);
        $pdf->SetFont('dejavusans', '', 9);
        $pdf->SetTextColor(...$black);
        $pdf->MultiCell(142, 7, $notes, 0, 'L', false, 1);
    }
    $pdf->Ln(7);

    $drawSectionHeading($pdf, 'LOAD DETAILS');

    $drawLoadHeader = static function (CehProductionReportPdf $document) use ($black, $white): void {
        $document->SetFillColor(...$black);
        $document->SetDrawColor(...$black);
        $document->SetTextColor(...$white);
        $document->SetFont('dejavusans', 'B', 9);
        $document->Cell(28, 9, 'LOAD', 1, 0, 'C', true);
        $document->Cell(82, 9, 'TIME', 1, 0, 'C', true);
        $document->Cell(70, 9, 'VOLUME (m³)', 1, 1, 'C', true);
    };
    $drawLoadHeader($pdf);
    $pdf->SetFont('dejavusans', '', 9);
    $pdf->SetTextColor(...$black);
    $pdf->SetDrawColor(...$midGray);
    foreach ($loads as $load) {
        if ($pdf->GetY() > 247) {
            $pdf->AddPage();
            $drawLoadHeader($pdf);
            $pdf->SetFont('dejavusans', '', 9);
            $pdf->SetTextColor(...$black);
            $pdf->SetDrawColor(...$midGray);
        }
        $pdf->Cell(28, 8, (string)$load['load_number'], 1, 0, 'C');
        $pdf->Cell(82, 8, production_report_local_time((string)$load['recorded_at']), 1, 0, 'C');
        $pdf->Cell(70, 8, number_format((float)$load['volume_m3'], 2), 1, 1, 'R');
    }

    if ($pdf->GetY() > 197) $pdf->AddPage();
    $pdf->Ln(8);
    $pdf->SetDrawColor(...$black);
    $pdf->SetTextColor(...$black);
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->Cell(45, 14, 'MIXER ' . (string)$session['mixer_code_snapshot'], 1, 0, 'C');
    $pdf->Cell(40, 14, (int)$signoff['load_count'] . ' LOADS', 1, 0, 'C');
    $pdf->SetFillColor(...$black);
    $pdf->SetTextColor(...$white);
    $pdf->SetFont('dejavusans', 'B', 11);
    $pdf->Cell(95, 14, 'TOTAL PRODUCTION  ' . number_format((float)$signoff['total_m3'], 2) . ' m³', 1, 1, 'C', true);
    $pdf->Ln(10);

    if ($pdf->GetY() > 205) $pdf->AddPage();

    $drawSectionHeading($pdf, 'CLIENT CONFIRMATION');
    $pdf->SetFont('dejavusans', 'B', 8);
    $pdf->SetTextColor(...$darkGray);
    $pdf->Cell(90, 5, 'CLIENT REPRESENTATIVE', 0, 0);
    $pdf->Cell(90, 5, 'SIGNED DATE / TIME', 0, 1);
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->SetTextColor(...$black);
    $pdf->Cell(90, 7, (string)$signoff['representative_name'], 0, 0);
    $pdf->Cell(90, 7, production_report_local_time((string)$signoff['signed_at']), 0, 1);
    $pdf->Ln(4);
    $pdf->SetFont('dejavusans', 'B', 8);
    $pdf->SetTextColor(...$darkGray);
    $pdf->Cell(0, 5, 'ORIGINAL CAPTURED CLIENT SIGNATURE', 0, 1);
    $signatureInfo = @getimagesizefromstring($signaturePng);
    if (!is_array($signatureInfo) || $signatureInfo[0] <= 0 || $signatureInfo[1] <= 0) {
        throw new RuntimeException('PDF_SIGNATURE_INVALID');
    }
    $signatureWidth = min(85.0, 27.0 * ((float)$signatureInfo[0] / (float)$signatureInfo[1]));
    $signatureHeight = $signatureWidth * (float)$signatureInfo[1] / (float)$signatureInfo[0];
    $signatureY = $pdf->GetY() + 2;
    $pdf->embedRequiredPng($signaturePng, 15, $signatureY, $signatureWidth, $signatureHeight);
    $signatureLineY = $signatureY + max($signatureHeight, 18.0) + 2;
    $pdf->SetDrawColor(...$midGray);
    $pdf->Line(15, $signatureLineY, 105, $signatureLineY);

    $bytes = $pdf->Output($reference . '.pdf', 'S');
    unset($pdf);
    production_report_cleanup_cache_directory($cacheDirectory);
    if (substr_count($bytes, '/Subtype /Image') < 2) {
        throw new RuntimeException('PDF_REQUIRED_IMAGES_MISSING');
    }
    production_discard_output();
    header('Content-Type: application/pdf');
    header('Content-Disposition: attachment; filename="' . $reference . '.pdf"');
    header('Content-Length: ' . strlen($bytes));
    header('Cache-Control: private, no-store, no-cache, must-revalidate');
    header('X-Content-Type-Options: nosniff');
    echo $bytes;
    exit;
} catch (Throwable $exception) {
    if ($db->inTransaction()) $db->rollBack();
    if (isset($pdf)) unset($pdf); // TCPDF destructor removes its temp files.
    if (isset($cacheDirectory)) production_report_cleanup_cache_directory($cacheDirectory);
    production_report_fail($user, $exception);
}
