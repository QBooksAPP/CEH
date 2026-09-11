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
      'bank_payment_common.php',
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
  test('retired statement receipt endpoint rejects without consuming a row', () {
    final legacy = source('customer_receipt_from_statement.php');
    expect(legacy, contains('billing_require_admin()'));
    expect(legacy, contains("production_require_method('POST')"));
    expect(legacy, contains(
        "accounts_fail('USE_STATEMENT_CLIENT_PAYMENT_WORKFLOW',409)"));
    for (final forbidden in [
      'production_db(',
      'bank_row_available(',
      'bank_payment_draft(',
      'customer_payment_post(',
      'accounts_post_journal(',
      '->prepare(',
      '->exec(',
    ]) {
      expect(legacy, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(RegExp(r'\b(INSERT|UPDATE|DELETE|REPLACE)\s', caseSensitive: false)
        .hasMatch(legacy), isFalse);
  });
  test('payment and refund reservations use the same exclusive ownership guard',
      () {
    final payment = source('bank_payment_common.php');
    final refund = source('general_expense_refunds_common.php');
    final guard = source('bank_row_usage.php');
    expect(source('bank_client_payment.php'), contains('billing_require_admin()'));
    expect(payment, contains('bank_ownership_transaction('));
    expect(payment, contains('FOR UPDATE'));
    expect(payment, contains('bank_row_available(\$db,\$rowId)'));
    expect(payment, contains("'CUSTOMER_RECEIPT',(int)\$receipt['id']"));
    expect(refund, contains('bank_ownership_transaction('));
    expect(refund, contains('bank_row_available(\$db,\$rowId)'));
    expect(guard, contains('BANK_ROW_USED_AS_REFUND'));
    expect(guard, contains('BANK_ROW_USED_AS_RECEIPT'));
    expect(guard, contains('function bank_payment_active_owner_sql('));
    expect(guard, contains('bank_payment_active_owner_sql()'));
    expect(refund, contains("bank_payment_active_owner_sql('cr')"));
    final migration = source('migration_v1_25_bank_payment_reservation.sql');
    expect(migration, contains('active_statement_row_id'));
    expect(migration, contains('UNIQUE'));
  });
  test('ordinary payment entry remains separate from statement draft creation',
      () {
    final save = source('customer_receipt_save.php');
    final endpoint = source('customer_receipt_post.php');
    final posting = source('customer_payment_post_common.php');
    expect(save, contains('INSERT INTO qbook_customer_receipts'));
    expect(save, isNot(contains('USE_STATEMENT_CLIENT_PAYMENT_WORKFLOW')));
    expect(save, isNot(contains('bank_payment_draft(')));
    expect(endpoint, contains('customer_payment_post(production_db(),\$user,\$input)'));
    expect(posting, contains("\$backed = \$receipt['statement_row_id'] !== null"));
    expect(posting, contains('if (\$backed)'));
    expect(posting, contains('\$cashAllocated += \$cashAmount'));
    expect(posting, contains('\$unallocatedCash = \$cash - \$cashAllocated'));
  });
}
