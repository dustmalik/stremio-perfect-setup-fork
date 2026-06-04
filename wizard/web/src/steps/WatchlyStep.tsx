import { WizardShell } from '../components/WizardShell';
import { useWizard } from '../store/wizard';

export function WatchlyStep() {
  const { nextStep } = useWizard();
  return (
    <WizardShell>
      <p>Watchly step (placeholder)</p>
      <button onClick={nextStep}>Continue</button>
    </WizardShell>
  );
}
