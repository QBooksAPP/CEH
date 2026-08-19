<?php
declare(strict_types=1);

require_once __DIR__ . '/production_report_common.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
production_require_method('GET');
$sessionId = (int)($_GET['session_id'] ?? 0);
if ($sessionId <= 0) qbook_json(['ok' => false, 'error' => 'PRODUCTION_SESSION_REQUIRED'], 422);

// CEH renders only local/inline resources. zlib is required for compressed PDF
// streams, and GD or Imagick is required for alpha-channel PNG processing.
// Optional TCPDF remote-resource support is unused.
if (!extension_loaded('zlib')
    || (!extension_loaded('gd') && !extension_loaded('imagick'))) {
    qbook_json(['ok' => false, 'error' => 'PDF_ENGINE_UNAVAILABLE'], 503);
}
require_once __DIR__ . '/vendor/tcpdf/tcpdf.php';

final class CehProductionReportPdf extends TCPDF {
    public string $reportReference = '';

    public function Footer(): void {
        $this->SetY(-14);
        $this->SetFont('dejavusans', '', 8);
        $this->SetTextColor(80, 90, 105);
        $this->Cell(
            0,
            8,
            $this->reportReference . '  •  Page ' . $this->getAliasNumPage() . '/' . $this->getAliasNbPages(),
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
        throw new RuntimeException('SIGNED_EVIDENCE_MISSING');
    }

    $report = production_report_issue($db, $sessionId);
    $loads = production_loads($db, $sessionId);
    $db->commit();

    $reference = $report['reference'];
    $pdf = new CehProductionReportPdf('P', 'mm', 'A4', true, 'UTF-8', false);
    $pdf->reportReference = $reference;
    $pdf->SetCreator('Concrete Equipment Hire Limited');
    $pdf->SetAuthor('Concrete Equipment Hire Limited');
    $pdf->SetTitle($reference . ' Daily Production Report');
    $pdf->SetPrintHeader(false);
    $pdf->SetPrintFooter(true);
    $pdf->SetMargins(15, 14, 15);
    $pdf->SetAutoPageBreak(true, 22);
    $pdf->setFontSubsetting(true);
    $pdf->AddPage();

    $navy = [18, 42, 76];
    $blue = [31, 103, 178];
    $light = [234, 241, 248];
    $logo = __DIR__ . '/assets/ceh_logo.png';
    $pdf->Image($logo, 15, 12, 38, 0, 'PNG');
    $pdf->SetXY(58, 13);
    $pdf->SetFont('dejavusans', 'B', 14);
    $pdf->SetTextColor(...$navy);
    $pdf->Cell(137, 7, 'Concrete Equipment Hire Limited', 0, 1, 'R');
    $pdf->SetX(58);
    $pdf->SetFont('dejavusans', 'B', 18);
    $pdf->SetTextColor(...$blue);
    $pdf->Cell(137, 10, 'DAILY PRODUCTION REPORT', 0, 1, 'R');
    $pdf->SetX(58);
    $pdf->SetFont('dejavusans', 'B', 11);
    $pdf->SetTextColor(...$navy);
    $pdf->Cell(137, 7, $reference, 0, 1, 'R');
    $pdf->Ln(7);

    $meta = [
        ['Production Date', (new DateTimeImmutable((string)$session['production_date']))->format('d M Y')],
        ['Client', (string)$session['client_name']],
        ['Project / Site', (string)$session['project_site']],
        ['Mixer', (string)$session['mixer_code_snapshot'] . ' — ' . (string)$session['mixer_name_snapshot']],
        ['Operator', (string)$session['operator_name_snapshot']],
    ];
    foreach ($meta as [$label, $value]) {
        $pdf->SetFont('dejavusans', 'B', 9);
        $pdf->SetTextColor(...$navy);
        $pdf->Cell(42, 7, $label, 0, 0);
        $pdf->SetFont('dejavusans', '', 9);
        $pdf->MultiCell(138, 7, $value, 0, 'L', false, 1);
    }
    $notes = trim((string)($session['notes'] ?? ''));
    if ($notes !== '') {
        $pdf->SetFont('dejavusans', 'B', 9);
        $pdf->Cell(42, 7, 'Notes', 0, 0);
        $pdf->SetFont('dejavusans', '', 9);
        $pdf->MultiCell(138, 7, $notes, 0, 'L', false, 1);
    }
    $pdf->Ln(5);

    $drawLoadHeader = static function (CehProductionReportPdf $document) use ($navy): void {
        $document->SetFillColor(...$navy);
        $document->SetTextColor(255, 255, 255);
        $document->SetFont('dejavusans', 'B', 9);
        $document->Cell(28, 8, 'Load', 1, 0, 'C', true);
        $document->Cell(82, 8, 'Time', 1, 0, 'C', true);
        $document->Cell(70, 8, 'Volume (m³)', 1, 1, 'C', true);
    };
    $drawLoadHeader($pdf);
    $pdf->SetFont('dejavusans', '', 9);
    $pdf->SetTextColor(20, 28, 38);
    foreach ($loads as $load) {
        if ($pdf->GetY() > 250) {
            $pdf->AddPage();
            $drawLoadHeader($pdf);
            $pdf->SetFont('dejavusans', '', 9);
            $pdf->SetTextColor(20, 28, 38);
        }
        $pdf->Cell(28, 7, (string)$load['load_number'], 1, 0, 'C');
        $pdf->Cell(82, 7, production_report_local_time((string)$load['recorded_at']), 1, 0, 'C');
        $pdf->Cell(70, 7, number_format((float)$load['volume_m3'], 2), 1, 1, 'R');
    }

    if ($pdf->GetY() > 205) $pdf->AddPage();
    $pdf->Ln(7);
    $pdf->SetFillColor(...$light);
    $pdf->SetTextColor(...$navy);
    $pdf->SetFont('dejavusans', 'B', 11);
    $pdf->Cell(45, 12, 'MIXER ' . (string)$session['mixer_code_snapshot'], 0, 0, 'C', true);
    $pdf->Cell(40, 12, (int)$signoff['load_count'] . ' LOADS', 0, 0, 'C', true);
    $pdf->Cell(95, 12, 'TOTAL PRODUCTION: ' . number_format((float)$signoff['total_m3'], 2) . ' m³', 0, 1, 'C', true);
    $pdf->Ln(8);

    if ($pdf->GetY() > 210) $pdf->AddPage();

    $pdf->SetFont('dejavusans', 'B', 11);
    $pdf->Cell(0, 7, 'CLIENT CONFIRMATION', 0, 1);
    $pdf->SetFont('dejavusans', '', 9);
    $pdf->Cell(48, 7, 'Client Representative', 0, 0);
    $pdf->SetFont('dejavusans', 'B', 9);
    $pdf->Cell(132, 7, (string)$signoff['representative_name'], 0, 1);
    $pdf->SetFont('dejavusans', '', 9);
    $pdf->Cell(48, 7, 'Signed', 0, 0);
    $pdf->Cell(132, 7, production_report_local_time((string)$signoff['signed_at']), 0, 1);
    $signatureY = $pdf->GetY() + 3;
    $pdf->Image('@' . $signoff['signature_data'], 15, $signatureY, 75, 28, 'PNG');
    $pdf->SetXY(15, $signatureY + 30);
    $pdf->SetFont('dejavusans', '', 8);
    $pdf->Cell(75, 5, 'Original captured client signature', 'T', 1, 'C');

    $bytes = $pdf->Output($reference . '.pdf', 'S');
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
    error_log('CEH Production Report generation failed for session ' . $sessionId);
    qbook_json(['ok' => false, 'error' => 'PRODUCTION_REPORT_FAILED'], 500);
}
