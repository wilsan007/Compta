import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { HelpCircle, Loader2, Receipt } from 'lucide-react'
import { expliquerMontant, type ExplicationPiece } from '@/lib/queries/chainView'
import { errorMessage, formatCurrency } from '@/lib/utils'

// ============================================================
// I-08 — « pourquoi ce chiffre ? » : dérouler la chaîne qui produit
// un montant.
//
// La 462 rend, pour un document, ses pièces de chaîne, ses écritures et
// ses lignes. Ce composant les MONTRE. Il ne fait qu'une chose de plus,
// et c'est la plus importante : ne RIEN calculer.
//
// TROIS RÈGLES.
//
// 1. **Le montant vient de la base.** L'écran affiche `montant` ; il ne
//    le recompose pas. Recalculer à l'affichage, c'est le défaut même
//    qu'I-08 supprime (5 fichiers calculaient une marge, 8 un budget).
//    Le total affiché est donc la SOMME DE CE QUE LA BASE A RENDU, et
//    rien d'autre.
// 2. **Une explication vide est une vraie réponse.** Un document sans
//    maillon ne renvoie rien : on le dit. Jamais de calcul de secours —
//    un chiffre qu'on ne sait pas expliquer doit le dire, sinon c'est
//    l'écran qui invente.
// 3. **Le détail est caché par défaut.** Dix lignes d'écriture dans une
//    fiche invoice écrasent la fiche. Le client ouvre quand il veut
//    savoir, il ne subit pas l'explication.

interface ExplainAmountProps {
  type: string
  id: string
  /** Le montant affiché ailleurs sur l'écran, pour la comparaison. */
  montantAffiche?: number | null
}

export function ExplainAmount({ type, id, montantAffiche = null }: ExplainAmountProps) {
  const { t } = useTranslation('crossModule')
  const [pieces, setPieces] = useState<ExplicationPiece[]>([])
  const [chargement, setChargement] = useState(true)
  const [erreur, setErreur] = useState<string | null>(null)
  const [ouvert, setOuvert] = useState(false)

  useEffect(() => {
    let annule = false
    setChargement(true)
    setErreur(null)
    expliquerMontant(type, id)
      .then((p) => !annule && setPieces(p))
      .catch((e: unknown) => !annule && setErreur(errorMessage(e)))
      .finally(() => !annule && setChargement(false))
    return () => {
      annule = true
    }
  }, [type, id])

  if (chargement) {
    return (
      <button
        type="button"
        onClick={() => setOuvert(!ouvert)}
        className="mt-2 inline-flex items-center gap-1 text-xs text-[var(--color-text-secondary)]"
      >
        <Loader2 className="w-3 h-3 animate-spin" />
        {t('chain.explain.loading')}
      </button>
    )
  }

  const lignes = pieces.filter((p) => p.genre === 'ligne')
  const ecritures = pieces.filter((p) => p.genre === 'ecriture')

  if (erreur) {
    return (
      <p className="mt-2 text-xs text-[var(--color-danger)]" role="alert">
        {t('chain.explain.error', { message: erreur })}
      </p>
    )
  }

  // RIEN à expliquer : c'est une réponse, pas un échec. On le dit sans
  // alarme — une saisie manuelle n'a, par construction, aucune origine.
  const sansProvenance = ecritures.length === 0 && lignes.length === 0

  return (
    <div className="mt-2" data-testid="explain-amount">
      <button
        type="button"
        onClick={() => setOuvert(!ouvert)}
        aria-expanded={ouvert}
        className="inline-flex items-center gap-1 text-xs text-[var(--color-primary)] hover:underline"
      >
        <HelpCircle className="w-3 h-3" />
        {t('chain.explain.toggle')}
      </button>

      {ouvert && (
        <div className="mt-2 text-xs space-y-2">
          {sansProvenance ? (
            <p className="text-[var(--color-text-secondary)]">{t('chain.explain.none')}</p>
          ) : (
            <>
              {ecritures.map((e) => (
                <div key={`ec-${e.id}`} className="flex items-center gap-2">
                  <Receipt className="w-3 h-3" aria-hidden="true" />
                  <span className="font-medium">{e.libelle ?? t('chain.explain.entry')}</span>
                  {e.libelle_piece && (
                    <span className="text-[var(--color-text-secondary)]">{e.libelle_piece}</span>
                  )}
                  {e.montant != null && (
                    <span className="font-mono">{formatCurrency(Number(e.montant))}</span>
                  )}
                </div>
              ))}
              <table className="w-full">
                <tbody>
                  {lignes.map((l) => (
                    <tr key={`li-${l.id}`}>
                      <td className="font-mono w-24">{l.libelle}</td>
                      <td className="text-[var(--color-text-secondary)]">{l.libelle_piece}</td>
                      <td className="text-right font-mono">
                        {l.montant != null ? formatCurrency(Number(l.montant)) : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {montantAffiche != null && lignes.length > 0 && (
                <p className="text-[var(--color-text-secondary)]">
                  {t('chain.explain.sum', { montant: formatCurrency(Number(montantAffiche)) })}
                </p>
              )}
            </>
          )}
        </div>
      )}
    </div>
  )
}