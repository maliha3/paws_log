import 'dart:io';

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

  static const String _folder = 'pet_photos';

  /// Asks the owner for an image and returns the stored copy's path, or null
  /// if they backed out.
  Future<String?> pick(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked == null) {
      return null;
    }
    return _store(picked);
  }

  Future<String> _store(XFile picked) async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(documents.path, _folder));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
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

final photoStoreProvider = Provider<PhotoStore>((ref) => PhotoStore());
