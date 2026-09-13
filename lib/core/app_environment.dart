enum CehEnvironmentKind { production, staging }

enum CehUpdateChannel { productionVps, stagingVps }

class CehAppEnvironment {
  const CehAppEnvironment._({
    required this.kind,
    required this.apiBaseUrl,
    required this.applicationId,
    required this.appLabel,
    required this.secureStorageNamespace,
    required this.updateChecksEnabled,
    required this.updateChannel,
    required this.updateManifestUrl,
    required this.updateSigningCertificateSha256,
  });

  static const productionApiUrl = 'https://qbook.concretehireng.com';
  static const stagingApiUrl = 'https://staging.concretehireng.com';
  static const productionApplicationId = 'com.concreteequipmenthire.ceh';
  static const stagingApplicationId = 'com.concreteequipmenthire.ceh.staging';
  static const stagingUpdateManifestUrl =
      'https://staging.concretehireng.com/updates/staging/manifest.json';
  static const productionUpdateManifestUrl =
      'https://qbook.concretehireng.com/updates/production/manifest.json';
  static const productionSigningCertificateSha256 =
      'F859045ABA784241FD33F6DF182A484D716012350AC9DE64C88C9799CB79A30E';
  static const stagingSigningCertificateSha256 =
      'AFAFCE4A89211E7CBE6F0F665DB977F78CD96EF9343002F0A892B42F3FCDD057';

  static const production = CehAppEnvironment._(
    kind: CehEnvironmentKind.production,
    apiBaseUrl: productionApiUrl,
    applicationId: productionApplicationId,
    appLabel: 'CEH',
    secureStorageNamespace: 'ceh',
    updateChecksEnabled: true,
    updateChannel: CehUpdateChannel.productionVps,
    updateManifestUrl: productionUpdateManifestUrl,
    updateSigningCertificateSha256: productionSigningCertificateSha256,
  );

  static const staging = CehAppEnvironment._(
    kind: CehEnvironmentKind.staging,
    apiBaseUrl: stagingApiUrl,
    applicationId: stagingApplicationId,
    appLabel: 'CEH STAGING',
    secureStorageNamespace: 'ceh_staging',
    updateChecksEnabled: true,
    updateChannel: CehUpdateChannel.stagingVps,
    updateManifestUrl: stagingUpdateManifestUrl,
    updateSigningCertificateSha256: stagingSigningCertificateSha256,
  );

  final CehEnvironmentKind kind;
  final String apiBaseUrl;
  final String applicationId;
  final String appLabel;
  final String secureStorageNamespace;
  final bool updateChecksEnabled;
  final CehUpdateChannel updateChannel;
  final String? updateManifestUrl;
  final String? updateSigningCertificateSha256;

  // Constant selection is resolved before AOT tree shaking. Runtime validation
  // below must not reference the other flavour's trust configuration.
  static const compiledKind =
      String.fromEnvironment('CEH_ENVIRONMENT', defaultValue: 'production');
  static const current = compiledKind == 'staging' ? staging : production;
  static const compiledApiUrl =
      compiledKind == 'staging' ? stagingApiUrl : productionApiUrl;
  static const compiledApplicationId = compiledKind == 'staging'
      ? stagingApplicationId
      : productionApplicationId;
  static const compiledEnvironmentName =
      compiledKind == 'staging' ? 'STAGING' : 'PRODUCTION';
  String get updateEnvironment => kind.name.toUpperCase();
  String get updateBridgeChannel =>
      'com.concreteequipmenthire.ceh/${kind.name}_update';
  String get updateCache => 'ceh-${kind.name}-updates';
  RegExp get updateFilenamePattern =>
      RegExp('^CEH-$updateEnvironment-[0-9A-Za-z._-]+\\.apk\$');

  bool get isProduction => kind == CehEnvironmentKind.production;
  bool get isStaging => kind == CehEnvironmentKind.staging;

  String secureStorageKey(String key) => '${secureStorageNamespace}_$key';

  static CehAppEnvironment validate({
    required String environment,
    required String apiBaseUrl,
    required bool updateChecksEnabled,
  }) {
    switch (environment.trim().toLowerCase()) {
      case 'production':
        if (apiBaseUrl != productionApiUrl || !updateChecksEnabled) {
          throw StateError(
            'Production builds must use only the production CEH API and '
            'retain production update checks.',
          );
        }
        return production;
      case 'staging':
        if (apiBaseUrl != stagingApiUrl || updateChecksEnabled) {
          throw StateError(
            'Staging builds must use only the staging CEH API and must not '
            'use production release checks.',
          );
        }
        return staging;
      default:
        throw StateError('Unsupported CEH environment: $environment');
    }
  }

  static CehAppEnvironment fromCompileTime() {
    const environment = String.fromEnvironment(
      'CEH_ENVIRONMENT',
      defaultValue: 'production',
    );
    const apiBaseUrl = String.fromEnvironment(
      'CEH_API_BASE_URL',
      defaultValue: compiledApiUrl,
    );
    const updateChecksEnabled = bool.fromEnvironment(
      'CEH_UPDATE_CHECKS',
      defaultValue: true,
    );

    if ((environment != 'production' && environment != 'staging') ||
        apiBaseUrl != current.apiBaseUrl ||
        updateChecksEnabled != current.isProduction) {
      throw StateError('Invalid compiled CEH environment configuration.');
    }
    return current;
  }
}

final CehAppEnvironment cehEnvironment = CehAppEnvironment.fromCompileTime();
