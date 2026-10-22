import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/client_backend_constants.dart';
import '../models/academic_schedule.dart';
import '../repositories/academic_schedule_repository.dart';
import 'client_backend_api_client.dart';
import 'http_timeout.dart';

class ShareCodeInfo {
  const ShareCodeInfo({
    required this.id,
    required this.code,
    required this.expiresAt,
    required this.termLabel,
    required this.includeNote,
  });

  final String id;
  final String code;
  final DateTime expiresAt;
  final String termLabel;
  final bool includeNote;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'expiresAt': expiresAt.toIso8601String(),
        'termLabel': termLabel,
        'includeNote': includeNote,
      };

  @override
  bool operator ==(Object other) =>
      other is ShareCodeInfo &&
      other.id == id &&
      other.code == code &&
      other.expiresAt == expiresAt &&
      other.termLabel == termLabel &&
      other.includeNote == includeNote;

  @override
  int get hashCode => Object.hash(id, code, expiresAt, termLabel, includeNote);

  factory ShareCodeInfo.fromJson(Map<String, dynamic> json) => ShareCodeInfo(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        termLabel: json['termLabel']?.toString() ?? '',
        includeNote: json['includeNote'] == true,
      );
}

class SharedScheduleResult {
  const SharedScheduleResult({required this.snapshot, required this.digest});

  final Map<String, dynamic> snapshot;
  final String digest;
}

Map<String, dynamic> scheduleShareSnapshot(AcademicSchedule schedule,
    {required bool includeNote}) {
  final term = schedule.term;
  return {
    'term': {
      'yearCode': term.yearCode,
      'termCode': term.termCode,
      'academicYearName': term.academicYearName,
      'termName': term.termName,
    },
    'sessions': [
      for (final item in schedule.sessions)
        {
          'courseName': item.courseName,
          'teacherName': item.teacherName,
          'campus': item.campus,
          'location': item.location,
          'credit': item.credit,
          'weekday': item.weekday,
          'sections': item.sections.isEmpty
              ? [for (var n = item.startSection; n <= item.endSection; n++) n]
              : item.sections,
          'weeks': item.weeks,
          if (includeNote) 'note': item.note,
        }
    ],
    'untimedCourses': [
      for (final item in schedule.untimedCourses)
        {
          'courseName': item.courseName,
          'teacherName': item.teacherName,
          'campus': item.campus,
          'credit': item.credit,
          'weeks': item.weeks,
          'summary': item.summary,
        }
    ],
  };
}

class ScheduleShareApi {
  ScheduleShareApi({http.Client? client})
      : _client = client ?? IOClient(HttpClient());

  final http.Client _client;
  Uri _uri(String path) => Uri.parse('${ClientBackendConstants.baseUrl}$path');

  Map<String, String> _headers({String? token}) => {
        'accept': 'application/json',
        'content-type': 'application/json; charset=utf-8',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _decode(Future<http.Response> future) async {
    final response = await HttpTimeout.request(future, message: '请求超时，请稍后再试');
    if (response.statusCode == 204) return {};
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const ClientBackendApiException('服务器响应无效');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] == false) {
      throw ClientBackendApiException(
        decoded['error']?.toString() ?? '请求失败',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<ShareCodeInfo?> current(String token) async {
    final data = (await _decode(_client.get(
      _uri('/api/v1/student/shares/current'),
      headers: _headers(token: token),
    )))['data'];
    return data is Map<String, dynamic> ? ShareCodeInfo.fromJson(data) : null;
  }

  Future<ShareCodeInfo> generate(String token, AcademicSchedule schedule,
      {required bool includeNote, required String requestId}) async {
    final data = (await _decode(_client.post(
      _uri('/api/v1/student/shares'),
      headers: _headers(token: token),
      body: jsonEncode({
        'requestId': requestId,
        'includeNote': includeNote,
        'snapshot': scheduleShareSnapshot(schedule, includeNote: includeNote),
      }),
    )))['data'];
    if (data is! Map<String, dynamic>) {
      throw const ClientBackendApiException('分享码生成失败');
    }
    return ShareCodeInfo.fromJson(data);
  }

  Future<void> destroy(String token) async {
    await _decode(_client.delete(_uri('/api/v1/student/shares/current'),
        headers: _headers(token: token)));
  }

  Future<SharedScheduleResult> resolve(String code) async {
    final data = (await _decode(_client.post(
      _uri('/api/v1/shares/resolve'),
      headers: _headers(),
      body: jsonEncode({'code': code}),
    )))['data'];
    if (data is! Map<String, dynamic> ||
        data['snapshot'] is! Map<String, dynamic>) {
      throw const ClientBackendApiException('分享课表无效');
    }
    return SharedScheduleResult(
      snapshot: data['snapshot'] as Map<String, dynamic>,
      digest: data['digest']?.toString() ?? '',
    );
  }
}

class ImportedSchedule {
  const ImportedSchedule({
    required this.id,
    required this.name,
    required this.digest,
    required this.snapshot,
    required this.importedAt,
  });

  final String id;
  final String name;
  final String digest;
  final Map<String, dynamic> snapshot;
  final DateTime importedAt;

  Map<String, dynamic> get term => snapshot['term'] as Map<String, dynamic>;
  String get termKey => '${term['yearCode']}:${term['termCode']}';

  ImportedSchedule copyWith({String? name}) => ImportedSchedule(
        id: id,
        name: name ?? this.name,
        digest: digest,
        snapshot: snapshot,
        importedAt: importedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'digest': digest,
        'snapshot': snapshot,
        'importedAt': importedAt.toIso8601String(),
      };

  factory ImportedSchedule.fromJson(Map<String, dynamic> value) =>
      ImportedSchedule(
        id: value['id'] as String,
        name: value['name'] as String,
        digest: value['digest'] as String,
        snapshot: value['snapshot'] as Map<String, dynamic>,
        importedAt: DateTime.parse(value['importedAt'] as String),
      );

  AcademicSchedule toSchedule({int? localWeekCount}) {
    final timed = snapshot['sessions'] as List<dynamic>? ?? [];
    final untimed = snapshot['untimedCourses'] as List<dynamic>? ?? [];
    final maxCourseWeek = [
      for (final row in [...timed, ...untimed])
        ...((row as Map<String, dynamic>)['weeks'] as List<dynamic>? ?? [])
            .whereType<int>(),
    ].fold<int>(0, max);
    final fallback = term['termName'] == '夏' ? 4 : 16;
    final weekCount = max(maxCourseWeek, max(localWeekCount ?? 0, fallback));
    return AcademicSchedule.fromJson({
      'term': {...term, 'studentName': '', 'studentId': '', 'className': ''},
      'sessions': [
        for (var i = 0; i < timed.length; i++)
          {
            ...timed[i] as Map<String, dynamic>,
            'id': 'import:$id:$i',
            'courseCode': '',
            'startSection': (timed[i]['sections'] as List<dynamic>).first,
            'endSection': (timed[i]['sections'] as List<dynamic>).last,
            'weekText': '',
          }
      ],
      'untimedCourses': [
        for (var i = 0; i < untimed.length; i++)
          {
            ...untimed[i] as Map<String, dynamic>,
            'id': 'import:$id:untimed:$i',
            'weekText': ''
          }
      ],
      'fetchedAt': importedAt.toIso8601String(),
      'teachingWeekCount': weekCount,
    });
  }
}

class ImportedScheduleStore {
  ImportedScheduleStore({Directory? directory}) : _directory = directory;
  static final shared = ImportedScheduleStore();

  final Directory? _directory;
  List<ImportedSchedule> _cachedItems = const [];
  int _revision = 0;

  List<ImportedSchedule> get cachedItems => _cachedItems;

  Future<Directory> _dir() async {
    final base = _directory ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/imported-schedules');
    await dir.create(recursive: true);
    return dir;
  }

  Future<List<ImportedSchedule>> list() async {
    final revision = _revision;
    final dir = await _dir();
    final items = <ImportedSchedule>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await entity.readAsString());
        if (data is Map<String, dynamic>) {
          items.add(ImportedSchedule.fromJson(data));
        }
      } on Object {
        // A damaged import must not hide other saved schedules.
      }
    }
    items.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    if (revision == _revision) {
      _cachedItems = List.unmodifiable(items);
    }
    return items;
  }

  Future<ImportedSchedule> save(SharedScheduleResult result) async {
    final imported = await list();
    final existing = imported.where((item) => item.digest == result.digest);
    if (existing.isNotEmpty) return existing.first;
    final random = Random.secure();
    final id = List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final usedNames = imported.map((item) => item.name).toSet();
    var number = 1;
    while (usedNames.contains('课表 $number')) {
      number++;
    }
    final item = ImportedSchedule(
      id: id,
      name: '课表 $number',
      digest: result.digest,
      snapshot: result.snapshot,
      importedAt: DateTime.now(),
    );
    await _write(item);
    _revision++;
    _cachedItems = List.unmodifiable([item, ...imported]);
    return item;
  }

  Future<void> rename(ImportedSchedule item, String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > 40) {
      throw const FormatException('名称不能为空或过长');
    }
    await _write(item.copyWith(name: value));
    _revision++;
    _cachedItems = List.unmodifiable([
      for (final cached in _cachedItems)
        cached.id == item.id ? cached.copyWith(name: value) : cached,
    ]);
  }

  Future<void> delete(String id) async {
    final dir = await _dir();
    final file = File('${dir.path}/$id.json');
    if (await file.exists()) await file.delete();
    _revision++;
    _cachedItems =
        List.unmodifiable(_cachedItems.where((item) => item.id != id));
  }

  Future<void> _write(ImportedSchedule item) async {
    final dir = await _dir();
    final temp = File('${dir.path}/${item.id}.tmp');
    await temp.writeAsString(jsonEncode(item.toJson()), flush: true);
    await temp.rename('${dir.path}/${item.id}.json');
  }
}

class TermCalendarStore {
  TermCalendarStore({Future<SharedPreferences> Function()? preferencesLoader})
      : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;
  String _key(String termKey) => 'academic.schedule.term_calendar.$termKey';

  Future<DateTime?> load(String termKey) async {
    final raw = (await _preferencesLoader()).getString(_key(termKey));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> save(String termKey, DateTime date) async {
    final monday = AcademicScheduleRepository.startOfWeek(date);
    await (await _preferencesLoader()).setString(
      _key(termKey),
      '${monday.year.toString().padLeft(4, '0')}-'
      '${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}',
    );
  }
}
