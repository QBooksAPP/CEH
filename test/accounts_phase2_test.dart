import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final migration = source('Server/migration_v1_13_shared_expense_lines.sql');
  final common = source('Server/accounts_common.php');
  final pettyCreate = source('Server/petty_cash_expense_create.php');
  final pettySubmit = source('Server/petty_cash_expense_submit.php');
  final pettyReview = source('Server/petty_cash_expense_review.php');
  final generalCreate = source('Server/general_expense_create.php');
  final generalSubmit = source('Server/general_expense_submit.php');
  final generalReview = source('Server/general_expense_review.php');
  final lineReclassify = source('Server/expense_line_reclassify.php');
  final voidExpense = source('Server/expense_void.php');
  final bankImport = source('Server/bank_statement_import.php');
  final bankReconcile = source('Server/bank_reconcile.php');
  final evidenceUpload = source('Server/financial_evidence_upload.php');
  final suppliers = source('Server/supplier_create.php');
  final register = source('Server/expenses.php');
  final ui = source('lib/screens/accounts/accounts_live_screens.dart');
  final generalUi =
      source('lib/screens/accounts/accounts_general_expense_screen.dart');

  test('v1.13 is incremental and keeps legacy petty rows without backfill', () {
    expect(migration, contains('line_model_version'));
    expect(migration, contains('DEFAULT 0'));
    expect(migration,
        isNot(contains('INSERT INTO qbook_petty_cash_expense_lines SELECT')));
    expect(
        migration,
        isNot(contains(
            'UPDATE qbook_petty_cash_expenses SET line_model_version')));
  });

  test('petty and general lines use strong concrete foreign keys', () {
    expect(migration, contains('CREATE TABLE qbook_petty_cash_expense_lines'));
    expect(migration, contains('CREATE TABLE qbook_general_expense_lines'));
    expect(migration, isNot(contains('source_type ENUM')));
    expect(migration, contains('REFERENCES qbook_petty_cash_expenses(id)'));
    expect(migration, contains('REFERENCES qbook_general_expenses(id)'));
  });

  test('server rejects header and line total mismatch', () {
    expect(common, contains('EXPENSE_LINE_TOTAL_MISMATCH'));
    expect(pettySubmit, contains('EXPENSE_LINE_TOTAL_MISMATCH'));
    expect(generalSubmit, contains('EXPENSE_LINE_TOTAL_MISMATCH'));
  });

  test('quantity and unit price remain optional but validate as a pair', () {
    expect(common, contains('QUANTITY_UNIT_PRICE_PAIR_REQUIRED'));
    expect(common, contains('LINE_QUANTITY_TOTAL_MISMATCH'));
    expect(migration, contains('quantity IS NULL AND unit_price IS NULL'));
  });

  test('new petty cash drafts use lines and reserve header once on submit', () {
    expect(pettyCreate, contains('line_model_version'));
    expect(pettyCreate, contains('qbook_petty_cash_expense_lines'));
    expect(pettyCreate, isNot(contains('accounts_custodian_balance')));
    expect(pettySubmit, contains("status='SUBMITTED'"));
    expect(pettySubmit, contains('_available_minor'));
  });

  test('petty approval posts each debit line and one petty cash credit', () {
    expect(pettyReview, contains(r'foreach($lines as $line)'));
    expect(pettyReview, contains(r"accounts_account_id($db,'1200')"));
    expect(pettyReview, contains(r"'credit_minor'=>$minor"));
    expect(pettyReview, contains('accounts_post_journal'));
  });

  test('general approval posts each debit line and one bank credit', () {
    expect(generalReview, contains(r'foreach($lines as $line)'));
    expect(
        generalReview, contains("'account_id'=>(int)\$e['ledger_account_id']"));
    expect(generalReview, contains("'credit_minor'=>\$header"));
    expect(generalReview, contains("'source_module'=>'GENERAL_EXPENSE'"));
  });

  test('CEH-EX references are independent concurrency-safe tombstones', () {
    expect(migration, contains('qbook_general_expense_references'));
    expect(migration,
        contains('reference_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT'));
    expect(migration, contains('ON DELETE SET NULL'));
    expect(common, contains("'CEH-EX-'"));
    expect(generalCreate, contains('qbook_general_expense_references'));
  });

  test('supplier creation is explicit and historical name is snapshotted', () {
    expect(suppliers, contains('SUPPLIER_NAME_OR_ALIAS_CONFLICT'));
    expect(suppliers, contains('canonical_name'));
    expect(generalCreate, contains('supplier_name_snapshot'));
    expect(bankImport, isNot(contains('INSERT INTO qbook_suppliers')));
  });

  test('optional bank reference and one-off payee rules are explicit', () {
    final reconcile = source('Server/bank_reconcile.php');
    final submit = source('Server/general_expense_submit.php');
    expect(generalCreate, contains("one_off_payee"));
    expect(generalCreate, contains("supplier_name_snapshot"));
    expect(submit, contains(r"$e['supplier_id']!==null"));
    expect(reconcile, contains('BANK_REFERENCE_MISMATCH'));
    expect(reconcile, contains(r"$rowReference!==''"));
    expect(reconcile, contains('narration_signal'));
    expect(generalCreate, isNot(contains('GENERATE_BANK_REFERENCE')));
  });

  test('supplier aliases are separate and fuzzy merge is absent', () {
    expect(migration, contains('CREATE TABLE qbook_supplier_aliases'));
    expect(migration, contains('uq_supplier_alias_normalized'));
    expect(suppliers.toLowerCase(), isNot(contains('levenshtein')));
  });

  test('line reclassification posts only expense-to-expense lines', () {
    expect(lineReclassify, contains("'asset_impact'=>'0.00'"));
    expect(lineReclassify, contains("'entry_kind'=>'REPLACEMENT'"));
    expect(lineReclassify, isNot(contains("accounts_account_id(\$db,'1200')")));
    expect(lineReclassify, isNot(contains('ledger_account_id')));
    expect(migration, contains('before_snapshot JSON'));
    expect(migration, contains('after_snapshot JSON'));
  });

  test('void unwinds line corrections newest first then original', () {
    final linePosition = voidExpense.indexOf('ORDER BY id DESC');
    final originalPosition = voidExpense.indexOf(
        "accounts_reverse_journal(\$db,\$user,(int)\$expense['journal_id']");
    expect(linePosition, greaterThanOrEqualTo(0));
    expect(originalPosition, greaterThan(linePosition));
    expect(voidExpense, contains('EXPENSE_ALREADY_VOIDED'));
  });

  test('bank void requires strict economic basis and preserves matches', () {
    expect(voidExpense, contains('BANK_VOID_BASIS_REQUIRED'));
    expect(voidExpense, contains('MATCHED_BANK_DEBIT_CANNOT_BE_VOIDED'));
    expect(voidExpense, contains('FULL_ACTUAL_REFUND_REQUIRED'));
    expect(voidExpense, contains('bank_matches_preserved'));
  });

  test('actual refunds are linked to immutable positive statement rows', () {
    expect(migration, contains('CREATE TABLE qbook_general_expense_refunds'));
    expect(migration, contains('REFERENCES qbook_bank_statement_rows(id)'));
    expect(voidExpense, contains("s.amount>0"));
  });

  test('statement matching suggests general expense without posting', () {
    expect(bankImport, contains("\$sourceType='GENERAL_EXPENSE'"));
    expect(
        bankImport, contains("status='APPROVED' AND journal_id IS NOT NULL"));
    expect(bankReconcile, contains("'GENERAL_EXPENSE'"));
    expect(bankReconcile, isNot(contains('accounts_post_journal')));
  });

  test('statement-first expense posts once then creates one match', () {
    expect(generalCreate, contains('created_from_statement_row_id'));
    expect(generalCreate, contains('EXPENSE_REQUIRES_BANK_DEBIT'));
    expect(generalReview, contains('qbook_bank_matches'));
    expect(migration, contains('uq_general_expense_statement_source'));
    expect(generalReview, contains("VALUES(?,'GENERAL_EXPENSE',?,?)"));
  });

  test('general evidence uses existing authenticated architecture', () {
    expect(evidenceUpload, contains("'GENERAL_EXPENSE'"));
    expect(evidenceUpload, contains("['DRAFT','CORRECTION_REQUIRED']"));
    expect(migration, isNot(contains('DROP TABLE qbook_financial_evidence')));
  });

  test('unified register includes both sources and their lines', () {
    expect(register, contains("'PETTY_CASH' AS source_type"));
    expect(register, contains("'BANK' AS source_type"));
    expect(register, contains('qbook_general_expense_lines'));
    expect(ui, contains("'PETTY_CASH'"));
    expect(ui, contains("'BANK'"));
  });

  test('Flutter exposes split-line and bank-expense workflows', () {
    expect(ui, contains('Add Expense Line'));
    expect(ui, contains('Create Expense from Statement'));
    expect(generalUi, contains('Bank-Paid Expense'));
    expect(generalUi, contains('Save Draft'));
    expect(generalUi, contains('Submit Expense'));
    expect(generalUi, contains('Create Supplier Inline'));
  });

  test('migration has no financial postings or destructive data rewrite', () {
    final upper = migration.toUpperCase();
    expect(upper, isNot(contains('INSERT INTO QBOOK_FINANCIAL_JOURNALS')));
    expect(upper, isNot(contains('DELETE FROM')));
    expect(upper, isNot(contains('TRUNCATE')));
    expect(upper, isNot(contains('DROP TABLE')));
    expect(upper, isNot(contains('ON DELETE CASCADE')));
    expect(upper, isNot(contains('INSERT INTO QBOOK_BANK_ACCOUNTS')));
  });
}
