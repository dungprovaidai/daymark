// Structural checks only. This does not compile Swift or replace xcodebuild.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(x => x.isDirectory() ? walk(path.join(d, x.name)) : [path.join(d, x.name)]);
const all = walk(root);
const swift = all.filter(x => x.endsWith('.swift'));
const project = fs.readFileSync(path.join(root, 'Daymark.xcodeproj/project.pbxproj'), 'utf8');
let lines = 0;
function checkSwiftDelimiters(source, file) {
  let i = 0;
  const pairs = { '(': ')', '[': ']', '{': '}' };
  function string() {
    i++;
    while (i < source.length) {
      if (source[i] === '\\') {
        if (source[i + 1] === '(') { i += 2; code(')'); }
        else i += 2;
      } else if (source[i++] === '"') return;
    }
    throw new Error(`${file}: unclosed string`);
  }
  function code(end = null) {
    while (i < source.length) {
      if (source.startsWith('//', i)) { const next = source.indexOf('\n', i); i = next < 0 ? source.length : next + 1; continue; }
      if (source.startsWith('/*', i)) {
        i += 2; let level = 1;
        while (i < source.length && level) {
          if (source.startsWith('/*', i)) { level++; i += 2; }
          else if (source.startsWith('*/', i)) { level--; i += 2; } else i++;
        }
        assert.equal(level, 0, `${file}: unterminated comment`); continue;
      }
      const c = source[i];
      if (c === '"') { string(); continue; }
      if (pairs[c]) { i++; code(pairs[c]); continue; }
      if (')]}'.includes(c)) { assert.equal(c, end, `${file}: unmatched ${c} at ${i}`); i++; return; }
      i++;
    }
    assert.equal(end, null, `${file}: missing ${end}`);
  }
  code();
}
for (const file of swift) {
  const source = fs.readFileSync(file, 'utf8');
  checkSwiftDelimiters(source, path.relative(root, file));
  lines += source.split('\n').length;
  assert(!/\b(TODO|FIXME|fatalError)\b/.test(source), `${file}: unfinished/crashing stub`);
  const relative = file.includes('DaymarkTests') ? path.basename(file) : path.relative(path.join(root, 'Daymark'), file).replaceAll('\\', '/');
  assert(project.includes(JSON.stringify(relative)), `${relative} missing from Xcode project`);
}
for (const file of all.filter(x => x.endsWith('.json'))) JSON.parse(fs.readFileSync(file, 'utf8'));
const objectIDs = [...project.matchAll(/^\t\t"([A-F0-9]{24})" = \{/gm)].map(x => x[1]);
assert.equal(new Set(objectIDs).size, objectIDs.length, 'Duplicate PBX objects');
for (const match of project.matchAll(/= "([A-F0-9]{24})";/g)) assert(objectIDs.includes(match[1]), `Unresolved PBX reference ${match[1]}`);
const png = fs.readFileSync(path.join(root, 'Daymark/Assets.xcassets/AppIcon.appiconset/AppIcon.png'));
assert.equal(png.subarray(1, 4).toString(), 'PNG');
assert.equal(png.readUInt32BE(16), 1024); assert.equal(png.readUInt32BE(20), 1024);
assert.equal(png[25], 2, 'App icon must use opaque RGB');
assert(project.includes('"IPHONEOS_DEPLOYMENT_TARGET" = "17.0"'));
const schemaSource = fs.readFileSync(path.join(root, 'Daymark/DaymarkApp.swift'), 'utf8');
const models = swift.filter(x => !x.includes('Tests')).flatMap(file => [...fs.readFileSync(file, 'utf8').matchAll(/@Model final class (\w+)/g)].map(x => x[1]));
for (const model of models) assert(schemaSource.includes(`${model}.self`), `${model} not registered in persistent schema`);
const testCount = swift.filter(x => x.includes('Tests')).reduce((n, file) => n + [...fs.readFileSync(file, 'utf8').matchAll(/func test\w+\(/g)].length, 0);
console.log(`PASS: ${swift.length} Swift files, ${lines} lines, balanced lexical delimiters, all source references, ${objectIDs.length} PBX objects, ${models.length} registered models, JSON assets, opaque 1024px icon.`);
console.log(`${testCount} XCTest cases included; NOT EXECUTED here. Swift type checking and native UI checks require Xcode.`);
