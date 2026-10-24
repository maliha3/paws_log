import 'dart:io';

import 'package:flutter/material.dart';

/// Photos at full size, zoomable.
///
/// Built for prescription pages, where reading the small print is the whole
/// reason the photo exists, and reused for visit attachments.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    required this.paths,
    this.initialPage = 0,
    this.label,
    super.key,
  });

  final List<String> paths;
  final int initialPage;

  /// What the pages are, for the title: "Page" by default.
  final String? label;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller = PageController(
    initialPage: widget.initialPage,
  );
  late int _page = widget.initialPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label ?? 'Page';

    // Its own dark scheme rather than the app's: a photograph is judged
    // against black, and the chrome has to read on top of it either way.
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          title: Text(
            widget.paths.length == 1
                ? label
                : '$label ${_page + 1} of ${widget.paths.length}',
          ),
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.paths.length,
          onPageChanged: (page) => setState(() => _page = page),
          itemBuilder: (context, index) =>
              ZoomablePhoto(path: widget.paths[index]),
        ),
      ),
    );
  }
}

/// One photo, pinch to zoom and double-tap to fill the screen.
///
/// Public so that screens needing their own chrome around a photo — an album
/// with per-photo actions, say — reuse the gesture handling rather than
/// growing a second copy of it.
class ZoomablePhoto extends StatefulWidget {
  const ZoomablePhoto({required this.path, super.key});

  final String path;

  @override
  State<ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<ZoomablePhoto> {
  final TransformationController _transform = TransformationController();

  static const double _doubleTapScale = 2.5;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Zooms to where the tap landed, or back out if already zoomed.
  void _toggleZoom(TapDownDetails details) {
    if (_transform.value != Matrix4.identity()) {
      _transform.value = Matrix4.identity();
      return;
    }
    final at = details.localPosition;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        -at.dx * (_doubleTapScale - 1),
        -at.dy * (_doubleTapScale - 1),
        0,
        1,
      )
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, _doubleTapScale, 1);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onDoubleTapDown: _toggleZoom,
    // A double tap with no handler does nothing, and without this the
    // gesture recogniser never fires onDoubleTapDown.
    onDoubleTap: () {},
    child: InteractiveViewer(
      transformationController: _transform,
      maxScale: 6,
      child: Center(
        child: Image.file(
          File(widget.path),
          fit: BoxFit.contain,
          errorBuilder: (context, _, _) => const MissingPhoto(),
        ),
      ),
    ),
  );
}

/// What stands in for a photo whose file is no longer there.
class MissingPhoto extends StatelessWidget {
  const MissingPhoto({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_not_supported_outlined, size: 40),
        SizedBox(height: 12),
        Text(
          'This photo is no longer on the device.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
