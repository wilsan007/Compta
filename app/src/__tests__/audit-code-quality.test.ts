import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync, existsSync } from 'fs'
import { join } from 'path'

const SRC_DIR = join(process.cwd(), 'src')

function readSourceFiles(dir: string, ext: string[]): string[] {
  const results: string[] = []
  if (!existsSync(dir)) return results
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name)
    if (entry.isDirectory() && entry.name !== 'node_modules' && entry.name !== '__tests__') {
      results.push(...readSourceFiles(fullPath, ext))
    } else if (entry.isFile() && ext.some(e => entry.name.endsWith(e))) {
      if (!entry.name.includes('.test.') && !entry.name.includes('.spec.')) {
        results.push(fullPath)
      }
    }
  }
  return results
}

function readFileContent(path: string): string {
  return readFileSync(path, 'utf-8')
}

function getAllTsFiles(dir: string): string[] {
  return readSourceFiles(dir, ['.ts', '.tsx'])
}

const PAGES_DIR = join(SRC_DIR, 'pages')
const QUERIES_DIR = join(SRC_DIR, 'lib', 'queries')
const COMPONENTS_DIR = join(SRC_DIR, 'components')

describe('Audit Code Quality — Règles automatisées', () => {

  // ─── Règle 1: Pas de .eq('tenant_id', tid!) dans les queries ───
  describe('R1: Pas de tid! non-null assertions', () => {
    const queryFiles = getAllTsFiles(QUERIES_DIR)

    for (const file of queryFiles) {
      const relPath = file.replace(process.cwd() + '/', '')
      it(`${relPath}: 0 occurrence de .eq('tenant_id', tid!)`, () => {
        const content = readFileContent(file)
        const matches = content.match(/\.eq\(['"]tenant_id['"],\s*tid!\)/g)
        expect(matches, `Found ${matches?.length || 0} tid! assertions in ${relPath}`).toBeNull()
      })
    }
  })

  // ─── Règle 2: Pas de '€' hardcoded dans les pages ───
  describe('R2: Pas de symbole € hardcoded', () => {
    const pageFiles = getAllTsFiles(PAGES_DIR)

    for (const file of pageFiles) {
      const relPath = file.replace(process.cwd() + '/', '')
      it(`${relPath}: 0 symbole € (utiliser formatCurrency)`, () => {
        const content = readFileContent(file)
        // Exclure les commentaires et les imports
        const lines = content.split('\n')
        const euroLines = lines.filter(l =>
          l.includes('€') &&
          !l.trim().startsWith('//') &&
          !l.trim().startsWith('*') &&
          !l.includes('formatCurrency') &&
          !l.includes('import ')
        )
        expect(euroLines, `€ found in ${relPath}:\n${euroLines.join('\n')}`).toHaveLength(0)
      })
    }
  })

  // ─── Règle 3: Pas de '...' pour le saving state ───
  describe('R3: Pas de hardcoded "..." pour saving state', () => {
    const pageFiles = getAllTsFiles(PAGES_DIR)

    for (const file of pageFiles) {
      const relPath = file.replace(process.cwd() + '/', '')
      it(`${relPath}: 0 hardcoded "..." saving`, () => {
        const content = readFileContent(file)
        const matches = content.match(/saving\s*\?\s*['"]\.\.\.['"]/g)
        expect(matches, `Hardcoded "..." saving in ${relPath}`).toBeNull()
      })
    }
  })

  // ─── Règle 4: Pas de caractère ✕ dans les composants/pages ───
  describe('R4: Pas de caractère ✕ (utiliser X icon)', () => {
    const allFiles = [...getAllTsFiles(PAGES_DIR), ...getAllTsFiles(COMPONENTS_DIR)]

    for (const file of allFiles) {
      const relPath = file.replace(process.cwd() + '/', '')
      it(`${relPath}: 0 caractère ✕`, () => {
        const content = readFileContent(file)
        const lines = content.split('\n')
        const crossLines = lines.filter(l =>
          l.includes('✕') &&
          !l.trim().startsWith('//') &&
          !l.trim().startsWith('*')
        )
        expect(crossLines, `✕ found in ${relPath}`).toHaveLength(0)
      })
    }
  })

  // ─── Règle 5: Toutes les pages importent useTranslation ───
  describe('R5: Toutes les pages utilisent useTranslation', () => {
    const pageFiles = getAllTsFiles(PAGES_DIR)
    const pageComponents = pageFiles.filter(f => !f.includes('__tests__'))

    for (const file of pageComponents) {
      const relPath = file.replace(process.cwd() + '/', '')
      it(`${relPath}: importe useTranslation`, () => {
        const content = readFileContent(file)
        expect(content, `${relPath} does not import useTranslation`).toContain('useTranslation')
      })
    }
  })

  // ─── Règle 6: Pas de `as any` dans les pages ───
  describe('R6: Pas de `as any` dans les pages', () => {
    const pageFiles = getAllTsFiles(PAGES_DIR)

    for (const file of pageFiles) {
      const relPath = file.replace(process.cwd() + '/', '')
      it(`${relPath}: 0 cast as any`, () => {
        const content = readFileContent(file)
        const lines = content.split('\n')
        const asAnyLines = lines.filter(l =>
          l.includes('as any') &&
          !l.trim().startsWith('//') &&
          !l.trim().startsWith('*')
        )
        // Allow up to 0 occurrences
        expect(asAnyLines, `as any found in ${relPath}:\n${asAnyLines.join('\n')}`).toHaveLength(0)
      })
    }
  })

  // ─── Règle 7: i18n key parity (fr/en/ar) ───
  describe('R7: i18n key parity across fr/en/ar', () => {
    const LOCALES_DIR = join(SRC_DIR, 'i18n', 'locales')
    const LANGS = ['fr', 'en', 'ar']

    function getDeepKeys(obj: any, prefix = ''): string[] {
      const keys: string[] = []
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

    const namespaces = readdirSync(join(LOCALES_DIR, 'fr'))
      .filter((f: string) => f.endsWith('.json'))
      .map((f: string) => f.replace('.json', ''))

    for (const ns of namespaces) {
      it(`namespace "${ns}": fr/en/ar ont les mêmes clés`, () => {
        const keysByLang: Record<string, Set<string>> = {}
        for (const lang of LANGS) {
          const filePath = join(LOCALES_DIR, lang, `${ns}.json`)
          const content = JSON.parse(readFileSync(filePath, 'utf-8'))
          keysByLang[lang] = new Set(getDeepKeys(content))
        }

        const allKeys = new Set<string>()
        for (const lang of LANGS) {
          for (const k of keysByLang[lang]) allKeys.add(k)
        }

        for (const lang of LANGS) {
          const missing = [...allKeys].filter(k => !keysByLang[lang].has(k))
          expect(missing, `[${ns}] ${lang} missing ${missing.length} keys: ${missing.slice(0, 5).join(', ')}`).toHaveLength(0)
        }
      })
    }
  })
})
