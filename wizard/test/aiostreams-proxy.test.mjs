import {
  createAioStreamsAdapter,
  createWithFallbacks,
  extractFailedManifestAddons,
  disableInternalAddons,
} from '../core/adapters/aiostreams.js';

const target = 'https://aiostreams.example/api/v1/user';

let passed = 0;
let failed = 0;

function ok(name, cond, detail = '') {
  if (cond) {
    passed++;
    console.log(`  ✓ ${name}`);
  } else {
    failed++;
    console.error(`  ✗ ${name}${detail ? ': ' + detail : ''}`);
  }
}

async function capturePostedUrl(proxyBase) {
  let postedUrl = '';
  globalThis.fetch = async (url) => {
    postedUrl = String(url);
    return {
      status: 201,
      async json() {
        return { data: { uuid: 'u', encryptedPassword: 'p' } };
      },
    };
  };

  const adapter = createAioStreamsAdapter('https://aiostreams.example', { proxyBase });
  await adapter.createConfig({
    template: { config: { services: [] }, metadata: { inputs: [] } },
    inputs: {},
    services: [],
    credentials: {},
    serviceCredentials: {},
    password: 'secret',
  });
  return postedUrl;
}

console.log('\n# AIOStreams proxy URL building');

ok(
  'plain proxyBase uses raw path target',
  await capturePostedUrl('https://proxy.numb3rs.stream') === target.replace('https://aiostreams.example', 'https://proxy.numb3rs.stream/https://aiostreams.example')
);

ok(
  'query proxyBase encodes target URL',
  await capturePostedUrl('https://proxy.example/?url=') === `https://proxy.example/?url=${encodeURIComponent(target)}`
);

ok(
  'raw placeholder proxyBase injects unencoded target',
  await capturePostedUrl('https://proxy.example/{url}') === `https://proxy.example/${target}`
);

ok(
  'encoded placeholder proxyBase injects encoded target',
  await capturePostedUrl('https://proxy.example/{url_encoded}') === `https://proxy.example/${encodeURIComponent(target)}`
);

console.log('\n# AIOStreams manifest failure helpers');
{
  const names = extractFailedManifestAddons('Failed to fetch manifest for Sootio. Failed to fetch manifest for HD Hub');
  ok('extractFailedManifestAddons finds all addon names', JSON.stringify(names) === JSON.stringify(['Sootio', 'HD Hub']));

  const config = {
    presets: [
      { type: 'torrentio', enabled: true, options: { name: 'Torrentio' } },
      { type: 'sootio', enabled: true, options: { name: 'Sootio' } },
    ],
  };
  const result = disableInternalAddons(config, ['Sootio']);
  ok('disableInternalAddons returns disabled name', JSON.stringify(result.disabledAddonNames) === JSON.stringify(['Sootio']));
  ok('disableInternalAddons flips matching preset off', result.config.presets[1].enabled === false);
  ok('disableInternalAddons leaves non-matching preset alone', result.config.presets[0].enabled === true);
  ok('disableInternalAddons does not mutate original config', config.presets[1].enabled === true);
}

console.log('\n# AIOStreams retries with broken internal addon disabled');
{
  let requestCount = 0;
  globalThis.fetch = async (url, options = {}) => {
    requestCount++;
    const { config } = JSON.parse(options.body);
    const sootio = config.presets.find((preset) => preset.options?.name === 'Sootio');
    const sootioEnabled = sootio?.enabled !== false;

    if (sootioEnabled) {
      return {
        status: 400,
        async json() {
          return { error: { message: 'Failed to fetch manifest for Sootio' } };
        },
        async text() {
          return 'Failed to fetch manifest for Sootio';
        },
      };
    }

    return {
      status: 201,
      async json() {
        return { data: { uuid: 'uuid-1', encryptedPassword: 'enc-1' } };
      },
    };
  };

  const retried = await createWithFallbacks(
    ['https://instance-a.example', 'https://instance-b.example'],
    {
      template: {
        metadata: { inputs: [] },
        config: {
          presets: [
            { type: 'torrentio', enabled: true, options: { name: 'Torrentio' } },
            { type: 'sootio', enabled: true, options: { name: 'Sootio' } },
          ],
        },
      },
      inputs: {},
      services: [],
      credentials: {},
      serviceCredentials: {},
      password: 'secret',
    }
  );

  ok('createWithFallbacks retries after disabling shared failed addon', requestCount === 3);
  ok('createWithFallbacks reports disabled internal addon', JSON.stringify(retried.disabledInternalAddons) === JSON.stringify(['Sootio']));
  ok(
    'createWithFallbacks returns retry warning',
    retried.retryWarnings.length === 1
      && retried.retryWarnings[0].includes('Sootio')
      && retried.retryWarnings[0].includes('Your account was created successfully')
      && retried.retryWarnings[0].includes('AIOStreams configuration')
  );
  ok('createWithFallbacks still returns a primary result', retried.primary?.manifestUrl === 'https://instance-a.example/stremio/uuid-1/enc-1/manifest.json');
}

console.log('\n# AIOStreams disables addon when the error appends an identifier to its name');
{
  // Real AIOStreams errors are "Failed to fetch manifest for <name> <identifier>: <reason>"
  // (getAddonName appends a displayIdentifier/identifier). The preset name is just "Comet",
  // so an exact-equality match against "Comet TorBox" would never disable it.
  const names = extractFailedManifestAddons('Failed to fetch manifest for Comet TorBox: fetch failed');
  ok('extractFailedManifestAddons captures name with identifier', JSON.stringify(names) === JSON.stringify(['Comet TorBox']));

  const config = {
    presets: [
      { type: 'comet', instanceId: 'com', enabled: true, options: { name: 'Comet' } },
      { type: 'torrentio', instanceId: 'tio', enabled: true, options: { name: 'Torrentio' } },
    ],
  };
  const result = disableInternalAddons(config, names);
  ok('disableInternalAddons matches preset despite appended identifier', JSON.stringify(result.disabledAddonNames) === JSON.stringify(['Comet']));
  ok('disableInternalAddons flips the identifier-suffixed preset off', result.config.presets[0].enabled === false);
}

console.log('\n# AIOStreams clears multiple broken addons across retry rounds');
{
  // fetchManifests uses Promise.all, so only ONE broken addon surfaces per attempt.
  // The wizard must keep disabling + retrying until the config is accepted.
  let requestCount = 0;
  globalThis.fetch = async (url, options = {}) => {
    requestCount++;
    const { config } = JSON.parse(options.body);
    const enabled = (name) => config.presets.find((p) => p.options?.name === name)?.enabled !== false;

    if (enabled('Comet')) {
      return {
        status: 400,
        async json() { return { error: { message: 'Failed to fetch manifest for Comet TorBox: fetch failed' } }; },
        async text() { return 'Failed to fetch manifest for Comet TorBox: fetch failed'; },
      };
    }
    if (enabled('HD Hub')) {
      return {
        status: 400,
        async json() { return { error: { message: 'Failed to fetch manifest for HD Hub: ETIMEDOUT' } }; },
        async text() { return 'Failed to fetch manifest for HD Hub: ETIMEDOUT'; },
      };
    }
    return {
      status: 201,
      async json() { return { data: { uuid: 'uuid-multi', encryptedPassword: 'enc-multi' } }; },
    };
  };

  const retried = await createWithFallbacks(
    ['https://only-instance.example'],
    {
      template: {
        metadata: { inputs: [] },
        config: {
          presets: [
            { type: 'comet', instanceId: 'com', enabled: true, options: { name: 'Comet' } },
            { type: 'hdhub', instanceId: 'hdh', enabled: true, options: { name: 'HD Hub' } },
            { type: 'torrentio', instanceId: 'tio', enabled: true, options: { name: 'Torrentio' } },
          ],
        },
      },
      inputs: {},
      services: [],
      credentials: {},
      serviceCredentials: {},
      password: 'secret',
    }
  );

  ok('createWithFallbacks retries until all broken addons are disabled', requestCount === 3);
  ok('createWithFallbacks reports every disabled addon', JSON.stringify(retried.disabledInternalAddons) === JSON.stringify(['Comet', 'HD Hub']));
  ok('createWithFallbacks succeeds after clearing broken addons', retried.primary?.manifestUrl === 'https://only-instance.example/stremio/uuid-multi/enc-multi/manifest.json');
}

console.log('\n# AIOStreams ignores opaque instance failures when other instances identify the broken addon');
{
  let requestCount = 0;
  globalThis.fetch = async (url, options = {}) => {
    requestCount++;
    const base = String(url).replace('/api/v1/user', '');
    const { config } = JSON.parse(options.body);
    const subtitlesEnabled = config.presets.find((preset) => preset.options?.name === 'OpenSubtitles V3 Pro')?.enabled !== false;

    if (base === 'https://instance-403-a.example') {
      return {
        status: 403,
        async json() { return {}; },
        async text() { return ''; },
      };
    }

    if (base === 'https://instance-400-a.example' && subtitlesEnabled) {
      return {
        status: 400,
        async json() {
          return { error: { message: 'Failed to fetch manifest for OpenSubtitles V3 Pro: 502 - Bad Gateway' } };
        },
        async text() {
          return 'Failed to fetch manifest for OpenSubtitles V3 Pro: 502 - Bad Gateway';
        },
      };
    }

    if (base === 'https://instance-403-b.example') {
      return {
        status: 403,
        async json() { return {}; },
        async text() { return ''; },
      };
    }

    if (base === 'https://instance-400-b.example' && subtitlesEnabled) {
      return {
        status: 400,
        async json() {
          return { error: { message: 'Failed to fetch manifest for OpenSubtitles V3 Pro: 502 - Bad Gateway' } };
        },
        async text() {
          return 'Failed to fetch manifest for OpenSubtitles V3 Pro: 502 - Bad Gateway';
        },
      };
    }

    return {
      status: 201,
      async json() {
        return { data: { uuid: 'uuid-opaque', encryptedPassword: 'enc-opaque' } };
      },
    };
  };

  const retried = await createWithFallbacks(
    [
      'https://instance-403-a.example',
      'https://instance-400-a.example',
      'https://instance-403-b.example',
      'https://instance-400-b.example',
    ],
    {
      template: {
        metadata: { inputs: [] },
        config: {
          presets: [
            { type: 'opensubtitlesv3pro', instanceId: 'osv3p', enabled: true, options: { name: 'OpenSubtitles V3 Pro' } },
            { type: 'torrentio', instanceId: 'tio', enabled: true, options: { name: 'Torrentio' } },
          ],
        },
      },
      inputs: {},
      services: [],
      credentials: {},
      serviceCredentials: {},
      password: 'secret',
    }
  );

  ok('createWithFallbacks retries after ignoring non-informative failures', requestCount === 6);
  ok(
    'createWithFallbacks disables the addon named by informative failures',
    JSON.stringify(retried.disabledInternalAddons) === JSON.stringify(['OpenSubtitles V3 Pro'])
  );
  ok(
    'createWithFallbacks succeeds once the shared broken addon is disabled',
    retried.primary?.manifestUrl === 'https://instance-400-a.example/stremio/uuid-opaque/enc-opaque/manifest.json'
  );
}

console.log('\n# AIOStreams stops after first successful instance');
{
  const seen = [];
  globalThis.fetch = async (url) => {
    seen.push(String(url));
    return {
      status: 201,
      async json() {
        return { data: { uuid: 'uuid-stop', encryptedPassword: 'enc-stop' } };
      },
    };
  };

  const result = await createWithFallbacks(
    ['https://instance-a.example', 'https://instance-b.example'],
    {
      template: { metadata: { inputs: [] }, config: { presets: [] } },
      inputs: {},
      services: [],
      credentials: {},
      serviceCredentials: {},
      password: 'secret',
    }
  );

  ok('createWithFallbacks only posts to the first successful instance', seen.length === 1 && seen[0] === 'https://instance-a.example/api/v1/user');
  ok('createWithFallbacks returns the first successful manifest', result.primary?.manifestUrl === 'https://instance-a.example/stremio/uuid-stop/enc-stop/manifest.json');
}

console.log(`\n${failed === 0 ? '✅' : '❌'} ${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);
