import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ceh/screens/accounts/accounts_live_screens.dart';

String source(String path) => File(path).readAsStringSync();

String? summarize(List<String?> values) {
  if (values.isEmpty) return null;
  String? common;
  var allocated = false;
  var unallocated = false;
  for (final raw in values) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      unallocated = true;
    } else if (!allocated) {
      common = value;
      allocated = true;
    } else if (common != value) {
      return 'Multiple allocations';
    }
  }
  if (allocated && unallocated) return 'Multiple allocations';
  return allocated ? common : null;
}

void main() {
  final common = source('Server/accounts_common.php');
  final register = source('Server/expenses.php');
  final petty = source('Server/petty_cash_expenses.php');
  final pettyReview = source('Server/petty_cash_expense_review.php');
  final generalReview = source('Server/general_expense_review.php');

  test('each expense dimension uses the approved summary semantics', () {
    expect(summarize(['ABC Construction']), 'ABC Construction');
    expect(summarize(['ABC Construction', 'ABC Construction']),
        'ABC Construction');
    expect(summarize([null, null]), isNull);
    expect(summarize(['ABC Construction', 'Another Client']),
        'Multiple allocations');
    expect(summarize(['ABC Construction', null]), 'Multiple allocations');

    final client = summarize(['ABC Construction', 'ABC Construction']);
    final project = summarize(['Epe', 'Badagry']);
    final equipment = summarize(['307', '307']);
    expect([client, project, equipment],
        ['ABC Construction', 'Multiple allocations', '307']);
  });

  test('production reference fixtures derive their proven summaries', () {
    expect([
      summarize(['ABC Construction']),
      summarize(['Epe']),
      summarize([null]),
    ], [
      'ABC Construction',
      'Epe',
      null
    ], reason: 'CEH-PC-000010');
    for (final reference in ['CEH-EX-000006', 'CEH-EX-000007']) {
      expect([
        summarize(['ABC Construction', 'ABC Construction']),
        summarize(['Epe', 'Epe']),
        summarize(['307', '307']),
      ], [
        'ABC Construction',
        'Epe',
        '307'
      ], reason: reference);
    }
  });

  test('server endpoints share line-derived summaries and keep legacy headers',
      () {
    expect(common, contains('accounts_expense_allocation_summary'));
    expect(common, contains("return 'Multiple allocations'"));
    expect(register, contains('accounts_apply_expense_allocation_summary'));
    expect(register, isNot(contains("\$row['client_name']=null")));
    expect(register, contains("legacy_client_name"));
    expect(register, contains("line_model_version']??1)===0"));
    expect(petty, contains("line_model_version']!==0"));
    expect(petty, contains('accounts_apply_expense_allocation_summary'));
    expect(petty, contains("line_model_version']===0"));
  });

  test('posted expense debits retain dimensions while asset credits do not',
      () {
    for (final review in [pettyReview, generalReview]) {
      expect(review, contains("'client_id'=>\$line['client_id']"));
      expect(review, contains("'project_id'=>\$line['project_id']"));
      expect(review, contains("'mixer_id'=>\$line['mixer_id']"));
    }
    expect(
        pettyReview,
        contains(
            "'account_id'=>\$petty,'debit_minor'=>0,'credit_minor'=>\$minor,'custodian_user_id'"));
    expect(
        generalReview,
        contains(
            "'ledger_account_id'],'debit_minor'=>0,'credit_minor'=>\$header,'description'"));
  });

  test('PETTY_CASH has a business-readable display label', () {
    expect(accountsExpenseFilterLabel('PETTY_CASH'), 'Petty Cash');
    expect(accountsExpenseFilterLabel('BANK'), 'Bank');
  });

  testWidgets('full original journal reference is accessible from compact row',
      (tester) async {
    const reference = 'CEH-JRN-20260823150336-01758BBE';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AccountsOriginalJournalRow(reference)),
    ));
    expect(find.text('Original Journal'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.text(reference), findsNothing);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text(reference), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });
}
