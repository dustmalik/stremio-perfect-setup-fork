import { useState } from 'react';
import { ArrowRight, Loader2, LogIn, UserPlus } from 'lucide-react';
import { WizardShell } from '../components/WizardShell';
import { MarkdownText } from '../components/MarkdownText';
import { useWizard } from '../store/wizard';

// @ts-ignore
import { createStremioAdapter } from '@core/adapters/stremio.js';
// @ts-ignore
import { createNuvioAdapter } from '@core/adapters/nuvio.js';

export function AccountStep() {
  const MIN_PASSWORD_LENGTHS = {
    stremio: {
      signin: 4,
      create: 8,
    },
    nuvio: {
      signin: 6,
      create: 8,
    },
  } as const;
  const { target, stremioAccount, nuvioAccount, setStremioAccount, setNuvioAccount, nextStep } = useWizard();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const account = target === 'stremio' ? stremioAccount : nuvioAccount;
  const appName = target === 'stremio' ? 'Stremio' : 'Nuvio';
  const isNuvio = target === 'nuvio';
  const nuvioProfiles = isNuvio ? (account.profiles ?? []) : [];
  const hasLoadedNuvioProfiles = isNuvio
    && account.mode === 'signin'
    && !!account.authToken
    && nuvioProfiles.length > 0;
  const minPasswordLength = MIN_PASSWORD_LENGTHS[target ?? 'stremio'][account.mode];

  const isValidEmail    = account.email.includes('@');
  const isValidPassword = account.password.length >= minPasswordLength;
  const isValidProfileName = !isNuvio || account.mode !== 'create' || !!account.profileName?.trim();
  const hasSelectedProfile = !hasLoadedNuvioProfiles || Number.isFinite(account.profileId);
  const canAttempt = isValidEmail && isValidPassword && isValidProfileName && hasSelectedProfile && !loading;

  function updateAccount(next: Partial<typeof account>) {
    if (target === 'stremio') {
      setStremioAccount({
        ...next,
        authKey: undefined,
        authError: undefined,
      });
      return;
    }

    setNuvioAccount({
      ...next,
      authToken: undefined,
      authError: undefined,
      profileId: undefined,
      profiles: [],
    });
  }

  async function handleContinue() {
    if (!canAttempt) return;

    if (isNuvio && account.mode === 'signin' && hasLoadedNuvioProfiles) {
      nextStep();
      return;
    }

    setLoading(true);
    setError('');
    try {
      if (target === 'stremio') {
        const adapter = createStremioAdapter();
        const auth = account.mode === 'create'
          ? await adapter.register(account.email, account.password)
          : await adapter.login(account.email, account.password);
        setStremioAccount({ authKey: auth.authKey });
      } else {
        const adapter = createNuvioAdapter();
        if (account.mode === 'create') {
          const auth = await adapter.signup(account.email, account.password);
          const profile = await adapter.createProfile(auth.token, {
            name: account.profileName?.trim() || 'Profile 1',
          });
          if (!profile) {
            throw new Error('Nuvio account was created, but the initial profile could not be created.');
          }
          setNuvioAccount({
            authToken: auth.token,
            profileId: profile.profile_index,
            profiles: [profile],
          });
        } else {
          const auth = await adapter.login(account.email, account.password);
          const profiles = await adapter.getProfiles(auth.token);
          if (!profiles.length) {
            throw new Error('Nuvio: no profiles found on this account. Create one in Nuvio first, then try again.');
          }

          const selectedProfileId = profiles.some(profile => profile.profile_index === account.profileId)
            ? account.profileId
            : profiles[0].profile_index;

          setNuvioAccount({
            authToken: auth.token,
            profiles,
            profileId: selectedProfileId,
          });
          return;
        }
      }
      nextStep();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      setError(msg);
    } finally {
      setLoading(false);
    }
  }

  const descKey = `${target ?? 'stremio'}-${account.mode}`;
  const descriptions: Record<string, string> = {
    'stremio-create': 'We will create a new Stremio account and install your addons automatically.',
    'stremio-signin': 'We will sign into your existing Stremio account and install your addons.',
    'nuvio-create':   'We will create a new Nuvio account, create its first profile, and install your addons automatically.',
    'nuvio-signin':   'We will sign into your existing Nuvio account, load its profiles, and install your addons and collections into the profile you choose.',
  };

  const inputStyle: React.CSSProperties = {
    marginTop: '0.35rem', width: '100%',
    border: '1px solid var(--border)', borderRadius: '8px',
    padding: '0.5rem 0.75rem', fontSize: '0.875rem',
    background: 'var(--panel)', color: 'var(--text)',
    outline: 'none', boxSizing: 'border-box',
  };

  return (
    <WizardShell>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--text)', marginBottom: '0.35rem' }}>
        Your {appName} Account
      </h2>
      <MarkdownText
        text={descriptions[descKey] ?? ''}
        style={{ color: 'var(--muted)', fontSize: '0.875rem', marginBottom: '1.25rem', lineHeight: 1.6 }}
      />

      <div className="wizard-notice" style={{ marginBottom: '1.25rem' }}>
        <div className="wizard-notice__title">🔒 Privacy</div>
        <div>
          No login credentials, API keys, or setup values are collected or stored by the wizard during this process.
          Everything runs locally in your browser.
        </div>
      </div>

      {/* Mode toggle */}
      <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1.25rem' }}>
        {(['create', 'signin'] as const).map(m => (
          <button
            key={m}
            type="button"
            className="wizard-hover-lift"
            onClick={() => { updateAccount({ mode: m }); setError(''); }}
            style={{
              padding: '0.7rem 1rem', borderRadius: '10px', fontSize: '0.875rem',
              fontWeight: 600, border: `1px solid ${account.mode === m ? 'var(--accent)' : 'var(--border)'}`,
              cursor: 'pointer', transition: 'all 0.15s',
              background: account.mode === m ? 'var(--accent)' : 'var(--panel-2)',
              color: account.mode === m ? '#fff' : 'var(--muted)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.45rem',
              flex: 1,
            }}
          >
            {m === 'create' ? <UserPlus size={15} /> : <LogIn size={15} />}
            {m === 'create' ? 'Create account' : 'Sign in'}
          </button>
        ))}
      </div>

      <label style={{ display: 'block', marginBottom: '0.75rem' }}>
        <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>Email address</span>
        <input
          type="email"
          value={account.email}
          onChange={e => { updateAccount({ email: e.target.value }); setError(''); }}
          placeholder="you@example.com"
          style={inputStyle}
        />
      </label>

      <label style={{ display: 'block', marginBottom: '0.5rem' }}>
        <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>
          Password
          <span style={{ fontWeight: 400, color: 'var(--muted)', fontSize: '0.8rem', marginLeft: '0.4rem' }}>(min. {minPasswordLength} characters)</span>
        </span>
        <input
          type="password"
          value={account.password}
          onChange={e => { updateAccount({ password: e.target.value }); setError(''); }}
          placeholder="Enter your password..."
          style={inputStyle}
        />
      </label>

      {isNuvio && account.mode === 'create' && (
        <label style={{ display: 'block', marginBottom: '0.5rem' }}>
          <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>Profile name</span>
          <input
            type="text"
            value={account.profileName ?? ''}
            onChange={e => { updateAccount({ profileName: e.target.value }); setError(''); }}
            placeholder="Profile 1"
            style={inputStyle}
          />
        </label>
      )}

      {hasLoadedNuvioProfiles && (
        <label style={{ display: 'block', marginBottom: '0.5rem' }}>
          <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--text)' }}>Profile</span>
          <select
            value={account.profileId ?? ''}
            onChange={e => { setNuvioAccount({ profileId: Number(e.target.value) }); setError(''); }}
            style={inputStyle}
          >
            {nuvioProfiles.map((profile) => (
              <option key={profile.profile_index} value={profile.profile_index}>
                {profile.name || `Profile ${profile.profile_index}`}
              </option>
            ))}
          </select>
          <p style={{ marginTop: '0.45rem', color: 'var(--muted)', fontSize: '0.78rem', lineHeight: 1.45 }}>
            The selected Nuvio profile will have its current addons replaced and its collections updated by the wizard.
          </p>
        </label>
      )}

      {error && (
        <div style={{
          background: '#fef2f2', border: '1px solid #fecaca', borderRadius: '8px',
          padding: '0.6rem 0.75rem', marginBottom: '0.5rem', fontSize: '0.8125rem', color: '#dc2626',
        }}>
          {error}
        </div>
      )}

      <button
        type="button"
        className="wizard-primary-btn"
        onClick={handleContinue}
        disabled={!canAttempt}
        style={{
          width: '100%',
          marginTop: '1.25rem',
          padding: '0.75rem 1.5rem',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: '0.5rem',
        }}
      >
        {loading && <Loader2 size={16} style={{ animation: 'spin 1s linear infinite' }} />}
        {!loading && <ArrowRight size={16} />}
        {loading
          ? (
            account.mode === 'create'
              ? 'Creating account...'
              : hasLoadedNuvioProfiles
              ? 'Continuing...'
              : isNuvio
              ? 'Loading profiles...'
              : 'Signing in...'
          )
          : hasLoadedNuvioProfiles
          ? 'Continue with profile'
          : 'Continue'
        }
      </button>
      <style>{`@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }`}</style>
    </WizardShell>
  );
}
