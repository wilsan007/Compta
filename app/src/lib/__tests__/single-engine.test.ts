/**
 * W5 — « un seul moteur par grandeur », tenu aussi côté front
 *
 * Les migrations 260 suppriment le second moteur d'amortissement et le second
 * calcul d'heures supplémentaires. Ce fichier tient l'autre moitié du contrat :
 * **aucun écran ne réintroduit** un plan d'amortissement, un seuil ou un taux
 * d'heures supplémentaires à lui.
 *
 * Les défauts tenus ici, mesurés avant la 260 :
 *   IMMO-01 `misc.ts` calculait `floor(jours / 365,25)` — un plan différent du moteur ;
 *   IMMO-02 « Calculer les amortissements » n'écrivait aucune écriture ;
 *   IMMO-03 le recalcul partait de `Date.now()` (un exercice clos changeait) ;
 *   IMMO-04 `units_of_production` était proposée à l'écran et ignorée en base ;
 *   IMMO-05 les échecs du lot étaient avalés (`console.error`) ;
 *   RH-04  `importTimesheetElements` recalculait les heures sup (seuil 8 h, × 1,25).
 *   C7     (X3, 275) `PayRunsPage` calculait les totaux du lot avec un barème marocain.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

const rpc = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...a: any[]) => rpc(...a), from: vi.fn() },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

describe('W5 — l’écran lit le moteur au lieu de le refaire', () => {
  beforeEach(() => rpc.mockReset())

  it('RH-04 : previewOvertimePay ne transmet NI taux NI montant — la base décide', async () => {
    rpc.mockResolvedValue({
      data: { heures: 1.5, taux_horaire_majore: 24.7253, montant: 37.09, source: 'parametre' },
      error: null,
    })
    const { previewOvertimePay } = await import('@/lib/queries/businessFunctions')

    const res = await previewOvertimePay('emp-1', 1.5)

    expect(rpc).toHaveBeenCalledWith('payroll_overtime_preview', { p_employee_id: 'emp-1', p_hours: 1.5 })
    expect(res.montant).toBe(37.09)
  })

  it('RH-04 : la majoration de la société est lue, pas inventée', async () => {
    rpc.mockResolvedValue({ data: 1.5, error: null })
    const { getOvertimeMajoration } = await import('@/lib/queries/businessFunctions')

    expect(await getOvertimeMajoration()).toBe(1.5)
    expect(rpc).toHaveBeenCalledWith('payroll_overtime_majoration')
  })
})

// ─────────────────────────────────────────────────────────────────────────────
// Miroir statique de la 260 : les symboles du second moteur n'ont plus de
// consommateur dans `src/`.
// ─────────────────────────────────────────────────────────────────────────────
const INTERDITS: Array<[string, RegExp, RegExp?]> = [
  ['calculate_depreciation (RPC supprimée par la 260)', /calculate_depreciation/, /^\s*(\/\/|\*|\/\*)/],
  // `fixedAssets.calculateDepreciation` est une CLÉ i18n (le libellé du bouton),
  // pas un appel : elle désigne l'action, qui passe par le moteur SQL.
  ['calculateDepreciation (plan d’amortissement du front, IMMO-01)', /calculateDepreciation/, /fixedAssets\.calculateDepreciation/],
  ['calculateAllDepreciation (lot du front qui avalait les échecs, IMMO-05)', /calculateAllDepreciation/],
  ['calculate_overtime_pay (second calcul d’heures sup, RH-04)', /calculate_overtime_pay/],
  ['importTimesheetElements (import qui recalculait, RH-04)', /importTimesheetElements/],
  ['seuil d’heures supplémentaires du front (RH-04)', /hours\s*-\s*8|hours\s*>\s*8/],
  ['écriture automatique d’heures supplémentaires par un écran (RH-04)', /element_type\s*:\s*'overtime'/],
  // X3 / C7 (275) : PayRunsPage portait un troisième moteur de paie, MAROCAIN
  // (CNSS 4,48 % plafonnée à 6 000, AMO 2,26 %, part patronale 8,98 %, IR).
  // Les totaux d'un lot sont l'agrégat de ses bulletins, tenu par la base.
  // (« MAD » reste une devise légitime des listes de devises : seul le calcul est interdit.)
  ['taux de cotisation marocains dans un écran (C7)', /0\.0448|0\.0226|0\.0898/],
  ['calcul CNSS / AMO du front (C7)', /\b(cnss|amo)(Total|Base|Ded)\b/i],
]

// Les commentaires CITENT les symboles supprimés pour dire ce qui a changé :
// ce ne sont pas des appels. On les retire avant de juger la ligne.
function sansCommentaire(ligne: string): string {
  const t = ligne.trim()
  if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*') || t.startsWith('{/*')) return ''
  return ligne.replace(/\/\/.*$/, '').replace(/\{\/\*.*$/, '')
}

function fichiersSource(dir: string): string[] {
  const out: string[] = []
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) {
      if (/__tests__|node_modules|\/types$/.test(p)) continue
      out.push(...fichiersSource(p))
    } else if (/\.(ts|tsx)$/.test(p) && !/database-generated|\.test\./.test(p)) {
      out.push(p)
    }
  }
  return out
}

describe('W5 — le front n’a plus de moteur à lui', () => {
  const racine = path.resolve(__dirname, '../../..') // app/
  const src = path.join(racine, 'src')

  it('aucun fichier de src/ ne porte le second moteur d’amortissement ni celui des heures sup', () => {
    const fautifs: string[] = []
    for (const f of fichiersSource(src)) {
      const lignes = fs.readFileSync(f, 'utf8').split('\n')
      for (let i = 0; i < lignes.length; i++) {
        const ligne = sansCommentaire(lignes[i])
        if (!ligne.trim()) continue
        for (const [nom, motif, exception] of INTERDITS) {
          if (exception && exception.test(ligne)) continue
          if (motif.test(ligne)) fautifs.push(`${path.relative(racine, f)}:${i + 1} → ${nom}`)
        }
      }
    }
    expect(fautifs).toEqual([])
  })

  it('IMMO-03 : la fiche d’immobilisation ne calcule plus sa valeur nette au jour d’aujourd’hui', () => {
    const fichier = path.join(src, 'pages/FixedAssetsPage.tsx')
    const contenu = fs.readFileSync(fichier, 'utf8')
    // Les commentaires RACONTENT ce qui a été retiré : on ne juge que le code.
    const code = contenu
      .split('\n')
      .map(sansCommentaire)
      .join('\n')

    expect(code).not.toMatch(/365\.25/)
    expect(code).not.toMatch(/Date\.now\(\)/)
    // et elle passe bien par le moteur (comptabilisation) et son lot (verdict)
    expect(code).toMatch(/generateDepreciationEntry/)
    expect(code).toMatch(/generateDepreciationEntries/)
    // l’option retirée du moteur ne doit plus être offerte
    expect(code).not.toMatch(/units_of_production/)
    // les échecs du lot sont affichés
    expect(code).toMatch(/depreciationFailures/)
  })

  it('RH-04 : l’écran de préparation rattache les éléments de pointage, il ne les écrit pas', () => {
    const fichier = path.join(src, 'pages/payroll/PayrollPreparationPage.tsx')
    const contenu = fs.readFileSync(fichier, 'utf8')

    expect(contenu).toMatch(/attachTimesheetElements/)
    expect(contenu).toMatch(/previewOvertimePay/)
    // plus aucun taux saisi dans l’écran
    expect(contenu).not.toMatch(/setRate\b/)
  })

  // C2 (rh-005) — le simulateur de paie avait son PROPRE moteur
  // (`src/lib/payroll.ts`) : 2 500 € brut y donnaient 1 798,53 € de net contre
  // 1 919,53 € au moteur de la base. Il appelle désormais `simulate_payslip`
  // (migration 319).
  it('C2 : le simulateur appelle le moteur, il n’en a plus un à lui', () => {
    const fichier = path.join(src, 'pages/PayrollCalcPage.tsx')
    const code = fs
      .readFileSync(fichier, 'utf8')
      .split('\n')
      .map(sansCommentaire)
      .join('\n')

    expect(code).toMatch(/simulatePayslip/)          // il appelle le moteur
    expect(code).not.toMatch(/calculatePayroll/)      // et plus son propre barème
    // les champs que le moteur ne prenait pas en entrée ne sont plus proposés
    expect(code).not.toMatch(/setContractType/)
    expect(code).not.toMatch(/setOvertimeHours/)
    expect(code).not.toMatch(/setTaxRate/)
    // la réduction générale est une ligne affichée, pas un calcul caché
    expect(code).toMatch(/reduction_generale/)
  })
})
