import { useEffect, useRef } from 'react';
import { useWizard } from './store/wizard';
import { buildAioSections } from './lib/aioSections';
import { Welcome } from './steps/Welcome';
import { AccountStep } from './steps/AccountStep';
import { KeysStep } from './steps/KeysStep';
import { AioSectionStep } from './steps/AioSectionStep';
import { CatalogStep } from './steps/CatalogStep';
import { InstallingStep } from './steps/InstallingStep';
import { DoneStep } from './steps/DoneStep';
import { TEMPLATE_URLS, type WizardConfig } from './lib/constants';
import {
  ACTIVE_KEY_SCREENS,
  AIO_SECTION_START_STEP,
  KEY_SCREEN_START_STEP,
  getCatalogStep,
  getInstallStep,
} from './lib/keyScreens';
import { WizardShell } from './components/WizardShell';
import { ensureAnalytics, getStepMeta, trackWizardStepView } from './lib/analytics';

// config.json is bundled at build time from the root wizard/config.json.
import bundledConfig from '../../config.json';

function StepRouter() {
  const { step, target, templates, aioSections, wizardConfig, setTemplates, setAioSections, setWizardConfig } = useWizard();
  const lastTrackedKeyRef = useRef('');

  useEffect(() => {
    // Apply config.json values into the store on first mount.
    if (!wizardConfig) {
      setWizardConfig(bundledConfig as WizardConfig);
    }

    if (templates) return;

    const cfg = bundledConfig as WizardConfig;
    const tplUrls = {
      aiostreams:         cfg.templates?.aiostreams          ?? TEMPLATE_URLS.aiostreams,
      aiometadataStremio: cfg.templates?.aiometadata_stremio ?? TEMPLATE_URLS.aiometadataStremio,
      collections:        cfg.templates?.collections          ?? TEMPLATE_URLS.collections,
      nuvioSettings:      cfg.templates?.nuvio_settings       ?? TEMPLATE_URLS.nuvioSettings,
    };

    Promise.all([
      fetch(tplUrls.aiostreams).then(r => r.json()),
      fetch(tplUrls.aiometadataStremio).then(r => r.json()),
      fetch(tplUrls.collections).then(r => r.json()),
      fetch(tplUrls.nuvioSettings).then(r => r.json()),
    ]).then(([aiostreams, aiometadata, collections, nuvioSettings]) => {
      setTemplates({ aiostreams, aiometadata, collections, nuvioSettings });
      setAioSections(buildAioSections(aiostreams));
    }).catch(console.error);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const effectiveTarget = target ?? wizardConfig?.target ?? null;
    const meta = getStepMeta(step, aioSections);
    if (!meta) return;

    const trackingKey = `${step}:${effectiveTarget ?? 'unknown'}:${meta.slug}`;
    if (lastTrackedKeyRef.current === trackingKey) return;

    lastTrackedKeyRef.current = trackingKey;
    ensureAnalytics();
    trackWizardStepView(step, effectiveTarget, aioSections);
  }, [aioSections, step, target, wizardConfig?.target]);

  const n = aioSections.length;
  const KEY_SCREEN_END_STEP = KEY_SCREEN_START_STEP + ACTIVE_KEY_SCREENS.length;
  const CATALOGS_STEP = getCatalogStep(n);
  const INSTALL_STEP = getInstallStep(n);

  // Fixed steps
  if (step === 0) return <Welcome />;
  if (step === 1) return <AccountStep />;
  if (step >= KEY_SCREEN_START_STEP && step < KEY_SCREEN_END_STEP) {
    return <KeysStep keyIndex={step - KEY_SCREEN_START_STEP} />;
  }

  if (step >= AIO_SECTION_START_STEP && step < AIO_SECTION_START_STEP + n) {
    return <AioSectionStep sectionIndex={step - AIO_SECTION_START_STEP} />;
  }

  if (step >= AIO_SECTION_START_STEP && n === 0) {
    return (
      <WizardShell>
        <p style={{ color: 'var(--muted)', fontSize: '0.875rem', textAlign: 'center', padding: '1rem 0' }}>
          Loading configuration...
        </p>
      </WizardShell>
    );
  }

  if (step === CATALOGS_STEP) return <CatalogStep />;
  if (step === INSTALL_STEP) return <InstallingStep />;
  return <DoneStep />;
}

export default function App() {
  return <StepRouter />;
}
