/// The state of a single occurrence of a reminder.
enum ReminderEventStatus {
  /// Waiting to be done; this is what Today shows and what gets scheduled.
  pending,

  /// The owner marked it done.
  done,

  /// The owner dismissed it without doing it.
  skipped,
}

/// One occurrence of a [Reminder] — the thing that is due, gets a
/// notification, and ends up as history.
class ReminderEvent {
  const ReminderEvent({
    required this.id,
    required this.reminderId,
    required this.scheduledFor,
    required this.status,
    this.completedAt,
    this.snoozedUntil,
    this.notes,
  });

  final String id;
  final String reminderId;

  /// When this occurrence is due, as UTC.
  final DateTime scheduledFor;

  final ReminderEventStatus status;
  final DateTime? completedAt;

  /// Set while a pending occurrence is snoozed. The event stays pending; this
  /// only moves when it is next notified.
  final DateTime? snoozedUntil;

  final String? notes;

  bool get isPending => status == ReminderEventStatus.pending;

  /// When this occurrence should actually fire, honouring an active snooze.
  DateTime get notifyAt => snoozedUntil ?? scheduledFor;

  ReminderEvent copyWith({
    DateTime? scheduledFor,
    ReminderEventStatus? status,
    DateTime? completedAt,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
    String? notes,
  }) => ReminderEvent(
    id: id,
    reminderId: reminderId,
    scheduledFor: scheduledFor ?? this.scheduledFor,
    status: status ?? this.status,
    completedAt: completedAt ?? this.completedAt,
    snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
    notes: notes ?? this.notes,
  );
}
