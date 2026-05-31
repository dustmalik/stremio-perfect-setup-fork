import { Moon, Sun, ChevronRight, Check } from 'lucide-react';
import { useWizard } from '../store/wizard';
import { useTheme } from '../hooks/useTheme';
import { resolveLogoUrl } from '../lib/services';

const KEY_STEP_LABELS: Record<number, string> = {
  2: 'Debrid Service',
  3: 'TMDB API Keys',
  4: 'TVDB API Key',
  5: 'Gemini AI Key',
  6: 'RPDB Ratings',
};

interface Props {
  isOpen: boolean;
  onClose: () => void;
}

export function Sidebar({ isOpen, onClose }: Props) {
  const { step, maxReachedStep, aioSections, setStep } = useWizard();
  const { theme, toggle } = useTheme();

  const n = aioSections.length;
  const CATALOGS_STEP = 7 + n;
  const INSTALL_STEP  = 7 + n + 1;

  function goTo(s: number) {
    if (s <= maxReachedStep && s !== step) { setStep(s); onClose(); }
  }

  function cls(s: number) {
    const isDone = s < step;
    const isCurr = s === step;
    const isClickable = s <= maxReachedStep && s !== step;
    return [
      'nav-step',
      isCurr ? 'is-current' : '',
      isDone ? 'is-done' : '',
      isClickable ? 'is-clickable' : '',
    ].filter(Boolean).join(' ');
  }

  function StepIcon({ s }: { s: number }) {
    if (s < step) return <Check size={12} style={{ color: 'var(--accent)', flexShrink: 0 }} />;
    if (s === step) return <ChevronRight size={12} style={{ color: 'var(--accent)', flexShrink: 0 }} />;
    return <span style={{ width: '12px', height: '12px', borderRadius: '50%', border: '1px solid var(--border)', display: 'inline-block', flexShrink: 0 }} />;
  }

  const spsLogo = resolveLogoUrl('assets/logos/sps-logo.svg');

  return (
    <aside className={`wizard-sidebar ${isOpen ? 'nav-open' : ''}`}>
      {/* Header */}
      <div style={{ padding: '1.25rem 1rem', borderBottom: '1px solid var(--border)', flexShrink: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', marginBottom: '0.15rem' }}>
          {spsLogo && <img src={spsLogo} alt="" style={{ width: '26px', height: '26px', flexShrink: 0 }} />}
          <span style={{ fontWeight: 700, fontSize: '0.9rem', color: 'var(--text)' }}>Perfect Setup</span>
        </div>
        <p style={{ fontSize: '0.72rem', color: 'var(--muted)', margin: 0 }}>Automated Wizard</p>
      </div>

      {/* Nav */}
      <nav style={{ flex: 1, overflowY: 'auto', padding: '0.6rem 0.5rem' }}>
        {/* Welcome */}
        <button className={cls(0)} onClick={() => goTo(0)}>
          <StepIcon s={0} />
          <span>Welcome</span>
        </button>

        {/* Account */}
        <button className={cls(1)} onClick={() => goTo(1)}>
          <StepIcon s={1} />
          <span>Account Setup</span>
        </button>

        {/* Services & Keys section label */}
        <div style={{ marginTop: '0.6rem', marginBottom: '0.2rem', fontSize: '0.65rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: 'var(--muted)', padding: '0 0.65rem' }}>
          Services &amp; Keys
        </div>
        {[2, 3, 4, 5, 6].map(s => (
          <button key={s} className={`${cls(s)} is-sub`} onClick={() => goTo(s)}>
            <StepIcon s={s} />
            <span>{KEY_STEP_LABELS[s]}</span>
          </button>
        ))}

        {/* AIOStreams Config section label */}
        <div style={{ marginTop: '0.6rem', marginBottom: '0.2rem', fontSize: '0.65rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: 'var(--muted)', padding: '0 0.65rem' }}>
          AIOStreams Config
        </div>
        {n === 0 ? (
          <div style={{ fontSize: '0.78rem', color: 'var(--muted)', padding: '0.35rem 0.65rem', fontStyle: 'italic' }}>
            Loading...
          </div>
        ) : (
          aioSections.map((sec, i) => {
            const s = 7 + i;
            return (
              <button key={sec.id} className={`${cls(s)} is-sub`} onClick={() => goTo(s)}>
                <StepIcon s={s} />
                <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {sec.icon} {sec.title}
                </span>
              </button>
            );
          })
        )}

        {/* Catalogs */}
        <div style={{ marginTop: '0.6rem' }}>
          <button className={cls(CATALOGS_STEP)} onClick={() => goTo(CATALOGS_STEP)}>
            <StepIcon s={CATALOGS_STEP} />
            <span>Catalogs</span>
          </button>
          <button className={cls(INSTALL_STEP)} onClick={() => goTo(INSTALL_STEP)}>
            <StepIcon s={INSTALL_STEP} />
            <span>Install</span>
          </button>
        </div>
      </nav>

      {/* Footer */}
      <div style={{ padding: '0.65rem 0.75rem', borderTop: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '0.5rem', flexShrink: 0 }}>
        <span style={{ fontSize: '0.65rem', color: 'var(--muted)', lineHeight: 1.4 }}>
          Runs entirely in your browser. Credentials never stored.
        </span>
        <button
          onClick={toggle}
          title={theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
          style={{
            background: 'var(--panel-2)', border: '1px solid var(--border)',
            borderRadius: '8px', padding: '0.35rem', cursor: 'pointer', display: 'flex',
            alignItems: 'center', justifyContent: 'center', color: 'var(--muted)', flexShrink: 0,
          }}
        >
          {theme === 'dark' ? <Sun size={14} /> : <Moon size={14} />}
        </button>
      </div>
    </aside>
  );
}
