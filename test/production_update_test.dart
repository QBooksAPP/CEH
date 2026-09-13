import 'dart:io';
import 'package:ceh/core/app_environment.dart';
import 'package:ceh/core/update_service.dart';
import 'package:ceh/core/staging_update_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'staging_update_service_test.dart' as fixtures;

const env = CehAppEnvironment.production;
const filename = 'CEH-PRODUCTION-0.4.1-98.apk';
const url = 'https://qbook.concretehireng.com/updates/production/$filename';
final bytes = <int>[1, 2, 3, 4];
Map<String, dynamic> manifest() => {
      ...fixtures.manifest(
          environment: 'PRODUCTION',
          applicationId: env.applicationId,
          versionCode: 98,
          apkUrl: url,
          sha: sha256.convert(bytes).toString(),
          certificate: CehAppEnvironment.productionSigningCertificateSha256),
      'channel': 'production',
      'versionName': '0.4.1',
      'apk': {
        'filename': filename,
        'url': url,
        'byteSize': 4,
        'sha256': sha256.convert(bytes).toString(),
        'signingCertificateSha256':
            CehAppEnvironment.productionSigningCertificateSha256
      },
    };
Future<CehUpdateInfo?> check(Map<String, dynamic> data, {int current = 97}) =>
    CehUpdateService(environment: env, client: fixtures.manifestClient(data))
        .checkForUpdate(currentBuild: current);
void main() {
  test('candidate updater has HTTPS channels only and no external URL fallback',
      () {
    expect(CehUpdateChannel.values,
        [CehUpdateChannel.productionVps, CehUpdateChannel.stagingVps]);
    final service = File('lib/core/update_service.dart').readAsStringSync();
    final dashboard =
        File('lib/screens/dashboard_screen.dart').readAsStringSync();
    expect(service, isNot(contains('api.github.com')));
    expect(dashboard, isNot(contains('launchUrl(')));
    expect(dashboard, isNot(contains('url_launcher')));
    expect(dashboard, contains('await _downloadStagingUpdate(update);'));
  });
  test('production 97 accepts HTTPS 98, ignores installed version', () async {
    expect((await check(manifest()))!.buildNumber, 98);
    expect(await check(manifest(), current: 98), isNull);
  });
  test('production rejects staging manifest and staging rejects production',
      () async {
    await expectLater(
        check(fixtures.manifest()), throwsA(isA<CehUpdateException>()));
    await expectLater(
        fixtures.check(manifest()), throwsA(isA<CehUpdateException>()));
  });
  for (final field in [
    'channel',
    'environment',
    'applicationId',
    'versionCode'
  ]) {
    test('production rejects wrong $field', () async {
      final data = manifest();
      data[field] = {
        'channel': 'staging',
        'environment': 'STAGING',
        'applicationId': CehAppEnvironment.stagingApplicationId,
        'versionCode': 97
      }[field];
      await expectLater(check(data), throwsA(isA<CehUpdateException>()));
    });
  }
  for (final field in [
    'url',
    'filename',
    'signingCertificateSha256',
    'sha256',
    'byteSize'
  ]) {
    test('production rejects wrong APK $field', () async {
      final data = manifest();
      (data['apk'] as Map)[field] = {
        'url': 'https://staging.concretehireng.com/updates/staging/$filename',
        'filename': '../CEH.apk',
        'signingCertificateSha256':
            CehAppEnvironment.stagingSigningCertificateSha256,
        'sha256': 'bad',
        'byteSize': 0
      }[field];
      await expectLater(check(data), throwsA(isA<CehUpdateException>()));
    });
  }
  test('manifest redirects are refused', () async {
    final client = MockClient((r) async {
      expect(r.followRedirects, isFalse);
      return http.Response('', 302, request: r, headers: {'location': url});
    });
    await expectLater(
        CehUpdateService(environment: env, client: client)
            .checkForUpdate(currentBuild: 97),
        throwsA(isA<CehUpdateException>()));
  });
  for (final failure in [
    'none',
    'sha',
    'size',
    'signer',
    'package',
    'environment',
    'version'
  ]) {
    test('production APK verification: $failure', () async {
      final dir =
          await Directory.systemTemp.createTemp('ceh-prod-update-test-');
      addTearDown(() => dir.delete(recursive: true));
      final update = (await check(manifest()))!;
      final bridge = fixtures.FakeBridge(CehApkMetadata(
          applicationId: failure == 'package'
              ? CehAppEnvironment.stagingApplicationId
              : env.applicationId,
          environment: failure == 'environment' ? 'STAGING' : 'PRODUCTION',
          versionName: '0.4.1',
          versionCode: failure == 'version' ? 99 : 98,
          signingCertificateSha256: failure == 'signer'
              ? CehAppEnvironment.stagingSigningCertificateSha256
              : CehAppEnvironment.productionSigningCertificateSha256));
      final installer = CehStagingUpdateInstaller(
          environment: env,
          platformBridge: bridge,
          directoryProvider: () async => dir,
          client: MockClient((r) async {
            expect(r.url.toString(), url);
            expect(r.followRedirects, isFalse);
            return http.Response.bytes(
                failure == 'sha'
                    ? [4, 3, 2, 1]
                    : failure == 'size'
                        ? [1]
                        : bytes,
                200,
                request: r);
          }));
      final task = installer.downloadAndVerify(update, onProgress: (_) {});
      if (failure == 'none') {
        final verified = await task;
        expect(verified.apkPath, contains('ceh-production-updates'));
        expect(await installer.launchInstaller(verified),
            CehInstallerLaunchResult.launched);
      } else {
        await expectLater(task, throwsA(isA<CehUpdateException>()));
        expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
      }
    });
  }
  test('production native provider and channel are separate from staging', () {
    final native = File(
            'android/app/src/main/kotlin/com/concreteequipmenthire/ceh/MainActivity.kt')
        .readAsStringSync();
    final trust = File(
            'android/app/src/production/kotlin/com/concreteequipmenthire/ceh/UpdateTrust.kt')
        .readAsStringSync();
    expect(
        trust, contains(CehAppEnvironment.productionSigningCertificateSha256));
    expect(trust,
        isNot(contains(CehAppEnvironment.stagingSigningCertificateSha256)));
    expect(native,
        isNot(contains(CehAppEnvironment.stagingSigningCertificateSha256)));
    expect(native,
        isNot(contains(CehAppEnvironment.productionSigningCertificateSha256)));
    expect(native, contains('packageName == UpdateTrust.PACKAGE'));
    expect(native, contains('requireUpdateRuntime()'));
    expect(native,
        contains('inspected.versionCode >= UpdateTrust.MINIMUM_VERSION'));
    expect(trust, contains('MINIMUM_VERSION = 98L'));
    final xml = File('android/app/src/production/AndroidManifest.xml')
        .readAsStringSync();
    expect(xml, contains('production_update_files'));
    expect(xml, contains('android:exported="false"'));
    expect(xml, isNot(contains('STAGING')));
  });
}
