// Validates a Tiptap JSON document against our extension set and writes it
// back exactly as Tiptap itself would save it (default attrs filled in).
import { readFileSync, writeFileSync } from 'node:fs';
import { getSchema } from '@tiptap/core';
import { Node } from '@tiptap/pm/model';
import { extensions } from '../src/extensions.js';

const [input, output] = process.argv.slice(2);
const schema = getSchema(extensions);
const doc = Node.fromJSON(schema, JSON.parse(readFileSync(input, 'utf8')));
doc.check();
writeFileSync(output, JSON.stringify(doc.toJSON(), null, 2) + '\n');
console.log(`ok: ${doc.childCount} top-level blocks -> ${output}`);
