# aminotes: developer guide

aminotes puts a rich note editor in your Flutter app: bold, lists, checklists,
colors, links, images, tables and voice notes, in English and Arabic. Notes are
saved as **Tiptap JSON**, the same format as the web app, and everything works
**offline**. The package draws no box, card or screen around the note: the
design is yours.

It runs on **Android (7+), iOS and the web**, with Flutter 3.47 or newer.

**Contents**

1. [Install](#1-install)
2. [Your first note box (5 minutes)](#2-your-first-note-box-5-minutes)
3. [Loading and saving notes](#3-loading-and-saving-notes)
4. [The toolbar: choosing your buttons](#4-the-toolbar-choosing-your-buttons)
5. [Designing the note](#5-designing-the-note)
6. [The box: size, scrolling, full screen](#6-the-box-size-scrolling-full-screen)
7. [Voice notes](#7-voice-notes)
8. [Images](#8-images)
9. [Links, tables, word count](#9-links-tables-word-count)
10. [Uploading recordings and photos](#10-uploading-recordings-and-photos)
11. [Lists of notes](#11-lists-of-notes)
12. [Languages](#12-languages)
13. [Errors](#13-errors)
14. [On the web](#14-on-the-web)
15. [Notes from the web app](#15-notes-from-the-web-app)
16. [Troubleshooting](#16-troubleshooting)
17. [Cheat sheet](#17-cheat-sheet)

> **Try before you code:** run the example app (`cd example && flutter run`)
> and open the **Playground** (palette icon). Pick a design and the toolbar
> buttons, see the result live, then copy the generated Dart code.

---

## 1. Install

```yaml
# pubspec.yaml
dependencies:
  aminotes:
    path: ../aminotes        # or a git dependency
```

**Android** (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>      <!-- images/voice notes by URL -->
<uses-permission android:name="android.permission.RECORD_AUDIO"/>  <!-- voice notes -->
```

No permission is needed for photos: Android's own photo picker is used.

**iOS** (`ios/Runner/Info.plist`), each with a sentence the user will read:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Record voice notes inside your notes.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Add photos to your notes.</string>
<key>NSCameraUsageDescription</key>
<string>Take photos for your notes.</string>
```

**Web:** nothing to set up.

Everything is imported from one file:

```dart
import 'package:aminotes/aminotes.dart';
```

---

## 2. Your first note box (5 minutes)

Three pieces work together:

| Piece | What it is |
|---|---|
| `AminotesController` | **The note.** Loads it, edits it, tells you when it changed. One per note. |
| `AminotesEditor` | **Where the note is shown.** Put it anywhere, any size. |
| `AminotesToolbar` | **Optional ready-made buttons.** Or build your own on the controller. |

A complete screen: a note box, the toolbar above the keyboard while editing,
and saving.

```dart
import 'package:aminotes/aminotes.dart';
import 'package:flutter/material.dart';

class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.savedNote});

  /// The note's Tiptap JSON from your database (null for a new note).
  final Map<String, dynamic>? savedNote;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  // 1. One controller per note.
  late final _controller = AminotesController(
    initialContent: widget.savedNote == null ? AminotesContent.empty : AminotesContent.json(widget.savedNote!),
    // 2. Save whenever the user pauses typing.
    onChanged: (json) => myDatabase.saveNote(json),
  );

  @override
  void dispose() {
    _controller.dispose(); // 5. Also saves the last edits.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Note')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 3. Your box, your design. The editor fills it.
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AminotesEditor(
                    controller: _controller,
                    placeholder: 'Write a note…',
                    autoHeight: true, // grows with the note…
                    minHeight: 120,
                    maxHeight: 320,  // …then scrolls inside
                  ),
                ),
              ],
            ),
          ),
          // 4. The toolbar, only while editing. The Scaffold shrinks the body
          //    when the keyboard opens, so this sits right above it.
          ValueListenableBuilder(
            valueListenable: _controller.toolbarVisible,
            builder: (context, visible, _) => visible
                ? SafeArea(
                    top: false,
                    child: AminotesToolbar(controller: _controller, items: AminotesToolbarItem.compact),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
```

That's a working note editor. Use `controller.toolbarVisible` rather than
"is the note focused": it also stays true while recording or playing a voice
note (the microphone permission dialog takes focus away, but the recording bar
must stay).

---

## 3. Loading and saving notes

### Loading

```dart
AminotesController(initialContent: AminotesContent.json(savedJson));   // Tiptap JSON (normal case)
AminotesController(initialContent: AminotesContent.html('<p>Hi</p>')); // old notes stored as HTML
AminotesController(initialContent: AminotesContent.text('Line 1\nLine 2')); // old plain-text notes
AminotesController(); // empty note

await controller.load(AminotesContent.json(otherNote)); // replace the note later
```

HTML and text are converted the first time they're shown; from then on save
the JSON you get back.

### Saving

| You want | Use |
|---|---|
| Save as the user types (recommended) | `onChanged: (json) => save(json)`. Fires once typing pauses (`changeDelay`, 400 ms by default) and when the editor loses focus. Also available as a stream: `controller.changes`. |
| The note right now | `final json = await controller.getJson();` |
| Send pending edits immediately | `await controller.flush();` (they arrive through `onChanged`) |
| Close the note and get the final JSON | `final json = await controller.close();` (also disposes the controller) |

**You don't lose edits:**

- `dispose()` sends the last edits to `onChanged` (shortly after), so check
  `mounted` there before calling `setState`.
- When the app goes to the background (home button, a call), pending edits are
  saved immediately, and a recording in progress is inserted
  (`saveRecordingWhenInterrupted: false` throws it away instead).

### What a note looks like

```json
{"type": "doc", "content": [
  {"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "Shopping"}]},
  {"type": "paragraph", "content": [
    {"type": "text", "text": "Buy "},
    {"type": "text", "text": "milk", "marks": [{"type": "bold"}]}
  ]}
]}
```

Store it as it is (e.g. as a JSON column). The package reads and writes exactly
what the web app does.

---

## 4. The toolbar: choosing your buttons

### Ready-made sets

```dart
AminotesToolbar(controller: controller, items: AminotesToolbarItem.compact) // small box
AminotesToolbar(controller: controller, items: AminotesToolbarItem.full)    // full screen (default)
```

- **compact**: bold, italic, underline, text color, highlight | bullet list,
  checklist, numbered list | voice note, image.
- **full**: undo, redo | bold, italic, underline, strikethrough, text color,
  highlight, link | H1, H2, H3 | bullet, numbered, checklist, indent, outdent |
  quote, inline code, code block, divider, table | voice note, image.

### Your own list, in your order

```dart
AminotesToolbar(
  controller: controller,
  items: const [
    AminotesToolbarItem.bold,
    AminotesToolbarItem.italic,
    AminotesToolbarItem.separator, // a thin line between groups
    AminotesToolbarItem.checklist,
    AminotesToolbarItem.image,
  ],
)
```

### Every button

| Item | What it does |
|---|---|
| `undo`, `redo` | Undo / redo (greyed out when there's nothing to undo) |
| `bold`, `italic`, `underline`, `strikethrough` | Text style; highlighted when active at the cursor |
| `textColor`, `highlight` | Opens a row of color swatches above the toolbar |
| `link` | Add, edit or remove a link (asks for the URL) |
| `heading1`, `heading2`, `heading3` | Headings; tap again to go back to normal text |
| `bulletList`, `numberedList`, `checklist` | Lists; checklists have tappable checkboxes |
| `indent`, `outdent` | Nest a list item deeper / move it back |
| `quote`, `inlineCode`, `codeBlock`, `divider` | Quote block, `code`, code block, horizontal line |
| `table` | Inserts a table. While the cursor is in a table, row and column buttons appear at the start of the toolbar |
| `voiceNote` | Records a voice note; the toolbar becomes the recording bar |
| `image` | Gallery or camera. A tapped image gets View, align left/center/right and Delete buttons |
| `separator` | A thin divider between groups |

The toolbar is one row that **scrolls sideways** when the buttons don't fit (by
finger, mouse drag or trackpad).

### Your own buttons, icons and colors

```dart
AminotesToolbar(
  controller: controller,
  items: [
    ...AminotesToolbarItem.compact,
    AminotesToolbarItem.custom(
      icon: const Icon(Icons.today),
      tooltip: 'Insert date',
      onPressed: (c) => c.insertText('19 Oct 2026'),
      isActive: (state) => false, // optional: highlight it like Bold
    ),
  ],
  icons: {AminotesToolbarItem.bold: Icons.format_bold_outlined}, // replace built-in icons
  textColors: const [Colors.red, Colors.blue],                   // your palettes
  highlightColors: const [Colors.yellow],
  trailing: IconButton(icon: const Icon(Icons.open_in_full), onPressed: openFullScreen), // pinned at the end
)
```

### Or build your own toolbar

Every button is a controller method, and `controller.state` tells you what's
active at the cursor:

```dart
ValueListenableBuilder<AminotesState>(
  valueListenable: controller.state,
  builder: (context, state, _) => Row(children: [
    IconButton(
      icon: const Icon(Icons.format_bold),
      isSelected: state.isActive('bold'),
      onPressed: controller.toggleBold,
    ),
    IconButton(
      icon: const Icon(Icons.undo),
      onPressed: state.canUndo ? controller.undo : null,
    ),
  ]),
)
```

Wrap your toolbar in `ExcludeFocus` so tapping it doesn't close the keyboard.
The [cheat sheet](#17-cheat-sheet) lists every method and state value.

---

## 5. Designing the note

There are two layers:

1. **The box around the note is yours.** The package draws nothing around the
   editor and its background is transparent. Wrap `AminotesEditor` in any
   widget: a card, a sticky note, a chat bubble, lined paper, rotated or
   animated.
2. **The note's text** is styled with `AminotesTheme`:

```dart
AminotesEditor(
  controller: controller,
  theme: const AminotesTheme(
    textColor: Color(0xFF1C1B1F),
    accentColor: Color(0xFF3F51B5), // links, checkboxes, quote bar, cursor
    fontSize: 17,
    lineHeight: 1.5,
    padding: EdgeInsets.all(20),
  ),
)
```

| Setting | Changes |
|---|---|
| `textColor`, `mutedTextColor` | Text; quotes and placeholder |
| `accentColor` | Links, checkboxes, quote bar, cursor, selection outline |
| `accentContainerColor`, `onAccentContainerColor` | The voice note pill and its text |
| `backgroundColor` | Behind the text (transparent by default: your box shows) |
| `surfaceColor`, `borderColor`, `codeBackgroundColor`, `selectionColor` | Table headers, borders, code, selected text |
| `fontFamily`, `fontSize`, `lineHeight` | The font |
| `padding` | Space between the box's edge and the text (`EdgeInsetsDirectional` follows Arabic/English) |
| `brightness` | Light or dark |
| `fonts` | Fonts bundled in your app (below) |
| `css` | Anything else (below) |

Anything you leave out comes from your app's `Theme`, **including dark mode**.

### Your brand font

```dart
AminotesTheme(
  fontFamily: 'Poppins',
  fonts: [
    AminotesFont('Poppins', 'assets/fonts/Poppins-Regular.ttf'),
    AminotesFont('Poppins', 'assets/fonts/Poppins-Bold.ttf', weight: FontWeight.w700),
  ],
)
```

Declare the files in your pubspec under `fonts:`, using the same family name.

### Anything else: CSS

The note is drawn by a web page, so CSS can change any detail:

```dart
AminotesTheme(css: '''
  .ProseMirror h1 { font-size: 2.4em; }                       /* bigger headings */
  .ProseMirror > * + * { margin-top: 0.25em; }                /* tighter spacing */
  .ProseMirror input[type='checkbox'] { border-radius: 50%; } /* round checkboxes */
''')
```

| Part | Selector |
|---|---|
| Paragraphs, headings | `.ProseMirror p`, `.ProseMirror h1` … `h6` |
| Space between blocks | `.ProseMirror > * + *` |
| Links, highlight | `.ProseMirror a`, `.ProseMirror mark` |
| Code | `.ProseMirror code`, `.ProseMirror pre` |
| Lists, checklists | `ul`, `ol`, `li`, `ul[data-type='taskList']`, `input[type='checkbox']` |
| Quote, divider | `.ProseMirror blockquote`, `.ProseMirror hr` |
| Images, tables | `.ProseMirror img`, `table`, `th`, `td` |
| Voice note pill | `.voice-note button`, `.voice-note-label` |
| Placeholder | `.ProseMirror p.is-editor-empty:first-child::before` |

The theme's colors are CSS variables you can reuse: `var(--text)`,
`var(--muted)`, `var(--primary)` (accent), `var(--border)`, `var(--surface)`,
`var(--code-bg)`.

> Custom CSS styles the editor only. `AminotesPreview` (for lists of notes)
> follows the theme's colors, font and size.

---

## 6. The box: size, scrolling, full screen

### Size

| You want | Use |
|---|---|
| A fixed size | Give `AminotesEditor` a size (`SizedBox`, `Expanded`, your container's height) |
| A box that grows with the note | `autoHeight: true, minHeight: 120, maxHeight: 320` |

Longer notes **scroll inside the box**, even when the box sits in a scrolling
screen. While the note is taller than its box, or being edited, drags on it
scroll the note; otherwise they scroll your screen.

### Full screen (the same note, bigger)

Show the **same controller** in a second editor on a new screen. Text, cursor
and undo history move with it, and come back when the screen closes:

```dart
void openFullScreen() {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(),
      body: Column(children: [
        Expanded(child: AminotesEditor(controller: _controller, autofocus: true)),
        AminotesToolbar(controller: _controller), // all buttons
      ]),
    ),
  ));
}
```

While the full-screen editor shows the note, the small box shows its
`inactiveChild` (e.g. `Center(child: Text('Editing in full screen'))`).

### Fast opening

- The note shows instantly as a preview while the editor loads (a fraction of
  a second); turn it off with `previewWhileLoading: false`.
- `controller.preload()` (e.g. in `initState`) starts the editor before it's
  on screen.

---

## 7. Voice notes

The `voiceNote` toolbar button does everything:

1. It asks for the microphone the first time.
2. It records (AAC `.m4a`, up to 10 minutes: `maxVoiceNoteDuration`).
3. Done inserts the voice note **at the cursor, inside the sentence**.

While recording, the toolbar becomes a bar with a timer, the input level,
Cancel and Done.

**Playing:** tapping a voice note in the note plays it; the toolbar becomes a
player with play/pause, a slider to seek, Delete and Close.

From your own buttons:

```dart
final result = await controller.startVoiceNote(); // started / permissionDenied / failed
await controller.finishVoiceNote();               // insert it
await controller.cancelVoiceNote();               // throw it away

controller.recording // ValueListenable: the recording in progress (elapsed, levels)
controller.playback  // ValueListenable: what's playing (position, duration, playing)
await controller.seekVoiceNote(const Duration(seconds: 30));
```

`AminotesRecordingBar` and `AminotesPlaybackBar` are the ready-made bars if you
build your own toolbar.

Recordings are stored on the phone, offline, until you upload them
([section 10](#10-uploading-recordings-and-photos)). Every voice note plays on
iPhone, Android and every browser.

---

## 8. Images

**Adding:** the `image` button offers the gallery or the camera. Photos are
scaled to at most 2048 px, stored offline and inserted at the cursor. From your
own code:

```dart
await controller.pickImage(AminotesImageSource.camera); // or .gallery
await controller.insertImage('https://example.com/photo.jpg', alt: 'A photo');
await controller.insertImageBytes(bytes, extension: 'png'); // Android/iOS
```

**Tapping an image** selects it; the toolbar then offers:

| Button | Does |
|---|---|
| View | Full screen, pinch to zoom (`AminotesImageViewer`) |
| Align left / center / right | Places it on its line (tap the active one again to go back to the text direction) |
| Delete | Removes it (undo brings it back) |

**Resizing:** a tapped image shows a round handle on each corner. Drag one with
a finger or the mouse; the proportions are kept. The size is saved with the
note.

From code: `controller.setImageAlignment(AminotesImageAlignment.center)`,
`controller.deleteSelection()`, and `controller.state.value.selectedNode` (the
tapped image: `src`, `alt`, `align`).

---

## 9. Links, tables, word count

**Links:** the `link` button adds them. Tapping a link in the note never opens
anything by itself. You decide:

```dart
AminotesController(
  onLinkTap: (url) => launchUrl(Uri.parse(url)), // package url_launcher
)
```

Unsafe links (`javascript:` …) are never reported.

**Tables:** the `table` button inserts a 3×3 table with a header row. While the
cursor is in it, the toolbar starts with: add row, add column, delete row,
delete column, header row on/off, delete table. From code:
`controller.insertTable(rows: 2, columns: 4)`, `addRowAfter()`,
`deleteColumn()`, …

**Word count:**

```dart
controller.state.value.stats.words      // live, while editing
controller.state.value.stats.characters
AminotesStats.of(savedJson).words       // any saved note, no editor needed
```

---

## 10. Uploading recordings and photos

New recordings and photos live **on the phone** (`local:…` in the note) so the
app works offline. When you're online, upload them:

```dart
final json = await controller.uploadPendingMedia((upload) async {
  // upload.read()    → the file's bytes
  // upload.fileName  → e.g. 1739….m4a
  // upload.mimeType  → audio/mp4, image/jpeg, …
  // upload.kind      → 'voiceNote' or 'image'
  return await myApi.uploadFile(await upload.read(), upload.fileName); // your https URL
});
await myDatabase.saveNote(json); // the note now points at the URLs
```

- A file that fails to upload stays local and is retried next time.
- For notes that aren't open: `AminotesMedia.pendingUploads(json)` and
  `AminotesMedia.replaceSources(json, {old: new})`.
- **Cleaning up:** `AminotesMedia.unusedLocalFiles(allNotes)` lists files no
  note uses any more (e.g. a deleted voice note). Delete them once those notes
  are saved everywhere.

On the web, recordings and photos are temporary `blob:` URLs: upload them
before the page is reloaded.

---

## 11. Lists of notes

Each `AminotesEditor` is a small web page: too heavy for a list of 50 notes.
For lists, use `AminotesPreview`, which draws a note with plain Flutter widgets:

```dart
ListView.builder(
  itemCount: notes.length,
  itemBuilder: (context, i) => Card(
    child: InkWell(
      onTap: () => openNote(notes[i]), // open the real editor
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AminotesPreview(json: notes[i], maxBlocks: 4, imageHeight: 100),
      ),
    ),
  ),
)
```

`AminotesPreview.plainText(json)` gives the note's text (for search or a
one-line summary).

---

## 12. Languages

English and Arabic are built in and follow the app's locale. Arabic paragraphs
read right to left, English ones left to right, even inside the same note.

Change any text (tooltips, dialogs):

```dart
AminotesStringsScope(
  strings: AminotesStrings.english.copyWith(bold: 'Strong', recordVoiceNote: 'Dictate'),
  child: myNoteScreen,
)
```

---

## 13. Errors

The package recovers on its own and tells you through `onError`:

```dart
AminotesController(
  onError: (error) {
    log('${error.kind}: ${error.message}');
    if (error.kind == AminotesErrorKind.webView) {
      showSnackBar('Please update "Android System WebView" from the Play Store.');
    }
  },
)
```

| Kind | Means |
|---|---|
| `load` | The note can't be edited safely. It's shown **read-only** and never changed (`state.loadFailed`) |
| `recording` | A recording couldn't start or was lost |
| `media` | A voice note couldn't play, a file couldn't be read, or a web recording couldn't be converted |
| `editor` | Something inside the editor failed |
| `webView` | The phone's WebView is too old (older than Chrome 80): the note stays visible as a preview |

---

## 14. On the web

Everything above works in the browser too. A few differences:

- **Buttons you draw over the editor** (e.g. a full-screen button in the
  corner of the box) need `PointerInterceptor` (package `pointer_interceptor`),
  or the browser sends the click to the editor:

  ```dart
  PositionedDirectional(
    top: 4, end: 4,
    child: PointerInterceptor(child: IconButton(icon: const Icon(Icons.open_in_full), onPressed: openFullScreen)),
  )
  ```

  Dialogs, sheets and new screens need nothing.
- Moving between the box and full screen keeps the text and the cursor, but the
  undo history starts over.
- Recordings and photos are `blob:` URLs until uploaded.
- Recordings are converted in the browser when needed, so they play on every
  device.

---

## 15. Notes from the web app

- **Same format:** a note written on the web opens on the phone and the other
  way round, as long as both use the same Tiptap setup
  ([web-team-schema.md](web-team-schema.md)).
- **Something the package doesn't know** (e.g. a newer web feature) shows as a
  grey "unsupported content" box and is **kept unchanged** when the note is
  saved.
- **A note that would break the editor** opens read-only and is never
  modified (`AminotesErrorKind.load`).
- `aminotesSchemaVersion` tells you which version of the format this package
  writes; you can store it next to notes.

---

## 16. Troubleshooting

| Problem | Fix |
|---|---|
| The toolbar is hidden by the keyboard | Put it at the bottom of a `Scaffold` body (`Column` + `Expanded`), with `resizeToAvoidBottomInset` left on |
| The toolbar disappears while recording | Show it with `controller.toolbarVisible`, not `state.focused` |
| Tapping the toolbar closes the keyboard | Use `AminotesToolbar` (it handles this), or wrap your own in `ExcludeFocus` |
| `setState() called after dispose()` in `onChanged` | The last edits arrive after `dispose()`: check `mounted` |
| My brand font doesn't show | Add it with `AminotesTheme(fonts: [...])`. `fontFamily` alone only finds fonts installed on the phone |
| A button over the editor doesn't react (web) | Wrap it in `PointerInterceptor` |
| Recording does nothing | Add the microphone permission (Android manifest, iOS Info.plist); handle `AminotesRecordResult.permissionDenied` |
| Images or voice notes don't show after reinstalling | `local:` files live on the device: upload them (`uploadPendingMedia`) |
| The editor stays blank on an old Android phone | Its WebView is too old: you get `AminotesErrorKind.webView` |

---

## 17. Cheat sheet

**`AminotesController`**

| Group | Members |
|---|---|
| Setup | `initialContent`, `onChanged`, `onLinkTap`, `onError`, `changeDelay`, `maxVoiceNoteDuration`, `saveRecordingWhenInterrupted` |
| Note | `load`, `getJson`, `flush`, `close`, `dispose`, `preload`, `changes`, `ready` |
| State | `state` (`AminotesState`), `toolbarVisible`, `contentHeight` |
| Text | `toggleBold`, `toggleItalic`, `toggleUnderline`, `toggleStrike`, `toggleCode`, `setTextColor`, `setHighlightColor`, `insertText` |
| Blocks | `toggleHeading(1–3)`, `setParagraph`, `toggleBulletList`, `toggleNumberedList`, `toggleChecklist`, `indent`, `outdent`, `toggleQuote`, `toggleCodeBlock`, `insertDivider` |
| Links | `setLink`, `removeLink` |
| Tables | `insertTable`, `addRowBefore`/`After`, `addColumnBefore`/`After`, `deleteRow`, `deleteColumn`, `toggleHeaderRow`, `deleteTable` |
| Images | `pickImage`, `insertImage`, `insertImageBytes`, `setImageAlignment`, `deleteSelection` |
| Voice notes | `startVoiceNote`, `finishVoiceNote`, `cancelVoiceNote`, `recording`, `playback`, `pauseVoiceNote`, `resumeVoiceNote`, `seekVoiceNote`, `stopVoiceNote`, `deleteVoiceNote` |
| Uploads | `uploadPendingMedia`, `replaceMediaSources` |
| Other | `undo`, `redo`, `focus`, `unfocus`, `execute` (any editor command by name) |

**`AminotesState`:** `ready`, `loadFailed`, `focused`, `canUndo`, `canRedo`,
`canIndent`, `canOutdent`, `isActive('bold')`, `headingLevel`, `linkHref`,
`textColor`, `highlightColor`, `selectedNode`, `stats`.

**Widgets:** `AminotesEditor`, `AminotesToolbar`, `AminotesPreview`,
`AminotesImageViewer`, `AminotesRecordingBar`, `AminotesPlaybackBar`,
`AminotesStringsScope`.

**Helpers:** `AminotesContent`, `AminotesTheme`, `AminotesFont`,
`AminotesToolbarItem`, `AminotesPalette`, `AminotesMedia`, `AminotesStats`,
`AminotesStrings`, `aminotesSchemaVersion`.

The README has more detail on each part, and the example app shows all of it
working.
