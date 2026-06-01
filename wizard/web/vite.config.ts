import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import fs from 'fs';
import path from 'path';

function loadGuideGa4Id() {
  const configPath = path.resolve(__dirname, '../../_config.yml');

  try {
    const raw = fs.readFileSync(configPath, 'utf8');
    const match = raw.match(/^google_analytics:\s*(.+)$/m);
    return match ? match[1].trim() : '';
  } catch {
    return '';
  }
}

export default defineConfig({
  plugins: [react()],
  base: './',
  build: { outDir: 'dist' },
  define: {
    __GUIDE_GA4_ID__: JSON.stringify(loadGuideGa4Id()),
  },
  resolve: {
    alias: {
      '@core': path.resolve(__dirname, '../core'),
    },
  },
  publicDir: 'public',
});
