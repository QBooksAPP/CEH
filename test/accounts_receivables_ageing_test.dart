import 'dart:io';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _admin = CehSession(
    token: 'ageing',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1,
        fullName: 'Admin',
        email: 'admin@example.invalid',
        role: 'ADMIN',
        isActive: true));

class _AgeingApi extends CehApiClient {
  const _AgeingApi();
  @override
  Future<Map<String, dynamic>> receivablesAgeing(CehSession session) async => {
        'as_of': '2026-08-26',
        'buckets': {
          'CURRENT': '450040.00',
          '1_30': '700.00',
          '31_60': '600.00',
          '61_90': '900.00',
          'OVER_90': '91.00'
        },
        'invoices': [
          {
            'reference': 'CEH-INV-000001',
            'client_name_snapshot': 'ABC Construction',
            'invoice_date': '2026-08-20',
            'due_date': '2026-08-30',
            'original_amount': '500000.00',
            'payments_credits_applied': '49960.00',
            'outstanding': '450040.00',
            'days_outstanding': 6,
            'days_overdue': 0,
            'bucket': 'CURRENT'
          }
        ]
      };
}

void main() {
  final backend = File('Server/receivables_ageing.php').readAsStringSync();

  test('authoritative ageing excludes settled and uses remaining balance', () {
    expect(backend, contains('if(\$outstanding<=0)continue'));
    expect(backend, contains("i.status='ISSUED'"));
    expect(backend, contains('\$original-\$settled'));
    expect(backend, contains("r.status='POSTED'"));
  });

  test('ageing boundaries are mutually exclusive', () {
    expect(
        backend,
        contains(
            "\$daysOverdue<=30?'1_30':(\$daysOverdue<=60?'31_60':(\$daysOverdue<=90?'61_90':'OVER_90'))"));
    const expected = {
      0: 'CURRENT',
      1: '1_30',
      30: '1_30',
      31: '31_60',
      60: '31_60',
      61: '61_90',
      90: '61_90',
      91: 'OVER_90'
    };
    String bucket(int days) => days <= 0
        ? 'CURRENT'
        : days <= 30
            ? '1_30'
            : days <= 60
                ? '31_60'
                : days <= 90
                    ? '61_90'
                    : 'OVER_90';
    for (final entry in expected.entries) {
      expect(bucket(entry.key), entry.value);
    }
  });

  testWidgets('ageing card opens a reconciling drill-down', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ReceivablesAgeingScreen(session: _admin, api: _AgeingApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ageing-bucket-CURRENT')));
    await tester.pumpAndSettle();
    expect(find.text('CURRENT Receivables'), findsOneWidget);
    expect(find.textContaining('ABC Construction'), findsOneWidget);
    expect(find.text('₦450,040.00'), findsNWidgets(3));
    expect(find.text('RECEIVABLES_AGEING_RECONCILIATION_ERROR'), findsNothing);
  });

  test('Estimates missing endpoint reports backend update requirement', () {
    expect(
        () => decodeApiObjectResponse(http.Response('<html>404</html>', 404)),
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'BACKEND_UPDATE_REQUIRED')));
  });

  test('Client Payments missing endpoint reports backend update requirement',
      () {
    expect(
        () => decodeApiObjectResponse(http.Response('Not Found', 404)),
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'BACKEND_UPDATE_REQUIRED')));
  });
}
