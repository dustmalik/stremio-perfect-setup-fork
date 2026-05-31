import { WizardShell } from '../components/WizardShell';
import { NextButton } from '../components/NextButton';
import { MarkdownText } from '../components/MarkdownText';
import { useWizard } from '../store/wizard';
import { DEBRID_SERVICES, resolveLogoUrl } from '../lib/services';

export function DebridStep() {
  const { credentials, toggleDebridService, setDebridApiKey, nextStep } = useWizard();
  const { debridServices } = credentials;

  return (
    <WizardShell>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--text)', marginBottom: '0.35rem' }}>
        Debrid Service
      </h2>
      <MarkdownText
        text="A **Debrid service** is a paid tool that gives you instant access to fast, cached streams with no P2P throttling or legal risk. It dramatically improves streaming quality and reliability.\n\nSelect one or more services below and enter your API key for each. You can find your API key in each service's account or settings page. **Skip if you prefer free P2P/HTTP-only mode.**"
        style={{ color: 'var(--muted)', fontSize: '0.875rem', marginBottom: '1.25rem', lineHeight: 1.65 }}
      />

      <p style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--muted)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: '0.5rem' }}>
        Select services (you can pick multiple)
      </p>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '0.5rem', marginBottom: '1rem' }}>
        {DEBRID_SERVICES.map(s => {
          const selected = debridServices.some(d => d.id === s.id);
          const logoUrl = resolveLogoUrl(s.logo);
          return (
            <button
              key={s.id}
              onClick={() => toggleDebridService(s.id)}
              style={{
                padding: '0.6rem 0.4rem',
                border: `2px solid ${selected ? 'var(--accent)' : 'var(--border)'}`,
                borderRadius: '10px',
                background: selected ? 'var(--panel-2)' : 'var(--panel)',
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.35rem',
                cursor: 'pointer', transition: 'all 0.15s',
              }}
            >
              {logoUrl ? (
                <img src={logoUrl} alt={s.name} style={{ height: '24px', width: '100%', objectFit: 'contain' }} />
              ) : (
                <span style={{ fontWeight: 700, fontSize: '0.75rem', color: 'var(--muted)' }}>{s.name[0]}</span>
              )}
              <span style={{ fontSize: '0.7rem', fontWeight: 600, color: 'var(--text)', textAlign: 'center', lineHeight: 1.2 }}>{s.name}</span>
            </button>
          );
        })}
      </div>

      {/* API key inputs for each selected service */}
      {debridServices.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', marginBottom: '0.5rem' }}>
          <p style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--muted)', textTransform: 'uppercase', letterSpacing: '0.06em' }}>
            API Keys
          </p>
          {debridServices.map(d => {
            const service = DEBRID_SERVICES.find(s => s.id === d.id);
            return (
              <label key={d.id} style={{ display: 'block' }}>
                <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>
                  {service?.name} API Key
                </span>
                <input
                  type="password"
                  value={d.apiKey}
                  onChange={e => setDebridApiKey(d.id, e.target.value)}
                  placeholder={`Paste your ${service?.name} API key...`}
                  style={{
                    marginTop: '0.35rem', width: '100%',
                    border: '1px solid var(--border)', borderRadius: '8px',
                    padding: '0.5rem 0.75rem', fontSize: '0.875rem',
                    background: 'var(--panel)', color: 'var(--text)',
                    outline: 'none', boxSizing: 'border-box',
                  }}
                />
              </label>
            );
          })}
        </div>
      )}

      <NextButton
        onClick={nextStep}
        label={debridServices.length > 0 ? 'Save & Continue' : 'Skip - Use P2P/HTTP only'}
      />
    </WizardShell>
  );
}
