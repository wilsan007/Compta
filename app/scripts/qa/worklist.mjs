// ============================================================
// qa/worklist.mjs — la liste de travail restante, fichier par fichier
//
// Lit le registre (`.qa-baseline.json`) et l'inventaire des routes, et rend
// pour chaque classe de défaut la liste des fichiers sources à ouvrir. C'est ce
// qui transforme « 150 défauts » en un plan de travail utilisable.
//
// Usage : npm run qa:worklist   (écrit .qa-out/TRAVAIL-RESTANT.md)
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const inv = JSON.parse(fs.readFileSync(path.join(APP, '.qa/inventory.json'), 'utf8'))
const src = new Map(inv.routes.map((r) => [r.path, r.source]))
const registry = JSON.parse(fs.readFileSync(path.join(APP, '.qa-baseline.json'), 'utf8'))

// Ordre de traitement : ce qui touche le plus d'écrans d'abord.
const ORDER = ['modal_sans_fermeture', 'modal_champ_sans_nom', 'cible_etroite', 'select_vide', 'route_redirigee', 'element_trop_large', 'erreur_console', 'bouton_sans_nom', 'erreur_js', 'sans_titre', 'page_blanche']
const L = ['# Travail restant des écrans (essaim QA)', '', `${registry.length} défaut(s) au registre, par classe.`, '']
for (const id of ORDER) {
  const rows = registry.filter((r) => r.id === id)
  if (!rows.length) continue
  const files = [...new Set(rows.map((r) => src.get(r.route) || `(source inconnue : ${r.route})`))].sort()
  L.push(`## ${id} — ${rows.length} défaut(s), ${files.length} fichier(s)`)
  L.push('')
  for (const f of files) L.push(`- ${f}`)
  L.push('')
}
fs.writeFileSync(path.join(APP, '.qa-out/TRAVAIL-RESTANT.md'), L.join('\n'))
console.log(`${registry.length} défaut(s) répartis ; liste écrite dans .qa-out/TRAVAIL-RESTANT.md`)
for (const id of ORDER) {
  const n = registry.filter((r) => r.id === id).length
  if (n) console.log(`  ${String(n).padStart(3)}  ${id}`)
}
