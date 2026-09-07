import 'dart:io';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/accounts.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_journal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1, fullName: 'Admin', email: '', role: 'ADMIN', isActive: true));
const _operator = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 2,
        fullName: 'Operator',
        email: '',
        role: 'OPERATOR',
        isActive: true));

class _JournalApi extends CehApiClient {
  const _JournalApi();
  @override
  Future<AccountsPage<FinancialJournalSummary>> financialJournals(
          CehSession session,
          {int page = 1,
          int pageSize = 25,
          Map<String, String> filters = const {}}) async =>
      AccountsPage(items: const [
        FinancialJournalSummary(
            id: 7,
            reference: 'CEH-JRN-000007',
            date: '2026-08-31',
            description: 'Issued invoice',
            sourceType: 'INVOICE',
            sourceRecordId: 3,
            entryKind: 'ORIGINAL',
            status: 'POSTED',
            createdBy: 'Admin',
            postedBy: 'Admin',
            totalDebit: 125000,
            totalCredit: 125000)
      ], page: page, pageSize: pageSize, total: 51, totalPages: 3);
  @override
  Future<FinancialJournalDetail> financialJournal(
          CehSession session, int journalId) async =>
      const FinancialJournalDetail(
          summary: FinancialJournalSummary(
              id: 7,
              reference: 'CEH-JRN-000007',
              date: '2026-08-31',
              description: 'Issued invoice',
              sourceType: 'INVOICE',
              sourceRecordId: 3,
              entryKind: 'ORIGINAL',
              status: 'POSTED',
              createdBy: 'Admin',
              postedBy: 'Admin',
              totalDebit: 125000,
              totalCredit: 125000),
          lines: [
            FinancialJournalLine(
                lineNo: 1,
                accountCode: '1100',
                accountName: 'Trade Receivables',
                description: 'Invoice',
                debit: 125000,
                credit: 0,
                client: 'ABC Construction',
                project: 'Epe',
                equipment: '307'),
            FinancialJournalLine(
                lineNo: 2,
                accountCode: '4000',
                accountName: 'Revenue',
                description: 'Concrete supply',
                debit: 0,
                credit: 125000)
          ],
          reversalJournalId: 8,
          reversalReference: 'CEH-JRN-000008');
  @override
  Future<List<FinancialAccount>> financialAccounts(CehSession session) async =>
      const [
        FinancialAccount(
            id: 1,
            code: '1100',
            name: 'Trade Receivables',
            accountType: 'ASSET',
            isPostable: true,
            isActive: true)
      ];
  @override
  Future<AccountLedgerPage> accountLedger(CehSession session,
          {required int accountId,
          int page = 1,
          int pageSize = 50,
          Map<String, String> filters = const {}}) async =>
      AccountLedgerPage(
          account: const FinancialAccount(
              id: 1,
              code: '1100',
              name: 'Trade Receivables',
              accountType: 'ASSET',
              isPostable: true,
              isActive: true),
          openingBalance: 50000,
          entries: [
            AccountLedgerEntry(
                id: page,
                journalId: 7,
                date: '2026-08-31',
                journalReference: 'CEH-JRN-000007',
                description: 'Issued invoice',
                sourceType: 'INVOICE',
                debit: 125000,
                credit: 0,
                runningBalance: 175000)
          ],
          page: page,
          pageSize: pageSize,
          total: 120,
          totalPages: 3);
}

Widget _app(CehSession session) => CehViewModeScope(
    controller: CehViewModeController(),
    child: MaterialApp(
        theme: CehTheme.light(),
        home:
            AccountsJournalScreen(session: session, api: const _JournalApi())));

void main() {
  test('journal and ledger models preserve authoritative totals and balances',
      () {
    final detail = FinancialJournalDetail.fromJson({
      'id': 1,
      'reference_no': 'J1',
      'transaction_date': '2026-08-31',
      'description': 'Memo',
      'source_module': 'INVOICE',
      'source_record_id': 2,
      'entry_kind': 'ORIGINAL',
      'status': 'POSTED',
      'created_by_name': 'Admin',
      'approved_by_name': 'Admin',
      'lines': [
        {
          'line_no': 1,
          'account_code': '1100',
          'account_name': 'Receivables',
          'debit': '10.00',
          'credit': '0.00'
        },
        {
          'line_no': 2,
          'account_code': '4000',
          'account_name': 'Revenue',
          'debit': '0.00',
          'credit': '10.00'
        }
      ]
    });
    expect(detail.summary.balances, isTrue);
    expect(detail.lines.length, 2);
    final entry = AccountLedgerEntry.fromJson({
      'id': 1,
      'journal_id': 2,
      'transaction_date': '2026-08-31',
      'journal_reference': 'J1',
      'source_module': 'INVOICE',
      'debit': '10.00',
      'credit': '0.00',
      'running_balance': '35.00'
    });
    expect(entry.runningBalance, 35);
  });

  testWidgets('journal surface is Admin only and exposes no mutation action',
      (tester) async {
    await tester.pumpWidget(_app(_operator));
    expect(find.text('Administrator access required.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_app(_admin));
    await tester.pumpAndSettle();
    expect(find.text('CEH-JRN-000007'), findsOneWidget);
    expect(find.textContaining('Post Journal'), findsNothing);
    expect(find.textContaining('Reverse Journal'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
  });

  testWidgets(
      'journal details show dimensions, balanced totals and reversal link',
      (tester) async {
    await tester.pumpWidget(_app(_admin));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CEH-JRN-000007'));
    await tester.pumpAndSettle();
    expect(find.text('Immutable journal lines'), findsOneWidget);
    expect(find.textContaining('Trade Receivables'), findsOneWidget);
    expect(find.text('Client: ABC Construction'), findsOneWidget);
    expect(find.text('Project: Epe'), findsOneWidget);
    expect(find.text('Equipment: 307'), findsOneWidget);
    expect(find.text('Journal balances'), findsOneWidget);
    expect(find.textContaining('Reversed by CEH-JRN-000008'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('journal-source-drilldown')), findsOneWidget);
  });

  testWidgets(
      'ledger shows authoritative opening and running balance with paging',
      (tester) async {
    await tester.pumpWidget(_app(_admin));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account Ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('1100').last);
    await tester.pumpAndSettle();
    expect(find.text('Opening balance'), findsOneWidget);
    expect(find.textContaining('50,000.00'), findsOneWidget);
    expect(find.textContaining('175,000.00'), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
  });

  test('backend is paginated read-only and ledger calculates before LIMIT', () {
    final journal = File('Server/financial_journals.php').readAsStringSync();
    final ledger = File('Server/account_ledger.php').readAsStringSync();
    expect(journal, contains("qbook_require_role(\$user,['ADMIN'])"));
    expect(journal, contains("production_require_method('GET')"));
    expect(journal, contains(r'LIMIT {$pageSize} OFFSET {$offset}'));
    expect(ledger, contains('SUM(l.debit-l.credit) OVER'));
    expect(ledger.indexOf('SUM(l.debit-l.credit) OVER'),
        lessThan(ledger.indexOf(r'LIMIT {$pageSize} OFFSET {$offset}')));
    for (final forbidden in [
      'financial_journal_post.php',
      'financial_journal_reverse.php',
      'DELETE FROM qbook_financial_journals'
    ]) {
      expect(
          File('lib/screens/accounts/accounts_journal_screen.dart')
              .readAsStringSync(),
          isNot(contains(forbidden)));
    }
  });
}
