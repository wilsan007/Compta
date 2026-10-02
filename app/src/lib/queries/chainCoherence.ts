import { supabase } from '@/lib/supabase'
import { getTenantId } from './core'
import type { Row } from '@/types/dbRow'

// ============================================================
// L4 — l'indice de cohérence des chaînages, lu côté écran.
//
// La migration 413 mesure VINGT invariants transversaux et publie un relevé
// par société et par nuit (`chain_invariants`, `chain_invariant_results`).
// Elle écrivait ces deux tables, et **personne ne les lisait** : le score
// existait en base, et l'éditeur le découvrait en ouvrant un client SQL.
// C'est ce que mesure la garde `check-unused-tables.mjs` (77 tables non
// lues > plafond 75).
//
// Ce module est donc la **moitié « lecture » de L4** : il rend l'indice
// visible là où se décide la reprise d'une clôture. Il ne mesure rien —
// c'est le rôle du job `audit_chains_nocturne`, en base.
//
// DEUX RÈGLES TENUES ICI.
//
// 1. **Le dernier relevé par invariant, pas l'historique entier.** Une société
//    qui tourne depuis des mois porte une ligne de résultat par invariant et
//    par nuit : renvoyer tout ferait grossir la charge de l'écran sans rien
//    apprendre. On garde le plus récent, et l'on expose `nb_releves` pour que
//    l'écran puisse dire « 42 nuits » sans les recharger.
//
// 2. **Un invariant `non_mesure` n'est pas un invariant rompu.** L'indice ne
//    ment pas sur ce qu'il ne sait pas mesurer : `non_mesure` est compté à
//    part, et `rompu` ne compte que les VRAIES ruptures. C'est ce qu'exige la
//    doctrine du dépôt — « rien n'est annoncé que la base ne l'ait confirmé ».

/** Un invariant transverse, tel que la 413 l'a inscrit. */
export interface ChainInvariant {
  code: string
  libelle: string
  /** Les modules que l'invariant relie entre eux (`ventes` → `compta`, …). */
  modules: string[]
  /** `tenu` = l'invariant tient, `rompu` = écart constaté, `non_mesure` = hors périmètre mesurable. */
  verdict: 'tenu' | 'rompu' | 'non_mesure'
  mesure_a: number | null
  mesure_b: number | null
  ecart: number | null
  lignes_en_ecart: number
  detail: Record<string, unknown> | null
  mesure_le: string
  /** Combien de nuits cet invariant a été mesuré — l'ancienneté du relevé. */
  nb_releves: number
}

/**
 * L'indice de cohérence de la société courante : un invariant par `code`,
 * avec son verdict et son **dernier** relevé.
 *
 * @param limit Nombre maximum d'invariants renvoyés (les plus dégradés d'abord).
 */
export async function getChainInvariants(limit = 100): Promise<ChainInvariant[]> {
  const tid = await getTenantId()

  // Les invariants sont la carte : peu de lignes, on les prend toutes.
  let invQ = supabase.from('chain_invariants').select('code, libelle, modules').order('code')
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: invariants, error: invErr } = await invQ
  if (invErr) throw invErr

  // Les résultats sont l'historique : on ne descend que jusqu'au dernier
  // relevé de chaque code.
  let resQ = supabase
    .from('chain_invariant_results')
    .select('code, verdict, mesure_a, mesure_b, ecart, lignes_en_ecart, detail, mesure_le')
    .order('mesure_le', { ascending: false })
    .limit(5000)
  if (tid) resQ = resQ.eq('tenant_id', tid)
  const { data: results, error: resErr } = await resQ
  if (resErr) throw resErr

  const parCode = new Map<string, ChainInvariant>()
  for (const inv of (invariants ?? []) as Pick<Row<'chain_invariants'>, 'code' | 'libelle' | 'modules'>[]) {
    parCode.set(inv.code, {
      code: inv.code,
      libelle: inv.libelle,
      modules: inv.modules ?? [],
      verdict: 'non_mesure',
      mesure_a: null,
      mesure_b: null,
      ecart: null,
      lignes_en_ecart: 0,
      detail: null,
      mesure_le: '',
      nb_releves: 0,
    })
  }

  // `results` est trié du plus récent au plus ancien : le PREMIER résultat
  // rencontré pour un code est donc son dernier relevé. Les suivants ne font
  // que compter les nuits.
  for (const r of (results ?? []) as Row<'chain_invariant_results'>[]) {
    const courant = parCode.get(r.code)
    if (!courant) continue
    courant.nb_releves += 1
    if (courant.nb_releves === 1) {
      // La 413 pose `CHECK (verdict = ANY (ARRAY['tenu','rompu','non_mesure']))` :
      // PostgREST rend `text`, le générateur ne peut pas lire un CHECK comme un
      // enum. On ramène donc au type fermé — et un verdict inconnu vaudrait
      // `non_mesure`, jamais `rompu` : on n'invente pas une alerte.
      const verdict = r.verdict
      courant.verdict =
        verdict === 'tenu' || verdict === 'rompu' ? verdict : 'non_mesure'
      courant.mesure_a = r.mesure_a === null ? null : Number(r.mesure_a)
      courant.mesure_b = r.mesure_b === null ? null : Number(r.mesure_b)
      courant.ecart = r.ecart === null ? null : Number(r.ecart)
      courant.lignes_en_ecart = r.lignes_en_ecart ?? 0
      courant.detail = (r.detail ?? null) as Record<string, unknown> | null
      courant.mesure_le = r.mesure_le
    }
  }

  // Les plus dégradés d'abord : `non_mesure` passe APRÈS `rompu` — un
  // invariant qu'on ne sait pas mesurer n'est pas une alerte.
  const rang: Record<ChainInvariant['verdict'], number> = { rompu: 0, tenu: 1, non_mesure: 2 }
  return [...parCode.values()]
    .sort((a, b) => rang[a.verdict] - rang[b.verdict] || a.code.localeCompare(b.code))
    .slice(0, limit)
}

/**
 * L'indice de cohérence en une ligne — l'indicateur qu'un tableau de bord
 * affiche : `tenu` sur 13, `rompu` sur 2, `non_mesure` sur 5.
 *
 * Les trois nombres sont renvoyés SÉPARÉS et non fondus en un score : sans
 * eux, « 15/20 » cacherait qu'un invariant n'a jamais été mesuré. C'est le
 * défaut qu'un unique pourcentage rendrait invisible.
 */
export async function getChainCoherenceIndex(): Promise<{
  tenu: number
  rompu: number
  non_mesure: number
  total: number
  /** Le relevé le plus récent de la société, s'il y en a un. */
  mesure_le: string | null
}> {
  const invariants = await getChainInvariants(Number.MAX_SAFE_INTEGER)

  let tenu = 0
  let rompu = 0
  let non_mesure = 0
  let mesure_le: string | null = null
  for (const inv of invariants) {
    if (inv.verdict === 'rompu') rompu += 1
    else if (inv.verdict === 'tenu') tenu += 1
    else non_mesure += 1
    if (inv.mesure_le && (!mesure_le || inv.mesure_le > mesure_le)) mesure_le = inv.mesure_le
  }

  return { tenu, rompu, non_mesure, total: invariants.length, mesure_le }
}