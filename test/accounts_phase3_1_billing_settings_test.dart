import 'dart:io';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/accounts_formatters.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_billing_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const adminSession = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1,
        fullName: 'Admin',
        email: 'admin@example.invalid',
        role: 'ADMIN',
        isActive: true));
const operatorSession = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 2,
        fullName: 'Operator',
        email: 'operator@example.invalid',
        role: 'OPERATOR',
        isActive: true));

class BillingSettingsApi extends CehApiClient {
  const BillingSettingsApi();
  @override
  Future<Map<String, dynamic>> taxConfiguration(CehSession session) async => {
        'tax_codes': [
          {
            'id': 1,
            'code': 'VAT_STD',
            'name': 'Standard VAT',
            'tax_type': 'VAT',
            'rate_percent': '7.500000',
            'calculation_base': 'NET',
            'effective_from': '2020-02-01',
            'effective_to': null,
            'is_active': '1'
          },
          {
            'id': 2,
            'code': 'WHT_SERVICES',
            'name': 'General Services',
            'tax_type': 'WHT',
            'rate_percent': '2.000000',
            'calculation_base': 'GROSS',
            'effective_from': '2025-01-01',
            'effective_to': null,
            'is_active': '1'
          }
        ],
        'invoice_settings': {
          'default_terms': 'ADVANCE_PAYMENT',
          'default_terms_text': 'Advance Payment'
        }
      };
}

void main() {
  testWidgets('Billing Settings is Admin-only', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AccountsBillingSettingsScreen(
            session: operatorSession, api: BillingSettingsApi())));
    expect(find.text('Administrator access required.'), findsOneWidget);
  });

  testWidgets('Admin sees effective tax history and invoice settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AccountsBillingSettingsScreen(
            session: adminSession, api: BillingSettingsApi())));
    await tester.pumpAndSettle();
    expect(find.textContaining('VAT_STD'), findsOneWidget);
    expect(find.textContaining('WHT_SERVICES'), findsOneWidget);
    expect(find.textContaining('01-02-2020'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-tax-code')), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-invoice-settings')), findsOneWidget);
    expect(find.text('Advance Payment'), findsWidgets);
  });

  testWidgets('narrow Android layout uses full-width readable sections',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
        home: AccountsBillingSettingsScreen(
            session: adminSession, api: BillingSettingsApi())));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text('Tax Configuration'));
    final card = tester.getRect(find.byType(Card).first);
    expect(title.width, greaterThan(120));
    expect(card.width, greaterThan(300));
    expect(find.textContaining('VAT • 7.50%'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-invoice-settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Billing percentages always display exactly two decimals', () {
    expect(formatBillingTaxRate('7.500000'), '7.50%');
    expect(formatBillingTaxRate('2'), '2.00%');
    expect(formatBillingTaxRate(5), '5.00%');
    expect(formatBillingTaxRate('10.000000'), '10.00%');
  });

  test('backend owns tax roles and preserves rate history', () {
    final php = File('Server/tax_configuration.php').readAsStringSync();
    expect(
        php, contains("\$type==='VAT'?'OUTPUT_VAT_PAYABLE':'WHT_RECEIVABLE'"));
    expect(php, contains("\$action==='SET_ACTIVE'"));
    expect(php, isNot(contains('UPDATE qbook_tax_codes SET rate_percent')));
    expect(php, contains('INVALID_TAX_EFFECTIVE_DATES'));
  });

  test('effective-dated defaults are data seeds, not app constants', () {
    final sql = File('Server/migration_v1_16_billing_tax_defaults.sql')
        .readAsStringSync();
    for (final code in [
      'VAT_STD',
      'WHT_CONSTRUCTION',
      'WHT_CONSTRUCTION_OTHER',
      'WHT_SERVICES',
      'WHT_PROFESSIONAL',
      'WHT_RENT_HIRE_LEASE'
    ]) {
      expect(sql, contains(code));
    }
    expect(sql, contains("'OUTPUT_VAT_PAYABLE','2020-02-01'"));
    expect(sql, contains("'WHT_RECEIVABLE','2025-01-01'"));
    expect(File('lib/core/api_client.dart').readAsStringSync(),
        isNot(contains("rate_percent': '7.5")));
  });

  test('invoice settings endpoint is authenticated and audited', () {
    final php = File('Server/invoice_settings_update.php').readAsStringSync();
    expect(php, contains('billing_require_admin()'));
    expect(php, contains('ADVANCE_PAYMENT'));
    expect(php, contains('INVOICE_SETTINGS_UPDATED'));
    expect(php, contains('qbook_invoice_settings'));
  });
}
