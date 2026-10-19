import 'package:aminotes/aminotes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled web code licenses show on the app license page', () async {
    AminotesController(hostFactory: FakeHost.new).dispose();
    final entries = await LicenseRegistry.licenses.where((e) => e.packages.contains('aminotes')).toList();
    final texts = entries.map((e) => e.paragraphs.map((p) => p.text).join('\n')).toList();
    expect(texts, contains(startsWith('@tiptap/core ')));
    expect(texts, contains(startsWith('prosemirror-model ')));
    expect(texts, contains(startsWith('mp4-muxer ')));
    // Everything bundled is MIT: no copyleft (GPL/LGPL) code ships in apps.
    expect(texts.every((t) => t.contains('Permission is hereby granted')), isTrue, reason: 'all MIT');
    expect(texts.any((t) => t.contains('GNU')), isFalse);
  });
}
