import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/domain/shedding_season.dart';

void main() {
  group('the shedding windows', () {
    test('cover March to May and September to November', () {
      for (final month in [3, 4, 5, 9, 10, 11]) {
        expect(
          inSheddingSeason(DateTime.utc(2026, month, 15)),
          isTrue,
          reason: 'month $month',
        );
      }
    });

    test('exclude the rest of the year', () {
      for (final month in [1, 2, 6, 7, 8, 12]) {
        expect(
          inSheddingSeason(DateTime.utc(2026, month, 15)),
          isFalse,
          reason: 'month $month',
        );
      }
    });

    test('include the first and last day of a window', () {
      expect(inSheddingSeason(DateTime.utc(2026, 3, 1)), isTrue);
      expect(inSheddingSeason(DateTime.utc(2026, 5, 31)), isTrue);
      expect(inSheddingSeason(DateTime.utc(2026, 2, 28)), isFalse);
      expect(inSheddingSeason(DateTime.utc(2026, 6, 1)), isFalse);
    });

    test('are the same months in both hemispheres', () {
      // Shedding turns at the equinoxes, which fall in March and September
      // everywhere. The hemisphere names the windows; it does not move them.
      for (var month = 1; month <= 12; month++) {
        final date = DateTime.utc(2026, month, 15);
        expect(
          sheddingWindowLabel(date, Hemisphere.northern) != null,
          sheddingWindowLabel(date, Hemisphere.southern) != null,
          reason: 'month $month',
        );
      }
    });
  });

  group('what a window is called', () {
    test('north of the equator, March is spring and September autumn', () {
      expect(
        sheddingWindowLabel(DateTime.utc(2026, 4, 1), Hemisphere.northern),
        'Spring shedding',
      );
      expect(
        sheddingWindowLabel(DateTime.utc(2026, 10, 1), Hemisphere.northern),
        'Autumn shedding',
      );
    });

    test('south of it, the two names swap', () {
      expect(
        sheddingWindowLabel(DateTime.utc(2026, 4, 1), Hemisphere.southern),
        'Autumn shedding',
      );
      expect(
        sheddingWindowLabel(DateTime.utc(2026, 10, 1), Hemisphere.southern),
        'Spring shedding',
      );
    });

    test('is nothing outside a window', () {
      for (final hemisphere in Hemisphere.values) {
        expect(
          sheddingWindowLabel(DateTime.utc(2026, 7, 1), hemisphere),
          isNull,
        );
      }
    });
  });
}
