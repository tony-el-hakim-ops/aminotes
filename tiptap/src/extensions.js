// The Tiptap schema shared by the web app and the mobile app. Keep it in sync
// with the web team's extension list so both save the same JSON.
import { Node, mergeAttributes } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import Image from '@tiptap/extension-image';
import { TaskList, TaskItem } from '@tiptap/extension-list';
import { Table, TableRow, TableHeader, TableCell } from '@tiptap/extension-table';
import { TextStyle, Color } from '@tiptap/extension-text-style';
import Highlight from '@tiptap/extension-highlight';

/// Bumped whenever this list changes in a way that changes saved JSON
/// (a new node, mark or attribute). Mirrored in Dart as `aminotesSchemaVersion`.
///   1: StarterKit, Image, TaskList/TaskItem, Table, VoiceNote.
///   2: + TextStyle/Color (text color), Highlight (multicolor).
///   3: + `align` on images (left, center, right).
export const SCHEMA_VERSION = 3;

/// A voice note that sits inside a sentence, between words.
/// JSON: {"type": "voiceNote", "attrs": {"src": "...", "duration": 12}}
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

/// Images can be placed left, center or right on their line:
/// {"type": "image", "attrs": {"src": "...", "align": "center"}}. No `align`
/// (null) follows the text direction (left in English, right in Arabic).
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
  // StarterKit v3 already includes Underline and Link.
  StarterKit,
  AlignedImage,
  TaskList,
  TaskItem.configure({ nested: true }),
  Table,
  TableRow,
  TableHeader,
  TableCell,
  VoiceNote,
  // Text color: {"type": "textStyle", "attrs": {"color": "#e53935"}}
  TextStyle,
  Color,
  // Background color: {"type": "highlight", "attrs": {"color": "#fff59d"}}
  Highlight.configure({ multicolor: true }),
];
