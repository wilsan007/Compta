import { supabase } from '@/lib/supabase'
import { getTenantId } from './core'
import type { Row } from '@/types/dbRow'

// ============================================================
// L5 — le rapport du banc d'épreuves, lu côté écran (page « Robustesse »).
//
// La 433 pose le rapport DANS la base : `chain_banc_resultats` garde CHAQUE
// passage (un rapport qui ne garde que le dernier verdict ne dit pas si un
// défaut est nouveau ou ancien), et la vue `chain_banc_rapport` rend le DERNIER
// verdict par (maillon, épreuve). Ce module lit les deux TABLES typées et réduit
// côté écran — la vue n'est pas dans les types générés.
//
// DEUX RÈGLES TENUES ICI.
//
// 1. **Aucun `tenu` par défaut.** Une épreuve jamais jouée est `non_joue` et
//    RESTE VISIBLE : l'absence est publiée, elle ne peut pas passer pour un
//    succès. Un verdict inconnu vaut `non_joue`, jamais `tenu`.
// 2. **Le dernier passage, pas l'historique.** On garde le verdict le plus
//    récent par (maillon, épreuve) et l'on compte les passages, pour que
//    l'écran puisse dire « tenu depuis N relevés » sans tout recharger.

export type BancVerdict = 'tenu' | 'rompu' | 'non_joue'

/** Les huit épreuves du banc, dans l'ordre (D1 → D8). */
export const EPREUVES_BANC = ['D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8'] as const

/** Une épreuve d'un maillon, et son dernier verdict. */
export interface BancEpreuve {
  epreuve: string
  verdict: BancVerdict
  mesure: number | null
  obtenu: string | null
  raison: string | null
  /** Date du dernier passage, `null` si l'épreuve n'a jamais été jouée. */
  passe_le: string | null
  /** Combien de passages connus pour ce couple (maillon, épreuve). */
  passages: number
}

/** Un maillon du banc, avec ses huit épreuves et le compte par verdict. */
export interface BancMaillon {
  code: string
  libelle: string
  effet: string | null
  epreuves: BancEpreuve[]
  tenues: number
  rompues: number
  nonJouees: number
  /** Date du passage le plus récent, toutes épreuves confondues. */
  passe_le: string | null
}

function verdictFerme(v: string): BancVerdict {
  // La 433 pose `CHECK (verdict IN ('tenu','rompu','non_joue'))` : PostgREST
  // rend `text`. Un verdict inconnu vaut `non_joue` — on n'invente pas un succès.
  return v === 'tenu' || v === 'rompu' ? v : 'non_joue'
}

interface DernierPassage {
  verdict: BancVerdict
  mesure: number | null
  obtenu: string | null
  raison: string | null
  passe_le: string
  passages: number
}

/**
 * Le rapport du banc pour la société courante : un maillon par ligne, avec ses
 * huit épreuves et leur dernier verdict.
 */
export async function getChainBanc(): Promise<BancMaillon[]> {
  const tid = await getTenantId()

  // Le catalogue des maillons est lisible sans filtre de société (RLS : true).
  const { data: maillons, error: mErr } = await supabase
    .from('chain_banc_maillons')
    .select('code, libelle, effet')
    .eq('actif', true)
    .order('code')
  if (mErr) throw mErr

  // Les résultats sont l'historique : on descend du plus récent au plus ancien.
  let rQ = supabase
    .from('chain_banc_resultats')
    .select('code, epreuve, verdict, mesure, obtenu, raison, joue_le')
    .order('joue_le', { ascending: false })
    .limit(5000)
  if (tid) rQ = rQ.eq('tenant_id', tid)
  const { data: resultats, error: rErr } = await rQ
  if (rErr) throw rErr

  // `resultats` est trié du plus récent au plus ancien : le PREMIER rencontré
  // pour un (code, épreuve) est son dernier verdict ; les suivants comptent.
  const parCouple = new Map<string, DernierPassage>()
  for (const r of (resultats ?? []) as Row<'chain_banc_resultats'>[]) {
    const cle = `${r.code}#${r.epreuve}`
    const existant = parCouple.get(cle)
    if (existant) {
      existant.passages += 1
      continue
    }
    parCouple.set(cle, {
      verdict: verdictFerme(r.verdict),
      mesure: r.mesure === null ? null : Number(r.mesure),
      obtenu: r.obtenu,
      raison: r.raison,
      passe_le: r.joue_le,
      passages: 1,
    })
  }

  const lignes = (maillons ?? []) as Pick<Row<'chain_banc_maillons'>, 'code' | 'libelle' | 'effet'>[]
  return lignes.map((m) => {
    const epreuves: BancEpreuve[] = EPREUVES_BANC.map((ep) => {
      const d = parCouple.get(`${m.code}#${ep}`)
      return d
        ? {
            epreuve: ep,
            verdict: d.verdict,
            mesure: d.mesure,
            obtenu: d.obtenu,
            raison: d.raison,
            passe_le: d.passe_le,
            passages: d.passages,
          }
        : { epreuve: ep, verdict: 'non_joue', mesure: null, obtenu: null, raison: null, passe_le: null, passages: 0 }
    })
    const tenues = epreuves.filter((e) => e.verdict === 'tenu').length
    const rompues = epreuves.filter((e) => e.verdict === 'rompu').length
    const nonJouees = epreuves.filter((e) => e.verdict === 'non_joue').length
    const passe_le = epreuves.reduce<string | null>(
      (acc, e) => (e.passe_le && (!acc || e.passe_le > acc) ? e.passe_le : acc),
      null,
    )
    return { code: m.code, libelle: m.libelle, effet: m.effet, epreuves, tenues, rompues, nonJouees, passe_le }
  })
}
