import 'package:ceh/core/api_client.dart';
import 'package:ceh/models/calibration_source.dart';
import 'package:ceh/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

CehSession session(String role) => CehSession(
      token: 'token',
      tokenType: 'Bearer',
      expiresAt: '',
      user: CehUser(
        id: 1,
        fullName: role,
        email: '$role@example.test',
        role: role,
        isActive: true,
      ),
    );

void main() {
  test('Admin may supply an approved calibration ID to the API client', () {
    expect(validateCalibrationOverride(session('ADMIN'), 14), 14);
  });

  test('Operator cannot inject a calibration override through API client', () {
    expect(
      () => validateCalibrationOverride(session('OPERATOR'), 14),
      throwsA(isA<ApiException>()),
    );
    expect(validateCalibrationOverride(session('OPERATOR'), null), isNull);
  });

  test('approved calibration source exposes traceable option details', () {
    final source = CalibrationSource.fromJson({
      'id': 14,
      'mixer_id': 3,
      'calibration_date': '2026-08-18',
      'revision_no': 2,
      'calibration_notes': 'Koton Karfi',
      'reviewed_at': '2026-08-19 10:00:00',
    });
    expect(source.optionLabel, contains('#14'));
    expect(source.optionLabel, contains('Rev 2'));
    expect(source.optionLabel, contains('Koton Karfi'));
    expect(source.mixerId, 3);
  });
}
