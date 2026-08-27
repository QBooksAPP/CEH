import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File('Server/migration_v1_17_invoice_company_snapshots.sql')
      .readAsStringSync();
  final issue = File('Server/invoice_issue.php').readAsStringSync();
  final pdf = File('Server/invoice_pdf.php').readAsStringSync();
  final save = File('Server/invoice_save.php').readAsStringSync();

  test('v1.17 adds only nullable immutable company snapshot columns', () {
    expect(migration, contains('ALTER TABLE qbook_invoices'));
    for (final field in [
      'company_legal_name_snapshot',
      'company_address_snapshot',
      'tax_identifier_snapshot',
      'payment_bank_details_snapshot',
    ]) {
      expect(migration, contains('ADD COLUMN $field'));
      expect(migration, contains('$field VARCHAR'));
      expect(migration, contains('NULL'));
    }
    expect(migration, isNot(contains('UPDATE qbook_invoices')));
    expect(migration, isNot(contains('INSERT INTO')));
    expect(migration, isNot(contains('DELETE FROM')));
    expect(migration, isNot(contains('DROP ')));
    expect(migration, isNot(contains('CASCADE')));
  });

  test('Issue locks settings and snapshots them in the posting transaction',
      () {
    expect(issue,
        contains('SELECT * FROM qbook_invoice_settings WHERE id=1 FOR UPDATE'));
    expect(issue, contains('INVOICE_SETTINGS_INCOMPLETE'));
    expect(issue, contains('INVOICE_TERMS_REQUIRED'));
    expect(issue, contains('company_legal_name_snapshot=?'));
    expect(issue, contains('company_address_snapshot=?'));
    expect(issue, contains('tax_identifier_snapshot=?'));
    expect(issue, contains('payment_bank_details_snapshot=?'));
    expect(issue, contains("WHERE id=? AND status='DRAFT'"));
    expect(issue, contains('accounts_post_journal'));
    expect(issue, contains('issued_company_settings_snapshotted'));
  });

  test('draft save remains journal-free and does not fabricate snapshots', () {
    expect(save, contains('INVOICE_DRAFT_SAVED'));
    expect(save, isNot(contains('accounts_post_journal')));
    expect(save, isNot(contains('company_legal_name_snapshot')));
    expect(save, contains("if(\$old['status']!=='DRAFT')"));
  });

  test('historical issued PDF never reads mutable Billing Settings', () {
    expect(pdf, isNot(contains('qbook_invoice_settings')));
    expect(pdf, contains('company_legal_name_snapshot'));
    expect(pdf, contains('company_address_snapshot'));
    expect(pdf, contains('tax_identifier_snapshot'));
    expect(pdf, contains('payment_bank_details_snapshot'));
    expect(pdf, contains('INVOICE_SETTINGS_SNAPSHOT_MISSING'));
    expect(pdf, contains('INVOICE_TERMS_SNAPSHOT_MISSING'));
  });

  test('professional PDF uses approved logo and authenticated access', () {
    expect(pdf, contains('billing_require_admin()'));
    expect(pdf, contains("__DIR__ . '/assets/ceh_logo.png'"));
    expect(pdf, contains('embedLogo(\$logoPng)'));
    expect(pdf, contains("'INVOICE'"));
    expect(pdf, contains("'PAYMENT DETAILS'"));
    expect(pdf, contains("'TERMS'"));
    expect(pdf, contains("'TOTAL'"));
    expect(pdf, contains("'Content-Type: application/pdf'"));
    expect(pdf, contains("'Cache-Control: private, no-store"));
  });

  test('invoice PDF uses the approved monochrome CEH document palette', () {
    expect(pdf, contains(r'$primary = [18, 18, 18]'));
    expect(pdf, contains(r'$ink = [20, 20, 20]'));
    expect(pdf, contains(r'$secondary = [75, 75, 75]'));
    expect(pdf, contains(r'$border = [190, 190, 190]'));
    expect(pdf, contains(r'$pale = [245, 245, 245]'));
    expect(pdf, contains(r'$background = [250, 250, 250]'));
    expect(pdf, contains(r'$this->tcpdflink = false'));
    expect(pdf, contains("'Invoice lines (continued)'"));
    expect(pdf, contains("'Invoice summary'"));
  });

  test('invoice PDF remains an authenticated read-only renderer', () {
    expect(pdf, contains('billing_require_admin()'));
    expect(pdf, contains("production_require_method('GET')"));
    expect(
      RegExp(r'\b(INSERT|UPDATE|DELETE|REPLACE|ALTER|DROP|TRUNCATE)\b')
          .hasMatch(pdf),
      isFalse,
    );
  });

  test('VAT stays separate and line values use quantity rate and net', () {
    expect(pdf, contains("'QUANTITY'"));
    expect(pdf, contains("'RATE'"));
    expect(pdf, contains("'NET'"));
    expect(pdf, contains("'VAT'"));
    expect(pdf, contains("\$line['net_amount']"));
    expect(pdf, contains("\$line['vat_amount']"));
    expect(pdf, contains("\$invoice['net_amount']"));
    expect(pdf, contains("\$invoice['vat_amount']"));
    expect(pdf, contains("\$invoice['total_amount']"));
    expect(pdf, contains("return 'm³'"));
  });

  test('multi-line dimensions and long content wrap across pages', () {
    expect(pdf, contains('foreach (\$lines as \$index => \$line)'));
    expect(pdf, contains("\$line['project_snapshot']"));
    expect(pdf, contains("\$line['mixer_snapshot']"));
    expect(pdf, contains('getStringHeight(\$columns[\$cellIndex][1] - 3'));
    expect(pdf, contains('MultiCell(\$width, \$rowHeight'));
    expect(pdf, contains('MultiCell(105, 4.3'));
    expect(pdf, contains('MultiCell(180, 5'));
    expect(pdf, contains('if (\$pdf->GetY() + \$rowHeight > 242)'));
    expect(pdf, contains('\$pdf->AddPage()'));
  });
}
