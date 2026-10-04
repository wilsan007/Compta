import { readdirSync, readFileSync } from 'fs'
import { join } from 'path'

const LOCALES_DIR = join(process.cwd(), 'src/i18n/locales')
const LANGS = ['fr', 'en', 'ar']
let hasErrors = false

function getDeepKeys(obj, prefix = '') {
  const keys = []
  for (const [key, value] of Object.entries(obj)) {
    const fullKey = prefix ? `${prefix}.${key}` : key
    if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
      keys.push(...getDeepKeys(value, fullKey))
    } else {
      keys.push(fullKey)
    }
  }
  return keys.sort()
}

const namespaces = readdirSync(join(LOCALES_DIR, LANGS[0]))
  .filter(f => f.endsWith('.json'))
  .map(f => f.replace('.json', ''))

console.log(`\nChecking i18n key parity across ${LANGS.length} languages (${LANGS.join(', ')})`)
console.log(`Namespaces: ${namespaces.length} (${namespaces.join(', ')})\n`)

for (const ns of namespaces) {
  const keysByLang = {}
  for (const lang of LANGS) {
    const filePath = join(LOCALES_DIR, lang, `${ns}.json`)
    try {
      const content = JSON.parse(readFileSync(filePath, 'utf-8'))
      keysByLang[lang] = new Set(getDeepKeys(content))
    } catch {
      console.error(`  ✗ ${ns}: MISSING file for '${lang}'`)
      hasErrors = true
      continue
    }
  }

  const allKeys = new Set()
  for (const lang of LANGS) {
    if (keysByLang[lang]) {
      for (const k of keysByLang[lang]) allKeys.add(k)
    }
  }

  const missing = {}
  let nsHasError = false
  for (const lang of LANGS) {
    if (!keysByLang[lang]) continue
    for (const k of allKeys) {
      if (!keysByLang[lang].has(k)) {
        if (!missing[lang]) missing[lang] = []
        missing[lang].push(k)
        nsHasError = true
      }
    }
  }

  if (nsHasError) {
    hasErrors = true
    console.error(`  ✗ ${ns}:`)
    for (const lang of LANGS) {
      if (missing[lang]?.length) {
        console.error(`      ${lang} missing ${missing[lang].length} keys:`)
        for (const k of missing[lang].slice(0, 10)) {
          console.error(`        - ${k}`)
        }
        if (missing[lang].length > 10) {
          console.error(`        ... and ${missing[lang].length - 10} more`)
        }
      }
    }
  } else {
    const counts = LANGS.map(l => `${l}: ${keysByLang[l]?.size || 0}`).join(', ')
    console.log(`  ✓ ${ns} (${counts})`)
  }
}

console.log('')
if (hasErrors) {
  console.error('❌ i18n key parity check FAILED — some translations are missing')
  process.exit(1)
} else {
  console.log('✅ i18n key parity check PASSED — all languages have matching keys')
}
