import 'package:flutter_test/flutter_test.dart';
import 'package:ceh/models/accounts.dart';

void main() {
  const fields = [
    'company_legal_name_snapshot',
    'company_address_snapshot',
    'tax_identifier_snapshot',
    'payment_bank_details_snapshot',
  ];
  BillingInvoiceDetail invoice(String status, Map<String, dynamic> values) =>
      BillingInvoiceDetail.fromJson({
        'invoice': {'status': status, ...values},
      });
  test('historical issued identity gaps suppress the PDF action', () {
    expect(invoice('ISSUED', {}).originalPdfUnavailable, isTrue);
    for (final missing in fields) {
      final values = {for (final field in fields) field: 'preserved'};
      values[missing] = '   ';
      expect(invoice('ISSUED', values).originalPdfUnavailable, isTrue);
    }
  });
  test('complete historical identity remains available with legacy NGN', () {
    expect(invoice('ISSUED', {for (final field in fields) field: 'preserved'})
        .originalPdfUnavailable, isFalse);
  });
  test('drafts and void records are not classified as snapshot exceptions', () {
    expect(invoice('DRAFT', {}).originalPdfUnavailable, isFalse);
    expect(invoice('VOID', {}).originalPdfUnavailable, isFalse);
  });
  test('paid display status does not hide raw issued snapshot gaps', () {
    expect(invoice('ISSUED', {'display_status': 'PAID'})
        .originalPdfUnavailable, isTrue);
  });
}
