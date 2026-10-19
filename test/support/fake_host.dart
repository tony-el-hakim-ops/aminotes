import 'dart:convert';

import 'package:aminotes/src/bridge/tiptap_host.dart';
import 'package:flutter/widgets.dart';

/// Stands in for the WebView: records the JavaScript the package runs and lets
/// a test post messages as if from the editor page.
class FakeHost implements TiptapHost {
  FakeHost(this.onMessage);

  final void Function(String message) onMessage;
  final scripts = <String>[];
  int builds = 0;

  /// What the last build asked for (see [TiptapHost.build]).
  bool claimVerticalDrags = false;
  bool disposed = false;

  /// Replies to `requestJSON(id)` calls with this document, when set.
  Map<String, dynamic>? replyDoc;

  void postFromPage(String message) => onMessage(message);

  @override
  bool get isWeb => false;

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
    final id = RegExp(r'requestJSON\((\d+)\)').firstMatch(script)?.group(1);
    final doc = replyDoc;
    if (id != null && doc != null) {
      Future.microtask(() => postFromPage('{"type":"json","id":$id,"doc":${jsonEncode(doc)}}'));
    }
  }

  @override
  Widget build(BuildContext context, {bool claimVerticalDrags = false}) {
    builds++;
    this.claimVerticalDrags = claimVerticalDrags;
    return const SizedBox.expand(key: ValueKey('fake-webview'));
  }

  @override
  void dispose() => disposed = true;

  /// Whether the page takes clicks (false while something covers the editor).
  bool interactiveValue = true;

  @override
  set interactive(bool value) => interactiveValue = value;

  /// Scripts that called `window.tiptap.<name>(`.
  Iterable<String> calls(String name) => scripts.where((s) => s.contains('window.tiptap.$name('));
}
