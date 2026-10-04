import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { ArrowRight, History, Loader2, Unlink } from 'lucide-react'
import { getChain, type ChainNode } from '@/lib/queries/chainView'
import { errorMessage } from '@/lib/utils'

// ============================================================
// I-01 — la « Vue Chaîne » : le composant D'INTERFACE unique,
// réutilisé par tous les écrans.
//
// Le référentiel (D.4) est net sur la forme : « une frise cliquable :
// ce qui l'a produit, ce qu'il a produit, et les pièces comptables
// associées ». Ce composant rend cette frise, et RIEN D'AUTRE : il ne
// décide ni de la direction, ni de la profondeur.
//
// TROIS RÈGLES, TENUES ICI.
//
// 1. **La base fait foi.** Les nœuds viennent de
//    `chain_document_arborescence` (460). Ce composant n'invente aucun
//    lien : un maillon qui ne pose pas son lien reste muet, et c'est le
//    maillon qu'il faut corriger, pas l'écran.
// 2. **Un lien fermé s'affiche comme tel.** `rompu` / `remplace` ne
//    sont pas des erreurs : ce sont des annulations et des
//    contre-passations, et l'historique se montre. C'est l'option
//    `historique`, éteinte par défaut — l'état vivant d'abord.
// 3. **Un document sans chaîne n'est pas une erreur.** Une facture
//    saisie à la main n'a ni amont ni aval ; l'écran affiche un mot
//    calme, pas une alerte rouge. Une alerte pour un cas normal est
//    une alerte qu'on finit par ignorer.

interface ChainTimelineProps {
  /** Le type au registre `chain_document_types` (ex. `sales_orders`). */
  type: string
  /** L'identifiant du document. */
  id: string
  /** Repli quand la table des 27 types ne connaît pas ce type. */
  libelle?: string
  /** Profondeur maximale de chaque côté. */
  profondeur?: number
  /** Inclure les liens fermés (annulés, contre-passés). */
  historique?: boolean
  /** Un nœud est cliquable si l'écran sait l'ouvrir. */
  onOpen?: (node: ChainNode) => void
}

export function ChainTimeline({
  type,
  id,
  libelle,
  profondeur = 20,
  historique = false,
  onOpen,
}: ChainTimelineProps) {
  const { t } = useTranslation('crossModule')
  const [amont, setAmont] = useState<ChainNode[]>([])
  const [aval, setAval] = useState<ChainNode[]>([])
  const [chargement, setChargement] = useState(true)
  const [erreur, setErreur] = useState<string | null>(null)

  useEffect(() => {
    let annule = false
    setChargement(true)
    setErreur(null)
    // Les deux directions sont demandées en parallèle : la frise est
    // une seule ligne, elle apparaît donc d'un coup.
    Promise.all([
      getChain(type, id, { sens: 'amont', profondeur, historique }),
      getChain(type, id, { sens: 'aval', profondeur, historique }),
    ])
      .then(([a, v]) => {
        if (annule) return
        setAmont(a.filter((n) => n.sens !== 'racine'))
        setAval(v.filter((n) => n.sens !== 'racine'))
      })
      .catch((e: unknown) => !annule && setErreur(errorMessage(e)))
      .finally(() => !annule && setChargement(false))
    return () => {
      annule = true
    }
  }, [type, id, profondeur, historique])

  if (chargement) {
    return (
      <div className="flex items-center gap-2 text-sm text-[var(--color-text-secondary)]">
        <Loader2 className="w-4 h-4 animate-spin" />
        {t('chain.loading')}
      </div>
    )
  }

  if (erreur) {
    return (
      <div className="text-sm text-[var(--color-danger)]" role="alert">
        {t('chain.error', { message: erreur })}
      </div>
    )
  }

  // Un document réellement seul : ni amont, ni aval. C'est normal — une
  // saisie manuelle n'a pas d'origine. On le dit, calmement.
  if (amont.length === 0 && aval.length === 0) {
    return (
      <div className="flex items-center gap-2 text-sm text-[var(--color-text-secondary)]">
        <Unlink className="w-4 h-4" />
        {t('chain.isolated')}
      </div>
    )
  }

  const ligne = (n: ChainNode) => {
    const fermee = n.etat !== 'actif' && n.etat !== 'racine'
    return (
      <li key={`${n.type}:${n.id}`}>
        <button
          type="button"
          disabled={!onOpen}
          onClick={() => onOpen?.(n)}
          className={`text-left px-2 py-1 rounded text-sm ${
            onOpen ? 'hover:bg-[var(--color-neutral-100)]' : 'cursor-default'
          } ${fermee ? 'line-through opacity-70' : ''}`}
        >
          <span className="font-medium">{n.libelle ?? libelle ?? n.type}</span>
          {fermee && (
            <span className="ml-2 inline-flex items-center gap-1 text-xs text-[var(--color-text-secondary)]">
              <History className="w-3 h-3" />
              {t(`chain.etats.${n.etat}`, { defaultValue: n.etat })}
            </span>
          )}
          {n.effet && <span className="ml-2 text-xs text-[var(--color-text-secondary)]">{n.effet}</span>}
        </button>
      </li>
    )
  }

  return (
    <div className="flex items-start gap-3 flex-wrap text-sm" data-testid="chain-timeline">
      {amont.length > 0 && (
        <ul className="flex flex-wrap items-center gap-1">
          {amont.map(ligne)}
          <li className="px-1 text-[var(--color-text-secondary)]" aria-hidden>
            <ArrowRight className="w-4 h-4" />
          </li>
        </ul>
      )}
      <span className="font-semibold px-2 py-1 rounded bg-[var(--color-neutral-100)]">
        {libelle ?? type}
      </span>
      {aval.length > 0 && (
        <ul className="flex flex-wrap items-center gap-1">
          <li className="px-1 text-[var(--color-text-secondary)]" aria-hidden>
            <ArrowRight className="w-4 h-4" />
          </li>
          {aval.map(ligne)}
        </ul>
      )}
    </div>
  )
}