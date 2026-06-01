/** Shape of the wizard/config.json file loaded at runtime. */
export interface WizardConfig {
  target?: 'stremio' | 'nuvio';
  account?: { mode: 'create' | 'signin' };
  addonDetailsFilename?: string;
  instances: {
    aiostreams: string[];
    aiometadata: string[];
    watchly?: string[];
  };
  templates?: {
    aiostreams?: string;
    aiometadata_stremio?: string;
    aiometadata_nuvio?: string;
    collections?: string;
    nuvio_settings?: string;
  };
  /** Optional CORS proxy base URL (e.g. "https://proxy.numb3rs.stream"). Prefixed to AIOStreams API calls. */
  proxyBase?: string;
}

// Default fallback instances, only used if bundled config.json is somehow missing.
export const INSTANCES: WizardConfig['instances'] = {
  aiostreams: ['https://aiostreamsfortheweebsstable.midnightignite.me'],
  aiometadata: ['https://aiometadata.viren070.me'],
};

// Raw GitHub URLs for templates (fetched at runtime, not bundled because files are too large to bundle)
export const TEMPLATE_URLS = {
  aiostreams:           'https://raw.githubusercontent.com/luckynumb3rs/stremio-perfect-setup/refs/heads/main/templates/AIOStreams.json',
  aiometadataStremio:   'https://raw.githubusercontent.com/luckynumb3rs/stremio-perfect-setup/refs/heads/main/templates/AIOMetadata.json',
  aiometadataNuvio:     'https://raw.githubusercontent.com/luckynumb3rs/stremio-perfect-setup/refs/heads/main/templates/AIOMetadata-All.json',
  collections:          'https://raw.githubusercontent.com/luckynumb3rs/stremio-perfect-setup/refs/heads/main/templates/Nuvio-Collections.json',
  nuvioSettings:        'https://raw.githubusercontent.com/luckynumb3rs/stremio-perfect-setup/refs/heads/main/templates/Nuvio-Settings.json',
} as const;

export const RPDB_FREE_KEY = 't0-free-rpdb';

// Stremio maximum enabled catalogs: the instance's /api/config may return a specific value,
// but 120 is a safe conservative default from community documentation.
export const STREMIO_MAX_CATALOGS = 120;
