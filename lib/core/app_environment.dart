enum CehEnvironmentKind { production, staging }

class CehAppEnvironment {
  const CehAppEnvironment._({
    required this.kind,
    required this.apiBaseUrl,
    required this.applicationId,
    required this.appLabel,
    required this.secureStorageNamespace,
    required this.updateChecksEnabled,
  });

  static const productionApiUrl = 'https://qbook.concretehireng.com';
  static const stagingApiUrl = 'https://staging.concretehireng.com';
  static const productionApplicationId = 'com.concreteequipmenthire.ceh';
  static const stagingApplicationId = 'com.concreteequipmenthire.ceh.staging';

  static const production = CehAppEnvironment._(
    kind: CehEnvironmentKind.production,
    apiBaseUrl: productionApiUrl,
    applicationId: productionApplicationId,
    appLabel: 'CEH',
    secureStorageNamespace: 'ceh',
    updateChecksEnabled: true,
  );

  static const staging = CehAppEnvironment._(
    kind: CehEnvironmentKind.staging,
    apiBaseUrl: stagingApiUrl,
    applicationId: stagingApplicationId,
    appLabel: 'CEH STAGING',
    secureStorageNamespace: 'ceh_staging',
    updateChecksEnabled: false,
  );

  final CehEnvironmentKind kind;
  final String apiBaseUrl;
  final String applicationId;
  final String appLabel;
  final String secureStorageNamespace;
  final bool updateChecksEnabled;

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
      defaultValue: productionApiUrl,
    );
    const updateChecksEnabled = bool.fromEnvironment(
      'CEH_UPDATE_CHECKS',
      defaultValue: true,
    );

    return validate(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      updateChecksEnabled: updateChecksEnabled,
    );
  }
}

final CehAppEnvironment cehEnvironment = CehAppEnvironment.fromCompileTime();
