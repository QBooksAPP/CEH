import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final summary = source('Server/petty_cash_summary.php');
  final common = source('Server/accounts_common.php');
  final history = source('Server/petty_cash_transactions.php');
  final ui = source('lib/screens/accounts/accounts_live_screens.dart');

  test('monthly Received includes only posted funding in current month', () {
    expect(summary, contains('f.funding_date>=?'));
    expect(summary, contains('f.funding_date<?'));
    expect(summary, contains("j.status='POSTED'"));
    expect(summary, contains("modify('first day of next month')"));
  });

  test('monthly Accounted includes only effective spending in month', () {
    expect(summary, contains('e.expense_date>=?'));
    expect(summary, contains('e.expense_date<?'));
    expect(summary, contains("e.status IN ('APPROVED','VOIDED')"));
    expect(summary, contains("j.status='POSTED'"));
  });

  test('previous-month transactions remain in lifetime history', () {
    expect(history, contains('qbook_petty_cash_fundings'));
    expect(history, contains('qbook_petty_cash_expenses'));
    expect(history, isNot(contains('CURRENT_DATE')));
    expect(history, isNot(contains('funding_date>=?')));
  });

  test('changing calendar month never changes Current Balance', () {
    expect(summary, contains('accounts_custodian_balance'));
    expect(common, contains(r'$balanceMinor = $fundedMinor - $accountedMinor'));
    expect(common, isNot(contains("first day of next month")));
    expect(ui, contains("'Current Balance'"));
  });

  test('voided expenses do not inflate effective monthly spending', () {
    expect(summary, contains("j.id=e.journal_id AND j.status='POSTED'"));
    expect(common, contains("SET status='REVERSED'"));
  });

  test('reclassification does not change monthly amount spent', () {
    expect(
        summary, isNot(contains('qbook_petty_cash_expense_reclassifications')));
    expect(summary, contains('SUM(e.amount)'));
  });

  test('Pending Approval remains current rather than monthly', () {
    expect(common, contains("status IN ('SUBMITTED','CORRECTION_REQUIRED')"));
    expect(common, isNot(contains('submitted_at>=?')));
    expect(ui, contains("'Pending Approval'"));
  });

  test('Total Petty Cash Outstanding remains effective current balance', () {
    expect(summary, contains("total_petty_cash_outstanding"));
    expect(summary,
        contains("\$total+=accounts_money_minor(\$balance['balance']"));
    expect(ui, contains('TOTAL PETTY CASH OUTSTANDING'));
    expect(summary, contains('c.is_active=1 AND u.is_active=1'));
  });
}
