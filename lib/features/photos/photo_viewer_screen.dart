import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/widgets/image_viewer_screen.dart';
import '../../data/providers.dart';
import '../../domain/models/pet_photo.dart';

/// One pet's album at full size, swipe between, pinch to zoom.
///
/// Watches the album rather than taking a snapshot of it, so a caption edited
/// or a photo deleted from here is reflected immediately — and running out of
/// photos closes the screen instead of showing an empty frame.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({
    required this.petId,
    required this.initialPhotoId,
    super.key,
  });

  final String petId;

  /// Which photo to open on. Identified rather than indexed: the album can
  /// shift under the screen while it is open.
  final String initialPhotoId;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  PageController? _controller;
  late String _currentId = widget.initialPhotoId;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final album = ref.watch(photosForPetProvider(widget.petId));
    final photos = album.hasValue ? album.requireValue : const <PetPhoto>[];

    // The last photo was deleted while this screen was open.
    if (album.hasValue && photos.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      });
    }

    var index = photos.indexWhere((photo) => photo.id == _currentId);
    if (index < 0) {
      // The photo being viewed is gone; stay where it was in the list.
      index = 0;
    }
    _controller ??= PageController(initialPage: index);
    final current = photos.isEmpty ? null : photos[index];

    // Its own dark scheme rather than the app's: a photograph is judged
    // against black, and the chrome has to read on top of it either way.
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          title: Text(
            photos.length <= 1
                ? 'Photo'
                : 'Photo ${index + 1} of ${photos.length}',
          ),
          actions: [
            if (current != null)
              PopupMenuButton<_PhotoAction>(
                tooltip: 'Photo options',
                onSelected: (action) => _run(action, current),
                itemBuilder: (context) => [
                  for (final action in _PhotoAction.values)
                    PopupMenuItem(value: action, child: Text(action.label)),
                ],
              ),
          ],
        ),
        body: photos.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : PageView.builder(
                controller: _controller,
                itemCount: photos.length,
                onPageChanged: (page) =>
                    setState(() => _currentId = photos[page].id),
                itemBuilder: (context, at) =>
                    ZoomablePhoto(path: photos[at].path),
              ),
        bottomNavigationBar: current == null ? null : _Details(photo: current),
      ),
    );
  }
}

extension on _PhotoViewerScreenState {
  Future<void> _run(_PhotoAction action, PetPhoto photo) => switch (action) {
    _PhotoAction.caption => _editCaption(photo),
    _PhotoAction.share => _share(photo),
    _PhotoAction.portrait => _setAsPortrait(photo),
    _PhotoAction.delete => _confirmDelete(photo),
  };

  Future<void> _editCaption(PetPhoto photo) async {
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => _CaptionDialog(caption: photo.caption),
    );
    if (caption != null) {
      await ref.read(petPhotoRepositoryProvider).setCaption(photo.id, caption);
    }
  }

  Future<void> _share(PetPhoto photo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(photo.path)], text: photo.caption),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share that photo: $error')),
      );
    }
  }

  Future<void> _setAsPortrait(PetPhoto photo) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(petRepositoryProvider)
        .setPortrait(widget.petId, sourcePath: photo.path);
    messenger.showSnackBar(
      const SnackBar(content: Text('Profile photo updated.')),
    );
  }

  /// Deleting takes the file with it, so it is worth asking.
  Future<void> _confirmDelete(PetPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text(
          'It is removed from the album and from this phone. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(petPhotoRepositoryProvider).delete(photo.id);
    }
  }
}

/// Writes a caption.
///
/// A widget of its own so that it owns the controller: disposing one the
/// moment `showDialog` returns disposes it while the dialog is still
/// animating out, and the field it still belongs to rebuilds on a dead
/// controller.
class _CaptionDialog extends StatefulWidget {
  const _CaptionDialog({this.caption});

  final String? caption;

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.caption ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Caption'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLines: 3,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(hintText: 'Asleep in the sink'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}

/// What can be done to the photo on screen.
enum _PhotoAction {
  caption('Edit caption'),
  share('Share'),
  portrait('Set as profile photo'),
  delete('Delete');

  const _PhotoAction(this.label);

  final String label;
}

/// When the photo was taken, and its caption if it has one.
class _Details extends StatelessWidget {
  const _Details({required this.photo});

  final PetPhoto photo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.5),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat.yMMMd().format(photo.takenAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
              if (photo.hasCaption) ...[
                const SizedBox(height: 4),
                Text(photo.caption!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
