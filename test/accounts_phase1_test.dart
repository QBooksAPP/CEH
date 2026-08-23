import 'dart:io';

import 'package:ceh/models/accounts.dart';
import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final migration = source('Server/migration_v1_10_accounts_phase1.sql');
  final engine = source('Server/accounts_common.php');
  final funding = source('Server/petty_cash_fund.php');
  final submit = source('Server/petty_cash_expense_submit.php');
  final review = source('Server/petty_cash_expense_review.php');
  final expenses = source('Server/petty_cash_expenses.php');
  final bankImport = source('Server/bank_statement_import.php');
  final bankMatch = source('Server/bank_reconcile.php');
  final evidenceUpload = source('Server/financial_evidence_upload.php');
  final evidenceGet = source('Server/financial_evidence_get.php');
  final liveUi = source('lib/screens/accounts/accounts_live_screens.dart');
  final apiClient = source('lib/core/api_client.dart');

  test('v1.10 creates restrictive double-entry financial foundation', () {
    for (final table in [
      'qbook_accounts_chart',
      'qbook_financial_journals',
      'qbook_financial_journal_lines',
      'qbook_bank_accounts',
      'qbook_bank_import_batches',
      'qbook_bank_statement_rows',
      'qbook_bank_matches',
      'qbook_petty_cash_custodians',
      'qbook_petty_cash_fundings',
      'qbook_petty_cash_expenses',
      'qbook_financial_evidence',
      'qbook_financial_audit',
    ]) {
      expect(migration, contains('CREATE TABLE $table'));
    }
    expect(migration, isNot(contains('ON DELETE CASCADE')));
    expect(migration, contains('DECIMAL(18,2)'));
    expect(migration, contains('chk_financial_line_one_side'));
  });

  test('approved Chart of Accounts and Zenith are seeded exactly once', () {
    for (final account in [
      "'1000','Assets'",
      "'1011','Zenith Bank'",
      "'1100','Trade Receivables'",
      "'1200','Petty Cash Control'",
      "'1300','Staff Advances'",
      "'1400','Prepayments'",
      "'2000','Liabilities'",
      "'3000','Equity'",
      "'4000','Revenue'",
      "'5000','Direct Costs'",
      "'6000','Operating Expenses'",
      "'7000','Payroll Costs'",
    ]) {
      expect(migration, contains(account));
    }
    expect(RegExp("'1011','Zenith Bank'").allMatches(migration).length, 1);
  });

  test('unbalanced journals reject and balanced journals post atomically', () {
    expect(engine, contains("accounts_fail('UNBALANCED_JOURNAL')"));
    expect(engine, contains(r'$debits !== $credits'));
    expect(migration, contains("status ENUM('POSTED','REVERSED')"),
        reason: 'migration and engine are reviewed together');
    expect(engine, contains(r'if (!$db->inTransaction())'));
    expect(engine, contains('qbook_financial_journal_lines'));
  });

  test('duplicate source posting is rejected and posted journals immutable',
      () {
    expect(migration, contains('uq_financial_journal_source'));
    expect(engine, contains("accounts_fail('SOURCE_ALREADY_POSTED', 409)"));
    expect(
        Directory('Server')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.contains('journal'))
            .map((file) => file.path)
            .any((path) => path.endsWith('journal_update.php')),
        isFalse);
    expect(engine, isNot(contains('DELETE FROM qbook_financial_journals')));
  });

  test('reversal is linked and inverts original lines', () {
    expect(migration, contains('reversal_of_id BIGINT UNSIGNED NULL'));
    expect(migration, contains('uq_financial_journal_reversal'));
    expect(
        engine,
        contains(
            "'debit_minor' => accounts_money_minor((string)\$line['credit'], false)"));
    expect(
        engine,
        contains(
            "'credit_minor' => accounts_money_minor((string)\$line['debit'], false)"));
    expect(engine, contains("SET status='REVERSED'"));
  });

  test('150k funding is an asset transfer from Zenith to custodian', () {
    expect(funding, contains("accounts_account_id(\$db,'1200')"));
    expect(funding, contains("'source_module'=>'PETTY_CASH_FUNDING'"));
    expect(funding, contains("'debit_minor'=>\$minor"));
    expect(funding, contains("'credit_minor'=>\$minor"));
    expect(funding, isNot(contains('EXPENSE')));
  });

  test('custodian balance and ownership are isolated server-side', () {
    expect(engine, contains('accounts_can_access_custodian'));
    expect(engine, contains("(int)\$user['id'] === \$custodianUserId"));
    expect(expenses, contains("WHERE e.custodian_user_id=?"));
    expect(submit, contains("accounts_fail('FORBIDDEN',403)"));
  });

  test('submission reserves and overspending is rejected', () {
    expect(engine, contains("status IN ('SUBMITTED','CORRECTION_REQUIRED')"));
    expect(submit, contains("SET status='SUBMITTED'"));
    expect(submit, contains("accounts_fail('INSUFFICIENT_PETTY_CASH',409)"));
    expect(submit, contains('RECEIPT_OR_REASON_REQUIRED'));
  });

  test('approval posts once while correction and cancellation preserve rules',
      () {
    expect(review, contains("if(\$e['journal_id']!==null)"));
    expect(review, contains("'source_module'=>'PETTY_CASH_EXPENSE'"));
    expect(review, contains("SET status='APPROVED',journal_id=?"));
    expect(review, contains("status='CORRECTION_REQUIRED'"));
    expect(review, contains("status='CANCELLED_NOT_SPENT'"));
    expect(review, contains("qbook_require_role(\$user,['ADMIN'])"));
  });

  test('bank imports prevent duplicates and suggest ±3 day funding matches',
      () {
    expect(migration, contains('uq_bank_import_file'));
    expect(migration, contains('uq_bank_statement_fingerprint'));
    expect(bankImport,
        contains("accounts_fail('STATEMENT_ALREADY_IMPORTED',409)"));
    expect(bankImport, contains("modify('-3 days')"));
    expect(bankImport, contains("modify('+3 days')"));
    expect(bankImport, contains("'POTENTIAL_MATCH'"));
    expect(bankImport, contains("'POSSIBLE_DUPLICATE'"));
  });

  test('statement import UI stays disabled pending real Zenith mapping', () {
    expect(liveUi, contains('onPressed: null'));
    final prototype =
        source('lib/screens/accounts/accounts_phase1_screens.dart');
    expect(prototype, contains("ValueKey('import-bank-statement')"));
    expect(
      prototype,
      contains('Import Statement — format mapping pending'),
    );
  });

  test('bank reconciliation matches funding without reposting it', () {
    expect(bankMatch, contains('qbook_bank_matches'));
    expect(
        bankMatch,
        contains(
            "['PETTY_CASH_FUNDING','GENERAL_EXPENSE','CUSTOMER_RECEIPT']"));
    expect(bankMatch, contains("SET status='RECONCILED'"));
    expect(bankMatch, isNot(contains('accounts_post_journal')));
  });

  test('project and equipment dimensions reach approved expense journal', () {
    for (final dimension in ['client_id', 'project_id', 'mixer_id']) {
      expect(migration, contains('$dimension BIGINT UNSIGNED NULL'));
      expect(review, contains("'$dimension'=>\$e['$dimension']"));
    }
    expect(engine, contains('PROJECT_CLIENT_MISMATCH'));
  });

  test('receipt evidence is private authorized and integrity checked', () {
    expect(migration, contains("storage_driver ENUM('MYSQL_BLOB'"));
    expect(migration, contains('evidence_data LONGBLOB'));
    expect(evidenceUpload, contains("hash('sha256',\$bytes)"));
    expect(evidenceUpload, contains('8*1024*1024'));
    expect(evidenceGet,
        contains("qbook_json(['ok'=>false,'error'=>'FORBIDDEN'],403)"));
    expect(evidenceGet, contains("hash_equals((string)\$e['sha256']"));
    expect(evidenceGet, contains("header('Cache-Control: private, no-store')"));
  });

  test('Flutter financial models parse MySQL decimal strings safely', () {
    final bank = CehBankAccount.fromJson({
      'id': '1',
      'name': 'Zenith Bank',
      'currency': 'NGN',
      'current_balance': '150000.00',
      'statement_balance': null,
      'unreconciled_count': '2',
    });
    expect(bank.currentBalance, 150000);
    expect(bank.statementBalance, isNull);
    expect(bank.unreconciledCount, 2);

    final overview = PettyCashOverview.fromJson({
      'total_petty_cash': '175000.00',
      'custodians': [
        {
          'user_id': 3,
          'name': 'Segun',
          'role': 'OPERATOR',
          'balance': {
            'funds_received': '150000.00',
            'accounted': '0.00',
            'pending': '30000.00',
            'balance': '150000.00',
            'available': '120000.00',
          },
          'this_month': {
            'funds_received': '400000.00',
            'accounted': '230000.00',
          },
        }
      ]
    });
    expect(overview.totalPettyCash, 175000);
    expect(overview.custodians.single.pending, 30000);
    expect(overview.custodians.single.available, 120000);
    expect(overview.custodians.single.thisMonthFundsReceived, 400000);
    expect(overview.custodians.single.thisMonthAccounted, 230000);
  });

  test('ready Phase 1 screens use authenticated APIs and protected evidence',
      () {
    expect(liveUi, isNot(contains('AccountsMockData')));
    expect(liveUi, contains('bankAccounts(widget.session)'));
    expect(liveUi, contains('pettyCashOverview(widget.session)'));
    expect(liveUi, contains('reviewPettyCashExpense'));
    expect(liveUi, contains('ImageSource.camera'));
    expect(liveUi, contains('ImageSource.gallery'));
    expect(liveUi, contains('uploadFinancialEvidence'));
    expect(apiClient, contains("'financial_evidence_upload.php'"));
    expect(apiClient, contains("'bank_reconcile.php'"));
  });
}
