// ============================================================
// qa/recette.mjs — le kit de recette P0-08 (procès-verbal + certificat)
//
// P0-08 (« les 14 parcours à l'écran ») est la seule recette que le banc
// automatique ne fait pas : elle lit des CHIFFRES métier, pas seulement des
// écrans. Ce kit ne remplace pas le passage humain — il l'industrialise :
//
//   1. il fixe le RÉFÉRENTIEL des 14 parcours (lu une fois, jamais réinventé) ;
//   2. il produit le PROCÈS-VERBAL — une ligne par parcours, un verdict, la
//      capture attendue, la signature ;
//   3. il produit le CERTIFICAT DE RECETTE — un document imprimable, daté et
//      empreint (SHA-256), qui rejoint le positionnement « preuve vérifiable »
//      du produit (le certificat d'intégrité, P1).
//
// Aucune dépendance : `node:fs`, `node:path`, `node:crypto`.
//
// Usage :
//   node scripts/qa/recette.mjs            # écrit le référentiel, le PV et le certificat
//   node scripts/qa/recette.mjs --print    # idem + imprime les chemins et l'empreinte
//
// Le certificat agrège les NOTES DE MODULE si `.qa-out/findings.json` existe
// (tournée de l'essaim QA) ; sinon il dit « non mesuré » et nomme la commande.
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'

const DIR = path.dirname(fileURLToPath(import.meta.url))
const APP = path.resolve(DIR, '../..')
const REPO = path.resolve(APP, '..')
const OUT = path.join(REPO, 'doc/audit/plan6/recette')
const FINDINGS = path.join(APP, '.qa-out/findings.json')

/** Les quatre gabarits d'écran — ceux du banc QA (`--viewports=all`). */
const GABARITS = [
  { id: 'mobile', px: 375 },
  { id: 'tablette', px: 768 },
  { id: 'bureau', px: 1280 },
  { id: 'grand', px: 1920 },
]

/** Les deux états de société — « écrans remplis » et « écrans vides ». */
const ETATS = ['remplie', 'vide']

/**
 * Le RÉFÉRENTIEL des 14 parcours, recopié de `RESTE-A-FAIRE` § P0-08 (la seule
 * source qui fait foi). `module` sert à la re-notation ; `lit` nomme le CHIFFRE
 * que le parcours doit lire — c'est ce qui en fait une recette et pas une visite.
 */
const PARCOURS = [
  { id: 'rec-01', ecran: 'Inscription', module: 'system', faire: 'Créer une société France, puis Djibouti', attendu: 'plan semé ; pour DJ : plan provisoire signalé ; autre pays refusé (PAYS_NON_DISPONIBLE)', lit: 'pays accepté / refusé' },
  { id: 'rec-02', ecran: 'Factures', module: 'commercial', faire: 'Nouvelle facture 2 lignes (TVA 20 % et 5,5 %) → Valider → Envoyer', attendu: 'brouillon BROUILLON-FAC-…, puis FAC-2026-000001 ; badge « Comptabilisé » ; écriture VT équilibrée', lit: 'numéro + écriture équilibrée' },
  { id: 'rec-03', ecran: 'Factures', module: 'commercial', faire: '« Envoyer » un brouillon', attendu: 'la facture est validée d’abord (numéro définitif), puis envoyée', lit: 'ordre valider → envoyer' },
  { id: 'rec-04', ecran: 'Factures', module: 'commercial', faire: '« Marquer payée »', attendu: 'règlement REG-…, facture payée, 411 lettré ; le bouton n’apparaît pas sur un brouillon', lit: 'règlement + lettrage 411' },
  { id: 'rec-05', ecran: 'Devis', module: 'commercial', faire: 'Nouveau devis → Convertir en facture', attendu: 'lignes et TVA reprises ; devis « transformé »', lit: 'lignes + TVA reprises' },
  { id: 'rec-06', ecran: 'Avoirs', module: 'commercial', faire: 'Avoir sur facture → Valider', attendu: 'AV-2026-000001, facture soldée ou réduite, lettrage', lit: 'numéro AV + solde' },
  { id: 'rec-07', ecran: 'Factures d’achat', module: 'stock', faire: 'Nouvelle facture (référence fournisseur + lignes) → Approuver → Marquer payée', attendu: 'ACH-2026-000001, écriture AC, décaissement DEC-…, 401 lettré ; libellés traduits (fr/en/ar)', lit: 'numéro ACH + lettrage 401' },
  { id: 'rec-08', ecran: 'Avoirs fournisseur', module: 'stock', faire: 'Nouveau → Valider', attendu: 'AVF-…, écriture AC inverse', lit: 'numéro AVF + écriture inverse' },
  { id: 'rec-09', ecran: 'Paie', module: 'hr', faire: 'Lot approuvé → « Générer l’écriture de paie » → passer à « payé »', attendu: 'une seule écriture PAIE, équilibrée ; message clair si un bulletin est incohérent', lit: 'une écriture PAIE équilibrée' },
  { id: 'rec-10', ecran: 'Import de relevé', module: 'treasury', faire: 'Fichier MT940 / CAMT.053 / CFONB réel', attendu: '« n opérations importées, m doublons écartés » ; lignes pointées automatiquement', lit: 'n importées / m doublons' },
  { id: 'rec-11', ecran: 'Stock', module: 'stock', faire: 'Inventaire en baisse puis en hausse', attendu: 'stock dépôt = stock article ; écriture ST', lit: 'stock dépôt = stock article' },
  { id: 'rec-12', ecran: 'Caisse', module: 'treasury', faire: 'Session avec 2 tickets → clôture', attendu: 'stock du magasin seul décrémenté, une fois', lit: 'stock décrémenté une fois' },
  { id: 'rec-13', ecran: 'Clôture (V2)', module: 'accounting', faire: 'Exercice complet → clôture → bilan / compte de résultat', attendu: 'équilibrés, à-nouveaux corrects, bandeau rouge absent', lit: 'bilan = compte de résultat' },
  { id: 'rec-14', ecran: 'Tout', module: 'system', faire: 'Changer de langue (fr → en → ar)', attendu: 'aucune clé brute affichée ; arabe en RTL', lit: '0 clé brute ; RTL' },
]

// ── Lecture optionnelle des notes de l'essaim QA ────────────────────────────
/** Le nombre de défauts par module, lu dans la tournée — ou `null` si non jouée. */
function notesModules() {
  if (!fs.existsSync(FINDINGS)) return null
  const findings = JSON.parse(fs.readFileSync(FINDINGS, 'utf8'))
  const parModule = {}
  for (const f of findings) parModule[f.module] = (parModule[f.module] ?? 0) + 1
  return parModule
}

/** La note d'un module : A (aucun défaut), B (n défauts), ou n/a (non mesuré). */
function note(parModule, module) {
  if (!parModule) return { code: 'n/a', mot: 'non mesuré — lancer l’essaim QA' }
  const n = parModule[module] ?? 0
  return n === 0 ? { code: 'A', mot: 'aucun défaut' } : { code: 'B', mot: `${n} défaut(s)` }
}

const empreinte = (o) => crypto.createHash('sha256').update(JSON.stringify(o)).digest('hex')
const today = () => new Date().toISOString().slice(0, 10)
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

/** Le référentiel, machine-lisible : la base d'un futur scénario Playwright (D.5). */
function ecrireReferentiel() {
  fs.writeFileSync(path.join(OUT, 'parcours.json'), JSON.stringify({
    referentiel: 'P0-08',
    source: 'doc/audit/RESTE-A-FAIRE-2026-09-22.md (§ P0-08)',
    gabarits: GABARITS,
    etats: ETATS,
    parcours: PARCOURS,
  }, null, 2) + '\n')
}

/** Le procès-verbal : la feuille que l'on remplit puis signe. */
function ecrirePv(empreinteRef) {
  const l = []
  l.push('# Procès-verbal de recette — P0-08 (les 14 parcours à l’écran)')
  l.push('')
  l.push(`> Généré le **${today()}** par \`node app/scripts/qa/recette.mjs\`.`)
  l.push(`> Référentiel : **${empreinteRef.slice(0, 12)}** — un référentiel figé, pas une liste tenue à la main.`)
  l.push('> **Preuve par parcours :** une capture + le CHIFFRE lu. Un écart devient un scénario rouge.')
  l.push('')
  l.push(`**Environnement.** Application locale (\`QA_BASE_URL\` local — jamais une URL distante) ; base à jour ; 2 sociétés — **${ETATS.join('** et **')}** ; 4 gabarits — ${GABARITS.map((g) => g.px).join(' / ')} px.`)
  l.push('')
  l.push('| # | Écran | Parcours | Ce qu’on doit voir | Lit | Verdict | Capture |')
  l.push('|---|---|---|---|---|---|---|')
  for (const p of PARCOURS) l.push(`| ${p.id} | ${p.ecran} | ${p.faire} | ${p.attendu} | ${p.lit} | ⬜ | |`)
  l.push('')
  l.push(`**Matrice.** Chaque parcours est joué sur **${ETATS.length} états** de société et **${GABARITS.length} gabarits** — ${PARCOURS.length} × ${ETATS.length} × ${GABARITS.length} = **${PARCOURS.length * ETATS.length * GABARITS.length} passages**. Un passage non applicable est *barré*, jamais laissé en ⬜ en silence.`)
  l.push('')
  l.push('## Critères de sortie (tous requis)')
  l.push('- [ ] les 14 parcours portent un verdict (aucun ⬜) ;')
  l.push('- [ ] 0 écart **bloquant** ouvert — les autres sont inscrits pour l’horizon suivant ;')
  l.push('- [ ] modules re-notés (voir le certificat) ;')
  l.push('- [ ] **procès-verbal signé** (ci-dessous).')
  l.push('')
  l.push('## Signature')
  l.push('')
  l.push('| | Nom | Date | Signature |')
  l.push('|---|---|---|---|')
  l.push('| Recette faite par |  |  |  |')
  l.push('| Accepté par (client) |  |  |  |')
  fs.writeFileSync(path.join(OUT, 'PROCES-VERBAL-P0-08.md'), l.join('\n') + '\n')
}


/** Le certificat : un document imprimable, daté, empreint — la preuve qui se garde. */
function ecrireCertificat(parModule, empreinteRef) {
  const modules = [...new Set(PARCOURS.map((p) => p.module))]
  const lignesParcours = PARCOURS.map((p) =>
    `        <tr><td class="mono">${p.id}</td><td>${esc(p.ecran)}</td><td>${esc(p.faire)}</td><td>${esc(p.attendu)}</td><td class="v"></td></tr>`,
  ).join('\n')
  const lignesModules = modules.map((m) => {
    const g = note(parModule, m)
    return `        <tr><td>${esc(m)}</td><td><span class="grade g-${g.code.replace('/', '')}">${g.code}</span></td><td>${esc(g.mot)}</td></tr>`
  }).join('\n')
  const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Certificat de recette — P0-08 · Onusuite</title>
<style>
  :root { --accent: #4338ca; --ink: #0f172a; --muted: #64748b; --line: #e2e8f0; --ok: #059669; --warn: #d97706; }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 40px 24px; font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; color: var(--ink); background: #f8fafc; }
  .sheet { max-width: 980px; margin: 0 auto; background: #fff; border: 1px solid var(--line); border-radius: 14px; overflow: hidden; box-shadow: 0 10px 40px rgba(15,23,42,.08); }
  .haut { padding: 28px 32px; background: linear-gradient(135deg, var(--accent), #6d28d9); color: #fff; }
  .marque { letter-spacing: .12em; text-transform: uppercase; font-size: 12px; opacity: .85; }
  h1 { margin: 6px 0 2px; font-size: 26px; }
  .sous { opacity: .92; font-size: 14px; }
  .corps { padding: 28px 32px; }
  .meta { display: flex; flex-wrap: wrap; gap: 10px 26px; padding: 12px 16px; background: #f1f5f9; border-radius: 10px; font-size: 13px; color: var(--muted); margin-bottom: 22px; }
  .meta b { color: var(--ink); }
  table { width: 100%; border-collapse: collapse; font-size: 12.5px; }
  th, td { border-bottom: 1px solid var(--line); padding: 8px 10px; text-align: left; vertical-align: top; }
  th { background: #f8fafc; font-size: 11px; letter-spacing: .04em; text-transform: uppercase; color: var(--muted); }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--accent); white-space: nowrap; }
  .v { width: 56px; }
  h2 { font-size: 15px; margin: 26px 0 8px; }
  .grade { display: inline-block; min-width: 26px; text-align: center; padding: 1px 7px; border-radius: 999px; font-weight: 700; font-size: 11px; }
  .g-A { background: #dcfce7; color: var(--ok); } .g-B { background: #fef3c7; color: var(--warn); } .g-na { background: #e2e8f0; color: var(--muted); }
  .pied { padding: 20px 32px 28px; border-top: 1px solid var(--line); display: flex; flex-wrap: wrap; gap: 18px; justify-content: space-between; align-items: flex-end; }
  .hash { font-size: 11px; color: var(--muted); word-break: break-all; max-width: 560px; }
  .hash code { font-family: ui-monospace, monospace; color: var(--ink); }
  .sign { text-align: right; font-size: 12px; color: var(--muted); }
  .sign .l { margin-top: 34px; border-top: 1px solid var(--ink); width: 220px; padding-top: 4px; }
  .phrase { font-size: 12.5px; color: var(--muted); font-style: italic; margin-top: 18px; }
  @media print { body { background: #fff; padding: 0; } .sheet { border: 0; box-shadow: none; border-radius: 0; } }
</style>
</head>
<body>
  <div class="sheet">
    <div class="haut">
      <div class="marque">Onusuite — The Unified Business Suite</div>
      <h1>Certificat de recette</h1>
      <div class="sous">P0-08 — les 14 parcours métier à l’écran</div>
    </div>
    <div class="corps">
      <div class="meta">
        <span>Date : <b>${today()}</b></span>
        <span>Référentiel : <b>${empreinteRef.slice(0, 12)}</b></span>
        <span>Sociétés : <b>remplie + vide</b></span>
        <span>Gabarits : <b>${GABARITS.map((g) => g.px).join(' / ')} px</b></span>
      </div>
      <table>
        <thead><tr><th>#</th><th>Écran</th><th>Parcours</th><th>Ce qu’on doit voir</th><th>Verdict</th></tr></thead>
        <tbody>
${lignesParcours}
        </tbody>
      </table>
      <h2>Re-notation des modules</h2>
      <table>
        <thead><tr><th>Module</th><th>Note</th><th>Mesure</th></tr></thead>
        <tbody>
${lignesModules}
        </tbody>
      </table>
      <p class="phrase">La recette ne s’évapore pas dans un fil de discussion : elle produit un document <b>daté, empreint et signable</b> — la même exigence de preuve que le certificat d’intégrité.</p>
    </div>
    <div class="pied">
      <div class="hash">Empreinte du référentiel de recette (SHA-256) :<br /><code>${empreinteRef}</code></div>
      <div class="sign"><div class="l">Recette &amp; acceptation (client)</div></div>
    </div>
  </div>
</body>
</html>
`
  fs.writeFileSync(path.join(OUT, 'CERTIFICAT-RECETTE.html'), html)
}

function main() {
  fs.mkdirSync(OUT, { recursive: true })
  const parModule = notesModules()
  const empreinteRef = empreinte({ referentiel: 'P0-08', parcours: PARCOURS, gabarits: GABARITS, etats: ETATS })
  ecrireReferentiel()
  ecrirePv(empreinteRef)
  ecrireCertificat(parModule, empreinteRef)
  console.log(`✅ Kit de recette écrit — ${parModule ? 'notes de module incluses' : 'notes de module : non mesurées (lancer l’essaim QA)'}`)
  for (const f of ['parcours.json', 'PROCES-VERBAL-P0-08.md', 'CERTIFICAT-RECETTE.html']) console.log(`   ${path.join(OUT, f)}`)
  console.log(`   empreinte du référentiel : ${empreinteRef}`)
  if (process.argv.includes('--print')) console.log(`   ${PARCOURS.length} parcours · ${GABARITS.length} gabarits · ${ETATS.length} états = ${PARCOURS.length * GABARITS.length * ETATS.length} passages`)
}

main()

