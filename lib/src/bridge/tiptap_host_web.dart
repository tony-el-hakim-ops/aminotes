import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'tiptap_bridge.dart';
import 'tiptap_host.dart';

/// Prefix the page adds when it posts to its parent (see tiptap_web/src/editor.js).
const _messagePrefix = 'tiptap-bridge:';

var _nextViewId = 0;

class PlatformTiptapHost implements TiptapHost {
  PlatformTiptapHost({required this.onMessage}) {
    _iframe = web.HTMLIFrameElement()
      ..src = ui_web.assetManager.getAssetUrl(tiptapEditorAsset)
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _iframe);
    _listener = _handleMessage.toJS;
    web.window.addEventListener('message', _listener);
  }

  final void Function(String message) onMessage;
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _listener;
  final _viewType = 'tiptap-editor-${_nextViewId++}';

  void _handleMessage(web.MessageEvent event) {
    // Only messages from our own page, same origin.
    if (event.source != _iframe.contentWindow || event.origin != web.window.location.origin) return;
    final data = event.data;
    if (data.isA<JSString>()) {
      final text = (data as JSString).toDart;
      if (text.startsWith(_messagePrefix)) onMessage(text.substring(_messagePrefix.length));
    }
  }

  @override
  bool get isWeb => true;

  @override
  Future<void> runJavaScript(String script) async {
    // The page is served from the app's own origin, so the parent may run
    // script in it directly, just like WebViewController.runJavaScript.
    final window = _iframe.contentWindow;
    if (window == null) return;
    (window as JSObject).callMethod('eval'.toJS, script.toJS);
  }

  @override
  // The browser sends drags inside the iframe to the page by itself.
  Widget build(BuildContext context, {bool claimVerticalDrags = false}) => HtmlElementView(viewType: _viewType);

  @override
  set interactive(bool value) => _iframe.style.pointerEvents = value ? 'auto' : 'none';

  @override
  void dispose() => web.window.removeEventListener('message', _listener);
}
