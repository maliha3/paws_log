import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_service.dart';

/// Moves a backup out to, and in from, the rest of the device.
///
/// Kept apart from [BackupService] so the export and import logic stays
/// testable without a share sheet or a file picker in the way.
class BackupSharing {
  const BackupSharing(this._service);

  final BackupService _service;

  /// Writes a backup and hands it to the share sheet.
  ///
  /// Returns false if the owner dismissed the sheet without choosing
  /// anything.
  Future<bool> exportAndShare({DateTime? now, bool includeAlbum = true}) async {
    final bytes = await _service.exportArchive(
      now: now,
      includeAlbum: includeAlbum,
    );
    final stamp = DateFormat(
      'yyyy-MM-dd',
    ).format(now ?? DateTime.now());

    // A temporary file, not the documents directory: this is a copy on its
    // way elsewhere, and leaving one behind after every export would grow
    // without limit.
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, 'pawslog-backup-$stamp.zip'));
    await file.writeAsBytes(bytes);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: 'PawsLog backup',
        title: 'PawsLog backup',
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  /// How big an export would be, split so the album can be weighed alone.
  Future<BackupSizes> estimateSize() => _service.estimateSize();

  /// Asks for a backup file and restores it.
  ///
  /// Returns null if the owner picked nothing.
  Future<BackupSummary?> pickAndImport() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose a PawsLog backup',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final file = picked.firstOrNull;
    if (file == null) {
      return null;
    }
    return _service.importArchive(await file.readAsBytes());
  }
}
