## 0.15.1

- No LGPL code any more: the LAME MP3 encoder (LGPL-3.0) is removed. Web
  recordings a browser can only make as Opus (Firefox) are now converted to
  WAV (16 kHz mono, about 1.9 MB per minute) instead of MP3; it plays on
  every device and needs no third-party encoder. Browsers with an AAC encoder
  (Chrome, Edge, Safari) still produce AAC. Everything the package ships is
  now MIT, BSD or Apache licensed.
- `assets/web_audio/lame.js` is gone, so it's no longer inside Android and
  iOS app bundles either.
- Uploads of WAV recordings get `audio/wav` and a `.wav` file name.

## 0.15.0

Schema version 3.

- Images can be aligned left, center or right: with a tapped image the
  toolbar shows three align buttons (tap the active one to go back to the text
  direction); `controller.setImageAlignment(...)`; `state.selectedNode.align`.
  Saved as the image's `align` attribute (`left`/`center`/`right`, null =
  text direction). Left and right stay put in Arabic notes. `AminotesPreview`
  follows it.
- **Web team:** add `AlignedImage` (doc/web-team-schema.md), or the web editor
  drops `align` when it saves a note.
- Images now always save an `align` field (null when not set), like `width`
  and `height`.
- New strings: alignImageLeft, alignImageCenter, alignImageRight (English and
  Arabic).

## 0.14.0

- Images can be resized: tapping one shows a handle on each corner, and
  dragging one (finger or mouse) resizes it, keeping its proportions. The
  size is saved as Tiptap's standard `width`/`height` image attributes, so
  the web app shows it too. A resized image still fits narrower screens, and
  `AminotesPreview` shows it at that size. (Tiptap's resize helper only
  finishes a resize on mouse release; the package also finishes it when the
  finger lifts, or resizes on phones would never be saved.)
- Fixed: a note box inside a scrolling screen (e.g. a `ListView`) couldn't be
  scrolled on Android; the screen took the drags, and when the note won them
  the Android WebView ignored the replayed touches. The note now takes each
  touch as it lands while it overflows its box or is being edited; otherwise
  drags scroll the screen as before.
- Integration tests: a note scrolls inside its box in a scrolling list; an
  image is resized by touch and its size survives reopening the note.

## 0.13.0

Design: anything the theme settings don't cover can now be changed.

- `AminotesTheme(css: ...)`: extra CSS for the note's content, applied after
  the package's own (heading sizes, spacing, checkbox shape, voice-note
  pill…). The README lists the elements to target and the CSS variables.
- `AminotesTheme(fonts: [AminotesFont(family, asset, weight:, style:)])`: fonts
  bundled in the app now work in the editor (they used to need to be
  installed on the device). A missing font file is reported through
  `onError`.
- Example app: a **Playground** screen with ready-made designs (plain, card,
  sticky note with a handwriting font and round checkboxes, Notion style,
  dark), live settings for the box, text and toolbar buttons, and the Dart
  code to copy. The example ships the Caveat font (SIL Open Font License).
- Integration test: custom CSS and an app font apply in the real page.

## 0.12.0

Every voice note now plays on every device (iPhone, Android, all browsers),
with nothing to set up on a server.

- Web: recordings that a browser can only make as Opus (Firefox, or Chrome
  when its AAC recorder fails), which iPhones can't play, are converted in the
  browser right after Done: to AAC (`.m4a`) with the browser's own encoder
  (WebCodecs), or to MP3 where there is none. Recordings that are already AAC
  are left as they are. If converting fails, the original is kept and
  `onError` reports it.
- New web-only assets: `assets/web_audio/audio.js` (the converter, loaded on
  first use) and `lame.js` (LAME MP3 encoder, LGPL-3.0, shipped unmodified as
  its own file, loaded only when needed). Their licenses are in NOTICES.txt
  and on the app's license page.
- Uploads of MP3 recordings get `audio/mpeg` and a `.mp3` file name.
- Integration tests: the conversion to AAC and to MP3 decodes back to the
  same length, and a real web recording ends up in one of the two.

## 0.11.1

- The licenses of the JavaScript bundled in the editor (Tiptap, ProseMirror
  and their dependencies: 38 packages, all MIT) now ship in
  `assets/editor/NOTICES.txt` and appear on the app's license page.
- Web: moving between the box and full screen keeps the cursor (the iframe
  reloads; the text was already kept). Undo history still starts over there.
- Links with an unsafe protocol (`javascript:`, …) are never reported to
  `onLinkTap` (they used to arrive as an empty string).
- Doc comments for the public API; the example app has a real README.
- `docs/` is now `doc/` (pub layout convention).

## 0.11.0

Integration tests (`example/integration_test/`): the real editor page on
Android and in Chrome, 17 tests; run scripts in `example/tool/`. They found:

- The first state from the page (word count and the rest) could arrive just
  before the controller counted as ready and was dropped: the word count
  showed 0 until the first edit.
- Web: moving the editor between the box and full screen reloads the iframe;
  calls made meanwhile (`getJson`, commands) went to the old page and were
  lost (`getJson` timed out). The controller now takes the latest text from
  the page before the move and makes calls wait for the reloaded page.

For tests: `controller.debugEvaluate(js)` runs JavaScript in the page and
returns the result; `controller.debugPageLoads` counts page loads.

## 0.10.2

- Older Android WebViews (Chrome 80–96, e.g. Android 7 phones not updated in a
  while) couldn't run the editor: Tiptap uses `findLast` and a few other recent
  built-ins. A small compatibility script (`compat.js`) adds them.
- A WebView too old even for that now reports `AminotesErrorKind.webView`
  through `onError` instead of leaving a blank editor.
- docs/device-test-checklist.md for testing on real devices.

## 0.10.1

- Web: tapping outside the link dialog (or the image sheet, or any dialog
  over the editor) didn't close it, so the dialog was hard to leave. While a
  dialog, sheet or route covers the editor, the editor's iframe now takes no
  clicks; the full-screen shield around the link dialog is gone.

## 0.10.0

M8: web checks in Chrome. Everything works on the web; fixed along the way:

- The editor iframe reloaded (losing focus and the toolbar) after the first
  save of a note loaded as text or HTML: the widgets around it changed shape.
- Clicks on widgets over the editor went to the iframe: the toolbar, bars,
  dialogs and sheets now use `PointerInterceptor`; host apps should wrap their
  own (see README, "On the web").
- Voice notes from servers without CORS headers didn't play: the web now plays
  through a plain `<audio>` element.
- Images from servers without CORS headers didn't show in the preview and the
  viewer: `AminotesMedia.networkImage` falls back to an `<img>`.
- Recording on the web could silently record nothing when the browser's AAC
  encoder failed: it now switches to Opus (`audio/webm`). A recording that
  stops by itself ends and is reported through `onError` ("Nothing was
  recorded" when Done gives no audio).
- Web uploads get their real `mimeType` and a file name with an extension.
- The toolbar can be dragged with a mouse.
- The image viewer shows a spinner while the image downloads.

## 0.9.0

The last gaps before 1.0.

- Images: tapping one selects it (`state.selectedNode`); the toolbar offers
  View (`AminotesImageViewer`: full screen, pinch to zoom, Delete) and Delete
  (`controller.deleteSelection()`). `AminotesMedia.imageProvider(src)`.
- Voice notes: `controller.playback` (playing, position, duration),
  `pauseVoiceNote`, `resumeVoiceNote`, `seekVoiceNote`, `stopVoiceNote`,
  `deleteVoiceNote`; `AminotesPlaybackBar`, shown by the toolbar while one
  plays (`toolbarVisible` includes playback). The pill shows the elapsed time.
  The length shown is corrected from the file once it loads.
- Word count: live `state.stats` (`words`, `characters`) and
  `AminotesStats.of(json)` for saved notes; both count the same way.
- New strings: viewImage, deleteImage, playVoiceNote, pauseVoiceNote,
  deleteVoiceNote, closePlayback (English and Arabic).

## 0.8.0

Robustness before 1.0.

- `controller.flush()` and `await controller.close()` (final JSON). `dispose()`
  flushes, and late edits still reach `onChanged`.
- Going to the background flushes edits and saves a recording in progress
  (`saveRecordingWhenInterrupted: false` discards it).
- `onLinkTap(url)`: links in the note are reported, never opened by the page.
- `onError(AminotesError)` with `kind` (load, recording, media, editor)
  instead of debug prints.
- `AminotesEditor(autoHeight:, minHeight:, maxHeight:)`: a box that grows with
  the note; `controller.contentHeight`.
- The note shows as a preview until the editor page is ready
  (`previewWhileLoading`); `controller.preload()` starts the page early.
- Fix: tapping a voice note or image inside a link no longer opens the link.

## 0.7.0

M7: preview widget.

- `AminotesPreview`: draws a note with plain Flutter widgets (no WebView) for
  lists of many notes: headings, marks, colors, links, lists, checklists,
  quotes, code, dividers, tables, images (local and remote), voice notes,
  unsupported content, Arabic/English direction per paragraph. Read-only and
  lets taps through. `maxBlocks`, `imageHeight`, `theme`.
- `AminotesPreview.plainText(json)` for summaries and search.
- Example app: a notes list of previews that open in the editor.

## 0.6.1

- `AminotesToolbarItem.custom(icon:, tooltip:, onPressed:, isActive:)`: host
  app buttons anywhere in the toolbar.
- `AminotesToolbar(icons:)`: replace any built-in icon (headings too).
- `controller.insertText(text)`.
- `AminotesToolbarItem` is now a class instead of an enum; existing uses
  (`AminotesToolbarItem.bold`, the presets, lists) are unchanged.

## 0.6.0

M6: tables.

- `insertTable(rows:, columns:, withHeaderRow:)`, `addRowBefore/After`,
  `addColumnBefore/After`, `deleteRow`, `deleteColumn`, `toggleHeaderRow`,
  `deleteTable`.
- `AminotesToolbarItem.table` (full preset): inserts a 3×3 table; while the
  cursor is in a table, row/column/header/delete buttons lead the toolbar,
  which scrolls back to its start so they're visible.
- Wide tables scroll sideways inside the note.
- Texts in English and Arabic.

## 0.5.0

M5: images.

- Pick from the gallery or camera (toolbar image button, or
  `controller.pickImage`); photos are scaled to 2048 px, stored offline as
  `local:images/…`, inserted at the cursor and shown immediately (Flutter
  serves the file to the page for display; the note keeps `local:`).
- `insertImage(url)`, `insertImageBytes(bytes)` for host-provided images.
- Images upload with voice notes through `uploadPendingMedia`; `AminotesMedia`
  helpers include them.
- Images that can't load show a grey placeholder instead of a broken icon.
- Fixes: the Gallery/Camera sheet no longer opens behind the keyboard, and
  still opens when closing the keyboard hides the toolbar.
- `AminotesMedia.store` is public, to choose where media is kept.
- Host apps on iOS need `NSPhotoLibraryUsageDescription` and
  `NSCameraUsageDescription`.

## 0.4.0

M4: voice notes.

- Record from the toolbar's mic (or `startVoiceNote`/`finishVoiceNote`/
  `cancelVoiceNote`); the voice note is inserted at the cursor, inside the
  sentence. AAC `.m4a`, saved offline; stops at `maxVoiceNoteDuration`.
- `AminotesRecordingBar` (timer, level, Cancel, Done), shown by the toolbar
  while recording; `controller.recording` for custom UIs.
- `controller.toolbarVisible`: stays true while recording, even when the
  microphone permission dialog takes focus.
- Uploads: `uploadPendingMedia(uploader)` uploads `local:` files and swaps in
  their URLs (not an undo step); failures stay local. `AminotesMedia` helpers
  for plain JSON: `sources`, `pendingUploads`, `replaceSources`,
  `unusedLocalFiles`.
- Fix: finishing a recording after the permission dialog no longer splits the
  line instead of inserting the voice note.
- Host apps need `RECORD_AUDIO` (Android) and `NSMicrophoneUsageDescription` (iOS).

## 0.3.0

M3: ready-made UI.

- `AminotesToolbar(items:)` with `AminotesToolbarItem.compact` (small box) and
  `.full` (full screen) presets, or any custom list; `trailing:` for a pinned
  button such as "full screen". Replaces `showUndoRedo` (use `items`).
- English and Arabic for every text the package shows, picked from the app's
  locale: toolbar tooltips, link dialog, color names, and labels inside the
  note. Override any of them with `AminotesStringsScope`.
- URL field and hint stay left-to-right in Arabic.

## 0.2.0

M2: colors, safety net, schema version.

- Text color and highlight (Tiptap Color/TextStyle and Highlight, multicolor):
  `setTextColor`, `setHighlightColor`, `state.textColor`/`highlightColor`, and
  palettes in `AminotesToolbar` that open above it without closing the keyboard.
- Safety net: unknown nodes, marks and attributes from the web are kept and
  saved back unchanged; notes that still can't load safely open read-only
  (`state.loadFailed`) and are never overwritten.
- `aminotesSchemaVersion` (2), checked against the JavaScript schema in tests.
- docs/web-team-schema.md: the exact Tiptap setup the web must use.
- JavaScript tests (`npm test`) run the same load/save code as the app.

## 0.1.0

M0 + M1: core editor.

- `AminotesController`: load Tiptap JSON, HTML or plain text; `getJson`;
  change callback/stream (after typing pauses, and on blur); editor state;
  formatting, heading, list, checklist, quote, link, indent and undo commands.
- `AminotesEditor`: place anywhere at any size; one controller can move between
  a small box and a full-screen route without reloading (cursor and undo kept).
- `AminotesTheme`: colors, font, size, line height, padding; defaults from the
  app theme, dark mode, directional padding.
- Arabic/English direction per paragraph without changing the saved JSON.
- Optional `AminotesToolbar`.
- Voice notes in loaded notes play (recording comes in M4).
- Android, iOS (WebView) and web (iframe); fully offline.
