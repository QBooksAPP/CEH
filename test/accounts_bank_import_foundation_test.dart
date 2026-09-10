import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String name) => File('Server/$name').readAsStringSync();
  test('statement evidence endpoints remain ADMIN only', () {
    for (final name in [
      'bank_statement_upload.php',
      'bank_statement_preview.php',
      'bank_statement_import.php',
      'bank_statement_document.php',
    ]) {
      expect(source(name), contains("qbook_require_role(\$user,['ADMIN'])"));
      expect(source(name), contains('qbook_require_user()'));
    }
  });
  test('server file pipeline does not post journals or accept supplied rows',
      () {
    final common = source('bank_import_common.php');
    expect(common, isNot(contains('accounts_post_journal')));
    expect(common, contains('document_data'));
    expect(common, contains('confirmation_sha256'));
    expect(common, contains('STATEMENT_INTEGRITY_FAILED'));
    expect(source('bank_statement_import.php'),
        isNot(contains("\$input['rows']")));
  });
  test('migration replaces content uniqueness with physical-row uniqueness',
      () {
    final migration = source('migration_v1_23_bank_import_foundation.sql');
    expect(migration, contains('DROP INDEX uq_bank_statement_fingerprint'));
    expect(
        migration,
        contains(
            'uq_bank_physical_row(import_batch_id,source_sheet,source_row)'));
    expect(migration, contains('occurrence_number'));
    expect(migration, isNot(contains('UPDATE qbook_')));
  });
  test('existing row consumers share authoritative ownership guard', () {
    for (final name in [
      'bank_reconcile_common.php',
      'general_expense_create.php',
      'general_expense_update.php',
      'general_expense_review.php',
      'general_expense_refunds_common.php',
      'customer_receipt_from_statement.php',
    ]) {
      expect(source(name), contains('bank_row_available('));
      final dependencies = source(name) +
          (source(name).contains('bank_expense_lock.php')
              ? source('bank_expense_lock.php')
              : '');
      expect(dependencies, contains('bank_row_usage.php'));
    }
    expect(source('bank_row_usage.php'), contains('FOR UPDATE'));
    expect(source('bank_row_usage.php'), contains('inTransaction()'));
  });
}
