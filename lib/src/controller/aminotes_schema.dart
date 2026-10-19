/// Version of the Tiptap schema this package edits (see
/// tiptap/src/extensions.js, `SCHEMA_VERSION`). It changes whenever saved JSON
/// can contain something new. Store it next to notes if you need to know which
/// app version wrote them.
///
///   1: StarterKit, Image, TaskList/TaskItem, Table, VoiceNote.
///   2: + text color (TextStyle/Color) and highlight (Highlight, multicolor).
///   3: + `align` on images (left, center, right).
const aminotesSchemaVersion = 3;
