# Tiptap schema shared with the mobile app (aminotes)

The mobile app edits notes with the **real Tiptap editor**, bundled inside the
`aminotes` Flutter package. Notes are saved as Tiptap JSON (`editor.getJSON()`),
the same as on the web. For a note to round-trip between web and mobile without
changes, **both sides must use the same extensions**.

Source of truth: [`tiptap/src/extensions.js`](../tiptap/src/extensions.js).
Schema version: **3** (`SCHEMA_VERSION`).

## Versions

All `@tiptap/*` packages at **3.31.4** (any 3.x should produce the same JSON,
but keep web and mobile on the same minor version when possible).

## Extensions

```js
import { Node, mergeAttributes } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import Image from '@tiptap/extension-image';
import { TaskList, TaskItem } from '@tiptap/extension-list';
import { Table, TableRow, TableHeader, TableCell } from '@tiptap/extension-table';
import { TextStyle, Color } from '@tiptap/extension-text-style';
import Highlight from '@tiptap/extension-highlight';

export const VoiceNote = Node.create({
  name: 'voiceNote',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,
  addAttributes() {
    return {
      src: { default: null },
      duration: { default: 0 },
    };
  },
  parseHTML() {
    return [{ tag: 'span[data-voice-note]' }];
  },
  renderHTML({ HTMLAttributes }) {
    return ['span', mergeAttributes(HTMLAttributes, { 'data-voice-note': '' })];
  },
});

// Images can be aligned left, center or right (schema version 3).
export const IMAGE_ALIGNMENTS = ['left', 'center', 'right'];
export const AlignedImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      align: {
        default: null,
        parseHTML: (element) => {
          const align = element.getAttribute('data-align');
          return IMAGE_ALIGNMENTS.includes(align) ? align : null;
        },
        renderHTML: (attributes) => (attributes.align ? { 'data-align': attributes.align } : {}),
      },
    };
  },
});

export const extensions = [
  StarterKit,                          // includes Underline and Link in v3
  AlignedImage,                        // Image + `align`
  TaskList,
  TaskItem.configure({ nested: true }),
  Table, TableRow, TableHeader, TableCell,
  VoiceNote,
  TextStyle,
  Color,
  Highlight.configure({ multicolor: true }),
];
```

Editor-only options that **don't** change the JSON are fine to differ (e.g. the
mobile app sets `link: { openOnClick: false }` and adds `Placeholder`).

## What the JSON looks like

```json
{ "type": "text", "text": "red", "marks": [{ "type": "textStyle", "attrs": { "color": "#e53935" } }] }
{ "type": "text", "text": "marked", "marks": [{ "type": "highlight", "attrs": { "color": "#fff59d" } }] }
{ "type": "voiceNote", "attrs": { "src": "https://…/note.m4a", "duration": 12 } }
{ "type": "image", "attrs": { "src": "https://…/photo.jpg", "width": 240, "height": 160, "align": "center" } }
```

- Images: `width`/`height` (Tiptap's standard attributes) are set when the
  user resizes the image; null means full width. `align` is `left`, `center`,
  `right` or null (follows the text direction). Show it on the web with CSS,
  e.g. a wrapper or `img[data-align='center'] { margin-inline: auto; }` (the
  image is a block; set `display: block`). **Without `AlignedImage`, the web
  editor drops `align` when it saves a note.**

- Colors are stored as `#rrggbb`. The mobile app reads other CSS colors (e.g.
  `rgb(…)`, names) fine but shows them as "no color" in its toolbar.
- A `voiceNote` sits **inside a paragraph**, between words. `duration` is in
  seconds. On mobile, a voice note recorded offline has
  `src: "local:voice_notes/<file>.m4a"` until it's uploaded; the app replaces it
  with the `https://` URL after upload. The web should show `local:` sources as
  "not uploaded yet" rather than trying to play them.

## Rules

1. **Adding an extension** that changes the JSON (a new node, mark or
   attribute): add it to `extensions.js` in the package too, bump
   `SCHEMA_VERSION`, release a new package version, then ship the web change.
2. **If the web ships first anyway**, nothing is lost: the mobile app keeps
   unknown nodes, marks and attributes exactly as they are and saves them back
   unchanged (unknown blocks show as "Unsupported content, kept unchanged").
   If a note can't be loaded safely at all, the mobile app opens it read-only
   and never overwrites it.
3. **Don't** enable Tiptap's global `textDirection` option: it adds `dir` to
   every node in the JSON. The mobile app handles Arabic/English direction with
   CSS instead (`unicode-bidi: plaintext`), and the web can do the same.

## Checking a note

From the package's `tiptap/` folder:

```bash
npm install
npm test     # includes the sample note round trip
```

To check real notes, add them to `tiptap/scripts/test_note.mjs` with
`assertRoundTrip(note)`.
