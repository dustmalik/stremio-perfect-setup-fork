import type { DebridServiceSelection } from '../store/wizard';

export const INSTANT_DEBRID_SERVICE_IDS = ['torbox', 'premiumize'] as const;
export type InstantDebridServiceId = typeof INSTANT_DEBRID_SERVICE_IDS[number];

/**
 * Returns a patch to deep-merge into the nuvioSettingsTemplate object (both
 * tv and mobile platforms) to enable Nuvio's native Instant Debrid integration.
 *
 * Returns null if no qualifying service has an API key entered.
 *
 * preferred_resolver_provider_id is set to the id of whichever qualifying
 * service appears first in the debridServices array (insertion order = selection order).
 */
export function buildInstantDebridSettingsPatch(
  debridServices: DebridServiceSelection[],
): Record<string, unknown> | null {
  const qualifying = debridServices.filter((d) =>
    (INSTANT_DEBRID_SERVICE_IDS as readonly string[]).includes(d.id),
  );

  if (qualifying.length === 0) return null;

  const debridSettingsPatch: Record<string, unknown> = {
    debrid_enabled: { type: 'boolean', value: true },
    preferred_resolver_provider_id: { type: 'string', value: qualifying[0].id },
  };

  let hasAnyKey = false;
  for (const service of qualifying) {
    const apiKey = (service.credentials?.['apiKey'] ?? '').trim();
    if (apiKey) {
      debridSettingsPatch[`${service.id}_api_key`] = { type: 'string', value: apiKey };
      hasAnyKey = true;
    }
  }

  if (!hasAnyKey) return null;

  const platformPatch = { features: { debrid_settings: debridSettingsPatch } };
  return { tv: platformPatch, mobile: platformPatch };
}
