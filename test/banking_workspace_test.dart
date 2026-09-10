import 'dart:async';
import 'dart:io';
import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/banking_workspace.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_banking_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const admin = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1, fullName: 'Admin', email: '', role: 'ADMIN', isActive: true));

class BankApi extends CehApiClient {
  final calls = <Map<String, Object>>[];
  bool fail = false, empty = false;
  Completer<BankingPage>? pending;
  @override
  Future<List<Map<String, dynamic>>> bankingAccounts(CehSession s) async =>
      empty
          ? []
          : [
              for (final id in [1, 2])
                {
                  'id': id,
                  'name': 'Account $id',
                  'bank_name': 'Bank $id',
                  'currency': 'NGN',
                  'current_balance': '100.00',
                  'statement_balance': '200.00',
                  'statement_date': '2026-08-31',
                  'masked_account_reference': '•••• 1234'
                }
            ];
  @override
  Future<BankingPage> bankingPage(CehSession s, int id,
      {int page = 1,
      bool imports = false,
      Map<String, String> filters = const {}}) async {
    calls.add({
      'bank': id,
      'page': page,
      'imports': imports,
      'filters': Map.of(filters)
    });
    if (fail) throw const ApiException('FAILED');
    if (pending != null) return pending!.future;
    return BankingPage.fromJson({
      'page': page,
      'total': 719,
      'has_more': page < 15,
      'summary': {
        'debit_count': 706,
        'credit_count': 13,
        'debit_total': '41851345.01',
        'credit_total': '33205837.50'
      },
      'transactions': [
        {
          'id': page,
          'bank_account_id': id,
          'transaction_date': '2026-08-31',
          'narration': 'Charge page $page',
          'amount': '-50.00',
          'usage_state': 'AVAILABLE'
        }
      ],
      'imports': []
    }, imports: imports);
  }
}

Widget host(Widget child) => CehViewModeScope(
    controller: CehViewModeController(),
    child: MaterialApp(theme: CehTheme.light(), home: child));
Future<void> select(WidgetTester t, String label) async {
  await t.tap(find.byKey(const Key('bank-selector')));
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
      'Import Details uses masked account or currency, never duplicate bank name',
      (t) async {
    for (final masked in [null, '•••• 1234']) {
      await t.pumpWidget(MaterialApp(
          home: BankImportDetail(
              session: admin,
              row: {
                'id': 3,
                'account_name': 'Zenith Bank',
                'bank_name': 'Zenith Bank',
                'currency': 'NGN',
                'masked_account_reference': masked
              },
              money: (v) => '$v')));
      expect(
          find.text(
              masked == null ? 'Zenith Bank • NGN' : 'Zenith Bank • •••• 1234'),
          findsOneWidget);
      expect(find.text('Zenith Bank • Zenith Bank'), findsNothing);
    }
  });
  test('page contract retains authoritative totals, ownership and bounded rows',
      () {
    final p = BankingPage.fromJson({
      'total': '719',
      'page': 15,
      'has_more': false,
      'transactions': [
        {'id': 719, 'usage_state': 'AVAILABLE'}
      ],
      'summary': {'debit_total': '41851345.01'}
    });
    expect(p.total, 719);
    expect(p.rows.length, 1);
    expect(p.summary['debit_total'], '41851345.01');
    expect(p.hasMore, false);
    expect(
        bankUsageLabels.values
            .any((s) => s.toLowerCase().contains('duplicate')),
        false);
  });
  testWidgets(
      'explicit bank selector, balance distinction, pagination and reset',
      (t) async {
    final api = BankApi();
    await t
        .pumpWidget(host(AccountsBankingWorkspace(session: admin, api: api)));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await select(t, 'Account 1 • •••• 1234');
    expect(find.text('CEH Ledger Balance'), findsOneWidget);
    expect(find.text('Latest Bank Statement Balance'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Next'), 250,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(api.calls.last['page'], 2);
    await t.scrollUntilVisible(find.byKey(const Key('bank-selector')), -250,
        scrollable: find.byType(Scrollable).first);
    await select(t, 'Account 2 • •••• 1234');
    expect(api.calls.last['bank'], 2);
    expect(api.calls.last['page'], 1);
    expect(api.calls.last['filters'], isEmpty);
  });
  testWidgets('filters are sent to server and reset page', (t) async {
    final api = BankApi();
    await t
        .pumpWidget(host(AccountsBankingWorkspace(session: admin, api: api)));
    await t.pumpAndSettle();
    await select(t, 'Account 1 • •••• 1234');
    await t.tap(find.text('Filters'));
    await t.pumpAndSettle();
    await t.enterText(
        find.widgetWithText(TextFormField, 'Exact amount (debit or credit)'),
        '53.75');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Narration or reference'), 'NIP');
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect((api.calls.last['filters'] as Map)['amount'], '53.75');
    expect((api.calls.last['filters'] as Map)['search'], 'NIP');
    expect(api.calls.last['page'], 1);
  });
  testWidgets('read-only imports tab and error retry', (t) async {
    final api = BankApi();
    await t
        .pumpWidget(host(AccountsBankingWorkspace(session: admin, api: api)));
    await t.pumpAndSettle();
    await select(t, 'Account 1 • •••• 1234');
    await t.tap(find.text('Imports'));
    await t.pumpAndSettle();
    expect(api.calls.last['imports'], true);
    expect(find.text('No statement imports.'), findsOneWidget);
    api.fail = true;
    await t.tap(find.text('Transactions'));
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    api.fail = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Confirm Match'), findsNothing);
    expect(find.text('Create Expense from Statement'), findsNothing);
  });
  testWidgets('non-admin does not request bank data', (t) async {
    const operatorSession = CehSession(
        token: 'test',
        tokenType: 'Bearer',
        expiresAt: '',
        user: CehUser(
            id: 2,
            fullName: 'Operator',
            email: '',
            role: 'OPERATOR',
            isActive: true));
    final api = BankApi();
    await t.pumpWidget(
        host(AccountsBankingWorkspace(session: operatorSession, api: api)));
    await t.pumpAndSettle();
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(api.calls, isEmpty);
  });
  testWidgets('empty banks and loading state', (t) async {
    final api = BankApi()..empty = true;
    await t
        .pumpWidget(host(AccountsBankingWorkspace(session: admin, api: api)));
    await t.pumpAndSettle();
    expect(find.text('No bank accounts available.'), findsOneWidget);
  });
  test('read endpoints ADMIN only; no mutation or share controls', () {
    for (final f in [
      'bank_transactions.php',
      'bank_statement_imports.php',
      'bank_statement_source.php'
    ]) {
      final s = File('Server/$f').readAsStringSync();
      expect(s, contains("['ADMIN']"));
      expect(s, contains("production_require_method('GET')"));
    }
    final s = File('lib/screens/accounts/accounts_banking_workspace.dart')
        .readAsStringSync();
    for (final forbidden in [
      'reconcileBankRow',
      'importBankStatement',
      'SharePlus',
      'uploadFinancialEvidence'
    ]) {
      expect(s, isNot(contains(forbidden)));
    }
    final native = File(
            'android/app/src/main/kotlin/com/concreteequipmenthire/ceh/MainActivity.kt')
        .readAsStringSync();
    expect(native, contains('file.parentFile == root'));
    expect(native, contains('Intent.FLAG_GRANT_READ_URI_PERMISSION'));
  });
}
