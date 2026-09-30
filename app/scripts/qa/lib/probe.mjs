// ============================================================
// qa/lib/probe.mjs — les sondes exécutées DANS la page (côté navigateur)
//
// Playwright sérialise ces fonctions : elles ne doivent référencer AUCUNE
// variable extérieure. Chaque sonde définit donc ses propres aides locales.
// ============================================================

// Mots qui retirent à un bouton son droit d'être cliqué par un robot :
// supprimer, valider, payer… Le clic d'un agent ne doit rien détruire.
const DESTRUCTIVE = [
  'supprim', 'delete', 'remove', 'retirer', 'annul', 'cancel', 'valider', 'validate',
  'confirmer', 'confirm', 'payer', 'pay', 'clôtur', 'clotur', 'close', 'envoyer', 'send',
  'signer', 'sign', 'rejeter', 'reject', 'réinitialis', 'reset', 'vider', 'purge',
  'désactiv', 'deactiv', 'archiver', 'archive', 'حذف', 'إلغاء', 'تأكيد',
]

// Boutons qui ouvrent normalement une fenêtre (formulaire, filtre, détail).
const OPENER = [
  'nouveau', 'nouvelle', 'new', 'ajouter', 'add', 'créer', 'create', 'modifier', 'edit',
  'détail', 'detail', 'voir', 'view', 'ouvrir', 'open', 'filtre', 'filter', 'exporter',
  'importer', 'import', 'paramétr', 'configur', 'réglage', 'setting',
  'générer', 'generer', 'generate', 'sélectionn', 'select', 'associer', 'rattacher',
  'إضافة', 'جديد', 'تعديل', 'تصفية',
]

export const isDestructive = (label) => {
  const l = (label || '').toLowerCase()
  return DESTRUCTIVE.some((w) => l.includes(w))
}
export const isOpener = (label) => {
  const l = (label || '').toLowerCase()
  return OPENER.some((w) => l.includes(w)) && !isDestructive(l)
}

/** Inventaire statique + analyse de mise en page de la page courante. */
export function collectDom() {
  const vis = (el) => {
    const r = el.getBoundingClientRect()
    const s = getComputedStyle(el)
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0.05
  }
  const nameOf = (el) => (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || el.value || '')
    .replace(/\s+/g, ' ').trim().slice(0, 60)
  const descOf = (el) => {
    const cls = typeof el.className === 'string' ? el.className.split(/\s+/).filter((c) => c && !c.includes(':'))[0] : ''
    return '<' + el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (cls ? '.' + cls : '') + '>'
  }

  const interactive = [...document.querySelectorAll('button, a[href], [role="button"], input[type="submit"], summary, [role="tab"], [role="menuitem"]')]
  const unnamed = []
  const tiny = []
  const zero = []
  for (const el of interactive) {
    const isBtn = el.tagName === 'BUTTON' || el.getAttribute('role') === 'button' || el.getAttribute('role') === 'tab'
    if (!vis(el)) {
      // Un bouton MASQUÉ est un bouton voulu : `display:none` (variante mobile)
      // ou `opacity:0` (affordance révélée au survol, comme l'épingle de la barre
      // latérale) ne sont pas des défauts. Un bouton présent dans le flux mais
      // sans boîte (0×0) en est un. Constaté le 29/09/2026 : confondre les deux a
      // produit 200 faux positifs, puis 194 autres sur le seul cas `opacity:0`.
      const s = getComputedStyle(el)
      const hiddenByDesign = s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity) === 0
      if (isBtn && !hiddenByDesign) zero.push(descOf(el) + (nameOf(el) ? ` « ${nameOf(el).slice(0, 30)} »` : ' (sans libellé)'))
      continue
    }
    const label = nameOf(el)
    if (!label) unnamed.push(descOf(el) + (el.querySelector('svg') ? ' (icône sans libellé)' : ''))
    const r = el.getBoundingClientRect()
    if (isBtn && (r.width < 24 || r.height < 24)) tiny.push(`${label || descOf(el)} ${Math.round(r.width)}×${Math.round(r.height)}`)
  }
  // Débordement horizontal : on nomme la cause, pas seulement le symptôme.
  const vw = window.innerWidth
  const overflowing = []
  for (const el of document.querySelectorAll('body *')) {
    if (!vis(el)) continue
    const r = el.getBoundingClientRect()
    const s = getComputedStyle(el)
    const selfScroll = el.scrollWidth - el.clientWidth > 4 && ['auto', 'scroll'].includes(s.overflowX)
    if (r.right > vw + 2 && !selfScroll && !overflowing.some((o) => o.el.contains(el))) {
      overflowing.push({ el, txt: descOf(el), right: Math.round(r.right), w: Math.round(r.width) })
    }
  }

  // Texte coupé (tronqué sans moyen de le lire).
  const clipped = []
  for (const el of document.querySelectorAll('h1,h2,h3,p,span,td,th,label,div')) {
    if (!vis(el) || el.children.length > 0) continue
    const s = getComputedStyle(el)
    if (['hidden', 'clip'].includes(s.overflowY) || ['hidden', 'clip'].includes(s.overflow)) {
      if (el.scrollHeight - el.clientHeight > 4 && !el.getAttribute('title') && !el.getAttribute('aria-label')) {
        clipped.push((nameOf(el) || descOf(el)) + ' (' + el.scrollHeight + '>' + el.clientHeight + ')')
      }
    }
  }

  // Proportions : un média plus large que la fenêtre et **hors conteneur
  // défilant** sera coupé à l'écran — c'est le défaut « mal proportionné ».
  // Le conteneur défilant compte : `.table-container` et les douze tableaux
  // écrits à la main posent `overflow-x: auto` (1 319 px dans 894 px, mesuré le
  // 29/09/2026) — l'utilisateur atteint chaque colonne, rien n'est coupé. Sans
  // cette exclusion, l'outil accusait trois écrans qui se comportaient bien, et
  // son propre commentaire disait déjà « hors conteneur défilant ».
  const inScroller = (el) => {
    for (let p = el.parentElement; p; p = p.parentElement) {
      const ox = getComputedStyle(p).overflowX
      if (ox === 'auto' || ox === 'scroll') return true
    }
    return false
  }
  const oversized = []
  for (const el of document.querySelectorAll('table, img, video, canvas, pre')) {
    if (!vis(el)) continue
    const r = el.getBoundingClientRect()
    if (r.width > vw + 2 && !inScroller(el)) oversized.push(descOf(el) + ' ' + Math.round(r.width) + 'px > ' + vw + 'px')
  }

  const headings = [...document.querySelectorAll('h1,h2')].filter(vis).map(nameOf).filter(Boolean)
  const text = (document.querySelector('#root')?.textContent || '').replace(/\s+/g, ' ').trim()

  return {
    url: location.pathname,
    textLength: text.length,
    textSample: text.slice(0, 220),
    headings,
    h1Count: [...document.querySelectorAll('h1')].filter(vis).length,
    tables: document.querySelectorAll('table').length,
    forms: document.querySelectorAll('form').length,
    dialogs: document.querySelectorAll('[role="dialog"]').length,
    tabs: [...document.querySelectorAll('[role="tab"]')].filter(vis).map(nameOf),
    tabpanels: document.querySelectorAll('[role="tabpanel"]').length,
    selects: [...document.querySelectorAll('select')].filter(vis).length,
    emptyStateHints: (text.match(/aucun|aucune|vide|no data|empty|لا توجد/gi) || []).length,
    interactiveCount: interactive.length,
    unnamed,
    zeroSized: zero,
    tinyTargets: tiny,
    overflowing: overflowing.map((o) => `${o.txt} right=${o.right} w=${o.w}`),
    docScrollOverflow: document.documentElement.scrollWidth - vw,
    clippedText: clipped.slice(0, 12),
    oversized: oversized.slice(0, 12),
    // Coquilles connues : frontière d'erreur React, module désactivé, accès refusé.
    errorBoundary: /Une erreur est survenue|a rencontré une erreur inattendue/.test(text),
    moduleDisabled: /module est désactivé|module désactivé/.test(text),
    accessDenied: /Accès refusé|n'avez pas les droits/.test(text),
    isBlank: text.length < 40,
  }
}

/** Analyse la fenêtre modale actuellement ouverte (après un clic d'ouverture). */
export function dialogInfo() {
  const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 }
  const named = (el) => (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || '').replace(/\s+/g, ' ').trim()
  const cands = [
    ...document.querySelectorAll('[role="dialog"], [role="alertdialog"], [aria-modal="true"]'),
    ...[...document.querySelectorAll('div,section')].filter((d) => {
      // Une région live n'est pas une fenêtre : la pile de notifications a la
      // taille, le z-index et la position d'une fenêtre, mais rien à fermer ni
      // de titre. Mesuré le 29/09/2026 : trois verdicts « fenêtre sans titre /
      // reste ouverte après Échap » désignaient des toasts (« Export en cours »,
      // « Erreur… ») — l'outil accusait le produit à la place de son message.
      if (d.hasAttribute('aria-live') || d.closest('[aria-live]')) return false
      if (['status', 'alert'].includes(d.getAttribute('role'))) return false
      const s = getComputedStyle(d)
      const r = d.getBoundingClientRect()
      return (s.position === 'fixed' || s.position === 'absolute') && r.height > 120 && r.width > 200 && Number(s.zIndex) >= 10
    }),
  ]
  if (!cands.length) return { open: false }
  const d = cands[cands.length - 1]
  const r = d.getBoundingClientRect()
  const title = d.querySelector('h1,h2,h3,[role="heading"]')
  const fields = [...d.querySelectorAll('input,select,textarea')].filter(vis)
  const text = (d.textContent || '').replace(/\s+/g, ' ').trim()
  // Les champs que la garde n'a PAS pu nommer (aucun libellé visible) : les
  // nommer ici, dans la mesure, évite de deviner de quel champ parle un
  // « 11/13 champ(s) nommé(s) » (ajouté le 29/09/2026).
  const unnamedFields = fields
    .filter((f) => !(f.getAttribute('aria-label') || f.getAttribute('aria-labelledby') || f.getAttribute('name') || f.id || f.getAttribute('placeholder')) && !f.closest('label'))
    .map((f) => (f.outerHTML || '').replace(/\s+/g, ' ').slice(0, 130))
  return {
    open: true,
    textLength: text.length,
    textSample: text.slice(0, 160),
    title: title ? named(title).slice(0, 80) : null,
    fields: fields.length,
    // Un champ enveloppé dans son propre <label> PORTE son nom : c'est le
    // navigateur qui l'associe, et tout lecteur d'écran le lit. La règle ne le
    // créditait pas et accusait douze fenêtres à tort (mesuré le 29/09/2026 :
    // les « sans nom » étaient des cases à cocher dans leur <label>).
    namedFields: fields.filter((f) => f.getAttribute('aria-label') || f.getAttribute('aria-labelledby') || f.getAttribute('name') || f.id || f.getAttribute('placeholder') || f.closest('label')).length,
    unnamedFields,
    buttons: [...d.querySelectorAll('button')].filter(vis).map((b) => named(b).slice(0, 40)),
    width: Math.round(r.width),
    height: Math.round(r.height),
    widerThanViewport: r.width > window.innerWidth + 2,
    tallerThanViewport: r.height > window.innerHeight + 2,
    clippedInside: [...d.querySelectorAll('input,select,button')].filter((el) => vis(el) && el.getBoundingClientRect().right > window.innerWidth + 2).length,
  }
}

/** Un menu déroulant est-il ouvert et peuplé ? */
export function menuInfo() {
  const items = [...document.querySelectorAll('[role="option"], [role="menuitem"], [role="menuitemradio"], li[data-value], .dropdown-item')]
    .filter((el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 })
  return { count: items.length, labels: items.slice(0, 12).map((e) => (e.textContent || '').trim().slice(0, 40)) }
}

