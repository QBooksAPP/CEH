import 'dart:io';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/models/accounts.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1,
        fullName: 'Admin',
        email: 'admin@example.invalid',
        role: 'ADMIN',
        isActive: true));

BillingInvoiceDetail _detail(String vatMode, {String status = 'DRAFT'}) =>
    BillingInvoiceDetail(
        id: 9,
        reference: 'CEH-INV-000001',
        clientId: 7,
        client: 'ABC Construction',
        status: status,
        invoiceDate: '2026-08-23',
        paymentTerm: 'ADVANCE_PAYMENT',
        terms: 'Advance Payment',
        vatMode: vatMode,
        vatTaxCodeId: vatMode == 'NONE' ? null : 3,
        vatRate: vatMode == 'NONE' ? null : '7.500000',
        net: 450000,
        vat: vatMode == 'NONE' ? 0 : 33750,
        total: vatMode == 'NONE' ? 450000 : 483750,
        amountPaid: status == 'DRAFT' ? 0 : 100000,
        whtAllocated: status == 'DRAFT' ? 0 : 10000,
        outstanding: status == 'DRAFT' ? 483750 : 373750,
        issuedAt: status == 'DRAFT' ? null : '2026-08-24 10:00:00',
        journalId: status == 'DRAFT' ? null : 44,
        postingStatus: status == 'DRAFT' ? null : 'POSTED',
        lines: const [
          BillingInvoiceLine(
              lineNo: 1,
              description: 'Concrete batched',
              sourceType: 'PRODUCTION_REPORT',
              revenueAccountId: 41,
              enteredAmount: 450000,
              quantity: 30,
              unitName: 'm³',
              unitPrice: 15000,
              net: 450000,
              vat: 33750,
              total: 483750,
              projectId: 12,
              project: 'Epe',
              equipmentId: 3,
              equipment: 'Mixer 307',
              productionAllocations: [
                {
                  'production_session_id': 8,
                  'report_reference_snapshot': 'CEH-PR-000124',
                  'billed_m3': '30.00'
                }
              ])
        ],
        creditNotes: status == 'DRAFT'
            ? const []
            : const [
                {'reference': 'CEH-CN-000001'}
              ]);

class _DetailApi extends CehApiClient {
  _DetailApi(this.detail);
  BillingInvoiceDetail detail;
  int issueCalls = 0;
  int detailReads = 0;

  @override
  Future<List<BillingInvoice>> invoices(CehSession session) async => [
        BillingInvoice(
            id: detail.id,
            reference: detail.reference,
            client: detail.client,
            status: detail.status,
            total: detail.total,
            outstanding: detail.outstanding)
      ];

  @override
  Future<BillingInvoiceDetail> invoiceDetails(
      CehSession session, int invoiceId) async {
    detailReads++;
    return detail;
  }

  @override
  Future<void> issueInvoice(CehSession session, int invoiceId) async {
    issueCalls++;
  }
}

void main() {
  test('invoice detail GET contract is read-only', () {
    final source = File('Server/invoices.php').readAsStringSync();
    expect(source, contains("production_require_method('GET')"));
    expect(source, contains("\$_GET['id']"));
    expect(source, isNot(contains('accounts_post_journal')));
    expect(source, isNot(contains('UPDATE qbook_invoices')));
    expect(source, isNot(contains('DELETE FROM qbook_invoices')));
  });

  test('issued invoice PDF is authenticated and loads its cache dependency',
      () {
    final endpoint = File('Server/invoice_pdf.php').readAsStringSync();
    final api = File('lib/core/api_client.dart').readAsStringSync();
    expect(endpoint,
        contains("require_once __DIR__ . '/production_report_common.php'"));
    expect(endpoint, contains('billing_require_admin()'));
    expect(endpoint, contains('INVOICE_SETTINGS_INCOMPLETE'));
    expect(endpoint, contains("'quantity'"));
    expect(endpoint, contains("'unit_price'"));
    expect(api, contains("headers:authHeaders(session)"));
    expect(api, contains("startsWith('application/pdf')"));
  });

  testWidgets('Draft invoice row opens without changing invoice state',
      (tester) async {
    final api = _DetailApi(_detail('VAT_EXCLUSIVE'));
    await tester.pumpWidget(
        MaterialApp(home: AccountsBillingScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invoice-row-9')));
    await tester.pumpAndSettle();
    expect(find.text('Invoice Details'), findsOneWidget);
    expect(find.text('CEH-INV-000001'), findsOneWidget);
    expect(api.detailReads, 1);
    expect(api.issueCalls, 0);
  });

  testWidgets('VAT Exclusive Draft details and allocations are visible',
      (tester) async {
    final api = _DetailApi(_detail('VAT_EXCLUSIVE'));
    await tester.pumpWidget(MaterialApp(
        home: InvoiceDetailsScreen(invoiceId: 9, session: _admin, api: api)));
    await tester.pumpAndSettle();
    expect(find.text('VAT Exclusive'), findsOneWidget);
    expect(find.text('7.50%'), findsOneWidget);
    expect(find.text('Project: Epe'), findsOneWidget);
    expect(find.text('Equipment: Mixer 307'), findsOneWidget);
    expect(find.textContaining('CEH-PR-000124'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-invoice-draft')), findsOneWidget);
  });

  testWidgets('VAT Inclusive Draft issue requires explicit confirmation',
      (tester) async {
    final api = _DetailApi(_detail('VAT_INCLUSIVE'));
    await tester.pumpWidget(MaterialApp(
        home: InvoiceDetailsScreen(invoiceId: 9, session: _admin, api: api)));
    await tester.pumpAndSettle();
    expect(find.text('VAT Inclusive'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('issue-invoice-from-detail')));
    await tester.pumpAndSettle();
    expect(api.issueCalls, 0);
    expect(find.textContaining('Trade Receivables'), findsOneWidget);
    expect(find.textContaining('Final invoice total: ₦483,750.00'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-issue-invoice')));
    await tester.pumpAndSettle();
    expect(api.issueCalls, 1);
  });

  testWidgets('issued invoice details are read-only and expose PDF/status',
      (tester) async {
    final api = _DetailApi(_detail('VAT_EXCLUSIVE', status: 'ISSUED'));
    await tester.pumpWidget(MaterialApp(
        home: InvoiceDetailsScreen(invoiceId: 9, session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-invoice-draft')), findsNothing);
    expect(
        find.byKey(const ValueKey('issue-invoice-from-detail')), findsNothing);
    expect(find.text('View / Share Invoice PDF'), findsOneWidget);
    expect(find.textContaining('Journal #44'), findsOneWidget);
    expect(find.text('24-08-2026'), findsOneWidget);
    expect(find.text('Concrete batched'), findsOneWidget);
    expect(find.text('30.00 m³ × ₦15,000.00 = ₦450,000.00'), findsOneWidget);
    expect(find.text('CEH-CN-000001'), findsOneWidget);
    expect(api.issueCalls, 0);
  });
}
