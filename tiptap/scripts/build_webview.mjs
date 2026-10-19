// Bundles the web code shipped inside the package:
// - ../assets/editor/: the editor page. index.html + editor.css + compat.js +
//   editor.js (one IIFE, no network needed).
// - ../assets/web_audio/: audio.js, which makes web recordings play on every
//   device (AAC, or WAV).
// - ../assets/editor/NOTICES.txt: the licenses of all of the above (Tiptap,
//   ProseMirror, mp4-muxer, …), shown on the app's license page.
import { build } from 'esbuild';
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const out = new URL('../../assets/editor/', import.meta.url).pathname;
const audioOut = new URL('../../assets/web_audio/', import.meta.url).pathname;
mkdirSync(out, { recursive: true });
mkdirSync(audioOut, { recursive: true });

const audio = await build({
  entryPoints: ['src/audio.js'],
  bundle: true,
  format: 'iife',
  target: 'es2020',
  minify: true,
  legalComments: 'none',
  metafile: true,
  outfile: `${audioOut}audio.js`,
  logLevel: 'warning',
});

const result = await build({
  entryPoints: ['src/editor.js'],
  bundle: true,
  format: 'iife',
  target: 'es2020',
  minify: true,
  legalComments: 'none',
  metafile: true,
  outfile: `${out}editor.js`,
  logLevel: 'warning',
});
for (const file of ['index.html', 'editor.css', 'compat.js']) copyFileSync(`webview/${file}`, `${out}${file}`);

// Every npm package with code in the bundle, and its license text.
const packages = new Map();
for (const input of [...Object.keys(result.metafile.inputs), ...Object.keys(audio.metafile.inputs)]) {
  const match = input.match(/^(.*node_modules\/(?:@[^/]+\/)?[^/]+)\//);
  if (!match || packages.has(match[1])) continue;
  const pkg = JSON.parse(readFileSync(join(match[1], 'package.json'), 'utf8'));
  packages.set(match[1], { name: pkg.name, version: pkg.version, license: pkg.license, text: licenseText(match[1]) });
}

function licenseText(dir) {
  for (let current = dir; current.includes('node_modules'); current = dirname(current)) {
    const file = readdirSync(current).find((name) => /^(licen[cs]e|copying)(\.(md|txt))?$/i.test(name));
    if (file) return readFileSync(join(current, file), 'utf8').trim();
    if (existsSync(join(current, 'package.json')) && current !== dir) break;
  }
  return null;
}

const missing = [...packages.values()].filter((p) => !p.text);
if (missing.length) {
  throw new Error(`No license file for: ${missing.map((p) => `${p.name} (${p.license})`).join(', ')}`);
}
const sorted = [...packages.values()].sort((a, b) => a.name.localeCompare(b.name));
writeFileSync(
  `${out}NOTICES.txt`,
  sorted.map((p) => `${p.name} ${p.version} (${p.license})\n\n${p.text}`).join('\n\n' + '-'.repeat(72) + '\n\n') + '\n',
);
console.log(`built -> ${out} (${sorted.length} bundled packages: ${[...new Set(sorted.map((p) => p.license))].join(', ')})`);
