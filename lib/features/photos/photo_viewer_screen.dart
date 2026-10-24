import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
        bottomNavigationBar: current == null
            ? null
            : _Details(photo: current),
      ),
    );
  }
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
