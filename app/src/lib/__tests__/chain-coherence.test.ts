import { describe, it, expect, vi, beforeEach } from 'vitest'

// ============ Mock Infrastructure ============
// Deux tables lues par deux requêtes distinctes : `from('chain_invariants')`
// et `from('chain_invariant_results')` ne rendent pas la même chose. Le mock
// répond donc par TABLE, pas par un chain unique partagé.
//
// Le chain est typé par une interface minimaliste — pas par `any`. La dette de
// `any` est un plafond qui ne peut QUE descendre (garde `check-any-ceiling`),
// et un mock non typé la ferait monter à chaque test ajouté.
interface MockChain {
  select: ReturnType<typeof vi.fn>
  eq: ReturnType<typeof vi.fn>
  order: ReturnType<typeof vi.fn>
  limit: ReturnType<typeof vi.fn>
  then: (resolve: (value: { data: unknown; error: unknown }) => unknown) => Promise<unknown>
}

interface Resolved {
  data: unknown
  error: unknown
}

function makeChain(resolved: Resolved): MockChain {
  const chain: MockChain = {
    select: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    order: vi.fn(() => chain),
    limit: vi.fn(() => chain),
    then: (resolve) => Promise.resolve(resolved).then(resolve),
  }
  return chain
}

const parTable: Record<string, MockChain> = {}
function setMockData(table: string, data: unknown, error: unknown = null) {
  parTable[table] = makeChain({ data, error })
}

vi.mock('@/lib/supabase', () => ({
  supabase: { from: vi.fn((t: string) => parTable[t]) },
  getCachedTenantId: vi.fn(() => 'societe-1'),
  isTenantTable: vi.fn(() => true),
}))

import { getChainInvariants, getChainCoherenceIndex } from '@/lib/queries/chainCoherence'

// ============ Fixtures ============
function invariant(code: string, modules: string[] = ['ventes', 'compta']) {
  return { code, libelle: `Invariant ${code}`, modules }
}

/** Un résultat de la 413. `mesure_le` décroissante = du plus récent au plus ancien. */
function resultat(
  code: string,
  verdict: string,
  mesure_le: string,
  ecart: string | null = null,
  lignes_en_ecart = 0,
) {
  return { code, verdict, mesure_a: '100', mesure_b: '100', ecart, lignes_en_ecart, detail: null, mesure_le }
}

beforeEach(() => {
  setMockData('chain_invariants', [])
  setMockData('chain_invariant_results', [])
})

// ============ L4 — l'indice de cohérence, lu côté écran ============
describe("L4 : l'indice de cohérence lu côté écran", () => {
  // T01 — le cas qui rendait la garde rouge : les deux tables de la 413
  // étaient écrites par la migration et lues par PERSONNE. Le plafond des
  // tables non lues ne peut pas être respecté sans un lecteur réel.
  it("T01 : lit les DEUX tables de la 413, pas seulement les résultats", async () => {
    setMockData('chain_invariants', [invariant('INV-01'), invariant('INV-02')])
    setMockData('chain_invariant_results', [
      resultat('INV-01', 'tenu', '2026-10-02T02:00:00Z'),
      resultat('INV-02', 'rompu', '2026-10-02T02:00:00Z', '12.50', 3),
    ])

    const invariants = await getChainInvariants()

    expect(invariants).toHaveLength(2)
    expect(invariants.map((i) => i.code).sort()).toEqual(['INV-01', 'INV-02'])
  })

  // T02 — un invariant SANS résultat n'est pas un invariant rompu : il n'a
  // jamais été mesuré. Le dire `rompu` serait inventer une alerte.
  it("T02 : un invariant jamais mesuré vaut `non_mesure`, jamais `rompu`", async () => {
    setMockData('chain_invariants', [invariant('INV-01'), invariant('INV-09')])
    setMockData('chain_invariant_results', [resultat('INV-01', 'tenu', '2026-10-02T02:00:00Z')])

    const invariants = await getChainInvariants()
    const inv9 = invariants.find((i) => i.code === 'INV-09')

    expect(inv9?.verdict).toBe('non_mesure')
    expect(inv9?.nb_releves).toBe(0)
    expect(inv9?.mesure_le).toBe('')
  })

  // T03 — l'historique ne doit pas noyer l'écran : c'est le DERNIER relevé
  // qui fait foi, les suivants ne servent qu'à compter les nuits.
  it("T03 : garde le DERNIER relevé et compte les nuits écoulées", async () => {
    setMockData('chain_invariants', [invariant('INV-01')])
    setMockData('chain_invariant_results', [
      resultat('INV-01', 'rompu', '2026-10-02T02:00:00Z', '5', 2),
      resultat('INV-01', 'rompu', '2026-10-01T02:00:00Z', '9', 4),
      resultat('INV-01', 'tenu', '2026-09-30T02:00:00Z'),
    ])

    const [inv] = await getChainInvariants()

    expect(inv.verdict).toBe('rompu')
    expect(inv.mesure_le).toBe('2026-10-02T02:00:00Z')
    expect(inv.ecart).toBe(5)
    expect(inv.lignes_en_ecart).toBe(2)
    expect(inv.nb_releves).toBe(3)
  })

  // T04 — un verdict hors des trois valeurs possibles ne doit pas devenir
  // une alerte : le CHECK de la 413 l'interdit en base, mais le lecteur ne
  // doit pas inventer une rupture sur une valeur qu'il ne connaît pas.
  it("T04 : un verdict inconnu retombe sur `non_mesure`, jamais sur `rompu`", async () => {
    setMockData('chain_invariants', [invariant('INV-01')])
    setMockData('chain_invariant_results', [resultat('INV-01', 'valeur_fantome', '2026-10-02T02:00:00Z')])

    const [inv] = await getChainInvariants()

    expect(inv.verdict).toBe('non_mesure')
  })

  // T05 — les ruptures d'abord : c'est ce que l'éditeur vient chercher.
  it("T05 : classe les `rompu` avant les `tenu`, et les `non_mesure` en dernier", async () => {
    setMockData('chain_invariants', [invariant('INV-01'), invariant('INV-02'), invariant('INV-03')])
    setMockData('chain_invariant_results', [
      resultat('INV-01', 'tenu', '2026-10-02T02:00:00Z'),
      resultat('INV-02', 'rompu', '2026-10-02T02:00:00Z', '1'),
      // INV-03 : jamais mesuré.
    ])

    const invariants = await getChainInvariants()

    expect(invariants.map((i) => i.verdict)).toEqual(['rompu', 'tenu', 'non_mesure'])
  })

  // T06 — l'indice ne fond PAS les trois nombres en un pourcentage : « 15/20 »
  // cacherait qu'un invariant n'a jamais été mesuré. C'est la règle du dépôt :
  // rien n'est annoncé que la base ne l'ait confirmé.
  it("T06 : l'indice sépare tenu / rompu / non_mesure au lieu d'un score", async () => {
    setMockData('chain_invariants', [
      invariant('INV-01'),
      invariant('INV-02'),
      invariant('INV-03'),
      invariant('INV-04'),
    ])
    setMockData('chain_invariant_results', [
      resultat('INV-01', 'tenu', '2026-10-02T02:00:00Z'),
      resultat('INV-02', 'tenu', '2026-10-02T02:00:00Z'),
      resultat('INV-03', 'rompu', '2026-10-02T02:00:00Z', '3'),
      // INV-04 : jamais mesuré.
    ])

    const index = await getChainCoherenceIndex()

    expect(index).toEqual({
      tenu: 2,
      rompu: 1,
      non_mesure: 1,
      total: 4,
      mesure_le: '2026-10-02T02:00:00Z',
    })
  })

  // T07 — le dernier relevé de la société, pas celui du premier invariant :
  // les invariants ne sont pas forcément mesurés à la même seconde.
  it("T07 : la date de l'indice est le relevé le PLUS RÉCENT", async () => {
    setMockData('chain_invariants', [invariant('INV-01'), invariant('INV-02')])
    setMockData('chain_invariant_results', [
      resultat('INV-01', 'tenu', '2026-10-01T02:00:00Z'),
      resultat('INV-02', 'tenu', '2026-10-02T03:30:00Z'),
    ])

    const index = await getChainCoherenceIndex()

    expect(index.mesure_le).toBe('2026-10-02T03:30:00Z')
  })

  // T08 — une société sans aucun invariant ne renvoie pas un écran qui craque.
  it("T08 : une société sans invariant renvoie un indice vide, pas une erreur", async () => {
    const index = await getChainCoherenceIndex()

    expect(index).toEqual({ tenu: 0, rompu: 0, non_mesure: 0, total: 0, mesure_le: null })
  })

  // T09 — une erreur de lecture se propage : l'écran doit afficher un échec,
  // pas un indice à zéro qui ferait croire à une société parfaitement cohérente.
  it("T09 : une erreur de lecture est levée, jamais transformée en indice vide", async () => {
    setMockData('chain_invariants', null, { message: 'échec réseau' })

    await expect(getChainInvariants()).rejects.toThrow()
  })
})
