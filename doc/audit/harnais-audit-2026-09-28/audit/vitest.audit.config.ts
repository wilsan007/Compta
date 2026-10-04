import { defineConfig } from 'vitest/config'
import path from 'path'
const APP = '/Users/awalehosman/Desktop/Projet Saas/compta/app'
export default defineConfig({
  root: APP,
  resolve: { alias: { '@': path.resolve(APP, './src') } },
  test: {
    globals: true,
    environment: 'node',
    include: [path.resolve(__dirname, '*.audit.ts')],
    testTimeout: 120000,
    hookTimeout: 60000,
    fileParallelism: false,
  },
})
