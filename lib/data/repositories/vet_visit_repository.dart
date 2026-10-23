import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/vet_visit.dart';
import '../../services/photo_store.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes the health log and the photos attached to it.
///
/// Attachment *files* are this repository's business as much as the rows are:
/// a row without its file is a broken thumbnail, and a file without its row
/// is dead weight in the owner's storage that nothing will ever clean up.
class VetVisitRepository {
  VetVisitRepository(
    this._db, {
    PhotoStore? photoStore,
    this.uuid = const Uuid(),
  }) : _photos = photoStore;

  final AppDatabase _db;
  final PhotoStore? _photos;
  final Uuid uuid;

  /// One pet's visits, most recent first.
  Stream<List<VetVisit>> watchForPet(String petId) {
    final query = _db.select(_db.vetVisits)
      ..where((visit) => visit.petId.equals(petId))
      ..orderBy([(visit) => OrderingTerm.desc(visit.visitedOn)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Stream<List<VisitAttachment>> watchAttachments(String visitId) {
    final query = _db.select(_db.visitAttachments)
      ..where((attachment) => attachment.visitId.equals(visitId))
      ..orderBy([(attachment) => OrderingTerm.asc(attachment.addedAt)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<VetVisit?> findById(String id) async {
    final row = await (_db.select(_db.vetVisits)
          ..where((visit) => visit.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  Future<VetVisit> create({
    required String petId,
    required DateTime visitedOn,
    required String reason,
    String? clinic,
    String? vetName,
    String? notes,
    List<String> attachmentPaths = const [],
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final visit = VetVisit(
      id: uuid.v4(),
      petId: petId,
      visitedOn: visitedOn,
      reason: reason.trim(),
      clinic: _trimmed(clinic),
      vetName: _trimmed(vetName),
      notes: _trimmed(notes),
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await _db.transaction(() async {
      await _db.into(_db.vetVisits).insert(visit.toInsertable());
      for (final path in attachmentPaths) {
        await _insertAttachment(visit.id, path, timestamp);
      }
    });
    return visit;
  }

  Future<void> update(VetVisit visit, {DateTime? now}) async {
    await _db
        .update(_db.vetVisits)
        .replace(
          visit
              .copyWith(updatedAt: (now ?? DateTime.now()).toUtc())
              .toInsertable(),
        );
  }

  Future<VisitAttachment> addAttachment(
    String visitId,
    String filePath, {
    String? caption,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return _insertAttachment(visitId, filePath, timestamp, caption: caption);
  }

  /// Removes an attachment and the file behind it.
  Future<void> deleteAttachment(String id) async {
    final row = await (_db.select(_db.visitAttachments)
          ..where((attachment) => attachment.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return;
    }
    await (_db.delete(_db.visitAttachments)
          ..where((attachment) => attachment.id.equals(id)))
        .go();
    await _photos?.delete(row.filePath);
  }

  /// Removes a visit, its attachment rows and their files.
  ///
  /// The rows would cascade on their own; the files would not, and nothing
  /// else would ever come looking for them.
  Future<void> delete(String id) async {
    final attachments = await (_db.select(_db.visitAttachments)
          ..where((attachment) => attachment.visitId.equals(id)))
        .get();

    await (_db.delete(_db.vetVisits)..where((visit) => visit.id.equals(id)))
        .go();

    for (final attachment in attachments) {
      await _photos?.delete(attachment.filePath);
    }
  }

  Future<VisitAttachment> _insertAttachment(
    String visitId,
    String filePath,
    DateTime timestamp, {
    String? caption,
  }) async {
    final attachment = VisitAttachment(
      id: uuid.v4(),
      visitId: visitId,
      filePath: filePath,
      caption: _trimmed(caption),
      addedAt: timestamp,
    );
    await _db
        .into(_db.visitAttachments)
        .insert(
          VisitAttachmentRow(
            id: attachment.id,
            visitId: attachment.visitId,
            filePath: attachment.filePath,
            caption: attachment.caption,
            addedAt: attachment.addedAt,
          ),
        );
    return attachment;
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

extension on VetVisit {
  VetVisitRow toInsertable() => VetVisitRow(
    id: id,
    petId: petId,
    visitedOn: visitedOn,
    reason: reason,
    clinic: clinic,
    vetName: vetName,
    notes: notes,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
