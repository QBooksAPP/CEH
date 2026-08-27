import 'dart:io';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/models/accounts.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = CehSession(
    token: 'phase35',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1,
        fullName: 'Admin',
        email: 'admin@example.invalid',
        role: 'ADMIN',
        isActive: true));

class _HomeApi extends CehApiClient {
  const _HomeApi();
  @override
  Future<List<BillingInvoice>> invoices(CehSession session) async => const [];
}

void main() {
  final migration = File('Server/migration_v1_20_client_receipts_estimates.sql')
      .readAsStringSync();
  String server(String name) => File('Server/$name').readAsStringSync();

  group('Phase 3.5 Client terminology and receipt workflow', () {
    testWidgets('Billing home uses Client-facing terminology', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: AccountsBillingScreen(session: _admin, api: _HomeApi())));
      await tester.pumpAndSettle();
      expect(find.text('Client Payments'), findsOneWidget);
      expect(find.text('Apply Client Credit'), findsOneWidget);
      expect(find.text('Customer Payment'), findsNothing);
      expect(find.text('Apply Customer Credit'), findsNothing);
    });

    test('posting snapshots company and Received Into atomically', () {
      final post = server('customer_receipt_post.php');
      expect(
          post,
          contains(
              "SELECT * FROM qbook_invoice_settings WHERE id=1 FOR UPDATE"));
      expect(post, contains('company_legal_name_snapshot'));
      expect(post, contains('received_into_snapshot'));
      expect(post, contains("pdf_template_version='CLIENT_PAYMENT_V1'"));
      expect(post, contains('CLIENT_PAYMENT_SETTINGS_INCOMPLETE'));
    });

    test('historical payments never fall back to current settings', () {
      final pdf = server('client_payment_pdf.php');
      expect(pdf, contains('CLIENT_PAYMENT_SNAPSHOT_MISSING'));
      expect(pdf, isNot(contains('FROM qbook_invoice_settings')));
      expect(pdf, contains("status='POSTED'"));
    });

    test('receipt separates cash, WHT, settlement and Client Credit', () {
      final pdf = server('client_payment_pdf.php');
      expect(pdf, contains('Cash Received'));
      expect(pdf, contains('Cash Applied to Invoices'));
      expect(pdf, contains('WHT Deducted by Client'));
      expect(pdf, contains('Total Invoice Settlement'));
      expect(pdf, contains('Unallocated Client Credit / Advance'));
      expect(pdf, contains('was not cash received by CEH'));
    });

    test('receipt access is authenticated and private', () {
      final pdf = server('client_payment_pdf.php');
      expect(pdf, contains('billing_require_admin()'));
      expect(pdf, contains("Cache-Control: private, no-store"));
      expect(pdf, contains('application/pdf'));
    });

    test('receipt uses professional CEH layout without generator branding', () {
      final pdf = server('client_payment_pdf.php');
      expect(pdf, contains("assets/ceh_logo.png"));
      expect(pdf, contains('PAYMENT RECEIPT'));
      expect(pdf, contains('Invoice allocation'));
      expect(pdf, contains('Settlement summary'));
      expect(pdf, contains('INVOICE TOTAL'));
      expect(pdf, contains('PROJECT / SITE'));
      expect(pdf, contains('SetPrintFooter(true)'));
      expect(pdf, contains("getAliasNumPage()"));
      expect(pdf, isNot(contains('Powered by TCPDF')));
      expect(pdf, isNot(contains("MultiCell(134,5,\$value,0,'J'")));
    });

    test('receipt uses the authoritative monochrome CEH logo palette', () {
      final pdf = server('client_payment_pdf.php');
      expect(pdf, contains(r'$primary=[18,18,18]'));
      expect(pdf, contains(r'$secondary=[75,75,75]'));
      expect(pdf, contains(r'$pale=[245,245,245]'));
      expect(pdf, contains(r'$background=[250,250,250]'));
      expect(pdf, contains(r'$ink=[20,20,20]'));
      expect(pdf, contains(r'$border=[190,190,190]'));
      expect(pdf, isNot(contains('CehTheme.blue')));
      expect(pdf, isNot(contains(r'$primary=[36,89,133]')));
      expect(pdf, isNot(contains(r'$green=')));
    });
  });

  group('Phase 3.5 Estimate schema and lifecycle', () {
    test('permanent CEH-EST references and restrictive relationships exist',
        () {
      expect(migration, contains('CREATE TABLE qbook_estimate_references'));
      expect(server('billing_common.php'), contains("'ESTIMATE'=>'CEH-EST'"));
      expect(migration, contains('ON UPDATE RESTRICT ON DELETE RESTRICT'));
      expect(migration.toUpperCase(), isNot(contains('ON DELETE CASCADE')));
    });

    test('state machine is non-accounting and explicit', () {
      expect(migration,
          contains("ENUM('DRAFT','SENT','ACCEPTED','DECLINED','EXPIRED')"));
      expect(server('estimate_send.php'), contains("status='SENT'"));
      expect(server('estimate_accept.php'), contains("status='ACCEPTED'"));
      expect(server('estimate_decline.php'), contains("status='DECLINED'"));
      expect(server('estimate_expire.php'), contains("status='EXPIRED'"));
      for (final endpoint in [
        'estimate_save.php',
        'estimate_send.php',
        'estimate_accept.php',
        'estimate_decline.php',
        'estimate_expire.php',
        'estimate_convert.php'
      ]) {
        expect(server(endpoint), isNot(contains('accounts_post_journal')),
            reason: endpoint);
      }
    });

    test('GET only derives warning and never expires an Estimate', () {
      final list = server('estimates.php');
      expect(server('estimate_common.php'), contains('expired_warning'));
      expect(list, isNot(contains("SET status='EXPIRED'")));
      expect(server('estimate_expire.php'), contains('ESTIMATE_NOT_EXPIRABLE'));
    });

    test('sent Estimate snapshots are immutable and versioned', () {
      final send = server('estimate_send.php');
      expect(
          send,
          contains(
              "SELECT * FROM qbook_invoice_settings WHERE id=1 FOR UPDATE"));
      expect(send, contains("pdf_template_version='ESTIMATE_V1'"));
      expect(server('estimate_save.php'), contains('SENT_ESTIMATE_IMMUTABLE'));
      expect(server('estimate_pdf.php'),
          contains('estimate_require_sent_snapshots'));
      expect(server('estimate_pdf.php'),
          isNot(contains('qbook_invoice_settings')));
    });

    test('revisions retain the original and receive a new reference', () {
      final revision = server('estimate_revision.php');
      expect(revision, contains('revision_of_estimate_id'));
      expect(revision, contains('qbook_estimate_references'));
      expect(revision, contains('ESTIMATE_REVISION_CREATED'));
    });
  });

  group('Estimate to Invoice Draft conversion', () {
    test('only accepted Estimates convert and no Issue is performed', () {
      final convert = server('estimate_convert.php');
      expect(convert, contains("status']!=='ACCEPTED'"));
      expect(convert, contains("'DRAFT'"));
      expect(convert, isNot(contains('INVOICE_ISSUED')));
      expect(convert, isNot(contains('accounts_post_journal')));
    });

    test('conversion locks lines and prevents cumulative excess', () {
      final convert = server('estimate_convert.php');
      expect(
          convert,
          contains(
              'qbook_estimate_lines WHERE id=? AND estimate_id=? FOR UPDATE'));
      expect(convert, contains('ORDER BY id FOR UPDATE'));
      expect(convert, contains("status IN('DRAFT','COMMITTED')"));
      expect(convert, contains('ESTIMATE_CONVERSION_EXCEEDED'));
      expect(convert, contains('DUPLICATE_ESTIMATE_LINE_CONVERSION'));
    });

    test('invoice and estimate retain links in both directions', () {
      expect(migration, contains('origin_estimate_id'));
      expect(migration, contains('qbook_estimate_invoice_conversions'));
      expect(server('estimates.php'), contains('generated_invoices'));
      expect(server('invoices.php'), contains('origin_estimate_reference'));
    });

    test('Invoice Issue alone commits conversion and posts accounting', () {
      final issue = server('invoice_issue.php');
      expect(issue, contains("SET c.status='COMMITTED'"));
      expect(issue, contains('accounts_post_journal'));
      expect(server('estimate_convert.php'),
          isNot(contains('accounts_post_journal')));
    });

    test('abandoned Invoice Draft releases capacity without deleting audit',
        () {
      final release = server('estimate_conversion_release.php');
      expect(release, contains("status='RELEASED'"));
      expect(release, contains("status='VOID'"));
      expect(release, contains('FOR UPDATE'));
      expect(release, contains('ESTIMATE_INVOICE_DRAFT_CONVERSION_RELEASED'));
      expect(release, isNot(contains('DELETE FROM')));
      expect(
          server('estimates.php'), contains("status IN('DRAFT','COMMITTED')"));
    });
  });

  test('v1.20 is incremental with no historical mutation', () {
    final upper = migration.toUpperCase();
    expect(upper, isNot(contains('TRUNCATE')));
    expect(upper, isNot(contains('DELETE FROM')));
    expect(upper, isNot(contains('DROP TABLE')));
    expect(upper, isNot(contains('INSERT INTO QBOOK_FINANCIAL_JOURNALS')));
    expect(migration, contains('No financial posting, historical backfill'));
  });

  test('v1.20 enforces positive economic net values', () {
    expect(migration,
        contains('entered_amount>0 AND net_amount>0 AND vat_amount>=0'));
    expect(migration,
        contains('converted_entered_amount>0 AND converted_net_amount>0'));
    expect(
        migration,
        isNot(
            contains('entered_amount>0 AND net_amount>=0 AND vat_amount>=0')));
    expect(
        migration,
        isNot(contains(
            'converted_entered_amount>0 AND converted_net_amount>=0')));
  });
}
