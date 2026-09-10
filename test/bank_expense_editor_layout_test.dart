import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/models/accounts.dart';
import 'package:ceh/models/client.dart';
import 'package:ceh/models/project.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_general_expense_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _long =
    'A very long accounting category and allocation name for narrow phone layout verification';
const _session = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1, fullName: 'QA', email: '', role: 'ADMIN', isActive: true));

class _Lookups extends CehApiClient {
  @override
  Future<List<CehBankAccount>> bankAccounts(CehSession session) async => [
        CehBankAccount.fromJson({'id': 1, 'name': _long, 'currency': 'NGN'})
      ];
  @override
  Future<List<ExpenseSupplier>> expenseSuppliers(CehSession session) async =>
      [const ExpenseSupplier(id: 1, name: _long, isActive: true)];
  @override
  Future<List<FinancialAccount>> financialAccounts(CehSession session) async =>
      [
        const FinancialAccount(
            id: 1,
            code: '5100',
            name: _long,
            accountType: 'EXPENSE',
            isPostable: true,
            isActive: true)
      ];
  @override
  Future<List<CostCentre>> costCentres(CehSession session) async =>
      [const CostCentre(id: 1, code: 'QA', name: _long, isActive: true)];
  @override
  Future<List<CehClient>> clients(CehSession session,
          {bool activeOnly = true, String? status}) async =>
      [const CehClient(id: 1, name: _long, isActive: true)];
  @override
  Future<List<CehProject>> projects(CehSession session, int clientId,
          {bool activeOnly = true, String? status}) async =>
      [const CehProject(id: 1, clientId: 1, name: _long, isActive: true)];
  @override
  Future<List<Map<String, dynamic>>> mixers(CehSession session,
          {int? projectId, bool includeAllocation = false}) async =>
      [
        {'id': 1, 'code': _long}
      ];
}

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is InputDecorator && w.decoration.labelText == label);
void main() {
  for (final width in [320.0, 360.0, 393.0, 412.0]) {
    testWidgets('Bank Expense fields remain separated at $width phone width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          theme: CehTheme.light(),
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 852),
                  textScaler: const TextScaler.linear(1.2)),
              child: AccountsGeneralExpenseScreen(
                  session: _session,
                  api: _Lookups(),
                  expense: {
                    'id': 99,
                    'bank_account_id': 1,
                    'supplier_id': 1,
                    'supplier_name_snapshot': _long,
                    'expense_date': '2026-09-10',
                    'created_from_statement_row_id': 726,
                    'amount': '1000.00',
                    'bank_reference': 'QA only',
                    'lines': [
                      {
                        'amount': '1000.00',
                        'item_description': '$_long. $_long. $_long.',
                        'expense_account_id': 1,
                        'cost_centre_id': 1,
                        'mixer_id': 1
                      }
                    ]
                  }))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(field('Bank Reference (optional)'), 200,
          scrollable: scroll);
      expect(
          tester
              .widget<TextField>(find.byWidgetPredicate((w) =>
                  w is TextField &&
                  w.decoration?.labelText == 'Bank Reference (optional)'))
              .enabled,
          isFalse);
      await tester.scrollUntilVisible(field('Cost Centre'), 250,
          scrollable: scroll);
      await tester.pumpAndSettle();
      for (final pair in [
        ['Cost Centre', 'Account / Category'],
        ['Account / Category', 'Description'],
        ['Description', 'Qty (optional)'],
        ['Qty (optional)', 'Total'],
        ['Total', 'Client / Project (optional)'],
        ['Client / Project (optional)', 'Project (optional)'],
        ['Project (optional)', 'Equipment (optional)']
      ]) {
        final a = tester.getRect(field(pair[0]));
        final b = tester.getRect(field(pair[1]));
        expect(b.top - a.bottom, greaterThanOrEqualTo(15),
            reason: '${pair[0]} → ${pair[1]}');
      }
      final qty = tester.getRect(field('Qty (optional)'));
      final price = tester.getRect(field('Price (optional)'));
      expect((qty.top - price.top).abs(), lessThan(1));
      expect(price.left - qty.right, greaterThanOrEqualTo(10));
      final card = tester.getRect(find
          .ancestor(of: field('Cost Centre'), matching: find.byType(Card))
          .first);
      expect(tester.getRect(field('Cost Centre')).left - card.left,
          greaterThanOrEqualTo(16));
      final description = tester.widget<TextField>(find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Description'));
      expect(description.minLines, 2);
      expect(description.maxLines, 4);
      final project = tester.widget<DropdownButtonFormField<int?>>(
          find.byWidgetPredicate((w) =>
              w is DropdownButtonFormField<int?> &&
              w.decoration.labelText == 'Project (optional)'));
      expect(project.onChanged, isNull);
      await tester.scrollUntilVisible(find.text('Submit Expense'), 300,
          scrollable: scroll);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Save Draft'), findsOneWidget);
      expect(find.text('Submit Expense'), findsOneWidget);
    });
  }
}
