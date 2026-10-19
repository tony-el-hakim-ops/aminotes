import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'tiptap_bridge.dart';
import 'tiptap_host.dart';

class PlatformTiptapHost implements TiptapHost {
  PlatformTiptapHost({required void Function(String message) onMessage}) {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(tiptapBridgeChannel, onMessageReceived: (message) => onMessage(message.message))
      ..setNavigationDelegate(
        NavigationDelegate(
          // Only the bundled page; never navigate away from the editor.
          onNavigationRequest: (request) => request.url.startsWith('file:') || request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..loadFlutterAsset(tiptapEditorAsset);
  }

  late final WebViewController _controller;

  @override
  bool get isWeb => false;

  @override
  Future<void> runJavaScript(String script) => _controller.runJavaScript(script);

  @override
  Widget build(BuildContext context, {bool claimVerticalDrags = false}) {
    _claimVerticalDrags = claimVerticalDrags;
    return WebViewWidget(controller: _controller, gestureRecognizers: _gestureRecognizers);
  }

  // The native view reads its gesture recognizers once, when it's created:
  // the set never changes, and the recognizer asks at each touch whether to
  // take it.
  bool _claimVerticalDrags = false;
  late final _gestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
    Factory<EagerGestureRecognizer>(() => _ClaimableTouch(() => _claimVerticalDrags)),
  };

  // Flutter's own hit testing already routes taps over the native view.
  @override
  set interactive(bool value) {}

  @override
  void dispose() {}
}

/// While [claim] says so, takes each touch for the WebView the moment it lands,
/// so a surrounding scrolling list can't take its drags; otherwise stays out
/// and the list gets them.
///
/// It must win at once: a drag won only after the finger has moved (by a
/// VerticalDragGestureRecognizer competing with the list) reaches the Android
/// WebView as replayed touches, which it doesn't scroll for.
class _ClaimableTouch extends EagerGestureRecognizer {
  _ClaimableTouch(this.claim);

  final bool Function() claim;

  @override
  bool isPointerAllowed(PointerDownEvent event) => claim() && super.isPointerAllowed(event);
}
