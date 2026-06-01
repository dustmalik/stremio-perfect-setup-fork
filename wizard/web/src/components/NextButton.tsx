import type { ReactNode } from 'react';
import { ArrowRight, Check, Save } from 'lucide-react';

interface Props {
  onClick: () => void;
  disabled?: boolean;
  label?: string;
  icon?: ReactNode;
}

function getDefaultIcon(label: string) {
  if (/finish/i.test(label)) return <Check size={16} />;
  if (/save/i.test(label)) return <Save size={16} />;
  return <ArrowRight size={16} />;
}

export function NextButton({ onClick, disabled = false, label = 'Continue', icon }: Props) {
  return (
    <button
      type="button"
      className="wizard-primary-btn"
      onClick={onClick}
      disabled={disabled}
      style={{
        width: '100%',
        marginTop: '1.5rem',
        padding: '0.75rem 1.5rem',
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.4rem',
      }}
    >
      <span>{label}</span>
      {icon ?? getDefaultIcon(label)}
    </button>
  );
}
