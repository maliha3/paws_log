/// What became of a single dose.
enum DoseStatus {
  /// Still to be taken; this is what Today shows and what gets scheduled.
  pending,

  /// The owner logged it.
  taken,

  /// Its day passed without being logged. Set by a sweep, not by the owner.
  missed,

  /// The owner deliberately passed on it.
  skipped;

  String get label => switch (this) {
    DoseStatus.pending => 'Due',
    DoseStatus.taken => 'Taken',
    DoseStatus.missed => 'Missed',
    DoseStatus.skipped => 'Skipped',
  };
}

/// One dose of a [Medicine] — the thing that is due, gets a notification, and
/// ends up as the adherence record.
class DoseLog {
  const DoseLog({
    required this.id,
    required this.medicineId,
    required this.scheduledFor,
    required this.status,
    this.takenAt,
    this.notes,
  });

  final String id;
  final String medicineId;

  /// When the dose is due, as UTC.
  final DateTime scheduledFor;

  final DoseStatus status;
  final DateTime? takenAt;
  final String? notes;

  bool get isPending => status == DoseStatus.pending;

  DoseLog copyWith({
    DoseStatus? status,
    DateTime? takenAt,
    bool clearTakenAt = false,
    String? notes,
  }) => DoseLog(
    id: id,
    medicineId: medicineId,
    scheduledFor: scheduledFor,
    status: status ?? this.status,
    takenAt: clearTakenAt ? null : (takenAt ?? this.takenAt),
    notes: notes ?? this.notes,
  );
}
