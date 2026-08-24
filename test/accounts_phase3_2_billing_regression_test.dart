import 'dart:io';

import 'package:ceh/core/api_client.dart';
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

class _InvoiceApi extends CehApiClient {
  Map<String, dynamic>? savedPayload;
  bool issued = false;

  @override
  Future<List<CehClient>> clients(CehSession session,
          {bool activeOnly = true, String? status}) async =>
      const [CehClient(id: 7, name: 'ABC Construction', isActive: true)];

  @override
  Future<List<FinancialAccount>> financialAccounts(CehSession session) async =>
      const [
        FinancialAccount(
            id: 41,
            code: '4100',
            name: 'Concrete Production Revenue',
            accountType: 'INCOME',
            isPostable: true,
            isActive: true)
      ];

  @override
  Future<Map<String, dynamic>> taxConfiguration(CehSession session) async => {
        'tax_codes': [
          {
            'id': 3,
            'code': 'VAT_STD',
            'name': 'Standard VAT',
            'tax_type': 'VAT',
            'rate_percent': '7.500000',
            'effective_from': '2020-02-01',
            'effective_to': null,
            'is_active': '1'
          }
        ]
      };

  @override
  Future<List<BillableProductionReport>> billableProductionReports(
          CehSession session, int clientId) async =>
      const [];

  @override
  Future<Map<String, dynamic>> saveInvoice(
      CehSession session, Map<String, dynamic> payload) async {
    savedPayload = payload;
    return {'id': 9, 'reference': 'CEH-INV-000001', 'status': 'DRAFT'};
  }

  @override
  Future<void> issueInvoice(CehSession session, int invoiceId) async {
    issued = true;
  }
}

Future<void> _selectDropdown(
    WidgetTester tester, Finder field, String option) async {
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('manual 30 x 15000 VAT-exclusive Advance Payment saves a Draft',
      (tester) async {
    final api = _InvoiceApi();
    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditorScreen(session: _admin, api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Issue Invoice'), findsNothing,
        reason: 'Issue is available only from saved Draft details.');

    await _selectDropdown(tester,
        find.byType(DropdownButtonFormField<CehClient>), 'ABC Construction');
    await tester.enterText(
        find.byKey(const ValueKey('invoice-quantity')), '30');
    await tester.enterText(find.byKey(const ValueKey('invoice-rate')), '15000');
    await tester.enterText(find.byType(TextField).at(2), 'Concrete batched');
    await _selectDropdown(
        tester, find.byType(DropdownButtonFormField<String>), 'VAT Exclusive');
    await _selectDropdown(tester, find.byType(DropdownButtonFormField<int>),
        'Standard VAT • 7.50%');

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Draft'));
    await tester.pumpAndSettle();

    final payload = api.savedPayload!;
    expect(payload['payment_term'], 'ADVANCE_PAYMENT');
    expect(payload['due_date'], isNull);
    expect(payload['vat_mode'], 'VAT_EXCLUSIVE');
    expect(payload['vat_tax_code_id'], 3);
    final line = (payload['lines'] as List).single as Map<String, dynamic>;
    expect(line['source_type'], 'MANUAL');
    expect(line['production'], isNull);
    expect(line['quantity'], '30.00');
    expect(line['unit_price'], '15000.00');
    expect(line['amount'], '450000.00');
    expect(line['revenue_account_id'], 41);
    expect(api.issued, isFalse);
  });

  test('invoice backend preserves Draft and Issue transaction boundaries', () {
    final save = File('Server/invoice_save.php').readAsStringSync();
    final issue = File('Server/invoice_issue.php').readAsStringSync();
    final common = File('Server/accounts_common.php').readAsStringSync();
    expect(save, contains("'source_type']==='PRODUCTION_REPORT'"));
    expect(save, contains('INVOICE_DRAFT_SAVED'));
    expect(save, isNot(contains('accounts_post_journal')));
    expect(issue, contains('accounts_post_journal'));
    expect(issue, contains("WHERE id=? AND status='DRAFT'"));
    expect(common, contains('if (\$db->inTransaction()) \$db->rollBack()'));
  });
}
