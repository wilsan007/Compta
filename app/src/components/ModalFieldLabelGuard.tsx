import { useEffect } from 'react'

/**
 * Donne un nom accessible aux champs des fenêtres écrites à la main.
 *
 * L'essaim QA a mesuré 43 champs, dans les fenêtres de 32 écrans, qu'un lecteur
 * d'écran annonce « champ de saisie » sans dire lequel : le libellé est bien
 * affiché à côté, mais aucun `id`/`htmlFor` ne les relie. Les composants
 * partagés (`Input`, `Select`) le font depuis LOT7-07 ; les fenêtres écrites à
 * la main l'oublient, une par une.
 *
 * Cette garde ne devine rien : elle ne se sert QUE d'un `<label>` visible présent
 * dans le même bloc que le champ — c'est-à-dire du libellé que l'utilisateur
 * lit. Elle ne touche pas à un champ déjà nommé, ni à un champ enveloppé dans
 * son propre `<label>` (déjà correctement associé par le navigateur), ni à un
 * champ sans libellé du tout : ceux-là restent au registre, à corriger à la main.
 */
export function ModalFieldLabelGuard() {
  useEffect(() => {
    function nameFields() {
      for (const overlay of document.querySelectorAll<HTMLElement>('.fixed.inset-0')) {
        for (const field of overlay.querySelectorAll<HTMLElement>('input, select, textarea')) {
          if (field.getAttribute('type') === 'hidden') continue
          if (field.getAttribute('aria-label') || field.getAttribute('aria-labelledby')) continue
          if (field.id || field.getAttribute('name') || field.getAttribute('placeholder')) continue
          if (field.closest('label')) continue
          const block = field.closest('div, td') ?? overlay
          const label = [...block.querySelectorAll('label')].find((el) => el !== field)
          let text = (label?.textContent ?? '').replace(/[*:]/g, ' ').replace(/\s+/g, ' ').trim()
          if (!text) {
            // Le libellé n'est pas un <label> : il est souvent juste avant, dans un
            // <div>/<span> du même bloc. On ne prend qu'un texte court — un texte
            // long serait une aide, pas un nom de champ.
            const siblings = [...block.children]
            const index = siblings.findIndex((el) => el === field || el.contains(field))
            const before = index > 0 ? (siblings[index - 1].textContent ?? '').trim() : ''
            if (before.length > 1 && before.length < 60) text = before.replace(/[*:]/g, ' ').replace(/\s+/g, ' ').trim()
          }
          if (text) field.setAttribute('aria-label', text)
        }
      }
    }
    const observer = new MutationObserver(() => window.requestAnimationFrame(nameFields))
    observer.observe(document.body, { childList: true, subtree: true })
    nameFields()
    return () => observer.disconnect()
  }, [])
  return null
}
