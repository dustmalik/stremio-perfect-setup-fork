# 🤖 Perfect Setup — Automation module

Guided web app that automates the manual steps in the guide: create/use a **Stremio** (later
**Nuvio**) account, build the **AIOStreams** / **AIOMetadata** / **Watchly** configs from the repo
templates, install everything in the right order, and hand back every credential created.

> **Status: Phase 1 (Stremio MVP) scaffold.** The template engine + Stremio + AIOStreams paths are
> implemented and unit-tested offline. AIOMetadata, Watchly, Nuvio, Trakt, and the Cloudflare
> Worker proxy are stubbed/flagged for later phases. See [`../AUTOMATION-PLAN.md`](../AUTOMATION-PLAN.md)
> and [`../API-NOTES.md`](../API-NOTES.md).

## Layout

```
automation/
  core/                    Template engine, catalog config, nuvio-collections, adapters, orchestrator
  web/                     Vite + React wizard (npm run dev / npm run build)
  assets/logos/            Mirrored service logos
  test/                    Node offline tests (no network needed)
  config.example.json      Instance URLs and default preferences
```

## Dev

```bash
# Core unit tests (no network)
node automation/test/template-engine.test.mjs
node automation/test/catalog-config.test.mjs

# Wizard dev server
cd automation/web && npm install && npm run dev
# → http://localhost:5173/stremio-perfect-setup/automator/

# Production build
cd automation/web && npm run build
```

## Why this design

- **The UI is generated from the template.** `templates/AIOStreams.json` carries a self-describing
  form schema in `metadata.inputs`. `schema-renderer.js` renders it and `template-engine.js`
  resolves the result — so **editing the template changes the interface automatically**, no UI code
  change needed.
- **AIOStreams has open CORS** (`Access-Control-Allow-Origin: *`, confirmed in upstream source), so
  the wizard can call it straight from GitHub Pages. **Stremio's `api.strem.io`** is browser-callable
  too and a single `addonCollectionSet` does install + ordering + Cinemeta clean-up (replacing
  Cinebye). Only **Trakt** strictly needs the Cloudflare Worker proxy (no CORS) — Phase 2.

## Roadmap (see AUTOMATION-PLAN.md §8)

- **Phase 1 (here):** Stremio account + AIOStreams create & install, dynamic form, credential summary.
- **Phase 2:** AIOMetadata save + install, Trakt device OAuth via Worker, Watchly, Watch Next.
- **Phase 3:** Nuvio (account/profiles/addons/collections), multi-instance Autopilot fallback.
- **Phase 4:** Resumability, error surfacing, local CLI mode, template-version compatibility guard.
