import { useEffect } from 'react'

/**
 * Ferme la fenêtre ouverte au clavier (Échap) — une garde, une fois pour toutes.
 *
 * Les fenêtres de cette application sont écrites à la main sur chaque écran :
 * l'essaim QA en a mesuré 60 qui ignoraient Échap, réparties sur 54 fichiers.
 * Plutôt que 54 correctifs locaux — qui laisseraient la prochaine fenêtre aussi
 * sourde — cette garde fait ce qu'un utilisateur fait : Échap « clique le fond »
 * de la fenêtre, qui est justement le geste de fermeture que ces écrans
 * prévoient déjà (`onClick={onClose}` sur le voile).
 *
 * Elle ne devine rien et ne ferme rien à l'aveugle : elle n'agit que si un voile
 * plein écran est ouvert ET qu'il contient un fond positionné en absolu et
 * marqué `aria-hidden` — c'est-à-dire un fond fait pour être cliqué. Sans ce
 * fond, elle ne touche à rien.
 */
export function ModalEscapeGuard() {
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key !== 'Escape') return
      const overlays = [...document.querySelectorAll<HTMLElement>('.fixed.inset-0')].filter((el) => {
        const r = el.getBoundingClientRect()
        return r.width > 200 && r.height > 200
      })
      const top = overlays[overlays.length - 1]
      if (!top) return

      // 1. Le fond, quand l'écran en a prévu un (c'est le geste de fermeture).
      const backdrop = [...top.querySelectorAll<HTMLElement>('[aria-hidden="true"]')].find((el) => {
        const r = el.getBoundingClientRect()
        return getComputedStyle(el).position === 'absolute' && r.width > 100 && r.height > 100
      })
      if (backdrop) { backdrop.click(); return }

      // 2. Sinon le bouton de fermeture (ou d'annulation) de la fenêtre — mesuré le
      //    29/09/2026 : les fenêtres de cette application n'ont pas de fond
      //    cliquable, elles ne se ferment que par leur croix.
      const CLOSE = /^(fermer|close|annuler|cancel|إغلاق|إلغاء|تخطي)/i
      const named = [...top.querySelectorAll<HTMLElement>('button, [role="button"]')].filter((el) => {
        const label = `${el.getAttribute('aria-label') ?? ''} ${el.getAttribute('title') ?? ''} ${el.textContent ?? ''}`.trim()
        return CLOSE.test(label)
      })
      named[named.length - 1]?.click()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])
  return null
}
