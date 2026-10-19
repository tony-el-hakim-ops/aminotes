// Safety net: a note written by the web app with an extension this package
// doesn't have must never lose data here.
//
// Plain Tiptap silently drops unknown nodes, marks and attributes when it
// loads JSON (an unknown node even makes it fall back to an EMPTY document),
// and saving would then overwrite the note. Instead:
//   - unknown nodes become placeholders that keep the original JSON,
//   - unknown marks become a generic mark that keeps the original JSON,
//   - unknown attributes are stashed in a hidden attribute,
// and `restoreFromEditor` puts everything back exactly when saving.
import { Extension, Mark, Node } from '@tiptap/core';

export const UNKNOWN_BLOCK = 'aminotesUnknownBlock';
export const UNKNOWN_INLINE = 'aminotesUnknownInline';
export const UNKNOWN_MARK = 'aminotesUnknownMark';
// Hidden attribute on every node and mark holding attributes the schema lacks.
export const EXTRA_ATTRS = 'aminotesExtra';

/// Texts shown in the note, set from Flutter in the app's language
/// (`{type}` is replaced by the kind of content, e.g. "callout").
export const labels = {
  unsupportedBlock: 'Unsupported content ({type}), kept unchanged',
};

const unknownLabel = (data) => {
  try {
    return JSON.parse(data).type ?? 'content';
  } catch {
    return 'content';
  }
};

const dataAttribute = { data: { default: null, rendered: false } };

export const UnknownBlock = Node.create({
  name: UNKNOWN_BLOCK,
  group: 'block',
  atom: true,
  selectable: true,
  addAttributes: () => dataAttribute,
  parseHTML: () => [{ tag: 'div[data-aminotes-unknown]' }],
  renderHTML: ({ node }) => [
    'div',
    { 'data-aminotes-unknown': '', class: 'aminotes-unknown', contenteditable: 'false' },
    labels.unsupportedBlock.replaceAll('{type}', unknownLabel(node.attrs.data)),
  ],
});

export const UnknownInline = Node.create({
  name: UNKNOWN_INLINE,
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,
  addAttributes: () => dataAttribute,
  parseHTML: () => [{ tag: 'span[data-aminotes-unknown]' }],
  renderHTML: ({ node }) => [
    'span',
    { 'data-aminotes-unknown': '', class: 'aminotes-unknown-inline', contenteditable: 'false' },
    `[${unknownLabel(node.attrs.data)}]`,
  ],
});

export const UnknownMark = Mark.create({
  name: UNKNOWN_MARK,
  // Several different unknown marks may cover the same text.
  excludes: '',
  addAttributes: () => dataAttribute,
  parseHTML: () => [{ tag: 'span[data-aminotes-unknown-mark]' }],
  renderHTML: () => ['span', { 'data-aminotes-unknown-mark': '' }, 0],
});

// Adds the hidden EXTRA_ATTRS attribute to every node and mark type.
export const ExtraAttributes = Extension.create({
  name: 'aminotesExtraAttributes',
  addGlobalAttributes() {
    const types = this.extensions
      .filter((extension) => (extension.type === 'node' || extension.type === 'mark') && extension.name !== 'text')
      .map((extension) => extension.name);
    return [{ types, attributes: { [EXTRA_ATTRS]: { default: null, rendered: false } } }];
  },
});

export const safetyExtensions = [UnknownBlock, UnknownInline, UnknownMark, ExtraAttributes];

// ---------------------------------------------------------------------------
// JSON in (before the editor sees it)

/// Rewrites [doc] so the editor's schema can load all of it. Returns a new
/// object; [doc] is untouched.
export function prepareForEditor(doc, schema) {
  return prepareNode(doc, null, schema);
}

function prepareNode(node, parentType, schema) {
  if (!node || typeof node !== 'object') return node;
  const type = schema.nodes[node.type];
  if (!type) {
    const inline = parentType?.inlineContent ?? false;
    return { type: inline ? UNKNOWN_INLINE : UNKNOWN_BLOCK, attrs: { data: JSON.stringify(node) } };
  }
  const out = { ...node };
  const attrs = splitAttrs(node.attrs, type.attrs);
  if (attrs) out.attrs = attrs;
  if (Array.isArray(node.marks)) out.marks = node.marks.map((mark) => prepareMark(mark, schema));
  if (Array.isArray(node.content)) out.content = node.content.map((child) => prepareNode(child, type, schema));
  return out;
}

function prepareMark(mark, schema) {
  const type = schema.marks[mark?.type];
  if (!type) return { type: UNKNOWN_MARK, attrs: { data: JSON.stringify(mark) } };
  const attrs = splitAttrs(mark.attrs, type.attrs);
  return attrs ? { ...mark, attrs } : { ...mark };
}

// Keeps known attributes, moves the rest into EXTRA_ATTRS.
function splitAttrs(attrs, known) {
  if (!attrs || typeof attrs !== 'object') return attrs;
  const kept = {};
  const extra = {};
  for (const [key, value] of Object.entries(attrs)) {
    if (key in known) kept[key] = value;
    else extra[key] = value;
  }
  if (Object.keys(extra).length) kept[EXTRA_ATTRS] = extra;
  return kept;
}

// ---------------------------------------------------------------------------
// JSON out (before saving)

/// Undoes [prepareForEditor] on the editor's JSON: restores unknown nodes,
/// marks and attributes, and removes the hidden attribute.
export function restoreFromEditor(doc) {
  return restoreNode(doc);
}

function restoreNode(node) {
  if (!node || typeof node !== 'object') return node;
  if (node.type === UNKNOWN_BLOCK || node.type === UNKNOWN_INLINE) return parseData(node.attrs?.data, node);
  const out = { ...node };
  const attrs = restoreAttrs(node.attrs);
  if (attrs) out.attrs = attrs;
  else delete out.attrs;
  if (Array.isArray(node.marks)) out.marks = node.marks.map(restoreMark);
  if (Array.isArray(node.content)) out.content = node.content.map(restoreNode);
  return out;
}

function restoreMark(mark) {
  if (mark.type === UNKNOWN_MARK) return parseData(mark.attrs?.data, mark);
  const out = { ...mark };
  const attrs = restoreAttrs(mark.attrs);
  if (attrs) out.attrs = attrs;
  else delete out.attrs;
  return out;
}

// Removes EXTRA_ATTRS and merges what it held back in. Returns null when no
// attributes remain (the type has none of its own, like `bold`).
function restoreAttrs(attrs) {
  if (!attrs || typeof attrs !== 'object') return attrs ?? null;
  const { [EXTRA_ATTRS]: extra, ...rest } = attrs;
  const merged = extra && typeof extra === 'object' ? { ...rest, ...extra } : rest;
  return Object.keys(merged).length ? merged : null;
}

function parseData(data, fallback) {
  try {
    return JSON.parse(data);
  } catch {
    return fallback;
  }
}
