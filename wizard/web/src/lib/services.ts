/// <reference types="vite/client" />
import { resolveImageUrl } from './integration';

// All AIOStreams services with logo paths relative to the configured images base.

export interface Service {
  id: string;
  name: string;
  logo: string;
  isDebrid: boolean;
  isUsenet: boolean;
  /** Public website for the service (debrid providers), used for the "Create Account" link. */
  url?: string;
  /** Direct link to the page where the user can find/generate their API key. */
  apiKeyUrl?: string;
}

export function resolveLogoUrl(logo?: string | null): string {
  if (!logo) return '';
  return resolveImageUrl(logo);
}

export const SERVICES: Service[] = [
  { id: 'torbox',          name: 'TorBox',         logo: 'services/torbox.svg',      isDebrid: true,  isUsenet: false, url: 'https://torbox.app/subscription?referral=6e80077e-c232-4b71-8914-5b87202b9577',      apiKeyUrl: 'https://torbox.app/settings' },
  { id: 'realdebrid',     name: 'Real-Debrid',    logo: 'services/realdebrid.png',  isDebrid: true,  isUsenet: false, url: 'http://real-debrid.com/?id=8801126', apiKeyUrl: 'https://real-debrid.com/apitoken' },
  { id: 'alldebrid',      name: 'AllDebrid',      logo: 'services/alldebrid.png',   isDebrid: true,  isUsenet: false, url: 'https://alldebrid.com',   apiKeyUrl: 'https://alldebrid.com/apikeys/' },
  { id: 'debridlink',     name: 'Debrid-Link',    logo: 'services/debridlink.svg',  isDebrid: true,  isUsenet: false, url: 'https://debrid-link.com', apiKeyUrl: 'https://debrid-link.com/webapp/apikey' },
  { id: 'premiumize',     name: 'Premiumize',     logo: 'services/premiumize.svg',  isDebrid: true,  isUsenet: false, url: 'https://premiumize.me',   apiKeyUrl: 'https://www.premiumize.me/account' },
  { id: 'easydebrid',     name: 'EasyDebrid',     logo: 'services/easydebrid.png',  isDebrid: true,  isUsenet: false, url: 'https://easydebrid.com',  apiKeyUrl: 'https://paradise-cloud.com/dashboard/' },
  { id: 'debrider',       name: 'Debrider',       logo: 'services/debrider.svg',    isDebrid: true,  isUsenet: false, url: 'https://debrider.app',    apiKeyUrl: 'https://debrider.app/dashboard/account' },
  { id: 'pikpak',         name: 'PikPak',         logo: 'services/pikpak.png',      isDebrid: true,  isUsenet: false, url: 'https://mypikpak.com',    apiKeyUrl: 'https://mypikpak.com/drive/all' },
  { id: 'offcloud',       name: 'Offcloud',       logo: 'services/offcloud.png',    isDebrid: true,  isUsenet: false, url: 'https://offcloud.com',    apiKeyUrl: 'https://offcloud.com/account' },
  { id: 'seedr',          name: 'Seedr',          logo: 'services/seedr.png',       isDebrid: true,  isUsenet: false, url: 'https://seedr.cc',        apiKeyUrl: 'https://www.seedr.cc/settings' },
  { id: 'putio',          name: 'Put.io',         logo: 'services/putio.svg',       isDebrid: true,  isUsenet: false, url: 'https://put.io',          apiKeyUrl: 'https://app.put.io/oauth' },
  { id: 'easynews',       name: 'Easynews',       logo: 'services/easynews.png',    isDebrid: false, isUsenet: true  },
  { id: 'nzbdav',         name: 'NzbDAV',         logo: '',                         isDebrid: false, isUsenet: true  },
  { id: 'altmount',       name: 'AltMount',       logo: '',                         isDebrid: false, isUsenet: true  },
  { id: 'stremio_nntp',   name: 'Stremio NNTP',   logo: '',                         isDebrid: false, isUsenet: true  },
  { id: 'stremthru_newz', name: 'StremThru Newz', logo: '',                         isDebrid: false, isUsenet: true  },
];

export const DEBRID_SERVICES = SERVICES.filter(s => s.isDebrid);
