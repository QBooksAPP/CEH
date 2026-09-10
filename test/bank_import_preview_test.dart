import 'package:flutter_test/flutter_test.dart';
import 'package:ceh/models/bank_import_preview.dart';
import 'package:ceh/models/banking_workspace.dart';

void main() {
  Map<String, dynamic> valid() => {
    'document': {'id': 1},
    'confirmation_sha256': List.filled(64, 'a').join(),
    'summary': {'can_import': true, 'invalid_rows': 0,
      'ambiguous_overlap_rows': 0, 'repeated_value_rows': 2},
  };
  test('bank selector uses only authoritative masked digits or currency', () {
    expect(bankAccountLabel({'name': 'Zenith Bank', 'currency': 'NGN'}),
        'Zenith Bank • NGN');
    expect(bankAccountLabel({'name': 'Zenith Bank', 'currency': 'NGN',
      'masked_account_reference': '•••• 1234'}), 'Zenith Bank • •••• 1234');
    expect(bankAccountLabel({'name': 'Zenith Bank', 'currency': 'NGN',
      'masked_account_reference': '•••• Bank'}), 'Zenith Bank • NGN');
  });
  test('repeated legitimate rows do not block confirmation', () {
    expect(BankImportPreview(valid()).canConfirm, isTrue);
  });
  test('already imported batch cannot be confirmed again from UI', () {
    expect(BankImportPreview({...valid(), 'batch_id': 2}).canConfirm, isFalse);
  });
  test('invalid and ambiguous rows block confirmation', () {
    for (final field in ['invalid_rows', 'ambiguous_overlap_rows']) {
      final p = valid();
      (p['summary'] as Map)[field] = 1;
      expect(BankImportPreview(p).canConfirm, isFalse);
    }
  });
  test('missing confirmation identity blocks confirmation', () {
    expect(BankImportPreview({...valid(), 'confirmation_sha256': ''}).canConfirm,
        isFalse);
  });
}
