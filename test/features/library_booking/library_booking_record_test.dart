import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/features/library_booking/library_booking_record.dart';

void main() {
  final beforeBooking = DateTime(2026, 10, 18, 20);
  final duringBooking = DateTime(2026, 10, 19, 8, 30);
  final afterBooking = DateTime(2026, 10, 19, 10);
  final booking = <String, dynamic>{
    'status': 'NORMAL',
    'statusLabel': '正常',
    'beginTime': '2026-10-19 08:00:00',
    'endTime': '2026-10-19 09:00:00',
  };

  test('normal reservations use the school clock for their visible state', () {
    expect(LibraryBookingRecord.category(booking, beforeBooking), '待履约');
    expect(LibraryBookingRecord.category(booking, duringBooking), '待履约');
    expect(LibraryBookingRecord.category(booking, afterBooking), '已结束');
  });

  test('There early use needs check-in evidence, not OPEN or close alone', () {
    expect(
      LibraryBookingRecord.category(
        {
          ...booking,
          'status': 'OPEN',
          'abilities': ['close']
        },
        beforeBooking,
      ),
      '待履约',
    );
    expect(
      LibraryBookingRecord.category(
        {
          ...booking,
          'status': 'OPEN',
          'abilities': ['close'],
          'checkInAt': '2026-10-18 19:55:00',
        },
        beforeBooking,
      ),
      '进行中',
    );
  });

  test('Chaoxing actual seat use takes precedence over the scheduled start',
      () {
    for (final status in ['CX_1', 'CX_3']) {
      expect(
        LibraryBookingRecord.category(
          {...booking, 'status': status, 'cxCurrent': true},
          beforeBooking,
        ),
        '进行中',
      );
    }
    expect(
      LibraryBookingRecord.category(
        {...booking, 'status': 'CX_0', 'cxCurrent': true},
        beforeBooking,
      ),
      '待履约',
    );
    expect(
      LibraryBookingRecord.category(
        {
          ...booking,
          'status': 'CANCEL',
          'abilities': ['close']
        },
        beforeBooking,
      ),
      '已取消',
    );
  });

  test('cancelled and early-finished records take precedence over time', () {
    expect(
      LibraryBookingRecord.category(
          {...booking, 'status': 'CANCEL'}, beforeBooking),
      '已取消',
    );
    expect(
      LibraryBookingRecord.category({
        ...booking,
        'endTime': '2026-10-19 08:30:00',
        'origEndAt': '2026-10-19 09:00:00',
        'duration': 0,
      }, beforeBooking),
      '已结束',
    );
  });

  test('Chaoxing-specific states and cross-year times remain recognizable', () {
    expect(
      LibraryBookingRecord.category(
        {...booking, 'status': 'CX_0', 'cxCurrent': true},
        afterBooking,
      ),
      '进行中',
    );
    expect(
      LibraryBookingRecord.category(
        {...booking, 'status': 'CX_0', 'cxCurrent': false},
        afterBooking,
      ),
      '已结束',
    );
    for (final status in ['CX_1', 'CX_3']) {
      expect(
        LibraryBookingRecord.category(
          {...booking, 'status': status, 'cxCurrent': true},
          afterBooking,
        ),
        '进行中',
        reason: 'A signed-in or temporarily absent reservation remains active',
      );
    }
    expect(
      LibraryBookingRecord.category(
        {...booking, 'status': 'CX_7'},
        duringBooking,
      ),
      '已结束',
    );
    expect(
      LibraryBookingRecord.category(
        {...booking, 'status': 'CX_2', 'cxCurrent': false},
        duringBooking,
      ),
      '已结束',
    );
    expect(
      LibraryBookingRecord.category(
          {...booking, 'status': 'CX_9', 'statusLabel': '状态 9'}, beforeBooking),
      '状态 9',
    );
    expect(
      LibraryBookingRecord.displayTime('2027-01-02 08:00:00', beforeBooking),
      '2027-01-02 08:00',
    );
    expect(
      LibraryBookingRecord.displayTime('2026-10-19 08:00:00', beforeBooking),
      '10-19 08:00',
    );
  });
}
