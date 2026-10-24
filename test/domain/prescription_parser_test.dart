import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/domain/prescriptions/prescription_parser.dart';

/// The sig lines a prescription is really written in, parsed on their own.
ParsedMedicine only(String text) {
  final parsed = PrescriptionParser.parse(text);
  expect(parsed.medicines, hasLength(1), reason: text);
  return parsed.medicines.single;
}

void main() {
  group('times per day', () {
    test('reads the words a vet writes', () {
      expect(only('once daily for 5 days').timesPerDay.value, 1);
      expect(only('twice daily for 7 days').timesPerDay.value, 2);
      expect(only('three times a day for 5 days').timesPerDay.value, 3);
      expect(only('four times daily for 3 days').timesPerDay.value, 4);
    });

    test('reads the Latin abbreviations', () {
      expect(only('BID x 10d').timesPerDay.value, 2);
      expect(only('1 tab TDS for 5 days').timesPerDay.value, 3);
      expect(only('QID for 3 days').timesPerDay.value, 4);
      expect(only('SID for 7 days').timesPerDay.value, 1);
    });

    test('reads digits', () {
      expect(only('1 tablet 3 times a day').timesPerDay.value, 3);
      expect(only('2 ml 2x daily for 5 days').timesPerDay.value, 2);
    });

    test('converts hourly intervals that divide a day', () {
      expect(only('q8h x 5 days').timesPerDay.value, 3);
      expect(only('q12h for 7 days').timesPerDay.value, 2);
      expect(only('every 6 hours for 3 days').timesPerDay.value, 4);
    });

    test('leaves an interval it cannot say in times per day blank', () {
      // q36h is every day and a half. Rounding it to once or twice a day
      // would be the app inventing a schedule.
      expect(only('q36h for 10 days').timesPerDay.isBlank, isTrue);
    });

    test('reads morning-noon-night slots', () {
      expect(only('1-0-1 for 5 days').timesPerDay.value, 2);
      expect(only('1+1+1 for 5 days').timesPerDay.value, 3);
      expect(only('0-0-1 for 7 days').timesPerDay.value, 1);
      expect(only('1-1-1-1 for 3 days').timesPerDay.value, 4);
    });

    test('never trusts OD on its own', () {
      // Once daily on most prescriptions, the right eye on eye drops.
      final medicine = only('Timolol eye drops\n1 drop OD for 14 days');
      expect(medicine.timesPerDay.value, 1);
      expect(medicine.timesPerDay.needsCheck, isTrue);
    });

    test('marks a frequency the page states two ways', () {
      final medicine = only('Cefalexin 250 mg tablets\nGive twice daily (q8h) for 7 days');
      expect(medicine.timesPerDay.needsCheck, isTrue);
      expect(medicine.timesPerDay.value, anyOf(2, 3));
    });

    test('as needed is not a schedule', () {
      final medicine = only('Buprenorphine 0.3 mg/ml\n0.1 ml as needed for pain');
      expect(medicine.isAsNeeded, isTrue);
      expect(medicine.timesPerDay.isBlank, isTrue);
    });
  });

  group('duration', () {
    test('reads days', () {
      expect(only('twice daily for 7 days').durationDays.value, 7);
      expect(only('BID x 10d').durationDays.value, 10);
      expect(only('q8h x 5 days').durationDays.value, 5);
      expect(only('once daily for ten days').durationDays.value, 10);
    });

    test('reads weeks and months as days', () {
      expect(only('twice daily for 2 weeks').durationDays.value, 14);
      expect(only('once daily for 3 months').durationDays.value, 90);
    });

    test('is blank when the course is open-ended, and says so', () {
      final medicine = only('Thyroxine 0.1 mg tablets\nOne tablet twice daily, continue long term');
      expect(medicine.durationDays.isBlank, isTrue);
      expect(medicine.isOpenEnded, isTrue);
      expect(medicine.timesPerDay.value, 2);
    });

    test('is blank, not guessed, when the page does not say', () {
      final medicine = only('1 tablet 3 times a day');
      expect(medicine.durationDays.isBlank, isTrue);
      expect(medicine.isOpenEnded, isFalse);
    });

    test('ignores a nonsense length', () {
      expect(only('twice daily for 4000 days').durationDays.isBlank, isTrue);
    });
  });

  group('dose', () {
    test('prefers a strength over a count of tablets', () {
      final medicine = only('Amoxicillin 50 mg tablets\nGive one tablet twice daily for 7 days');
      expect(medicine.dose, const ParsedField.read('50 mg'));
    });

    test('falls back to a count when there is no strength', () {
      expect(only('1 tablet 3 times a day').dose, const ParsedField.read('1 tablet'));
      expect(only('Give two capsules once daily for 5 days').dose.value, '2 capsules');
      expect(only('half tablet twice daily for 7 days').dose.value, '0.5 tablets');
    });

    test('marks the concentration-versus-dose trap', () {
      // "0.5 mg/ml suspension, give 0.1 ml" states two amounts and the
      // parser cannot know which one is the dose.
      final medicine = only('Meloxicam 0.5 mg/ml suspension\nGive 0.1 ml once daily for 3 days');
      expect(medicine.dose.value, '0.5 mg/ml');
      expect(medicine.dose.needsCheck, isTrue);
    });

    test('is blank when no amount appears', () {
      expect(only('twice daily for 7 days').dose.isBlank, isTrue);
    });
  });

  group('name', () {
    test('takes the drug off a line that states its strength', () {
      expect(
        only('Amoxicillin 50 mg tablets\nGive one tablet twice daily for 7 days').name,
        const ParsedField.read('Amoxicillin'),
      );
      expect(
        only('Co-amoxiclav 250mg/125mg tabs\n1 tab BID for 7 days').name.value,
        'Co-amoxiclav',
      );
    });

    test('is unsure of a bare name with the instructions underneath', () {
      final medicine = only('Amoxicillin\nTwice daily for 7 days');
      expect(medicine.name.value, 'Amoxicillin');
      expect(medicine.name.needsCheck, isTrue);
    });

    test('is blank when the text is only a sig line', () {
      expect(only('q8h x 5 days').name.isBlank, isTrue);
    });

    test('is unsure when a digit landed in the name', () {
      // Either the strength bled in or OCR turned a letter into a number.
      final medicine = only('Vitamin B12 500 mcg\nOne tablet once daily for 30 days');
      expect(medicine.name.value, 'Vitamin B12');
      expect(medicine.name.needsCheck, isTrue);
    });
  });

  group('a whole page', () {
    const text = '''
Riverside Veterinary Clinic
Dr. A. Okafor  MRCVS
Patient: Mochi (cat, 4y)
Date: 04/05/2026

Rx
1. Amoxicillin 50 mg tablets
Give one tablet twice daily for 7 days
2. Meloxicam 0.5 mg/ml oral suspension
Give 0.1 ml once daily for 3 days

Recheck in 2 weeks
''';

    test('splits into one medicine per numbered line', () {
      final parsed = PrescriptionParser.parse(text);
      expect(parsed.medicines.map((m) => m.name.value), ['Amoxicillin', 'Meloxicam']);
    });

    test('reads each course', () {
      final parsed = PrescriptionParser.parse(text);
      final amoxicillin = parsed.medicines[0];
      expect(amoxicillin.dose, const ParsedField.read('50 mg'));
      expect(amoxicillin.timesPerDay, const ParsedField.read(2));
      expect(amoxicillin.durationDays, const ParsedField.read(7));

      final meloxicam = parsed.medicines[1];
      expect(meloxicam.timesPerDay, const ParsedField.read(1));
      expect(meloxicam.durationDays, const ParsedField.read(3));
    });

    test('does not read the footer as the last course', () {
      // "Recheck in 2 weeks" sits under medicine 2 and must not become its
      // duration.
      final parsed = PrescriptionParser.parse(text);
      expect(parsed.medicines.last.durationDays.value, 3);
    });

    test('keeps the lines each medicine came from', () {
      final parsed = PrescriptionParser.parse(text);
      expect(parsed.medicines.first.sourceText, contains('twice daily for 7 days'));
      expect(parsed.medicines.first.sourceText, isNot(contains('Meloxicam')));
    });
  });

  group('nothing to read', () {
    test('empty text yields no medicines', () {
      expect(PrescriptionParser.parse('').isEmpty, isTrue);
      expect(PrescriptionParser.parse('   \n\n  ').isEmpty, isTrue);
    });

    test('a letterhead alone yields no medicines', () {
      expect(
        PrescriptionParser.parse(
          'Riverside Veterinary Clinic\n'
          '12 Mill Lane\n'
          'Tel: 01234 567890\n'
          'Date: 04/05/2026',
        ).isEmpty,
        isTrue,
      );
    });

    test('OCR noise yields no medicines', () {
      expect(PrescriptionParser.parse('|| ~~ ::').isEmpty, isTrue);
    });
  });
}
