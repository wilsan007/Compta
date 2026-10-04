// ============================================================
// qa/lib/rules.mjs — le barème commun aux ouvriers et au validateur
//
// Un identifiant de défaut, une gravité, une famille. Le validateur refuse
// tout identifiant absent de ce barème : un ouvrier ne peut pas inventer une
// catégorie, et le registre (.qa-baseline.json) reste lisible par un humain.
// ============================================================

export const RULES = {
  // ── Rendu : l'écran ne s'affiche pas ─────────────────────────────
  erreur_js: { severity: 'bloquant', kind: 'console', label: 'Exception JavaScript non rattrapée' },
  erreur_page: { severity: 'bloquant', kind: 'rendu', label: "L'écran tombe dans la frontière d'erreur" },
  page_blanche: { severity: 'bloquant', kind: 'rendu', label: 'Écran vide (aucun contenu rendu)' },
  route_redirigee: { severity: 'bloquant', kind: 'session', label: 'Route redirigée (session ou société perdue)' },
  sans_titre: { severity: 'mineur', kind: 'contenu', label: 'Ni h1 ni h2 visible' },

  // ── Contrat d'appel : la base refuse ce que l'écran demande ─────
  api_refusee: { severity: 'bloquant', kind: 'contrat', label: 'Appel refusé (4xx/5xx) sur la route' },

  // ── Console ─────────────────────────────────────────────────────
  erreur_console: { severity: 'majeur', kind: 'console', label: 'Erreur écrite en console' },

  // ── Blocage de l'interface ─────────────────────────────────────
  overlay_bloquant: { severity: 'majeur', kind: 'blocage', label: 'Fenêtre de bienvenue revenue : elle recouvre l’écran et intercepte les clics' },

  // ── Onglets ────────────────────────────────────────────────────
  onglet_inchange: { severity: 'majeur', kind: 'onglet', label: "Onglet sans effet (le panneau ne change pas)" },

  // ── Listes déroulantes et menus ────────────────────────────────
  select_vide: { severity: 'majeur', kind: 'liste', label: 'Liste déroulante sans option' },
  menu_vide: { severity: 'majeur', kind: 'liste', label: 'Menu qui s’ouvre sans entrée' },

  // ── Fenêtres ───────────────────────────────────────────────────
  modal_sans_fermeture: { severity: 'majeur', kind: 'modale', label: 'Fenêtre qui ne se ferme pas (Échap)' },
  modal_deborde: { severity: 'majeur', kind: 'modale', label: "Fenêtre plus grande que l'écran" },
  modal_sans_titre: { severity: 'mineur', kind: 'modale', label: 'Fenêtre sans titre' },
  modal_champ_sans_nom: { severity: 'mineur', kind: 'modale', label: 'Champ de formulaire sans libellé' },
  modal_vide: { severity: 'majeur', kind: 'modale', label: 'Fenêtre ouverte mais vide' },
  // Le guide de bienvenue a son propre scénario (scripts/qa/guide.mjs) : la
  // tournée le pose comme déjà vu, sinon il recouvre les 334 écrans.
  guide_etape_inchange: { severity: 'majeur', kind: 'modale', label: "Le guide n'avance pas (l'étape ne change pas)" },

  // ── Boutons et accessibilité ───────────────────────────────────
  bouton_sans_nom: { severity: 'majeur', kind: 'a11y', label: 'Bouton/onglet sans libellé accessible' },
  bouton_taille_nulle: { severity: 'mineur', kind: 'a11y', label: 'Bouton présent mais de taille nulle' },
  cible_etroite: { severity: 'mineur', kind: 'a11y', label: 'Cible tactile plus petite que 24 px' },

  // ── Mise en page et responsive ─────────────────────────────────
  debordement_horizontal: { severity: 'majeur', kind: 'responsive', label: 'La page déborde horizontalement' },
  element_trop_large: { severity: 'majeur', kind: 'responsive', label: 'Élément plus large que la fenêtre' },
  texte_coupe: { severity: 'mineur', kind: 'responsive', label: 'Texte coupé sans moyen de le lire' },
}

export const SEVERITY_ORDER = ['bloquant', 'majeur', 'mineur']

export function finding(route, id, detail, viewport) {
  const rule = RULES[id]
  if (!rule) throw new Error(`règle inconnue : ${id}`)
  return { route: route.path, module: route.module, source: route.source, id, viewport, detail, severity: rule.severity, kind: rule.kind, label: rule.label }
}

/** Empreinte stable : un même défaut vu par deux ouvriers ne compte qu'une fois. */
export function fingerprint(f) {
  const d = typeof f.detail === 'string' ? f.detail : JSON.stringify(f.detail ?? '')
  return `${f.route}|${f.viewport}|${f.id}|${d.slice(0, 120)}`
}

export function summarize(findings) {
  const by = { bloquant: 0, majeur: 0, mineur: 0 }
  for (const f of findings) by[f.severity] = (by[f.severity] ?? 0) + 1
  return by
}
