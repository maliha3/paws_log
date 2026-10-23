import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/domain/models/weight_entry.dart';

void main() {
  group('conversion', () {
    test('kilograms are grams over a thousand', () {
      expect(WeightUnit.kilograms.fromGrams(4200), 4.2);
      expect(WeightUnit.kilograms.toGrams(4.2), 4200);
    });

    test('pounds use the international avoirdupois pound', () {
      expect(WeightUnit.pounds.fromGrams(453), closeTo(0.9987, 0.0001));
      expect(WeightUnit.pounds.toGrams(1), 454, reason: '453.59 rounds to 454');
      expect(WeightUnit.pounds.toGrams(10), 4536);
    });

    test('a value survives a round trip through either unit', () {
      for (final grams in [100, 1000, 4200, 7500, 12345]) {
        for (final unit in WeightUnit.values) {
          expect(
            unit.toGrams(unit.fromGrams(grams)),
            grams,
            reason: '$grams g through ${unit.label}',
          );
        }
      }
    });

    test('switching the display unit does not change what is stored', () {
      // The point of storing grams: the number an owner reads changes, the
      // record does not.
      const grams = 4200;
      expect(WeightUnit.kilograms.format(grams), '4.20');
      expect(WeightUnit.pounds.format(grams), '9.3');
      expect(grams, 4200);
    });
  });

  group('formatting', () {
    test('kilograms get two decimals, pounds one', () {
      expect(WeightUnit.kilograms.format(4210), '4.21');
      expect(WeightUnit.pounds.format(4210), '9.3');
    });

    test('labels are the short forms owners expect', () {
      expect(WeightUnit.kilograms.label, 'kg');
      expect(WeightUnit.pounds.label, 'lb');
    });
  });

  group('storage', () {
    test('a name round-trips, which is how the setting is stored', () {
      for (final unit in WeightUnit.values) {
        expect(WeightUnit.fromName(unit.name), unit);
      }
    });

    test('an unknown name throws so the caller can fall back', () {
      expect(() => WeightUnit.fromName('stones'), throwsStateError);
    });
  });
}
