import 'package:drift/drift.dart';

import '../../../domain/models/dose_log.dart';
import 'medicines.dart';

/// One row per dose: what is due, what was taken, and what was missed.
@DataClassName('DoseLogRow')
class DoseLogs extends Table {
  TextColumn get id => text()();
  TextColumn get medicineId =>
      text().references(Medicines, #id, onDelete: KeyAction.cascade)();

  /// When the dose is due, as UTC.
  DateTimeColumn get scheduledFor => dateTime()();

  TextColumn get status => textEnum<DoseStatus>()();
  DateTimeColumn get takenAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
