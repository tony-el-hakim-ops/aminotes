// The Tiptap editor page inside the aminotes package (a WebView on Android/iOS,
// an iframe on Flutter web). It has no UI of its own: the Flutter side drives it
// through `window.tiptap` (Dart → JS) and gets messages back through the
// `TiptapBridge` JavaScriptChannel or postMessage (JS → Dart). Every message is
// a JSON string with a `type`:
//   ready | state | change | json | error | voiceNoteToggle | voiceNoteStop |
//   resolveMedia | linkTap | height | evalResult.
import { ResizableNodeView } from '@tiptap/core';
import { Placeholder } from '@tiptap/extensions';
import { NodeSelection } from '@tiptap/pm/state';
import { countText, createNoteEditor, noteExtensions } from './note.js';
import { labels } from './safety.js';

// Shown while the note is empty; set from Flutter (configure).
let placeholderText = '';
// How long typing must pause before a `change` message is sent.
let changeDelay = 400;
// Spoken label of a voice note pill; set from Flutter (configure).
let voiceNoteLabel = 'Voice note';

// The shared schema (see note.js); only rendering is customised here, so the
// saved JSON is unaffected.
const editorExtensions = noteExtensions({
  customize: (extension) => {
    if (extension.name === 'voiceNote') return extension.extend({ addNodeView: () => voiceNoteView });
    if (extension.name === 'image') return extension.extend({ addNodeView: () => imageView });
    return extension;
  },
  extra: [Placeholder.configure({ placeholder: () => placeholderText })],
});

// The current note: {editor, loadFailed, exportJSON()}, and its editor.
let session = null;
let editor = null;
let statePending = false;
let changeTimer = null;

// Inside the app, Flutter plays voice notes: recordings are app files the page
// can't read. In a plain browser the page plays them itself.
const hostedByFlutter = Boolean(window.TiptapBridge) || window.parent !== window;

function post(message) {
  const text = JSON.stringify(message);
  if (window.TiptapBridge) window.TiptapBridge.postMessage(text);
  // Flutter web hosts this page in an iframe instead of a WebView.
  else if (window.parent !== window) window.parent.postMessage(`tiptap-bridge:${text}`, window.location.origin);
  else console.log('[TiptapBridge]', text);
}

// content: {format: 'json' | 'html' | 'text', value}
function loadNote(content) {
  clearTimeout(changeTimer);
  changeTimer = null;
  session?.editor.destroy();
  // A fresh editor per note so loading it never becomes an undo step.
  session = createNoteEditor({
    element: document.getElementById('editor'),
    content,
    extensions: editorExtensions,
    editorProps: { attributes: { autocapitalize: 'sentences', spellcheck: 'true' } },
    onLoadError: (error) => post({ type: 'error', message: `load: ${error.message}` }),
  });
  editor = session.editor;
  for (const event of ['transaction', 'focus', 'blur']) editor.on(event, scheduleState);
  editor.on('update', scheduleChange);
  // Leaving the editor (e.g. tapping "full screen") sends pending edits now.
  editor.on('blur', flushChange);
  scheduleState();
}

// Edits are reported once typing pauses, not on every keystroke.
function scheduleChange() {
  clearTimeout(changeTimer);
  changeTimer = setTimeout(flushChange, changeDelay);
}

function flushChange() {
  if (changeTimer === null) return;
  clearTimeout(changeTimer);
  changeTimer = null;
  if (session && !session.loadFailed) post({ type: 'change', doc: session.exportJSON() });
}

// Batches state pushes to one per frame (typing fires many transactions).
function scheduleState() {
  if (statePending) return;
  statePending = true;
  requestAnimationFrame(() => {
    statePending = false;
    if (editor) post({ type: 'state', ...editorState() });
  });
}

const markNames = ['bold', 'italic', 'underline', 'strike', 'code', 'link', 'highlight'];
const nodeNames = ['paragraph', 'bulletList', 'orderedList', 'taskList', 'blockquote', 'codeBlock', 'table'];

function editorState() {
  const active = {};
  for (const name of [...markNames, ...nodeNames]) active[name] = editor.isActive(name);
  for (const level of [1, 2, 3]) active[`heading${level}`] = editor.isActive('heading', { level });
  const can = editor.can();
  return {
    loadFailed: session.loadFailed,
    focused: editor.isFocused,
    canUndo: can.undo(),
    canRedo: can.redo(),
    canSink: can.sinkListItem('listItem') || can.sinkListItem('taskItem'),
    canLift: can.liftListItem('listItem') || can.liftListItem('taskItem'),
    active,
    linkHref: editor.getAttributes('link').href ?? null,
    textColor: editor.getAttributes('textStyle').color ?? null,
    highlightColor: editor.isActive('highlight') ? (editor.getAttributes('highlight').color ?? null) : null,
    selectedNode: selectedNode(),
    stats: countText(editor.state.doc),
  };
}

// A tapped image or voice note: {type, src, …} so the app can offer View and
// Delete for it.
function selectedNode() {
  const { selection } = editor.state;
  if (!(selection instanceof NodeSelection)) return null;
  const { type, attrs } = selection.node;
  if (type.name === 'image') {
    return { type: 'image', src: attrs.src ?? null, alt: attrs.alt ?? null, align: attrs.align ?? null };
  }
  if (type.name === 'voiceNote') return { type: 'voiceNote', src: attrs.src ?? null, duration: attrs.duration ?? 0 };
  return null;
}

// Each command runs in a focus() chain so the caret (and Android keyboard)
// stays in the editor after a native toolbar tap.
const commands = {
  toggleBold: (c) => c.toggleBold(),
  toggleItalic: (c) => c.toggleItalic(),
  toggleUnderline: (c) => c.toggleUnderline(),
  toggleStrike: (c) => c.toggleStrike(),
  toggleCode: (c) => c.toggleCode(),
  setParagraph: (c) => c.setParagraph(),
  // Plain text at the cursor (replaces the selection).
  insertText: (c, { text }) => c.insertContent({ type: 'text', text }),
  setHeading: (c, { level }) => c.toggleHeading({ level }),
  toggleBulletList: (c) => c.toggleBulletList(),
  toggleOrderedList: (c) => c.toggleOrderedList(),
  toggleTaskList: (c) => c.toggleTaskList(),
  toggleBlockquote: (c) => c.toggleBlockquote(),
  toggleCodeBlock: (c) => c.toggleCodeBlock(),
  setHorizontalRule: (c) => c.setHorizontalRule(),
  setLink: (c, { href }) =>
    editor.state.selection.empty && !editor.isActive('link')
      ? c.insertContent({ type: 'text', text: href, marks: [{ type: 'link', attrs: { href } }] })
      : c.extendMarkRange('link').setLink({ href }),
  unsetLink: (c) => c.extendMarkRange('link').unsetLink(),
  insertImage: (c, { src, alt }) => c.setImage({ src, ...(alt ? { alt } : {}) }),
  // The selected image: 'left', 'center', 'right', or null (text direction).
  setImageAlign: (c, { align }) => c.updateAttributes('image', { align: align ?? null }),
  insertTable: (c, { rows = 3, cols = 3, withHeaderRow = true }) => c.insertTable({ rows, cols, withHeaderRow }),
  addRowBefore: (c) => c.addRowBefore(),
  addRowAfter: (c) => c.addRowAfter(),
  deleteRow: (c) => c.deleteRow(),
  addColumnBefore: (c) => c.addColumnBefore(),
  addColumnAfter: (c) => c.addColumnAfter(),
  deleteColumn: (c) => c.deleteColumn(),
  toggleHeaderRow: (c) => c.toggleHeaderRow(),
  deleteTable: (c) => c.deleteTable(),
  // color: '#rrggbb', or null to remove.
  setTextColor: (c, { color }) => (color ? c.setColor(color) : c.unsetColor()),
  setHighlight: (c, { color }) => (color ? c.setHighlight({ color }) : c.unsetHighlight()),
  insertVoiceNote: (c, { src, duration }) => c.insertContent({ type: 'voiceNote', attrs: { src, duration } }),
  // The voice note whose pill has this key (the one Flutter is playing).
  deleteVoiceNote: (c, { key }) => {
    const pos = voiceNotePositions.get(key)?.();
    return typeof pos === 'number' ? c.deleteRange({ from: pos, to: pos + 1 }) : c;
  },
  // Deletes what's selected, e.g. a tapped image.
  deleteSelection: (c) => c.deleteSelection(),
  undo: (c) => c.undo(),
  redo: (c) => c.redo(),
  sinkListItem: (c) => c.sinkListItem(editor.isActive('taskItem') ? 'taskItem' : 'listItem'),
  liftListItem: (c) => c.liftListItem(editor.isActive('taskItem') ? 'taskItem' : 'listItem'),
};

// Commands that run without focusing the editor when it isn't focused.
const UNFOCUSED_OK = new Set(['insertVoiceNote', 'insertImage', 'deleteVoiceNote']);

// The API Dart calls with runJavaScript.
window.tiptap = {
  // {format: 'json' | 'html' | 'text', value}
  setContent(content) {
    loadNote(content);
  },
  // {placeholder, changeDelay, direction: 'ltr' | 'rtl', labels: {unsupportedBlock, voiceNote}}
  configure(options) {
    if (options.placeholder !== undefined) placeholderText = options.placeholder;
    if (options.labels) {
      if (options.labels.unsupportedBlock) labels.unsupportedBlock = options.labels.unsupportedBlock;
      if (options.labels.voiceNote) voiceNoteLabel = options.labels.voiceNote;
    }
    if (options.changeDelay !== undefined) changeDelay = options.changeDelay;
    if (options.direction) document.documentElement.dir = options.direction;
    // Re-render so a changed placeholder shows immediately.
    if (editor) editor.view.dispatch(editor.state.tr);
  },
  // Replies asynchronously with {type: 'json', id, doc}.
  requestJSON(id) {
    post({ type: 'json', id, doc: session.exportJSON() });
  },
  command(name, args = {}) {
    const run = commands[name];
    if (!run) return post({ type: 'error', message: `Unknown command ${name}` });
    // Commands would still change a read-only document; never touch a note
    // that didn't load.
    if (session.loadFailed) return post({ type: 'error', message: `${name}: the note failed to load and is read-only` });
    try {
      // Inserting a finished recording must not reopen the keyboard when the
      // note isn't focused (e.g. a permission dialog took focus): on Android
      // the keyboard coming back mid-insert can turn into an Enter.
      const keepUnfocused = UNFOCUSED_OK.has(name) && !editor.isFocused;
      run(keepUnfocused ? editor.chain() : editor.chain().focus(), args).run();
    } catch (error) {
      post({ type: 'error', message: `${name}: ${error.message}` });
    }
  },
  focus() {
    editor.commands.focus();
  },
  blur() {
    editor.commands.blur();
    document.activeElement?.blur?.();
  },
  // {brightness: 'light' | 'dark', vars: {'--text': '#…', '--font-size': '16px', …}}
  setTheme({ brightness, vars }) {
    const root = document.documentElement;
    root.dataset.brightness = brightness;
    for (const [name, value] of Object.entries(vars)) root.style.setProperty(name, value);
    // Padding and font size change the height without resizing #editor's box
    // in every case: report again.
    requestAnimationFrame(() => reportHeight());
  },
  // The host app's fonts (@font-face from data: URLs) and extra CSS, after the
  // package's own styles so they win.
  setStyles({ css = '', fonts = [] }) {
    let style = document.getElementById('aminotes-host-styles');
    if (!style) {
      style = document.createElement('style');
      style.id = 'aminotes-host-styles';
      document.head.append(style);
    }
    const faces = fonts.map(
      (font) =>
        `@font-face { font-family: ${JSON.stringify(font.family)}; src: url(${JSON.stringify(font.data)}); ` +
        `font-weight: ${Number(font.weight) || 400}; font-style: ${font.style === 'italic' ? 'italic' : 'normal'}; font-display: block; }`,
    );
    style.textContent = [...faces, css].join('\n');
    // New fonts or spacing change the note's height once they apply.
    document.fonts?.ready.then(() => reportHeight());
    requestAnimationFrame(() => reportHeight());
  },
  getJSON: () => session.exportJSON(),
  // The cursor/selection as document positions, to put it back after the page
  // reloads (the web iframe reloads when it moves between editors).
  getSelection() {
    const { from, to } = editor.state.selection;
    return { from, to };
  },
  setSelection({ from, to }) {
    if (!editor) return;
    const size = editor.state.doc.content.size;
    const clamp = (n) => Math.max(0, Math.min(Number(n) || 0, size));
    editor.commands.setTextSelection({ from: clamp(from), to: clamp(to) });
  },
  // For tests: runs [code] in the page and replies {type: 'evalResult', id,
  // value} (awaiting a promise), or {id, error}.
  evaluate(id, code) {
    Promise.resolve()
      .then(() => (0, eval)(code))
      .then(
        (value) => post({ type: 'evalResult', id, value: value === undefined ? null : value }),
        (error) => post({ type: 'evalResult', id, error: String(error) }),
      );
  },
  // Sends edits still waiting for the typing pause now (app going to the
  // background, note closing).
  flush() {
    flushChange();
  },
  // {oldSrc: newSrc}: after uploads, point media at their URLs. Not an undo
  // step (undo must never bring back a local file reference).
  replaceSources(map) {
    if (!editor || session.loadFailed) return;
    const { tr } = editor.state;
    editor.state.doc.descendants((node, pos) => {
      const src = node.attrs?.src;
      if (typeof src === 'string' && Object.hasOwn(map, src)) {
        tr.setNodeMarkup(pos, undefined, { ...node.attrs, src: map[src] });
      }
    });
    if (!tr.docChanged) return;
    tr.setMeta('addToHistory', false);
    editor.view.dispatch(tr);
  },
  // Flutter answers resolveMedia: a displayable URL (data:) for a local: src,
  // or null if the file isn't on this device.
  mediaResolved(src, url) {
    resolvedMedia.set(src, url);
    for (const show of mediaViews.get(src) ?? []) show(url);
  },
  // Flutter reports native playback so the pill shows ▶ or ⏸ and, once
  // started, the elapsed time (position in seconds; null when stopped).
  voiceNotePlayback(key, playing, position = null) {
    voiceNoteViews.get(key)?.(playing, position);
  },
};

// Inline voice note pill: ▶ waveform 0:12.
// Each mounted pill registers a setter Flutter can call by key.
const voiceNoteViews = new Map();
const voiceNotePositions = new Map(); // key -> getPos
let nextVoiceNoteKey = 0;

const formatSeconds = (value) => {
  const seconds = Math.round(Number(value) || 0);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
};

function voiceNoteView({ node, getPos }) {
  const dom = document.createElement('span');
  dom.className = 'voice-note';
  dom.contentEditable = 'false';
  dom.setAttribute('data-voice-note', '');

  const button = document.createElement('button');
  button.type = 'button';
  button.tabIndex = -1;
  const icon = document.createElement('span');
  icon.className = 'voice-note-icon';
  const label = document.createElement('span');
  label.className = 'voice-note-label';
  button.append(icon, waveIcon(), label);
  dom.append(button);

  const key = `vn${nextVoiceNoteKey++}`;
  let audio = null;
  let nativePlaying = false;
  let nativePosition = null;
  let current = node;
  const render = () => {
    const duration = formatSeconds(current.attrs.duration);
    const playing = hostedByFlutter ? nativePlaying : audio && !audio.paused;
    const position = hostedByFlutter ? nativePosition : audio && audio.currentTime > 0 ? audio.currentTime : null;
    label.textContent = position === null ? duration : formatSeconds(Math.floor(position));
    icon.innerHTML = playing ? pauseSvg : playSvg;
    button.setAttribute('aria-label', `${voiceNoteLabel}, ${duration}`);
  };
  voiceNoteViews.set(key, (playing, position) => {
    nativePlaying = playing;
    nativePosition = position;
    render();
  });
  voiceNotePositions.set(key, getPos);

  // Keep the tap from moving the caret or opening the keyboard.
  button.addEventListener('mousedown', (event) => event.preventDefault());
  button.addEventListener('click', (event) => {
    event.preventDefault();
    const { src } = current.attrs;
    if (!src) return;
    if (hostedByFlutter) return post({ type: 'voiceNoteToggle', key, src, duration: Number(current.attrs.duration) || 0 });
    if (!audio) {
      audio = new Audio(src);
      for (const name of ['play', 'pause', 'ended', 'timeupdate']) audio.addEventListener(name, render);
    }
    if (audio.paused) audio.play().catch((error) => post({ type: 'error', message: `audio: ${error.message}` }));
    else audio.pause();
  });
  render();

  return {
    dom,
    update(updated) {
      if (updated.type !== current.type) return false;
      current = updated;
      render();
      return true;
    },
    stopEvent: (event) => button.contains(event.target),
    ignoreMutation: () => true,
    destroy() {
      voiceNoteViews.delete(key);
      voiceNotePositions.delete(key);
      audio?.pause();
      if (nativePlaying) post({ type: 'voiceNoteStop', key });
    },
  };
}

// Images. A `local:` src is a file in the app's storage, which the page can't
// read: Flutter sends a displayable URL for it, and the note keeps `local:`.
const resolvedMedia = new Map(); // src -> url | null
const mediaViews = new Map(); // src -> Set(show)

function displayUrl(src, show) {
  if (!src || !src.startsWith('local:')) return src;
  let views = mediaViews.get(src);
  if (!views) mediaViews.set(src, (views = new Set()));
  views.add(show);
  if (resolvedMedia.has(src)) return resolvedMedia.get(src);
  if (views.size === 1) post({ type: 'resolveMedia', src });
  return undefined; // pending
}

const BLANK_PIXEL = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

// Images can be resized by dragging a corner handle of a tapped (selected)
// image. The size is saved as the node's `width`/`height` (Tiptap's standard
// image attributes); on a narrower screen the image still fits the width.
function imageView({ node, getPos, editor: viewEditor }) {
  const img = document.createElement('img');
  img.draggable = false;
  // A URL that can't load (offline, deleted) shows the placeholder, not a
  // broken-image icon.
  // (The blank pixel hides the browser's own broken-image icon.)
  img.addEventListener('error', () => {
    if (!img.getAttribute('src') || img.src === BLANK_PIXEL) return;
    img.classList.add('aminotes-image-missing');
    img.src = BLANK_PIXEL;
  });
  img.addEventListener('load', () => {
    if (img.src !== BLANK_PIXEL) img.classList.remove('aminotes-image-missing');
  });
  let current = null;
  const show = (url) => {
    img.classList.toggle('aminotes-image-pending', url === undefined);
    img.classList.toggle('aminotes-image-missing', url === null);
    if (url) img.src = url;
    else img.src = BLANK_PIXEL;
  };
  const applyWidth = (width) => {
    img.style.width = width ? `${width}px` : '';
  };
  const render = (next) => {
    if (current) mediaViews.get(current.attrs.src)?.delete(show);
    current = next;
    const { src, alt, title } = next.attrs;
    if (alt) img.alt = alt;
    else img.removeAttribute('alt');
    if (title) img.title = title;
    else img.removeAttribute('title');
    show(displayUrl(src, show));
  };
  render(node);

  const view = new ResizableNodeView({
    element: img,
    editor: viewEditor,
    node,
    getPos,
    // Only the width: the height follows the picture's own proportions.
    onResize: (width) => applyWidth(width),
    onCommit: (width, height) => {
      const pos = getPos();
      if (typeof pos !== 'number') return;
      viewEditor
        .chain()
        .setNodeSelection(pos)
        .updateAttributes('image', { width: Math.round(width), height: Math.round(height) })
        .run();
    },
    onUpdate: (updated) => {
      if (updated.attrs.src !== current.attrs.src || updated.attrs.alt !== current.attrs.alt) render(updated);
      else current = updated;
      applyWidth(updated.attrs.width);
      applyAlign(updated.attrs.align);
      return true;
    },
    options: {
      directions: ['top-left', 'top-right', 'bottom-left', 'bottom-right'],
      min: { width: 48, height: 48 },
      preserveAspectRatio: true,
    },
  });
  applyWidth(node.attrs.width);
  // Left, center or right on its line (CSS on [data-align], see editor.css).
  const applyAlign = (align) => {
    if (align) view.dom.dataset.align = align;
    else delete view.dom.dataset.align;
  };
  applyAlign(node.attrs.align);

  // Tiptap ends a resize on mouseup only: end it when the finger lifts too,
  // or a resize on a phone would never be saved.
  const endTouchResize = () => {
    document.removeEventListener('touchmove', view.handleTouchMove);
    view.handleMouseUp();
  };
  view.dom.addEventListener(
    'touchstart',
    (event) => {
      if (!event.target.closest?.('[data-resize-handle]')) return;
      document.addEventListener('touchend', endTouchResize, { once: true });
      document.addEventListener('touchcancel', endTouchResize, { once: true });
    },
    { capture: true },
  );

  const destroyView = view.destroy.bind(view);
  view.destroy = () => {
    mediaViews.get(current.attrs.src)?.delete(show);
    document.removeEventListener('touchend', endTouchResize);
    document.removeEventListener('touchcancel', endTouchResize);
    destroyView();
  };
  return view;
}

const playSvg = '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>';
const pauseSvg = '<svg viewBox="0 0 24 24"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>';
function waveIcon() {
  const span = document.createElement('span');
  span.className = 'voice-note-wave';
  span.innerHTML =
    '<svg viewBox="0 0 24 24"><path d="M7 18h2V6H7v12zm4 4h2V2h-2v20zm-8-8h2v-4H3v4zm12 4h2V6h-2v12zm4-8v4h2v-4h-2z"/></svg>';
  return span;
}

// Links don't navigate (that would replace the editor page): report the tap,
// and the app decides what to do with the URL.
document.addEventListener('click', (event) => {
  // A voice note or image inside a link keeps its own tap.
  if (event.target.closest?.('.voice-note, img')) return;
  const link = event.target.closest?.('a[href]');
  if (link && editor?.view.dom.contains(link)) {
    event.preventDefault();
    // Tiptap renders a link with an unsafe protocol (javascript:, data:, …)
    // as href="": nothing to open, so nothing to report.
    const href = link.getAttribute('href');
    if (href) post({ type: 'linkTap', href });
  }
});

// The height the note needs, so the app can grow the editor with its content.
let reportedHeight = 0;
const reportHeight = () => {
  const page = document.getElementById('page');
  const style = getComputedStyle(page);
  const height = Math.ceil(
    document.getElementById('editor').offsetHeight + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom),
  );
  if (Math.abs(height - reportedHeight) < 1) return;
  reportedHeight = height;
  post({ type: 'height', value: height });
};
new ResizeObserver(reportHeight).observe(document.getElementById('editor'));

// Tapping the empty area under the last line puts the caret at the end.
document.addEventListener('click', (event) => {
  if (editor && event.target === document.getElementById('page')) editor.chain().focus('end').run();
});
// The WebView shrinks when the keyboard opens; keep the caret visible.
window.addEventListener('resize', () => {
  if (editor?.isFocused) editor.commands.scrollIntoView();
});
window.addEventListener('error', (event) => post({ type: 'error', message: String(event.message) }));

loadNote({ format: 'json', value: { type: 'doc', content: [{ type: 'paragraph' }] } });
post({ type: 'ready' });
