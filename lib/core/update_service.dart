import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_environment.dart';

class CehUpdateException implements Exception {
  const CehUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CehUpdateInfo {
  const CehUpdateInfo({
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseName,
    this.environment = CehAppEnvironment.compiledEnvironmentName,
    this.applicationId = CehAppEnvironment.compiledApplicationId,
    this.versionName = '',
    this.byteSize,
    this.sha256,
    this.signingCertificateSha256,
    this.commit,
    this.publishedAt,
    this.releaseNotes,
    this.filename,
  });

  final int buildNumber;
  final String downloadUrl;
  final String releaseName;
  final String environment;
  final String applicationId;
  final String versionName;
  final int? byteSize;
  final String? sha256;
  final String? signingCertificateSha256;
  final String? commit;
  final DateTime? publishedAt;
  final String? releaseNotes;
  final String? filename;

  bool get isStaging => environment == 'STAGING';
}

class CehUpdateService {
  const CehUpdateService({this.environment, this.client});

  final CehAppEnvironment? environment;
  final http.Client? client;

  CehAppEnvironment get _environment => environment ?? cehEnvironment;

  bool get updateChecksEnabled => _environment.updateChecksEnabled;

  Future<CehUpdateInfo?> checkForUpdate({
    required int currentBuild,
  }) async {
    if (!updateChecksEnabled) return null;

    return _checkStaging(currentBuild: currentBuild);
  }

  Future<CehUpdateInfo?> _checkStaging({required int currentBuild}) async {
    final manifestValue = _environment.updateManifestUrl;
    final pinnedCertificate =
        _normaliseFingerprint(_environment.updateSigningCertificateSha256);
    if (manifestValue == null || pinnedCertificate == null) {
      throw const CehUpdateException(
        'The CEH update channel is not configured.',
      );
    }

    final manifestUri = Uri.parse(manifestValue);
    _requireApprovedStagingUri(manifestUri, expectedFilename: 'manifest.json');

    final ownedClient = client == null;
    final activeClient = client ?? http.Client();
    try {
      final request = http.Request('GET', manifestUri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers['Accept'] = 'application/json';
      final response =
          await activeClient.send(request).timeout(const Duration(seconds: 15));
      if (response.isRedirect) {
        throw const CehUpdateException(
          'The update manifest must not redirect.',
        );
      }
      if (response.statusCode != 200) {
        throw CehUpdateException(
          'The update service returned HTTP ${response.statusCode}.',
        );
      }
      if (response.request?.url != manifestUri) {
        throw const CehUpdateException(
          'The update manifest resolved to an unexpected URL.',
        );
      }

      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 64 * 1024) {
          throw const CehUpdateException(
            'The update manifest is unexpectedly large.',
          );
        }
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const CehUpdateException(
          'The update manifest is not valid JSON.',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw const CehUpdateException(
          'The update manifest has an invalid structure.',
        );
      }

      final schemaVersion = decoded['schemaVersion'];
      final channel = decoded['channel'];
      final manifestEnvironment = decoded['environment'];
      final applicationId = decoded['applicationId'];
      final versionName = decoded['versionName'];
      final versionCode = decoded['versionCode'];
      final build = decoded['build'];
      final commit = decoded['commit'];
      final publishedAtValue = decoded['publishedAt'];
      final releaseNotesValue = decoded['releaseNotes'];
      final apk = decoded['apk'];

      if (schemaVersion != 1 ||
          channel != _environment.kind.name ||
          manifestEnvironment != _environment.updateEnvironment ||
          applicationId != _environment.applicationId ||
          versionName is! String ||
          versionName.isEmpty ||
          versionName.length > 80 ||
          versionCode is! int ||
          versionCode < (_environment.isStaging ? 1 : 98) ||
          build is! int ||
          build <= 0 ||
          commit is! String ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit) ||
          publishedAtValue is! String ||
          apk is! Map<String, dynamic>) {
        throw const CehUpdateException(
          'The update manifest failed validation.',
        );
      }
      if (releaseNotesValue != null &&
          (releaseNotesValue is! String || releaseNotesValue.length > 2000)) {
        throw const CehUpdateException(
          'The release notes failed validation.',
        );
      }

      final publishedAt = DateTime.tryParse(publishedAtValue)?.toUtc();
      if (publishedAt == null) {
        throw const CehUpdateException(
          'The publication timestamp is invalid.',
        );
      }

      final filename = apk['filename'];
      final urlValue = apk['url'];
      final byteSize = apk['byteSize'];
      final shaValue = apk['sha256'];
      final signingValue = apk['signingCertificateSha256'];
      if (filename is! String ||
          !_environment.updateFilenamePattern.hasMatch(filename) ||
          urlValue is! String ||
          byteSize is! int ||
          byteSize <= 0 ||
          byteSize > 250 * 1024 * 1024 ||
          shaValue is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(shaValue) ||
          signingValue is! String) {
        throw const CehUpdateException(
          'The APK metadata failed validation.',
        );
      }

      final signingCertificate = _normaliseFingerprint(signingValue);
      if (signingCertificate == null ||
          signingCertificate != pinnedCertificate) {
        throw const CehUpdateException(
          'The manifest signing certificate is not approved.',
        );
      }

      final downloadUri = Uri.tryParse(urlValue);
      if (downloadUri == null) {
        throw const CehUpdateException('The APK URL is invalid.');
      }
      _requireApprovedStagingUri(downloadUri, expectedFilename: filename);

      if (versionCode <= currentBuild) return null;

      return CehUpdateInfo(
        buildNumber: versionCode,
        downloadUrl: downloadUri.toString(),
        releaseName:
            'CEH ${_environment.isStaging ? "STAGING " : ""}$versionName',
        environment: manifestEnvironment,
        applicationId: applicationId,
        versionName: versionName,
        byteSize: byteSize,
        sha256: shaValue,
        signingCertificateSha256: signingCertificate,
        commit: commit,
        publishedAt: publishedAt,
        releaseNotes: releaseNotesValue as String?,
        filename: filename,
      );
    } finally {
      if (ownedClient) activeClient.close();
    }
  }

  void _requireApprovedStagingUri(
    Uri uri, {
    required String expectedFilename,
  }) {
    final expectedPath = '/updates/${_environment.kind.name}/$expectedFilename';
    if (uri.scheme != 'https' ||
        uri.host != Uri.parse(_environment.updateManifestUrl!).host ||
        (uri.hasPort && uri.port != 443) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path != expectedPath) {
      throw const CehUpdateException(
        'The update URL is outside the approved CEH channel.',
      );
    }
  }

  static String? _normaliseFingerprint(String? value) {
    if (value == null) return null;
    final normalised = value.replaceAll(':', '').trim().toUpperCase();
    return RegExp(r'^[0-9A-F]{64}$').hasMatch(normalised) ? normalised : null;
  }
}
