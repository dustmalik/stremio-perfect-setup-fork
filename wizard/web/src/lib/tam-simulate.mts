// Simulate wizard option selections and assert the resolved config matches what the
// template's conditionals dictate (for templates/tam.json + templates/AIOStreams.json).
// Run: node --experimental-strip-types wizard/web/src/lib/tam-simulate.mts
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
// @ts-ignore - JS engine
import { resolveTemplate } from '../../../core/template-engine.js';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..');
const tam = JSON.parse(readFileSync(join(repoRoot, 'templates', 'tam.json'), 'utf8'));
const aio = JSON.parse(readFileSync(join(repoRoot, 'templates', 'AIOStreams.json'), 'utf8'));

let passed = 0, failed = 0;
const ok = (name: string, cond: boolean, detail = '') => {
  if (cond) { passed++; console.log(`  ✓ ${name}`); }
  else { failed++; console.error(`  ✗ ${name} — ${detail}`); }
};
const eseStrings = (cfg: any): Set<string> =>
  new Set((cfg.excludedStreamExpressions ?? []).map((e: any) => e?.expression).filter(Boolean));

// Collect template-side expression strings gated by a specific __if (so assertions are
// derived from the template, not hardcoded).
const gatedExpr = (template: any, ifExpr: string): string[] =>
  (template.config.excludedStreamExpressions ?? [])
    .filter((e: any) => e?.__if === ifExpr)
    .map((e: any) => e.expression);

console.log('\n# tam.json — addon name/logo (__switch + interpolation)');
{
  const def: any = resolveTemplate(tam, { inputs: {}, services: [], credentials: {} });
  ok('default addonName seeds template default', def.addonName === 'AIOStreams', `got ${JSON.stringify(def.addonName)}`);
  ok('default addonLogo seeds template default', typeof def.addonLogo === 'string' && def.addonLogo.includes('Tam-Taro'), `got ${JSON.stringify(def.addonLogo)}`);

  const custom: any = resolveTemplate(tam, { inputs: { misc: { addonName: 'My Addon' } }, services: [], credentials: {} });
  ok('custom addonName flows through', custom.addonName === 'My Addon', `got ${JSON.stringify(custom.addonName)}`);

  const none: any = resolveTemplate(tam, { inputs: { misc: { addonName: 'none', addonLogo: 'none' } }, services: [], credentials: {} });
  ok('addonName "none" removes the key', !('addonName' in none), `got ${JSON.stringify(none.addonName)}`);
  ok('addonLogo "none" removes the key', !('addonLogo' in none), `got ${JSON.stringify(none.addonLogo)}`);
}

console.log('\n# tam.json — coreFilter (includes) gates excludedStreamExpressions');
{
  const extendedExprs = gatedExpr(tam, 'inputs.coreFilter includes extended');
  const standardExprs = gatedExpr(tam, 'inputs.coreFilter includes standard');
  ok('template has extended- and standard-gated expressions', extendedExprs.length > 0 && standardExprs.length > 0,
    `ext=${extendedExprs.length} std=${standardExprs.length}`);

  const std = eseStrings(resolveTemplate(tam, { inputs: { coreFilter: 'standard' }, services: [], credentials: {} }));
  const ext = eseStrings(resolveTemplate(tam, { inputs: { coreFilter: 'extended' }, services: [], credentials: {} }));

  ok('standard run keeps standard-gated expr', standardExprs.every((e) => std.has(e)));
  ok('standard run drops extended-gated expr', extendedExprs.every((e) => !std.has(e)));
  ok('extended run keeps extended-gated expr', extendedExprs.every((e) => ext.has(e)));
  ok('extended run drops standard-gated expr', standardExprs.every((e) => !ext.has(e)));
}

console.log('\n# tam.json — deviceExclude (multi-select includes) adds device exclusions');
{
  const no4kExprs = gatedExpr(tam, 'inputs.deviceExclude includes 4k');
  ok('template has a deviceExclude-4k-gated expression', no4kExprs.length > 0, `got ${no4kExprs.length}`);

  const without = eseStrings(resolveTemplate(tam, { inputs: { deviceExclude: [] }, services: [], credentials: {} }));
  const with4k = eseStrings(resolveTemplate(tam, { inputs: { deviceExclude: ['4k'] }, services: [], credentials: {} }));
  ok('no-4k exclusion absent when 4k not excluded', no4kExprs.every((e) => !without.has(e)));
  ok('no-4k exclusion present when 4k excluded', no4kExprs.every((e) => with4k.has(e)));
}

console.log('\n# tam.json — service selection injects/omits services where applicable');
{
  const p2p: any = resolveTemplate(tam, { inputs: {}, services: [], credentials: {} });
  const svc: any = resolveTemplate(tam, { inputs: {}, services: ['torbox'], credentials: {} });
  // tam.json manages services via presets/conditionals (no top-level services array),
  // so the two resolutions should differ somewhere driven by the services condition.
  ok('service vs no-service resolutions differ', JSON.stringify(p2p) !== JSON.stringify(svc));
  ok('both resolve clean (no directive/interp leak)',
    [p2p, svc].every((c) => { const j = JSON.stringify(c); return !j.includes('"__if"') && !j.includes('"__switch"') && !j.includes('{{inputs'); }));
}

console.log('\n# AIOStreams.json — reference scenarios (P2P vs Debrid)');
{
  const p2p: any = resolveTemplate(aio, {
    inputs: { formatterChoice: 'flat', languages: ['English'], languagesRequired: true, httpAddons: 'none', timeout: 5000 },
    services: [], credentials: { tmdbApiKey: 'K', tmdbAccessToken: 'A', tvdbApiKey: 'V' },
  });
  ok('P2P: no TorBox Search preset', !p2p.presets.some((p: any) => p.type === 'torbox-search'));
  ok('P2P: services all disabled', Array.isArray(p2p.services) && p2p.services.every((s: any) => s.enabled === false));
  ok('P2P: credentials injected', p2p.tmdbApiKey === 'K' && p2p.tvdbApiKey === 'V');
  ok('P2P: clean', (() => { const j = JSON.stringify(p2p); return !j.includes('"__if"') && !j.includes('{{inputs'); })());

  const debrid: any = resolveTemplate(aio, {
    inputs: { formatterChoice: 'color', languages: ['English', 'German'], httpAddons: 'none', timeout: 8000, anime: true },
    services: ['torbox'], credentials: { tmdbApiKey: 'K', tmdbAccessToken: 'A', tvdbApiKey: 'V' },
  });
  ok('Debrid: TorBox enabled', debrid.services.some((s: any) => s.id === 'torbox' && s.enabled === true));
  ok('Debrid: TorBox Search preset included', debrid.presets.some((p: any) => p.type === 'torbox-search'));
}

console.log(`\n${failed === 0 ? '✅' : '❌'} ${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);
