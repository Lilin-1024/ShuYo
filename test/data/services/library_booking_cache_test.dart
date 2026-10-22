import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/library_booking_cache.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keeps confirmed recent records by account and venue', () async {
    final cache = LibraryBookingCache();
    await cache.replaceVenue('student-a', 'LIB_SEAT', [
      {
        'id': 'LIB_1',
        'roomType': 'LIB_SEAT',
        'roomName': '2E015',
        'beginTime': '2026-10-04 08:30:00',
        'endTime': '2026-10-04 09:30:00',
        'ownerMobile': 'not-for-cache',
      },
    ]);
    await cache.replaceVenue('student-a', 'STATION', [
      {
        'id': 'STATION_1',
        'roomType': 'STATION',
        'roomName': 'B-034',
        'beginTime': '2026-10-05 08:30:00',
        'endTime': '2026-10-05 09:30:00',
      },
    ]);
    final records = await cache.load('student-a');
    expect(records.map((item) => item['id']), ['STATION_1', 'LIB_1']);
    expect(records.first.containsKey('ownerMobile'), isFalse);
    expect(await cache.load('student-b'), isEmpty);

    await cache.removeBooking('student-a', 'LIB_1');
    expect((await cache.load('student-a')).map((item) => item['id']),
        ['STATION_1']);
  });

  test('a damaged local snapshot reads as empty', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('library_booking.recent.v1.student-a', '{broken');
    expect(await LibraryBookingCache().load('student-a'), isEmpty);
  });

  test('merges new records while retaining older booking history', () async {
    final cache = LibraryBookingCache();
    await cache.mergeVenue('student-a', 'LIB_SEAT', [
      {
        'id': 'LIB_OLD',
        'roomType': 'LIB_SEAT',
        'roomName': 'A-001',
        'beginTime': '2025-01-01 08:30:00',
        'endTime': '2025-01-01 09:30:00',
        'status': 'CANCEL',
      },
      {
        'id': 'LIB_CURRENT',
        'roomType': 'LIB_SEAT',
        'roomName': 'A-002',
        'beginTime': '2026-10-05 08:30:00',
        'endTime': '2026-10-05 09:30:00',
        'status': 'OPEN',
      },
    ]);
    await cache.mergeVenue('student-a', 'LIB_SEAT', [
      {
        'id': 'LIB_CURRENT',
        'roomType': 'LIB_SEAT',
        'roomName': 'A-002',
        'beginTime': '2026-10-05 08:30:00',
        'endTime': '2026-10-05 08:45:00',
        'status': 'CANCEL',
        'ownerMobile': 'not-for-cache',
      },
      {
        'id': 'LIB_NEW',
        'roomType': 'LIB_SEAT',
        'roomName': 'A-003',
        'beginTime': '2026-10-06 08:30:00',
        'endTime': '2026-10-06 09:30:00',
        'status': 'OPEN',
      },
    ]);

    final records = await cache.load('student-a');
    expect(records.map((item) => item['id']),
        ['LIB_NEW', 'LIB_CURRENT', 'LIB_OLD']);
    expect(records[1]['id'], 'LIB_CURRENT');
    expect(records[1]['status'], 'CANCEL');
    expect(records[1].containsKey('ownerMobile'), isFalse);
    expect(await cache.load('student-b'), isEmpty);
  });

  test('normalizes numeric appointment ids before persisting history',
      () async {
    final cache = LibraryBookingCache();
    await cache.mergeVenue('student-a', 'LIB_SEAT', [
      {
        'id': 12345,
        'roomType': 'LIB_SEAT',
        'roomName': 'A-004',
        'beginTime': '2026-10-07 08:30:00',
        'endTime': '2026-10-07 09:30:00',
      },
    ]);

    final records = await cache.load('student-a');
    expect(records.single['id'], '12345');
  });

  test('retains records beyond the former local limit', () async {
    final cache = LibraryBookingCache();
    await cache.mergeVenue('student-a', 'LIB_SEAT', [
      for (var index = 0; index < 501; index++)
        {
          'id': 'LIB_$index',
          'roomType': 'LIB_SEAT',
          'beginTime': '2026-10-07 08:30:00',
        },
    ]);

    expect((await cache.load('student-a')).length, 501);
  });
}
