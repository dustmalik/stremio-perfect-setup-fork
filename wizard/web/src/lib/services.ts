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
  /** Direct link to the page where the user can find/generate their credentials. */
  credentialsUrl?: string;
  /** Optional override for the credentials helper button label. */
  credentialsUrlLabel?: string;
  credentialFields?: ServiceCredentialField[];
}

export interface ServiceCredentialField {
  id: string;
  label: string;
  placeholder: string;
  type?: 'password' | 'text' | 'email';
  required?: boolean;
}

export function resolveLogoUrl(logo?: string | null): string {
  if (!logo) return '';
  return resolveImageUrl(logo);
}

function apiKeyField(serviceName: string): ServiceCredentialField {
  return {
    id: 'apiKey',
    label: 'API Key',
    placeholder: `Paste your ${serviceName} API key...`,
    type: 'password',
    required: true,
  };
}

export const SERVICES: Service[] = [
  { id: 'torbox',          name: 'TorBox',         logo: 'services/torbox.svg',      isDebrid: true,  isUsenet: false, url: 'https://torbox.app/subscription?referral=6e80077e-c232-4b71-8914-5b87202b9577',      credentialsUrl: 'https://torbox.app/settings', credentialFields: [apiKeyField('TorBox')] },
  { id: 'realdebrid',     name: 'Real-Debrid',    logo: 'services/realdebrid.png',  isDebrid: true,  isUsenet: false, url: 'http://real-debrid.com/?id=8801126', credentialsUrl: 'https://real-debrid.com/apitoken', credentialFields: [apiKeyField('Real-Debrid')] },
  { id: 'alldebrid',      name: 'AllDebrid',      logo: 'services/alldebrid.png',   isDebrid: true,  isUsenet: false, url: 'https://alldebrid.com',   credentialsUrl: 'https://alldebrid.com/apikeys/', credentialFields: [apiKeyField('AllDebrid')] },
  { id: 'debridlink',     name: 'Debrid-Link',    logo: 'services/debridlink.svg',  isDebrid: true,  isUsenet: false, url: 'https://debrid-link.com', credentialsUrl: 'https://debrid-link.com/webapp/apikey', credentialFields: [apiKeyField('Debrid-Link')] },
  { id: 'premiumize',     name: 'Premiumize',     logo: 'services/premiumize.svg',  isDebrid: true,  isUsenet: false, url: 'https://premiumize.me',   credentialsUrl: 'https://www.premiumize.me/account', credentialFields: [apiKeyField('Premiumize')] },
  { id: 'easydebrid',     name: 'EasyDebrid',     logo: 'services/easydebrid.png',  isDebrid: true,  isUsenet: false, url: 'https://easydebrid.com',  credentialsUrl: 'https://paradise-cloud.com/dashboard/', credentialFields: [apiKeyField('EasyDebrid')] },
  { id: 'debrider',       name: 'Debrider',       logo: 'services/debrider.svg',    isDebrid: true,  isUsenet: false, url: 'https://debrider.app',    credentialsUrl: 'https://debrider.app/dashboard/account', credentialFields: [apiKeyField('Debrider')] },
  {
    id: 'pikpak',
    name: 'PikPak',
    logo: 'services/pikpak.png',
    isDebrid: true,
    isUsenet: false,
    url: 'https://mypikpak.com',
    credentialsUrl: 'https://mypikpak.com/drive/all',
    credentialsUrlLabel: 'Open Account Page',
    credentialFields: [
      { id: 'email', label: 'Email', placeholder: 'Enter your PikPak email...', type: 'email', required: true },
      { id: 'password', label: 'Password', placeholder: 'Enter your PikPak password...', type: 'password', required: true },
    ],
  },
  {
    id: 'offcloud',
    name: 'Offcloud',
    logo: 'services/offcloud.png',
    isDebrid: true,
    isUsenet: false,
    url: 'https://offcloud.com',
    credentialsUrl: 'https://offcloud.com/account',
    credentialsUrlLabel: 'Open Account Page',
    credentialFields: [
      apiKeyField('Offcloud'),
      { id: 'email', label: 'Email', placeholder: 'Enter your Offcloud email...', type: 'email', required: true },
      { id: 'password', label: 'Password', placeholder: 'Enter your Offcloud password...', type: 'password', required: true },
    ],
  },
  { id: 'seedr',          name: 'Seedr',          logo: 'services/seedr.png',       isDebrid: true,  isUsenet: false, url: 'https://seedr.cc',        credentialsUrl: 'https://www.seedr.cc/settings', credentialFields: [apiKeyField('Seedr')] },
  {
    id: 'putio',
    name: 'Put.io',
    logo: 'services/putio.svg',
    isDebrid: true,
    isUsenet: false,
    url: 'https://put.io',
    credentialsUrl: 'https://app.put.io/oauth',
    credentialsUrlLabel: 'Open OAuth Page',
    credentialFields: [
      { id: 'clientId', label: 'Client ID', placeholder: 'Paste your Put.io client ID...', type: 'password', required: true },
      { id: 'token', label: 'Token', placeholder: 'Paste your Put.io token...', type: 'password', required: true },
    ],
  },
  { id: 'easynews',       name: 'Easynews',       logo: 'services/easynews.png',    isDebrid: false, isUsenet: true  },
  { id: 'nzbdav',         name: 'NzbDAV',         logo: '',                         isDebrid: false, isUsenet: true  },
  { id: 'altmount',       name: 'AltMount',       logo: '',                         isDebrid: false, isUsenet: true  },
  { id: 'stremio_nntp',   name: 'Stremio NNTP',   logo: '',                         isDebrid: false, isUsenet: true  },
  { id: 'stremthru_newz', name: 'StremThru Newz', logo: '',                         isDebrid: false, isUsenet: true  },
];

export const DEBRID_SERVICES = SERVICES.filter(s => s.isDebrid);

export function getServiceById(id: string): Service | undefined {
  return SERVICES.find((service) => service.id === id);
}

export function getServiceCredentialFields(service?: Service | null): ServiceCredentialField[] {
  return service?.credentialFields?.length ? service.credentialFields : [];
}
