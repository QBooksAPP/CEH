import 'dart:io';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/accounts.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_journal_screen.dart';
import 'package:ceh/screens/accounts/accounts_wht_certificates_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const admin = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1, fullName: 'Admin', email: '', role: 'ADMIN', isActive: true));
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

class Phase2Api extends CehApiClient {
  const Phase2Api();
  @override
  Future<AccountsPage<FinancialJournalSummary>> financialJournals(CehSession s,
          {int page = 1,
          int pageSize = 25,
          Map<String, String> filters = const {}}) async =>
      AccountsPage(
          items: const [], page: 1, pageSize: 25, total: 0, totalPages: 0);
  @override
  Future<List<FinancialAccount>> financialAccounts(CehSession s) async =>
      const [];
  @override
  Future<TrialBalanceReport> trialBalance(CehSession s,
          {Map<String, String> filters = const {}}) async =>
      const TrialBalanceReport(
          accounts: [
            TrialBalanceAccount(
                accountId: 1,
                code: '1100',
                name: 'Trade Receivables',
                debit: 100000,
                credit: 0),
            TrialBalanceAccount(
                accountId: 2,
                code: '4000',
                name: 'Revenue',
                debit: 0,
                credit: 100000)
          ],
          totalDebit: 100000,
          totalCredit: 100000,
          balanced: true,
          dateTo: '2026-09-01');
  @override
  Future<List<WhtCertificateRecord>> whtCertificates(CehSession s,
          {Map<String, String> filters = const {}}) async =>
      const [
        WhtCertificateRecord(
            recordType: 'ALLOCATION',
            recordId: 7,
            receiptId: 3,
            clientId: 2,
            client: 'ABC Construction',
            receiptReference: 'CEH-RCP-000003',
            paymentDate: '2026-09-01',
            amount: 5000,
            status: 'CERTIFICATE_PENDING',
            createdAt: '2026-09-01',
            allocationWhtId: 7,
            invoiceId: 4,
            invoiceReference: 'CEH-INV-000004')
      ];
}

Widget app(Widget child) => CehViewModeScope(
    controller: CehViewModeController(),
    child: MaterialApp(theme: CehTheme.light(), home: child));

void main() {
  test('models parse authoritative Trial Balance and both WHT record shapes',
      () {
    final report = TrialBalanceReport.fromJson({
      'basis': {'date_to': '2026-09-01'},
      'accounts': [
        {
          'account_id': '1',
          'account_code': '1100',
          'account_name': 'Trade Receivables',
          'debit_balance': '20.00',
          'credit_balance': '0.00'
        }
      ],
      'total_debit': '20.00',
      'total_credit': '20.00',
      'balanced': true
    });
    expect(report.balanced, isTrue);
    expect(report.totalDebit, report.totalCredit);
    expect(report.accounts.single.code, '1100');
    final legacy = WhtCertificateRecord.fromJson({
      'record_type': 'RECEIPT',
      'record_id': 1,
      'receipt_id': 2,
      'client_id': 3,
      'client_name_snapshot': 'Client',
      'receipt_reference': 'CEH-RCP-000002',
      'receipt_date': '2026-09-01',
      'accepted_amount': '50.00',
      'certificate_status': 'CERTIFICATE_RECEIVED',
      'certificate_evidence_id': '9',
      'created_at': '2026-09-01'
    });
    expect(legacy.allocationWhtId, isNull);
    expect(legacy.evidenceId, 9);
    expect(legacy.isPending, isFalse);
  });

  testWidgets(
      'Trial Balance is Admin only, balanced and has no mutation controls',
      (tester) async {
    await tester.pumpWidget(
        app(AccountsJournalScreen(session: admin, api: const Phase2Api())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trial Balance'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trade Receivables'), findsOneWidget);
    expect(find.text('Total debits equal total credits'), findsOneWidget);
    expect(find.textContaining('Post'), findsNothing);
    expect(find.textContaining('Reverse'), findsNothing);
    await tester.pumpWidget(app(AccountsJournalScreen(
        session: operatorSession, api: const Phase2Api())));
    expect(find.text('Administrator access required.'), findsOneWidget);
  });

  testWidgets(
      'WHT list exposes pending business context and Admin-only receipt workflow',
      (tester) async {
    await tester.pumpWidget(
        app(WhtCertificatesScreen(session: admin, api: const Phase2Api())));
    await tester.pumpAndSettle();
    expect(find.text('ABC Construction'), findsOneWidget);
    expect(find.textContaining('CEH-RCP-000003'), findsOneWidget);
    expect(find.textContaining('CEH-INV-000004'), findsOneWidget);
    await tester.tap(find.text('ABC Construction'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('receive-wht-certificate')), findsOneWidget);
    await tester.pumpWidget(app(WhtCertificatesScreen(
        session: operatorSession, api: const Phase2Api())));
    expect(find.text('Administrator access required.'), findsOneWidget);
  });

  test(
      'server contracts preserve authoritative accounting, evidence, audit and duplicate safety',
      () {
    final trial = File('Server/trial_balance.php').readAsStringSync(),
        list = File('Server/wht_certificates.php').readAsStringSync(),
        update = File('Server/wht_certificate_update.php').readAsStringSync(),
        upload =
            File('Server/financial_evidence_upload.php').readAsStringSync();
    expect(trial, contains('qbook_financial_journal_lines'));
    expect(trial, contains("qbook_require_role(\$user, ['ADMIN'])"));
    expect(trial, contains("production_require_method('GET')"));
    expect(trial, contains('total_debit'));
    expect(trial, contains('balanced'));
    expect(list, contains("['PENDING','RECEIVED','ALL']"));
    expect(list, contains("'RECEIPT' record_type"));
    expect(list, contains("'ALLOCATION'"));
    expect(list, contains('certificate_evidence_id'));
    expect(upload, contains("'WHT_CERTIFICATE'"));
    expect(update, contains("source_type='WHT_CERTIFICATE'"));
    expect(update, contains('WHT_CERTIFICATE_ALREADY_RECEIVED'));
    expect(update, contains("'WHT_CERTIFICATE_RECEIVED'"));
    expect(update, contains("'journal_created'=>false"));
    expect(update, isNot(contains('accounts_post_journal')));
  });
}
