import 'package:flutter/material.dart';

import '../media/aminotes_media.dart';
import 'aminotes_strings.dart';

/// A full-screen view of a note's image: pinch to zoom, drag to move.
///
/// The [AminotesToolbar] opens it for a tapped image; open it yourself with
/// [AminotesImageViewer.show]. With [onDelete], it shows a Delete button that
/// calls it and closes the viewer.
class AminotesImageViewer extends StatelessWidget {
  const AminotesImageViewer({super.key, required this.src, this.alt, this.onDelete});

  /// `local:…`, `https://…` or (web) `blob:…`.
  final String src;

  /// The image's description, read by screen readers.
  final String? alt;

  /// Shows a Delete button that calls this and closes the viewer.
  final VoidCallback? onDelete;

  /// Opens the viewer as a full-screen route.
  static Future<void> show(BuildContext context, {required String src, String? alt, VoidCallback? onDelete}) {
    // Carry the app's strings into the new route.
    final strings = AminotesStrings.of(context);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AminotesStringsScope(
          strings: strings,
          child: AminotesImageViewer(src: src, alt: alt, onDelete: onDelete),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AminotesStrings.of(context);
    Widget missing() => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (onDelete != null)
            IconButton(
              tooltip: strings.deleteImage,
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                onDelete!();
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: FutureBuilder<ImageProvider?>(
        future: AminotesMedia.imageProvider(src),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const SizedBox.expand();
          final provider = snapshot.data;
          return Center(
            child: provider == null
                ? missing()
                : InteractiveViewer(
                    maxScale: 5,
                    child: Image(
                      image: provider,
                      semanticLabel: alt,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, _, _) => missing(),
                      // Remote images download again here (the web reports no
                      // progress): a spinner until the first frame.
                      frameBuilder: (context, child, frame, sync) => frame == null && !sync
                          ? const Center(child: CircularProgressIndicator(color: Colors.white70))
                          : child,
                    ),
                  ),
          );
        },
      ),
    );
  }
}
