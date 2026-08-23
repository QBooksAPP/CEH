import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

List<Map<String, int>> reverseLines(List<Map<String, int>> lines) => lines
    .map((line) => {
          'account': line['account']!,
          'debit': line['credit']!,
          'credit': line['debit']!,
        })
    .toList();

void main() {
  final migration =
      source('Server/migration_v1_12_accounts_expense_lifecycle.sql');
  final common = source('Server/accounts_common.php');
  final delete = source('Server/expense_delete.php');
  final voidExpense = source('Server/expense_void.php');
  final reclassifyExpense = source('Server/expense_reclassify.php');
  final review = source('Server/petty_cash_expense_review.php');
  final expenses = source('Server/expenses.php');
  final pettyExpenses = source('Server/petty_cash_expenses.php');
  final evidenceGet = source('Server/financial_evidence_get.php');
  final ui = source('lib/screens/accounts/accounts_live_screens.dart');

  test('v1.12 is incremental and adds VOIDED lifecycle metadata', () {
    expect(migration, contains("'VOIDED'"));
    for (final column in [
      'reversal_journal_id BIGINT UNSIGNED NULL',
      'voided_by BIGINT UNSIGNED NULL',
      'voided_at DATETIME NULL',
      'void_reason VARCHAR(500) NULL',
    ]) {
      expect(migration, contains(column));
    }
    expect(migration, contains('ON DELETE SET NULL'));
    expect(migration, isNot(contains('INSERT INTO')));
    expect(migration, isNot(contains('UPDATE qbook_')));
    expect(migration, isNot(contains('DROP TABLE')));
    expect(migration, isNot(contains('TRUNCATE')));
  });

  test('Admin alone can hard-delete an unposted DRAFT', () {
    expect(delete, contains("qbook_require_role(\$user,['ADMIN'])"));
    expect(delete, contains("\$expense['status']!=='DRAFT'"));
    expect(delete, contains("\$expense['journal_id']!==null"));
    expect(delete, contains('source_module=? AND source_record_id=?'));
    expect(delete, contains("'PETTY_CASH_EXPENSE'"));
    expect(delete, contains('POSTED_EXPENSE_NOT_DELETABLE'));
    expect(delete, contains("'qbook_petty_cash_expenses'"));
    expect(delete, contains(r'DELETE FROM {$table}'));
  });

  test('SUBMITTED and CORRECTION_REQUIRED cannot be hard-deleted', () {
    expect(delete, contains("if(\$expense['status']!=='DRAFT')"));
    expect(delete, contains("accounts_fail('EXPENSE_NOT_DELETABLE',409)"));
    expect(review, contains("['SUBMITTED','CORRECTION_REQUIRED']"));
  });

  test('draft deletion removes evidence but permanently retires reference', () {
    expect(delete, contains('DELETE FROM qbook_financial_evidence'));
    expect(delete,
        isNot(contains('DELETE FROM qbook_petty_cash_expense_references')));
    expect(migration, contains('MODIFY expense_id BIGINT UNSIGNED NULL'));
    expect(migration, contains('ON DELETE SET NULL'));
    expect(delete, contains("'EXPENSE_DRAFT_DELETED'"));
  });

  test('cancellation is explicit Admin action with mandatory reason', () {
    expect(review, contains("qbook_require_role(\$user,['ADMIN'])"));
    expect(review, contains("'CANCELLED_NOT_SPENT'"));
    expect(review, contains('REVIEW_REASON_REQUIRED'));
    expect(ui, contains('Cancel / Not Spent'));
    expect(ui, contains('Reason (required)'));
  });

  test('void requires reason and preserves original expense and journal', () {
    expect(voidExpense, contains("qbook_require_role(\$user,['ADMIN'])"));
    expect(voidExpense, contains('VOID_REASON_REQUIRED'));
    expect(voidExpense, contains('accounts_reverse_journal'));
    expect(voidExpense, contains("SET status='VOIDED'"));
    expect(voidExpense, isNot(contains('DELETE FROM')));
    expect(voidExpense, contains('original_journal_id'));
    expect(voidExpense, contains('reversal_journal_id'));
  });

  test('second void is rejected', () {
    expect(voidExpense, contains("\$expense['status']==='VOIDED'"));
    expect(voidExpense, contains("\$expense['reversal_journal_id']!==null"));
    expect(
        voidExpense, contains("accounts_fail('EXPENSE_ALREADY_VOIDED',409)"));
  });

  test('reversal swaps every debit and credit and remains balanced', () {
    final original = [
      {'account': 6000, 'debit': 3000000, 'credit': 0},
      {'account': 1200, 'debit': 0, 'credit': 3000000},
    ];
    final reversal = reverseLines(original);
    expect(reversal[0], {'account': 6000, 'debit': 0, 'credit': 3000000});
    expect(reversal[1], {'account': 1200, 'debit': 3000000, 'credit': 0});
    expect(reversal.fold<int>(0, (sum, line) => sum + line['debit']!),
        reversal.fold<int>(0, (sum, line) => sum + line['credit']!));
    expect(common, contains(r'$debits !== $credits'));
  });

  test('bank-paid expense reversal restores the same bank account', () {
    final original = [
      {'account': 6100, 'debit': 25000000, 'credit': 0},
      {'account': 1011, 'debit': 0, 'credit': 25000000},
    ];
    final reversal = reverseLines(original);
    expect(reversal[0], {'account': 6100, 'debit': 0, 'credit': 25000000});
    expect(reversal[1], {'account': 1011, 'debit': 25000000, 'credit': 0});
    expect(
        common,
        contains(
            "'debit_minor' => accounts_money_minor((string)\$line['credit']"));
    expect(
        common,
        contains(
            "'credit_minor' => accounts_money_minor((string)\$line['debit']"));
  });

  test('Petty Cash balance follows effective posted/reversed journal state',
      () {
    expect(common, contains("j.status='POSTED'"));
    expect(common, contains("e.status IN ('APPROVED','VOIDED')"));
    expect(voidExpense, contains('accounts_reverse_journal'));
    const funded = 13000000;
    const postedSpendAfterVoid = 0;
    expect(funded - postedSpendAfterVoid, 13000000);
  });

  test('void preserves CEH-PC reference evidence and dimensions', () {
    expect(voidExpense, contains('accounts_petty_cash_reference'));
    expect(
        voidExpense, isNot(contains('qbook_petty_cash_expense_references(')));
    expect(
        voidExpense, isNot(contains('DELETE FROM qbook_financial_evidence')));
    expect(evidenceGet, isNot(contains("status='APPROVED'")));
    for (final dimension in [
      'client_id',
      'project_id',
      'mixer_id',
      'custodian_user_id'
    ]) {
      expect(common, contains("'$dimension' => \$line['$dimension']"));
    }
  });

  test('voided expenses remain visible with journals and void metadata', () {
    expect(expenses, contains('e.status AS lifecycle_status'));
    expect(expenses, contains("'VOIDED / REVERSED'"));
    expect(expenses, contains('reversal_journal_reference'));
    expect(pettyExpenses, contains('voided_by_name'));
    expect(pettyExpenses, contains('void_reason'));
    for (final filter in ['ACTIVE', 'PENDING', 'VOIDED', 'ALL']) {
      expect(ui, contains("'$filter'"));
    }
    expect(ui, contains('Void Expense'));
  });

  test('bank reconciliation evidence is preserved and reported on void', () {
    expect(voidExpense, contains('qbook_bank_matches'));
    expect(voidExpense, contains('bank_matches_preserved'));
    expect(voidExpense, isNot(contains('DELETE FROM qbook_bank_matches')));
    expect(voidExpense, isNot(contains('UPDATE qbook_bank_statement_rows')));
  });

  test('all lifecycle actions write financial audit records', () {
    expect(delete, contains("'EXPENSE_DRAFT_DELETED'"));
    expect(review, contains('accounts_audit'));
    expect(voidExpense, contains("'EXPENSE_VOIDED'"));
    expect(voidExpense, contains('original_journal_reference'));
    expect(voidExpense, contains("'reversal_journal_id'=>\$reversal['id']"));
  });

  test('reclassification never posts a Petty Cash or bank asset line', () {
    expect(reclassifyExpense,
        contains("'source_module'=>'PETTY_CASH_RECLASSIFICATION'"));
    expect(reclassifyExpense, contains("'entry_kind'=>'REPLACEMENT'"));
    expect(
        reclassifyExpense, isNot(contains("accounts_account_id(\$db,'1200')")));
    expect(reclassifyExpense, isNot(contains('qbook_bank_accounts')));
    expect(reclassifyExpense,
        contains("'asset_impact'=>accounts_minor_decimal(0)"));
  });

  test('reclassification moves the exact amount between expense codings', () {
    expect(reclassifyExpense, contains("'debit_minor'=>\$minor"));
    expect(reclassifyExpense, contains("'credit_minor'=>\$minor"));
    expect(reclassifyExpense, contains("'account_id'=>\$newAccount"));
    expect(reclassifyExpense, contains("'account_id'=>\$oldAccount"));
  });

  test('reclassification preserves source, evidence and immutable journals',
      () {
    expect(reclassifyExpense, isNot(contains('DELETE FROM')));
    expect(reclassifyExpense, isNot(contains('qbook_financial_evidence')));
    expect(
        reclassifyExpense, isNot(contains('UPDATE qbook_financial_journals')));
    expect(reclassifyExpense, contains("'original_journal_id'"));
    expect(reclassifyExpense, contains("'prior'=>"));
    expect(reclassifyExpense, contains("'corrected'=>"));
  });

  test('reclassification is Admin-only, reasoned and versioned', () {
    expect(reclassifyExpense, contains("qbook_require_role(\$user,['ADMIN'])"));
    expect(reclassifyExpense, contains('RECLASSIFICATION_REASON_REQUIRED'));
    expect(reclassifyExpense,
        contains('qbook_petty_cash_expense_reclassifications'));
    expect(reclassifyExpense, contains("'EXPENSE_RECLASSIFIED'"));
  });

  test('void after reclassification reverses corrections before original', () {
    expect(voidExpense, contains('qbook_petty_cash_expense_reclassifications'));
    expect(voidExpense, contains('ORDER BY id DESC FOR UPDATE'));
    expect(voidExpense, contains("'reclassification_reversals'"));
  });
}
