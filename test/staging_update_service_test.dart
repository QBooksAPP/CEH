import 'dart:convert';
import 'dart:io';

import 'package:ceh/core/app_environment.dart';
import 'package:ceh/core/staging_update_installer.dart';
import 'package:ceh/core/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _commit = '23d8588bc1efc4aa1e59bc57cb0b04701b62298d';
const _filename = 'CEH-STAGING-0.3.0-staging.2-96002.apk';
const _apkUrl = 'https://staging.concretehireng.com/updates/staging/$_filename';

Map<String, dynamic> manifest({
  String environment = 'STAGING',
  String applicationId = CehAppEnvironment.stagingApplicationId,
  int versionCode = 96002,
  String apkUrl = _apkUrl,
  int byteSize = 4,
  String sha =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String certificate = CehAppEnvironment.stagingSigningCertificateSha256,
}) =>
    {
      'schemaVersion': 1,
      'channel': 'staging',
      'environment': environment,
      'applicationId': applicationId,
      'versionName': '0.3.0-staging.2',
      'versionCode': versionCode,
      'build': 96,
      'commit': _commit,
      'publishedAt': '2026-08-31T18:00:00Z',
      'releaseNotes': 'Secure staging updater acceptance test.',
      'apk': {
        'filename': _filename,
        'url': apkUrl,
        'byteSize': byteSize,
        'sha256': sha,
        'signingCertificateSha256': certificate,
      },
    };

MockClient manifestClient(Object body, {int status = 200}) =>
    MockClient((request) async => http.Response(
          body is String ? body : jsonEncode(body),
          status,
          request: request,
        ));

Future<CehUpdateInfo?> check(Object body, {int currentBuild = 96001}) =>
    CehUpdateService(
      environment: CehAppEnvironment.staging,
      client: manifestClient(body),
    ).checkForUpdate(currentBuild: currentBuild);

class FakeBridge implements CehApkPlatformBridge {
  FakeBridge(this.metadata);

  CehApkMetadata metadata;
  CehInstallerLaunchResult launchResult = CehInstallerLaunchResult.launched;
  Object? inspectionFailure;
  String? inspectedPath;

  @override
  Future<CehApkMetadata> inspectApk(String path) async {
    inspectedPath = path;
    if (inspectionFailure != null) throw inspectionFailure!;
    return metadata;
  }

  @override
  Future<CehInstallerLaunchResult> launchInstaller(String path) async =>
      launchResult;
}

void main() {
  group('staging manifest boundary', () {
    test('valid newer staging manifest is accepted', () async {
      final update = await check(manifest());
      expect(update, isNotNull);
      expect(update!.buildNumber, 96002);
      expect(update.applicationId, CehAppEnvironment.stagingApplicationId);
      expect(update.signingCertificateSha256,
          CehAppEnvironment.stagingSigningCertificateSha256);
    });

    test('same or older staging versions are ignored', () async {
      expect(await check(manifest(versionCode: 96001)), isNull);
      expect(await check(manifest(versionCode: 96000)), isNull);
    });

    test('wrong environment is rejected', () async {
      await expectLater(
        check(manifest(environment: 'PRODUCTION')),
        throwsA(isA<CehUpdateException>()),
      );
    });

    test('production package metadata is rejected', () async {
      await expectLater(
        check(
            manifest(applicationId: CehAppEnvironment.productionApplicationId)),
        throwsA(isA<CehUpdateException>()),
      );
    });

    test('malformed manifest is rejected', () async {
      await expectLater(check('{not-json'), throwsA(isA<CehUpdateException>()));
      final missing = manifest()..remove('apk');
      await expectLater(check(missing), throwsA(isA<CehUpdateException>()));
    });

    test('HTTP and non-channel APK URLs are rejected', () async {
      await expectLater(
        check(manifest(apkUrl: _apkUrl.replaceFirst('https:', 'http:'))),
        throwsA(isA<CehUpdateException>()),
      );
      await expectLater(
        check(manifest(apkUrl: 'https://qbook.concretehireng.com/$_filename')),
        throwsA(isA<CehUpdateException>()),
      );
    });

    test('wrong signing-certificate declaration is rejected', () async {
      await expectLater(
        check(manifest(certificate: List.filled(64, '0').join())),
        throwsA(isA<CehUpdateException>()),
      );
    });

    test('production updater still queries only GitHub releases', () async {
      Uri? requestUri;
      final client = MockClient((request) async {
        requestUri = request.url;
        return http.Response(
          jsonEncode({
            'tag_name': 'build-97',
            'name': 'CEH Build #97',
            'assets': [
              {
                'name': 'CEH.apk',
                'browser_download_url':
                    'https://github.com/QBooksAPP/CEH/releases/download/build-97/CEH.apk',
              }
            ],
          }),
          200,
          request: request,
        );
      });
      final update = await CehUpdateService(
        environment: CehAppEnvironment.production,
        client: client,
      ).checkForUpdate(currentBuild: 96);
      expect(
          requestUri.toString(), CehUpdateService.latestProductionReleaseUrl);
      expect(update!.buildNumber, 97);
      expect(update.downloadUrl, contains('github.com'));
    });
  });

  group('staging APK download verification', () {
    late Directory temporaryDirectory;
    late List<int> apkBytes;
    late String apkSha;
    late FakeBridge bridge;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('ceh-update-');
      apkBytes = <int>[1, 2, 3, 4];
      apkSha = sha256.convert(apkBytes).toString();
      bridge = FakeBridge(const CehApkMetadata(
        applicationId: CehAppEnvironment.stagingApplicationId,
        versionName: '0.3.0-staging.2',
        versionCode: 96002,
        environment: 'STAGING',
        signingCertificateSha256:
            CehAppEnvironment.stagingSigningCertificateSha256,
      ));
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    CehUpdateInfo update({
      int? size,
      String? sha,
    }) =>
        CehUpdateInfo(
          buildNumber: 96002,
          downloadUrl: _apkUrl,
          releaseName: 'CEH STAGING 0.3.0-staging.2',
          environment: 'STAGING',
          applicationId: CehAppEnvironment.stagingApplicationId,
          versionName: '0.3.0-staging.2',
          byteSize: size ?? apkBytes.length,
          sha256: sha ?? apkSha,
          signingCertificateSha256:
              CehAppEnvironment.stagingSigningCertificateSha256,
          filename: _filename,
        );

    CehStagingUpdateInstaller installer({List<int>? responseBytes}) =>
        CehStagingUpdateInstaller(
          client: MockClient((request) async => http.Response.bytes(
                responseBytes ?? apkBytes,
                200,
                request: request,
              )),
          platformBridge: bridge,
          directoryProvider: () async => temporaryDirectory,
        );

    test('valid APK passes size, hash, package, version and signer checks',
        () async {
      final progress = <double>[];
      final verified = await installer().downloadAndVerify(
        update(),
        onProgress: progress.add,
      );
      expect(await File(verified.apkPath).readAsBytes(), apkBytes);
      expect(bridge.inspectedPath, verified.apkPath);
      expect(bridge.inspectedPath, endsWith('.apk'));
      expect(bridge.inspectedPath, isNot(endsWith('.part')));
      expect(progress.last, 1);
    });

    test('native inspection never receives the partial download path',
        () async {
      final verified = await installer().downloadAndVerify(
        update(),
        onProgress: (_) {},
      );

      expect(bridge.inspectedPath, verified.apkPath);
      expect(bridge.inspectedPath, endsWith(_filename));
      expect(bridge.inspectedPath, isNot(endsWith('.part')));
    });

    test('native validation failure is classified and final APK is removed',
        () async {
      bridge.inspectionFailure = StateError('native package rejection');

      await expectLater(
        installer().downloadAndVerify(update(), onProgress: (_) {}),
        throwsA(
          isA<CehUpdateException>().having(
            (error) => error.message,
            'message',
            contains('failed Android package validation'),
          ),
        ),
      );

      expect(bridge.inspectedPath, endsWith('.apk'));
      expect(
        Directory(temporaryDirectory.path)
            .listSync(recursive: true)
            .whereType<File>(),
        isEmpty,
      );
    });

    test('wrong APK size is rejected and partial file is removed', () async {
      await expectLater(
        installer(responseBytes: [1, 2, 3]).downloadAndVerify(
          update(),
          onProgress: (_) {},
        ),
        throwsA(isA<CehUpdateException>()),
      );
      expect(
        Directory(temporaryDirectory.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
    });

    test('wrong APK SHA-256 is rejected', () async {
      await expectLater(
        installer().downloadAndVerify(
          update(sha: List.filled(64, '0').join()),
          onProgress: (_) {},
        ),
        throwsA(isA<CehUpdateException>()),
      );
    });

    test('wrong APK signing certificate is rejected', () async {
      bridge.metadata = const CehApkMetadata(
        applicationId: CehAppEnvironment.stagingApplicationId,
        versionName: '0.3.0-staging.2',
        versionCode: 96002,
        environment: 'STAGING',
        signingCertificateSha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      );
      await expectLater(
        installer().downloadAndVerify(update(), onProgress: (_) {}),
        throwsA(isA<CehUpdateException>()),
      );
    });

    test('production APK package is rejected', () async {
      bridge.metadata = const CehApkMetadata(
        applicationId: CehAppEnvironment.productionApplicationId,
        versionName: '0.3.0-staging.2',
        versionCode: 96002,
        environment: 'STAGING',
        signingCertificateSha256:
            CehAppEnvironment.stagingSigningCertificateSha256,
      );
      await expectLater(
        installer().downloadAndVerify(update(), onProgress: (_) {}),
        throwsA(isA<CehUpdateException>()),
      );
    });
  });
}
