// AIOStreams adapter: creates a stored user config on an instance and returns the manifest URL.
// Contract confirmed from Viren070/AIOStreams and internal API notes (§2).
//
// CORS note: all known community instances respond to OPTIONS /api/v1/user without
// Access-Control-Allow-Origin headers, causing browsers to block the preflight.
// The adapter supports an optional `proxyBase` parameter which, when set, prefixes
// the API URL so requests are relayed through a CORS-capable proxy
// (e.g. "https://proxy.numb3rs.stream" or a self-hosted worker).

import { resolveTemplate } from '../template-engine.js';

const API_VERSION = 'v1';

function normalizeBase(instanceUrl) {
  return instanceUrl.replace(/\/+$/, '');
}

function resolveConfigPayload({ template, inputs, services, credentials, serviceCredentials, configOverride }) {
  let config = resolveTemplate(template, { inputs, services, credentials, serviceCredentials });
  if (configOverride && typeof configOverride === 'object') {
    config = { ...config, ...configOverride };
  }
  return config;
}

function normalizeAddonName(value) {
  // Collapse runs of non-alphanumerics to single spaces (instead of stripping them) so we keep
  // word boundaries. This lets us tell "Comet" apart from "Comet TorBox": AIOStreams' real error
  // is "Failed to fetch manifest for <name> <identifier>" (getAddonName appends a
  // displayIdentifier/identifier), so the error name is the preset name plus a trailing label.
  return String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

// True when a preset name and an error-derived addon name refer to the same addon. They match when
// equal, or when one is a leading word-prefix of the other — covering the identifier AIOStreams
// appends to the preset name in manifest-failure errors (e.g. preset "Comet" vs error "Comet TorBox").
function addonNameMatches(presetName, targetName) {
  if (!presetName || !targetName) return false;
  if (presetName === targetName) return true;
  return targetName.startsWith(`${presetName} `) || presetName.startsWith(`${targetName} `);
}

export function extractFailedManifestAddons(message) {
  const text = String(message || '');
  const matches = text.matchAll(/Failed to fetch manifest for\s+(.+?)(?=[:.,\n]|$)/gi);
  const names = [];
  for (const match of matches) {
    const name = String(match[1] || '').trim().replace(/^["'`]+|["'`]+$/g, '');
    if (name) names.push(name);
  }
  return [...new Set(names)];
}

export function disableInternalAddons(config, addonNames) {
  if (!Array.isArray(config?.presets) || !Array.isArray(addonNames) || addonNames.length === 0) {
    return { config, disabledAddonNames: [] };
  }

  const targets = addonNames.map(normalizeAddonName).filter(Boolean);
  if (targets.length === 0) return { config, disabledAddonNames: [] };

  const nextConfig = structuredClone(config);
  const disabledAddonNames = [];

  for (const preset of nextConfig.presets) {
    const presetNames = [
      preset?.options?.name,
      preset?.name,
      preset?.type,
      preset?.instanceId,
    ].map(normalizeAddonName);

    if (!presetNames.some((name) => targets.some((target) => addonNameMatches(name, target)))) continue;
    if (preset.enabled === false) continue;

    preset.enabled = false;
    disabledAddonNames.push(preset?.options?.name || preset?.name || preset?.type || preset?.instanceId);
  }

  return { config: nextConfig, disabledAddonNames: [...new Set(disabledAddonNames)] };
}

function sharedFailedManifestAddons(results) {
  const failures = results.filter((result) => !result.ok);
  if (failures.length === 0) return [];

  const informativeFailures = failures
    .map((failure) => {
      const names = extractFailedManifestAddons(failure.error);
      return names.length > 0 ? { failure, names } : null;
    })
    .filter(Boolean);

  if (informativeFailures.length === 0) return [];

  let intersection = null;
  for (const { names } of informativeFailures) {
    const current = new Set(names.map(normalizeAddonName).filter(Boolean));
    if (current.size === 0) return [];
    intersection = intersection === null
      ? current
      : new Set([...intersection].filter((name) => current.has(name)));
    if (intersection.size === 0) return [];
  }

  const canonical = new Map();
  for (const { names } of informativeFailures) {
    for (const name of names) {
      const normalized = normalizeAddonName(name);
      if (normalized && !canonical.has(normalized)) canonical.set(normalized, name);
    }
  }

  return [...intersection].map((name) => canonical.get(name) || name);
}

async function tryCreateUntilSuccess(instances, createAttempt) {
  const results = [];
  for (const instanceUrl of instances) {
    try {
      const success = { instanceUrl, ok: true, ...(await createAttempt(instanceUrl)) };
      results.push(success);
      return { primary: success, results };
    } catch (err) {
      results.push({ instanceUrl, ok: false, error: String(err.message || err) });
    }
  }
  return { primary: null, results };
}

/**
 * Build the final fetch URL, optionally routing through a CORS proxy.
 * proxyBase examples:
 *   ""                               → direct request (may fail due to CORS)
 *   "https://proxy.numb3rs.stream"   → append the raw target URL as a path
 *   "https://proxy.example/?url="    → append the encoded target URL as a query value
 *   "https://proxy.example/{url}"    → replace placeholder with the raw target URL
 *   "https://proxy.example/{url_encoded}" → replace placeholder with the encoded target URL
 */
function buildUrl(targetUrl, proxyBase) {
  if (!proxyBase) return targetUrl;
  const trimmed = proxyBase.replace(/\/+$/, '');
  if (trimmed.includes('{url_encoded}')) {
    return trimmed.replace('{url_encoded}', encodeURIComponent(targetUrl));
  }
  if (trimmed.includes('{url}')) {
    return trimmed.replace('{url}', targetUrl);
  }
  // Query-style proxies usually expect the target as an encoded value.
  if (trimmed.includes('?') || trimmed.endsWith('=')) {
    return trimmed + encodeURIComponent(targetUrl);
  }
  // Path-style proxies expect the raw target URL after the slash:
  // https://proxy.example/https://upstream.example/path
  return trimmed + '/' + targetUrl;
}

export function createAioStreamsAdapter(instanceUrl, { proxyBase = '' } = {}) {
  const base = normalizeBase(instanceUrl);
  return {
    base,
    async saveConfig({ config, password, addonPassword }) {
      const headers = { 'content-type': 'application/json' };
      if (addonPassword) headers['x-aiostreams-addon-password'] = addonPassword;

      const apiUrl = buildUrl(`${base}/api/${API_VERSION}/user`, proxyBase);

      let res;
      try {
        res = await fetch(apiUrl, {
          method: 'POST',
          headers,
          body: JSON.stringify({ config, password }),
        });
      } catch (err) {
        const message = String(err?.message || err);
        const isCors = /Failed to fetch|NetworkError|Load failed|CORS/i.test(message);
        if (isCors) {
          throw new Error(
            `[CORS] AIOStreams at ${base} is unreachable from your browser, this is a CORS issue. ` +
            `The instance is online and reachable, but its server does not send the ` +
            `Access-Control-Allow-Origin header required for browser requests. ` +
            `To work around this, set a CORS proxy URL in config.json under "proxyBase" ` +
            `(e.g. "https://proxy.numb3rs.stream") and rebuild the wizard.`
          );
        }
        throw new Error(`AIOStreams ${base}: network error: ${message}`);
      }
      if (res.status !== 201) {
        let detail = '';
        try { detail = (await res.json())?.error?.message || ''; } catch { /* ignore */ }
        if (!detail) detail = await res.text().catch(() => '');
        throw new Error(
          `AIOStreams ${base}: configuration rejected by the server (HTTP ${res.status}).` +
          (detail ? ` Details: ${detail.slice(0, 300)}` : '')
        );
      }
      const body = await res.json();
      const data = body.data || body;
      const { uuid, encryptedPassword } = data;
      if (!uuid || !encryptedPassword) throw new Error(`AIOStreams ${base}: server returned an incomplete response (missing uuid or encryptedPassword)`);
      return {
        uuid,
        encryptedPassword,
        password,
        manifestUrl: `${base}/stremio/${uuid}/${encryptedPassword}/manifest.json`,
      };
    },
    /**
     * Resolve the repo template with the user's inputs + credentials, store it, return identifiers.
     * @returns {Promise<{uuid, encryptedPassword, manifestUrl, password}>}
     */
    async createConfig({ template, inputs, services, credentials, serviceCredentials, password, addonPassword, configOverride }) {
      const config = resolveConfigPayload({ template, inputs, services, credentials, serviceCredentials, configOverride });
      return this.saveConfig({ config, password, addonPassword });
    },

    /** Verify an instance is reachable + lists templates (health probe). */
    async health() {
      const res = await fetch(`${base}/api/${API_VERSION}/health`).catch(() => null);
      return Boolean(res && res.ok);
    },
  };
}

// Try instances in order until one accepts the config. Later entries are fallbacks that are
// only attempted if earlier instances fail. params may include `proxyBase` for CORS proxy
// support and `_postResolveOverride` to patch the resolved config before POSTing
// (useful for testing without a TMDB key).
// One internal addon can fail per attempt (AIOStreams' fetchManifests uses Promise.all, so only
// the first rejection surfaces). Bound how many addons we're willing to disable across retry rounds
// so a misbehaving instance can't loop forever.
const MAX_DISABLE_ROUNDS = 12;

export async function createWithFallbacks(instances, params) {
  const { proxyBase, _postResolveOverride, ...createParams } = params;
  const configOverride = _postResolveOverride || undefined;
  let currentConfig = resolveConfigPayload({ ...createParams, configOverride });

  const createAttempt = async (instanceUrl, config) => {
    const adapter = createAioStreamsAdapter(instanceUrl, { proxyBase });
    return adapter.saveConfig({
      config,
      password: createParams.password,
      addonPassword: createParams.addonPassword,
    });
  };

  const disabledInternalAddons = [];
  const allResults = [];
  let primary = null;
  let results = [];

  // Keep disabling the internal addon that failed on every instance and retrying, until an
  // instance accepts the config or there is nothing left we can disable.
  for (let round = 0; round <= MAX_DISABLE_ROUNDS; round++) {
    const attempt = await tryCreateUntilSuccess(instances, (instanceUrl) => createAttempt(instanceUrl, currentConfig));
    results = attempt.results;
    allResults.push(...attempt.results);
    if (attempt.primary) { primary = attempt.primary; break; }

    const manifestAddons = sharedFailedManifestAddons(attempt.results);
    if (manifestAddons.length === 0) break;
    const { config: nextConfig, disabledAddonNames } = disableInternalAddons(currentConfig, manifestAddons);
    if (disabledAddonNames.length === 0) break;
    disabledInternalAddons.push(...disabledAddonNames);
    currentConfig = nextConfig;
  }

  const uniqueDisabled = [...new Set(disabledInternalAddons)];
  const retryWarnings = uniqueDisabled.length > 0
    ? [
        `AIOStreams disabled ${uniqueDisabled.join(', ')} because ${uniqueDisabled.length === 1 ? 'it was' : 'they were'} not reachable at the moment. Your account was created successfully and it is fine to continue using it. You can log in to the AIOStreams configuration later and try re-enabling ${uniqueDisabled.length === 1 ? 'it' : 'them'} manually, or leave ${uniqueDisabled.length === 1 ? 'it' : 'them'} disabled if you prefer.`,
      ]
    : [];

  if (!primary) {
    const allCors = results.every((r) => r.error?.includes('[CORS]'));
    const errors = results.map((r) => r.error?.replace('[CORS] ', '')).join('\n\n');
    if (allCors) {
      throw new Error(
        `[CORS_ALL] Unable to create your AIOStreams configuration, all ${results.length} instance${results.length !== 1 ? 's' : ''} ` +
        `blocked the browser request due to missing CORS headers.\n\n` +
        `This is a server-side configuration issue on the AIOStreams instances, not a problem with your setup. ` +
        `Your options are:\n` +
        `  • Ask the instance owner to enable CORS on their server.\n` +
        `  • Set "proxyBase" in config.json to route through a CORS proxy ` +
        `(e.g. "https://proxy.numb3rs.stream") and rebuild.\n` +
        `  • Use the AIOStreams web interface directly at the instance URL and paste your manifest URL into the wizard.`
      );
    }
    throw new Error(`All AIOStreams instances failed:\n\n${errors}`);
  }
  return { primary, all: allResults, disabledInternalAddons: uniqueDisabled, retryWarnings };
}
