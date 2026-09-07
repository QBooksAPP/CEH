import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/accounts_formatters.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/accounts.dart';
import 'package:ceh/models/company_regional_settings.dart';
import 'package:ceh/screens/accounts/accounts_billing_screen.dart';
import 'package:ceh/screens/accounts/accounts_journal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'accounts_trial_balance_wht_test.dart' show admin, operatorSession;

Map<String, dynamic> payload({bool voided = false, bool eligible = true}) => {
      'invoice': {
        'id': 7,
        'reference': 'CEH-INV-QA',
        'client_id': 1,
        'client_name_snapshot': 'QA client',
        'status': voided ? 'VOID' : 'ISSUED',
        'raw_status': voided ? 'VOID' : 'ISSUED',
        'display_status': voided ? 'VOID' : 'OVERDUE',
        'can_void': !voided && eligible,
        'void_blocking_reasons': eligible ? [] : ['WHT_SETTLEMENT_EXISTS'],
        'invoice_date': '2026-01-01',
        'total_amount': '20000.00',
        'outstanding': '20000.00',
        'void_reason': voided ? 'QA reason' : null,
        'voided_by_name': voided ? 'QA Admin' : null,
        'voided_at': voided ? '2026-09-07 12:00:00' : null,
        'effective_void_date': voided ? '2026-09-06' : null,
        'journal_id': 15,
        'original_journal_reference': 'CEH-JRN-ORIGINAL',
        'reversal_journal_id': voided ? 16 : null,
        'reversal_journal_reference': voided ? 'CEH-JRN-REVERSAL' : null,
      },
      'lines': [],
      'credit_notes': []
    };

class VoidApi extends CehApiClient {
  bool voided = false, failRefresh = false, failSubmit = false, eligible = true;
  int reads = 0, calls = 0;
  String? reason, date;
  Completer<void>? pending;
  final journalReads = <int>[];
  @override
  Future<FinancialJournalDetail> financialJournal(s, int id) async {
    journalReads.add(id);
    return FinancialJournalDetail.fromJson(
        {'id': id, 'reference_no': 'QA JOURNAL', 'lines': []});
  }

  @override
  Future<BillingInvoiceDetail> invoiceDetails(s, int id) async {
    reads++;
    if (failRefresh && reads > 1) throw Exception('offline');
    return BillingInvoiceDetail.fromJson(
        payload(voided: voided, eligible: eligible));
  }

  @override
  Future<void> voidInvoice(s, int id,
      {required String reason, required String voidDate}) async {
    calls++;
    this.reason = reason;
    date = voidDate;
    if (pending != null) await pending!.future;
    if (failSubmit) throw TimeoutException('uncertain');
    voided = true;
  }
}

Future<void> mount(WidgetTester t, VoidApi api,
    {bool operator = false, bool viewOnly = false}) async {
  final mode = CehViewModeController();
  if (viewOnly) mode.enableOperatorView();
  await t.pumpWidget(CehViewModeScope(
      controller: mode,
      child: MaterialApp(
          theme: CehTheme.light(),
          home: InvoiceDetailsScreen(
              invoiceId: 7,
              session: operator ? operatorSession : admin,
              api: api))));
  await t.pumpAndSettle();
}

Future<void> confirm(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('void-invoice')));
  await t.pumpAndSettle();
  await t.enterText(
      find.byKey(const ValueKey('invoice-void-reason')), 'QA reason');
  await t.ensureVisible(find.byType(CheckboxListTile));
  await t.tap(find.byType(CheckboxListTile));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('confirm-void-invoice')));
  await t.pump();
}

void main() {
  tearDown(() => CehRegionalFormats.use(const CompanyRegionalSettings()));
  testWidgets(
      'phone-width void sections follow settlements and both journal links navigate read-only',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = VoidApi()..voided = true;
    await mount(t, api);
    await t.scrollUntilVisible(find.text('Void Details'), 300);
    await t.scrollUntilVisible(find.text('Voided by: QA Admin'), 100);
    expect(find.text('Status: VOID'), findsOneWidget);
    expect(find.text('Voided by: QA Admin'), findsOneWidget);
    expect(find.textContaining('Journal #15'), findsNothing);
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('view-original-journal')), 200);
    await t.tap(find.descendant(
        of: find.byKey(const ValueKey('view-original-journal')),
        matching: find.byType(TextButton)));
    await t.pumpAndSettle();
    expect(
        t
            .widget<JournalDetailScreen>(find.byType(JournalDetailScreen))
            .journalId,
        15);
    Navigator.of(t.element(find.byType(JournalDetailScreen))).pop();
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('view-reversal-journal')), 200);
    await t.tap(find.descendant(
        of: find.byKey(const ValueKey('view-reversal-journal')),
        matching: find.byType(TextButton)));
    await t.pumpAndSettle();
    expect(
        t
            .widget<JournalDetailScreen>(find.byType(JournalDetailScreen))
            .journalId,
        16);
    expect(api.journalReads, [15, 16]);
    expect(api.calls, 0);
    expect(t.takeException(), isNull);
  });
  test('raw status, guidance and void metadata parsed separately', () {
    final i = BillingInvoiceDetail.fromJson(payload());
    expect(i.rawStatus, 'ISSUED');
    expect(i.status, 'OVERDUE');
    expect(i.canVoid, true);
    final v = BillingInvoiceDetail.fromJson(payload(voided: true));
    expect(v.canVoid, false);
    expect(v.reversalJournalId, 16);
    expect(v.effectiveVoidDate, '2026-09-06');
    expect(v.voidedByName, 'QA Admin');
    final legacy = payload();
    (legacy['invoice'] as Map).remove('can_void');
    expect(BillingInvoiceDetail.fromJson(legacy).canVoid, false);
  });
  test('POST payload and auth remain server-authoritative', () async {
    await http.runWithClient(
        () => const CehApiClient()
            .voidInvoice(admin, 7, reason: 'QA', voidDate: '2026-09-07'),
        () => MockClient((r) async {
              expect(r.url.path, '/invoice_void.php');
              expect(r.method, 'POST');
              expect(r.headers['Authorization'], contains(admin.token));
              expect(jsonDecode(r.body),
                  {'invoice_id': 7, 'reason': 'QA', 'void_date': '2026-09-07'});
              return http.Response('{"ok":true}', 200);
            }));
  });
  testWidgets('Operator and view-only contexts have no void action', (t) async {
    await mount(t, VoidApi(), operator: true);
    expect(find.byKey(const ValueKey('void-invoice')), findsNothing);
    await mount(t, VoidApi(), viewOnly: true);
    expect(find.byKey(const ValueKey('void-invoice')), findsNothing);
  });
  testWidgets('server-ineligible invoice has no action', (t) async {
    await mount(t, VoidApi()..eligible = false);
    expect(find.byKey(const ValueKey('void-invoice')), findsNothing);
    expect(find.textContaining('Wht Settlement Exists'), findsOneWidget);
  });
  testWidgets(
      'confirmation requires reason, explicit consent and supports cancel',
      (t) async {
    final api = VoidApi();
    await mount(t, api);
    await t.tap(find.byKey(const ValueKey('void-invoice')));
    await t.pumpAndSettle();
    expect(
        t
            .widget<FilledButton>(
                find.byKey(const ValueKey('confirm-void-invoice')))
            .onPressed,
        isNull);
    await t.ensureVisible(find.byType(CheckboxListTile));
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('confirm-void-invoice')));
    await t.pumpAndSettle();
    expect(find.text('Reason is required.'), findsOneWidget);
    expect(api.calls, 0);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls, 0);
  });
  testWidgets('one submission then refreshed VOID and history', (t) async {
    final api = VoidApi()..pending = Completer<void>();
    await mount(t, api);
    await confirm(t);
    expect(api.calls, 1);
    expect(
        t
            .widget<OutlinedButton>(find.byKey(const ValueKey('void-invoice')))
            .onPressed,
        isNull);
    api.pending!.complete();
    await t.pumpAndSettle();
    expect(api.reads, 2);
    expect(find.byKey(const ValueKey('void-invoice')), findsNothing);
    await t.scrollUntilVisible(find.text('Reason: QA reason'), 300);
    expect(find.text('Reason: QA reason'), findsOneWidget);
    await t.scrollUntilVisible(find.text('CEH-JRN-REVERSAL'), 200);
    expect(find.text('CEH-JRN-REVERSAL'), findsOneWidget);
    expect(api.date, canonicalAccountsDate(DateTime.now()));
  });
  testWidgets(
      'uncertain submission and failed refresh cannot reuse old eligibility',
      (t) async {
    final api = VoidApi()
      ..failSubmit = true
      ..failRefresh = true;
    await mount(t, api);
    await confirm(t);
    await t.pumpAndSettle();
    expect(api.reads, 2);
    expect(find.byKey(const ValueKey('void-invoice')), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    api.failRefresh = false;
    api.voided = true;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Void Details'), 300);
    expect(find.text('Void Details'), findsOneWidget);
    expect(api.calls, 1);
  });
  testWidgets('Regional Settings date is shown in confirmation', (t) async {
    CehRegionalFormats.use(
        const CompanyRegionalSettings(dateFormat: 'YYYY-MM-DD'));
    await mount(t, VoidApi());
    await t.tap(find.byKey(const ValueKey('void-invoice')));
    await t.pumpAndSettle();
    expect(find.text(canonicalAccountsDate(DateTime.now())), findsOneWidget);
    expect(find.text('Total: ₦20,000.00'), findsOneWidget);
  });
  test('endpoint uses shared locked lifecycle, original records not deleted',
      () {
    final source = File('Server/invoice_void_common.php').readAsStringSync();
    expect(source, contains('FOR UPDATE'));
    expect(source, contains('accounts_reverse_journal'));
    expect(source, contains('reversed_allocation_ids'));
    expect(source, isNot(contains('DELETE FROM')));
    expect(File('Server/invoice_void.php').readAsStringSync(),
        contains('billing_require_admin()'));
  });
}
