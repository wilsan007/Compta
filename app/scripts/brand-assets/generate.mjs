/**
 * One-off generator for Onusuite brand imagery via the Black Forest Labs FLUX.2 API.
 *
 * This script runs locally only. The API key is never bundled into the client:
 * it is read from the environment (or app/.env, which is gitignored) and used
 * exclusively here, at authoring time.
 *
 * Usage:
 *   node scripts/brand-assets/generate.mjs                  # generate everything missing
 *   node scripts/brand-assets/generate.mjs --only=hero-geometric
 *   node scripts/brand-assets/generate.mjs --force          # regenerate existing files
 *   node scripts/brand-assets/generate.mjs --dry-run        # print the plan and exit
 *   node scripts/brand-assets/generate.mjs --validate-only  # re-check palette of files on disk
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import { ASSETS } from './prompts.mjs'
import { decodePng, validatePalette } from './palette.mjs'
import { remapToPalette } from './remap.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const APP_ROOT = resolve(HERE, '../..')
const OUTPUT_DIR = join(APP_ROOT, 'public/brand')
const REPORT_PATH = join(OUTPUT_DIR, 'generation-report.json')

const API_BASE = process.env.BFL_API_BASE || 'https://api.bfl.ai'
const POLL_INTERVAL_MS = 1500
const POLL_TIMEOUT_MS = 5 * 60 * 1000
const MAX_RETRIES = 5

const args = process.argv.slice(2)
const flags = {
  only: args.find((a) => a.startsWith('--only='))?.split('=')[1] ?? null,
  force: args.includes('--force'),
  dryRun: args.includes('--dry-run'),
  validateOnly: args.includes('--validate-only'),
  remapOnly: args.includes('--remap-only'),
}

function loadEnvFile() {
  const envPath = join(APP_ROOT, '.env')
  if (!existsSync(envPath)) return
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)
    if (!match) continue
    const [, key, rawValue] = match
    if (process.env[key]) continue
    process.env[key] = rawValue.replace(/^["']|["']$/g, '')
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms))
}

async function submit(asset, apiKey) {
  const endpoint = `${API_BASE}/v1/${asset.model}`
  const body = {
    prompt: asset.prompt,
    width: asset.width,
    height: asset.height,
    seed: asset.seed,
    output_format: 'png',
  }

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        accept: 'application/json',
        'x-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })

    if (response.status === 429) {
      const retryAfter = Number(response.headers.get('retry-after') ?? 5)
      const wait = retryAfter * 1000 * 2 ** attempt
      console.log(`    rate limited, waiting ${wait / 1000}s`)
      await sleep(wait)
      continue
    }

    const text = await response.text()
    if (!response.ok) {
      throw new Error(`${asset.model} returned HTTP ${response.status}: ${text.slice(0, 300)}`)
    }

    const data = JSON.parse(text)
    if (!data.polling_url) {
      throw new Error(`No polling_url in response: ${text.slice(0, 300)}`)
    }
    return data
  }

  throw new Error('Exceeded retry budget while submitting (rate limited)')
}

async function poll(pollingUrl, apiKey) {
  const deadline = Date.now() + POLL_TIMEOUT_MS

  while (Date.now() < deadline) {
    await sleep(POLL_INTERVAL_MS)

    const response = await fetch(pollingUrl, {
      headers: { accept: 'application/json', 'x-key': apiKey },
    })

    if (!response.ok) {
      throw new Error(`Polling failed with HTTP ${response.status}`)
    }

    const data = await response.json()

    if (data.status === 'Ready') return data.result
    if (data.status === 'Error' || data.status === 'Failed') {
      throw new Error(`Generation failed: ${JSON.stringify(data).slice(0, 300)}`)
    }
  }

  throw new Error('Timed out waiting for generation')
}

async function download(url, destination) {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`Download failed with HTTP ${response.status}`)
  const buffer = Buffer.from(await response.arrayBuffer())
  writeFileSync(destination, buffer)
  return buffer
}

function checkPalette(asset, buffer) {
  try {
    const png = decodePng(buffer)
    return validatePalette(png, {
      mode: asset.paletteMode,
      expect: asset.expect,
    })
  } catch (error) {
    return { ok: false, problems: [`palette check skipped: ${error.message}`], coverage: [], dominants: [] }
  }
}

function reportPalette(result) {
  for (const entry of result.coverage ?? []) {
    const verdict = entry.ok ? 'ok  ' : 'DRIFT'
    console.log(
      `    ${verdict} ${entry.name.padEnd(11)} target ${entry.expected}  closest ${entry.closest}  ΔE ${entry.deltaE.toFixed(1)}`
    )
  }
  for (const problem of result.problems ?? []) {
    console.log(`    ! ${problem}`)
  }
}

async function main() {
  loadEnvFile()

  const selected = flags.only ? ASSETS.filter((a) => a.id === flags.only) : ASSETS
  if (selected.length === 0) {
    console.error(`No asset matches --only=${flags.only}`)
    console.error(`Available: ${ASSETS.map((a) => a.id).join(', ')}`)
    process.exit(1)
  }

  mkdirSync(OUTPUT_DIR, { recursive: true })

  if (flags.dryRun) {
    console.log(`\nPlan (${selected.length} assets, output to public/brand/):\n`)
    for (const asset of selected) {
      console.log(`  ${asset.id}`)
      console.log(`    model      ${asset.model}  ${asset.width}x${asset.height}  seed ${asset.seed}`)
      console.log(`    palette    ${asset.paletteMode} (expects ${asset.expect.join(', ')})`)
      console.log(`    purpose    ${asset.description}`)
      console.log(`    prompt     ${asset.prompt.slice(0, 110)}...`)
      console.log('')
    }
    return
  }

  if (flags.validateOnly) {
    console.log('\nRe-validating palette of files already on disk:\n')
    for (const asset of selected) {
      const target = join(OUTPUT_DIR, asset.file)
      if (!existsSync(target)) {
        console.log(`  ${asset.id}: not generated yet`)
        continue
      }
      console.log(`  ${asset.id} (${asset.paletteMode})`)
      reportPalette(checkPalette(asset, readFileSync(target)))
      console.log('')
    }
    return
  }

  if (flags.remapOnly) {
    console.log('\nRemapping existing files to brand palette:\n')
    for (const asset of selected) {
      const target = join(OUTPUT_DIR, asset.file)
      if (!existsSync(target)) {
        console.log(`  ${asset.id}: not generated yet, skipping`)
        continue
      }
      if (asset.paletteMode !== 'strict') {
        console.log(`  ${asset.id}: loose mode, skipping (photographs are not remapped)`)
        continue
      }
      console.log(`  ${asset.id} (${asset.paletteMode})`)
      const before = checkPalette(asset, readFileSync(target))
      console.log('    before:')
      reportPalette(before)
      const stats = remapToPalette(target, target, asset.expect, { threshold: 25 })
      console.log(`    remapped ${(stats.remappedPixels / 1024).toFixed(0)}K pixels (${(stats.coverage * 100).toFixed(1)}%)`)
      const after = checkPalette(asset, readFileSync(target))
      console.log('    after:')
      reportPalette(after)
      console.log('')
    }
    return
  }

  const apiKey = process.env.BFL_API_KEY
  if (!apiKey) {
    console.error('ERROR: BFL_API_KEY is not set. Add it to app/.env (gitignored).')
    console.error('Do NOT hardcode the key in source, and never expose it with a VITE_ prefix.')
    process.exit(1)
  }

  const report = []
  let failures = 0

  for (const asset of selected) {
    const target = join(OUTPUT_DIR, asset.file)

    if (existsSync(target) && !flags.force) {
      console.log(`\n${asset.id}: already present, skipping (use --force to regenerate)`)
      continue
    }

    console.log(`\n${asset.id}  [${asset.model} ${asset.width}x${asset.height} seed ${asset.seed}]`)

    try {
      const started = Date.now()
      const { polling_url: pollingUrl } = await submit(asset, apiKey)
      const result = await poll(pollingUrl, apiKey)
      const buffer = await download(result.sample, target)
      const elapsed = ((Date.now() - started) / 1000).toFixed(1)

      console.log(`    generated in ${elapsed}s, ${(buffer.length / 1024).toFixed(0)} KB`)

      let palette = checkPalette(asset, buffer)
      reportPalette(palette)

      // Auto-remap strict-mode assets that drifted
      if (!palette.ok && asset.paletteMode === 'strict') {
        console.log('    remapping to brand palette (strict mode)...')
        const stats = remapToPalette(target, target, asset.expect, { threshold: 25 })
        console.log(`    remapped ${(stats.remappedPixels / 1024).toFixed(0)}K pixels (${(stats.coverage * 100).toFixed(1)}%)`)
        palette = checkPalette(asset, readFileSync(target))
        console.log('    palette after remap:')
        reportPalette(palette)
      }

      if (!palette.ok) failures++

      report.push({
        id: asset.id,
        file: `public/brand/${asset.file}`,
        model: asset.model,
        seed: result.seed ?? asset.seed,
        bytes: buffer.length,
        elapsedSeconds: Number(elapsed),
        paletteMode: asset.paletteMode,
        paletteOk: palette.ok,
        paletteProblems: palette.problems,
        paletteCoverage: palette.coverage,
        generatedAt: new Date().toISOString(),
      })
    } catch (error) {
      failures++
      console.error(`    FAILED: ${error.message}`)
      report.push({ id: asset.id, error: error.message, generatedAt: new Date().toISOString() })
    }
  }

  if (report.length > 0) {
    writeFileSync(REPORT_PATH, `${JSON.stringify(report, null, 2)}\n`)
    console.log(`\nReport written to public/brand/generation-report.json`)
  }

  console.log(
    failures === 0
      ? '\nAll requested assets generated and on-palette.'
      : `\n${failures} asset(s) need review — inspect the files before shipping them.`
  )
}

main().catch((error) => {
  console.error(`\nFatal: ${error.message}`)
  process.exit(1)
})
