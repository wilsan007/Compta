#!/usr/bin/env node
/**
 * audit-silent-failures.mjs — Détecteur statique de failures silencieux
 *
 * Catégories détectées:
 *   1. EMPTY_CATCH       — catch {} / catch (e) {} sans traitement
 *   2. CONSOLE_ONLY_CATCH — catch qui ne fait que console.log/error (pas de toast, pas de rethrow)
 *   3. SWALLOWED_ERROR_RETURN — if (error) return null/[]/false/{} sans logger ni throw
 *   4. AS_ANY_CAST       — casts `as any` qui court-circuitent le typage
 *   5. FLOATING_PROMISE  — appels de fonctions async sans await (fire-and-forget non intentionnel)
 *   6. UNDEFINED_SPREAD  — spread de variable possiblement undefined/null
 *   7. MISSING_TENANT_FILTER — requêtes supabase .from() sur tables tenant sans .eq('tenant_id')
 *   8. UNCHECKED_SUPABASE — déstructuration { data } sans vérifier error
 *   9. OPTIONAL_CHAIN_SWALLOW — ?. qui masque une erreur (ex: await x?.() retourne undefined silencieusement)
 *  10. CATCH_RETURN_DEFAULT — catch qui retourne une valeur par défaut sans logger
 *
 * Usage:
 *   node scripts/audit-silent-failures.mjs [--json] [--severity error|warning|all]
 *
 * Exit 1 si au moins une catégorie "error" a des findings.
 */

import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(__dirname, '..')

// ---------- Configuration ----------
const SCAN_DIRS = [
  'src',
  'supabase/functions',
]
const EXCLUDE_PATTERNS = [
  /node_modules/,
  /\.test\./,
  /\.spec\./,
  /__tests__\//,
  /\/test\//,
  /\/dist\//,
  /\/coverage\//,
  /\.d\.ts$/,
]

// Tables tenant-scoped (extraites de src/lib/supabase.ts TENANT_TABLES)
// On lit dynamiquement le fichier pour rester à jour.
function loadTenantTables() {
  const supabaseFile = path.join(ROOT, 'src/lib/supabase.ts')
  if (!fs.existsSync(supabaseFile)) return new Set()
  const content = fs.readFileSync(supabaseFile, 'utf8')
  const match = content.match(/TENANT_TABLES\s*=\s*new Set\(\[([\s\S]*?)\]\)/)
  if (!match) return new Set()
  const tables = new Set()
  const tableRegex = /'([a-z_]+)'/g
  let m
  while ((m = tableRegex.exec(match[1])) !== null) {
    tables.add(m[1])
  }
  return tables
}

const TENANT_TABLES = loadTenantTables()

// ---------- Helpers ----------
function shouldExclude(filePath) {
  return EXCLUDE_PATTERNS.some((p) => p.test(filePath))
}

function walkDir(dir) {
  const results = []
  if (!fs.existsSync(dir)) return results
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      results.push(...walkDir(full))
    } else if (/\.(ts|tsx|js|mjs)$/.test(entry.name)) {
      const rel = path.relative(ROOT, full)
      if (!shouldExclude(rel)) results.push(full)
    }
  }
  return results
}

function readLines(filePath) {
  return fs.readFileSync(filePath, 'utf8').split('\n')
}

// ---------- Detectors ----------

/**
 * 1. EMPTY_CATCH — catch {} ou catch (e) {} vide
 */
function detectEmptyCatch(lines, _filePath) {
  const findings = []
  // catch { } / catch (e) { } / catch (e: any) { } avec corps vide (potentiellement un commentaire)
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    // Match catch block opening then check if body is empty
    const catchMatch = line.match(/catch\s*(?:\(\s*\w*(?:\s*:\s*[^)]+)?\s*\))?\s*\{/)
    if (!catchMatch) continue
    // Look ahead for closing brace on same or next non-empty lines
    const afterBrace = line.slice(catchMatch.index + catchMatch[0].length)
    // Same-line close: } catch { }
    if (/^\s*\}\s*(?:finally\b.*)?$/.test(afterBrace) || /^\s*$/.test(afterBrace)) {
      // Check next lines until }
      if (/^\s*\}/.test(afterBrace)) {
        findings.push({ line: i + 1, code: line.trim(), severity: 'error' })
        continue
      }
      // Multi-line: check if body is empty (only comments/whitespace until })
      let j = i + 1
      let isEmpty = true
      while (j < lines.length && j < i + 10) {
        const next = lines[j].trim()
        if (next === '') { j++; continue }
        if (next.startsWith('//') || next.startsWith('/*') || next.startsWith('*')) { j++; continue }
        if (next.startsWith('}')) break
        isEmpty = false
        break
      }
      if (isEmpty) {
        findings.push({ line: i + 1, code: line.trim(), severity: 'error' })
      }
    }
  }
  return findings
}

/**
 * 2. CONSOLE_ONLY_CATCH — catch qui ne fait que console.* sans toast/throw/reportError
 */
function detectConsoleOnlyCatch(lines, _filePath) {
  const findings = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const catchMatch = line.match(/catch\s*(?:\(\s*\w*(?:\s*:\s*[^)]+)?\s*\))?\s*\{/)
    if (!catchMatch) continue
    // Collect body until matching }
    let depth = 1
    let bodyLines = []
    let j = i
    const afterBrace = line.slice(catchMatch.index + catchMatch[0].length)
    if (afterBrace.trim() && afterBrace.trim() !== '}') bodyLines.push(afterBrace)
    j = i + 1
    while (j < lines.length && depth > 0) {
      const l = lines[j]
      for (const ch of l) {
        if (ch === '{') depth++
        else if (ch === '}') depth--
        if (depth === 0) break
      }
      if (depth > 0 || (depth === 0 && l.trim() !== '}')) {
        bodyLines.push(l)
      }
      if (depth === 0) break
      j++
    }
    const body = bodyLines.join('\n')
    const hasConsole = /console\.(log|error|warn|info|debug)/.test(body)
    const hasToast = /toast\s*\(|showToast|setError|set_error|throw\b|reportError|Sentry\.|captureException|setError\b/.test(body)
    const hasReturn = /\breturn\b/.test(body)
    if (hasConsole && !hasToast) {
      // console + return is still swallowing if return is a default value
      const _isJustConsole = body.trim().startsWith('console.') || /^\s*console\./.test(body.trim())
      findings.push({
        line: i + 1,
        code: line.trim(),
        severity: 'warning',
        note: hasReturn ? 'console + return (erreur avalée avec fallback)' : 'console uniquement (pas de notification UI)',
      })
    }
  }
  return findings
}

/**
 * 3. SWALLOWED_ERROR_RETURN — if (error) return null/[]/false/{} sans logger ni throw
 */
function detectSwallowedErrorReturn(lines, _filePath) {
  const findings = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    // if (error) return null / [] / false / {} / '' / 0 / undefined
    const m = line.match(/if\s*\(\s*error\b[^)]*\)\s*return\s+(null|undefined|false|\[\]|\{\}|''|""|0)\s*;?\s*$/)
    if (m) {
      // Check if there's a console/throw on same line before
      const hasLog = /console\.|throw|Sentry\./.test(line)
      if (!hasLog) {
        findings.push({ line: i + 1, code: line.trim(), severity: 'error', note: `return ${m[1]} sans logger` })
      }
    }
    // if (err) return  / if (jeErr) return  (return sans valeur = undefined)
    const m2 = line.match(/if\s*\(\s*\w*[Ee]rr\w*\s*\)\s*return\s*;?\s*$/)
    if (m2 && !/console\.|throw|Sentry\./.test(line)) {
      findings.push({ line: i + 1, code: line.trim(), severity: 'error', note: 'return sans valeur' })
    }
  }
  return findings
}

/**
 * 4. AS_ANY_CAST — `as any` (surtout dans queries/logic, pas juste pages)
 */
function detectAsAny(lines, _filePath) {
  const findings = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    // Skip comments
    if (line.trim().startsWith('//')) continue
    const matches = [...line.matchAll(/\bas\s+any\b/g)]
    for (const _m of matches) {
      // Lower severity for test files already excluded; here all are non-test
      findings.push({ line: i + 1, code: line.trim(), severity: 'warning' })
    }
  }
  return findings
}

/**
 * 5. FLOATING_PROMISE — appel de fonction async sans await dans une fonction async
 *    Heuristique: ligne avec `someFunc(args)` où someFunc est connu async (getXxx, createXxx, etc.)
 *    et pas précédé de await, pas dans .then, pas dans return, pas assigné.
 */
const ASYNC_FUNC_PREFIXES = [
  'get', 'create', 'update', 'delete', 'save', 'fetch', 'load', 'submit', 'send',
  'generate', 'calculate', 'process', 'import', 'export', 'validate', 'verify',
  'release', 'apply', 'remove', 'close', 'open', 'start', 'stop', 'run', 'init',
]
function detectFloatingPromise(lines, filePath) {
  const findings = []
  // Only check .tsx pages/components and query files (where this matters most)
  if (!/src\/(pages|components|lib\/queries)\//.test(filePath)) return findings

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    // Skip comments, imports, type declarations, function declarations
    if (/^\s*(\/\/|\/\*|\*|import|export\s+type|interface|type\s)/.test(line)) continue
    // Skip function declarations: export async function foo(, export function foo(, function foo(
    if (/^\s*(export\s+)?(async\s+)?function\s+\w+\s*\(/.test(line)) continue
    // Look for function calls that look async: getXxx(...) without await
    // Pattern: word boundary + camelCase async name + ( ... ) not preceded by await/return/const/let/=/&&/||/?
    const callRegex = /\b([a-z][a-zA-Z]+)\s*\(/g
    let m
    while ((m = callRegex.exec(line)) !== null) {
      const name = m[1]
      // Must start with an async-ish prefix
      const startsWithAsyncPrefix = ASYNC_FUNC_PREFIXES.some(
        (p) => name.toLowerCase().startsWith(p) && name.length > p.length + 2
      )
      if (!startsWithAsyncPrefix) continue
      // Check what's before the call on the line
      const before = line.slice(0, m.index)
      // If preceded by await, return, =, ., `, ?, new, typeof → not floating
      if (/\b(await|return|typeof|new|void)\s*$/.test(before)) continue
      if (/[=.:?(&|!<>+\-*/]$/.test(before)) continue
      if (/\b(const|let|var)\s+\w+\s*=\s*$/.test(before)) continue
      // If the whole line is just the call (statement) → floating promise
      const afterCall = line.slice(m.index + m[0].length)
      // Must end the statement (closing paren + optional ; + end of line)
      if (/^\s*\)?\s*;?\s*$/.test(afterCall) || /^\s*\)?\s*;?\s*\/\/.*/.test(afterCall)) {
        // Exclude if it's inside a JSX expression (common in render)
        if (/src\/(pages|components)\//.test(filePath) && /jsx|tsx$/.test(filePath)) {
          // In tsx, a bare call on its own line in an async effect is suspicious but common
          // Only flag if NOT inside a try block (try blocks usually await)
        }
        findings.push({ line: i + 1, code: line.trim(), severity: 'warning', note: `${name}() non awaité` })
      }
    }
  }
  return findings
}

/**
 * 6. UNDEFINED_SPREAD — {...(maybeUndefined)} sans garde
 *    Pattern: ...(variable) où variable pourrait être undefined
 *    Heuristique: spread d'une variable qui n'est pas visiblement un objet/array literal
 */
function detectUndefinedSpread(lines, _filePath) {
  const findings = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (line.trim().startsWith('//')) continue
    // ...(someVar)  — spread of a bare identifier (could be undefined)
    // Exclude ...(condition ? a : b) and ...(literal) and ...(await ...)
    const matches = [...line.matchAll(/\.\.\.\(\s*([a-zA-Z_$][\w$]*)\s*\)/g)]
    for (const m of matches) {
      const varName = m[1]
      // If it's a known-safe pattern (e.g. ...(obj || {})) skip — but our regex already excludes || inside parens
      findings.push({ line: i + 1, code: line.trim(), severity: 'warning', note: `spread de ${varName} (possiblement undefined)` })
    }
    // ...(await fn()) is fine; ...(cond ? a : b) is fine
    // Also catch: ...data where data comes from supabase and might be null
    // { ...data, foo: 1 } where data could be null
    const spreadBare = [...line.matchAll(/\.\.\.([a-zA-Z_$][\w$]*)(?!\s*[?:])/g)]
    for (const m of spreadBare) {
      const varName = m[1]
      // Skip if preceded by ( (already handled above) or if it's a literal
      const before = line.slice(0, m.index)
      if (/\.\.\.\(\s*$/.test(before + m[0].slice(0, 3))) continue
      // Only flag if variable name suggests it comes from a destructure that could be null
      if (/^(data|result|res|response|item|row|record|entry|payload|body)$/.test(varName)) {
        findings.push({ line: i + 1, code: line.trim(), severity: 'info', note: `...${varName} — vérifier nullabilité` })
      }
    }
  }
  return findings
}

/**
 * 7. MISSING_TENANT_FILTER — supabase.from('table') sur table tenant sans .eq('tenant_id', ...)
 *    Détecte les chaînes .from('tenantTable').select/insert/update/delete qui n'ont pas
 *    .eq('tenant_id' ni tud( ni ti( helpers.
 */
function detectMissingTenantFilter(lines, _filePath) {
  const findings = []
  // Only in query files and pages where supabase is called directly
  const _fullText = lines.join('\n')
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const fromMatch = line.match(/\.from\(\s*['"]([a-z_]+)['"]\s*\)/)
    if (!fromMatch) continue
    const table = fromMatch[1]
    if (!TENANT_TABLES.has(table)) continue
    // Look at surrounding context: 10 lines before (tud/ti may wrap .from() in multi-line calls) + 15 lines after
    const startLine = Math.max(0, i - 10)
    const chunk = lines.slice(startLine, Math.min(i + 15, lines.length)).join('\n')
    const hasTenantFilter = /\.eq\(\s*['"]tenant_id['"]/.test(chunk)
    const hasTiHelper = /\bti\s*\(/.test(chunk)
    const hasTudHelper = /\btud\s*\(/.test(chunk)
    // Also check for inline tenant_id in insert payload: any tenant_id: <value> or shorthand tenant_id,
    const hasInlineTenantId = /tenant_id\s*:\s*[^\s,)}\]]|tenant_id\s*[,}]/.test(chunk)
    const isSelect = /\.select\s*\(/.test(chunk)
    const isInsert = /\.insert\s*\(/.test(chunk)
    const isUpdate = /\.update\s*\(/.test(chunk)
    const isDelete = /\.delete\s*\(/.test(chunk)
    // For select: need .eq('tenant_id') OR RLS handles it (but we flag for defense-in-depth)
    // For insert: need ti() helper OR explicit tenant_id in payload
    // For update/delete: need tud() helper OR .eq('tenant_id')
    if (isSelect && !hasTenantFilter) {
      // RLS covers this, but defense-in-depth wants app-level filter too
      findings.push({ line: i + 1, code: line.trim(), severity: 'info', note: `SELECT sur ${table} sans .eq('tenant_id') — RLS couvre, mais defense-in-depth recommandée` })
    }
    if ((isUpdate || isDelete) && !hasTenantFilter && !hasTudHelper) {
      findings.push({ line: i + 1, code: line.trim(), severity: 'error', note: `${isUpdate ? 'UPDATE' : 'DELETE'} sur ${table} sans filtre tenant (tud() manquant)` })
    }
    if (isInsert && !hasTiHelper && !hasTenantFilter && !hasInlineTenantId) {
      findings.push({ line: i + 1, code: line.trim(), severity: 'error', note: `INSERT sur ${table} sans tenant_id (ti() manquant)` })
    }
  }
  return findings
}

/**
 * 8. UNCHECKED_SUPABASE — const { data } = await supabase... sans error
 */
function detectUncheckedSupabase(lines, _filePath) {
  const findings = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    // const { data } = await supabase.from(...)...  (no error in destructure)
    if (/const\s*\{\s*data\s*\}\s*=\s*await\s+supabase/.test(line)) {
      findings.push({ line: i + 1, code: line.trim(), severity: 'warning', note: 'data déstructuré sans error — erreur ignorée' })
    }
    // const { data: x } = await supabase... (aliased, no error)
    if (/const\s*\{\s*data\s*:\s*\w+\s*\}\s*=\s*await\s+supabase/.test(line)) {
      findings.push({ line: i + 1, code: line.trim(), severity: 'warning', note: 'data aliasé sans error — erreur ignorée' })
    }
  }
  return findings
}

/**
 * 9. OPTIONAL_CHAIN_SWALLOW — await x?.() retourne undefined silencieusement si x est null
 */
function detectOptionalChainSwallow(lines, _filePath) {
  const findings = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (line.trim().startsWith('//')) continue
    // await someObj?.someMethod()  — if someObj is null, returns undefined
    if (/await\s+\w+(?:\.\w+)*\?\.\w+\s*\(/.test(line)) {
      findings.push({ line: i + 1, code: line.trim(), severity: 'info', note: 'await sur optional chain — retourne undefined si null' })
    }
  }
  return findings
}

/**
 * 10. CATCH_RETURN_DEFAULT — catch qui retourne une valeur par défaut sans logger
 */
function detectCatchReturnDefault(lines, _filePath) {
  const findings = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const catchMatch = line.match(/catch\s*(?:\(\s*\w*(?:\s*:\s*[^)]+)?\s*\))?\s*\{/)
    if (!catchMatch) continue
    // Check single-line: catch { return X }
    const afterBrace = line.slice(catchMatch.index + catchMatch[0].length).trim()
    const singleLineReturn = afterBrace.match(/return\s+(null|undefined|false|\[\]|\{\}|''|""|0)\s*;?\s*\}/)
    if (singleLineReturn && !/console\.|throw|Sentry\./.test(afterBrace)) {
      findings.push({ line: i + 1, code: line.trim(), severity: 'error', note: `catch retourne ${singleLineReturn[1]} silencieusement` })
      continue
    }
    // Multi-line: check if body is just `return X; }`
    if (afterBrace === '' || afterBrace === '{') {
      let j = i + 1
      const bodyParts = []
      while (j < lines.length && j < i + 5) {
        const l = lines[j].trim()
        if (l === '' || l.startsWith('//')) { j++; continue }
        bodyParts.push(l)
        if (l.includes('}')) break
        j++
      }
      const body = bodyParts.join(' ')
      const retMatch = body.match(/return\s+(null|undefined|false|\[\]|\{\}|''|""|0)\s*;?\s*\}/)
      if (retMatch && !/console\.|throw|Sentry\./.test(body)) {
        findings.push({ line: i + 1, code: line.trim(), severity: 'error', note: `catch retourne ${retMatch[1]} silencieusement` })
      }
    }
  }
  return findings
}

// ---------- Main ----------
const detectors = [
  { id: 'EMPTY_CATCH', fn: detectEmptyCatch, label: 'Catch vide (erreur avalée totalement)' },
  { id: 'CONSOLE_ONLY_CATCH', fn: detectConsoleOnlyCatch, label: 'Catch avec console uniquement (pas de notification UI)' },
  { id: 'SWALLOWED_ERROR_RETURN', fn: detectSwallowedErrorReturn, label: 'if(error) return null/[] (erreur avalée avec fallback)' },
  { id: 'AS_ANY_CAST', fn: detectAsAny, label: 'Casts `as any` (typage court-circuité)' },
  { id: 'FLOATING_PROMISE', fn: detectFloatingPromise, label: 'Promises non attendues (fire-and-forget)' },
  { id: 'UNDEFINED_SPREAD', fn: detectUndefinedSpread, label: 'Spread de valeur possiblement undefined' },
  { id: 'MISSING_TENANT_FILTER', fn: detectMissingTenantFilter, label: 'Requêtes tenant sans filtre applicatif' },
  { id: 'UNCHECKED_SUPABASE', fn: detectUncheckedSupabase, label: 'Déstructuration supabase sans vérifier error' },
  { id: 'OPTIONAL_CHAIN_SWALLOW', fn: detectOptionalChainSwallow, label: 'await sur optional chain (undefined silencieux)' },
  { id: 'CATCH_RETURN_DEFAULT', fn: detectCatchReturnDefault, label: 'Catch retourne valeur par défaut silencieusement' },
]

function main() {
  const args = process.argv.slice(2)
  const jsonMode = args.includes('--json')
  const sevArg = args.find((a) => a.startsWith('--severity='))
  const severityFilter = sevArg ? sevArg.split('=')[1] : 'all'

  const allFiles = []
  for (const dir of SCAN_DIRS) {
    allFiles.push(...walkDir(path.join(ROOT, dir)))
  }

  const results = {}
  const summary = {}
  for (const det of detectors) {
    results[det.id] = []
    summary[det.id] = { label: det.label, error: 0, warning: 0, info: 0 }
  }

  for (const file of allFiles) {
    const relPath = path.relative(ROOT, file)
    const lines = readLines(file)
    for (const det of detectors) {
      const findings = det.fn(lines, relPath)
      for (const f of findings) {
        results[det.id].push({ file: relPath, ...f })
        summary[det.id][f.severity] = (summary[det.id][f.severity] || 0) + 1
      }
    }
  }

  if (jsonMode) {
    console.log(JSON.stringify({ summary, results, tenantTablesCount: TENANT_TABLES.size, filesScanned: allFiles.length }, null, 2))
    return
  }

  // Human-readable report
  console.log('═'.repeat(80))
  console.log('  AUDIT DES FAILURES SILENCIEUX — Onusuite/compta')
  console.log('═'.repeat(80))
  console.log(`  Fichiers scannés : ${allFiles.length}`)
  console.log(`  Tables tenant   : ${TENANT_TABLES.size}`)
  console.log('─'.repeat(80))

  let totalErrors = 0
  let totalWarnings = 0
  let totalInfos = 0

  for (const det of detectors) {
    const s = summary[det.id]
    const total = s.error + s.warning + s.info
    totalErrors += s.error
    totalWarnings += s.warning
    totalInfos += s.info
    const icon = s.error > 0 ? '❌' : s.warning > 0 ? '⚠️ ' : s.info > 0 ? 'ℹ️ ' : '✅'
    console.log(`\n${icon} ${det.id} — ${det.label}`)
    console.log(`   ${total} finding(s)  [error: ${s.error}, warning: ${s.warning}, info: ${s.info}]`)

    if (total === 0) continue
    if (severityFilter !== 'all') {
      // Filter findings
      results[det.id] = results[det.id].filter((f) => f.severity === severityFilter || (severityFilter === 'error' && f.severity === 'error'))
    }
    // Show top 15 findings per category
    const shown = results[det.id].slice(0, 15)
    for (const f of shown) {
      const sevTag = f.severity === 'error' ? 'ERR ' : f.severity === 'warning' ? 'WARN' : 'INFO'
      console.log(`   [${sevTag}] ${f.file}:${f.line} — ${f.note || ''}`)
      console.log(`          ${f.code.slice(0, 100)}`)
    }
    if (results[det.id].length > 15) {
      console.log(`   ... et ${results[det.id].length - 15} autre(s)`)
    }
  }

  console.log('\n' + '═'.repeat(80))
  console.log(`  TOTAL: ${totalErrors} errors, ${totalWarnings} warnings, ${totalInfos} infos`)
  console.log('═'.repeat(80))

  if (totalErrors > 0) {
    process.exit(1)
  }
}

main()
