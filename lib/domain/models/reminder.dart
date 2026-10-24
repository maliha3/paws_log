import '../repeat_rule.dart';

/// What kind of care a reminder is for. Drives the icon and the starter
/// suggestions; `other` covers anything the owner adds themselves.
enum ReminderCategory {
  vaccine,
  deworming,
  fleaTick,
  nailTrim,
  brushing,
  other;

  String get label => switch (this) {
    ReminderCategory.vaccine => 'Vaccine',
    ReminderCategory.deworming => 'Deworming',
    ReminderCategory.fleaTick => 'Flea & tick',
    ReminderCategory.nailTrim => 'Nail trim',
    ReminderCategory.brushing => 'Brushing',
    ReminderCategory.other => 'Other',
  };

  /// Grooming is care the owner does themselves, which is why it can repeat
  /// every few days where medical care repeats every few months.
  bool get isGrooming =>
      this == ReminderCategory.nailTrim || this == ReminderCategory.brushing;
}

/// A recurring piece of care for one pet.
class Reminder {
  const Reminder({
    required this.id,
    required this.petId,
    required this.title,
    required this.category,
    required this.repeat,
    required this.anchorDate,
    required this.timeOfDayMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.nextDueAt,
    this.isActive = true,
    this.notes,
  });

  final String id;
  final String petId;
  final String title;
  final ReminderCategory category;
  final RepeatRule repeat;

  /// The date the cycle counts from. Date-only, stored as UTC midnight.
  final DateTime anchorDate;

  /// Minutes past local midnight that this reminder fires at.
  final int timeOfDayMinutes;

  /// When the next pending occurrence is due, as UTC. Null once a one-off
  /// reminder has been completed and nothing follows it.
  final DateTime? nextDueAt;

  final bool isActive;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Reminder copyWith({
    String? title,
    ReminderCategory? category,
    RepeatRule? repeat,
    DateTime? anchorDate,
    int? timeOfDayMinutes,
    DateTime? nextDueAt,
    bool clearNextDueAt = false,
    bool? isActive,
    String? notes,
    DateTime? updatedAt,
  }) => Reminder(
    id: id,
    petId: petId,
    title: title ?? this.title,
    category: category ?? this.category,
    repeat: repeat ?? this.repeat,
    anchorDate: anchorDate ?? this.anchorDate,
    timeOfDayMinutes: timeOfDayMinutes ?? this.timeOfDayMinutes,
    nextDueAt: clearNextDueAt ? null : (nextDueAt ?? this.nextDueAt),
    isActive: isActive ?? this.isActive,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
