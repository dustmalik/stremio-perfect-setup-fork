# Nuvio Instant Debrid — Wizard Feature Design

## Overview

Add an opt-in "Instant Debrid" toggle to the wizard's debrid step for Nuvio users. When enabled, the wizard injects Nuvio's native debrid integration keys into the user's Nuvio settings JSON and configures AIOStreams in P2P/HTTP-only mode (no debrid keys passed). Only TorBox and Premiumize are supported by Nuvio's Instant Debrid feature.

## Affected Files

| File | Change type |
|---|---|
| `wizard/web/src/lib/services.ts` | Add `supportsInstantDebrid?: boolean` to `Service` interface; mark torbox and premiumize |
| `wizard/web/src/lib/instantDebrid.ts` | **New** — constants + `buildInstantDebridSettingsPatch` helper |
| `wizard/web/src/store/wizard.ts` | Add `instantDebrid: boolean` state + `setInstantDebrid` action |
| `wizard/web/src/steps/KeysStep.tsx` | Render toggle card; disable non-qualifying service cards; adapt continue button label |
| `wizard/web/src/steps/InstallingStep.tsx` | When flag is on: empty aiostreams services/credentials; patch nuvioSettingsTemplate |

The orchestrator (`wizard/core/orchestrator.js`) and the Nuvio adapter are **not touched**.

## Service Metadata

```ts
// services.ts — Service interface
supportsInstantDebrid?: boolean;

// Entries updated:
{ id: 'torbox',    supportsInstantDebrid: true, ... }
{ id: 'premiumize', supportsInstantDebrid: true, ... }
```

`INSTANT_DEBRID_SERVICE_IDS` in `lib/instantDebrid.ts` derives from this — or is a typed constant `['torbox', 'premiumize']`.

## Store Changes (`wizard.ts`)

```ts
// New state field (top-level, not inside Credentials)
instantDebrid: boolean   // default: false

// New action
setInstantDebrid: (enabled: boolean) => void
```

Side effect of `setInstantDebrid(true)`: filters `credentials.debridServices` to keep only qualifying services (torbox, premiumize). This keeps the store self-consistent.

Side effect of `setInstantDebrid(false)`: no side effect on `debridServices` (cleared services are not restored).

`toggleDebridService` is unchanged — non-qualifying cards are simply not rendered as clickable in the UI when the toggle is on.

## New Helper: `lib/instantDebrid.ts`

```ts
export const INSTANT_DEBRID_SERVICE_IDS = ['torbox', 'premiumize'] as const;
export type InstantDebridServiceId = typeof INSTANT_DEBRID_SERVICE_IDS[number];

export function buildInstantDebridSettingsPatch(
  debridServices: DebridServiceSelection[]
): Record<string, unknown> | null
```

Logic:
1. Filter `debridServices` to qualifying services (in array order — first = first selected).
2. If none, return `null`.
3. Build `debridSettingsPatch`:
   - `debrid_enabled: { type: "boolean", value: true }`
   - For each qualifying service with a non-empty `apiKey` credential: `{serviceId}_api_key: { type: "string", value: apiKey }`
   - `preferred_resolver_provider_id: { type: "string", value: firstQualifyingService.id }`
4. Return a patch object covering both platforms:

```json
{
  "tv":     { "features": { "debrid_settings": { ...debridSettingsPatch } } },
  "mobile": { "features": { "debrid_settings": { ...debridSettingsPatch } } }
}
```

Returns `null` if no qualifying service has an API key entered.

## UI: `KeysStep.tsx`

### Toggle card visibility

Shown when: `wizardConfig`-resolved `target === 'nuvio'` AND `credentials.debridServices` contains at least one qualifying service (`torbox` or `premiumize`).

Hidden (and `instantDebrid` auto-reset to `false`) when: the last qualifying service is deselected. This is handled by a check inside the `toggleDebridService` call path in `KeysStep` — after the store action, if no qualifying service remains selected and `instantDebrid` is true, call `setInstantDebrid(false)`.

### Toggle card layout

- Positioned between the credentials panels and the Continue button
- Bordered card (`border: 1px solid var(--border)`, `borderRadius: 10px`, `background: var(--panel)`, same as credential panels)
- Header row: "⚡ Instant Debrid" label (left) + toggle checkbox (right)
- Warning notice below the toggle:

  > **This feature is still new.** It may deliver results slightly faster, but typically returns fewer and less well-organized streams than the standard mode. Unlike the standard mode, it does not definitively exclude P2P streams.

### Non-qualifying service cards when toggle is ON

Cards for non-qualifying services (everything except torbox and premiumize) receive:
- `opacity: 0.4`
- `pointerEvents: 'none'`
- `cursor: 'not-allowed'`

They cannot be clicked or selected. Qualifying cards remain fully interactive.

### Continue button

When `instantDebrid === true`: label → `"Continue with Instant Debrid"` (standard `KeyRound` icon).

When `instantDebrid === false`: unchanged from existing logic.

`getDebridContinueState` still governs the enabled/disabled state — the user must still enter valid credentials for all selected qualifying service(s).

## Data Flow: `InstallingStep.tsx`

When `target === 'nuvio'` AND `instantDebrid === true`:

1. **AIOStreams params**: override `services: []` and `serviceCredentials: {}` so AIOStreams is configured for P2P/HTTP only.
2. **Nuvio settings patch**: call `buildInstantDebridSettingsPatch(credentials.debridServices)`. If it returns a non-null patch (i.e. at least one qualifying service has an API key), deep-merge it into `nuvioSettingsTemplate` before passing to `runNuvioSetup`. If it returns `null` (no key entered for any qualifying service), proceed without patching — the Nuvio settings will not have `debrid_enabled` injected, which is effectively a no-op for instant debrid.
3. Pass the patched template as `nuvioSettingsTemplate` — the orchestrator processes it identically to a normal run.

Deep-merge is a minimal 3-line recursive helper inline in `InstallingStep` (no new dependency):
```ts
function deepMerge(base: Record<string, unknown>, patch: Record<string, unknown>): Record<string, unknown>
```
Only plain-object keys are recursed; scalar values are overwritten. Arrays are not present in the patch.

## Test Credentials

Nuvio test account: `testio2@testio.com` / `testiotestio`, profile **Bini**.
Use a stub API key value when verifying settings injection into the account.

## Constraints & Notes

- Qualifying services list is currently `['torbox', 'premiumize']`. Adding future services requires one entry in `services.ts` and updating `INSTANT_DEBRID_SERVICE_IDS`.
- `preferred_resolver_provider_id` is set to the `id` of whichever qualifying service appears first in `credentials.debridServices` (insertion order = selection order).
- If both torbox and premiumize are selected, both `torbox_api_key` and `premiumize_api_key` are injected; only one `preferred_resolver_provider_id` is written.
- The toggle is Nuvio-only. In Stremio mode it is never shown.
- The orchestrator is unchanged; this feature is entirely implemented in the frontend layer.
