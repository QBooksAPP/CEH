import 'dart:io';

import 'package:ceh/core/ceh_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('overview uses authoritative sources and document-date monthly expenses',
      () {
    final reports = source('Server/reports_common.php');
    expect(reports, contains("j.status='POSTED'"));
    expect(reports, contains("e.expense_date>=?"));
    expect(reports, contains('reports_receivables'));
    expect(reports, contains('accounts_custodian_balance'));
    expect(reports, isNot(contains('Net Operating Position')));
  });

  test('expense filtering totals matched lines without duplicating headers',
      () {
    final reports = source('Server/reports_common.php');
    expect(reports, contains('reports_line_matches'));
    expect(reports, contains("'matched_amount'"));
    expect(reports, contains("'header_amount'"));
    expect(reports, contains('array_sum(array_map'));
  });

  test('receivables JSON and PDF share the same ageing calculation', () {
    final ageing = source('Server/receivables_ageing.php');
    final report = source('Server/receivables_report.php');
    final pdf = source('Server/receivables_report_pdf.php');
    for (final file in [ageing, report, pdf]) {
      expect(file, contains('reports_receivables'));
    }
    final common = source('Server/reports_common.php');
    for (final bucket in ['CURRENT', '1_30', '31_60', '61_90', 'OVER_90']) {
      expect(common, contains(bucket));
    }
    expect(common, contains(r"$row['due_date']===null"));
  });

  test('audit packs enforce evidence integrity and private PDF import', () {
    final pdf = source('Server/report_pdf_common.php');
    expect(pdf, contains("hash_equals"));
    expect(pdf, contains("getimagesizefromstring"));
    expect(pdf, contains("setSourceFile"));
    expect(pdf, contains("importPage"));
    expect(pdf, contains("private_report_imports"));
    expect(pdf, contains("random_bytes(16)"));
    expect(pdf, contains("finally"));
    expect(pdf, contains("No receipt attached"));
    expect(pdf, contains('SECTION 1 - TRANSACTION REGISTER'));
    expect(pdf, contains('SECTION 2 - MISSING EVIDENCE SUMMARY'));
    expect(pdf, contains('SECTION 3 - SUPPORTING EVIDENCE'));
    expect(pdf, contains('Transactions without supporting evidence:'));
    expect(pdf, contains('Value without supporting evidence:'));
    expect(pdf, contains("continue;"));
    expect(pdf, contains('Supporting Evidence - '));
    expect(pdf, contains('Evidence file'));
    expect(pdf, contains('SHA-256'));
    expect(source('Server/vendor/setasign/fpdi/composer.json'),
        contains('setasign/fpdi'));
  });

  test('report PDFs use accountant-facing monochrome presentation', () {
    final pdf = source('Server/report_pdf_common.php');
    final fullExpense = source('Server/expense_audit_pack.php');
    expect(pdf, contains('company_money'));
    expect(pdf, contains('qbook_company_regional_settings'));
    expect(pdf, contains('Transaction amount'));
    expect(pdf, contains('Transaction total'));
    expect(pdf, contains('Amount matching filter'));
    expect(pdf, contains('Total Outstanding'));
    expect(pdf, contains('Report period'));
    expect(pdf, contains('Concrete Equipment Hire Limited'));
    expect(pdf, contains('company_legal_name'));
    expect(pdf, contains('company_address'));
    expect(pdf, contains('tax_identifier'));
    expect(pdf, contains('REPORT_SETTINGS_INCOMPLETE'));
    expect(pdf, contains('disableTcpdfAttribution'));
    expect(pdf, contains(r'$this->tcpdflink = false;'));
    expect(pdf, contains('embedRequiredCehLogo'));
    expect(pdf, contains('assertCehLogoEmbedded'));
    expect(pdf, contains('REPORT_LOGO_EMBED_FAILED'));
    expect(pdf, contains('REPORT_PDF_ALT'));
    expect(pdf, isNot(contains('Powered by TCPDF')));
    expect(pdf, isNot(contains("['Header'")));
    expect(pdf, isNot(contains("['Matched'")));
    expect(fullExpense, contains('Full Expense Audit Pack'));
  });

  test('missing evidence is summarized and never gets a blank evidence page',
      () {
    final pdf = source('Server/report_pdf_common.php');
    final emptyBranch = RegExp(
            r"if \(\$evidence === \[\]\) \{\s*continue;\s*\}",
            multiLine: true)
        .hasMatch(pdf);
    expect(emptyBranch, isTrue);
    expect(pdf, contains("?: 'No receipt attached'"));
    expect(pdf, contains('reports_pdf_collect_evidence'));
    expect(pdf, contains('reports_pdf_append_missing_evidence_summary'));
  });

  test('audit evidence matrix supports zero one many mixed and all missing',
      () {
    final pdf = source('Server/report_pdf_common.php');
    expect(pdf, contains(r"$missing = array_values(array_filter"));
    expect(pdf, contains(r"count($missing)"));
    expect(pdf, contains(r"array_sum(array_map"));
    expect(pdf, contains("?: 'No receipt attached'"));
    expect(pdf, contains(r"if ($evidence === [])"));
    expect(pdf, contains('continue;'));
    expect(pdf, contains(r"if ($firstEvidence)"));
    expect(pdf, contains("['image/jpeg', 'image/png']"));
    expect(pdf, contains("0, true, false, true);"));
    expect(pdf, contains(r"$mime !== 'application/pdf'"));
    expect(pdf, contains(r"for ($page = 1; $page <= $pages; $page++)"));
    expect(pdf, contains('original_filename'));
    expect(pdf, contains('byte_size'));
    expect(pdf, contains('sha256'));
    final regression = source('test/report_pdf_production_regression.php');
    expect(regression, contains('QA SAMPLE RECEIPT'));
    expect(regression, contains('QA SAMPLE EVIDENCE - NOT PRODUCTION DATA'));
    expect(regression, contains(r'for ($page = 1; $page <= 2; $page++)'));
    expect(regression, contains('qa-real-size-sample-receipt.jpg'));
    expect(regression, contains('qa-sample-evidence-two-pages.pdf'));
    expect(regression, contains("regression_expenses(\$filters, 'PETTY_CASH', 'CEH-PC-', 1)"));
    expect(regression, contains("regression_expenses(\$filters, 'PETTY_CASH', 'CEH-PC-', 11)"));
    expect(regression, contains("regression_expenses(\$filters, 'PETTY_CASH', 'CEH-PC-', 27)"));
    expect(regression, contains('REGRESSION_JPEG_NOT_REAL_SIZE'));
    expect(regression, contains(r"$id % 5 !== 0"));
  });

  test('dense registers reserve totals and avoid orphan continuation pages', () {
    final pdf = source('Server/report_pdf_common.php');
    expect(pdf, contains('reports_pdf_compact_journal_reference'));
    expect(pdf, contains('reports_pdf_paginate_rows'));
    expect(pdf, contains(r"count($pages[$lastIndex]) !== 1"));
    expect(pdf, contains(r'reports_pdf_table_header($pdf, $columns)'));
    expect(pdf, contains("188 - \$pdf->GetY(), 167, 25"));
  });

  test('report PDF dates use CEH presentation without changing API filters',
      () {
    final pdf = source('Server/report_pdf_common.php');
    expect(pdf, contains("'DD-MM-YYYY'=>'d-m-Y'"));
    expect(pdf, contains('DateTimeZone'));
    final reports = source('Server/reports_common.php');
    expect(reports, contains("'date_from'=>\$dateFrom"));
    expect(reports, contains('accounts_date'));
  });

  test('report endpoints are authenticated Admin-only GET operations', () {
    for (final path in [
      'Server/accounts_overview.php',
      'Server/petty_cash_report.php',
      'Server/expense_report.php',
      'Server/receivables_report.php',
      'Server/petty_cash_audit_pack.php',
      'Server/expense_audit_pack.php',
      'Server/receivables_report_pdf.php',
    ]) {
      final contents = source(path);
      expect(contents, contains('billing_require_admin()'));
      expect(contents, contains("production_require_method('GET')"));
      expect(contents, isNot(contains('INSERT ')));
      expect(contents, isNot(contains('UPDATE ')));
      expect(contents, isNot(contains('DELETE ')));
    }
  });

  test('monochrome corporate palette preserves semantic status colours', () {
    final theme = CehTheme.light();
    expect(CehTheme.ink, const Color(0xFF121212));
    expect(CehTheme.text, const Color(0xFF141414));
    expect(theme.colorScheme.primary, CehTheme.ink);
    expect(theme.colorScheme.surface, Colors.white);
    expect(theme.colorScheme.outline, CehTheme.border);
    expect(theme.scaffoldBackgroundColor, CehTheme.background);
    expect(theme.colorScheme.error, isNot(CehTheme.ink));
    final widgets = source('lib/widgets/accounts_widgets.dart');
    expect(widgets, contains('Color(0xFFE3F4E8)'));
    expect(widgets, contains('Color(0xFFFFF0D7)'));
    expect(widgets, contains('Color(0xFFFFE3E3)'));
  });

  test('shared accounting PDFs retain the approved corrected-preview palette',
      () {
    final pdf = source('Server/report_pdf_common.php');
    expect(pdf, contains('const REPORT_PDF_INK = [18, 18, 18];'));
    expect(pdf, contains('const REPORT_PDF_TEXT = [20, 20, 20];'));
    expect(pdf, contains('const REPORT_PDF_SECONDARY = [75, 75, 75];'));
    expect(pdf, contains('const REPORT_PDF_BORDER = [190, 190, 190];'));
    expect(pdf, contains('const REPORT_PDF_PANEL = [245, 245, 245];'));
    expect(pdf, contains('const REPORT_PDF_ALT = [250, 250, 250];'));
    expect(pdf, contains('SetFillColor(...REPORT_PDF_INK)'));
    expect(pdf, contains('SetTextColor(255, 255, 255)'));
    expect(pdf, isNot(contains('Powered by TCPDF')));
  });

  test('legacy petty cash and evidence types remain supported', () {
    final reports = source('Server/reports_common.php');
    expect(reports, contains("line_model_version']===0"));
    final pdf = source('Server/report_pdf_common.php');
    expect(pdf, contains("'image/jpeg', 'image/png'"));
    expect(pdf, contains("'application/pdf'"));
  });
}
