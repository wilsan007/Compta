// UX-02 / LOT7-07 : aides à l'accessibilité, branchées sur les boîtes de dialogue
// de `components/ui.tsx` et `components/project-management/Modal.tsx`.
//
// Ont été retirés d'ici, parce qu'ils faisaient doublon avec du code réellement
// utilisé : `AccessibleButton` (le `Button` de `ui.tsx` porte la prop `ariaLabel`),
// `LiveRegion` et `useAnnouncement` (les toasts portent désormais eux-mêmes
// `role="status"` / `role="alert"`, cf. `lib/toast.tsx`).
import { useEffect, useRef } from 'react'

// LOT7-07 : `AccessibleButton` a été retiré — il faisait doublon avec le `Button`
// de `ui.tsx`, qui porte désormais la prop `ariaLabel` (et pose aussi `title`).

// Hook pour gérer le piège de focus dans les modales
/**
 * LOT7-07 — Piège de focus pour une boîte de dialogue.
 *
 * Ce hook existait mais n'était branché nulle part, et présentait quatre défauts qui
 * l'auraient rendu inopérant :
 *   1. le focus n'était jamais rendu à l'élément qui l'avait avant l'ouverture — après
 *      fermeture, la navigation au clavier repartait du début de la page ;
 *   2. la liste des éléments focalisables était calculée UNE SEULE FOIS au montage :
 *      dès que le contenu changeait (une ligne ajoutée à un formulaire), le piège
 *      bouclait sur des éléments disparus ;
 *   3. `querySelectorAll` ramenait aussi les éléments `disabled` ou masqués, qui ne
 *      peuvent pas recevoir le focus — le piège se bloquait dessus ;
 *   4. Échap émettait un `CustomEvent('escape')` que personne n'écoutait, sur le
 *      conteneur : il ne se déclenchait donc que si le focus était déjà dedans.
 *
 * `onEscape` est optionnel : sans lui, Échap ne ferme pas (certaines boîtes doivent
 * exiger un choix explicite).
 */
export function useFocusTrap(active: boolean, onEscape?: () => void) {
  const containerRef = useRef<HTMLDivElement>(null)
  // Conservé dans une ref : ne doit pas relancer l'effet à chaque rendu du parent.
  const escapeRef = useRef(onEscape)
  escapeRef.current = onEscape

  useEffect(() => {
    if (!active) return
    const container = containerRef.current
    if (!container) return

    // Qui avait le focus avant l'ouverture ? On le lui rendra à la fermeture.
    const previouslyFocused = document.activeElement as HTMLElement | null

    const FOCUSABLE =
      'a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])'

    // Recalculé à chaque appel : le contenu d'une boîte de dialogue change.
    // NB : ne PAS filtrer sur `offsetParent !== null` pour détecter les éléments
    // masqués — il vaut aussi `null` pour tout élément en `position: fixed`, ce que
    // sont justement les boîtes de dialogue, et toujours `null` sous jsdom. Le piège
    // se serait retrouvé sans aucun élément, donc inerte. On s'en tient aux marqueurs
    // explicites, quitte à retenir un élément masqué par CSS seul (cas rare, et moins
    // grave qu'un piège qui ne retient rien).
    function focusables(): HTMLElement[] {
      return Array.from(container!.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
        (el) =>
          !el.hasAttribute('disabled') &&
          !el.hidden &&
          el.getAttribute('aria-hidden') !== 'true' &&
          el.closest('[hidden], [aria-hidden="true"]') === null &&
          el.tabIndex !== -1
      )
    }

    const first = focusables()[0]
    if (first) first.focus()
    else container.focus()

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        if (escapeRef.current) {
          e.stopPropagation()
          escapeRef.current()
        }
        return
      }
      if (e.key !== 'Tab') return
      const items = focusables()
      if (items.length === 0) {
        e.preventDefault()
        return
      }
      const firstItem = items[0]
      const lastItem = items[items.length - 1]
      const current = document.activeElement as HTMLElement | null
      // Le focus a pu sortir de la boîte (clic ailleurs, contenu remplacé) : on le ramène.
      if (!current || !container!.contains(current)) {
        e.preventDefault()
        firstItem.focus()
        return
      }
      if (e.shiftKey && current === firstItem) {
        e.preventDefault()
        lastItem.focus()
      } else if (!e.shiftKey && current === lastItem) {
        e.preventDefault()
        firstItem.focus()
      }
    }

    // Sur `document` : Échap doit fonctionner même si le focus n'est pas dans la boîte.
    document.addEventListener('keydown', handleKeyDown)
    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      // Ne rendre le focus que s'il est encore dans le document (l'élément peut avoir
      // été démonté entre-temps).
      if (previouslyFocused && document.contains(previouslyFocused)) {
        previouslyFocused.focus()
      }
    }
  }, [active])

  return containerRef
}

/**
 * LOT7-07 — Empêche la page de défiler derrière une boîte de dialogue ouverte.
 * Restaure la valeur précédente plutôt que de forcer '' : deux boîtes superposées
 * ne doivent pas se marcher dessus.
 */
export function useLockBodyScroll(active: boolean) {
  useEffect(() => {
    if (!active) return
    const previous = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = previous }
  }, [active])
}
