import 'package:ceh/core/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compiled environment selects exactly the requested trust configuration',
      () {
    const selected =
        String.fromEnvironment('CEH_ENVIRONMENT', defaultValue: 'production');
    final expected = selected == 'staging'
        ? CehAppEnvironment.staging
        : CehAppEnvironment.production;
    expect(identical(cehEnvironment, expected), isTrue);
    expect(CehAppEnvironment.compiledApplicationId, expected.applicationId);
    expect(CehAppEnvironment.compiledApiUrl, expected.apiBaseUrl);
    expect(cehEnvironment.updateSigningCertificateSha256,
        expected.updateSigningCertificateSha256);
    expect(cehEnvironment.updateBridgeChannel, endsWith('/${selected}_update'));
  });
}
