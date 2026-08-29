<?php
declare(strict_types=1);

require_once __DIR__.'/reports_common.php';
require_once __DIR__.'/company_regional_common.php';
require_once __DIR__.'/vendor/tcpdf/tcpdf.php';
require_once __DIR__.'/vendor/setasign/fpdi/src/autoload.php';

const REPORT_PDF_INK = [18, 18, 18];
const REPORT_PDF_TEXT = [20, 20, 20];
const REPORT_PDF_SECONDARY = [75, 75, 75];
const REPORT_PDF_BORDER = [190, 190, 190];
const REPORT_PDF_PANEL = [245, 245, 245];
const REPORT_PDF_ALT = [250, 250, 250];

function reports_pdf_money(mixed $amount): string {
    return company_money($amount, (string)($GLOBALS['ceh_report_currency'] ?? 'NGN'));
}

function reports_pdf_text(mixed $value): string {
    $value = trim((string)$value);
    return $value === '' ? 'Not allocated' : $value;
}

function reports_pdf_date(mixed $value): string {
    $value = trim((string)$value);
    if ($value === '') return 'Not specified';
    $format=(string)($GLOBALS['ceh_report_date_format']??'DD-MM-YYYY');
    $php=['DD-MM-YYYY'=>'d-m-Y','MM-DD-YYYY'=>'m-d-Y','YYYY-MM-DD'=>'Y-m-d'][$format]??'d-m-Y';
    return (new DateTimeImmutable($value))->format($php);
}

function reports_pdf_company(?array $company = null): array {
    if ($company === null) {
        $company = production_db()->query('SELECT s.company_legal_name,s.company_address,s.tax_identifier,r.time_zone,r.date_format,r.time_format,r.base_currency FROM qbook_invoice_settings s JOIN qbook_company_regional_settings r ON r.company_id=1 WHERE s.id=1')->fetch() ?: [];
    }
    foreach (['company_legal_name', 'company_address', 'tax_identifier'] as $field) {
        if (trim((string)($company[$field] ?? '')) === '') {
            accounts_fail('REPORT_SETTINGS_INCOMPLETE', 409);
        }
    }
    return $company;
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
        'qa_notice' => 'Data classification',
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

function reports_pdf_document(string $title, array $filters, ?array $company = null): \setasign\Fpdi\Tcpdf\Fpdi {
    $company = reports_pdf_company($company);
    $GLOBALS['ceh_report_currency']=(string)($company['base_currency']??'NGN');
    $GLOBALS['ceh_report_date_format']=(string)($company['date_format']??'DD-MM-YYYY');
    $pdf = new class('L', 'mm', 'A4', true, 'UTF-8', false) extends \setasign\Fpdi\Tcpdf\Fpdi {
        private bool $cehLogoEmbedded = false;

        public function disableTcpdfAttribution(): void {
            $this->tcpdflink = false;
        }

        public function embedRequiredCehLogo(): void {
            $configured = __DIR__.DIRECTORY_SEPARATOR.'assets'.DIRECTORY_SEPARATOR.'ceh_logo.png';
            $path = realpath($configured);
            if ($path === false || !is_file($path) || !is_readable($path)) {
                throw new RuntimeException('REPORT_LOGO_UNREADABLE');
            }
            $info = @getimagesize($path);
            if (!is_array($info) || ($info['mime'] ?? '') !== 'image/png' || $info[0] <= 0 || $info[1] <= 0) {
                throw new RuntimeException('REPORT_LOGO_INVALID');
            }
            $before = count($this->images);
            $this->Image($path, 12, 8, 50, 0, 'PNG');
            if (count($this->images) <= $before) {
                throw new RuntimeException('REPORT_LOGO_EMBED_FAILED');
            }
            $this->cehLogoEmbedded = true;
        }

        public function assertCehLogoEmbedded(): void {
            if (!$this->cehLogoEmbedded) {
                throw new RuntimeException('REPORT_LOGO_EMBED_FAILED');
            }
        }

        public function Footer(): void {
            $this->SetY(-12);
            $this->SetFont('dejavusans', '', 7);
            $this->SetTextColor(...REPORT_PDF_SECONDARY);
            $this->Cell(0, 5, 'Concrete Equipment Hire Limited  •  Page '.$this->getAliasNumPage().' of '.$this->getAliasNbPages(), 0, 0, 'C');
        }
    };
    $pdf->disableTcpdfAttribution();
    $pdf->setPrintHeader(false);
    $pdf->setPrintFooter(true);
    $pdf->SetMargins(12, 12, 12);
    $pdf->SetAutoPageBreak(true, 16);
    $pdf->SetCreator('Concrete Equipment Hire Limited');
    $pdf->SetAuthor('Concrete Equipment Hire Limited');
    $pdf->SetTitle($title);
    $pdf->AddPage();
    $pdf->embedRequiredCehLogo();
    $pdf->SetXY(66, 8);
    $pdf->SetFont('dejavusans', 'B', 9.5);
    $pdf->SetTextColor(...REPORT_PDF_INK);
    $pdf->MultiCell(107, 5, (string)$company['company_legal_name'], 0, 'L', false, 1);
    $pdf->SetX(66);
    $pdf->SetFont('dejavusans', '', 7.2);
    $pdf->SetTextColor(...REPORT_PDF_SECONDARY);
    $pdf->MultiCell(107, 4, (string)$company['company_address'], 0, 'L', false, 1);
    $pdf->SetX(66);
    $pdf->Cell(107, 4, 'TIN: '.(string)$company['tax_identifier'], 0, 1, 'L');
    $pdf->SetXY(178, 8);
    $pdf->SetFont('dejavusans', 'B', strlen($title) > 24 ? 14.5 : 17);
    $pdf->SetTextColor(...REPORT_PDF_INK);
    $pdf->MultiCell(107, 8, strtoupper($title), 0, 'R', false, 1);
    $pdf->SetX(178);
    $pdf->SetFont('dejavusans', '', 7.5);
    $pdf->SetTextColor(...REPORT_PDF_SECONDARY);
    $zone=new DateTimeZone((string)($company['time_zone']??'Africa/Lagos'));
    $generated=(new DateTimeImmutable('now',new DateTimeZone('UTC')))->setTimezone($zone);
    $datePattern=['DD-MM-YYYY'=>'d-m-Y','MM-DD-YYYY'=>'m-d-Y','YYYY-MM-DD'=>'Y-m-d'][(string)($company['date_format']??'DD-MM-YYYY')]??'d-m-Y';
    $timePattern=(string)($company['time_format']??'24_HOUR')==='12_HOUR'?'h:i A':'H:i';
    $pdf->Cell(107, 4.5, 'Generated '.$generated->format($datePattern.' '.$timePattern).' '.(string)($company['time_zone']??'Africa/Lagos'), 0, 1, 'R');
    $pdf->SetX(178);
    $pdf->Cell(107, 4.5, 'Read-only financial report', 0, 1, 'R');
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

function reports_pdf_expenses(string $title, array $data, bool $withEvidence, ?callable $evidenceLoader = null, ?array $company = null): string {
    $pdf = reports_pdf_document($title, $data['filters'], $company);
    $evidenceByRow = $withEvidence ? reports_pdf_collect_evidence($data['rows'], $evidenceLoader) : [];
    $filtered = reports_pdf_line_filter_active($data['filters']);
    $columns = [
        ['Reference', 25, 'L'], ['Date', 19, 'C'], ['Source / custodian', 30, 'L'],
        ['Paid to / description', $filtered ? 44 : 55, 'L'],
        ['Client / project / equipment', $filtered ? 40 : 48, 'L'],
        ['Status / journal', $filtered ? 32 : 38, 'L'],
        ['Evidence', $filtered ? 17 : 18, 'C'],
        [$filtered ? 'Transaction total' : 'Transaction amount', $filtered ? 27 : 33, 'R'],
    ];
    if ($filtered) {
        $columns[] = ['Amount matching filter', 28, 'R'];
    }
    $pdf->SetFont('dejavusans', 'B', 11);
    $pdf->SetTextColor(...REPORT_PDF_INK);
    $pdf->Cell(0, 7, 'SECTION 1 - TRANSACTION REGISTER', 0, 1, 'L');
    reports_pdf_table_header($pdf, $columns);
    $fill = false;
    foreach ($data['rows'] as $row) {
        $values = [
            (string)$row['reference_no'], reports_pdf_date($row['expense_date']),
            reports_pdf_text($row['source_name'] ?? $row['custodian_name'] ?? ''),
            reports_pdf_text($row['supplier_paid_to'])."\n".reports_pdf_text($row['description']),
            reports_pdf_text($row['client_name'])."\n".reports_pdf_text($row['project_name']).' • '.reports_pdf_text($row['mixer_code']),
            reports_pdf_text($row['status'])."\n".reports_pdf_text($row['original_journal_reference']),
            $evidenceByRow[reports_pdf_evidence_key($row)] === [] ? 'Missing' : 'Attached',
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
        reports_pdf_append_missing_evidence_summary($pdf, $data['rows'], $evidenceByRow);
        reports_pdf_append_evidence($pdf, $data['rows'], $evidenceByRow);
    }
    $pdf->assertCehLogoEmbedded();
    return $pdf->Output('report.pdf', 'S');
}

function reports_pdf_evidence_heading(\TCPDF $pdf, string $reference): void {
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->SetTextColor(...REPORT_PDF_INK);
    $pdf->MultiCell($pdf->getPageWidth() - 24, 6, 'Supporting Evidence - '.$reference, 0, 'L', false, 1);
    $pdf->SetDrawColor(...REPORT_PDF_INK);
    $pdf->Line($pdf->GetX(), $pdf->GetY(), $pdf->getPageWidth() - 12, $pdf->GetY());
    $pdf->Ln(3);
}

function reports_pdf_evidence_key(array $row): string {
    return (string)$row['source_type'].':'.(int)$row['id'];
}

function reports_pdf_collect_evidence(array $rows, ?callable $evidenceLoader = null): array {
    $db = $evidenceLoader === null ? production_db() : null;
    $result = [];
    foreach ($rows as $row) {
        $source = $row['source_type'] === 'BANK' ? 'GENERAL_EXPENSE' : 'PETTY_CASH_EXPENSE';
        $result[reports_pdf_evidence_key($row)] = $evidenceLoader === null
            ? reports_evidence($db, $source, (int)$row['id'])
            : (array)$evidenceLoader($row);
    }
    return $result;
}

function reports_pdf_append_missing_evidence_summary(\TCPDF $pdf, array $rows, array $evidenceByRow): void {
    $missing = array_values(array_filter($rows, static fn(array $row): bool => $evidenceByRow[reports_pdf_evidence_key($row)] === []));
    $value = array_sum(array_map(static fn(array $row): int => accounts_money_minor($row['amount'], false), $missing));
    $pdf->AddPage('L');
    $pdf->SetFont('dejavusans', 'B', 14);
    $pdf->SetTextColor(...REPORT_PDF_INK);
    $pdf->Cell(0, 8, 'SECTION 2 - MISSING EVIDENCE SUMMARY', 0, 1, 'L');
    $pdf->SetFont('dejavusans', '', 8.5);
    $pdf->SetTextColor(...REPORT_PDF_SECONDARY);
    $pdf->Cell(0, 6, 'Transactions without supporting evidence: '.count($missing).'   •   Value without supporting evidence: '.reports_pdf_money(accounts_minor_decimal($value)), 0, 1, 'L');
    $pdf->Ln(2);
    $columns = [
        ['CEH reference', 27, 'L'], ['Date', 21, 'C'], ['Paid to / supplier', 48, 'L'],
        ['Description', 78, 'L'], ['Amount', 32, 'R'], ['Missing evidence reason', 67, 'L'],
    ];
    reports_pdf_table_header($pdf, $columns);
    $fill = false;
    foreach ($missing as $row) {
        $reason = trim((string)($row['no_receipt_reason'] ?? '')) ?: 'No receipt attached';
        $values = [(string)$row['reference_no'], reports_pdf_date($row['expense_date']), reports_pdf_text($row['supplier_paid_to']), reports_pdf_text($row['description']), reports_pdf_money($row['amount']), $reason];
        $height = 7.0;
        foreach ($values as $index => $cell) {
            $height = max($height, $pdf->getStringHeight($columns[$index][1] - 2, $cell) + 2);
        }
        if ($pdf->GetY() + $height > 188) {
            $pdf->AddPage('L');
            reports_pdf_table_header($pdf, $columns);
        }
        if ($fill) $pdf->SetFillColor(...REPORT_PDF_ALT);
        $pdf->SetDrawColor(...REPORT_PDF_BORDER);
        $pdf->SetTextColor(...REPORT_PDF_TEXT);
        $pdf->SetFont('dejavusans', '', 6.5);
        foreach ($values as $index => $cell) {
            $pdf->MultiCell($columns[$index][1], $height, $cell, 1, $columns[$index][2], $fill, $index === count($values) - 1 ? 1 : 0, '', '', true, 0, false, true, $height, 'M');
        }
        $fill = !$fill;
    }
    if ($missing === []) {
        $pdf->SetFont('dejavusans', '', 9);
        $pdf->Cell(0, 8, 'All qualifying transactions have supporting evidence attached.', 1, 1, 'L');
    }
}

function reports_pdf_append_evidence(\setasign\Fpdi\Tcpdf\Fpdi $pdf, array $rows, array $evidenceByRow): void {
    $tempDir = __DIR__.'/runtime/private_report_imports';
    if (!is_dir($tempDir) && !mkdir($tempDir, 0700, true) && !is_dir($tempDir)) {
        accounts_fail('REPORT_TEMPORARY_STORAGE_FAILED', 500);
    }
    @chmod($tempDir, 0700);
    $firstEvidence = true;
    foreach ($rows as $row) {
        $evidence = $evidenceByRow[reports_pdf_evidence_key($row)];
        if ($evidence === []) {
            continue;
        }
        foreach ($evidence as $item) {
            $bytes = reports_evidence_bytes($item);
            $mime = strtolower((string)$item['mime_type']);
            $pdf->AddPage('P');
            if ($firstEvidence) {
                $pdf->SetFont('dejavusans', 'B', 11);
                $pdf->SetTextColor(...REPORT_PDF_INK);
                $pdf->Cell(0, 7, 'SECTION 3 - SUPPORTING EVIDENCE', 0, 1, 'L');
                $firstEvidence = false;
            }
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
                $pdf->Image('@'.$bytes, 15, 55, 180, 218, '', '', '', true, 300, 'C', false, false, 0, true, false, true);
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

function reports_pdf_receivables(array $data, ?array $company = null): string {
    $pdf = reports_pdf_document('Receivables Report', $data['filters'], $company);
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
    $pdf->assertCehLogoEmbedded();
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
