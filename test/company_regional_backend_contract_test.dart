import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String name) => File('Server/$name').readAsStringSync();

  test('v1.21 is incremental, restrictive, and preserves legacy documents', () {
    final sql = source('migration_v1_21_company_regional_settings.sql');
    expect(sql, contains('CREATE TABLE qbook_companies'));
    expect(
        sql, contains("VALUES (1,'CEH','Concrete Equipment Hire Limited',1)"));
    expect(sql,
        contains("VALUES (1,'Africa/Lagos','DD-MM-YYYY','24_HOUR','NGN')"));
    expect(sql, contains('ON DELETE RESTRICT'));
    expect(sql, contains('currency_code_snapshot CHAR(3) NULL'));
    expect(sql, contains('intentionally not backfilled'));
    expect(sql.toUpperCase(), isNot(contains('CASCADE')));
    expect(sql.toUpperCase(), isNot(contains('TRUNCATE')));
    expect(sql.toUpperCase(), isNot(contains('DROP TABLE')));
  });

  test('immutable commercial documents snapshot currency at lifecycle boundary',
      () {
    expect(source('invoice_issue.php'), contains('currency_code_snapshot=?'));
    expect(source('estimate_send.php'), contains('currency_code_snapshot=?'));
    expect(source('customer_receipt_post.php'),
        contains('currency_code_snapshot=?'));
  });

  test('document renderers use snapshot with explicit legacy NGN fallback', () {
    final common = source('company_regional_common.php');
    expect(common, contains("if(\$code==='') return 'NGN'"));
    for (final file in [
      'invoice_pdf.php',
      'estimate_pdf.php',
      'client_payment_pdf.php'
    ]) {
      expect(source(file), contains('currency_code_snapshot'));
      expect(source(file), contains('company_document_currency'));
    }
  });

  test('base currency protection and settings audit are server authoritative',
      () {
    final update = source('company_regional_settings_update.php');
    expect(
        update, contains('BASE_CURRENCY_CHANGE_REQUIRES_CONTROLLED_MIGRATION'));
    expect(update, contains('qbook_company_regional_settings_audit'));
    expect(update, contains('DateTimeZone::listIdentifiers()'));
  });

  test('operational reports use active company regional configuration', () {
    final report = source('report_pdf_common.php');
    expect(report, contains('qbook_company_regional_settings'));
    expect(report, contains("\$GLOBALS['ceh_report_currency']"));
    expect(report, contains('company_money'));
  });
}
