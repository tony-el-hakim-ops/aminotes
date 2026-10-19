import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

var _registered = false;

/// Adds the licenses of the JavaScript bundled in the editor page (Tiptap,
/// ProseMirror and their dependencies, all MIT) to the app's license page
/// (`showLicensePage`), as their licenses require. Runs once, from the first
/// `AminotesController`.
void registerAminotesLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('packages/aminotes/assets/editor/NOTICES.txt');
    // One block per npm package, starting with "name version (license)".
    for (final block in text.trim().split(RegExp(r'\n\n-{72}\n\n'))) {
      yield LicenseEntryWithLineBreaks(const ['aminotes'], block);
    }
  });
}
