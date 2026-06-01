import { useEffect, useMemo, useState } from 'react';
import { Copy, Download, ExternalLink, Sparkles } from 'lucide-react';
import { WizardShell } from '../components/WizardShell';
import { useWizard } from '../store/wizard';
import { getGuideUrl } from '../lib/site';
import { trackWizardCompletion } from '../lib/analytics';

function toConfigureUrl(manifestUrl: string) {
  const [baseUrl, search = ''] = manifestUrl.split('?');
  const configureBase = baseUrl.endsWith('/manifest.json')
    ? `${baseUrl.slice(0, -'/manifest.json'.length)}/configure`
    : `${baseUrl.replace(/\/$/, '')}/configure`;
  return search ? `${configureBase}?${search}` : configureBase;
}

async function copyText(text: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.setAttribute('readonly', '');
  textarea.style.position = 'absolute';
  textarea.style.left = '-9999px';
  document.body.appendChild(textarea);
  textarea.select();
  document.execCommand('copy');
  document.body.removeChild(textarea);
}

export function DoneStep() {
  const {
    credentials,
    installResult,
    nuvioAccount,
    stremioAccount,
    target,
    wizardConfig,
  } = useWizard();
  const { aiostreams, aiometadata, addonPasswordSource, warnings, error } = installResult;
  const guideUrl = getGuideUrl();
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const isUsingAccountPassword = addonPasswordSource === 'account';
  const accountMode = target === 'nuvio' ? nuvioAccount.mode : stremioAccount.mode;
  const addonDetailsFilename = wizardConfig?.addonDetailsFilename ?? 'perfect-setup-addon-details.txt';

  const addons = useMemo(() => (
    [
      aiostreams
        ? {
            id: 'aiostreams',
            name: '📚 AIOStreams',
            uuid: aiostreams.uuid,
            password: aiostreams.password,
            manifestUrl: aiostreams.manifestUrl,
            configureUrl: toConfigureUrl(aiostreams.manifestUrl),
          }
        : null,
      aiometadata
        ? {
            id: 'aiometadata',
            name: '🔎 AIOMetadata',
            uuid: aiometadata.uuid,
            password: aiometadata.password,
            manifestUrl: aiometadata.manifestUrl,
            configureUrl: toConfigureUrl(aiometadata.manifestUrl),
          }
        : null,
    ].filter(Boolean)
  ), [aiostreams, aiometadata]) as Array<{
    id: string;
    name: string;
    uuid: string;
    password: string;
    manifestUrl: string;
    configureUrl: string;
  }>;

  async function handleManifestCopy(addonId: string, manifestUrl: string) {
    try {
      await copyText(manifestUrl);
      setCopiedKey(addonId);
      window.setTimeout(() => setCopiedKey(current => current === addonId ? null : current), 1800);
    } catch {
      setCopiedKey(null);
    }
  }

  useEffect(() => {
    if (error || !target) return;

    const runId = addons.map(addon => addon.uuid).filter(Boolean).join(':') || `${target}-setup`;

    trackWizardCompletion({
      accountMode,
      addonCount: addons.length,
      debridServiceCount: credentials.debridServices.length,
      runId,
      target,
    });
  }, [accountMode, addons, credentials.debridServices.length, error, target]);

  function handleDownload() {
    const lines = [
      'Stremio/Nuvio Perfect Setup - Add-on Details',
      '',
      ...addons.flatMap(addon => [
        `${addon.name}`,
        `UUID: ${addon.uuid}`,
        isUsingAccountPassword
          ? 'Password: same as your account password'
          : `Password: ${addon.password}`,
        `Manifest URL: ${addon.manifestUrl}`,
        `Configure URL: ${addon.configureUrl}`,
        '',
      ]),
    ];

    const blob = new Blob([lines.join('\n')], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = addonDetailsFilename;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url);
  }

  return (
    <WizardShell showBack={false}>
      {error ? (
        <>
          <h2 className="text-xl font-bold text-red-600 mb-2">Something went wrong 😕</h2>
          <p className="text-red-500 text-sm bg-red-50 rounded-lg p-3 mb-4">{error}</p>
          <p className="text-gray-500 text-sm">
            Check the error above and try again, or follow the{' '}
            <a href={guideUrl} target="_blank" rel="noopener noreferrer" className="guide-pill-link">
              manual guide
            </a>.
          </p>
        </>
      ) : (
        <>
          <div className="text-4xl mb-3 text-center">🎉</div>
          <h2 className="text-xl font-bold text-center mb-1">And now you're really done!</h2>
          <p className="text-gray-500 text-sm text-center mb-5">
            {target === 'stremio'
              ? 'Open Stremio and sign in. Your addons are installed and ready.'
              : 'Open Nuvio and sign in. Your addons and collections are ready.'}
          </p>

          {addons.length > 0 && (
            <>
              <div
                style={{
                  marginBottom: '0.85rem',
                  padding: '0.85rem 1rem',
                  borderRadius: '10px',
                  border: '1px solid var(--border)',
                  background: isUsingAccountPassword ? 'var(--panel-2)' : '#fff8e7',
                  color: 'var(--text)',
                  fontSize: '0.85rem',
                  lineHeight: 1.55,
                  textAlign: 'center',
                }}
              >
                {isUsingAccountPassword
                  ? `These add-ons use your ${target === 'stremio' ? 'Stremio' : 'Nuvio'} account password. You can change each add-on password later from its configuration page if you want.`
                  : `Your ${target === 'stremio' ? 'Stremio' : 'Nuvio'} account password was not accepted by the add-on configurations, so a stronger shared add-on password was generated and used for all add-ons below.`}
              </div>

              <button
                onClick={handleDownload}
                style={{
                  width: '100%',
                  marginBottom: '0.85rem',
                  padding: '0.75rem 1rem',
                  borderRadius: '10px',
                  border: '1px solid var(--border)',
                  background: 'var(--panel)',
                  color: 'var(--text)',
                  fontWeight: 600,
                  fontSize: '0.9rem',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '0.45rem',
                  cursor: 'pointer',
                }}
              >
                <Download size={16} />
                Download all add-on details
              </button>

              <div className="bg-gray-50 rounded-xl p-4 text-xs font-mono space-y-4 mb-4 border border-gray-200">
                <p className="font-sans font-semibold text-gray-700 text-sm mb-1">📋 Your credentials (save these!)</p>
                {addons.map((addon) => (
                  <div key={addon.id}>
                    <p className="font-sans font-semibold text-gray-700 text-sm mb-2">{addon.name}</p>
                    <p className="text-gray-500">
                      UUID: <span className="text-gray-800 select-all">{addon.uuid}</span>
                    </p>
                    {!isUsingAccountPassword && (
                      <p className="text-gray-500">
                        Password: <span className="text-gray-800 select-all">{addon.password}</span>
                      </p>
                    )}
                    <p className="text-gray-500" style={{ fontFamily: "'Space Grotesk', 'Avenir Next', 'Segoe UI', sans-serif" }}>
                      <a
                        href={addon.configureUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="guide-pill-link"
                      >
                        <span>Customize Addon</span>
                        <ExternalLink size={12} />
                      </a>
                    </p>
                    <p className="text-gray-500 break-all" style={{ marginTop: '0.35rem' }}>
                      <span>Manifest: </span>
                      <span className="text-accent select-all">{addon.manifestUrl}</span>
                      <button
                        onClick={() => handleManifestCopy(addon.id, addon.manifestUrl)}
                        type="button"
                        className="text-accent"
                        aria-label={`Copy ${addon.name} manifest URL`}
                        style={{
                          background: 'none',
                          border: 'none',
                          padding: 0,
                          marginLeft: '0.35rem',
                          cursor: 'pointer',
                          font: 'inherit',
                          display: 'inline-flex',
                          alignItems: 'center',
                          verticalAlign: 'middle',
                        }}
                      >
                        {copiedKey === addon.id ? <span>Copied</span> : <Copy size={12} />}
                      </button>
                    </p>
                  </div>
                ))}
              </div>
            </>
          )}

          {warnings.length > 0 && (
            <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-sm text-amber-700 mb-4">
              <p className="font-semibold mb-1">A few warnings:</p>
              {warnings.map((w, i) => <p key={i}>• {w}</p>)}
            </div>
          )}

          <div className="bg-purple-50 border border-purple-200 rounded-lg p-3 text-sm text-purple-700 mb-4 flex items-center gap-2">
            <Sparkles size={16} />
            <span><strong>Watchly</strong> (Netflix-like recommendations) coming soon!</span>
          </div>

        </>
      )}
    </WizardShell>
  );
}
