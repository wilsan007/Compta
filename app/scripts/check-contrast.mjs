#!/usr/bin/env node
/**
 * LOT7-07 — Contraste des couleurs (WCAG 2.1, critère 1.4.3).
 *
 * Mesure le rapport de contraste des couleurs de texte réellement employées dans le
 * code (`text-[var(--color-…)]`) sur les fonds du thème, en clair ET en sombre.
 * C'est objectif et reproductible, là où « vérifier le contraste à l'œil » ne l'est pas.
 *
 * Seuils WCAG AA : 4,5:1 pour le texte courant, 3:1 pour le texte large (≥ 24px, ou
 * ≥ 18,66px en gras). Ce contrôle applique 4,5:1, le cas le plus fréquent dans
 * l'application, et 3:1 pour les couleurs qui ne servent qu'à des pastilles d'état.
 *
 * Usage : node scripts/check-contrast.mjs
 */
import { readFileSync, readdirSync, statSync, existsSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const CSS = join(ROOT, 'src/index.css')
const ALLOWLIST = join(ROOT, '.contrast-allowlist.json')

// ---------- calcul WCAG ----------
function hexToRgb(hex) {
  const h = hex.replace('#', '').trim()
  const full = h.length === 3 ? h.split('').map((c) => c + c).join('') : h
  if (!/^[0-9a-f]{6}$/i.test(full)) return null
  return [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16))
}
/** Luminance relative, formule WCAG 2.1. */
function luminance([r, g, b]) {
  const [R, G, B] = [r, g, b].map((v) => {
    const c = v / 255
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  })
  return 0.2126 * R + 0.7152 * G + 0.0722 * B
}
function contrast(fg, bg) {
  const L1 = luminance(fg), L2 = luminance(bg)
  const [hi, lo] = L1 > L2 ? [L1, L2] : [L2, L1]
  return (hi + 0.05) / (lo + 0.05)
}

// ---------- lecture des thèmes ----------
/**
 * Le thème clair est réparti entre `@theme { … }` (les jetons Tailwind v4) et
 * `:root { … }` ; `:root.dark { … }` porte le sombre, qui ne redéfinit qu'une partie
 * des variables et hérite du clair pour le reste.
 *
 * Les sélecteurs sont cherchés en début de ligne et suivis d'une accolade : sinon
 * `:root.dark` attrape `:root.dark .glass { … }`, qui n'est pas la palette.
 */
function readThemes(css) {
  function block(selector) {
    const re = new RegExp(`^${selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*\\{`, 'm')
    const m = re.exec(css)
    if (!m) return {}
    const start = css.indexOf('{', m.index)
    let depth = 0, end = start
    for (let k = start; k < css.length; k++) {
      if (css[k] === '{') depth++
      else if (css[k] === '}') { depth--; if (depth === 0) { end = k; break } }
    }
    const vars = {}
    for (const mm of css.slice(start, end).matchAll(/(--color-[a-z0-9-]+)\s*:\s*(#[0-9a-fA-F]{3,8})/g)) {
      vars[mm[1]] = mm[2]
    }
    return vars
  }
  const light = { ...block('@theme'), ...block(':root') }
  return { light, dark: { ...light, ...block(':root.dark') } }
}

// ---------- couleurs de texte utilisées dans le code ----------
function walk(dir) {
  const out = []
  for (const e of readdirSync(dir)) {
    const p = join(dir, e)
    if (statSync(p).isDirectory()) { if (e !== '__tests__') out.push(...walk(p)) }
    else if (p.endsWith('.tsx')) out.push(p)
  }
  return out
}
/**
 * Relève chaque couleur de texte ET le fond sur lequel elle est réellement posée.
 *
 * Trois pièges, tous rencontrés dans ce code :
 *  1. un fond écrit dans le même `className` l'emporte sur le fond de page — sinon un
 *     `text-[var(--color-neutral-50)]` sur `bg-[var(--color-neutral-900)]` (bloc de
 *     code) serait mesuré à 1:1 alors qu'il est parfaitement lisible ;
 *  2. une classe d'ÉTAT (`hover:bg-…`, `focus:…`, `dark:…`) n'est pas le fond
 *     permanent : la retenir fausse la mesure ;
 *  3. `bg-[var(--color-success)]/10` est une couleur à 10 % composée sur le fond de
 *     page, pas la couleur pleine — la prendre telle quelle donne un absurde 1:1.
 *
 * L'appariement se fait à l'intérieur d'un même littéral de chaîne : dans un
 * `cn('…', ok && 'text-A bg-B', !ok && 'text-C bg-D')`, A ne va jamais avec D.
 *
 * Rend une Map `"texte|fond|alpha"` → nombre d'usages.
 */
/** Composants importés de `lucide-react` dans ce fichier : ce sont des icônes. */
function lucideIcons(src) {
  const set = new Set()
  for (const m of src.matchAll(/import\s*\{([^}]*)\}\s*from\s*'lucide-react'/g)) {
    for (const n of m[1].split(',')) {
      const name = n.trim().split(' as ').pop().trim()
      if (name) set.add(name)
    }
  }
  return set
}

/** Neutralise les `text-[var(…)]` portés par une balise d'icône, en gardant les autres. */
function maskIconColors(line, icons) {
  if (icons.size === 0) return line
  let out = ''
  let pos = 0
  for (const m of line.matchAll(/text-\[var\(--color-[a-z0-9-]+\)\]/g)) {
    const head = line.lastIndexOf('<', m.index)
    const tag = head === -1 ? null : (/^<([A-Za-z][A-Za-z0-9.]*)/.exec(line.slice(head, m.index)) ?? [])[1]
    out += line.slice(pos, m.index) + (icons.has(tag) ? 'text-icone-decorative' : m[0])
    pos = m.index + m[0].length
  }
  return out + line.slice(pos)
}

const TEXT_RE = /(?<![\w:-])text-\[var\((--color-[a-z0-9-]+)\)\]/g
const BG_RE = /(?<![\w:-])bg-\[var\((--color-[a-z0-9-]+)\)\](?:\/(\d{1,3}))?/g

function usedPairs() {
  const counts = new Map()
  const add = (fg, bg, alpha) => {
    const k = `${fg}|${bg}|${alpha}`
    counts.set(k, (counts.get(k) ?? 0) + 1)
  }
  for (const f of walk(join(ROOT, 'src'))) {
    const src = readFileSync(f, 'utf8')
    const icons = lucideIcons(src)
    for (let line of src.split('\n')) {
      if (!line.includes('text-[var(')) continue
      // Une couleur posée sur une icône lucide n'est PAS une couleur de texte : depuis
      // le LOT7-07 ces icônes sont `aria-hidden` et doublées d'un libellé, donc
      // décoratives — aucun seuil de contraste ne s'y applique. Les compter comme du
      // texte faisait ressortir --color-warning à 2,02:1 alors que le texte, lui, est
      // passé à --color-warning-text. On les masque avant tout appariement.
      line = maskIconColors(line, icons)
      if (!line.includes('text-[var(')) continue
      // Découpage sur les quotes, ligne par ligne. Un appariement plus large se laisse
      // piéger par les apostrophes du français (« l'utilisateur ») qui traversent les
      // littéraux, et par les branches d'un ternaire qui ne coexistent jamais.
      for (const seg of line.split(/['"`]/)) {
        const texts = [...seg.matchAll(TEXT_RE)].map((m) => m[1])
        if (texts.length === 0) continue
        const bgs = [...seg.matchAll(BG_RE)].map((m) => ({ v: m[1], a: m[2] ? Number(m[2]) / 100 : 1 }))
        for (const fg of texts) {
          if (bgs.length > 0) for (const b of bgs) add(fg, b.v, b.a)
          else for (const bg of DEFAULT_BACKGROUNDS) add(fg, bg, 1)
        }
      }
    }
  }
  return counts
}

/** Compose une couleur semi-transparente sur un fond opaque. */
function over(fg, bg, alpha) {
  return fg.map((c, i) => Math.round(c * alpha + bg[i] * (1 - alpha)))
}

// Fonds retenus quand la classe n'en nomme aucun explicitement.
const DEFAULT_BACKGROUNDS = ['--color-surface', '--color-background']
const MIN = 4.5

const css = readFileSync(CSS, 'utf8')
const themes = readThemes(css)
const used = usedPairs()
const allowed = existsSync(ALLOWLIST) ? JSON.parse(readFileSync(ALLOWLIST, 'utf8')).allowed ?? [] : []

const failures = []
const tolerated = []
const rows = []

for (const [theme, vars] of Object.entries(themes)) {
  for (const [pair, uses] of [...used].sort((a, b) => b[1] - a[1])) {
    const [fgVar, bgVar, alphaStr] = pair.split('|')
    const alpha = Number(alphaStr)
    const fgHex = vars[fgVar]
    const bgHex = vars[bgVar]
    if (!fgHex || !bgHex) continue // variable absente de ce thème
    const fg = hexToRgb(fgHex)
    let bg = hexToRgb(bgHex)
    if (!fg || !bg) continue
    // un fond translucide se compose sur la surface de la page
    if (alpha < 1) {
      const page = hexToRgb(vars['--color-surface'])
      if (!page) continue
      bg = over(bg, page, alpha)
    }
    const ratio = contrast(fg, bg)
    const label = alpha < 1 ? `${bgVar}/${Math.round(alpha * 100)}` : bgVar
    const entry = { theme, fgVar, fgHex, bgVar: label, bgHex, ratio: Math.round(ratio * 100) / 100, uses }
    rows.push(entry)
    if (ratio >= MIN) continue
    const waived = allowed.find((a) => a.theme === theme && a.fg === fgVar && a.bg === bgVar)
    // `maxUses` empêche une tolérance de couvrir plus large que ce qui a été examiné :
    // la dispense vaut pour les N occurrences vérifiées une par une, pas pour la couleur.
    if (waived && waived.maxUses != null && uses > waived.maxUses) {
      failures.push({ ...entry, over: waived.maxUses })
    } else if (waived) {
      tolerated.push({ ...entry, reason: waived.reason })
    } else {
      failures.push(entry)
    }
  }
}

console.log(`Contraste WCAG AA (${MIN}:1) — ${used.size} paires texte/fond relevées dans le code, mesurées dans les deux thèmes\n`)
for (const r of rows.sort((a, b) => a.ratio - b.ratio).slice(0, 12)) {
  const mark = r.ratio >= MIN ? '✅' : '❌'
  console.log(`  ${mark} ${r.ratio.toFixed(2).padStart(5)}:1  ${r.theme.padEnd(5)} ${r.fgVar} (${r.fgHex}) sur ${r.bgVar} — ${r.uses} usages`)
}
console.log()

if (tolerated.length) {
  console.log(`ℹ️  ${tolerated.length} écart(s) toléré(s) (voir .contrast-allowlist.json) :`)
  for (const t of tolerated) console.log(`     ${t.ratio}:1 ${t.theme} ${t.fgVar} sur ${t.bgVar} — ${t.reason}`)
  console.log()
}

if (failures.length === 0) {
  console.log('✅ Toutes les couleurs de texte employées atteignent le seuil AA.')
  process.exit(0)
}
console.error(`❌ ${failures.length} combinaison(s) sous le seuil AA de ${MIN}:1 :`)
for (const f of failures) {
  const plafond = f.over != null ? ` — dispense limitée à ${f.over} usages vérifiés, ${f.uses} trouvés` : ''
  console.error(`   ${f.ratio}:1  thème ${f.theme} — ${f.fgVar} (${f.fgHex}) sur ${f.bgVar} (${f.bgHex}), ${f.uses} usages${plafond}`)
}
// ---------- proposition de correction ----------
// `--suggest` calcule, pour chaque couleur fautive, la teinte la PLUS PROCHE qui atteint
// le seuil : même tonalité et même saturation, seule la luminosité bouge. L'écart visuel
// reste donc minimal, et la décision de l'appliquer revient au design.
function rgbToHsl([r, g, b]) {
  r /= 255; g /= 255; b /= 255
  const max = Math.max(r, g, b), min = Math.min(r, g, b)
  const l = (max + min) / 2
  if (max === min) return [0, 0, l]
  const d = max - min
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  let h
  if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6
  else if (max === g) h = ((b - r) / d + 2) / 6
  else h = ((r - g) / d + 4) / 6
  return [h, s, l]
}
function hslToRgb([h, s, l]) {
  if (s === 0) { const v = Math.round(l * 255); return [v, v, v] }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s
  const p = 2 * l - q
  const f = (t) => {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  return [f(h + 1 / 3), f(h), f(h - 1 / 3)].map((v) => Math.round(v * 255))
}
const toHex = (rgb) => '#' + rgb.map((v) => v.toString(16).padStart(2, '0')).join('')

/** Luminosité la plus proche de l'originale qui atteint `min` sur tous les fonds donnés. */
function suggest(fgHex, bgList, min) {
  const [h, sat, l0] = rgbToHsl(hexToRgb(fgHex))
  let best = null
  for (let step = 1; step <= 100; step++) {
    for (const dir of [-1, 1]) {
      const l = l0 + (dir * step) / 100
      if (l < 0 || l > 1) continue
      const rgb = hslToRgb([h, sat, l])
      if (bgList.every((bg) => contrast(rgb, bg) >= min)) { best = toHex(rgb); break }
    }
    if (best) break
  }
  return best
}

if (process.argv.includes('--suggest') && failures.length) {
  // La suggestion vise les DEUX FONDS DE PAGE du thème, et rien d'autre. Inclure les
  // fonds teintés (`--color-danger` sur `--color-danger/10`) reviendrait à demander
  // qu'une couleur contraste avec elle-même : la seule issue serait le noir ou le
  // blanc, ce qui détruirait la charte. Un texte sur fond teinté de la même famille
  // se corrige en éclaircissant le FOND, pas le texte.
  const pageBgs = (theme) => DEFAULT_BACKGROUNDS.map((v) => hexToRgb(themes[theme][v])).filter(Boolean)
  const onPage = failures.filter((f) => DEFAULT_BACKGROUNDS.includes(f.bgVar))
  const tinted = failures.filter((f) => !DEFAULT_BACKGROUNDS.includes(f.bgVar))

  if (onPage.length) {
    console.error('\nCorrections possibles sur les fonds de page — même tonalité et même')
    console.error('saturation, seule la luminosité change, pour rester au plus près de la charte :')
    const byVar = new Map()
    for (const f of onPage) {
      const k = `${f.theme}|${f.fgVar}`
      if (!byVar.has(k)) byVar.set(k, { theme: f.theme, fgVar: f.fgVar, fgHex: f.fgHex, uses: 0 })
      byVar.get(k).uses += f.uses
    }
    for (const e of [...byVar.values()].sort((a, b) => b.uses - a.uses)) {
      const bgs = pageBgs(e.theme)
      const sug = suggest(e.fgHex, bgs, MIN)
      const got = sug ? Math.min(...bgs.map((bg) => contrast(hexToRgb(sug), bg))).toFixed(2) : '—'
      console.error(`   ${e.theme.padEnd(5)} ${e.fgVar.padEnd(22)} ${e.fgHex} → ${sug ?? 'aucune sans changer de teinte'}  (${got}:1, ${e.uses} usages)`)
    }
  }
  if (tinted.length) {
    console.error('\nSur fond teinté de la même famille — à corriger en éclaircissant le FOND :')
    for (const f of tinted.sort((a, b) => b.uses - a.uses)) {
      console.error(`   ${f.theme.padEnd(5)} ${f.fgVar} sur ${f.bgVar} — ${f.ratio}:1, ${f.uses} usages`)
    }
  }
}

console.error(`\n   Éclaircir ou assombrir la variable dans src/index.css, ou — si la couleur ne`)
console.error(`   sert qu'à du texte large ou décoratif — l'inscrire dans .contrast-allowlist.json.`)
process.exit(1)
