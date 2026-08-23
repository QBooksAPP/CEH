import 'dart:io';

import 'package:ceh/core/billing_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 3 tax arithmetic', () {
    test('VAT exclusive snapshots net, VAT and gross', () {
      final value = calculateInvoiceTax(
          enteredMinor: 1000000000,
          rateMillionthsOfPercent: 7500000,
          mode: InvoiceVatMode.exclusive);
      expect(value.netMinor, 1000000000);
      expect(value.vatMinor, 75000000);
      expect(value.grossMinor, 1075000000);
    });

    test('VAT inclusive derives net deterministically', () {
      final value = calculateInvoiceTax(
          enteredMinor: 1075000000,
          rateMillionthsOfPercent: 7500000,
          mode: InvoiceVatMode.inclusive);
      expect(value.netMinor, 1000000000);
      expect(value.vatMinor, 75000000);
      expect(value.grossMinor, 1075000000);
    });

    test('non-taxable lines never create VAT', () {
      final value = calculateInvoiceTax(
          enteredMinor: 200000,
          rateMillionthsOfPercent: 7500000,
          mode: InvoiceVatMode.exclusive,
          taxable: false);
      expect(value.vatMinor, 0);
      expect(value.grossMinor, 200000);
    });
  });

  group('production billing controls', () {
    test('partial billing up to signed m3 is allowed', () {
      expect(
          canBillProductionQuantity(
              signed: 100, previouslyBilled: 60, billingNow: 40),
          isTrue);
    });
    test('cumulative billing above signed m3 is rejected', () {
      expect(
          canBillProductionQuantity(
              signed: 100, previouslyBilled: 60, billingNow: 40.01),
          isFalse);
    });

    test('explicit 20 m3 release makes 20 of 100 m3 available', () {
      final effective = effectiveBilledProductionQuantity(
          originallyBilled: 100, explicitlyReleased: 20);
      expect(effective, 80);
      expect(100 - effective, 20);
    });

    test('price-only credit releases no production quantity', () {
      final effective = effectiveBilledProductionQuantity(
          originallyBilled: 100, explicitlyReleased: 0);
      expect(effective, 100);
      expect(100 - effective, 0);
    });
  });

  group('Phase 3 server and migration contracts', () {
    final migration = File('Server/migration_v1_15_billing_receivables.sql')
        .readAsStringSync();
    String server(String name) => File('Server/$name').readAsStringSync();

    test('permanent CEH reference tombstone tables exist', () {
      expect(migration, contains('qbook_invoice_references'));
      expect(migration, contains('qbook_customer_receipt_references'));
      expect(migration, contains('qbook_credit_note_references'));
      expect(server('billing_common.php'), contains("'CEH-INV'"));
      expect(server('billing_common.php'), contains("'CEH-RCP'"));
      expect(server('billing_common.php'), contains("'CEH-CN'"));
    });

    test('approved configurable account roles are seeded', () {
      expect(migration, contains("('1150','WHT Receivable'"));
      expect(migration, contains("('2310','Output VAT Payable'"));
      expect(migration, contains('Customer Advances / Deposits'));
      expect(migration, contains("'OUTPUT_VAT_PAYABLE'"));
      expect(migration, contains("'WHT_RECEIVABLE'"));
      expect(migration, contains("'CUSTOMER_ADVANCES'"));
    });

    test('account seeds resolve parents before MySQL-safe inserts', () {
      expect(migration, contains('@ceh_v115_assets_parent_id'));
      expect(migration, contains('@ceh_v115_tax_liabilities_parent_id'));
      expect(migration, contains('@ceh_v115_liabilities_parent_id'));
      expect(migration, contains('ON DUPLICATE KEY UPDATE code=VALUES(code)'));
      expect(
          migration,
          isNot(contains(
              "('1150','WHT Receivable','ASSET',(SELECT id FROM qbook_accounts_chart")));

      final resume = File('Server/migration_v1_15_resume_after_1093.sql')
          .readAsStringSync();
      expect(resume, contains('v1_15_object_count'));
      expect(resume, contains('@ceh_v115_existing_object_count=0'));
      expect(resume, contains('@ceh_v115_parent_count=3'));
      expect(resume, contains('@ceh_v115_existing_seed_account_count=0'));
      expect(resume, contains('@ceh_v115_conflicting_account_count=0'));
      expect(resume, contains('chk_ceh_v115_resume_guard'));
      expect(resume, contains('CREATE TABLE qbook_financial_account_roles'));
      expect(resume, contains('CREATE TABLE qbook_credit_note_allocations'));
      expect(resume, contains('ALTER TABLE qbook_financial_evidence'));
    });

    test('no statutory tax rate is seeded', () {
      expect(migration, isNot(contains('INSERT INTO qbook_tax_codes')));
      expect(server('invoice_issue.php'), contains('billing_account_role'));
      expect(server('invoice_issue.php'),
          isNot(contains("accounts_account_id(\$db,'2310')")));
    });

    test('invoice posting is AR debit, revenue and VAT credit', () {
      final issue = server('invoice_issue.php');
      expect(issue, contains("billing_account_role(\$db,'TRADE_RECEIVABLES')"));
      expect(
          issue, contains("billing_account_role(\$db,'OUTPUT_VAT_PAYABLE')"));
      expect(issue, contains("'source_module'=>'INVOICE'"));
      expect(issue, contains("'client_id'=>(int)\$i['client_id']"));
    });

    test('receipt posts cash and explicit WHT without revenue', () {
      final receipt = server('customer_receipt_post.php');
      expect(receipt, contains("billing_account_role(\$db,'WHT_RECEIVABLE')"));
      expect(receipt, contains('WHT_MUST_BE_FULLY_ALLOCATED'));
      expect(receipt, isNot(contains("account_type='INCOME'")));
      expect(receipt, contains('CERTIFICATE_PENDING'));
    });

    test('advance receipt and later application use liability then AR', () {
      expect(
          server('customer_receipt_post.php'), contains("'CUSTOMER_ADVANCES'"));
      final apply = server('customer_advance_apply.php');
      expect(apply, contains("billing_account_role(\$db,'CUSTOMER_ADVANCES')"));
      expect(apply, contains("billing_account_role(\$db,'TRADE_RECEIVABLES')"));
    });

    test('partial production allocation is locked and cumulative', () {
      final issue = server('invoice_issue.php');
      expect(issue, contains('FOR UPDATE'));
      expect(issue, contains("pa.status='COMMITTED'"));
      expect(issue, contains('PRODUCTION_M3_EXCEEDED'));
      expect(migration, contains('billed_m3 <= signed_m3_snapshot'));
    });

    test('issued correction uses credit note and invoice void is narrow', () {
      expect(server('credit_note_issue.php'),
          contains("'source_module'=>'CREDIT_NOTE'"));
      expect(server('invoice_void.php'),
          contains('ONLY_UNPAID_INVOICE_CAN_BE_VOIDED'));
      expect(server('invoice_void.php'), contains('accounts_reverse_journal'));
    });

    test('credit-note production quantity release is explicit and bounded', () {
      final credit = server('credit_note_issue.php');
      expect(credit, contains("'production_releases'"));
      expect(credit, contains("'invoice_production_allocation_id'"));
      expect(credit, contains('ALLOCATION_SPECIFIC_RELEASE_REQUIRED'));
      expect(credit, contains('INVALID_RELEASED_M3'));
      expect(credit, contains('QUANTITY_RELEASE_EXCEEDS_ALLOCATION_M3'));
      expect(credit, contains("'production_quantity'=>\$quantityAudit"));
      expect(migration,
          contains('CREATE TABLE qbook_credit_note_production_releases'));
      expect(migration, contains('invoice_production_allocation_id'));
      expect(migration, contains('uq_credit_release_line_allocation'));
      expect(migration, contains('released_m3 > 0'));
      expect(server('billable_production_reports.php'),
          contains('pa2.id=cr.invoice_production_allocation_id'));
      expect(server('invoice_issue.php'),
          contains('WHERE production_session_id=? ORDER BY id FOR UPDATE'));
    });

    test('credit notes expose no incomplete void lifecycle', () {
      expect(
          migration,
          contains(
              "qbook_credit_notes (\n  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT"));
      final creditNotesStart =
          migration.indexOf('CREATE TABLE qbook_credit_notes');
      final creditLinesStart =
          migration.indexOf('CREATE TABLE qbook_credit_note_lines');
      final creditNotes =
          migration.substring(creditNotesStart, creditLinesStart);
      expect(creditNotes, contains("ENUM('DRAFT','ISSUED')"));
      expect(creditNotes, isNot(contains("'VOID'")));
    });

    test('bank matching supports receipts without duplicate posting', () {
      final reconcile = server('bank_reconcile.php');
      expect(reconcile, contains("'CUSTOMER_RECEIPT'"));
      expect(reconcile, isNot(contains("'source_module'=>'CUSTOMER_RECEIPT'")));
      expect(server('customer_receipt_from_statement.php'),
          contains("'source_module'=>'CUSTOMER_RECEIPT'"));
    });

    test('migration is incremental and contains no financial data', () {
      expect(migration, isNot(contains('DROP TABLE')));
      expect(migration, isNot(contains('TRUNCATE')));
      expect(migration, isNot(contains('CASCADE')));
      expect(
          migration, isNot(contains('INSERT INTO qbook_financial_journals')));
      expect(migration, isNot(contains('opening balance')));
    });
  });
}
