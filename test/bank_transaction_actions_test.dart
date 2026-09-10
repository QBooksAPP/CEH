import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ceh/core/api_client.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/bank_transaction_actions.dart';

const _admin = CehSession(
    token: 'qa',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1, fullName: 'QA', email: '', role: 'ADMIN', isActive: true));

class _Api extends CehApiClient {
  List<Map<String, dynamic>> history = [];
  bool credit = false, owned = false, fail = false;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> bankingDetail(
      CehSession s, int bankId, int rowId,
      {bool candidates = false, int page = 1, String search = ''}) async {
    calls++;
    if (fail) throw const ApiException('FAILED');
    return {
      'bank': {'name': 'Zenith Bank', 'currency': 'NGN'},
      'transaction': {
        'id': rowId,
        'bank_account_id': bankId,
        'amount': credit ? '500.00' : '-53.75',
        'transaction_date': '2026-09-10',
        'bank_reference': 'QA-ONLY',
        'narration': 'QA charge',
        'import_batch_id': 99,
        'source_sheet': 'Activity',
        'source_row': 2,
        'usage_state': owned ? 'RESERVED_EXPENSE' : 'AVAILABLE',
        'owner': owned ? {'type': 'GENERAL_EXPENSE', 'id': 99} : null
      },
      'can_create_expense': !credit && !owned,
      'can_match': !credit && !owned,
      'can_link_refund': credit && !owned,
      'history': history
    };
  }
}

void main() {
  test('friendly Banking history labels preserve unknown audit codes', () {
    const labels = {
      'GENERAL_EXPENSE_DRAFTED': 'Expense drafted',
      'GENERAL_EXPENSE_UPDATED': 'Expense updated',
      'GENERAL_EXPENSE_SUBMITTED': 'Expense submitted',
      'GENERAL_EXPENSE_APPROVED': 'Expense approved',
      'GENERAL_EXPENSE_CORRECTION_REQUIRED': 'Expense correction requested',
      'GENERAL_EXPENSE_CANCELLED_NOT_SPENT': 'Expense cancelled (not spent)',
      'GENERAL_EXPENSE_REFUND_LINKED': 'Refund linked',
      'BANK_ROW_RECONCILED': 'Bank transaction reconciled',
      'ADMIN_CONFIRMED': 'Confirmed by administrator',
      'EXPENSE_APPROVAL': 'Reconciled on Expense approval',
    };
    for (final entry in labels.entries) {
      expect(bankingHistoryLabel(entry.key), entry.value);
    }
    expect(bankingHistoryLabel('FUTURE_EVENT'), 'FUTURE_EVENT');
    expect(bankingHistoryLabel(''), '');
  });
  Future<void> show(WidgetTester t, _Api api,
      {CehSession session = _admin}) async {
    await t.pumpWidget(MaterialApp(
        home: BankTransactionActions(
            session: session, bankId: 2, rowId: 999, api: api)));
    await t.pumpAndSettle();
  }

  testWidgets('debit exposes eligible expense and existing match only',
      (t) async {
    final api = _Api();
    await show(t, api);
    await t.scrollUntilVisible(find.text('Create Expense'), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.text('Create Expense'), findsOneWidget);
    expect(find.text('Match Existing Transaction'), findsOneWidget);
    expect(find.text('Create Client Payment'), findsNothing);
    expect(find.text('Unmatch'), findsNothing);
    expect(find.text('Delete Match'), findsNothing);
  });
  testWidgets('history displays friendly wording without changing raw data',
      (t) async {
    final raw = {
      'action': 'GENERAL_EXPENSE_REFUND_LINKED',
      'source_reference': 'CEH-EX-000009',
      'actor': 'QA Admin',
      'timestamp': '2026-09-10 22:20:00',
      'method': 'ADMIN_CONFIRMED',
    };
    final api = _Api()..history = [raw];
    await show(t, api);
    await t.scrollUntilVisible(find.text('Refund linked'), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.text('Refund linked'), findsOneWidget);
    expect(find.textContaining('Confirmed by administrator'), findsOneWidget);
    expect(find.text('GENERAL_EXPENSE_REFUND_LINKED'), findsNothing);
    expect(raw['action'], 'GENERAL_EXPENSE_REFUND_LINKED');
    expect(raw['method'], 'ADMIN_CONFIRMED');
    expect(t.takeException(), isNull);
  });
  testWidgets('credit permits existing refund workflow, not new receipt',
      (t) async {
    await show(t, _Api()..credit = true);
    await t.scrollUntilVisible(find.text('Link Expense Refund'), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.text('Link Expense Refund'), findsOneWidget);
    expect(find.text('Create Expense'), findsNothing);
    expect(find.text('Match Existing Transaction'), findsNothing);
    expect(find.text('Create Client Payment'), findsNothing);
  });
  testWidgets(
      'reserved expense provides owner navigation without claim actions',
      (t) async {
    await show(t, _Api()..owned = true);
    await t.scrollUntilVisible(find.text('Open Expense'), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.text('Open Expense'), findsOneWidget);
    expect(find.text('Create Expense'), findsNothing);
    expect(find.text('Match Existing Transaction'), findsNothing);
  });
  testWidgets('failed authoritative refresh never exposes mutation', (t) async {
    final api = _Api()..fail = true;
    await show(t, api);
    expect(find.textContaining('Could not refresh'), findsOneWidget);
    expect(find.text('Create Expense'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    api.fail = false;
    await t.tap(find.text('Refresh'));
    await t.pumpAndSettle();
    expect(api.calls, 2);
  });
  testWidgets('non-admin cannot load or act', (t) async {
    final api = _Api();
    await show(t, api,
        session: const CehSession(
            token: 'qa',
            tokenType: 'Bearer',
            expiresAt: '',
            user: CehUser(
                id: 2,
                fullName: 'QA',
                email: '',
                role: 'OPERATOR',
                isActive: true)));
    expect(api.calls, 0);
    expect(find.text('Admin access required.'), findsOneWidget);
  });
}
