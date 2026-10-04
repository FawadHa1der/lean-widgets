// The exhaustive UX suite (BUILD-PLAN §8 with docs/TEST-PLAN-DELTAS.md applied). Run it with `npm run test:ux`
// (wraps the run in scripts/with-browser-lock.sh: one browser on the host at a time). Outputs: out/ux/<run>/.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from '@playwright/test';

const here = path.dirname(fileURLToPath(import.meta.url));
const SC = path.resolve(here, '../..');
if (!process.env.UX_RUN) process.env.UX_RUN = `run-${new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, '')}`;
const RUN_DIR = path.join(SC, 'out', 'ux', process.env.UX_RUN);

export default defineConfig({
  testDir: path.join(here, 'specs'),
  testMatch: /.*\.spec\.mjs$/,
  workers: 1,
  fullyParallel: false,
  retries: 0,
  forbidOnly: true, // a committed test.only would otherwise turn a subset into a "full-suite" run (docs audit r3)
  timeout: 45 * 60 * 1000,
  expect: { timeout: 30000, toHaveScreenshot: { maxDiffPixelRatio: 0.01, animations: 'disabled', caret: 'hide' } },
  outputDir: path.join(RUN_DIR, 'test-results'),
  // the headed sign-off (UX_HEADED_ALL=1) compares with its OWN baselines (__screenshots__/headed/): Chrome for Testing in a
  // window rasterises glyphs differently from chrome-headless-shell (final-gate lane: C13 hasse-view panel and the 390 px
  // gallery differed only in text anti-aliasing), so the headless baselines stay the verdict's
  snapshotPathTemplate: process.env.UX_HEADED_ALL === '1' ? path.join(here, '__screenshots__', 'headed', '{arg}{ext}') : path.join(here, '__screenshots__', '{arg}{ext}'),
  reporter: [['list'], ['json', { outputFile: path.join(RUN_DIR, 'report.json') }]],
  globalSetup: path.join(here, 'lib', 'global-setup.mjs'),
  globalTeardown: path.join(here, 'lib', 'global-teardown.mjs'),
  use: { trace: 'retain-on-failure', actionTimeout: 45000, navigationTimeout: 120000, launchOptions: { args: ['--enable-features=SharedArrayBuffer'] } },
  // UX_HEADED_ALL=1 (tests/ux/lib/qed64.mjs HEADED_ALL): the 'headed' project, every launch a real Chrome for Testing window
  projects: [{ name: process.env.UX_HEADED_ALL === '1' ? 'headed' : 'headless-shell' }],
});
