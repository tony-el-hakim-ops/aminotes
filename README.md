# aminotes

Tiptap note editing for Flutter apps. Notes are **Tiptap JSON**, the same
format as the web app. The real Tiptap editor is bundled inside the package, so
it works **fully offline**. The package draws no screens: your app decides where
the editor goes (a small box, full screen, anything) and how the toolbar looks.

**New here? Start with the [developer guide](doc/guide.md):** your first note
box in 5 minutes, choosing toolbar buttons, designing the note, voice notes,
images, uploads and troubleshooting. This README is the reference.

Platforms: Android (7+), iOS, web. Flutter 3.47+.

On Android the editor runs in the system WebView, which needs to be Chrome 80
or newer (any phone that updated "Android System WebView" in the last few
years). On an older one the editor can't open: `onError` reports
`AminotesErrorKind.webView` and the note stays visible as a read-only preview,
so ask the user to update Android System WebView from the Play Store.

> Status: **0.15.1, milestone M8.** All v1 features, checked on Android
> (emulator) and the web (Chrome). Next: testing on real devices (Android
> phone, iPhone) before 1.0.

## Install

```yaml
dependencies:
  aminotes:
    path: ../aminotes   # or a git dependency once published
```

Platform setup in the host app:

- **Android** (`android/app/src/main/AndroidManifest.xml`):
  `<uses-permission android:name="android.permission.INTERNET"/>` (media by URL)
  and `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` (voice notes).
- **iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription` (voice
  notes), `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription`
  (images), each with a sentence explaining why.
- Android needs no permission for images: the gallery uses the system photo
  picker.

## Use

```dart
final controller = AminotesController(
  initialContent: AminotesContent.json(savedNote),   // or .html(...) / .text(...)
  onChanged: (json) => saveNote(json),                // after typing pauses
);

// Anywhere, any size:
AminotesEditor(controller: controller, placeholder: 'Write a note…');

// Your own buttons...
IconButton(icon: Icon(Icons.format_bold), onPressed: controller.toggleBold);

// ...or the ready-made toolbar, e.g. above the keyboard while editing:
ValueListenableBuilder(
  valueListenable: controller.toolbarVisible, // editing, or recording
  builder: (context, visible, _) => visible
      ? AminotesToolbar(controller: controller, items: AminotesToolbarItem.compact)
      : const SizedBox.shrink(),
);

// Read the note at any time:
final json = await controller.getJson();

controller.dispose(); // when the note closes
```

### Saving safely

- `onChanged` fires after typing pauses (`changeDelay`, 400 ms).
- `flush()` sends pending edits to `onChanged` right away.
- `await controller.close()` returns the final JSON and disposes.
- `dispose()` flushes too; edits that arrive during dispose still reach `onChanged`,
  so check `mounted` there before calling `setState`.
- When the app goes to the background, edits are flushed and a recording in
  progress is saved into the note (`saveRecordingWhenInterrupted: false`
  discards it instead).

### Box that grows with the note

A note taller than its box scrolls inside it, even when the box sits in a
scrolling screen: while the note overflows its box, or while it's being
edited, drags on it go to the note; otherwise they scroll the screen.

```dart
AminotesEditor(controller: controller, autoHeight: true, minHeight: 120, maxHeight: 320);
```

It scrolls inside beyond `maxHeight`. `controller.contentHeight` gives the
height if you size it yourself. Until the editor page is ready (a fraction of
a second) the note shows as an `AminotesPreview`, so the box never looks
empty (`previewWhileLoading: false` turns it off). `controller.preload()` starts
the page early, e.g. in `initState`.

### Links and errors

```dart
AminotesController(
  onLinkTap: (url) => launchUrl(Uri.parse(url)), // links never open by themselves
  onError: (error) => log(error.kind, error.message), // load, recording, media, editor
);
```

### Small box → full screen

Show the **same controller** in a second `AminotesEditor` on a new route. Text,
cursor and undo history move with it; when the route closes they move back.
The editor that's covered shows `inactiveChild` meanwhile.

```dart
Navigator.push(context, MaterialPageRoute(
  builder: (_) => Scaffold(body: AminotesEditor(controller: controller)),
));
```

### Toolbar

`AminotesToolbar(items: ...)` takes `AminotesToolbarItem.compact` (small box:
bold, italic, underline, colors, lists), `AminotesToolbarItem.full` (default:
everything, with undo/redo) or your own list in any order, with
`AminotesToolbarItem.separator` between groups. `trailing:` pins a widget at the
end, e.g. a "full screen" button (default: "hide keyboard").

Built-in items: `undo`, `redo`, `bold`, `italic`, `underline`, `strikethrough`,
`inlineCode`, `textColor`, `highlight`, `link`, `heading1`–`heading3`,
`bulletList`, `numberedList`, `checklist`, `indent`, `outdent`, `quote`,
`codeBlock`, `divider`, `table`, `voiceNote`, `image`, `separator`.

Add your own buttons anywhere in the list, and replace any built-in icon:

```dart
AminotesToolbar(
  controller: controller,
  items: [
    ...AminotesToolbarItem.compact,
    AminotesToolbarItem.custom(
      icon: const Icon(Icons.today),
      tooltip: 'Insert date',
      onPressed: (c) => c.insertText(formatDate(DateTime.now())),
      isActive: (state) => false, // optional highlight
    ),
  ],
  icons: {AminotesToolbarItem.bold: MyIcons.bold},
)
```

### Languages

Built-in English and Arabic for every text the package shows (toolbar
tooltips, the link dialog, "unsupported content" labels inside the note),
picked from the app's locale. Change any text with `AminotesStringsScope`:

```dart
AminotesStringsScope(
  strings: AminotesStrings.arabic.copyWith(bold: 'عريض'),
  child: ...,
)
```

Right-to-left follows the app's `Directionality`: the toolbar flips, and each
paragraph of the note takes its own direction (Arabic or English).

### Voice notes

The toolbar's mic button (or `controller.startVoiceNote()`) records; Done
(`finishVoiceNote()`) inserts the voice note **at the cursor, inside the
sentence**; Cancel (`cancelVoiceNote()`) throws it away. Recordings are AAC
`.m4a`, saved offline in the app's documents folder, and stop on their own at
`maxVoiceNoteDuration` (10 min). While recording, `AminotesToolbar` shows
`AminotesRecordingBar` (timer, level, Cancel, Done); build your own on
`controller.recording` if you prefer. Show the toolbar with
`controller.toolbarVisible`: the microphone permission dialog takes focus from
the note, and the recording bar must stay up.

In the note a voice note is
`{"type": "voiceNote", "attrs": {"src": "local:voice_notes/….m4a", "duration": 7}}`.
`local:` means "only on this device". When online, upload:

```dart
final json = await controller.uploadPendingMedia((upload) async {
  // upload.read(), upload.fileName, upload.mimeType ('audio/mp4'), upload.path
  return await myApi.uploadFile(await upload.read(), upload.fileName); // → https URL
});
save(json); // the note now points at the URLs (not an undo step)
```

A failed file stays `local:` and is retried next time. For notes that aren't
open, `AminotesMedia.pendingUploads(json)` and `AminotesMedia.replaceSources`
do the same on plain JSON. `AminotesMedia.unusedLocalFiles(allNotes)` lists
recordings no note uses any more; delete them once those notes are saved
everywhere.

**Playing.** Tapping a voice note plays it (one at a time); its pill shows the
elapsed time. `AminotesToolbar` then shows `AminotesPlaybackBar`: play/pause,
a slider to seek, Delete and Close. Build your own on `controller.playback`
(`playing`, `position`, `duration`) with `pauseVoiceNote`, `resumeVoiceNote`,
`seekVoiceNote(position)`, `stopVoiceNote`, `deleteVoiceNote`.

### Images

The toolbar's image button (or `controller.pickImage(AminotesImageSource.gallery
/ .camera)`) picks a photo, scales it to at most 2048 px, stores it offline as
`local:images/….jpg` and inserts it at the cursor. It shows straight away: the
package hands the page the file for display while the note keeps the `local:`
reference. `insertImage(url)` inserts an image you already host;
`insertImageBytes(bytes)` stores and inserts your own bytes (Android/iOS).

`uploadPendingMedia` uploads images together with voice notes
(`upload.kind == 'image'`, `upload.mimeType` e.g. `image/jpeg`). An image that
can't be shown (not on this device yet, or offline) shows a grey placeholder.

**Resizing:** a tapped image shows a handle on each corner; drag one (finger
or mouse) to make the image smaller or bigger. Its proportions are kept, and
the size is saved as the image's `width`/`height` (Tiptap's standard image
attributes, which the web app reads too). On a narrower screen a resized
image still fits the width. `AminotesPreview` shows images at their resized
size.

**Alignment:** with a tapped image, the toolbar's align buttons place it left,
center or right on its line (tap the active one again to go back to the text
direction): `controller.setImageAlignment(AminotesImageAlignment.center)`.
Saved as the image's `align`; the web app needs the same attribute (see
doc/web-team-schema.md). `AminotesPreview` follows it.

**Tapping an image** selects it: `state.selectedNode` says which
(`kind`, `src`, `alt`), and the toolbar starts with View (full screen, pinch to
zoom: `AminotesImageViewer`) and Delete (`controller.deleteSelection()`; undo
brings it back). A tapped voice note can be deleted the same way.

### Word count

`controller.state.value.stats` has live `words` and `characters`;
`AminotesStats.of(json)` counts a saved note the same way without an editor
(e.g. in a list of notes).

### Tables

`controller.insertTable(rows:, columns:, withHeaderRow:)`, then
`addRowBefore/After`, `addColumnBefore/After`, `deleteRow`, `deleteColumn`,
`toggleHeaderRow`, `deleteTable` for the cell at the cursor
(`state.isActive('table')`). `AminotesToolbarItem.table` (in the full preset)
inserts tables; while the cursor is in one, the toolbar starts with the row and
column buttons. Wide tables scroll sideways inside the note.

### Lists of notes: `AminotesPreview`

Each `AminotesEditor` is a WebView, too heavy for a list of many notes. Show
notes there with `AminotesPreview`: plain Flutter widgets drawing the same
content (formatting, colors, lists, checklists, quotes, code, tables, images,
voice notes, unsupported-content boxes, Arabic). It's read-only and lets taps
through, so wrap it in your own `InkWell` to open the note in an editor.

```dart
InkWell(
  onTap: () => openNote(note),
  child: AminotesPreview(json: note, maxBlocks: 6, imageHeight: 100),
)
```

Show only the top of long notes with `maxBlocks` and/or a fixed-height,
clipped box. `AminotesPreview.plainText(json)` gives the text for one-line
summaries or search.

### Look

**Try it first:** the example app's **Playground** (palette icon) shows
ready-made designs (plain, card, sticky note, Notion style, dark), lets you
change the box, the text and the toolbar buttons live, and gives you the Dart
code to paste into your app.

**The box is yours.** The package draws nothing around the note and its
background is transparent: wrap `AminotesEditor` in any widget (card, sticky
note, chat bubble, lined paper, rotated, animated).

**The note's text** is styled with `AminotesTheme`: colors (text, muted, accent,
voice-note pill, borders, code, selection, background), font, size, line
height and padding. Anything unset comes from the app's `Theme`, including dark
mode. Arabic and English paragraphs each take their own direction; empty notes
follow the app's `Directionality`.

**Your own font** (bundled in the app, e.g. a brand font):

```dart
AminotesTheme(
  fontFamily: 'Poppins',
  fonts: [
    AminotesFont('Poppins', 'assets/fonts/Poppins-Regular.ttf'),
    AminotesFont('Poppins', 'assets/fonts/Poppins-Bold.ttf', weight: FontWeight.w700),
  ],
)
```

Declare the files in your pubspec (under `fonts:` with the same family name,
so `AminotesPreview` matches too). `.ttf`, `.otf`, `.woff` and `.woff2` work.

#### Styling with CSS

For anything the settings don't cover, `AminotesTheme(css: ...)` adds CSS after
the package's own, so it wins:

```dart
AminotesTheme(css: '''
  .ProseMirror h1 { font-size: 2.4em; }                       /* bigger headings */
  .ProseMirror > * + * { margin-top: 0.25em; }                /* tighter spacing */
  .ProseMirror input[type='checkbox'] { border-radius: 50%; } /* round checkboxes */
''')
```

| Part of the note | Selector |
|---|---|
| Paragraphs, headings | `.ProseMirror p`, `.ProseMirror h1` … `h6` |
| Space between blocks | `.ProseMirror > * + *` |
| Bold, italic, underline, strike | `strong`, `em`, `u`, `s` |
| Links | `.ProseMirror a` |
| Highlight | `.ProseMirror mark` |
| Inline code, code block | `.ProseMirror code`, `.ProseMirror pre` |
| Bullet / numbered lists | `.ProseMirror ul`, `.ProseMirror ol`, `li` |
| Checklist, checkbox | `ul[data-type='taskList']`, `input[type='checkbox']`, `li[data-checked='true']` |
| Quote, divider | `.ProseMirror blockquote`, `.ProseMirror hr` |
| Images | `.ProseMirror img` |
| Tables | `.ProseMirror table`, `th`, `td` |
| Voice note pill | `.voice-note button`, `.voice-note-label` |
| Placeholder (empty note) | `.ProseMirror p.is-editor-empty:first-child::before` |
| Content from a newer web app | `.aminotes-unknown` |

The theme's values are available as CSS variables: `var(--text)`,
`var(--muted)`, `var(--primary)` (accent), `var(--primary-container)`,
`var(--on-primary-container)`, `var(--surface)`, `var(--border)`,
`var(--code-bg)`, `var(--font-size)`, `var(--line-height)`.

Custom CSS styles the editor only; `AminotesPreview` (plain Flutter) follows the
theme's colors, font and size.

### Colors

`controller.setTextColor(color)` and `controller.setHighlightColor(color)`
(`null` removes). Stored as `#rrggbb`; `state.textColor` / `state.highlightColor`
give the colors at the cursor. `AminotesToolbar` has both, with palettes you can
replace (`textColors:`, `highlightColors:`, defaults in `AminotesPalette`).

### On the web

The editor runs in an iframe. Everything above works the same, with these
differences:

- **Dialogs, sheets and routes** over the editor just work: while one is open
  the editor takes no clicks, so tapping outside a dialog closes it.
- **Widgets drawn over the editor** on the same screen (a button in the corner
  of the note box) don't get clicks by default: the iframe takes them. Wrap
  them in `PointerInterceptor` (package `pointer_interceptor`):

  ```dart
  PositionedDirectional(top: 4, end: 4,
    child: PointerInterceptor(child: IconButton(icon: Icon(Icons.open_in_full), onPressed: openFullScreen)));
  ```

  The package's own toolbar and bars already do this.
- **Moving between the box and full screen** reloads the editor's iframe (a
  browser reloads an iframe that moves). The text and the cursor come along;
  the undo history starts over.
- **Recordings** are `blob:` URLs, valid until the page reloads: upload them
  soon (`uploadPendingMedia`). Every voice note plays on every device (iPhone,
  Android, all browsers) with no server work: browsers that record AAC keep
  it; the others (Firefox, or Chrome when its AAC recorder fails) record Opus,
  which the package converts in the browser right after Done, to AAC
  (`audio/mp4`, `.m4a`) with the browser's own encoder, or to WAV
  (`audio/wav`, `.wav`, about 1.9 MB per minute) where there is none
  (Firefox). `upload.mimeType` and
  `upload.fileName` say which. If converting fails, the original is kept and
  `onError` reports it (`AminotesErrorKind.media`).

  No third-party audio encoder is involved: everything the package ships is
  MIT, BSD or Apache licensed (see the app's license page).
- **Photos** picked on the web are `blob:` URLs too.
- **Remote files**: voice notes play and images show even from servers
  without CORS headers.
- The toolbar scrolls with a mouse drag or the trackpad.
- Leaving the tab (switching tabs, minimizing) saves edits right away, like
  an app going to the background.

### Notes from a newer web app

Content this package doesn't know (a node, mark or attribute from a web
extension it doesn't have) is **kept and saved back unchanged**; unknown blocks
show as "Unsupported content, kept unchanged". If a note can't be loaded safely
at all, `state.loadFailed` is true: the note is read-only, `onChanged` never
fires and `getJson` returns it untouched. Show your own message for it.

The schema is versioned (`aminotesSchemaVersion`); the web team's guide is
[doc/web-team-schema.md](doc/web-team-schema.md).

### Old notes

`AminotesContent.text` (one paragraph per line) and `AminotesContent.html` are
converted by Tiptap when loaded. Save `getJson()` / `onChanged` from then on.

## API summary

| | |
|---|---|
| `AminotesController` | `load`, `getJson`, `onChanged` / `changes`, `onLinkTap`, `onError`, `flush`, `close`, `preload`, `contentHeight`, `saveRecordingWhenInterrupted`, `deleteSelection`, `playback` (`pauseVoiceNote`, `resumeVoiceNote`, `seekVoiceNote`, `stopVoiceNote`, `deleteVoiceNote`), `state`, `ready`, `focus`, `unfocus`, `insertText`, formatting commands (`toggleBold`, `toggleHeading(1-3)`, `toggleBulletList`, `toggleNumberedList`, `toggleChecklist`, `toggleQuote`, `setLink`, `indent`, `undo`, …), `execute` for anything else, `dispose` |
| `AminotesEditor` | `controller`, `theme`, `placeholder`, `autofocus`, `inactiveChild`, `autoHeight`, `minHeight`, `maxHeight`, `previewWhileLoading` |
| `AminotesState` | `ready`, `loadFailed`, `focused`, `canUndo`, `canRedo`, `canIndent`, `canOutdent`, `isActive('bold')`, `headingLevel`, `linkHref`, `textColor`, `highlightColor`, `selectedNode`, `stats` |
| `AminotesStats` | `words`, `characters`; `AminotesStats.of(json)` |
| `AminotesImageViewer` | `AminotesImageViewer.show(context, src:, alt:, onDelete:)` |
| `AminotesPlaybackBar` | Shown by the toolbar while a voice note plays |
| `AminotesToolbar` | Optional; `items` (`AminotesToolbarItem.compact`/`full`/custom), `trailing`, `textColors`, `highlightColors`; scrolls sideways; never closes the keyboard |
| `AminotesStrings` / `AminotesStringsScope` | English and Arabic texts; override any of them |
| `AminotesPreview` | `json`, `theme`, `maxBlocks`, `imageHeight`; `AminotesPreview.plainText(json)` |
| Tables | `insertTable`, `addRowBefore`/`After`, `addColumnBefore`/`After`, `deleteRow`, `deleteColumn`, `toggleHeaderRow`, `deleteTable` |
| Images | `controller.pickImage`, `insertImage`, `insertImageBytes`; `AminotesImageSource`; uploads via `uploadPendingMedia` |
| Voice notes | `controller.startVoiceNote` / `finishVoiceNote` / `cancelVoiceNote`, `recording`, `toolbarVisible`, `maxVoiceNoteDuration`, `uploadPendingMedia`, `replaceMediaSources`; `AminotesRecordingBar`; `AminotesMedia` (`sources`, `pendingUploads`, `replaceSources`, `unusedLocalFiles`) |
| `AminotesTheme` | Colors, `fontFamily`, `fontSize`, `lineHeight`, `padding` |

## Development

```
lib/            Dart: controller, editor widget, bridge, optional UI, media
tiptap/         The Tiptap side (npm): shared schema, editor page, build, tests
assets/editor/  Built editor page (generated by `npm run build`)
example/        Demo app: note box with full-screen mode
```

```bash
cd tiptap && npm install
npm run build       # rebuild assets/editor/ after changing tiptap/src or webview/
npm test            # JSON round trips, safety net, conversions
npm run normalize   # regenerate example/assets/sample_note.json

cd .. && flutter test
cd example && flutter run
```

### Tests

| Kind | Where | Run | What |
|---|---|---|---|
| Unit + widget | `test/` | `flutter test` | Controller, toolbar, preview, media, bars; the editor page is faked |
| JS | `tiptap/scripts/` | `cd tiptap && npm test` | Saved JSON, safety net, conversions, old-WebView compatibility |
| Integration | `example/integration_test/` | see below | The real editor page in a real WebView or Chrome |

```bash
cd example
tool/integration_android.sh [device]   # Android device/emulator; grants the microphone
flutter test integration_test -d <id>  # iOS (allow the microphone when asked)
tool/integration_web.sh                # Chrome, headless, fake microphone
```

The integration tests load notes (JSON, text, HTML, newer-web content,
invalid), run formatting/tables/links, save (typing pause, flush, close, app
going to the background), move between box and full screen, size the box to
the note, check dialogs over the editor (web), Arabic and dark mode, show an
image, play a voice note to the end and record one. System screens (permission
prompts, gallery, camera, calls) stay on
[doc/device-test-checklist.md](doc/device-test-checklist.md).

`tiptap/src/extensions.js` is the schema shared with the web app: keep it in
sync with the web team's extension list.
