import 'dart:io';

import 'package:ceh/screens/accounts/accounts_live_screens.dart';
import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

Map<String, dynamic> expense(String status, {int custodianId = 3}) => {
      'id': 1,
      'status': status,
      'custodian_user_id': custodianId,
    };

void main() {
  final ui = source('lib/screens/accounts/accounts_live_screens.dart');
  final dashboard = source('lib/screens/dashboard_screen.dart');
  final submit = source('Server/petty_cash_expense_submit.php');
  final update = source('Server/petty_cash_expense_update.php');
  final review = source('Server/petty_cash_expense_review.php');
  final expensesApi = source('Server/petty_cash_expenses.php');
  final chart = source('Server/accounts_chart.php');
  final common = source('Server/accounts_common.php');

  test('only SUBMITTED expenses enter Needs Approval', () {
    final rows = [expense('DRAFT'), expense('SUBMITTED'), expense('APPROVED')];
    final queue = pettyCashExpensesForSection(
        rows, PettyCashExpenseSection.needsApproval);

    expect(queue.map((row) => row['status']), ['SUBMITTED']);
    expect(pettyCashExpenseSection('DRAFT'),
        isNot(PettyCashExpenseSection.needsApproval));
    expect(pettyCashExpenseSection('APPROVED'),
        isNot(PettyCashExpenseSection.needsApproval));
  });

  test('DRAFT and CORRECTION_REQUIRED enter Drafts / Needs Correction', () {
    final rows = [
      expense('DRAFT'),
      expense('CORRECTION_REQUIRED'),
      expense('SUBMITTED'),
    ];
    final drafts =
        pettyCashExpensesForSection(rows, PettyCashExpenseSection.drafts);

    expect(
        drafts.map((row) => row['status']), ['DRAFT', 'CORRECTION_REQUIRED']);
  });

  test('APPROVED and CANCELLED_NOT_SPENT enter Transaction History', () {
    final rows = [
      expense('APPROVED'),
      expense('CANCELLED_NOT_SPENT'),
      expense('SUBMITTED'),
    ];
    final history =
        pettyCashExpensesForSection(rows, PettyCashExpenseSection.history);

    expect(history.map((row) => row['status']),
        ['APPROVED', 'CANCELLED_NOT_SPENT']);
  });

  test('approval moves a record from Needs Approval to History', () {
    expect(pettyCashExpenseSection('SUBMITTED'),
        PettyCashExpenseSection.needsApproval);
    expect(
        pettyCashExpenseSection('APPROVED'), PettyCashExpenseSection.history);
  });

  test('screen exposes the required workflow sections and actions', () {
    for (final label in [
      'Needs Approval',
      'No expenses awaiting approval',
      'Drafts / Needs Correction',
      'Transaction History',
      'Continue Draft',
      'Correct & Resubmit',
      'Submit Expense',
    ]) {
      expect(ui, contains(label));
    }
    expect(ui, isNot(contains('Expense approval queue')));
  });

  test('owner can update and submit an existing DRAFT', () {
    expect(ui, contains('updatePettyCashExpense'));
    expect(ui, contains('submitPettyCashExpense'));
    expect(update, contains("['DRAFT','CORRECTION_REQUIRED']"));
    expect(update, contains('accounts_can_access_custodian'));
    expect(submit, contains("SET status='SUBMITTED'"));
  });

  test('Admin and owner both receive draft management controls', () {
    expect(
      canManagePettyCashDraft(
          isAdmin: true, currentUserId: 1, custodianUserId: 3),
      isTrue,
    );
    expect(
      canManagePettyCashDraft(
          isAdmin: false, currentUserId: 3, custodianUserId: 3),
      isTrue,
    );
    expect(
      canManagePettyCashDraft(
          isAdmin: false, currentUserId: 4, custodianUserId: 3),
      isFalse,
    );
    expect(ui, contains('PettyCashExpenseSection.drafts && canManageDraft'));
  });

  test('draft edit form pre-populates category and evidence state', () {
    expect(ui, contains('initialValue: _account ?? accounts.first.id'));
    expect(ui, contains('Existing receipt attached'));
    for (final field in [
      "expense['expense_date']",
      "expense['amount']",
      "expense['supplier_paid_to']",
      "expense['description']",
      "expense['client_id']",
      "expense['project_id']",
      "expense['mixer_id']",
      "expense['no_receipt_reason']",
    ]) {
      expect(ui, contains(field));
    }
  });

  test('Admin cannot approve a DRAFT directly', () {
    expect(review, contains("if(\$e['status']!=='SUBMITTED')"));
    expect(review, contains("accounts_fail('EXPENSE_NOT_REVIEWABLE',409)"));
    expect(
        ui,
        contains(
            'section == PettyCashExpenseSection.needsApproval && isAdmin'));
  });

  test('submitting the exact available balance is allowed and fully reserved',
      () {
    const balance = 13000000;
    const pendingBefore = 0;
    const amount = 13000000;
    final availableBefore = balance - pendingBefore;
    final pendingAfter = pendingBefore + amount;
    final availableAfter = balance - pendingAfter;

    expect(amount, availableBefore);
    expect(pendingAfter, 13000000);
    expect(availableAfter, 0);
    expect(submit, contains(r'if($amount>$available)'));
    expect(submit, isNot(contains(r'if($amount>=$available)')));
  });

  test('overspending remains rejected server-side', () {
    expect(submit, contains("accounts_fail('INSUFFICIENT_PETTY_CASH',409)"));
    expect(update, contains("accounts_fail('INSUFFICIENT_PETTY_CASH',409)"));
  });

  test('CORRECTION_REQUIRED stays reserved and can be corrected/resubmitted',
      () {
    expect(common, contains("status IN ('SUBMITTED','CORRECTION_REQUIRED')"));
    expect(update, contains("\$old['status']==='CORRECTION_REQUIRED'"));
    expect(submit, contains("\$e['status']==='CORRECTION_REQUIRED'"));
    expect(submit, contains("SET status='SUBMITTED'"));
    expect(ui, contains("status == 'CORRECTION_REQUIRED'"));
    expect(ui, contains("'Correct & Resubmit'"));
  });

  test('pre-v1.11 Reference pending does not block legitimate submission', () {
    expect(ui, contains('Reference pending'));
    expect(submit, isNot(contains('reference_no')));
    expect(submit, isNot(contains('qbook_petty_cash_expense_references')));
  });

  test('custodian records remain isolated server-side', () {
    expect(expensesApi, contains("if(!\$admin)"));
    expect(expensesApi, contains("\$target=(int)\$user['id']"));
    expect(expensesApi, contains('WHERE e.custodian_user_id=?'));
    expect(submit, contains('accounts_can_access_custodian'));
    expect(update, contains('accounts_can_access_custodian'));
  });

  test('custodian UX is available without exposing the Admin Accounts area',
      () {
    expect(dashboard, contains("'t': 'Petty Cash'"));
    expect(ui, contains("isAdmin ? 'Custodian balances' : 'My Balance'"));
    expect(ui, contains("'My Drafts / Corrections'"));
    expect(ui, contains("'My Transaction History'"));
    expect(chart, contains('accounts_custodian'));
    expect(chart, contains("WHERE account_type='EXPENSE'"));
  });

  test('approval retains exactly-once balanced journal posting', () {
    expect(review, contains("if(\$e['journal_id']!==null)"));
    expect(review, contains("accounts_fail('SOURCE_ALREADY_POSTED',409)"));
    expect(review, contains('accounts_post_journal'));
    expect(review, contains("'debit_minor'=>\$minor"));
    expect(review, contains("'credit_minor'=>\$minor"));
    expect(review, contains("SET status='APPROVED',journal_id=?"));
  });
}
