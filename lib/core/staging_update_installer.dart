import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_environment.dart';
import 'update_service.dart';

class CehApkMetadata {
  const CehApkMetadata({
    required this.applicationId,
    required this.versionName,
    required this.versionCode,
    required this.environment,
    required this.signingCertificateSha256,
  });

  final String applicationId;
  final String versionName;
  final int versionCode;
  final String environment;
  final String signingCertificateSha256;
}

abstract interface class CehApkPlatformBridge {
  Future<CehApkMetadata> inspectApk(String path);

  Future<CehInstallerLaunchResult> launchInstaller(String path);
}

enum CehInstallerLaunchResult { launched, permissionRequested }

class CehAndroidApkPlatformBridge implements CehApkPlatformBridge {
  const CehAndroidApkPlatformBridge();

  static const _channel = MethodChannel(
    'com.concreteequipmenthire.ceh/staging_update',
  );

  @override
  Future<CehApkMetadata> inspectApk(String path) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'inspectApk',
      <String, dynamic>{'path': path},
    );
    if (value == null ||
        value['applicationId'] is! String ||
        value['versionName'] is! String ||
        value['versionCode'] is! int ||
        value['environment'] is! String ||
        value['signingCertificateSha256'] is! String) {
      throw const CehUpdateException(
        'Android could not validate the downloaded staging package.',
      );
    }
    return CehApkMetadata(
      applicationId: value['applicationId'] as String,
      versionName: value['versionName'] as String,
      versionCode: value['versionCode'] as int,
      environment: value['environment'] as String,
      signingCertificateSha256: value['signingCertificateSha256'] as String,
    );
  }

  @override
  Future<CehInstallerLaunchResult> launchInstaller(String path) async {
    final result = await _channel.invokeMethod<String>(
      'launchInstaller',
      <String, dynamic>{'path': path},
    );
    return switch (result) {
      'launched' => CehInstallerLaunchResult.launched,
      'permissionRequested' => CehInstallerLaunchResult.permissionRequested,
      _ => throw const CehUpdateException(
          'Android could not open the staging package installer.',
        ),
    };
  }
}

class CehVerifiedStagingUpdate {
  const CehVerifiedStagingUpdate({
    required this.apkPath,
    required this.metadata,
  });

  final String apkPath;
  final CehApkMetadata metadata;
}

typedef CehUpdateDirectoryProvider = Future<Directory> Function();

class _DigestCaptureSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class CehStagingUpdateInstaller {
  const CehStagingUpdateInstaller({
    this.environment = CehAppEnvironment.staging,
    this.client,
    this.platformBridge = const CehAndroidApkPlatformBridge(),
    this.directoryProvider,
  });

  final CehAppEnvironment environment;
  final http.Client? client;
  final CehApkPlatformBridge platformBridge;
  final CehUpdateDirectoryProvider? directoryProvider;

  Future<CehVerifiedStagingUpdate> downloadAndVerify(
    CehUpdateInfo update, {
    required void Function(double progress) onProgress,
  }) async {
    if (!environment.isStaging ||
        update.environment != 'STAGING' ||
        update.applicationId != CehAppEnvironment.stagingApplicationId) {
      throw const CehUpdateException(
        'Only approved CEH STAGING packages can use this installer.',
      );
    }

    final filename = update.filename;
    final expectedSize = update.byteSize;
    final expectedSha = update.sha256;
    final expectedCertificate = _normaliseFingerprint(
      environment.updateSigningCertificateSha256,
    );
    if (filename == null ||
        expectedSize == null ||
        expectedSha == null ||
        expectedCertificate == null ||
        update.signingCertificateSha256 != expectedCertificate) {
      throw const CehUpdateException(
        'The staging APK verification metadata is incomplete.',
      );
    }

    final uri = Uri.parse(update.downloadUrl);
    if (uri.scheme != 'https' ||
        uri.host != 'staging.concretehireng.com' ||
        (uri.hasPort && uri.port != 443) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path != '/updates/staging/$filename') {
      throw const CehUpdateException(
        'The staging APK URL is outside the approved update channel.',
      );
    }

    final baseDirectory = directoryProvider == null
        ? await getTemporaryDirectory()
        : await directoryProvider!();
    final updateDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}ceh-staging-updates',
    );
    await updateDirectory.create(recursive: true);
    final finalFile = File(
      '${updateDirectory.path}${Platform.pathSeparator}$filename',
    );
    final partialFile = File('${finalFile.path}.part');
    if (await partialFile.exists()) await partialFile.delete();

    final ownedClient = client == null;
    final activeClient = client ?? http.Client();
    IOSink? fileSink;
    ByteConversionSink? hashSink;
    var finalFileCreated = false;
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers['Accept'] = 'application/vnd.android.package-archive';
      final response =
          await activeClient.send(request).timeout(const Duration(seconds: 30));
      if (response.isRedirect || response.request?.url != uri) {
        throw const CehUpdateException(
          'The staging APK download attempted an unexpected redirect.',
        );
      }
      if (response.statusCode != 200) {
        throw CehUpdateException(
          'The staging APK download returned HTTP ${response.statusCode}.',
        );
      }
      if (response.contentLength != null &&
          response.contentLength != expectedSize) {
        throw const CehUpdateException(
          'The staging APK download size does not match the manifest.',
        );
      }

      final digestSink = _DigestCaptureSink();
      hashSink = sha256.startChunkedConversion(digestSink);
      fileSink = partialFile.openWrite(mode: FileMode.writeOnly);
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > expectedSize) {
          throw const CehUpdateException(
            'The staging APK exceeded the approved manifest size.',
          );
        }
        hashSink.add(chunk);
        fileSink.add(chunk);
        onProgress(received / expectedSize);
      }
      hashSink.close();
      hashSink = null;
      await fileSink.flush();
      await fileSink.close();
      fileSink = null;

      if (received != expectedSize) {
        throw const CehUpdateException(
          'The staging APK download was incomplete.',
        );
      }
      if (digestSink.value?.toString().toLowerCase() != expectedSha) {
        throw const CehUpdateException(
          'The staging APK SHA-256 verification failed.',
        );
      }

      if (await finalFile.exists()) await finalFile.delete();
      await partialFile.rename(finalFile.path);
      finalFileCreated = true;

      CehApkMetadata metadata;
      try {
        metadata = await platformBridge.inspectApk(finalFile.path);
      } catch (error) {
        if (error is CehUpdateException) rethrow;
        throw const CehUpdateException(
          'The downloaded CEH STAGING APK failed Android package validation.',
        );
      }
      final actualCertificate =
          _normaliseFingerprint(metadata.signingCertificateSha256);
      if (metadata.applicationId != CehAppEnvironment.stagingApplicationId ||
          metadata.environment != 'STAGING' ||
          metadata.versionCode != update.buildNumber ||
          metadata.versionName != update.versionName ||
          actualCertificate != expectedCertificate) {
        throw const CehUpdateException(
          'The downloaded APK is not the approved CEH STAGING update.',
        );
      }

      onProgress(1);
      return CehVerifiedStagingUpdate(
        apkPath: finalFile.path,
        metadata: metadata,
      );
    } catch (_) {
      if (fileSink != null) {
        await fileSink.close();
      }
      hashSink?.close();
      if (await partialFile.exists()) await partialFile.delete();
      if (finalFileCreated && await finalFile.exists()) {
        await finalFile.delete();
      }
      rethrow;
    } finally {
      if (ownedClient) activeClient.close();
    }
  }

  Future<CehInstallerLaunchResult> launchInstaller(
    CehVerifiedStagingUpdate update,
  ) {
    if (!environment.isStaging) {
      throw const CehUpdateException(
        'The staging installer is unavailable in production.',
      );
    }
    return platformBridge.launchInstaller(update.apkPath);
  }

  static String? _normaliseFingerprint(String? value) {
    if (value == null) return null;
    final result = value.replaceAll(':', '').trim().toUpperCase();
    return RegExp(r'^[0-9A-F]{64}$').hasMatch(result) ? result : null;
  }
}
