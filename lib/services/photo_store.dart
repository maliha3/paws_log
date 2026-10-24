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

  /// Copies a file already on disk into [folder], returning the new path.
  ///
  /// For a photo that has to belong in two places at once: promoting an album
  /// photo to the portrait copies it rather than sharing the path, so
  /// deleting it from the album cannot leave the portrait pointing at
  /// nothing.
  Future<String> copyInto(String path, {String folder = petPhotos}) async {
    final destination = await directory(folder);
    final extension = p.extension(path).isEmpty ? '.jpg' : p.extension(path);
    final target = p.join(destination.path, '${uuid.v4()}$extension');
    await File(path).copy(target);
    return target;
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
///
/// Its file work is deliberately **synchronous**. A widget test runs under a
/// fake clock, and an asynchronous file-system future started from a widget
/// callback never completes there — the handler hangs on its first await and
/// everything after it silently never runs. `runAsync` cannot rescue it,
/// because the callback is dispatched in the binding's zone rather than the
/// test's. Synchronous syscalls have no such problem, so the files are real
/// and the assertions about them mean something.
@visibleForTesting
class FixedPhotoStore extends PhotoStore {
  FixedPhotoStore({this.taken, this.picked = const [], Directory? root})
    : _root = root ?? Directory.systemTemp;

  /// Stands in for the documents directory, which no test host has.
  final Directory _root;

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

  @override
  Future<Directory> directory(String folderName) async {
    final folder = Directory(p.join(_root.path, folderName));
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }
    return folder;
  }

  @override
  Future<String> copyInto(
    String path, {
    String folder = PhotoStore.petPhotos,
  }) async {
    final destination = await directory(folder);
    final extension = p.extension(path).isEmpty ? '.jpg' : p.extension(path);
    final target = p.join(destination.path, '${uuid.v4()}$extension');
    File(path).copySync(target);
    return target;
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

final photoStoreProvider = Provider<PhotoStore>((ref) => PhotoStore());
