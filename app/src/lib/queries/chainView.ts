import { supabase } from '@/lib/supabase'
import { getTenantId } from './core'

// ============================================================
// I-01 — la « Vue Chaîne », côté écran : la moitié LECTURE.
//
// L'innovation I-01 du référentiel (D.4) : « depuis n'importe quel
// document, une frise cliquable : ce qui l'a produit, ce qu'il a
// produit, et les pièces comptables associées ». La migration 460
// (`chain_document_arborescence`) fournit la moitié base ; ce module est
// l'autre moitié, et le composant `ChainTimeline` l'affiche.
//
// CE QUE CE MODULE NE FAIT PAS. Il n'invente aucun chaînage, ne
// complete aucune information : il rend ce que la base a tracé dans
// `document_links`. Si un maillon ne pose pas son lien, la frise reste
// muette — c'est le maillon qui est en cause, pas l'écran. Le doctrine
// du dépôt s'applique : « rien n'est annoncé que la base ne l'ait
// confirmé ».
//
// LE LIEN FERMÉ N'EST PAS UN LIEN MORT. Un lien `rompu` (annulation,
// contre-passation) reste dans l'historique : il raconte ce qui s'est
// passé. Par défaut la frise ne montre que l'état VIVANT (`actif`) ;
// `historique: true` ajoute les liens fermés, avec leur état. Rien
// n'est jamais effacé.

/** Un nœud de la chaîne : un document, et le lien qui l'yamenait. */
export interface ChainNode {
  /** `racine` = le document de départ, `amont` / `aval` = la direction suivie. */
  sens: 'racine' | 'amont' | 'aval'
  /** 0 pour le document de départ, puis 1, 2, … */
  profondeur: number
  /** Le type au registre `chain_document_types` (ex. `sales_orders`). */
  type: string
  id: string
  /** Libellé lisible, venu du registre — jamais traduit ici. */
  libelle: string | null
  /** L'effet produit par le maillon (`delivery.create`, `stock.reserve`…). */
  effet: string | null
  /** `actif`, `rompu`, `remplace` — ou `racine` pour le document de départ. */
  etat: string
  tour: number | null
  lien_date: string | null
  lien_id: string | null
}

/**
 * La chaîne complète d'un document.
 *
 * @param type    Le type au registre (`chain_document_types`), pas le nom d'une table.
 * @param id      L'identifiant du document.
 * @param options.sens      `aval` (ce qu'il a produit, par défaut) ou `amont`.
 * @param options.profondeur Borne la descente — la base la borne aussi (100).
 * @param options.historique Inclure les liens FERMÉS (annulés, contre-passés).
 */
export async function getChain(
  type: string,
  id: string,
  options: { sens?: 'aval' | 'amont'; profondeur?: number; historique?: boolean } = {}
): Promise<ChainNode[]> {
  const tid = await getTenantId()
  if (!tid) return []

  const { data, error } = await supabase.rpc('chain_document_arborescence', {
    p_tenant: tid,
    p_type: type,
    p_id: id,
    p_sens: options.sens ?? 'aval',
    p_profondeur: options.profondeur ?? 20,
    p_fermes: options.historique ?? false,
  })
  if (error) throw error

  // PostgREST rend une liste d'objets ; on la borne au contrat pour que
  // l'écran ne dépende pas de l'ordre des colonnes.
  return ((data ?? []) as ChainNode[]).map((n) => ({
    sens: n.sens,
    profondeur: n.profondeur,
    type: n.type,
    id: n.id,
    libelle: n.libelle ?? null,
    effet: n.effet ?? null,
    etat: n.etat ?? 'racine',
    tour: n.tour ?? null,
    lien_date: n.lien_date ?? null,
    lien_id: n.lien_id ?? null,
  }))
}

/**
 * La chaîne entière : l'amont ET l'aval, la racine en tête.
 *
 * C'est ce que veut dire « tout document ouvert sur son amont et son
 * aval » : l'écran affiche une frise unique, pas deux listes. La racine
 * est renvoyée deux fois (une par direction) ; on la garde une seule
 * fois et on reclasse les nœuds autour d'elle.
 */
export async function getChainComplete(
  type: string,
  id: string,
  options: { profondeur?: number; historique?: boolean } = {}
): Promise<{ amont: ChainNode[]; aval: ChainNode[] }> {
  const [amont, aval] = await Promise.all([
    getChain(type, id, { ...options, sens: 'amont' }),
    getChain(type, id, { ...options, sens: 'aval' }),
  ])
  return { amont: amont.filter((n) => n.sens !== 'racine'), aval: aval.filter((n) => n.sens !== 'racine') }
}

// ───────────────────────────────────────────────────────────────
// I-08 — le « pourquoi ce chiffre ? »
//
// La 462 déroule, pour un document, les pièces de sa chaîne, les
// ÉCRITURES produites et les LIGNES qui portent le montant.
//
// CE QUE L'ÉCRAN DOIT PRÉSERVER, ET QUOIQU'IL ARRIVE :
//
// 1. **Rien n'est recalculé ici.** `montant` vient de la base ; l'écran
//    l'affiche, il ne le recompose pas. Recalculer à l'affichage, c'est
//    exactement le défaut « définitions concurrentes » (5 fichiers
//    calculaient une marge, 8 un budget) qu'I-08 supprime.
// 2. **Une explication vide est une VRAIE RÉPONSE.** Une facture sans
//    maillon ne renvoie rien : l'écran doit le dire (« provenance non
//    renseignée »), pas combler avec un calcul de secours. Un chiffre
//    qu'on ne sait pas expliquer doit le dire — c'est tout le sens
//    d'I-08.

/** Une pièce de l'explication : document, écriture, ou ligne. */
export interface ExplicationPiece {
  genre: 'document' | 'ecriture' | 'ligne'
  type: string
  id: string
  libelle: string | null
  libelle_piece: string | null
  effet: string | null
  lien_etat: string | null
  profondeur: number
  montant: number | null
  debit: boolean | null
  date_piece: string | null
}

/** Le « pourquoi ce chiffre ? » : d'où vient ce montant ? */
export async function expliquerMontant(type: string, id: string): Promise<ExplicationPiece[]> {
  const tid = await getTenantId()
  if (!tid) return []

  const { data, error } = await supabase.rpc('chain_expliquer_montant', {
    p_tenant: tid,
    p_type: type,
    p_id: id,
  })
  if (error) throw error
  return (data ?? []) as ExplicationPiece[]
}