import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Keeps pet photos somewhere durable.
///
/// The picker hands back a file in a cache directory the OS is free to clear,
/// so the chosen image is copied into the app's documents directory and only
/// that path is stored.
class PhotoStore {
  PhotoStore({ImagePicker? picker, this.uuid = const Uuid()})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final Uuid uuid;

  /// Where pet portraits live.
  static const String petPhotos = 'pet_photos';

  /// Where photos attached to a vet visit live.
  static const String visitAttachments = 'visit_attachments';

  /// Where a pet's photo album lives.
  static const String petVault = 'pet_vault';

  /// Asks the owner for an image and returns the stored copy's path, or null
  /// if they backed out.
  Future<String?> pick(
    ImageSource source, {
    String folder = petPhotos,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) {
      return null;
    }
    return _store(picked, folder);
  }

  /// Asks for several images at once, for attaching to a visit.
  Future<List<String>> pickMany({String folder = visitAttachments}) async {
    final picked = await _picker.pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    return [for (final file in picked) await _store(file, folder)];
  }

  /// The app's folder for [folderName], created if it is not there yet.
  Future<Directory> directory(String folderName) async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(documents.path, folderName));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  Future<String> _store(XFile picked, String folderName) async {
    final folder = await directory(folderName);
    final extension = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path);
    final destination = p.join(folder.path, '${uuid.v4()}$extension');
    await File(picked.path).copy(destination);
    return destination;
  }

  /// Removes a stored photo, ignoring one that is already gone.
  Future<void> delete(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}

/// Hands back fixed paths instead of asking the OS. For tests, and for
/// walking the photo flows without a camera.
@visibleForTesting
class FixedPhotoStore extends PhotoStore {
  FixedPhotoStore({this.taken, this.picked = const []});

  /// What the camera "returns". Null means the owner backed out.
  final String? taken;

  /// What the Photos picker "returns".
  final List<String> picked;

  @override
  Future<String?> pick(
    ImageSource source, {
    String folder = PhotoStore.petPhotos,
  }) async => taken;

  @override
  Future<List<String>> pickMany({
    String folder = PhotoStore.visitAttachments,
  }) async => picked;
}

final photoStoreProvider = Provider<PhotoStore>((ref) => PhotoStore());
