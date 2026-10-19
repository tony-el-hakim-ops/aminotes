# aminotes example

A demo app for the `aminotes` package, and the app the integration tests run
in. It shows the package the way a host app would use it.

## Run

```bash
flutter run                 # Android / iOS device or emulator
flutter run -d chrome       # web
```

## What's on screen

- **Note box**: a small `AminotesEditor` that grows with the note
  (`autoHeight`). Tap it to edit; the compact toolbar sits above the
  keyboard. The corner button opens the same note full screen, with the full
  toolbar and a custom "Insert date" button.
- **Under the box**: live word and character counts, and how many times the
  note was saved (`onChanged`).
- **Load buttons**: a sample note with every feature, plain text, HTML,
  Arabic, content written by a newer web app (kept unchanged), and a broken
  note (shown read-only, never modified).
- **Upload media**: pretends to upload recordings and photos and swaps their
  `local:` sources for `https://` URLs.
- **Show JSON**: the note exactly as it would be saved.
- **Playground** (palette icon): ready-made designs (plain, card, sticky
  note, Notion style, dark); change the box, the text (font, size, colors,
  custom CSS) and the toolbar buttons live, then copy the Dart code.
- **App bar**: a list of notes drawn with `AminotesPreview` (no WebView per
  note), dark mode and Arabic.

Tapping a link shows its URL in a dialog (`onLinkTap`); a real app would open
it with `url_launcher`.

## Integration tests

`integration_test/editor_test.dart` runs the real editor page:

```bash
tool/integration_android.sh [device]   # grants the microphone, then runs
flutter test integration_test -d <id>  # iOS (allow the microphone when asked)
tool/integration_web.sh                # Chrome, headless, fake microphone
```

The web script downloads a chromedriver matching your Chrome into
`.chromedriver/` (ignored by git) the first time.
