import 'package:flutter/widgets.dart';

import 'tiptap_host_webview.dart' if (dart.library.js_interop) 'tiptap_host_web.dart' as platform;

/// Hosts the bundled Tiptap page: a WebView on Android/iOS, an iframe on the
/// web (webview_flutter has no web implementation; in a browser Tiptap simply
/// runs in an embedded page).
abstract class TiptapHost {
  /// [onMessage] receives the raw JSON strings the page posts.
  factory TiptapHost({required void Function(String message) onMessage}) = platform.PlatformTiptapHost;

  /// Whether the host is a browser, where the toolbar stays visible (there's
  /// no on-screen keyboard to sit above).
  bool get isWeb;

  Future<void> runJavaScript(String script);

  /// The view showing the page. [claimVerticalDrags]: whether vertical drags
  /// on it go to the page (to scroll the note, or resize an image) even
  /// inside a scrolling list, which would otherwise take them.
  Widget build(BuildContext context, {bool claimVerticalDrags = false});

  /// Whether the page takes clicks. Off while a dialog, sheet or route covers
  /// the editor: in a browser the iframe would otherwise take clicks meant for
  /// it (e.g. tapping outside a dialog to close it). No-op on Android/iOS.
  set interactive(bool value);

  void dispose();
}
