import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/client_app_info.dart';
import '../../core/client_user_agent.dart';
import '../models/common.dart';
import 'http_timeout.dart';

class AppStoreVersionException implements Exception {
  const AppStoreVersionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppStoreVersionUnavailableException extends AppStoreVersionException {
  const AppStoreVersionUnavailableException() : super('App Store 暂无可查询的正式版本');
}

class AppStoreVersionInfo {
  const AppStoreVersionInfo({
    required this.version,
    required this.productUrl,
  });

  final String version;
  final String productUrl;

  bool isNewerThan(String currentVersion) {
    return compareVersions(version, currentVersion) > 0;
  }

  static int compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final leftPart = index < leftParts.length ? leftParts[index] : 0;
      final rightPart = index < rightParts.length ? rightParts[index] : 0;
      final comparison = leftPart.compareTo(rightPart);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  }

  static List<int> _versionParts(String value) {
    return value
        .trim()
        .split('.')
        .map((part) =>
            int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '') ?? 0)
        .toList(growable: false);
  }
}

class AppStoreVersionService {
  AppStoreVersionService({
    http.Client? httpClient,
    String? bundleId,
    String? currentVersion,
    this.countryCode = 'cn',
  })  : _httpClient = httpClient ?? IOClient(HttpClient()),
        _bundleId = bundleId ?? ClientAppInfo.packageName,
        _currentVersion = currentVersion ?? ClientAppInfo.version;

  final http.Client _httpClient;
  final String _bundleId;
  final String _currentVersion;
  final String countryCode;

  Future<AppStoreVersionInfo?> checkForUpdate() async {
    final published = await fetchPublishedVersion();
    return published.isNewerThan(_currentVersion) ? published : null;
  }

  Future<AppStoreVersionInfo> fetchPublishedVersion() async {
    final response = await HttpTimeout.request(
      _httpClient.get(
        Uri.https('itunes.apple.com', '/lookup', {
          'bundleId': _bundleId,
          'country': countryCode,
        }),
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.userAgentHeader: ClientUserAgent.mobileBrowser,
        },
      ),
      message: 'App Store 请求超时，请稍后再试',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppStoreVersionException(
        'App Store 版本查询失败 (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! JsonMap) {
      throw const AppStoreVersionException('App Store 返回了无效数据');
    }
    final results = decoded['results'];
    if (results is! List || results.isEmpty) {
      throw const AppStoreVersionUnavailableException();
    }
    final result = results.whereType<JsonMap>().firstWhere(
          (item) => stringValue(item['bundleId']) == _bundleId,
          orElse: () => const <String, dynamic>{},
        );
    final version = stringValue(result['version']).trim();
    final trackViewUrl = stringValue(result['trackViewUrl']).trim();
    final trackId = intValue(result['trackId']);
    final productUrl = trackViewUrl.isNotEmpty
        ? trackViewUrl
        : trackId > 0
            ? 'https://apps.apple.com/$countryCode/app/id$trackId'
            : '';
    if (version.isEmpty || productUrl.isEmpty) {
      throw const AppStoreVersionException('App Store 返回的版本信息不完整');
    }
    return AppStoreVersionInfo(version: version, productUrl: productUrl);
  }
}
