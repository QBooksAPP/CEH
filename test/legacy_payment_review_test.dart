import 'package:ceh/core/api_client.dart';
import 'package:ceh/models/accounts.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/legacy_payment_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const admin = CehSession(token: 'test', tokenType: 'Bearer', expiresAt: '',
  user: CehUser(id: 1, fullName: 'Admin', email: 'a@example.invalid', role: 'ADMIN', isActive: true));
class ReviewApi extends CehApiClient {
  ReviewApi(this.id, this.amount);
  final int id;
  final String amount;
  int writes = 0;
  Map<String, dynamic>? lastSave;
  @override
  Future<Map<String, dynamic>> ordinaryPaymentReview(CehSession session,
      {int? receiptId, int page = 1, Map<String, dynamic>? action}) async {
    if (action != null) { writes++; lastSave = action; }
    return {'receipt': {'id': id, 'reference': 'CEH-RCP-${id.toString().padLeft(6, '0')}',
      'client_id': 2, 'client_name_snapshot': 'Historical client', 'cash_amount': amount,
      'receipt_date': '2026-08-24', 'current_bank_name': 'Bank',
      'destination': 'TRADE_RECEIVABLES', 'status': 'DRAFT', 'draft_revision': writes,
      'review_required': writes == 0, 'reviewed_allocations': writes == 0 ? null : [],
      'client_credit_confirmed': action?['client_credit_confirmed'] == true}};
  }
  @override
  Future<List<BillingInvoice>> outstandingInvoices(CehSession session, int clientId) async => [];
  @override
  Future<Map<String, dynamic>> taxConfiguration(CehSession session) async => {'tax_codes': []};
}
void main() {
  final amounts = ['5000000.00','483750.00','483750.00','483750.00','485000.00'];
  for (var n = 0; n < amounts.length; n++) {
    testWidgets('historical draft ${n + 1} opens without writing or enabling posting', (tester) async {
      final api = ReviewApi(n + 1, amounts[n]);
      await tester.pumpWidget(MaterialApp(home: LegacyPaymentReviewScreen(api: api, session: admin, receiptId: n + 1)));
      await tester.pumpAndSettle();
      expect(find.text('Legacy payment draft — review required'), findsOneWidget);
      expect(api.writes, 0);
      await tester.ensureVisible(find.text('Post saved reviewed payment'));
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post saved reviewed payment'));
      expect(button.onPressed, isNull);
      expect(api.lastSave, isNull);
    });
  }
  testWidgets('explicit review and Client Credit choice are sent only on save', (tester) async {
    final api = ReviewApi(1, '5000000.00');
    await tester.pumpWidget(MaterialApp(home: LegacyPaymentReviewScreen(api: api, session: admin, receiptId: 1)));
    await tester.pumpAndSettle();
    final credit = find.text('Intentionally retain any unallocated cash as Client Credit');
    await tester.ensureVisible(credit); await tester.tap(credit); await tester.pump();
    final review = find.text('I have reviewed and reconstructed the intended allocation');
    await tester.ensureVisible(review); await tester.tap(review); await tester.pump();
    expect(api.writes, 0);
    await tester.ensureVisible(find.text('Save reviewed draft'));
    await tester.tap(find.text('Save reviewed draft')); await tester.pumpAndSettle();
    expect(api.writes, 1);
    expect(api.lastSave!['review_completed'], true);
    expect(api.lastSave!['client_credit_confirmed'], true);
    expect(api.lastSave!['allocations'], isEmpty);
  });
}
