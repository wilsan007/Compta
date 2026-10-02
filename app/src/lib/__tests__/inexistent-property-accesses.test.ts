/**
 * Les accès à une propriété inexistante — gardes de régression (2026-10-02).
 *
 * Quatre défauts de la même famille, trouvés en nommant le type d'un tableau
 * d'état depuis sa fonction de requête (état des lieux :
 * `doc/audit/ETAT-DES-LIEUX-29-ACCES-PROPRIETE-INEXISTANTE-2026-10-01.md`) :
 *
 *  - AUD-ACCES-02 `EmployeeExpensesPage` : l'indicateur d'intégration en paie
 *    lisait `r.payroll_integrated || r.payroll_variable_id` sur la note de frais.
 *    Aucune des deux n'existe — ni dans `ExpenseReport`, ni en base
 *    (`information_schema` : aucune colonne `payroll%` sur `expense_reports`).
 *    Toujours faux : « Non intégré » même pour une note entrée en paie. La vérité
 *    est dans `payroll_variable_elements` (`source='expense_report'`).
 *  - AUD-ACCES-03 `ThirdPartyInquiryPage` : la colonne « tiers » et le filtre de
 *    compte lisaient `e.third_party_account` sur l'EN-TÊTE de l'écriture. Le tiers
 *    vit sur les LIGNES (`journal_lines.account_tiers`) : colonne toujours `-`,
 *    filtre qui ne filtrait rien.
 *  - AUD-ACCES-05 `EcheancierPage` : `key={r.id || i}` — `getEcheancier()`
 *    sélectionnait `id` sur le document source puis le jetait, donc le repli sur
 *    l'index prenait toujours.
 *  - AUD-ACCES-06 `AnalyticODEntryPage` : le badge de type lisait `s.type` alors
 *    que la colonne est `section_type` (274) — « section » pour toutes les lignes,
 *    y compris les 5 sections `total` (mesuré en base) qui ne sont jamais
 *    imputables.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

// ============ Mock Infrastructure (même harnais que production-queries) ============

/** Ce que le faux PostgREST rend : la donnée est `unknown`, jamais `any` — un `any`
 *  ici rendrait la garde incapable de dire quoi que ce soit. */
type ReponseSimulee = { data: unknown; error: unknown }
/** Rôle du `then` qu'on passe à `Promise` : reçoit la réponse résolue. */
type Resolveur = (reponse: ReponseSimulee) => void
type Simulateur = ReturnType<typeof vi.fn>
/** Une chaîne : chaque méthode se renvoie elle-même, `single`/`rpc`/`then` résolvent. */
interface ChaineSimulee {
  select: Simulateur; insert: Simulateur; update: Simulateur; delete: Simulateur
  eq: Simulateur; neq: Simulateur; order: Simulateur; single: Simulateur
  maybeSingle: Simulateur; limit: Simulateur; range: Simulateur; in: Simulateur
  gte: Simulateur; lte: Simulateur; like: Simulateur; ilike: Simulateur
  or: Simulateur; not: Simulateur; is: Simulateur; count: Simulateur
  rpc: Simulateur
  // Le thenable rend ce que `Promise` lui rend : le resolveur renvoie `void`,
  // donc le résultat est `unknown` — la forme exacte n'a pas d'importance ici.
  then: (resolve: Resolveur) => Promise<unknown>
}

function createMockChain(resolvedValue: ReponseSimulee = { data: [], error: null }): ChaineSimulee {
  const chain: ChaineSimulee = {
    select: vi.fn(() => chain),
    insert: vi.fn(() => chain),
    update: vi.fn(() => chain),
    delete: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    neq: vi.fn(() => chain),
    order: vi.fn(() => chain),
    single: vi.fn(() => Promise.resolve(resolvedValue)),
    maybeSingle: vi.fn(() => Promise.resolve(resolvedValue)),
    limit: vi.fn(() => chain),
    range: vi.fn(() => new Promise((resolve) => chain.then(resolve))),
    in: vi.fn(() => chain),
    gte: vi.fn(() => chain),
    lte: vi.fn(() => chain),
    like: vi.fn(() => chain),
    ilike: vi.fn(() => chain),
    or: vi.fn(() => chain),
    not: vi.fn(() => chain),
    is: vi.fn(() => chain),
    count: vi.fn(() => chain),
    rpc: vi.fn(() => Promise.resolve(resolvedValue)),
    then: (resolve: Resolveur) => Promise.resolve(resolvedValue).then(resolve),
  }
  return chain
}

const mockChain = createMockChain()

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn(() => mockChain),
    auth: {
      getSession: vi.fn(() => Promise.resolve({ data: { session: { user: { id: 'user-1' } } } })),
      signInWithPassword: vi.fn(),
      signOut: vi.fn(),
    },
    channel: vi.fn(),
    removeChannel: vi.fn(),
    rpc: vi.fn(() => Promise.resolve({ data: null, error: null })),
  },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

import { supabase } from '@/lib/supabase'

function setMockData(data: unknown, error: unknown = null) {
  mockChain.single = vi.fn(() => Promise.resolve({ data, error }))
  mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data, error }))
  mockChain.then = (resolve: Resolveur) => Promise.resolve({ data, error }).then(resolve)
}

function resetMock() {
  mockChain.single = vi.fn(() => Promise.resolve({ data: null, error: null }))
  mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: null, error: null }))
  mockChain.then = (resolve: Resolveur) => Promise.resolve({ data: [], error: null }).then(resolve)
  vi.clearAllMocks()
}

beforeEach(() => resetMock())

const racine = path.resolve(__dirname, '../../..') // app/
const lire = (p: string) => fs.readFileSync(path.join(racine, p), 'utf8')
/** Le corps d'une fonction exportée, jusqu'à la prochaine exportation. */
function corpsDe(src: string, signature: string): string {
  const debut = src.indexOf(signature)
  expect(debut, `signature introuvable : ${signature}`).toBeGreaterThan(-1)
  const fin = src.indexOf('\nexport ', debut + 1)
  return fin > 0 ? src.slice(debut, fin) : src.slice(debut)
}
/**
 * Les lignes de code, commentaires exclus. Le commentaire qui documente le
 * défaut cite la propriété fautive — il faut donc retirer les blocs
 * (`/* … *\/` et le JSX `{/* … *\/}`) avant de découper, pas seulement les
 * lignes `//` et `*`.
 */
function codeSeul(src: string): string[] {
  const sansBlocs = src.replace(/\{?\/\*[\s\S]*?\*\/\}?/g, '')
  return sansBlocs.split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*'))
}

// ============ AUD-JOINTURE — les types de retour de la paie ============

describe('AUD-JOINTURE — les 14 fonctions de paie déclarent enfin leur retour', () => {
  const PAYROLL = 'src/lib/queries/payroll.ts'

  it('aucune ne renvoie plus `Record<string, unknown>[]`', () => {
    const src = lire(PAYROLL)
    const fautives = codeSeul(src).filter((l) => /Record<string, unknown>\[\]/.test(l))
    // Zéro : c'est ce repli qui rendait le typage des écrans IMPOSSIBLE
    // (`doc/audit/ETAT-DES-LIEUX-TYPAGE-ETATS-TRANCHE-2-2026-10-02.md` §3).
    expect(fautives).toEqual([])
  })

  it('la ressource jointe est nommée, sinon `tsc` la refuse', () => {
    const src = lire(PAYROLL)
    expect(src).toMatch(/interface EmployeJoint \{/)
    expect(src).toMatch(/employees: EmployeJoint \| null/)
    // Si `EmployeJoint` disparaît (renommée, supprimée), les 14 `AvecEmploye<T>`
    // ne résolvent plus : `tsc` refuse les 14 lignes d'un coup. La garde vérifie
    // donc le lien de NOM, pas seulement que le type existe quelque part —
    // c'est ce qui a été mesuré : renommer l'interface sans toucher aux 14 appels
    // donne `tsc` 4 erreurs (TS2304, TS6196) et laisse les 17 tests verts.
    expect(src).toMatch(/type AvecEmploye<T> = T & \{ employees: EmployeJoint \| null \}/)
  })

  it('`EmployeJoint` couvre les colonnes réellement demandées par les `select`', () => {
    const src = lire(PAYROLL)
    // Mesuré en base le 2026-10-02 : `employees` a bien `first_name`/`last_name`
    // — que `Employee` (src/types) ne déclare PAS. C'est pourquoi le type joint
    // est déclaré côté requête plutôt qu'en élargissant `Employee` en silence.
    const demandes = new Set(
      [...src.matchAll(/select\('\*,\s*employees(?:\([^)]*\))?/g)]
        .flatMap((m) => [...m[0].matchAll(/(\w+)/g)].map((c) => c[1])),
    )
    const exigees = ['first_name', 'last_name', 'name', 'position', 'department']
    for (const colonne of exigees) {
      expect(new RegExp(`\\b${colonne}\\?: string \\| null`).test(src),
        `EmployeJoint ne déclare pas ${colonne}`).toBe(true)
    }
    expect(exigees.some((c) => demandes.has(c))).toBe(true)
  })

  it('les 10 écrans de paie ne sont plus des tableaux `any`', () => {
    // Le portillon (`check-any-ceiling.mjs`) lit le TEXTE et retient les positions
    // de type. Écrire l'un de ces motifs — même dans une chaîne de test de ce
    // fichier, même dans ce commentaire — est compté comme une dette. Ce libellé
    // et ce commentaire sont donc écrits sans les motifs. Mesuré le 2026-10-02 :
    // 1 de trop, trouvé de cette façon.
    const src = lire('src/pages/Phase4Pages.tsx')
    const restants = codeSeul(src).filter((l) => /useState<any\[\]>/.test(l))
    expect(restants).toEqual([])
    // Et ils sont nommés depuis leur fonction de requête.
    expect(src).toMatch(/useState<Awaited<ReturnType<typeof getSalaryAdvances>>>/)
    expect(src).toMatch(/useState<Awaited<ReturnType<typeof getPayrollArchives>>>/)
  })

  it('une colonne absente de la ressource jointe est refusée par `tsc`', () => {
    // Preuve comportementale du garde-fou : `position_du_salarie` n'existe ni en
    // base ni dans `EmployeJoint`, donc l'écran ne peut pas la lire. On vérifie
    // que le type ne l'expose pas, plutôt que de le supposer.
    const src = lire(PAYROLL)
    const bloc = src.slice(src.indexOf('interface EmployeJoint'))
    const lignes = bloc.slice(0, bloc.indexOf('}'))
    expect(lignes).not.toMatch(/position_du_salarie/)
    // La seule présence de `unknown` toléré est celle du type d'index interne.
    expect(lignes).not.toMatch(/:\s*any\b/)
  })
})

// ============ AUD-ACCES-02 — l'intégration en paie d'une note de frais ============

describe('AUD-ACCES-02 — note de frais : intégration en paie lue sur sa vraie table', () => {
  it("interroge `payroll_variable_elements` filtré sur source='expense_report'", async () => {
    setMockData([])
    const { getExpensePayrollIntegration } = await import('@/lib/queries/sprintDE')
    await getExpensePayrollIntegration()
    expect(supabase.from).toHaveBeenCalledWith('payroll_variable_elements')
    expect(mockChain.eq).toHaveBeenCalledWith('source', 'expense_report')
  })

  it('rend le rattachement par note, et `integrated` NULL veut dire « pas encore »', async () => {
    // W9 (265) : les alimentations de la base ne posent pas toujours `integrated`.
    setMockData([
      { source_id: 'note-1', integrated: true, pay_run_id: 'lot-1' },
      { source_id: 'note-2', integrated: false, pay_run_id: 'lot-2' },
      { source_id: 'note-3', integrated: null, pay_run_id: null },
    ])
    const { getExpensePayrollIntegration } = await import('@/lib/queries/sprintDE')
    const liens = await getExpensePayrollIntegration()
    expect(liens).toEqual([
      { sourceId: 'note-1', integrated: true, payRunId: 'lot-1' },
      { sourceId: 'note-2', integrated: false, payRunId: 'lot-2' },
      { sourceId: 'note-3', integrated: false, payRunId: null },
    ])
  })

  it('écarte une ligne sans `source_id` — elle ne rattache aucune note', async () => {
    setMockData([
      { source_id: null, integrated: true, pay_run_id: 'lot-1' },
      { source_id: 'note-1', integrated: true, pay_run_id: 'lot-1' },
    ])
    const { getExpensePayrollIntegration } = await import('@/lib/queries/sprintDE')
    const liens = await getExpensePayrollIntegration()
    expect(liens).toHaveLength(1)
    expect(liens[0].sourceId).toBe('note-1')
  })

  it("l'écran ne lit plus `payroll_integrated` / `payroll_variable_id`", () => {
    const src = lire('src/pages/EmployeeExpensesPage.tsx')
    const fautives = codeSeul(src).filter((l) => /payroll_integrated|payroll_variable_id/.test(l))
    expect(fautives).toEqual([])
    // Et il lit bien le rattachement, avec ses TROIS états.
    expect(src).toContain('getExpensePayrollIntegration')
    expect(src).toMatch(/payrollByReport\.get\(reportId\)/)
    expect(src).toContain("t('expenses.payrollNone')")
    expect(src).toContain("t('expenses.payrollPending')")
    expect(src).toContain("t('expenses.payrollIntegrated')")
  })
})

// ============ AUD-ACCES-03 — le tiers vit sur les lignes ============

describe('AUD-ACCES-03 — interrogation tiers : le compte se lit sur les LIGNES', () => {
  it("l'écran ne lit plus `third_party_account` sur l'en-tête", () => {
    const src = lire('src/pages/Phase7DInquiryPages.tsx')
    const fautives = codeSeul(src).filter((l) => /third_party_account/.test(l))
    expect(fautives).toEqual([])
  })

  it('résout le tiers depuis `journal_lines.account_tiers`, sans doublon', () => {
    const src = lire('src/pages/Phase7DInquiryPages.tsx')
    const corps = corpsDe(src, 'function entryThirdPartyAccounts')
    expect(corps).toMatch(/entry\.journal_lines/)
    expect(corps).toMatch(/\.account_tiers/)
    expect(corps).toMatch(/new Set\(/)
  })

  it('la colonne affiche les tiers résolus et le filtre en atteint un', () => {
    const src = lire('src/pages/Phase7DInquiryPages.tsx')
    expect(src).toMatch(/tiers\.join\(', '\)/)
    expect(src).toMatch(/tiers\.some\(c => c\.includes\(accountFilter\)\)/)
  })
})


// ============ AUD-ACCES-05 — l'identité d'une échéance ============

describe("AUD-ACCES-05 — échéancier : la ligne porte l'id de son document source", () => {
  it("getEcheancier remonte l'id de la facture", async () => {
    setMockData([{ id: 'doc-1', number: 'INV-001', total: 1000, due_date: '2025-01-01', status: 'sent', customer_name: 'Cust' }])
    const { getEcheancier } = await import('@/lib/queries/accounting')
    const lignes = await getEcheancier('customer')
    expect(lignes).toHaveLength(1)
    expect(lignes[0].id).toBe('doc-1')
    expect(lignes[0].type).toBe('customer')
  })

  it("getEcheancier remonte l'id de la facture d'achat aussi", async () => {
    setMockData([{ id: 'doc-2', number: 'PINV-001', total: 500, due_date: '2025-02-01', status: 'approved', supplier_name: 'Sup' }])
    const { getEcheancier } = await import('@/lib/queries/accounting')
    const lignes = await getEcheancier('supplier')
    expect(lignes).toHaveLength(1)
    expect(lignes[0].id).toBe('doc-2')
    expect(lignes[0].type).toBe('supplier')
  })

  it("l'écran clé sur cet id, sans repli sur l'index", () => {
    const src = lire('src/pages/EcheancierPage.tsx')
    expect(src).toContain('<TableRow key={r.id}>')
    const fautives = codeSeul(src).filter((l) => /key=\{r\.id \|\| i\}/.test(l))
    expect(fautives).toEqual([])
    expect(src).toContain('useState<Awaited<ReturnType<typeof getEcheancier>>>')
  })
})

// ============ AUD-ACCES-06 — le type d'une section analytique ============

describe('AUD-ACCES-06 — saisie OD analytique : le type se lit sur `section_type`', () => {
  it("l'écran ne lit plus `s.type`, qui n'existe ni en base ni dans le type", () => {
    const src = lire('src/pages/Phase7DInquiryPages.tsx')
    const fautives = codeSeul(src).filter((l) => /\bs\.type\b/.test(l))
    expect(fautives).toEqual([])
    // La colonne réelle (274), et les deux libellés — une section « total » n'est
    // jamais imputable, elle doit se distinguer.
    expect(src).toMatch(/s\.section_type === 'total'/)
    expect(src).toContain("t('analyticSections.typeTotal')")
    expect(src).toContain("t('analyticSections.typeSection')")
  })

  it('les quatre états nommés ne sont plus des tableaux de `any`', () => {
    const src = lire('src/pages/Phase7DInquiryPages.tsx')
    expect(src).toContain('useState<Awaited<ReturnType<typeof getAnalyticSections>>>')
    expect(src).toContain('useState<Awaited<ReturnType<typeof getAnalyticLedgerLines>>>')
    expect(src).toContain('useState<Awaited<ReturnType<typeof getJournalEntries>>>')
    expect(src).toContain('useState<Awaited<ReturnType<typeof getChartAccounts>>>')
    const restants = codeSeul(src).filter((l) => /useState<any\[\]>/.test(l))
    expect(restants).toEqual([])
  })
})

