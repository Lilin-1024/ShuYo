import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/classroom_url_resolver.dart';
import '../models/classroom.dart';
import '../models/common.dart';
import 'classroom_auth_service.dart';

class ClassroomApiException implements Exception {
  const ClassroomApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    final code = statusCode;
    if (code == null) {
      return message;
    }
    return '$message ($code)';
  }
}

class ClassroomApiClient {
  ClassroomApiClient({
    ClassroomAuthService? authService,
    http.Client? httpClient,
  })  : _authService = authService ?? ClassroomAuthService(),
        _httpClient = httpClient ?? IOClient(HttpClient());

  final ClassroomAuthService _authService;
  final http.Client _httpClient;

  Future<ClassroomSearchOptions> fetchSearchOptions() async {
    final form = await _postJson('/build/findSearchRoomSearchForm');
    final section = await _postJson('/course/findSection');
    return parseSearchOptions(form, section);
  }

  Future<ClassroomBuildingSchedule> fetchBuildingSchedule({
    required ClassroomBuilding building,
    required DateTime date,
  }) async {
    final json = await _postJson(
      '/build/findBuildRoomType',
      body: {
        'buildId': building.id.toString(),
        'courseDate': _dateParam(date),
      },
    );
    return parseBuildingSchedule(json, building: building);
  }

  static ClassroomSearchOptions parseSearchOptions(
    JsonMap formJson,
    JsonMap sectionJson,
  ) {
    final formData = _dataMap(formJson);
    final sectionData = _dataMap(sectionJson);
    final buildings = (formData['buildList'] as List? ?? const [])
        .whereType<JsonMap>()
        .map(ClassroomBuilding.fromJson)
        .where((building) => building.id > 0 && building.name.isNotEmpty)
        .toList(growable: false);
    final sections = (sectionData['section'] as List? ?? const [])
        .whereType<JsonMap>()
        .map(ClassroomSection.fromJson)
        .where((section) => section.index > 0)
        .toList(growable: false)
      ..sort((a, b) => a.index.compareTo(b.index));
    return ClassroomSearchOptions(
      buildings: buildings,
      sections: sections,
      currentSection: intValue(sectionData['curSection']),
    );
  }

  static ClassroomBuildingSchedule parseBuildingSchedule(
    JsonMap json, {
    required ClassroomBuilding building,
  }) {
    final data = _dataMap(json);
    final floors = (data['floorList'] as List? ?? const [])
        .whereType<JsonMap>()
        .map(ClassroomFloor.fromJson)
        .where((floor) => floor.rooms.isNotEmpty)
        .toList(growable: false);
    return ClassroomBuildingSchedule(
      building: building,
      floors: floors,
    );
  }

  Future<JsonMap> _postJson(
    String path, {
    Map<String, String>? body,
  }) async {
    final headers = await _headers();
    final response = await _httpClient.post(
      ClassroomUrlResolver.uri(path),
      headers: headers,
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClassroomApiException(
        '空教室查询请求失败',
        statusCode: response.statusCode,
      );
    }
    final decoded = _decodeJson(response.bodyBytes);
    final code = intValue(decoded['code']);
    if (code != 200) {
      throw ClassroomApiException(
        stringValue(decoded['msg'], '空教室查询失败'),
        statusCode: code,
      );
    }
    return decoded;
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'accept': 'application/json, text/javascript, */*; q=0.01',
      'referer': ClassroomUrlResolver.baseUrl,
      'user-agent':
          'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      'x-requested-with': 'XMLHttpRequest',
    };
    if (ClassroomUrlResolver.usesWebVpn) {
      final cookie = await _authService.cookieHeader();
      if (cookie == null || cookie.isEmpty) {
        throw const ClassroomApiException('请先登录WebVPN后再查询空教室');
      }
      headers['cookie'] = cookie;
    }
    return headers;
  }

  JsonMap _decodeJson(List<int> bodyBytes) {
    final body = utf8.decode(bodyBytes);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ClassroomApiException(
        ClassroomUrlResolver.usesWebVpn
            ? '空教室系统返回了无法识别的数据，请确认WebVPN已登录'
            : '空教室查询返回了无法识别的数据',
      );
    }
    if (decoded is! JsonMap) {
      throw const ClassroomApiException('空教室查询返回了无法识别的数据');
    }
    return decoded;
  }

  static JsonMap _dataMap(JsonMap json) {
    final data = json['data'];
    if (data is JsonMap) {
      return data;
    }
    return const <String, dynamic>{};
  }

  static String _dateParam(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }
}
