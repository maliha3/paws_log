/// When a medicine's doses fall.
///
/// Medicines are dosed several times a day over a course that usually ends,
/// which is why they do not reuse [Reminder]'s recurrence: a rule of "every 3
/// months" has no way to express "08:00 and 20:00, for ten days".
class DoseSchedule {
  const DoseSchedule({
    required this.timesOfDayMinutes,
    required this.startDate,
    this.intervalDays = 1,
    this.endDate,
  }) : assert(intervalDays >= 1, 'intervalDays must be at least 1');

  /// Minutes past local midnight, one per dose, ascending.
  final List<int> timesOfDayMinutes;

  /// Date-only, held at UTC midnight. The first dosing day.
  final DateTime startDate;

  /// 1 for daily, 2 for every other day, and so on.
  final int intervalDays;

  /// Date-only, held at UTC midnight. Inclusive. Null for an open-ended
  /// course, which is dosed until the owner stops it.
  final DateTime? endDate;

  int get dosesPerDay => timesOfDayMinutes.length;

  bool get isOpenEnded => endDate == null;

  DoseSchedule copyWith({
    List<int>? timesOfDayMinutes,
    DateTime? startDate,
    int? intervalDays,
    DateTime? endDate,
    bool clearEndDate = false,
  }) => DoseSchedule(
    timesOfDayMinutes: timesOfDayMinutes ?? this.timesOfDayMinutes,
    startDate: startDate ?? this.startDate,
    intervalDays: intervalDays ?? this.intervalDays,
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
  );

  @override
  bool operator ==(Object other) =>
      other is DoseSchedule &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.intervalDays == intervalDays &&
      _sameTimes(other.timesOfDayMinutes, timesOfDayMinutes);

  @override
  int get hashCode => Object.hash(
    startDate,
    endDate,
    intervalDays,
    Object.hashAll(timesOfDayMinutes),
  );

  static bool _sameTimes(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

/// A course of medication for one pet.
class Medicine {
  const Medicine({
    required this.id,
    required this.petId,
    required this.name,
    required this.schedule,
    required this.createdAt,
    required this.updatedAt,
    this.dosage,
    this.notes,
    this.isActive = true,
  });

  final String id;
  final String petId;
  final String name;

  /// Free text, e.g. "1 tablet" or "2.5 mg". Deliberately not a number with
  /// a unit: owners copy what the label says, and the app has no business
  /// reinterpreting a prescription.
  final String? dosage;

  final DoseSchedule schedule;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Medicine copyWith({
    String? name,
    String? dosage,
    DoseSchedule? schedule,
    String? notes,
    bool? isActive,
    DateTime? updatedAt,
  }) => Medicine(
    id: id,
    petId: petId,
    name: name ?? this.name,
    dosage: dosage ?? this.dosage,
    schedule: schedule ?? this.schedule,
    notes: notes ?? this.notes,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
