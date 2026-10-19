// Loading and saving a note: the part of the editor that decides what JSON is
// written back. Shared by the editor page (editor.js) and the tests, so the
// tests check exactly what the app does.
import { Editor, getSchema } from '@tiptap/core';
import { extensions } from './extensions.js';
import { prepareForEditor, restoreFromEditor, safetyExtensions } from './safety.js';

/// The shared schema plus the safety net. [customize] may change how an
/// extension renders or behaves (node views, link clicks) but must not change
/// the JSON it produces.
export function noteExtensions({ customize = (extension) => extension, extra = [] } = {}) {
  return [
    ...extensions.map((extension) => {
      // A tap on a link must never navigate away from the editor.
      const configured = extension.name === 'starterKit' ? extension.configure({ link: { openOnClick: false } }) : extension;
      return customize(configured);
    }),
    ...extra,
    ...safetyExtensions,
  ];
}

/// Creates an editor for one note.
///
/// [content] is {format: 'json' | 'html' | 'text', value}. The returned
/// object's `exportJSON()` gives the JSON to save: unknown content restored,
/// or — if the note couldn't be loaded — the original JSON untouched, with the
/// editor made read-only (`loadFailed`).
export function createNoteEditor({ element = null, content, extensions: editorExtensions, editorProps, onLoadError }) {
  const schema = getSchema(editorExtensions);
  const original = content.format === 'json' ? content.value : null;
  const session = { editor: null, loadFailed: false };

  session.editor = new Editor({
    element,
    extensions: editorExtensions,
    content: toEditorContent(content, schema),
    // Invalid content raises contentError instead of being silently dropped.
    enableContentCheck: true,
    onContentError: ({ error }) => {
      session.loadFailed = true;
      onLoadError?.(error);
    },
    editorProps: editorProps ?? {},
  });
  if (session.loadFailed) session.editor.setEditable(false);

  session.exportJSON = () =>
    session.loadFailed && original ? original : restoreFromEditor(session.editor.getJSON());
  return session;
}

function toEditorContent({ format, value }, schema) {
  if (format === 'json') return prepareForEditor(value, schema);
  if (format === 'html') return value;
  // Plain text: one paragraph per line, empty lines kept.
  const lines = String(value ?? '').split(/\r\n|\r|\n/);
  return {
    type: 'doc',
    content: lines.map((line) => (line ? { type: 'paragraph', content: [{ type: 'text', text: line }] } : { type: 'paragraph' })),
  };
}

// Word and character counts of a note (a ProseMirror doc). Blocks, line
// breaks, voice notes and images separate words; marks don't. The Dart side
// (AminotesStats.of) counts the same way from JSON.
export function countText(doc) {
  let text = '';
  let characters = 0;
  doc.descendants((node) => {
    if (node.isText) {
      text += node.text;
      characters += [...node.text].length;
    } else if (node.isBlock || node.isLeaf) {
      text += ' ';
    }
  });
  return { words: text.split(/\s+/).filter(Boolean).length, characters };
}
