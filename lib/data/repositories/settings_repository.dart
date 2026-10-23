import '../../domain/models/weight_entry.dart';
import '../db/app_database.dart';

/// App preferences.
///
/// Typed accessors over a key/value table, so callers never deal with the
/// string encoding and an unreadable value falls back to the default rather
/// than throwing on startup.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const String weightUnitKey = 'weight_unit';

  Stream<WeightUnit> watchWeightUnit() =>
      _watch(weightUnitKey).map(_parseWeightUnit);

  Future<WeightUnit> weightUnit() async =>
      _parseWeightUnit(await _read(weightUnitKey));

  Future<void> setWeightUnit(WeightUnit unit) =>
      _write(weightUnitKey, unit.name);

  WeightUnit _parseWeightUnit(String? stored) {
    if (stored == null) {
      return WeightUnit.kilograms;
    }
    try {
      return WeightUnit.fromName(stored);
    } on StateError {
      // A value written by a newer build, or a corrupted row. Falling back
      // beats taking the screen down over a preference.
      return WeightUnit.kilograms;
    }
  }

  Stream<String?> _watch(String key) => (_db.select(
    _db.appSettings,
  )..where((row) => row.key.equals(key))).watchSingleOrNull().map(
    (row) => row?.value,
  );

  Future<String?> _read(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((setting) => setting.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(AppSettingRow(key: key, value: value));
}
