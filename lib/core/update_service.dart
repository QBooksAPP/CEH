import 'dart:convert';

import 'package:http/http.dart' as http;

class CehUpdateInfo {
  const CehUpdateInfo({
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseName,
  });

  final int buildNumber;
  final String downloadUrl;
  final String releaseName;
}

class CehUpdateService {
  const CehUpdateService();

  static const _latestReleaseUrl =
      'https://api.github.com/repos/QBooksAPP/CEH/releases/latest';

  Future<CehUpdateInfo?> checkForUpdate({
    required int currentBuild,
  }) async {
    final response = await http.get(
      Uri.parse(_latestReleaseUrl),
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
  }
}
