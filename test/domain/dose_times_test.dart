import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/domain/prescriptions/dose_times.dart';

void main() {
  test('the table CLAUDE.md specifies', () {
    expect(doseTimesFor(1), [9 * 60]);
    expect(doseTimesFor(2), [8 * 60, 20 * 60]);
    expect(doseTimesFor(3), [8 * 60, 14 * 60, 20 * 60]);
    expect(doseTimesFor(4), [8 * 60, 12 * 60, 16 * 60, 20 * 60]);
  });

  test('more than four still spreads across the waking day', () {
    expect(doseTimesFor(5), [8 * 60, 11 * 60, 14 * 60, 17 * 60, 20 * 60]);
    expect(doseTimesFor(6).first, 8 * 60);
    expect(doseTimesFor(6).last, 20 * 60);
    expect(doseTimesFor(6), hasLength(6));
  });

  test('times come back ascending and distinct', () {
    for (var perDay = 1; perDay <= maxTimesPerDay; perDay++) {
      final times = doseTimesFor(perDay);
      expect(times, hasLength(perDay), reason: '$perDay a day');
      expect(times.toSet(), hasLength(perDay), reason: '$perDay a day');
      expect(
        List.of(times)..sort(),
        times,
        reason: '$perDay a day comes back in order',
      );
    }
  });

  test('nonsense does not produce a nonsense schedule', () {
    expect(doseTimesFor(0), [9 * 60]);
    expect(doseTimesFor(-3), [9 * 60]);
    expect(doseTimesFor(40), hasLength(maxTimesPerDay));
  });
}
