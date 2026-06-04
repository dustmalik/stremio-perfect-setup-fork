// Comprehensive resolution coverage: verifies that the WHOLE template config maps to a
// valid resolved config — including hardcoded values that aren't selectable wizard options.
// Run: node --experimental-strip-types wizard/web/src/lib/config-coverage.mts
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
// @ts-ignore - JS engine
import { resolveTemplate } from '../../../core/template-engine.js';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..');
const load = (name: string) => JSON.parse(readFileSync(join(repoRoot, 'templates', name), 'utf8'));

let passed = 0, failed = 0;
const ok = (name: string, cond: boolean, detail = '') => {
  if (cond) { passed++; console.log(`  ✓ ${name}`); }
  else { failed++; console.error(`  ✗ ${name} — ${detail}`); }
};

const DIRECTIVE_KEYS = ['__if', '__switch', '__value', '__remove', '__flatten'];
const PLACEHOLDER_RE = /<(?:required_|optional_)?template_placeholder>/;
const hasInterp = (s: string) => s.includes('{{');
const isPlaceholder = (s: string) => PLACEHOLDER_RE.test(s);

// A node is "static" if it (and everything under it) is free of directives, interpolation
// and placeholders — i.e. a hardcoded value that must pass through unchanged.
function isStatic(node: unknown): boolean {
  if (typeof node === 'string') return !hasInterp(node) && !isPlaceholder(node);
  if (typeof node === 'number' || typeof node === 'boolean' || node === null) return true;
  if (Array.isArray(node)) return node.every(isStatic);
  if (node && typeof node === 'object') {
    const keys = Object.keys(node as object);
    if (keys.some((k) => DIRECTIVE_KEYS.includes(k))) return false;
    return keys.every((k) => isStatic((node as Record<string, unknown>)[k]));
  }
  return true;
}

// Top-level keys the engine deliberately rewrites post-resolution (not pure passthrough):
//  - services: enabled flag + credentials injected from the selected debrid services
//  - rpdbApiKey: overridden when the wizard collected an explicit RPDB key
// Their transforms are covered by the simulate tests, so exclude them from passthrough.
const ENGINE_REWRITTEN = new Set(['services', 'rpdbApiKey']);

// Collect [path, value] for every guaranteed-static leaf/array reachable without crossing a
// directive node. These MUST appear identically in the resolved output, for any inputs.
function collectStatic(node: unknown, path: string[], out: Array<[string[], unknown]>) {
  if (path.length === 1 && ENGINE_REWRITTEN.has(path[0])) return;
  if (Array.isArray(node)) {
    if (isStatic(node)) out.push([path, node]); // whole array passes through as a unit
    return; // arrays with dynamic items have unstable indices; skip (can't guarantee)
  }
  if (node && typeof node === 'object') {
    const keys = Object.keys(node as object);
    if (keys.some((k) => DIRECTIVE_KEYS.includes(k))) return; // dynamic subtree
    for (const k of keys) collectStatic((node as Record<string, unknown>)[k], [...path, k], out);
    return;
  }
  if (typeof node === 'string') { if (!hasInterp(node) && !isPlaceholder(node)) out.push([path, node]); return; }
  out.push([path, node]); // number | boolean | null
}

function getPath(obj: unknown, path: string[]): unknown {
  return path.reduce<any>((o, k) => (o == null ? undefined : o[k]), obj);
}

function deepLeak(node: unknown): string | null {
  if (typeof node === 'string') {
    if (hasInterp(node)) return `interpolation left: ${node.slice(0, 60)}`;
    if (isPlaceholder(node)) return `placeholder left: ${node}`;
    return null;
  }
  if (Array.isArray(node)) { for (const v of node) { const r = deepLeak(v); if (r) return r; } return null; }
  if (node && typeof node === 'object') {
    for (const k of Object.keys(node as object)) {
      if (DIRECTIVE_KEYS.includes(k)) return `directive key left: ${k}`;
      const r = deepLeak((node as Record<string, unknown>)[k]); if (r) return r;
    }
  }
  return null;
}

function verify(label: string, template: any, scenarios: Array<{ name: string; opts: any }>) {
  console.log(`\n# ${label}`);
  const statics: Array<[string[], unknown]> = [];
  collectStatic(template.config, [], statics);
  ok(`${label}: template has a substantial set of hardcoded values`, statics.length > 20, `found ${statics.length}`);

  for (const sc of scenarios) {
    const cfg: any = resolveTemplate(template, sc.opts);

    // 1. Every hardcoded (non-directive, non-interpolated) value survives verbatim.
    const missing = statics.filter(([p, v]) => JSON.stringify(getPath(cfg, p)) !== JSON.stringify(v));
    ok(`[${sc.name}] all ${statics.length} hardcoded values preserved verbatim`, missing.length === 0,
      missing.slice(0, 3).map(([p, v]) => `${p.join('.')}=${JSON.stringify(v)} -> ${JSON.stringify(getPath(cfg, p))}`).join(' | '));

    // 2. No unresolved artifacts anywhere in the output.
    const leak = deepLeak(cfg);
    ok(`[${sc.name}] no unresolved directive/placeholder/interpolation`, leak === null, leak ?? '');

    // 3. Output is a non-trivial object.
    ok(`[${sc.name}] resolved config is a non-empty object`, cfg && typeof cfg === 'object' && Object.keys(cfg).length > 5,
      `keys=${cfg && typeof cfg === 'object' ? Object.keys(cfg).length : 'n/a'}`);
  }
}

const tam = load('tam.json');
const aio = load('AIOStreams.json');

verify('AIOStreams.json', aio, [
  { name: 'P2P/defaults', opts: { inputs: {}, services: [], credentials: { tmdbApiKey: 'K', tmdbAccessToken: 'A', tvdbApiKey: 'V' } } },
  { name: 'Debrid/torbox', opts: { inputs: { anime: true, httpAddons: 'none' }, services: ['torbox'], credentials: { tmdbApiKey: 'K', tmdbAccessToken: 'A', tvdbApiKey: 'V' } } },
]);

verify('tam.json', tam, [
  { name: 'defaults/no-svc', opts: { inputs: {}, services: [], credentials: {} } },
  { name: 'extended+torbox', opts: { inputs: { coreFilter: 'extended', deviceExclude: ['4k'], misc: { addonName: 'My Addon' } }, services: ['torbox'], credentials: {} } },
  { name: 'addon-none', opts: { inputs: { misc: { addonName: 'none', addonLogo: 'none' } }, services: [], credentials: {} } },
]);

console.log(`\n${failed === 0 ? '✅' : '❌'} ${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);
