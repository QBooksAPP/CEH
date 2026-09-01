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
    this.environment = 'PRODUCTION',
    this.applicationId = CehAppEnvironment.productionApplicationId,
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

  static const latestProductionReleaseUrl =
      'https://api.github.com/repos/QBooksAPP/CEH/releases/latest';

  Future<CehUpdateInfo?> checkForUpdate({
    required int currentBuild,
  }) async {
    if (!updateChecksEnabled) return null;

    if (_environment.updateChannel == CehUpdateChannel.productionGithub) {
      return _checkProduction(currentBuild: currentBuild);
    }
    return _checkStaging(currentBuild: currentBuild);
  }

  Future<CehUpdateInfo?> _checkProduction({required int currentBuild}) async {
    final ownedClient = client == null;
    final activeClient = client ?? http.Client();
    try {
      final response = await activeClient.get(
        Uri.parse(latestProductionReleaseUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map) return null;

      final tag = (data['tag_name'] ?? '').toString();
      final match = RegExp(r'^build-(\d+)$').firstMatch(tag);
      if (match == null) return null;

      final latestBuild = int.tryParse(match.group(1) ?? '');
      if (latestBuild == null || latestBuild <= currentBuild) return null;

      final assets = data['assets'];
      if (assets is! List) return null;

      String? downloadUrl;
      for (final asset in assets) {
        if (asset is Map && asset['name']?.toString() == 'CEH.apk') {
          downloadUrl = asset['browser_download_url']?.toString();
          break;
        }
      }

      if (downloadUrl == null || downloadUrl.isEmpty) return null;

      return CehUpdateInfo(
        buildNumber: latestBuild,
        downloadUrl: downloadUrl,
        releaseName: (data['name'] ?? tag).toString(),
      );
    } finally {
      if (ownedClient) activeClient.close();
    }
  }

  Future<CehUpdateInfo?> _checkStaging({required int currentBuild}) async {
    final manifestValue = _environment.updateManifestUrl;
    final pinnedCertificate =
        _normaliseFingerprint(_environment.updateSigningCertificateSha256);
    if (manifestValue == null || pinnedCertificate == null) {
      throw const CehUpdateException(
        'The CEH STAGING update channel is not configured.',
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
          'The staging update manifest must not redirect.',
        );
      }
      if (response.statusCode != 200) {
        throw CehUpdateException(
          'The staging update service returned HTTP ${response.statusCode}.',
        );
      }
      if (response.request?.url != manifestUri) {
        throw const CehUpdateException(
          'The staging update manifest resolved to an unexpected URL.',
        );
      }

      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 64 * 1024) {
          throw const CehUpdateException(
            'The staging update manifest is unexpectedly large.',
          );
        }
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const CehUpdateException(
          'The staging update manifest is not valid JSON.',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw const CehUpdateException(
          'The staging update manifest has an invalid structure.',
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
          channel != 'staging' ||
          manifestEnvironment != 'STAGING' ||
          applicationId != CehAppEnvironment.stagingApplicationId ||
          versionName is! String ||
          versionName.isEmpty ||
          versionName.length > 80 ||
          versionCode is! int ||
          versionCode <= 0 ||
          build is! int ||
          build <= 0 ||
          commit is! String ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit) ||
          publishedAtValue is! String ||
          apk is! Map<String, dynamic>) {
        throw const CehUpdateException(
          'The staging update manifest failed validation.',
        );
      }
      if (releaseNotesValue != null &&
          (releaseNotesValue is! String || releaseNotesValue.length > 2000)) {
        throw const CehUpdateException(
          'The staging release notes failed validation.',
        );
      }

      final publishedAt = DateTime.tryParse(publishedAtValue)?.toUtc();
      if (publishedAt == null) {
        throw const CehUpdateException(
          'The staging publication timestamp is invalid.',
        );
      }

      final filename = apk['filename'];
      final urlValue = apk['url'];
      final byteSize = apk['byteSize'];
      final shaValue = apk['sha256'];
      final signingValue = apk['signingCertificateSha256'];
      if (filename is! String ||
          !RegExp(r'^CEH-STAGING-[0-9A-Za-z._-]+\.apk$').hasMatch(filename) ||
          urlValue is! String ||
          byteSize is! int ||
          byteSize <= 0 ||
          byteSize > 250 * 1024 * 1024 ||
          shaValue is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(shaValue) ||
          signingValue is! String) {
        throw const CehUpdateException(
          'The staging APK metadata failed validation.',
        );
      }

      final signingCertificate = _normaliseFingerprint(signingValue);
      if (signingCertificate == null ||
          signingCertificate != pinnedCertificate) {
        throw const CehUpdateException(
          'The staging manifest signing certificate is not approved.',
        );
      }

      final downloadUri = Uri.tryParse(urlValue);
      if (downloadUri == null) {
        throw const CehUpdateException('The staging APK URL is invalid.');
      }
      _requireApprovedStagingUri(downloadUri, expectedFilename: filename);

      if (versionCode <= currentBuild) return null;

      return CehUpdateInfo(
        buildNumber: versionCode,
        downloadUrl: downloadUri.toString(),
        releaseName: 'CEH STAGING $versionName',
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

  static void _requireApprovedStagingUri(
    Uri uri, {
    required String expectedFilename,
  }) {
    final expectedPath = '/updates/staging/$expectedFilename';
    if (uri.scheme != 'https' ||
        uri.host != 'staging.concretehireng.com' ||
        (uri.hasPort && uri.port != 443) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path != expectedPath) {
      throw const CehUpdateException(
        'The update URL is outside the approved CEH STAGING channel.',
      );
    }
  }

  static String? _normaliseFingerprint(String? value) {
    if (value == null) return null;
    final normalised = value.replaceAll(':', '').trim().toUpperCase();
    return RegExp(r'^[0-9A-F]{64}$').hasMatch(normalised) ? normalised : null;
  }
}
