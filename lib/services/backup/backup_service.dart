import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../data/db/app_database.dart';

/// Reads and writes the whole database as a single portable file.
///
/// A zip rather than bare JSON: attachments and pet photos are files on disk,
/// and a backup that silently drops them is worse than no backup — the owner
/// only finds out when they restore.
class BackupService {
  BackupService(this._db, {required this.photosRoot});

  final AppDatabase _db;

  /// Where photo files live. Paths inside the archive are relative to this,
  /// because absolute paths differ between installs and devices.
  final Directory photosRoot;

  /// Bumped only when the archive layout changes in a way an older build
  /// could not read.
  static const int formatVersion = 1;

  static const String _manifest = 'backup.json';
  static const String _photoPrefix = 'photos/';

  static const ValueSerializer _serializer = _BackupSerializer();

  /// The whole database and its photos, as a zip.
  Future<Uint8List> exportArchive({DateTime? now}) async {
    final tables = <String, List<Map<String, dynamic>>>{
      'pets': _json(await _db.select(_db.pets).get()),
      'reminders': _json(await _db.select(_db.reminders).get()),
      'reminderEvents': _json(await _db.select(_db.reminderEvents).get()),
      'prescriptions': _json(await _db.select(_db.prescriptions).get()),
      'medicines': _json(await _db.select(_db.medicines).get()),
      'doseLogs': _json(await _db.select(_db.doseLogs).get()),
      'vetVisits': _json(await _db.select(_db.vetVisits).get()),
      'visitAttachments': _json(await _db.select(_db.visitAttachments).get()),
      'vaccinationRecords': _json(
        await _db.select(_db.vaccinationRecords).get(),
      ),
      'weightEntries': _json(await _db.select(_db.weightEntries).get()),
      'appSettings': _json(await _db.select(_db.appSettings).get()),
    };

    final archive = Archive();
    // Rewrite every file reference to a path inside the archive, adding the
    // file as we go. Done before the manifest is encoded so the two agree.
    _packFiles(archive, tables['pets']!, 'photoPath');
    _packFiles(archive, tables['visitAttachments']!, 'filePath');
    _packFileLists(archive, tables['prescriptions']!, 'imagePaths');

    final manifest = jsonEncode({
      'formatVersion': formatVersion,
      'schemaVersion': _db.schemaVersion,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'tables': tables,
    });
    final manifestBytes = utf8.encode(manifest);
    archive.addFile(
      ArchiveFile(_manifest, manifestBytes.length, manifestBytes),
    );

    return ZipEncoder().encodeBytes(archive);
  }

  /// Replaces everything in the database with the contents of [bytes].
  ///
  /// Replace rather than merge: two installs that have both moved on have no
  /// shared notion of which version of a row is right, and silently keeping
  /// the wrong one is worse than being told the import overwrites.
  Future<BackupSummary> importArchive(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifestFile = archive.files
        .where((file) => file.name == _manifest)
        .firstOrNull;
    if (manifestFile == null) {
      throw const BackupFormatException('This file is not a PawsLog backup.');
    }

    final manifest =
        jsonDecode(utf8.decode(manifestFile.readBytes()!))
            as Map<String, dynamic>;
    final version = manifest['formatVersion'] as int?;
    if (version == null || version > formatVersion) {
      throw BackupFormatException(
        'This backup was made by a newer version of PawsLog.',
      );
    }

    final tables = (manifest['tables'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        [for (final row in value as List) (row as Map).cast<String, dynamic>()],
      ),
    );

    // Photos first: if writing them fails, the database is still the one the
    // owner had, rather than a set of rows pointing at files that never
    // arrived.
    await _unpackFiles(archive, tables['pets'] ?? [], 'photoPath');
    await _unpackFiles(archive, tables['visitAttachments'] ?? [], 'filePath');
    await _unpackFileLists(
      archive,
      tables['prescriptions'] ?? [],
      'imagePaths',
    );

    await _db.transaction(() async {
      // Reverse dependency order, so no foreign key is ever left dangling.
      await _db.delete(_db.appSettings).go();
      await _db.delete(_db.weightEntries).go();
      await _db.delete(_db.vaccinationRecords).go();
      await _db.delete(_db.visitAttachments).go();
      await _db.delete(_db.vetVisits).go();
      await _db.delete(_db.doseLogs).go();
      await _db.delete(_db.medicines).go();
      await _db.delete(_db.prescriptions).go();
      await _db.delete(_db.reminderEvents).go();
      await _db.delete(_db.reminders).go();
      await _db.delete(_db.pets).go();

      // Then forwards, so every parent exists before its children.
      await _db.batch((batch) {
        batch
          ..insertAll(_db.pets, _rows(tables['pets'], PetRow.fromJson))
          ..insertAll(
            _db.reminders,
            _rows(tables['reminders'], ReminderRow.fromJson),
          )
          ..insertAll(
            _db.reminderEvents,
            _rows(tables['reminderEvents'], ReminderEventRow.fromJson),
          )
          // Visits before prescriptions, and prescriptions before medicines:
          // a prescription may belong to a visit, and a medicine to a
          // prescription, and foreign keys are enforced row by row.
          ..insertAll(
            _db.vetVisits,
            _rows(tables['vetVisits'], VetVisitRow.fromJson),
          )
          ..insertAll(
            _db.prescriptions,
            _rows(tables['prescriptions'], PrescriptionRow.fromJson),
          )
          ..insertAll(
            _db.medicines,
            _rows(tables['medicines'], MedicineRow.fromJson),
          )
          ..insertAll(
            _db.doseLogs,
            _rows(tables['doseLogs'], DoseLogRow.fromJson),
          )
          ..insertAll(
            _db.visitAttachments,
            _rows(tables['visitAttachments'], VisitAttachmentRow.fromJson),
          )
          ..insertAll(
            _db.vaccinationRecords,
            _rows(tables['vaccinationRecords'], VaccinationRecordRow.fromJson),
          )
          ..insertAll(
            _db.weightEntries,
            _rows(tables['weightEntries'], WeightEntryRow.fromJson),
          )
          ..insertAll(
            _db.appSettings,
            _rows(tables['appSettings'], AppSettingRow.fromJson),
          );
      });
    });

    return BackupSummary(
      pets: tables['pets']?.length ?? 0,
      reminders: tables['reminders']?.length ?? 0,
      medicines: tables['medicines']?.length ?? 0,
      visits: tables['vetVisits']?.length ?? 0,
      weighings: tables['weightEntries']?.length ?? 0,
      photos: archive.files
          .where((file) => file.name.startsWith(_photoPrefix))
          .length,
    );
  }

  List<Map<String, dynamic>> _json(Iterable<DataClass> rows) => [
    for (final row in rows) row.toJson(serializer: _serializer),
  ];

  List<D> _rows<D>(
    List<Map<String, dynamic>>? rows,
    D Function(Map<String, dynamic>, {ValueSerializer? serializer}) fromJson,
  ) => [
    for (final row in rows ?? const <Map<String, dynamic>>[])
      fromJson(row, serializer: _serializer),
  ];

  /// Copies the file each row points at into the archive, replacing the
  /// absolute path with the name it was stored under.
  void _packFiles(
    Archive archive,
    List<Map<String, dynamic>> rows,
    String field,
  ) {
    for (final row in rows) {
      final path = row[field] as String?;
      if (path == null) {
        continue;
      }
      final file = File(path);
      if (!file.existsSync()) {
        // The row outlived its file. Keep the row, drop the reference, so a
        // restore shows a placeholder rather than a path to nothing.
        row[field] = null;
        continue;
      }
      final name = '$_photoPrefix${_relativeName(path)}';
      final bytes = file.readAsBytesSync();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      row[field] = name;
    }
  }

  /// The same, for a field holding a list of paths.
  ///
  /// Page order survives: a missing page is dropped from the list rather than
  /// nulled in place, because a prescription's pages are read in order and a
  /// hole in the middle would be worse than a shorter list.
  void _packFileLists(
    Archive archive,
    List<Map<String, dynamic>> rows,
    String field,
  ) {
    for (final row in rows) {
      final paths = (row[field] as List?)?.cast<String>();
      if (paths == null) {
        continue;
      }
      final packed = <String>[];
      for (final path in paths) {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        final name = '$_photoPrefix${_relativeName(path)}';
        final bytes = file.readAsBytesSync();
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
        packed.add(name);
      }
      row[field] = packed;
    }
  }

  /// Writes archived files back under [photosRoot] and points the rows at
  /// where they actually landed.
  Future<void> _unpackFiles(
    Archive archive,
    List<Map<String, dynamic>> rows,
    String field,
  ) async {
    for (final row in rows) {
      final name = row[field] as String?;
      if (name == null || !name.startsWith(_photoPrefix)) {
        continue;
      }
      final entry = archive.files
          .where((file) => file.name == name)
          .firstOrNull;
      if (entry == null) {
        row[field] = null;
        continue;
      }
      final destination = File(
        p.join(photosRoot.path, name.substring(_photoPrefix.length)),
      );
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(entry.readBytes()!);
      row[field] = destination.path;
    }
  }

  /// The same, for a field holding a list of paths.
  Future<void> _unpackFileLists(
    Archive archive,
    List<Map<String, dynamic>> rows,
    String field,
  ) async {
    for (final row in rows) {
      final names = (row[field] as List?)?.cast<String>();
      if (names == null) {
        continue;
      }
      final restored = <String>[];
      for (final name in names) {
        if (!name.startsWith(_photoPrefix)) {
          continue;
        }
        final entry = archive.files
            .where((file) => file.name == name)
            .firstOrNull;
        if (entry == null) {
          continue;
        }
        final destination = File(
          p.join(photosRoot.path, name.substring(_photoPrefix.length)),
        );
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(entry.readBytes()!);
        restored.add(destination.path);
      }
      row[field] = restored;
    }
  }

  /// A stable name for a photo inside the archive.
  String _relativeName(String absolutePath) {
    final relative = p.relative(absolutePath, from: photosRoot.path);
    // A file from outside the photos directory would otherwise be written
    // with `..` segments, which a restore must never follow.
    return relative.startsWith('..') || p.isAbsolute(relative)
        ? p.basename(absolutePath)
        : relative;
  }
}

/// How rows are written into, and read back out of, the manifest.
///
/// DateTimes go in as ISO-8601 strings rather than epoch milliseconds, so a
/// backup file is legible and the UTC flag survives the round trip.
///
/// Two columns are lists behind a type converter: the medicine dosing times
/// (`List<int>`) and a prescription's pages (`List<String>`). `jsonDecode`
/// hands any array back as `List<dynamic>`, which drift's default serializer
/// casts straight to the element type and throws, so both are converted
/// here instead.
class _BackupSerializer extends ValueSerializer {
  const _BackupSerializer();

  static const ValueSerializer _inner = ValueSerializer.defaults(
    serializeDateTimeValuesAsString: true,
  );

  @override
  T fromJson<T>(dynamic json) {
    if (json is List && <T>[] is List<List<int>?>) {
      return json.cast<int>() as T;
    }
    if (json is List && <T>[] is List<List<String>?>) {
      return json.cast<String>() as T;
    }
    return _inner.fromJson<T>(json);
  }

  @override
  dynamic toJson<T>(T value) => _inner.toJson<T>(value);
}

/// What an import brought in, for telling the owner afterwards.
class BackupSummary {
  const BackupSummary({
    required this.pets,
    required this.reminders,
    required this.medicines,
    required this.visits,
    required this.weighings,
    required this.photos,
  });

  final int pets;
  final int reminders;
  final int medicines;
  final int visits;
  final int weighings;
  final int photos;

  String describe() => [
    '$pets ${pets == 1 ? 'pet' : 'pets'}',
    '$reminders reminders',
    '$medicines medicines',
    '$visits visits',
    '$weighings weighings',
    '$photos photos',
  ].join(', ');
}

/// The file was not something this app can restore.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
