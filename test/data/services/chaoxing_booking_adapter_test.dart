import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/chaoxing_booking_adapter.dart';
import 'package:shuyo/data/services/chaoxing_booking_client.dart';
import 'package:shuyo/data/services/there_booking_client.dart';

class _FakeChaoxingClient extends ChaoxingBookingClient {
  _FakeChaoxingClient();

  Map<String, dynamic>? _user;
  int bootstrapCalls = 0;
  int roomsCalls = 0;
  int homeCalls = 0;
  int availabilityCalls = 0;
  int submitCalls = 0;
  int cancelCalls = 0;
  String? cancelledId;
  int signbackCalls = 0;
  String? signedBackId;
  int signCalls = 0;
  String? signedId;
  String? signedRoomId;
  String? signedSeatNum;
  Map<String, dynamic>? homeFixture;

  @override
  Map<String, dynamic>? get user => _user;

  @override
  Future<Map<String, dynamic>> bootstrap() async {
    bootstrapCalls++;
    return _user = {
      'uid': 'fixture-user',
      'sno': 'student-a',
      'uname': '测试用户',
    };
  }

  @override
  Future<void> clearSession() async => _user = null;

  @override
  Future<List<Map<String, dynamic>>> rooms() async {
    roomsCalls++;
    return [
      {
        'id': 1001,
        'secondLevelName': '钱伟长馆',
        'thirdLevelName': '四楼内圈',
        'capacity': 3,
        'startSeatNum': 1,
      },
      {
        'id': 2002,
        'secondLevelName': '嘉定联合馆',
        'thirdLevelName': '一楼自修室',
        'capacity': 2,
        'startSeatNum': 1,
      },
      {
        'id': 3003,
        'secondLevelName': '延长文荟馆',
        'thirdLevelName': '二楼阅览室',
        'capacity': 2,
        'startSeatNum': 1,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> availability({
    required String roomId,
    required String start,
    required String end,
  }) async {
    availabilityCalls++;
    return {
      'room': {
        'id': int.parse(roomId),
        'capacity': roomId == '1001' ? 3 : 2,
        'startSeatNum': 1,
      },
      'used': ['002'],
      'available': roomId == '1001' ? ['001', '003'] : ['001'],
      'total': roomId == '1001' ? 3 : 2,
      'availableCount': roomId == '1001' ? 2 : 1,
    };
  }

  @override
  Future<Map<String, dynamic>> home() async {
    homeCalls++;
    if (homeFixture case final Map<String, dynamic> fixture) return fixture;
    return {
      'curReserves': [
        _reserve(101, '钱伟长馆', 0),
        _reserve(101, '嘉定联合馆', 0),
      ],
      'nearReserves': [
        _reserve(101, '钱伟长馆', 0),
        _reserve(102, '钱伟长馆', 7),
        _reserve(202, '嘉定联合馆', 9),
      ],
    };
  }

  Map<String, dynamic> _reserve(int id, String hall, int status) => {
        'id': id,
        'seatNum': '001',
        'roomId': 1001,
        'secondLevelName': hall,
        'thirdLevelName': '阅览室',
        'startTime': DateTime.utc(2026, 10, 18, 1).millisecondsSinceEpoch,
        'endTime': DateTime.utc(2026, 10, 18, 2).millisecondsSinceEpoch,
        'status': status,
      };

  @override
  Future<String> submit({
    required String roomId,
    required String start,
    required String end,
    required String seatNum,
  }) async {
    submitCalls++;
    return '303';
  }

  @override
  Future<void> cancel(String reserveId) async {
    cancelCalls++;
    cancelledId = reserveId;
  }

  @override
  Future<void> signback(String reserveId) async {
    signbackCalls++;
    signedBackId = reserveId;
  }

  @override
  Future<void> sign(String reserveId) async {
    signCalls++;
    signedId = reserveId;
  }

  @override
  Future<void> signWithSeatPage({
    required String reserveId,
    required String roomId,
    required String seatNum,
    String? deptId,
  }) async {
    signedRoomId = roomId;
    signedSeatNum = seatNum;
    await sign(reserveId);
  }
}

void main() {
  late _FakeChaoxingClient client;
  late ChaoxingBookingAdapter adapter;
  late DateTime schoolNow;

  setUp(() {
    schoolNow = DateTime.utc(2026, 10, 18, 9);
    SharedPreferences.setMockInitialValues({
      'academic.account.student_id': 'student-a',
    });
    client = _FakeChaoxingClient();
    adapter =
        ChaoxingBookingAdapter(client: client, schoolClock: () => schoolNow);
  });

  tearDown(() {
    adapter.dispose();
    client.dispose();
  });

  test("maps today's room and selected interval to existing area and seats",
      () async {
    await adapter.selectVenue(BookingVenue.qianweichang);
    final profile = await adapter.profile();
    expect(profile['loginName'], 'student-a');
    expect(profile['isAnonymous'], false);
    expect(adapter.hasBusinessSession, true);
    expect((await adapter.overview('2026-10-18'))['bookingDays'], [
      {'day': '2026-10-18'},
    ]);

    final areas = await adapter.areas('2026-10-18');
    expect(areas, hasLength(1));
    expect(areas.single['id'], '1001');
    expect(areas.single['name'], '四楼内圈');
    expect(areas.single['supportRoomTypes'], ['CX_QWC']);
    expect(areas.single.containsKey('freeResourceCount'), false);

    final rules = await adapter.area('1001', '2026-10-18', '2026-10-18');
    expect((rules['bookingTimes'] as Map)['minDuration'], 60);
    expect(client.availabilityCalls, 0);

    final seats =
        await adapter.area('1001', '2026-10-18 09:00', '2026-10-18 10:00');
    final entries = ThereBookingClient.objects(seats['rooms']);
    expect(entries.map((item) => item['id']), ['001', '002', '003']);
    expect(entries[0]['abilities'], ['booking']);
    expect(entries[1]['isBusy'], true);
    expect(entries[1]['abilities'], isEmpty);
    expect(client.availabilityCalls, 1);
  });

  test('tomorrow is rejected before room query or submit', () async {
    await adapter.selectVenue(BookingVenue.qianweichang);
    await expectLater(
      adapter.areas('2026-10-19'),
      throwsA(isA<ThereBookingException>()),
    );
    await expectLater(
      adapter.create(
        areaId: '1001',
        roomId: '001',
        day: '2026-10-19',
        start: '09:00',
        end: '10:00',
      ),
      throwsA(isA<ThereBookingException>()),
    );
    expect(client.roomsCalls, 0);
    expect(client.availabilityCalls, 0);
    expect(client.submitCalls, 0);
  });

  test('old day becomes invalid when Shanghai date changes', () async {
    schoolNow = DateTime.utc(2026, 10, 18, 23, 59);
    await adapter.selectVenue(BookingVenue.qianweichang);
    expect((await adapter.overview('2026-10-18'))['bookingDays'], [
      {'day': '2026-10-18'},
    ]);
    schoolNow = DateTime.utc(2026, 10, 19, 0, 1);
    await expectLater(
      adapter.create(
        areaId: '1001',
        roomId: '001',
        day: '2026-10-18',
        start: '09:00',
        end: '10:00',
      ),
      throwsA(isA<ThereBookingException>()),
    );
    expect(client.roomsCalls, 0);
    expect(client.availabilityCalls, 0);
    expect(client.submitCalls, 0);
  });

  test('booking stays closed until 07:00 Shanghai time', () async {
    schoolNow = DateTime.utc(2026, 10, 18, 6, 59);
    await adapter.selectVenue(BookingVenue.qianweichang);
    await expectLater(
      adapter.create(
        areaId: '1001',
        roomId: '001',
        day: '2026-10-18',
        start: '09:00',
        end: '10:00',
      ),
      throwsA(isA<ThereBookingException>()),
    );
    expect(client.roomsCalls, 0);
    expect(client.availabilityCalls, 0);
    expect(client.submitCalls, 0);
  });

  test('create rechecks the seat and returns a namespaced receipt', () async {
    await adapter.selectVenue(BookingVenue.qianweichang);
    final id = await adapter.create(
      areaId: '1001',
      roomId: '001',
      day: '2026-10-18',
      start: '09:00',
      end: '10:00',
    );
    expect(id, 'cx:CX_QWC:303');
    expect(client.availabilityCalls, 1);
    expect(client.submitCalls, 1);
    final pending = await adapter.detail(id);
    expect(pending['roomType'], 'CX_QWC');
    expect(pending['abilities'], isEmpty);
  });

  test('recent is scoped by campus and IDs remain provider namespaced',
      () async {
    await adapter.selectVenue(BookingVenue.qianweichang);
    final qwc = await adapter.recent();
    expect(qwc.map((item) => item['id']), ['cx:CX_QWC:101', 'cx:CX_QWC:102']);
    expect(qwc.every((item) => item['roomType'] == 'CX_QWC'), true);
    expect((await adapter.detail('cx:CX_QWC:101'))['abilities'], ['cancel']);
    expect((await adapter.detail('cx:CX_QWC:102'))['abilities'], isEmpty);
    await adapter.cancel('cx:CX_QWC:101');
    expect(client.cancelledId, '101');

    await adapter.selectVenue(BookingVenue.jiading);
    expect(client.bootstrapCalls, 1);
    final jd = await adapter.recent();
    expect(jd.map((item) => item['id']), ['cx:CX_JD:101', 'cx:CX_JD:202']);
    expect(jd.every((item) => item['roomType'] == 'CX_JD'), true);
    await expectLater(
      adapter.detail('cx:CX_QWC:101'),
      throwsA(isA<ThereBookingException>()),
    );
    await expectLater(
      adapter.cancel('cx:CX_QWC:101'),
      throwsA(isA<ThereBookingException>()),
    );
    expect(client.cancelCalls, 1);
    expect((await adapter.detail('cx:CX_JD:202'))['statusLabel'], '状态 9');
    expect((await adapter.detail('cx:CX_JD:202'))['abilities'], isEmpty);
    await expectLater(
      adapter.cancel('cx:CX_JD:202'),
      throwsA(isA<ThereBookingException>()),
    );
    expect(client.cancelCalls, 1);
  });

  test('maps observed Chaoxing reservation states', () async {
    client.homeFixture = {
      'curReserves': [
        client._reserve(1, '钱伟长馆', 0),
        client._reserve(2, '钱伟长馆', 1),
        client._reserve(3, '钱伟长馆', 3),
      ],
      'nearReserves': [client._reserve(4, '钱伟长馆', 7)],
    };
    await adapter.selectVenue(BookingVenue.qianweichang);
    final records = await adapter.recent();
    expect(
        records.map((item) => item['statusLabel']), ['待签到', '在座', '暂离', '已结束']);
    expect(records.map((item) => item['cxCurrent']), [true, true, true, false]);
  });

  test(
      'sign is offered only within the configured window for a pending current reservation',
      () async {
    client.homeFixture = {
      'seatConfig': {'preSignDuration': 20, 'signDuration': 15},
      'curReserves': [client._reserve(1, '钱伟长馆', 0)],
      'nearReserves': [client._reserve(2, '钱伟长馆', 0)],
    };
    await adapter.selectVenue(BookingVenue.qianweichang);
    schoolNow = DateTime.utc(2026, 10, 18, 8, 39);
    expect((await adapter.detail('cx:CX_QWC:1'))['abilities'], ['cancel']);
    await expectLater(
        adapter.sign('cx:CX_QWC:1'), throwsA(isA<ThereBookingException>()));
    expect(client.signCalls, 0);

    schoolNow = DateTime.utc(2026, 10, 18, 8, 40);
    expect(
        (await adapter.detail('cx:CX_QWC:1'))['abilities'], ['cancel', 'sign']);
    expect((await adapter.detail('cx:CX_QWC:2'))['abilities'], isEmpty);
    await adapter.sign('cx:CX_QWC:1');
    expect(client.signedId, '1');
    expect(client.signedRoomId, '1001');
    expect(client.signedSeatNum, '001');
    expect(client.signCalls, 1);

    schoolNow = DateTime.utc(2026, 10, 18, 9, 15);
    expect(
        (await adapter.detail('cx:CX_QWC:1'))['abilities'], ['cancel', 'sign']);
    schoolNow = DateTime.utc(2026, 10, 18, 9, 16);
    expect((await adapter.detail('cx:CX_QWC:1'))['abilities'], ['cancel']);
    await expectLater(
        adapter.sign('cx:CX_QWC:1'), throwsA(isA<ThereBookingException>()));
    expect(client.signCalls, 1);

    client.homeFixture!['seatConfig'] = {'preSignDuration': 20};
    schoolNow = DateTime.utc(2026, 10, 18, 8, 50);
    expect(
        (await adapter.detail('cx:CX_QWC:1'))['abilities'], ['cancel', 'sign']);
  });

  test('only in-use or temporarily absent seats can be released', () async {
    client.homeFixture = {
      'curReserves': [
        client._reserve(1, '钱伟长馆', 0),
        client._reserve(2, '钱伟长馆', 1),
        client._reserve(3, '钱伟长馆', 3),
      ],
      'nearReserves': [client._reserve(4, '钱伟长馆', 2)],
    };
    await adapter.selectVenue(BookingVenue.qianweichang);
    final bookings = await adapter.recent();
    expect(bookings.map((item) => item['abilities']), [
      ['cancel'],
      ['close'],
      ['close'],
      <String>[],
    ]);
    await expectLater(
        adapter.finish('cx:CX_QWC:1'), throwsA(isA<ThereBookingException>()));
    await expectLater(
        adapter.finish('cx:CX_QWC:4'), throwsA(isA<ThereBookingException>()));
    expect(client.signbackCalls, 0);

    await adapter.finish('cx:CX_QWC:2');
    expect(client.signedBackId, '2');
    expect(client.signbackCalls, 1);
    client.homeFixture = {
      'curReserves': [client._reserve(3, '钱伟长馆', 3)],
      'nearReserves': [client._reserve(2, '钱伟长馆', 2)],
    };
    final refreshed = await adapter.recent();
    expect(client.homeCalls, greaterThan(1));
    expect(
        refreshed
            .firstWhere((item) => item['id'] == 'cx:CX_QWC:2')['abilities'],
        isEmpty);
    await adapter.finish('cx:CX_QWC:3');
    expect(client.signedBackId, '3');
    expect(client.signbackCalls, 2);
  });

  test('one venue sweep shares read snapshots, but revisits and writes refresh',
      () async {
    await adapter.selectVenue(BookingVenue.qianweichang);
    expect(await adapter.areas('2026-10-18'), hasLength(1));
    await adapter.selectVenue(BookingVenue.jiading);
    expect(await adapter.areas('2026-10-18'), hasLength(1));
    await adapter.selectVenue(BookingVenue.wenhui);
    expect(await adapter.areas('2026-10-18'), hasLength(1));
    expect(client.roomsCalls, 1);

    await adapter.selectVenue(BookingVenue.qianweichang);
    await adapter.areas('2026-10-18');
    expect(client.roomsCalls, 2);

    await adapter.recent();
    await adapter.selectVenue(BookingVenue.jiading);
    await adapter.recent();
    await adapter.selectVenue(BookingVenue.wenhui);
    await adapter.recent();
    expect(client.homeCalls, 1);

    await adapter.selectVenue(BookingVenue.qianweichang);
    await adapter.recent();
    expect(client.homeCalls, 2);
    await adapter.create(
      areaId: '1001',
      roomId: '001',
      day: '2026-10-18',
      start: '09:00',
      end: '10:00',
    );
    expect(client.availabilityCalls, 1);
    await adapter.recent();
    expect(client.homeCalls, 3);
  });

  test('a cleared login never reuses the previous account snapshot', () async {
    await adapter.selectVenue(BookingVenue.qianweichang);
    await adapter.recent();
    expect(client.homeCalls, 1);

    await client.clearSession();
    await adapter.selectVenue(BookingVenue.jiading);
    await adapter.recent();
    expect(client.bootstrapCalls, 2);
    expect(client.homeCalls, 2);
  });
}
