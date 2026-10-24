import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../photo_store.dart';

/// Gets prescription pages onto the device, from the camera or from Photos.
///
/// Both routes end the same way: files copied into the app's documents
/// directory, in page order. Whatever the scanner or picker hands back lives
/// in a cache the OS may clear.
abstract interface class ScanService {
  /// Scans pages with the document camera. Empty if the owner backed out.
  Future<List<String>> scanPages();

  /// Picks already-taken photos. Empty if the owner backed out.
  Future<List<String>> pickPages();
}

class DeviceScanService implements ScanService {
  DeviceScanService({PhotoStore? photoStore, this.uuid = const Uuid()})
    : _photos = photoStore ?? PhotoStore();

  final PhotoStore _photos;
  final Uuid uuid;

  /// Where prescription pages live, apart from pet portraits and visit
  /// attachments.
  static const String folder = 'prescriptions';

  @override
  Future<List<String>> scanPages() async {
    try {
      final scanned = await CunningDocumentScanner.getPictures(
        // Edge detection and cropping are the scanner's job; the app only
        // needs the finished pages.
        noOfPages: 10,
      );
      if (scanned == null || scanned.isEmpty) {
        return const [];
      }
      return _keep(scanned);
    } on Object catch (error) {
      // No camera, a denied permission, or no scanner on this platform. The
      // owner can still pick from Photos, so this is not a dead end.
      debugPrint('Could not scan: $error');
      return const [];
    }
  }

  @override
  Future<List<String>> pickPages() =>
      _photos.pickMany(folder: PhotoStore.visitAttachments).then(_relocate);

  /// Copies the scanner's temporary files somewhere durable.
  Future<List<String>> _keep(List<String> sources) async {
    final destination = await _photos.directory(folder);
    final kept = <String>[];

    for (final source in sources) {
      final extension = p.extension(source).isEmpty
          ? '.jpg'
          : p.extension(source);
      final file = File(p.join(destination.path, '${uuid.v4()}$extension'));
      await File(source).copy(file.path);
      kept.add(file.path);
    }
    return kept;
  }

  /// The picker already stored its copies; move them under the prescription
  /// folder so a prescription's pages are not mixed in with visit photos.
  Future<List<String>> _relocate(List<String> picked) async {
    if (picked.isEmpty) {
      return const [];
    }
    final destination = await _photos.directory(folder);
    final moved = <String>[];

    for (final path in picked) {
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      final target = p.join(destination.path, p.basename(path));
      moved.add((await file.rename(target)).path);
    }
    return moved;
  }
}

/// Hands back whatever it was given. For tests and for previewing the flow.
@visibleForTesting
class FixedScanService implements ScanService {
  const FixedScanService({this.scanned = const [], this.picked = const []});

  final List<String> scanned;
  final List<String> picked;

  @override
  Future<List<String>> scanPages() async => scanned;

  @override
  Future<List<String>> pickPages() async => picked;
}
