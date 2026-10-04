// X0 — suites « chemin de l'écran » : le vrai client Supabase contre PostgREST
// réel (voir src/__screen__/rig.ts). SANS le mock de src/test/setup.ts.
// Prérequis : base migrée, `node scripts/screen-rig/setup.mjs`, PostgREST et
// `node scripts/screen-rig/gateway.mjs` lancés.
import { defineConfig } from 'vitest/config'
import { BaseSequencer, type TestSpecification } from 'vitest/node'
import fs from 'fs'
import path from 'path'

const rigFile = process.env.SCREEN_RIG_FILE || path.resolve(__dirname, '.screen-rig/rig.json')
const rig = fs.existsSync(rigFile) ? JSON.parse(fs.readFileSync(rigFile, 'utf8')) : { anonKey: '' }

// Les scénarios s'enchaînent comme l'audit les a joués (01 → 14) : certains lisent
// l'état laissé par les précédents (comptes bancaires, factures, exercice).
class ByName extends BaseSequencer {
  async sort(files: TestSpecification[]) {
    return [...files].sort((a, b) => a.moduleId.localeCompare(b.moduleId))
  }
  async shard(files: TestSpecification[]) { return files }
}

export default defineConfig({
  resolve: { alias: { '@': path.resolve(__dirname, './src') } },
  test: {
    globals: true,
    environment: 'node',
    include: ['src/__screen__/*.screen.ts'],
    setupFiles: ['src/__screen__/setup.ts'],
    env: {
      VITE_SUPABASE_URL: process.env.SCREEN_GATEWAY_URL || 'http://localhost:54399',
      VITE_SUPABASE_PUBLISHABLE_KEY: rig.anonKey,
    },
    testTimeout: 120000,
    hookTimeout: 60000,
    fileParallelism: false,
    sequence: { shuffle: false, sequencer: ByName },
  },
})
