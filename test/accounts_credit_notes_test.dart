import 'dart:io';
import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/credit_note_pending.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_credit_notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const admin = CehSession(
    token: 'qa',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1, fullName: 'QA', email: '', role: 'ADMIN', isActive: true));
const operatorSession = CehSession(
    token: 'qa',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 2, fullName: 'QA', email: '', role: 'OPERATOR', isActive: true));

class MemoryPending extends CreditNotePendingStore {
  Map<String, dynamic>? request;
  @override
  Future<Map<String, dynamic>?> load(int user, int invoice) async => request;
  @override
  Future<void> save(int user, int invoice, Map<String, dynamic> value) async {
    request = Map.of(value);
  }

  @override
  Future<void> clear(int user, int invoice) async {
    request = null;
  }
}

class CreditApi extends CehApiClient {
  int reads = 0, issues = 0;
  bool fail = false;
  ApiException issuanceError = const ApiException('UNCERTAIN', statusCode: 500);
  Map<String, dynamic>? submitted;
  @override
  Future<Map<String, dynamic>> quoteCreditNote(
          CehSession session, Map<String, dynamic> request) async =>
      {
        'quote': {
          'lines': [
            {
              'original': {'description': 'QA service'},
              'net_amount': '27.91',
              'vat_amount': '2.09',
              'gross_amount': '30.00',
              'production_releases': []
            }
          ],
          'total_amount': '30.00',
          'outstanding_after': '77.50'
        }
      };
  @override
  Future<Map<String, dynamic>> creditNotes(
      CehSession s, Map<String, String> query) async {
    reads++;
    if (fail) throw const ApiException('QA_UNAVAILABLE');
    if (query.containsKey('request_key')) return {'completed': false};
    return {
      'can_issue_credit_note': true,
      'blocking_reasons': [],
      'outstanding': '107.50',
      'credit_notes': [],
      'lines': [
        {
          'id': 1,
          'description': 'QA service',
          'net_amount': '100.00',
          'vat_amount': '7.50',
          'gross_amount': '107.50',
          'credited_gross': '0.00',
          'remaining_net': '100.00',
          'remaining_vat': '7.50',
          'remaining_gross': '107.50',
          'production_allocations': []
        }
      ]
    };
  }

  @override
  Future<Map<String, dynamic>> issueCreditNote(
      CehSession s, Map<String, dynamic> request) async {
    issues++;
    submitted = Map.of(request);
    throw issuanceError;
  }
}

void main() {
  testWidgets('authentication failure cannot discard an uncertain issuance key',
      (tester) async {
    final store = MemoryPending()
      ..request = {
        'invoice_id': 1,
        'request_key': 'b' * 48,
        'credit_date': '2026-09-07',
        'reason': 'QA',
        'lines': []
      };
    final api = CreditApi()
      ..issuanceError = const ApiException('UNAUTHORIZED', statusCode: 401);
    await tester.pumpWidget(MaterialApp(
        home: CreditNotesScreen(
            session: admin, invoiceId: 1, api: api, pendingStore: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve / retry same request'));
    await tester.pumpAndSettle();
    expect(store.request!['request_key'], 'b' * 48);
    expect(find.text('Review Credit Note'), findsNothing);
  });
  testWidgets(
      'review uses server amounts and persists before uncertain issuance',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = CreditApi(), store = MemoryPending();
    await tester.pumpWidget(MaterialApp(
        home: CreditNotesScreen(
            session: admin, invoiceId: 1, api: api, pendingStore: store)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Gross amount to credit'), '30.00');
    await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'), 'QA reason');
    await tester.ensureVisible(find.text('Review Credit Note'));
    await tester.tap(find.text('Review Credit Note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('27.91'), findsOneWidget);
    expect(find.textContaining('77.50'), findsOneWidget);
    expect(api.issues, 0);
    await tester.tap(find.text('Confirm Issue Credit Note'));
    await tester.pumpAndSettle();
    expect(api.issues, 1);
    expect(store.request!['request_key'], api.submitted!['request_key']);
    expect(find.text('Resolve / retry same request'), findsOneWidget);
    expect(find.text('Review Credit Note'), findsNothing);
  });
  testWidgets('unsaved Home protection preserves form when Stay is selected',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CreditNotesScreen(
            session: admin,
            invoiceId: 1,
            api: CreditApi(),
            pendingStore: MemoryPending())));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Gross amount to credit'), '30.00');
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Discard the unsubmitted form?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('30.00'), findsOneWidget);
  });
  test('issuance keys are secure-shaped unique and valid for server contract',
      () {
    final keys = List.generate(100, (_) => CreditNotePendingStore.newKey());
    expect(keys.toSet().length, 100);
    expect(keys.every((k) => RegExp(r'^[a-f0-9]{48}$').hasMatch(k)), true);
  });
  testWidgets('operator cannot read or issue Credit Notes', (tester) async {
    final api = CreditApi();
    await tester.pumpWidget(MaterialApp(
        home: CreditNotesScreen(
            session: operatorSession,
            invoiceId: 1,
            api: api,
            pendingStore: MemoryPending())));
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(api.reads, 0);
  });
  testWidgets(
      'server amounts, empty history and Home are visible without mutation controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CreditNotesScreen(
            session: admin,
            invoiceId: 1,
            api: CreditApi(),
            pendingStore: MemoryPending())));
    await tester.pumpAndSettle();
    expect(find.text('No Credit Notes issued.'), findsOneWidget);
    expect(find.text('QA service'), findsOneWidget);
    expect(find.byTooltip('Home'), findsOneWidget);
    for (final text in [
      'Edit Credit Note',
      'Delete Credit Note',
      'Void Credit Note',
      'Reverse Credit Note'
    ]) {
      expect(find.text(text), findsNothing);
    }
    expect(find.textContaining('Remaining net'), findsOneWidget);
  });
  testWidgets(
      'pending uncertain request blocks fresh issuance and retries identical key',
      (tester) async {
    final store = MemoryPending()
      ..request = {
        'invoice_id': 1,
        'request_key': 'a' * 48,
        'credit_date': '2026-09-07',
        'reason': 'QA',
        'lines': []
      };
    final api = CreditApi();
    await tester.pumpWidget(MaterialApp(
        home: CreditNotesScreen(
            session: admin, invoiceId: 1, api: api, pendingStore: store)));
    await tester.pumpAndSettle();
    expect(find.text('Review Credit Note'), findsNothing);
    await tester.tap(find.text('Resolve / retry same request'));
    await tester.pumpAndSettle();
    expect(api.issues, 1);
    expect(api.submitted!['request_key'], 'a' * 48);
    expect(store.request, isNotNull);
    expect(find.textContaining('Outcome not confirmed'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('read errors show retry instead of fake amounts', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CreditNotesScreen(
            session: admin,
            invoiceId: 1,
            api: CreditApi()..fail = true,
            pendingStore: MemoryPending())));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Invoice outstanding:'), findsNothing);
  });
  test(
      'backend guards, immutable snapshot and persistent replay remain present',
      () {
    final code = File('Server/credit_note_common.php').readAsStringSync();
    expect(code.indexOf('DUPLICATE_CREDIT_INVOICE_LINE'),
        lessThan(code.indexOf('INSERT INTO qbook_credit_notes')));
    for (final guard in [
      'CREDIT_HISTORY_INTEGRITY_ERROR',
      'IDEMPOTENCY_PAYLOAD_MISMATCH',
      'QUANTITY_RELEASE_EXCEEDS_ALLOCATION_M3',
      'CREDIT_EXCEEDS_OUTSTANDING',
      'qbook_credit_note_requests',
      'document_snapshot'
    ]) {
      expect(code, contains(guard));
    }
    expect(code, contains("'source_module'=>'CREDIT_NOTE'"));
    expect(code, contains("billing_account_role(\$db,'OUTPUT_VAT_PAYABLE')"));
    expect(code, contains("billing_account_role(\$db,'TRADE_RECEIVABLES')"));
  });
  test('Credit Note PDF uses frozen values, white tables and no attribution',
      () {
    final code = File('Server/credit_note_pdf_common.php').readAsStringSync();
    expect(code, contains('background-color:#ffffff'));
    expect(code, contains('background-color:#121212;color:#ffffff'));
    expect(code, contains('SetDrawColor(190,190,190)'));
    expect(code, contains('tcpdflink=false'));
    expect(code, contains('<thead>'));
    expect(code, contains(r'if($this->getPage()<=1)return;'));
    expect(code, contains("' — Continued'"));
    expect(code, contains('SetXY(15,5)'));
    expect(code, contains('nobr="true"'));
    expect(code, isNot(contains('production_db()')));
    expect(code, isNot(contains('qbook_invoice_settings')));
  });
}
