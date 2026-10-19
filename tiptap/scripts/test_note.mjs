// What the package saves, tested with the same code the editor page runs
// (src/note.js), headless. Run: npm test
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { GlobalRegistrator } from '@happy-dom/global-registrator';
import assert from 'node:assert/strict';
import { countText, createNoteEditor, noteExtensions } from '../src/note.js';
import { SCHEMA_VERSION } from '../src/extensions.js';

const extensions = noteExtensions();
const load = (value) => createNoteEditor({ content: { format: 'json', value }, extensions });
const doc = (...content) => ({ type: 'doc', content });
const p = (...content) => ({ type: 'paragraph', ...(content.length ? { content } : {}) });
const text = (value, marks) => ({ type: 'text', text: value, ...(marks ? { marks } : {}) });

// Loading then saving without edits must give back the same JSON.
function assertRoundTrip(original) {
  const note = load(original);
  assert.equal(note.loadFailed, false, 'loads');
  assert.deepEqual(note.exportJSON(), original);
  return note;
}

test('schema version', () => assert.equal(SCHEMA_VERSION, 3));

test('the sample note round-trips', () => {
  assertRoundTrip(JSON.parse(readFileSync(new URL('../../example/assets/sample_note.json', import.meta.url))));
});

test('text color and highlight round-trip', () => {
  assertRoundTrip(
    doc(
      p(
        text('red', [{ type: 'textStyle', attrs: { color: '#e53935' } }]),
        text(' and '),
        text('marked', [{ type: 'highlight', attrs: { color: '#fff59d' } }]),
      ),
    ),
  );
});

test('an unknown block is kept, with its children and attributes', () => {
  const callout = {
    type: 'callout',
    attrs: { emoji: '💡', tone: 'info' },
    content: [p(text('Remember this', [{ type: 'bold' }]))],
  };
  const original = doc(p(text('Before')), callout, p(text('After')));
  const note = assertRoundTrip(original);
  // The editor shows a placeholder in its place.
  assert.equal(note.editor.state.doc.child(1).type.name, 'aminotesUnknownBlock');
});

test('an unknown block inside a list item is kept', () => {
  assertRoundTrip(
    doc({
      type: 'bulletList',
      content: [{ type: 'listItem', content: [p(text('Item')), { type: 'embed', attrs: { url: 'https://x.y' } }] }],
    }),
  );
});

test('an unknown inline node inside a sentence is kept', () => {
  assertRoundTrip(doc(p(text('Hi '), { type: 'mention', attrs: { id: '42', label: 'Sam' } }, text(', welcome'))));
});

test('an unknown mark is kept next to known marks', () => {
  assertRoundTrip(doc(p(text('E=mc'), text('2', [{ type: 'bold' }, { type: 'superscript' }]))));
});

test('unknown attributes on known nodes and marks are kept', () => {
  assertRoundTrip(
    doc(
      { type: 'paragraph', attrs: { textAlign: 'center' }, content: [text('Centered')] },
      { type: 'heading', attrs: { level: 2, id: 'intro' }, content: [text('Intro')] },
      p(
        text('link', [
          {
            type: 'link',
            attrs: {
              href: 'https://tiptap.dev',
              target: '_blank',
              rel: 'noopener noreferrer nofollow',
              class: null,
              title: null,
              trackingId: 'abc',
            },
          },
        ]),
      ),
    ),
  );
});

test('editing keeps unknown content', () => {
  const original = doc(p(text('Hello')), { type: 'callout', content: [p(text('kept'))] });
  const note = load(original);
  note.editor.commands.insertContentAt(1, { type: 'text', text: 'Oh, ' });
  const saved = note.exportJSON();
  assert.deepEqual(saved.content[0], p(text('Oh, Hello')));
  assert.deepEqual(saved.content[1], original.content[1]);
});

test('invalid structure makes the note read-only and saves the original untouched', () => {
  // A paragraph directly inside a bullet list (it must be in a list item).
  const original = doc({ type: 'bulletList', content: [p(text('broken'))] }, p(text('rest')));
  let error = null;
  const note = createNoteEditor({
    content: { format: 'json', value: original },
    extensions,
    onLoadError: (e) => (error = e),
  });
  assert.equal(note.loadFailed, true);
  assert.ok(error, 'reports the error');
  assert.equal(note.editor.isEditable, false);
  assert.deepEqual(note.exportJSON(), original);
});

test('plain text becomes one paragraph per line', () => {
  const note = createNoteEditor({ content: { format: 'text', value: 'One\n\nThree' }, extensions });
  assert.deepEqual(note.exportJSON(), doc(p(text('One')), p(), p(text('Three'))));
});

test('HTML is converted, and saving never leaks the hidden attribute', (t) => {
  // HTML parsing needs a DOM; the app has one (WebView), Node needs happy-dom.
  GlobalRegistrator.register();
  t.after(() => GlobalRegistrator.unregister());
  const note = createNoteEditor({ content: { format: 'html', value: '<h2>Title</h2><p><b>Bold</b></p>' }, extensions });
  const saved = JSON.stringify(note.exportJSON());
  assert.match(saved, /"heading"/);
  assert.doesNotMatch(saved, /aminotes/);
});

test('replacing a voice note src is saved and is not an undo step', async (t) => {
  // Undo needs a mounted editor, so this one runs in happy-dom.
  GlobalRegistrator.register();
  const element = document.createElement('div');
  document.body.append(element);
  const vn = (src) => ({ type: 'voiceNote', attrs: { src, duration: 3 } });
  const note = createNoteEditor({
    element,
    content: { format: 'json', value: doc(p(text('Hi '), vn('local:voice_notes/1.m4a'), text(' there'))) },
    extensions,
  });
  t.after(() => {
    note.editor.destroy();
    GlobalRegistrator.unregister();
  });
  // The editor mounts its view on the next tick.
  await new Promise((resolve) => setTimeout(resolve, 0));
  note.editor.commands.insertContentAt(1, { type: 'text', text: 'Oh ' });
  // What editor.js replaceSources does:
  const { tr } = note.editor.state;
  note.editor.state.doc.descendants((node, pos) => {
    if (node.attrs?.src === 'local:voice_notes/1.m4a') tr.setNodeMarkup(pos, undefined, { ...node.attrs, src: 'https://cdn/1.m4a' });
  });
  tr.setMeta('addToHistory', false);
  note.editor.view.dispatch(tr);
  assert.deepEqual(note.exportJSON().content[0].content[1], vn('https://cdn/1.m4a'));
  assert.equal(note.editor.commands.undo(), true);
  const after = note.exportJSON().content[0];
  assert.deepEqual(after.content[0], text('Hi '), 'undo removed the typing');
  assert.deepEqual(after.content[1], vn('https://cdn/1.m4a'), 'undo kept the uploaded URL');
});

test('table commands build valid tables that round-trip', () => {
  const note = load(doc(p(text('Before'))));
  const { editor } = note;
  editor.commands.setTextSelection(7);
  assert.ok(editor.commands.insertTable({ rows: 2, cols: 2, withHeaderRow: true }), 'insert');
  assert.ok(editor.isActive('table'), 'cursor is in the table');
  assert.ok(editor.commands.addRowAfter(), 'add row');
  assert.ok(editor.commands.addColumnBefore(), 'add column');
  const saved = note.exportJSON();
  const table = saved.content.find((n) => n.type === 'table');
  assert.equal(table.content.length, 3, 'rows');
  assert.equal(table.content[0].content.length, 3, 'columns');
  assert.equal(table.content[0].content[0].type, 'tableHeader');
  assertRoundTrip(saved);
  assert.ok(editor.commands.deleteColumn());
  assert.ok(editor.commands.deleteTable());
  assert.equal(note.exportJSON().content.some((n) => n.type === 'table'), false, 'deleted');
});


// The same cases are counted by AminotesStats.of in Dart (test/stats_test.dart).
test('words and characters', () => {
  const count = (value) => countText(load(value).editor.state.doc);
  assert.deepEqual(count(doc(p())), { words: 0, characters: 0 });
  assert.deepEqual(
    count(
      doc(
        { type: 'heading', attrs: { level: 1 }, content: [text('Shopping')] },
        p(text('bo'), text('ld', [{ type: 'bold' }]), text(' milk'), { type: 'hardBreak' }, text('eggs')),
        p(text('مرحبا بكم'), { type: 'voiceNote', attrs: { src: 'local:voice_notes/a.m4a', duration: 3 } }, text('end')),
      ),
    ),
    { words: 7, characters: 33 },
  );
});

// Resizing an image saves Tiptap's standard width/height attributes, which
// the web app's Image extension reads too.
test('a resized image keeps its width and height', () => {
  assertRoundTrip(
    doc(
      {
        type: 'image',
        attrs: { src: 'https://example.com/a.png', alt: null, title: null, width: 240, height: 120, align: null },
      },
    ),
  );
});

test('image alignment is saved, and set on the selected image', () => {
  const image = (attrs) => ({
    type: 'image',
    attrs: { src: 'https://example.com/a.png', alt: null, title: null, width: null, height: null, ...attrs },
  });
  assertRoundTrip(doc(image({ align: 'center' })));

  const note = load(doc(p(text('Before')), image({})));
  const { editor } = note;
  editor.commands.setNodeSelection(8);
  assert.ok(editor.commands.updateAttributes('image', { align: 'right' }), 'aligned');
  assert.equal(note.exportJSON().content[1].attrs.align, 'right');
  editor.commands.updateAttributes('image', { align: null });
  assert.equal(note.exportJSON().content[1].attrs.align, null, 'back to the text direction');
});

test('image alignment from HTML: known values only', (t) => {
  // HTML parsing needs a DOM (see the HTML test above).
  GlobalRegistrator.register();
  t.after(() => GlobalRegistrator.unregister());
  const html = (value) =>
    createNoteEditor({ content: { format: 'html', value }, extensions }).exportJSON().content[0].attrs.align;
  assert.equal(html('<img src="https://example.com/a.png" data-align="center">'), 'center');
  assert.equal(html('<img src="https://example.com/a.png" data-align="sideways">'), null);
});
