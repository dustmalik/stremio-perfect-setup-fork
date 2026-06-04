import { createAiometadataAdapter } from '../core/adapters/aiometadata.js';

let passed = 0;
let failed = 0;

function ok(name, cond, detail = '') {
  if (cond) { passed++; console.log(`  ✓ ${name}`); }
  else { failed++; console.error(`  ✗ ${name}${detail ? ': ' + detail : ''}`); }
}

console.log('\n# AIOMetadata adapter — updateConfig');

// updateConfig POSTs with userUUID in body (in-place update)
{
  const originalFetch = globalThis.fetch;
  let capturedBody = null;
  globalThis.fetch = async (url, opts) => {
    capturedBody = JSON.parse(opts.body);
    return { ok: true, status: 200, async json() { return { userUUID: 'uuid-abc', installUrl: 'https://instance/stremio/uuid-abc/manifest.json', message: 'Configuration updated successfully' }; } };
  };
  try {
    const adapter = createAiometadataAdapter('https://aiometadata.example');
    const result = await adapter.updateConfig({ language: 'en-US', apiKeys: { tmdb: 'k' } }, 'pass123', 'uuid-abc');
    ok('updateConfig POSTs to /api/config/save', true);
    ok('updateConfig includes userUUID in request body', capturedBody?.userUUID === 'uuid-abc');
    ok('updateConfig includes password in request body', capturedBody?.password === 'pass123');
    ok('updateConfig includes config in request body', capturedBody?.config?.language === 'en-US');
    ok('updateConfig returns userUUID from response', result.userUUID === 'uuid-abc');
  } finally {
    globalThis.fetch = originalFetch;
  }
}

// updateConfig throws when password missing
{
  const adapter = createAiometadataAdapter('https://aiometadata.example');
  let thrown = null;
  try { await adapter.updateConfig({}, '', 'uuid'); } catch (err) { thrown = err; }
  ok('updateConfig throws when password is empty', thrown instanceof Error && thrown.message.includes('password is required'));
}

// updateConfig throws when userUUID missing
{
  const adapter = createAiometadataAdapter('https://aiometadata.example');
  let thrown = null;
  try { await adapter.updateConfig({}, 'pass', ''); } catch (err) { thrown = err; }
  ok('updateConfig throws when userUUID is empty', thrown instanceof Error && thrown.message.includes('userUUID is required'));
}

console.log('\n# AIOMetadata adapter — validateTokenId');

// validateTokenId POSTs to /api/oauth/token/info
{
  const originalFetch = globalThis.fetch;
  let capturedBody = null;
  globalThis.fetch = async (url, opts) => {
    capturedBody = JSON.parse(opts.body);
    ok('validateTokenId POSTs to /api/oauth/token/info', url.endsWith('/api/oauth/token/info'), url);
    return { ok: true, status: 200, async json() { return { provider: 'trakt', username: 'user1', status: 'valid' }; } };
  };
  try {
    const adapter = createAiometadataAdapter('https://aiometadata.example');
    const result = await adapter.validateTokenId('tok-id-xyz');
    ok('validateTokenId sends tokenId in body', capturedBody?.tokenId === 'tok-id-xyz');
    ok('validateTokenId returns provider from response', result.provider === 'trakt');
  } finally {
    globalThis.fetch = originalFetch;
  }
}

// validateTokenId throws on non-200
{
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: false, status: 404 });
  try {
    const adapter = createAiometadataAdapter('https://aiometadata.example');
    let thrown = null;
    try { await adapter.validateTokenId('bad-id'); } catch (err) { thrown = err; }
    ok('validateTokenId throws on 404 with paste guidance',
      thrown instanceof Error && thrown.message.includes('pasted the correct Token ID'),
      thrown instanceof Error ? thrown.message : String(thrown));
  } finally {
    globalThis.fetch = originalFetch;
  }
}

// validateTokenId throws when tokenId missing
{
  const adapter = createAiometadataAdapter('https://aiometadata.example');
  let thrown = null;
  try { await adapter.validateTokenId(''); } catch (err) { thrown = err; }
  ok('validateTokenId throws when tokenId is empty', thrown instanceof Error && thrown.message.includes('tokenId is required'));
}

console.log(`\n${failed === 0 ? '✅' : '❌'} ${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);
