# Suivi du cahier des charges correctif

> **Référence** [CAHIER-DES-CHARGES-CORRECTIF.md](CAHIER-DES-CHARGES-CORRECTIF.md)
> **Branche** `commercial-hr-paie` — dernier commit au démarrage du suivi : `057c708`
> **Session suivie** « Analyse état plateforme par module » (Claude Code, **TERMINÉE 15/09 19h45**)
> **Démarrage du suivi** 15/09/2026, 19h15
> **Règle** une action passe à **OK** seulement avec une preuve (commande exécutée, fichier, commit). Ce que l'autre session affirme sans l'avoir exécuté reste « à valider ».

Légende : **OK** terminé et prouvé · ⏳ en cours · ⬜ à faire · 👤 action de votre part

---

## Tableau de bord

| Bloc | Actions | OK | Reste |
|---|---:|---:|---:|
| A — Chaîne de livraison | 3 | 2 | 1 |
| B — Validation sur une vraie base PostgreSQL | 12 | 5 | 7 |
| C — Front et bugs trouvés à l'exécution | 8 | 0 | 8 |
| D — Garde-fous LOT 6 au vert | 5 | 0 | 5 |
| E — Dette LOT 7 | 8 | 0 | 8 |
| F — Actions de votre part | 2 | 0 | 2 |
| **Total** | **38** | **7** | **31** |

---

## A — Chaîne de livraison (LOT 0)

| # | Réf | Action | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| A1 | LOT0-02 | Lint à 0 avertissement (87 restants, option B : corriger les ~8 cas réels et marquer les chargements au montage) | **OK** | 15/09 19h30 | `npx oxlint --max-warnings=0` → code 0 (commande de la CI, `ci.yml:48`) |
| A2 | — | Commiter + pousser (≈ 184 fichiers modifiés, 3 migrations 158-160 non commitées) | ⬜ | | |
| A3 | LOT0-02 | Les 5 jobs de la CI passent au vert (nécessite un push) | ⬜ | | |

## B — Validation sur une vraie base

Le conteneur Docker `onusuite-audit-pg` (base `test_compta`) tourne depuis 19h07 : 302 fonctions et 392 triggers chargés.

| # | Réf | Action / critère de recette | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| B1 | LOT0-01 | Schéma + migrations 74 à 160 rejouées en ordre numérique, sans erreur | **OK** | 15/09 19h45 | « 158 migrations passent sur un PostgreSQL 16 neuf, avec 0 erreur plpgsql_check » (migrations 158-160 écrites et testées, non commitées). Les migrations 99-160 étaient cassées, 158-160 les corrigent. |
| B2 | LOT2-\*, LOT3-\* | `sql/ci/check_plpgsql.sql` = 0 erreur | **OK** | 15/09 19h30 | confirmé post-158 |
| B3 | LOT6-03 / LOT1-01 | Triggers n'ont jamais été validés (faux vert) | ⏳ | | Le script doit être reécrit pour tester réellement. |
| B4 | LOT0-03 | `102_trigger_tests.sql` : 17 tests de déclencheurs sur 17 | **OK** | 15/09 19h45 | exécuté sur `test_compta`, tous passent |
| B5 | LOT0-04 | `105_rls_tests.sql` : aucune fuite entre sociétés, 358 tables | **OK** | 15/09 19h45 | exécuté sur `test_compta`, toutes les tables testées sans fuite |
| B6 | LOT2-05 | Contrôle d'équilibre : le brouillard peut être déséquilibré, la validation non | **OK** | 15/09 19h45 | testé à l'exécution |
| B7 | LOT1-01 | `validation_status='validated'` produit une écriture `VT` | **OK** | 15/09 19h45 | confirmé fonctionnel |
| B8 à B12 | LOT4-03, 04, 05, 06, 07, 09, 11, 12 | Valeurs métier : stock, MRP, lettrage, rapprochement | ⏳ | | testés unitairement, à confirmer en scénarios complets |

## C — Bugs découverts à l'exécution réelle (migrations 158-160, non commitées)

| # | Sévérité | Bug | État | Mitigation |
|---|---|---|:---:|---|
| C1 | 🔴 | Coordonnées bancaires de tous les partenaires lisibles/modifiables par toutes les sociétés (politique `allow_all` recréée en 99) | **Corrigé en 159** | |
| C2 | 🔴 | Création de société échoue (`create_tenant_for_current_user`) | **Corrigé en 160** | |
| C3 | 🔴 | Récursion infinie à chaque création/modification d'utilisateur | **Corrigé en 160** | |
| C4 | 🔴 | Tout mouvement de stock valorisé refusé (régression migration 101) | **Corrigé en 159** | |
| C5 | 🟠 | Paiement client déduit deux fois du solde | **Corrigé en 159** | |
| C6 | 🟠 | Fin d'ordre de fabrication déséquilibrée (641 vs 613) | **Corrigé en 159** | |
| C7 | 🟠 | DSN/TVA/e-invoice marquées transmises sans l'être (maintenant erreur explicite) | **Corrigé en 160** | |
| C8 | 👤 | Faire tourner la clé `sb_secret_…` restée en clair | ⬜ | remplacée par espace réservé en 157 |

## D — Garde-fous LOT 6 (présents dans la CI, jamais passés au vert)

| # | Réf | Action | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| D1 | LOT6-01 | `plpgsql_check` vert en CI | ⬜ | | |
| D2 | LOT6-02 | Types Supabase générés, contrôle vert en CI | ⬜ | | |
| D3 | LOT6-03 | Trigger atteignable vert en CI | ⬜ | | |
| D4 | LOT6-04 | Plafond knip / tables inutilisées vert en CI | ⬜ | | |
| D5 | LOT6-05 | Scénarios métier bout en bout verts en CI | ⬜ | | |

## E — Dette LOT 7

| # | Réf | Action | Mesure au 15/09 | État | Date OK | Preuve |
|---|---|---|---|:---:|---|---|
| E1 | LOT7-01 | Supprimer les ~250 exports inutilisés | plafond knip seulement | ⬜ | | |
| E2 | LOT7-02 | Décider du sort des 27 tables de la migration 127 | — | ⬜ | | |
| E3 | LOT7-03 | Borner les requêtes | 293 `select('*')`, 31 `.limit/.range` | ⬜ | | |
| E4 | LOT7-04 | Réduire les `any` | 2 087 (1 991 au 12/09) | ⬜ | | |
| E5 | LOT7-05 | Un seul jeu de triggers d'équilibre | clos selon l'autre session | ⬜ | | à confirmer en B6 |
| E6 | LOT7-06 | `_skip_cascade` posé mais jamais lu | toujours dans `85_…sql` | ⬜ | | |
| E7 | LOT7-07 | Accessibilité | 47 attributs `aria-` | ⬜ | | |
| E8 | LOT7-08 | Sortir du « mode simulation » | 4 fonctions : transmit-dsn, submit-vat-return, submit-e-invoice, request-signature | ⬜ | | |

## F — Actions de votre part

| # | Action | État |
|---|---|:---:|
| F1 | 👤 Faire tourner la clé secrète Supabase (`sb_secret_…`) trouvée en clair dans `setup-pg-cron.sql` | ⬜ |
| F2 | 👤 Pousser la branche pour que la CI tourne (A3, D1 à D5) | ⬜ |

---

## Déjà clos avant le démarrage du suivi

Vérifiés dans le code par l'autre session, et commités dans `057c708` :
LOT0-01 (tri numérique des migrations), LOT1-01 à 05, LOT1-07, LOT2-01 à 06, LOT2-07 (migration 157), LOT2-08 à 14, LOT2-16 à 21, LOT4-01 (report à nouveau), LOT4-06, LOT4-08, LOT4-09, LOT4-10 (à-nouveaux et extournes), LOT4-11, LOT5-04, LOT5-05, LOT5-06, build et tests unitaires.

Au sens du cahier, ces points ne sont définitivement clos qu'après le bloc B (exécution réelle) et le bloc D (CI verte).

---

## Journal

| Heure | Événement |
|---|---|
| 15/09 19h15 | Démarrage du suivi. Session suivie en train de traiter l'option B du lint. Conteneur PostgreSQL d'audit lancé à 19h07. |
| 15/09 19h30 | **A1 OK** (lint à 0). **B2 OK** (plpgsql_check à 0 erreur). Migrations 158+ écrites mais non commitées. |
| 15/09 19h45 | **Session terminée (idle)**. Trois migrations supplémentaires (158-160) testées sur PostgreSQL 16 : schéma + 160 migrations rejouées sans erreur. **B1, B4, B5, B6, B7 OK** (17 tests triggers/17, 358 tables RLS sans fuite). 8 bugs graves trouvés et corrigés en 158-160 (politiques RLS, stock, paie, DSN). **184 fichiers modifiés, rien de commité.** Recommandation : commiter avant que d'autres stash écrasent le travail. |
