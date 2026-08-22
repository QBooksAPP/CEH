import 'dart:io';

import 'package:ceh/core/accounts_formatters.dart';
import 'package:ceh/models/accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final migration = source('Server/migration_v1_11_accounts_phase1_1.sql');
  final create = source('Server/petty_cash_expense_create.php');
  final update = source('Server/petty_cash_expense_update.php');
  final funding = source('Server/petty_cash_fund.php');
  final consolidated = source('Server/expenses.php');
  final common = source('Server/accounts_common.php');
  final liveUi = source('lib/screens/accounts/accounts_live_screens.dart');

  test('Accounts dates display DD-MM-YYYY and retain canonical API date', () {
    expect(displayAccountsDate('2026-08-22'), '22-08-2026');
    expect(canonicalAccountsDate(DateTime(2026, 8, 22)), '2026-08-22');
    expect(parseCanonicalAccountsDate('2026-08-22'), DateTime(2026, 8, 22));
    expect(liveUi, contains("'expense_date': _date"));
    expect(liveUi, contains("'funding_date': _date"));
  });

  testWidgets('new Accounts date picker defaults to today', (tester) async {
    String? canonical;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountsDatePickerField(
          onChanged: (value) => canonical = value,
        ),
      ),
    ));
    await tester.pump();
    final today = canonicalAccountsDate(DateTime.now());
    expect(canonical, today);
    expect(find.text(displayAccountsDate(today)), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
  });

  test('NGN formatting uses separators and two decimal places', () {
    expect(formatNgn(30000), '₦30,000.00');
    expect(formatNgn(1200000.5), '₦1,200,000.50');
    expect(parseNgnInput('1,200,000.50'), 1200000.5);
  });

  test('petty cash reference uses an independent concurrent-safe sequence', () {
    expect(migration,
        contains('CREATE TABLE qbook_petty_cash_expense_references'));
    expect(migration,
        contains('reference_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT'));
    expect(migration,
        contains('UNIQUE KEY uq_petty_cash_expense_reference_expense'));
    expect(migration, contains('ON DELETE RESTRICT'));
    expect(migration, isNot(contains('INSERT INTO')),
        reason: 'historical records are not silently renumbered');
    expect(create, contains('qbook_petty_cash_expense_references(expense_id)'));
    expect(create, contains("'reference_no'=>\$reference"));
    expect(common, contains("'CEH-PC-' . str_pad"));
  });

  test('petty cash reference is not editable or reusable through APIs', () {
    expect(update, isNot(contains('reference_no')));
    final php = Directory('Server')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.php'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(php, isNot(contains('UPDATE qbook_petty_cash_expense_references')));
    expect(php,
        isNot(contains('DELETE FROM qbook_petty_cash_expense_references')));
  });

  test('funding retains Zenith reference and has no CEH-PF reference', () {
    expect(funding, contains("\$input['bank_reference']"));
    expect(funding, contains("'bank_reference'=>\$reference"));
    expect(funding, isNot(contains('CEH-PF')));
    expect(create, isNot(contains('bank_reference')));
  });

  test('petty cash lifecycle appears in consolidated read model once', () {
    expect(consolidated, contains('e.status AS lifecycle_status'));
    expect(consolidated, contains('LEFT JOIN qbook_financial_journals'));
    expect(consolidated, contains("'PETTY_CASH' AS source_type"));
    expect(consolidated, contains('evidence_count'));
    expect(consolidated, isNot(contains('accounts_post_journal')));
    expect(consolidated, isNot(contains('INSERT INTO')));
    expect(consolidated, isNot(contains('UPDATE ')));
  });

  test('consolidated model keeps amounts numeric and exposes dimensions', () {
    final expense = ConsolidatedExpense.fromJson({
      'reference_no': 'CEH-PC-000001',
      'expense_date': '2026-08-22',
      'amount': '30000.00',
      'category': 'Diesel',
      'supplier_paid_to': 'TotalEnergies',
      'description': 'Diesel',
      'client_name': 'ABC Construction',
      'project_name': 'Badagry',
      'mixer_code': '307',
      'source_type': 'PETTY_CASH',
      'source_name': 'Segun',
      'posting_status': 'APPROVED / POSTED',
      'lifecycle_status': 'APPROVED',
      'evidence_count': '1',
    });
    expect(expense.amount, 30000);
    expect(expense.reference, 'CEH-PC-000001');
    expect(expense.hasEvidence, isTrue);
    expect(expense.lifecycleStatus, 'APPROVED');
  });
}
