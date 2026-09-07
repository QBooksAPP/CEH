import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/accounts_formatters.dart';
import 'package:ceh/models/company_regional_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/expense_refunds.dart';
import 'package:ceh/screens/accounts/accounts_expense_refunds_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'accounts_trial_balance_wht_test.dart' show admin, operatorSession;

Map<String, dynamic> response(
        {String status = 'PARTIAL', bool eligible = false, int page = 1}) =>
    {
      'expense': {
        'reference_no': 'CEH-EX-000001',
        'bank_name': 'CEH Bank',
        'amount': '100000.00',
        'linked_amount': status == 'FULL' ? '100000.00' : '40000.00',
        'remaining_amount': status == 'FULL' ? '0.00' : '60000.00',
        'refund_status': status,
        'can_link': status != 'FULL'
      },
      'page': page,
      'total_pages': 2,
      'total': 26,
      'rows': [
        {
          'statement_row_id': 8,
          'amount': eligible ? '60000.00' : '40000.00',
          'transaction_date': '2026-09-01',
          'bank_reference': 'BANK-REF-8',
          'narration': 'Supplier returned payment',
          'statement_status': 'UNMATCHED',
          'linked_at': eligible ? null : '2026-09-02 12:00:00',
          'linked_by_name': eligible ? null : 'Admin'
        }
      ]
    };

class RefundApi extends CehApiClient {
  int reads = 0, links = 0, lastPage = 0;
  String lastSearch = '';
  bool failRead = false, failLink = false, full = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> generalExpenseRefunds(s,
      {required int expenseId,
      String view = 'history',
      int page = 1,
      String search = '',
      String dateFrom = '',
      String dateTo = ''}) async {
    reads++;
    lastPage = page;
    lastSearch = search;
    if (failRead) throw Exception('offline');
    if (pending != null) return pending!.future;
    return response(
        status: full ? 'FULL' : 'PARTIAL',
        eligible: view == 'eligible',
        page: page);
  }

  @override
  Future<void> linkGeneralExpenseRefund(s,
      {required int expenseId, required int statementRowId}) async {
    links++;
    if (failLink) throw Exception('connection lost');
    full = true;
  }
}

Widget app(RefundApi api, {bool operator = false}) => CehViewModeScope(
    controller: CehViewModeController(),
    child: MaterialApp(
        theme: CehTheme.light(),
        home: AccountsExpenseRefundsScreen(
            session: operator ? operatorSession : admin,
            expenseId: 1,
            api: api)));

void main() {
  tearDown(() => CehRegionalFormats.use(const CompanyRegionalSettings()));
  test(
      'API sends authenticated filters and only expense/statement IDs on linking',
      () async {
    final requests = <http.Request>[];
    await http.runWithClient(() async {
      const api = CehApiClient();
      await api.generalExpenseRefunds(admin,
          expenseId: 1,
          view: 'eligible',
          page: 3,
          search: 'BANK',
          dateFrom: '2026-09-01');
      await api.linkGeneralExpenseRefund(admin,
          expenseId: 1, statementRowId: 8);
    },
        () => MockClient((r) async {
              requests.add(r);
              return http.Response(
                  jsonEncode({'ok': true, ...response()}), 200);
            }));
    expect(requests.first.url.queryParameters['page'], '3');
    expect(requests.first.url.queryParameters['search'], 'BANK');
    expect(requests.first.url.queryParameters['date_from'], '2026-09-01');
    expect(requests.first.headers['Authorization'], 'Bearer test');
    expect(jsonDecode(requests.last.body),
        {'expense_id': 1, 'statement_row_id': 8});
    expect(requests.last.url.path, '/general_expense_refund_link.php');
  });
  testWidgets('Regional Settings date display and narrow-screen layout',
      (t) async {
    CehRegionalFormats.use(
        const CompanyRegionalSettings(dateFormat: 'DD/MM/YYYY'));
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(app(RefundApi()));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
        find.textContaining('01/09/2026').hitTestable(), 250,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.textContaining('01/09/2026'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test(
      'server totals, partial/full status and history parse without page summation',
      () {
    final p = ExpenseRefundPage.fromJson(response());
    expect(p.original, 100000);
    expect(p.linked, 40000);
    expect(p.remaining, 60000);
    expect(p.statusLabel, 'Partially Refunded');
    expect(p.total, 26);
    expect(p.rows.single.linkedBy, 'Admin');
    final full = ExpenseRefundPage.fromJson(response(status: 'FULL'));
    expect(full.statusLabel, 'Fully Refunded');
    expect(full.canLink, false);
  });
  testWidgets('non Admin cannot fetch or link refunds', (t) async {
    final api = RefundApi();
    await t.pumpWidget(app(api, operator: true));
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(api.reads, 0);
    expect(api.links, 0);
  });
  testWidgets('loading/error/retry and empty states', (t) async {
    final api = RefundApi()..pending = Completer();
    await t.pumpWidget(app(api));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.pending!.completeError(Exception('offline'));
    api.pending = null;
    await t.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    api.pending = Completer();
    await t.tap(find.text('Try again'));
    await t.pump();
    api.pending!
        .complete({...response(), 'rows': [], 'total': 0, 'total_pages': 0});
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
        find.text('No linked refunds match these filters.'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('No linked refunds match these filters.'), findsOneWidget);
  });
  testWidgets(
      'history, pagination, search, CEH Home and no mutation of bank entries',
      (t) async {
    final api = RefundApi();
    await t.pumpWidget(app(api));
    await t.pumpAndSettle();
    expect(find.text('Partially Refunded'), findsOneWidget);
    expect(find.text('₦60,000.00'), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Unlink'), findsNothing);
    await t.scrollUntilVisible(find.byTooltip('Next page'), 250,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byTooltip('Next page'));
    await t.pumpAndSettle();
    expect(api.lastPage, 2);
    await t.scrollUntilVisible(find.byType(TextField), -250,
        scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byType(TextField), 'BANK-REF');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(api.lastSearch, 'BANK-REF');
    expect(api.lastPage, 1);
  });
  testWidgets('link confirmation, cancel and successful full refund refresh',
      (t) async {
    final api = RefundApi();
    await t.pumpWidget(app(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Link Refund'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Link this credit').hitTestable(), 250,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Link this credit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.links, 0);
    await t.tap(find.text('Link this credit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirm Link'));
    await t.pumpAndSettle();
    expect(api.links, 1);
    await t.scrollUntilVisible(find.text('Fully Refunded'), -250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Fully Refunded'), findsOneWidget);
    expect(find.text('Link this credit'), findsNothing);
  });
  testWidgets('link failure clears busy and refreshes authoritative state',
      (t) async {
    final api = RefundApi()..failLink = true;
    await t.pumpWidget(app(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Link Refund'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Link this credit').hitTestable(), 250,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Link this credit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirm Link'));
    await t.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Could not confirm refund linkage'),
        findsOneWidget);
    expect(api.reads, 3);
  });
  test(
      'backend boundaries: Admin, locks, duplicate constraint, audit and no journal/bank mutations',
      () {
    for (final endpoint in [
      'general_expense_refunds.php',
      'general_expense_refund_link.php'
    ]) {
      final source = File('Server/$endpoint').readAsStringSync();
      expect(source, contains("qbook_require_role(\$user, ['ADMIN'])"));
    }
    final common =
        File('Server/general_expense_refunds_common.php').readAsStringSync();
    expect(common, contains('FOR UPDATE'));
    expect(common, contains('REFUND_ALREADY_LINKED'));
    expect(common, contains('GENERAL_EXPENSE_REFUND_LINKED'));
    expect(common, contains("'journal_posted'=>false"));
    expect(
        RegExp(r'(INSERT INTO|UPDATE|DELETE FROM)\s+qbook_(financial_journal|bank_statement)',
                caseSensitive: false)
            .hasMatch(common),
        false);
    expect(
        File('Server/migration_v1_13_shared_expense_lines.sql')
            .readAsStringSync(),
        contains('UNIQUE KEY uq_general_refund_statement (statement_row_id)'));
  });
}
