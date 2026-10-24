import '../../domain/models/weight_entry.dart';
import '../../domain/shedding_season.dart';
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
  static const String premiumKey = 'is_premium';
  static const String hemisphereKey = 'hemisphere';

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

  /// Which hemisphere the owner is in.
  ///
  /// App-wide rather than per pet: it is a fact about where the owner lives.
  /// It names the shedding windows and does not move them — see
  /// [inSheddingSeason].
  Stream<Hemisphere> watchHemisphere() =>
      _watch(hemisphereKey).map(_parseHemisphere);

  Future<Hemisphere> hemisphere() async =>
      _parseHemisphere(await _read(hemisphereKey));

  Future<void> setHemisphere(Hemisphere value) =>
      _write(hemisphereKey, value.name);

  Hemisphere _parseHemisphere(String? stored) {
    if (stored == null) {
      return Hemisphere.northern;
    }
    try {
      return Hemisphere.fromName(stored);
    } on StateError {
      return Hemisphere.northern;
    }
  }

  /// Whether the owner has unlocked the paid features.
  ///
  /// Stubbed: nothing checks a receipt yet, the value is simply stored. It
  /// lives in the settings table so both paths are reachable while the real
  /// purchase flow does not exist, and so the gate behaves consistently
  /// across restarts.
  Stream<bool> watchIsPremium() =>
      _watch(premiumKey).map((stored) => stored == 'true');

  Future<bool> isPremium() async => await _read(premiumKey) == 'true';

  Future<void> setPremium({required bool value}) =>
      _write(premiumKey, value.toString());

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
