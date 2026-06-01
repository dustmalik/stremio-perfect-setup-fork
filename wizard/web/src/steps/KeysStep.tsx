import type { CSSProperties } from 'react';
import { ArrowRight } from 'lucide-react';
import { WizardShell } from '../components/WizardShell';
import { NextButton } from '../components/NextButton';
import { MarkdownText } from '../components/MarkdownText';
import { useWizard } from '../store/wizard';
import { RPDB_FREE_KEY } from '../lib/constants';
import { getGuideAccountsUrl } from '../lib/site';
import { ACTIVE_KEY_SCREENS } from '../lib/keyScreens';
import { DEBRID_SERVICES, resolveLogoUrl } from '../lib/services';

interface Props { keyIndex: number; }

export function KeysStep({ keyIndex }: Props) {
  const screen = ACTIVE_KEY_SCREENS[keyIndex];
  const {
    credentials,
    setCredentials,
    toggleDebridService,
    setDebridApiKey,
    nextStep,
  } = useWizard();
  const guideAccountsUrl = getGuideAccountsUrl();

  if (!screen) { nextStep(); return null; }

  const isRequired = !screen.optional;
  const canContinue = !isRequired || (
    screen.id === 'tmdb'
      ? credentials.tmdbApiKey.trim().length > 10 && credentials.tmdbAccessToken.trim().length > 20
      : screen.id === 'tvdb'
        ? credentials.tvdbApiKey.trim().length > 0
        : true
  );
  const nextLabel = screen.id === 'debrid' && credentials.debridServices.length === 0
    ? 'Skip - Use P2P/HTTP only'
    : undefined;
  const showSkipButton = screen.optional && screen.id !== 'debrid';

  const inputStyle: CSSProperties = {
    width: '100%', border: '1px solid var(--border)', borderRadius: '8px',
    padding: '0.5rem 0.75rem', fontSize: '0.875rem',
    background: 'var(--panel)', color: 'var(--text)', outline: 'none', boxSizing: 'border-box',
  };

  return (
    <WizardShell>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--text)', marginBottom: '0.35rem' }}>
        {screen.title}
      </h2>
      <MarkdownText
        text={screen.description}
        style={{ color: 'var(--muted)', fontSize: '0.875rem', marginBottom: '1rem', lineHeight: 1.65 }}
      />

      <div style={{
        background: 'var(--panel-2)', border: '1px solid var(--border)',
        borderRadius: '10px', padding: '0.75rem 1rem', marginBottom: '1.25rem', fontSize: '0.875rem',
      }}>
        <div style={{ fontWeight: 600, color: 'var(--text)', marginBottom: '0.35rem' }}>👉 How to get it:</div>
        <MarkdownText text={screen.instruction} style={{ color: 'var(--muted)' }} />
      </div>

      <div className="wizard-notice" style={{ marginBottom: '1rem' }}>
        <div className="wizard-notice__title">ℹ️ Detailed Instructions</div>
        <div>
          For a longer walkthrough with screenshots and service-specific notes, go to
          {' '}
          <a href={guideAccountsUrl} target="_blank" rel="noopener noreferrer" className="guide-pill-link">
            📝 Accounts Preparation
          </a>
        </div>
      </div>

      {screen.id === 'debrid' && (
        <>
          <p style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--muted)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: '0.5rem' }}>
            Select services (you can pick multiple)
          </p>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(118px, 1fr))', gap: '0.5rem', marginBottom: '1rem' }}>
            {DEBRID_SERVICES.map((service) => {
              const selected = credentials.debridServices.some(d => d.id === service.id);
              const logoUrl = resolveLogoUrl(service.logo);
              return (
                <button
                  key={service.id}
                  type="button"
                  onClick={() => toggleDebridService(service.id)}
                  style={{
                    padding: '0.6rem 0.4rem',
                    border: `2px solid ${selected ? 'var(--accent)' : 'var(--border)'}`,
                    borderRadius: '10px',
                    background: selected ? 'var(--panel-2)' : 'var(--panel)',
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    gap: '0.35rem',
                    cursor: 'pointer',
                    transition: 'all 0.15s',
                  }}
                >
                  {logoUrl ? (
                    <img src={logoUrl} alt={service.name} style={{ height: '24px', width: '100%', objectFit: 'contain' }} />
                  ) : (
                    <span style={{ fontWeight: 700, fontSize: '0.75rem', color: 'var(--muted)' }}>{service.name[0]}</span>
                  )}
                  <span style={{ fontSize: '0.7rem', fontWeight: 600, color: 'var(--text)', textAlign: 'center', lineHeight: 1.2 }}>
                    {service.name}
                  </span>
                </button>
              );
            })}
          </div>

          {credentials.debridServices.length > 0 && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', marginBottom: '0.5rem' }}>
              <p style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--muted)', textTransform: 'uppercase', letterSpacing: '0.06em', margin: 0 }}>
                API Keys
              </p>
              {credentials.debridServices.map((debridService) => {
                const service = DEBRID_SERVICES.find(candidate => candidate.id === debridService.id);
                return (
                  <label key={debridService.id} style={{ display: 'block' }}>
                    <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>
                      {service?.name} API Key
                    </span>
                    <input
                      type="password"
                      value={debridService.apiKey}
                      onChange={e => setDebridApiKey(debridService.id, e.target.value)}
                      placeholder={`Paste your ${service?.name} API key...`}
                      style={{ ...inputStyle, marginTop: '0.35rem' }}
                    />
                  </label>
                );
              })}
            </div>
          )}
        </>
      )}

      {screen.id === 'tmdb' && (
        <>
          <label style={{ display: 'block', marginBottom: '0.75rem' }}>
            <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>
              API Key <span style={{ color: '#e53e3e' }}>*</span>
            </span>
            <input
              type="password"
              value={credentials.tmdbApiKey}
              onChange={e => setCredentials({ tmdbApiKey: e.target.value })}
              placeholder="Paste your short API key here..."
              style={{ ...inputStyle, marginTop: '0.35rem' }}
            />
          </label>
          <label style={{ display: 'block' }}>
            <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>
              API Read Access Token <span style={{ color: '#e53e3e' }}>*</span>
            </span>
            <input
              type="password"
              value={credentials.tmdbAccessToken}
              onChange={e => setCredentials({ tmdbAccessToken: e.target.value })}
              placeholder="Paste your long Read Access Token here..."
              style={{ ...inputStyle, marginTop: '0.35rem' }}
            />
          </label>
        </>
      )}

      {screen.id === 'tvdb' && (
        <label style={{ display: 'block' }}>
          <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>
            API Key <span style={{ color: '#e53e3e' }}>*</span>
          </span>
          <input
            type="password"
            value={credentials.tvdbApiKey}
            onChange={e => setCredentials({ tvdbApiKey: e.target.value })}
            placeholder="Paste your TVDB API key..."
            style={{ ...inputStyle, marginTop: '0.35rem' }}
          />
        </label>
      )}

      {screen.id === 'gemini' && (
        <label style={{ display: 'block' }}>
          <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>
            API Key
          </span>
          <input
            type="password"
            value={credentials.geminiApiKey}
            onChange={e => setCredentials({ geminiApiKey: e.target.value })}
            placeholder="Paste your Gemini API key..."
            style={{ ...inputStyle, marginTop: '0.35rem' }}
          />
        </label>
      )}

      {screen.id === 'rpdb' && (
        <label style={{ display: 'block' }}>
          <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>
            API Key
          </span>
          <input
            type="text"
            value={credentials.rpdbApiKey}
            onChange={e => setCredentials({ rpdbApiKey: e.target.value })}
            placeholder={RPDB_FREE_KEY}
            style={{ ...inputStyle, marginTop: '0.35rem', fontFamily: "'IBM Plex Mono', monospace" }}
          />
        </label>
      )}

      <NextButton onClick={nextStep} disabled={!canContinue} label={nextLabel} />
      {showSkipButton && (
        <button
          type="button"
          onClick={nextStep}
          style={{
            width: '100%',
            marginTop: '0.5rem',
            fontSize: '0.875rem',
            color: 'var(--muted)',
            background: 'none',
            border: 'none',
            cursor: 'pointer',
            padding: '0.35rem',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '0.35rem',
          }}
        >
          <ArrowRight size={14} />
          Skip for now
        </button>
      )}
    </WizardShell>
  );
}
