<?php
declare(strict_types=1);

require_once __DIR__.'/reports_common.php';
require_once __DIR__.'/vendor/tcpdf/tcpdf.php';
require_once __DIR__.'/vendor/setasign/fpdi/src/autoload.php';

const REPORT_PDF_INK = [18, 18, 18];
const REPORT_PDF_TEXT = [20, 20, 20];
const REPORT_PDF_SECONDARY = [75, 75, 75];
const REPORT_PDF_BORDER = [190, 190, 190];
const REPORT_PDF_PANEL = [245, 245, 245];
const REPORT_PDF_ALT = [250, 250, 250];

function reports_pdf_money(mixed $amount): string {
    return '₦'.number_format((float)$amount, 2);
}

function reports_pdf_text(mixed $value): string {
    $value = trim((string)$value);
    return $value === '' ? 'Not allocated' : $value;
}

function reports_pdf_date(mixed $value): string {
    $value = trim((string)$value);
    return $value === '' ? 'Not specified' : (new DateTimeImmutable($value))->format('d-m-Y');
}

function reports_pdf_line_filter_active(array $filters): bool {
    foreach (['account_id', 'client_id', 'project_id', 'mixer_id', 'cost_centre_id'] as $key) {
        if ((int)($filters[$key] ?? 0) > 0) {
            return true;
        }
    }
    foreach (['category', 'client', 'project', 'equipment', 'cost_centre'] as $key) {
        if (trim((string)($filters[$key] ?? '')) !== '') {
            return true;
        }
    }
    return false;
}

function reports_evidence_bytes(array $evidence): string {
    $driver = (string)$evidence['storage_driver'];
    if ($driver === 'MYSQL_BLOB') {
        $bytes = (string)($evidence['evidence_data'] ?? '');
    } elseif ($driver === 'PRIVATE_FILE') {
        $key = (string)($evidence['storage_key'] ?? '');
        $base = realpath(__DIR__.'/runtime');
        $path = realpath(__DIR__.'/runtime/'.$key);
        if ($base === false || $path === false || !str_starts_with($path, $base.DIRECTORY_SEPARATOR) || !is_file($path)) {
            accounts_fail('EVIDENCE_UNAVAILABLE', 409);
        }
        $bytes = (string)file_get_contents($path);
    } else {
        accounts_fail('EVIDENCE_STORAGE_UNSUPPORTED', 409);
    }
    if ($bytes === '' || !hash_equals(strtolower((string)$evidence['sha256']), hash('sha256', $bytes))) {
        accounts_fail('EVIDENCE_INTEGRITY_FAILED', 409);
    }
    return $bytes;
}

function reports_pdf_filter_rows(string $title, array $filters): array {
    $rows = [];
    $from = trim((string)($filters['date_from'] ?? ''));
    $to = trim((string)($filters['date_to'] ?? ''));
    if ($from !== '' || $to !== '') {
        $rows[] = ['Report period', ($from === '' ? 'Beginning' : reports_pdf_date($from)).' to '.($to === '' ? 'Present' : reports_pdf_date($to))];
    } else {
        $rows[] = ['Report period', 'All available dates'];
    }
    if (stripos($title, 'Receivables') !== false) {
        $rows[] = ['As at', reports_pdf_date($filters['as_of'] ?? '')];
    }
    $labels = [
        'source' => 'Expense source', 'status' => 'Status', 'reference' => 'CEH reference',
        'paid_to' => 'Supplier / paid to', 'custodian' => 'Custodian', 'category' => 'Category',
        'client' => 'Client', 'project' => 'Project', 'equipment' => 'Equipment',
        'cost_centre' => 'Cost centre', 'evidence' => 'Evidence',
    ];
    foreach ($labels as $key => $label) {
        $value = trim((string)($filters[$key] ?? ''));
        if ($value === '' || $value === 'ALL') {
            continue;
        }
        $rows[] = [$label, ucwords(strtolower(str_replace('_', ' ', $value)))];
    }
    if (!array_filter($rows, static fn(array $row): bool => $row[0] === 'Evidence')) {
        $rows[] = ['Evidence', 'All'];
    }
    return $rows;
}

function reports_pdf_document(string $title, array $filters): \setasign\Fpdi\Tcpdf\Fpdi {
    $pdf = new class('L', 'mm', 'A4', true, 'UTF-8', false) extends \setasign\Fpdi\Tcpdf\Fpdi {
        public function Footer(): void {
            $this->SetY(-12);
            $this->SetFont('dejavusans', '', 7);
            $this->SetTextColor(...REPORT_PDF_SECONDARY);
            $this->Cell(0, 5, 'Concrete Equipment Hire Limited  •  Page '.$this->getAliasNumPage().' of '.$this->getAliasNbPages(), 0, 0, 'C');
        }
    };
    $pdf->setPrintHeader(false);
    $pdf->setPrintFooter(true);
    $pdf->SetMargins(12, 12, 12);
    $pdf->SetAutoPageBreak(true, 16);
    $pdf->SetCreator('Concrete Equipment Hire Limited');
    $pdf->SetTitle($title);
    $pdf->AddPage();
    $logo = @file_get_contents(__DIR__.'/assets/ceh_logo.png');
    if ($logo !== false) {
        $pdf->Image('@'.$logo, 12, 8, 50, 0, 'PNG');
    }
    $pdf->SetXY(68, 10);
    $pdf->SetFont('dejavusans', 'B', strlen($title) > 24 ? 14.5 : 17);
    $pdf->SetTextColor(...REPORT_PDF_INK);
    $pdf->Cell(217, 9, strtoupper($title), 0, 1, 'R');
    $pdf->SetX(68);
    $pdf->SetFont('dejavusans', '', 8);
    $pdf->SetTextColor(...REPORT_PDF_SECONDARY);
    $pdf->Cell(217, 5, 'Generated '.gmdate('d-m-Y H:i').' UTC', 0, 1, 'R');
    $pdf->SetX(68);
    $pdf->Cell(217, 5, 'Read-only financial report', 0, 1, 'R');
    $pdf->SetDrawColor(...REPORT_PDF_INK);
    $pdf->SetLineWidth(0.35);
    $pdf->Line(12, 34, 285, 34);
    $pdf->SetY(38);
    $pdf->SetFillColor(...REPORT_PDF_PANEL);
    $pdf->SetDrawColor(...REPORT_PDF_BORDER);
    $filterRows = reports_pdf_filter_rows($title, $filters);
    $height = max(10, count($filterRows) * 5 + 4);
    $pdf->RoundedRect(12, 38, 273, $height, 1.5, '1111', 'DF');
    $pdf->SetXY(16, 40);
    foreach ($filterRows as [$label, $value]) {
        $pdf->SetFont('dejavusans', 'B', 7.5);
        $pdf->SetTextColor(...REPORT_PDF_TEXT);
        $pdf->Cell(32, 5, $label.':', 0, 0, 'L');
        $pdf->SetFont('dejavusans', '', 7.5);
        $pdf->Cell(225, 5, $value, 0, 1, 'L');
        $pdf->SetX(16);
    }
    $pdf->SetY(38 + $height + 4);
    return $pdf;
}

function reports_pdf_table_header(\TCPDF $pdf, array $columns): void {
    $pdf->SetFillColor(...REPORT_PDF_INK);
    $pdf->SetDrawColor(...REPORT_PDF_BORDER);
    $pdf->SetTextColor(255, 255, 255);
    $pdf->SetFont('dejavusans', 'B', 6.5);
    foreach ($columns as $index => [$label, $width, $align]) {
        $label = str_replace(
            ['Transaction total', 'Amount matching filter', 'Ageing bucket'],
            ["Transaction\ntotal", "Amount matching\nfilter", "Ageing\nbucket"],
            $label
        );
        $pdf->MultiCell($width, 9, $label, 1, $align, true, $index === count($columns) - 1 ? 1 : 0, '', '', true, 0, false, true, 9, 'M');
    }
}

function reports_pdf_expenses(string $title, array $data, bool $withEvidence, ?callable $evidenceLoader = null): string {
    $pdf = reports_pdf_document($title, $data['filters']);
    $filtered = reports_pdf_line_filter_active($data['filters']);
    $columns = [
        ['Reference', 25, 'L'], ['Date', 19, 'C'], ['Source / custodian', 30, 'L'],
        ['Paid to / description', $filtered ? 55 : 65, 'L'],
        ['Client / project / equipment', $filtered ? 48 : 55, 'L'],
        ['Status / journal', $filtered ? 35 : 46, 'L'],
        [$filtered ? 'Transaction total' : 'Transaction amount', $filtered ? 28 : 33, 'R'],
    ];
    if ($filtered) {
        $columns[] = ['Amount matching filter', 28, 'R'];
    }
    reports_pdf_table_header($pdf, $columns);
    $fill = false;
    foreach ($data['rows'] as $row) {
        $values = [
            (string)$row['reference_no'], reports_pdf_date($row['expense_date']),
            reports_pdf_text($row['source_name'] ?? $row['custodian_name'] ?? ''),
            reports_pdf_text($row['supplier_paid_to'])."\n".reports_pdf_text($row['description']),
            reports_pdf_text($row['client_name'])."\n".reports_pdf_text($row['project_name']).' • '.reports_pdf_text($row['mixer_code']),
            reports_pdf_text($row['status'])."\n".reports_pdf_text($row['original_journal_reference']),
            reports_pdf_money($row['amount']),
        ];
        if ($filtered) {
            $values[] = reports_pdf_money($row['matched_amount']);
        }
        $height = 7.0;
        foreach ($values as $index => $value) {
            $height = max($height, $pdf->getStringHeight($columns[$index][1] - 2, $value) + 2);
        }
        if ($pdf->GetY() + $height > 188) {
            $pdf->AddPage();
            reports_pdf_table_header($pdf, $columns);
        }
        if ($fill) {
            $pdf->SetFillColor(...REPORT_PDF_ALT);
        }
        $pdf->SetDrawColor(...REPORT_PDF_BORDER);
        $pdf->SetTextColor(...REPORT_PDF_TEXT);
        $pdf->SetFont('dejavusans', '', 6.2);
        foreach ($values as $index => $value) {
            $pdf->MultiCell($columns[$index][1], $height, $value, 1, $columns[$index][2], $fill, $index === count($values) - 1 ? 1 : 0, '', '', true, 0, false, true, $height, 'M');
        }
        $fill = !$fill;
    }
    if ($pdf->GetY() > 180) {
        $pdf->AddPage();
    }
    $pdf->Ln(3);
    $pdf->SetDrawColor(...REPORT_PDF_INK);
    $pdf->Line(170, $pdf->GetY(), 285, $pdf->GetY());
    $pdf->Ln(2);
    $pdf->SetFont('dejavusans', '', 8.5);
    $pdf->Cell(220, 7, 'Transactions', 0, 0, 'R');
    $pdf->SetFont('dejavusans', 'B', 9);
    $pdf->Cell(45, 7, (string)$data['totals']['transaction_count'], 0, 1, 'R');
    $total = $filtered ? $data['totals']['matched_amount'] : $data['totals']['header_amount'];
    $label = $filtered ? 'Total amount matching filter' : 'Total transaction amount';
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->Cell(220, 8, $label, 0, 0, 'R');
    $pdf->Cell(45, 8, reports_pdf_money($total), 0, 1, 'R');
    if ($withEvidence) {
        reports_pdf_append_evidence($pdf, $data['rows'], $evidenceLoader);
    }
    return $pdf->Output('report.pdf', 'S');
}

function reports_pdf_evidence_heading(\TCPDF $pdf, string $reference): void {
    $pdf->SetFont('dejavusans', 'B', 12);
    $pdf->SetTextColor(...REPORT_PDF_INK);
    $pdf->Cell(0, 8, 'Supporting Evidence - '.$reference, 0, 1, 'L');
    $pdf->SetDrawColor(...REPORT_PDF_INK);
    $pdf->Line($pdf->GetX(), $pdf->GetY(), $pdf->getPageWidth() - 12, $pdf->GetY());
    $pdf->Ln(3);
}

function reports_pdf_append_evidence(\setasign\Fpdi\Tcpdf\Fpdi $pdf, array $rows, ?callable $evidenceLoader = null): void {
    $db = $evidenceLoader === null ? production_db() : null;
    $tempDir = __DIR__.'/runtime/private_report_imports';
    if (!is_dir($tempDir) && !mkdir($tempDir, 0700, true) && !is_dir($tempDir)) {
        accounts_fail('REPORT_TEMPORARY_STORAGE_FAILED', 500);
    }
    @chmod($tempDir, 0700);
    foreach ($rows as $row) {
        $source = $row['source_type'] === 'BANK' ? 'GENERAL_EXPENSE' : 'PETTY_CASH_EXPENSE';
        $evidence = $evidenceLoader === null
            ? reports_evidence($db, $source, (int)$row['id'])
            : (array)$evidenceLoader($row);
        if ($evidence === []) {
            $pdf->AddPage('P');
            reports_pdf_evidence_heading($pdf, (string)$row['reference_no']);
            $pdf->SetFont('dejavusans', 'B', 10);
            $pdf->Cell(0, 8, 'No receipt attached', 0, 1);
            if (trim((string)($row['no_receipt_reason'] ?? '')) !== '') {
                $pdf->SetFont('dejavusans', '', 9);
                $pdf->MultiCell(0, 6, 'Recorded reason: '.$row['no_receipt_reason'], 0, 'L');
            }
            continue;
        }
        foreach ($evidence as $item) {
            $bytes = reports_evidence_bytes($item);
            $mime = strtolower((string)$item['mime_type']);
            $pdf->AddPage('P');
            reports_pdf_evidence_heading($pdf, (string)$row['reference_no']);
            $pdf->SetFillColor(...REPORT_PDF_PANEL);
            $pdf->SetDrawColor(...REPORT_PDF_BORDER);
            $pdf->SetFont('dejavusans', 'B', 8);
            $pdf->Cell(35, 6, 'Evidence file', 1, 0, 'L', true);
            $pdf->SetFont('dejavusans', '', 8);
            $pdf->Cell(150, 6, (string)$item['original_filename'], 1, 1, 'L', true);
            $pdf->SetFont('dejavusans', 'B', 8);
            $pdf->Cell(35, 6, 'File details', 1, 0, 'L', true);
            $pdf->SetFont('dejavusans', '', 8);
            $pdf->Cell(150, 6, $mime.' • '.(int)$item['byte_size'].' bytes', 1, 1, 'L', true);
            $pdf->SetFont('dejavusans', 'B', 8);
            $pdf->Cell(35, 6, 'SHA-256', 1, 0, 'L', true);
            $pdf->SetFont('dejavusans', '', 7);
            $pdf->Cell(150, 6, strtolower((string)$item['sha256']), 1, 1, 'L', true);
            if (in_array($mime, ['image/jpeg', 'image/png'], true)) {
                if (@getimagesizefromstring($bytes) === false) {
                    accounts_fail('EVIDENCE_IMAGE_INVALID', 409);
                }
                $pdf->Image('@'.$bytes, 15, 55, 180, 218, '', '', '', true, 300, 'C', false, false, 0, true, true, true);
                continue;
            }
            if ($mime !== 'application/pdf' || !str_starts_with($bytes, '%PDF-')) {
                accounts_fail('EVIDENCE_FORMAT_INVALID', 409);
            }
            $temp = $tempDir.DIRECTORY_SEPARATOR.bin2hex(random_bytes(16)).'.pdf';
            if (file_put_contents($temp, $bytes, LOCK_EX) !== strlen($bytes)) {
                accounts_fail('REPORT_TEMPORARY_STORAGE_FAILED', 500);
            }
            @chmod($temp, 0600);
            try {
                $pages = $pdf->setSourceFile($temp);
                if ($pages < 1 || $pages > 100) {
                    accounts_fail('EVIDENCE_PDF_PAGE_LIMIT', 409);
                }
                for ($page = 1; $page <= $pages; $page++) {
                    $template = $pdf->importPage($page);
                    $size = $pdf->getTemplateSize($template);
                    $pdf->AddPage($size['orientation']);
                    reports_pdf_evidence_heading($pdf, (string)$row['reference_no'].' - '.$item['original_filename'].' - page '.$page.' of '.$pages);
                    $availableWidth = $size['orientation'] === 'L' ? 273 : 186;
                    $pdf->useTemplate($template, 12, 28, $availableWidth, null, false);
                }
            } finally {
                @unlink($temp);
            }
        }
    }
}

function reports_pdf_receivables(array $data): string {
    $pdf = reports_pdf_document('Receivables Report', $data['filters']);
    $columns = [
        ['Client', 52, 'L'], ['Invoice', 32, 'L'], ['Invoice date', 23, 'C'], ['Due date', 23, 'C'],
        ['Original', 35, 'R'], ['Payments / credits', 35, 'R'], ['Outstanding', 35, 'R'],
        ['Days overdue', 20, 'R'], ['Ageing bucket', 18, 'C'],
    ];
    reports_pdf_table_header($pdf, $columns);
    $fill = false;
    foreach ($data['invoices'] as $row) {
        $values = [
            $row['client_name_snapshot'], $row['reference'], reports_pdf_date($row['invoice_date']),
            $row['due_date'] === null ? 'Not due-dated' : reports_pdf_date($row['due_date']),
            reports_pdf_money($row['original_amount']), reports_pdf_money($row['payments_credits_applied']),
            reports_pdf_money($row['outstanding']), (string)$row['days_overdue'], str_replace('_', '-', $row['bucket']),
        ];
        if ($pdf->GetY() + 9 > 188) {
            $pdf->AddPage();
            reports_pdf_table_header($pdf, $columns);
        }
        if ($fill) {
            $pdf->SetFillColor(...REPORT_PDF_ALT);
        }
        $pdf->SetDrawColor(...REPORT_PDF_BORDER);
        $pdf->SetTextColor(...REPORT_PDF_TEXT);
        $pdf->SetFont('dejavusans', '', 6.3);
        foreach ($values as $index => $value) {
            $pdf->MultiCell($columns[$index][1], 8, (string)$value, 1, $columns[$index][2], $fill, $index === count($values) - 1 ? 1 : 0, '', '', true, 0, false, true, 8, 'M');
        }
        $fill = !$fill;
    }
    if ($pdf->GetY() > 172) {
        $pdf->AddPage();
    }
    $pdf->Ln(4);
    $pdf->SetDrawColor(...REPORT_PDF_INK);
    $pdf->Line(180, $pdf->GetY(), 285, $pdf->GetY());
    $pdf->Ln(3);
    $pdf->SetFont('dejavusans', '', 8.5);
    $pdf->Cell(220, 7, 'Outstanding invoices', 0, 0, 'R');
    $pdf->SetFont('dejavusans', 'B', 9);
    $pdf->Cell(45, 7, (string)$data['totals']['invoice_count'], 0, 1, 'R');
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->Cell(220, 8, 'Total Outstanding', 0, 0, 'R');
    $pdf->Cell(45, 8, reports_pdf_money($data['totals']['outstanding']), 0, 1, 'R');
    $pdf->SetFont('dejavusans', '', 7.5);
    $pdf->SetTextColor(...REPORT_PDF_SECONDARY);
    $pdf->Cell(220, 6, 'Original invoices', 0, 0, 'R');
    $pdf->Cell(45, 6, reports_pdf_money($data['totals']['original_amount']), 0, 1, 'R');
    $pdf->Cell(220, 6, 'Payments / credits applied', 0, 0, 'R');
    $pdf->Cell(45, 6, reports_pdf_money($data['totals']['payments_credits_applied']), 0, 1, 'R');
    return $pdf->Output('receivables-report.pdf', 'S');
}

function reports_pdf_output(string $filename, string $bytes): never {
    header('Content-Type: application/pdf');
    header('Content-Length: '.strlen($bytes));
    header('Cache-Control: private, no-store');
    header('Content-Disposition: attachment; filename="'.$filename.'"');
    echo $bytes;
    exit;
}
