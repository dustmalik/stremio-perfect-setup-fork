import { useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Menu, X, ChevronLeft } from 'lucide-react';
import { Sidebar } from './Sidebar';
import { useWizard } from '../store/wizard';

const variants = {
  enter:  { opacity: 0, x: 30 },
  center: { opacity: 1, x: 0 },
  exit:   { opacity: 0, x: -30 },
};

interface Props {
  children: React.ReactNode;
  showBack?: boolean;
}

export function WizardShell({ children, showBack = true }: Props) {
  const { step, prevStep } = useWizard();
  const [navOpen, setNavOpen] = useState(false);

  return (
    <div className="wizard-layout">
      {/* Mobile top bar */}
      <div className="wizard-mobile-topbar">
        <button
          onClick={() => setNavOpen(o => !o)}
          style={{ color: 'var(--text)', background: 'none', border: 'none', cursor: 'pointer', display: 'flex', padding: '0.25rem' }}
        >
          {navOpen ? <X size={20} /> : <Menu size={20} />}
        </button>
        <span style={{ fontWeight: 700, fontSize: '0.9rem', color: 'var(--text)' }}>Perfect Setup Wizard</span>
      </div>

      {/* Sidebar */}
      <Sidebar isOpen={navOpen} onClose={() => setNavOpen(false)} />

      {/* Mobile backdrop */}
      {navOpen && (
        <div
          onClick={() => setNavOpen(false)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)', zIndex: 9 }}
        />
      )}

      {/* Main content area */}
      <main className="wizard-content">
        <div style={{ width: '100%', maxWidth: '560px' }}>
          <AnimatePresence mode="wait">
            <motion.div
              key={step}
              variants={variants}
              initial="enter"
              animate="center"
              exit="exit"
              transition={{ duration: 0.22, ease: 'easeInOut' }}
              style={{
                background: 'var(--panel)',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius)',
                boxShadow: 'var(--shadow)',
                padding: '2rem',
              }}
            >
              {children}
            </motion.div>
          </AnimatePresence>

          {showBack && step > 0 && (
            <button
              onClick={prevStep}
              style={{
                marginTop: '0.875rem', display: 'flex', alignItems: 'center', gap: '0.3rem',
                fontSize: '0.875rem', color: 'var(--muted)', background: 'none', border: 'none',
                cursor: 'pointer', padding: '0.25rem 0',
              }}
              onMouseOver={e => (e.currentTarget.style.color = 'var(--accent)')}
              onMouseOut={e => (e.currentTarget.style.color = 'var(--muted)')}
            >
              <ChevronLeft size={14} /> Back
            </button>
          )}
        </div>
      </main>
    </div>
  );
}
