import 'dart:io';
import 'dart:typed_data';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/accounts_formatters.dart';
import 'package:ceh/models/accounts.dart';
import 'package:ceh/models/client.dart';
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

class _PaymentApi extends CehApiClient {
  Map<String, dynamic>? saved;
  Map<String, dynamic>? posted;
  Map<String, dynamic>? creditApplied;
  final List<Map<String, dynamic>> evidenceUploads = [];

  @override
  Future<Map<String, dynamic>> taxConfiguration(CehSession session) async => {
        'tax_codes': [
          {
            'id': 21,
            'code': 'WHT_SERVICES',
            'name': 'General Services',
            'tax_type': 'WHT',
            'rate_percent': '2.000000',
            'calculation_base': 'GROSS',
            'effective_from': '2025-01-01',
            'effective_to': null,
            'is_active': 1,
          },
          {
            'id': 22,
            'code': 'WHT_PROFESSIONAL',
            'name': 'Professional',
            'tax_type': 'WHT',
            'rate_percent': '5.000000',
            'calculation_base': 'NET',
            'effective_from': '2025-01-01',
            'effective_to': null,
            'is_active': 1,
          },
          {
            'id': 23,
            'code': 'WHT_OLD',
            'name': 'Expired',
            'tax_type': 'WHT',
            'rate_percent': '1.000000',
            'calculation_base': 'GROSS',
            'effective_from': '2020-01-01',
            'effective_to': '2024-12-31',
            'is_active': 1,
          }
        ]
      };

  @override
  Future<List<CehClient>> clients(CehSession session,
          {bool activeOnly = true, String? status}) async =>
      const [CehClient(id: 7, name: 'ABC Construction', isActive: true)];

  @override
  Future<List<CehBankAccount>> bankAccounts(CehSession session) async => const [
        CehBankAccount(
            id: 2,
            name: 'Zenith Bank',
            currency: 'NGN',
            currentBalance: 0,
            statementBalance: null,
            unreconciledCount: 0)
      ];

  @override
  Future<List<BillingInvoice>> outstandingInvoices(
          CehSession session, int clientId) async =>
      const [
        BillingInvoice(
            id: 4,
            reference: 'CEH-INV-000004',
            client: 'ABC Construction',
            status: 'ISSUED',
            projectNames: 'Epe',
            total: 483750,
            outstanding: 483750),
        BillingInvoice(
            id: 5,
            reference: 'CEH-INV-000005',
            client: 'ABC Construction',
            status: 'PART_PAID',
            projectNames: 'Badagry • Epe',
            total: 300000,
            outstanding: 200000),
      ];

  @override
  Future<Map<String, dynamic>> saveCustomerReceipt(
      CehSession session, Map<String, dynamic> payload) async {
    saved = payload;
    return {'id': 11, 'reference': 'CEH-RCP-000011', 'status': 'DRAFT'};
  }

  @override
  Future<Map<String, dynamic>> postCustomerPayment(
      CehSession session, Map<String, dynamic> payload) async {
    posted = payload;
    return {'id': 11, 'reference': 'CEH-RCP-000011', 'status': 'POSTED'};
  }

  @override
  Future<void> uploadFinancialEvidence(CehSession session,
      {required String sourceType,
      required int sourceRecordId,
      required String filename,
      required String mimeType,
      required Uint8List bytes}) async {
    evidenceUploads.add({
      'source_type': sourceType,
      'source_record_id': sourceRecordId,
      'filename': filename,
    });
  }

  @override
  Future<int> uploadFinancialEvidenceRecord(CehSession session,
      {required String sourceType,
      required int sourceRecordId,
      required String filename,
      required String mimeType,
      required Uint8List bytes}) async {
    evidenceUploads.add({
      'source_type': sourceType,
      'source_record_id': sourceRecordId,
      'filename': filename,
    });
    return 99;
  }

  @override
  Future<double> availableCustomerCredit(
          CehSession session, int clientId) async =>
      116250;

  @override
  Future<Map<String, dynamic>> applyCustomerCredit(
      CehSession session, Map<String, dynamic> payload) async {
    creditApplied = payload;
    return {'total_applied': '116250.00', 'remaining_customer_credit': '0.00'};
  }
}

void main() {
  group('customer payment accounting', () {
    final post = File('Server/customer_receipt_post.php').readAsStringSync();
    final apply = File('Server/customer_advance_apply.php').readAsStringSync();
    final invoices = File('Server/invoices.php').readAsStringSync();
    final statement = File('Server/client_statement.php').readAsStringSync();
    final migration = File('Server/migration_v1_18_customer_payment_wht.sql')
        .readAsStringSync();

    test('v1.18 adds restrictive allocation-specific WHT snapshots only', () {
      expect(migration, contains('qbook_customer_receipt_allocation_wht'));
      expect(migration, contains('UNIQUE KEY uq_receipt_allocation_wht'));
      expect(migration,
          contains('REFERENCES qbook_customer_receipt_allocations(id)'));
      expect(migration, contains('ON DELETE RESTRICT'));
      expect(migration, contains('calculation_base_amount DECIMAL(18,2)'));
      expect(migration, contains('certificate_evidence_id BIGINT UNSIGNED'));
      expect(
          migration,
          isNot(contains(RegExp(r'\b(DROP TABLE|TRUNCATE|DELETE FROM)\b',
              caseSensitive: false))));
      expect(migration, isNot(contains('CASCADE')));
    });

    test('full, partial and multiple allocations credit AR only once', () {
      expect(post, contains(r'$cashAllocated += $cashAmount'));
      expect(post, contains(r'$arCredit = $cashAllocated + $whtAllocated'));
      expect(post, contains("billing_account_role(\$db,'TRADE_RECEIVABLES')"));
      expect(post, contains('DUPLICATE_INVOICE_ALLOCATION'));
      expect(post, contains('INVOICE_OVERALLOCATION'));
      expect(post, contains('RECEIPT_OVERALLOCATION'));
      expect(post, contains('FOR UPDATE'));
    });

    test('overpayment and pure advance credit Customer Advances', () {
      expect(post, contains(r'$unallocatedCash = $cash - $cashAllocated'));
      expect(post, contains("billing_account_role(\$db,'CUSTOMER_ADVANCES')"));
      expect(post, contains(r"$legacyDestination = $arCredit > 0"));
      expect(post, contains("'CUSTOMER_ADVANCES'"));
    });

    test('explicit WHT settles AR and is never inferred', () {
      expect(post, contains("billing_account_role(\$db,'WHT_RECEIVABLE')"));
      expect(post, contains('WHT_MUST_BE_FULLY_ALLOCATED'));
      expect(post, contains(r'$whtAllocated !== $wht'));
      expect(post, isNot(contains(r'cash - $wht')));
      expect(post, contains('qbook_customer_receipt_allocation_wht'));
      expect(post, contains('WHT_CALCULATION_MISMATCH'));
      expect(post, contains('billing_percent_amount'));
      expect(post, contains('CERTIFICATE_PENDING'));
      expect(post, contains('CERTIFICATE_RECEIVED'));
      expect(post, contains('WHT_CERTIFICATE_EVIDENCE_REQUIRED'));
    });

    test('later application uses only calculated customer credit', () {
      expect(apply, contains('cash_allocated'));
      expect(apply, contains('credit_applied'));
      expect(apply, contains('customer_credit_sources'));
      expect(apply, contains('CUSTOMER_CREDIT_INTEGRITY_ERROR'));
      expect(apply, contains("billing_account_role(\$db,'CUSTOMER_ADVANCES')"));
      expect(apply, contains("billing_account_role(\$db,'TRADE_RECEIVABLES')"));
    });

    test('credit application is client-locked, multi-invoice and cash-free',
        () {
      expect(apply, contains("r.client_id=? AND r.status='POSTED'"));
      expect(apply, contains('FOR UPDATE'));
      expect(apply, contains('DUPLICATE_INVOICE_ALLOCATION'));
      expect(apply, contains('ADVANCE_OVERALLOCATION'));
      expect(apply, contains('INVOICE_OVERALLOCATION'));
      expect(
          apply, isNot(contains("billing_account_role(\$db, 'ZENITH_BANK')")));
      expect(apply,
          isNot(contains("billing_account_role(\$db, 'OUTPUT_VAT_PAYABLE')")));
      expect(apply,
          isNot(contains("billing_account_role(\$db, 'WHT_RECEIVABLE')")));
      expect(apply, isNot(contains("account_type='INCOME'")));
      expect(apply, isNot(contains('INSERT INTO qbook_customer_receipts')));
    });

    test('cross-client, outstanding and fully settled safety remains', () {
      expect(post, contains('INVOICE_ALLOCATION_MISMATCH'));
      expect(post, contains(r"(int)$invoice['client_id']"));
      expect(invoices, contains('outstanding_only'));
      expect(
          invoices, contains(r'if($outstandingOnly&&$outstanding<=0)continue'));
      expect(invoices, contains("i.status='ISSUED'"));
      expect(invoices, contains('GROUP_CONCAT(DISTINCT p.name'));
    });

    test('client statement uses allocations, not legacy destination', () {
      expect(statement, contains('qbook_customer_receipt_allocations'));
      expect(statement, contains('SUM(a.cash_amount+a.wht_amount)'));
      expect(statement, isNot(contains("r.destination='TRADE_RECEIVABLES'")));
    });

    test('payment posting never duplicates Revenue or VAT', () {
      expect(post, isNot(contains("'OUTPUT_VAT_PAYABLE'")));
      expect(post, isNot(contains("account_type='INCOME'")));
      expect(post, isNot(contains("'source_module' => 'INVOICE'")));
    });
  });

  testWidgets('business-facing payment supports multiple invoice allocations',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PaymentApi();
    await tester.pumpWidget(
        MaterialApp(home: CustomerPaymentScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Customer Payment'), findsOneWidget);
    expect(find.text('Accounting destination'), findsNothing);
    expect(find.text('Save / Post Payment'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<CehClient>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC Construction').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('CEH-INV-000004 • Epe'), findsOneWidget);
    expect(
        find.textContaining('CEH-INV-000005 • Badagry • Epe'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), '600000');
    await tester.pump();
    await tester.enterText(fields.at(0), '483750');
    await tester.enterText(fields.at(1), '100000');
    await tester.pump();
    expect(find.text('₦16,250.00'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<CehBankAccount>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zenith Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-post-customer-payment')));
    await tester.pumpAndSettle();

    expect(api.saved, isNotNull);
    expect(api.saved, isNot(contains('destination')));
    expect(api.posted?['receipt_id'], 11);
    expect((api.posted?['allocations'] as List).length, 2);
    expect(api.posted, isNot(contains('wht_amount')));
    expect((api.posted?['allocations'] as List).first,
        isNot(contains('wht_amount')));
  });

  testWidgets('explicit WHT is configured per invoice allocation',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PaymentApi();
    await tester.pumpWidget(
        MaterialApp(home: CustomerPaymentScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<CehClient>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('payment-amount-received')), '100000');
    await tester.enterText(
        find.byKey(const ValueKey('payment-allocation-4')), '100000');
    await tester.tap(find.byKey(const ValueKey('payment-wht-4')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Expired'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('payment-wht-code-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('General Services').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('payment-wht-base-4')), '100000');
    await tester.enterText(
        find.byKey(const ValueKey('payment-allocation-4')), '100000');
    await tester.pump();
    expect(find.text('₦2,000.00'), findsWidgets);
    expect(find.textContaining('Calculation base: Gross'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<CehBankAccount>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zenith Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-post-customer-payment')));
    await tester.pumpAndSettle();
    final row = (api.posted!['allocations'] as List).first as Map;
    expect(row['cash_amount'], '100000.00');
    expect(row['wht_amount'], '2000.00');
    expect(row['wht_tax_code_id'], 21);
    expect(row['wht_calculation_base_amount'], '100000.00');
    expect(row['certificate_status'], 'CERTIFICATE_PENDING');
  });

  testWidgets('multiple invoices retain different explicit WHT treatments',
      (tester) async {
    tester.view.physicalSize = const Size(900, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PaymentApi();
    await tester.pumpWidget(
        MaterialApp(home: CustomerPaymentScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<CehClient>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('payment-amount-received')), '150000');
    for (final id in [4, 5]) {
      await tester.enterText(
          find.byKey(ValueKey('payment-allocation-$id')), '75000');
      await tester.tap(find.byKey(ValueKey('payment-wht-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('payment-wht-code-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find
          .textContaining(id == 4 ? 'General Services' : 'Professional')
          .last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(ValueKey('payment-wht-base-$id')), '50000');
    }
    await tester.tap(find.byType(DropdownButtonFormField<CehBankAccount>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zenith Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-post-customer-payment')));
    await tester.pumpAndSettle();
    final rows = api.posted!['allocations'] as List;
    expect(rows[0]['wht_amount'], '1000.00');
    expect(rows[0]['wht_tax_code_id'], 21);
    expect(rows[1]['wht_amount'], '2500.00');
    expect(rows[1]['wht_tax_code_id'], 22);
  });

  testWidgets('WHT settlement cannot exceed invoice outstanding',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PaymentApi();
    await tester.pumpWidget(
        MaterialApp(home: CustomerPaymentScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<CehClient>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('payment-amount-received')), '483750');
    await tester.enterText(
        find.byKey(const ValueKey('payment-allocation-4')), '483750');
    await tester.tap(find.byKey(const ValueKey('payment-wht-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-wht-code-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('General Services').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('payment-wht-base-4')), '100000');
    await tester.enterText(
        find.byKey(const ValueKey('payment-allocation-4')), '483750');
    await tester.tap(find.byType(DropdownButtonFormField<CehBankAccount>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zenith Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-post-customer-payment')));
    await tester.pump();
    expect(find.textContaining('settlement exceeds its outstanding balance'),
        findsOneWidget);
    expect(api.saved, isNull);
  });

  testWidgets('received WHT certificate requires attachment', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PaymentApi();
    await tester.pumpWidget(
        MaterialApp(home: CustomerPaymentScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<CehClient>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('payment-amount-received')), '100000');
    await tester.enterText(
        find.byKey(const ValueKey('payment-allocation-4')), '90000');
    await tester.tap(find.byKey(const ValueKey('payment-wht-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-wht-code-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('General Services').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('payment-wht-base-4')), '100000');
    await tester.tap(find.byKey(const ValueKey('payment-wht-certificate-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Received').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<CehBankAccount>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zenith Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-post-customer-payment')));
    await tester.pump();
    expect(find.textContaining('attach the received WHT certificate'),
        findsOneWidget);
    expect(api.saved, isNull);
  });

  test('WHT percentage uses exact integer minor-unit rounding', () {
    expect(calculateTaxMinorUnits(10000000, '2.000000'), 200000);
    expect(calculateTaxMinorUnits(33333, '5.000000'), 1667);
  });

  testWidgets(
      'payment prevents allocation before received amount and never shows negative credit',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PaymentApi();
    await tester.pumpWidget(
        MaterialApp(home: CustomerPaymentScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<CehClient>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC Construction').last);
    await tester.pumpAndSettle();
    final allocation = tester
        .widget<TextField>(find.byKey(const ValueKey('payment-allocation-4')));
    expect(allocation.enabled, isFalse);
    expect(find.textContaining('−₦'), findsNothing);
  });

  testWidgets('existing customer credit applies to one or multiple invoices',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PaymentApi();
    await tester.pumpWidget(MaterialApp(
        home: ApplyCustomerCreditScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<CehClient>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC Construction').last);
    await tester.pumpAndSettle();
    expect(find.text('₦116,250.00'), findsWidgets);
    await tester.enterText(
        find.byKey(const ValueKey('credit-allocation-4')), '100000');
    await tester.enterText(
        find.byKey(const ValueKey('credit-allocation-5')), '16250');
    await tester.pump();
    expect(find.text('₦0.00'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('apply-customer-credit-submit')));
    await tester.pumpAndSettle();
    final rows = api.creditApplied?['allocations'] as List;
    expect(rows, hasLength(2));
    expect(rows.first['amount'], '100000.00');
    expect(rows.last['amount'], '16250.00');
  });

  testWidgets('customer credit over-application is rejected locally',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PaymentApi();
    await tester.pumpWidget(MaterialApp(
        home: ApplyCustomerCreditScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<CehClient>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('credit-allocation-4')), '116251');
    await tester
        .tap(find.byKey(const ValueKey('apply-customer-credit-submit')));
    await tester.pump();
    expect(find.text('Total Applied cannot exceed Available Customer Credit.'),
        findsOneWidget);
    expect(api.creditApplied, isNull);
  });

  test('NGN formatter groups and parses exact minor units', () {
    const formatter = NgnAmountInputFormatter();
    final formatted = formatter.formatEditUpdate(
        const TextEditingValue(),
        const TextEditingValue(
            text: '116250', selection: TextSelection.collapsed(offset: 6)));
    expect(formatted.text, '116,250');
    expect(parseNgnMinorUnits('116,250.00'), 11625000);
    expect(ngnMinorUnitsForApi(11625000), '116250.00');
    expect(normalizeNgnInput('1,16,250'), isNull);
  });
}
