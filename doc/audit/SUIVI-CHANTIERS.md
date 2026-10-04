# Suivi des chantiers — un seul tableau, tenu à jour

> **Objet.** Une ligne par chantier, **tous plans confondus**, avec son état, sa preuve et
> **le plan qui le porte aujourd'hui**. Quand un chantier passe d'un plan à un autre, la ligne
> le dit (➜) au lieu de le compter deux fois. Créé le **02/10/2026**.
>
> **Comment il reste à jour — deux mécanismes, pas un vœu :**
>
> 1. **Les mesures** (§0) se recalculent depuis le dépôt :
>    `node app/scripts/suivi-chantiers.mjs --write` réécrit le bloc entre les marqueurs ;
>    `--check` échoue s'il est périmé. Ne jamais éditer ce bloc à la main.
> 2. **Les verdicts** (§1 à §7) se tiennent **dans le commit qui change l'état** : une session
>    qui ferme, ouvre ou déplace un chantier modifie sa ligne (état, preuve, date) dans le même
>    commit que la migration, la suite et le câblage CI. C'est la règle « le travail non commité
>    n'existe pas », appliquée au suivi. Une ligne sans date de vérification est suspecte.
>
> **Légende.** ✅ fait et prouvé · 🔶 en partie / en cours · ⬜ pas commencé ·
> ❓ à recompter (non vérifié dans la dernière passe) · ➜ repris par · 🔴 alerte ·
> 👤 dépend de vous (hors dépôt).
>
> **Plans couverts.** [Perfection 9,5](PLAN-PERFECTION-9.5.md) (10/09) ·
> [Correctif audit A→K](PLAN-CORRECTIF-AUDIT-2026-09-21.md) (21/09) ·
> [Correctif complet W0→W10](PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md) (24/09) ·
> [Reste-à-faire en 10 phases](RESTE-A-FAIRE-ET-PLAN-PHASES-2026-09-24.md) (24/09) ·
> [Chaînages L0→L24](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md) (24/09) ·
> [Audit fonctionnel X0→X8](PLAN-CORRECTIF-AUDIT-FONCTIONNEL-2026-09-28.md) (28/09) ·
> Plan QA correctif (29/09, **sur la branche `qa/recette-2026-09-29` seulement**) ·
> [Propositions P1→P8](PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md) (30/09) ·
> Plan en 5 parties du 02/10 ([1](PLAN-PARTIE-1-STABILISER-2026-10-02.md),
> [2](PLAN-PARTIE-2-DEFAUTS-METIER-2026-10-02.md), [3](PLAN-PARTIE-3-CHAINAGES-L3-L4-2026-10-02.md),
> [4](PLAN-PARTIE-4-RECETTE-LIVRAISON-2026-10-02.md), [5](PLAN-PARTIE-5-INTEGRITE-CHAINAGES-2026-10-02.md)).

---

## 0. Mesures (recalculées par le script)

<!-- MESURES:DEBUT -->
*Mesuré le **2026-10-03** par `node app/scripts/suivi-chantiers.mjs --write` — ne pas éditer à la main.*

| Mesure | Valeur | Chantier |
|---|---|---|
| Branche de la copie de travail | `harmonisation` @ `75d9799` | — |
| Migrations / suites SQL dans `app/sql` | 215 / 134 | — |
| **Numéros de migration en collision entre branches** (SOC-06) | ✅ 0 | alerte |
| Registre SQL `ci/expected_failures.sql` (lignes `INSERT`) | 2 | registre |
| Registre écran `__screen__/expected_failures.json` | ✅ vide | registre |
| `confirmSync` (= `window.confirm`) — fichiers | 100 | AUD-I01 · 1.8 · UX-03 |
| `useConfirm` / `confirmDialog` — fichiers | 4 | AUD-I01 · 1.8 |
| Champs factices du plan comptable (`nbLines`, `pageBreak`, `regrouping`) | ✅ retirés | AUD-I02 · 1.10 |
| Suite `412` (caisse) finit par `_audit_assert` | ✅ | 1.2 |
| `parse-bank-statement` / `ai-import-mapping` refusent sans consentement | ✅ / ✅ | D-5 · AUD-H04 · 1.11 |
| `get_vat_codes` (correctif TVA 198) présent en base | ✅ | ✅ | `325_vat_codes_ca3` (ex-`198`), livré par `08fbb39` sur `fusion-1.6`, fusionné dans `harmonisation` 
| e2e Playwright sur chaque PR vers `main` | ⬜ sur étiquette seulement | AUD-J01 · 4.3 |
| `any` explicites (plafond gelé : production / tests) | 1035 / 802 (gelé le 2026-10-03) | AUD-J07 · DAT-02 |
| Tables non lues par l'écran (plafond) | 75 (gelé le 2026-10-03) | SOC-05 |
| **Tables coquilles** (ni écran, ni Edge, SQL = DDL seul) | 37 | ORPH-02 · SOC-05 |
| Suites SQL qui exercent `user_totp` / `api_keys` | 0 | ORPH-01 · SEC-02 |

<details><summary>Les 37 tables coquilles</summary>

`business_alert_rules` · `business_connectors` · `collective_agreements` · `collective_classifications` · `crm_scoring_rules` · `crm_sequence_steps` · `crm_sequences` · `custom_field_definitions` · `custom_field_values` · `document_attachments` · `e_invoicing_logs` · `employee_self_service` · `fixed_asset_components` · `group_entities` · `group_members` · `intra_group_transactions` · `job_applications` · `job_postings` · `landed_cost_lines` · `maintenance_records` · `migration_templates` · `mo_consumptions` · `mo_operations` · `notification_center` · `platform_admins` · `quality_control_plans` · `quality_control_points` · `reorder_rules` · `report_definitions` · `resource_capacities` · `signup_flows` · `stock_count_cycles` · `stock_transfer_lines` · `tenant_fiscal_settings` · `time_entries` · `uom_categories` · `work_center_calendars`

</details>
<!-- MESURES:FIN -->

---

## 1. Alertes ouvertes (à traiter avant toute fusion)

| ID | Alerte | Constat | Qui tranche | Vérifié le |
|---|---|---|---|---|
| ✅ **ALR-01** | **`415` pris deux fois, puis `416` trois fois** — **corrigé le 02/10 au soir** | la plage inscrite (`415`→`429`, L16→L24) garde ses numéros ; la partie 3 passe en `430` (paie), `431` (invariants L4), `432` (relevé) — `0cd347c` (poussé) sur `partie-3-chainages`, `9e0f33d` sur `l4-invariants`. **Prévention** : `migration-numero.mjs` (contrôle avant → création → contrôle après → registre commun), crochet `pre-commit` commun à tous les worktrees, étape CI `SOC-06` | — | 02/10 |
| 🔶 **ALR-02** | **Une copie de travail, plusieurs sessions** | la copie est sur `partie-5-integrite-chainages` avec ~20 fichiers modifiés non commités (partie 5 en cours) et les fichiers L23 non suivis. Un `git checkout` d'une autre session les emporte | chaque session : worktree propre (tâche 1.9) | 02/10 |
| ✅ **ALR-03** | **Le plan QA et ses correctifs ne sont pas sur la ligne principale** | `PLAN-QA-CORRECTIF-2026-09-29.md`, les lots A/B et `4065d10` (1.5) n'existent que sur `qa/recette-2026-09-29` ; D3 (`bc92cf9`) sur `qa/lot-d-stock` | tâche 1.6 | 02/10 — **levée le 03/10 : tout est dans `harmonisation`** |
| 🔶 **ALR-04** | **`417_chain_banc_moteur` (partie 3, non suivi) est dans la plage de L16→L24** | le crochet refusera son commit ; la session doit le prendre dans sa plage (`433` si libre) avec `migration:prendre` | session partie 3 | 02/10 |
| ✅ **ALR-05** | **Deux migrations créaient `chain_document_types`** — **tranchée le 03/10** | un seul registre : celui de la `450`. La `431` ne garde que les six raisons de non-mesure devenues preuves ; même défaut sur `chain_invariant_mesurer` (`435` × `455`), réuni par la `456` — 17 mesurés, 3 nommés | branche `harmonisation` (`934b725`, `3fbf208`) | 03/10 |

---

## 2. Le plan en cours — 5 parties du 02/10

### Partie 1 — Stabiliser

| Tâche | Objet | État | Preuve / reste | Repris de |
|---|---|---|---|---|
| 1.0 | Inventaire et gel des travaux en vol | ✅ | `e3110ef` | — |
| 1.1 | Ligne principale au vert (types, plafond des tables non lues) | ✅ | `98afde3`, `39a7107` | — |
| 1.2 | Faux vert de la suite caisse `412` | ✅ | `317c0a6` (mesure §0) | — |
| 1.3 | Garde anti-faux-vert dans `check-test-suites.mjs` | ✅ | `317c0a6` | — |
| 1.4 | CI sur `qa/**` et `partie-*` | ✅ | `b5a02dc` | — |
| 1.5 | Réparer la branche QA avant fusion | 🔶 | `4065d10` sur `qa/recette-2026-09-29`, pas encore sur la ligne principale | — |
| 1.6 | Fusionner la recette (QA `310→324`, chaînages `400→413`) | ✅ | fusionnée dans `harmonisation` (`18fb06d`, `75d9799`), avec `partie-1-stabiliser`, `audit/employe-colonnes-identite`, `l4-invariants` et `partie-3-chainages` : base neuve **316 migrations, 0 erreur**, **150/150** étapes SQL, Vitest **1 643** | ALR-03 |
| 1.7 | Correctif TVA 198 sous `325` | ⬜ | `get_vat_codes` absent (mesure §0) | — |
| 1.8 | Vrai dialogue de confirmation | ⬜ **bloquée** | attend la fin de 1.6 : la fusion touche les mêmes écrans (`SuppliersPage`, `QuotesPage`, `CustomersPage`…) ; `confirmSync` dans 97 fichiers (mesure §0) | AUD-I01, UX-03 |
| 1.9 | Ménage des worktrees et des documents | ⬜ | — | ALR-02 |
| 1.10 | Champs factices du plan comptable | ✅ | `7a99dae` sur `partie-1-stabiliser` : les **six** contrôles retirés (3 sans colonne, 3 dont la colonne n'est lue par rien) ; test rouge avant | AUD-I02 |
| 1.11 | D-5 côté code : 2 fonctions sans garde | ✅ | `0002ce6` sur `partie-1-stabiliser` : 409 sans consentement, 400 sans société (plus devinée), écrans joignent `x-tenant-id` ; 6 tests Edge + 2 Vitest rouges avant | AUD-H04, D-5 |
| 1.12 | Rejeu de contrôle final | ⬜ | dépend de tout le reste | — |
| 1.13 | D-4, voie A | 🔶 | `503` honnête fait ; restent convertisseur isolé, `GOTENBERG_URL`, un appelant | AUD-H03, D-4 |

### Partie 2 — Défauts métier (fermée tant que la partie 1 n'est pas close)

| Tâche | Objet | État | Repris de (plan QA du 29/09) |
|---|---|---|---|
| 2.1 | Titres-restaurant et transport dans le bulletin | ✅ code · 👤 signature | C2 ter — migration `341`, suite `321` **10/10** (dont la part patronale sous 50 % : totalité réintégrée, BOSS 16/03/2023), registre SQL **vide** ; barèmes 2026 relevés sur urssaf.fr le 04/10 ; **déploiement soumis à la signature de l'expert-comptable (D-G)** |
| 2.2 | Heures sup détectées depuis la feuille de temps | ✅ | C3 (rh-008) — migration `340`, suite `340` **9/9** (4 rouges avant), scénario écran H11/H12, 04/10 |
| 2.3 | Tranches d'heures sup + exonération | ✅ code · 👤 signature | reste de W5 — migration `342`, suite `342` **8/8** : 8 h à 25 % puis 50 % sur la semaine civile, réduction salariale 11,31 %, `calculate_overtime_pay` supprimée ; règles relevées sur service-public (F2391) le 04/10. **Non codés, dits** : seuil hebdomadaire (il reste journalier), exonération d'impôt de 7 500 € |
| 2.4 | Pointage d'absence ; constats bas de paie | ✅ (maladie : 👤 expert) | C4 (rh-009) : le formulaire pointe une absence (scénario écran H13, base déjà prouvée par `263 A02`) ; C5/C6 : migration `343`, suite `343` **4/4** (4 rouges avant) — type de contrat, date d'embauche, salaire unique, droits à congés au prorata, dates de lot en heure locale, libellés. **Restent** : arrêt maladie (carence, maintien) à faire valider par l'expert ; message du salaire négatif → 2.12 |
| 2.5 | OF terminé à 0,00 €, consommations | 🔶 | D3 — `bc92cf9` sur `qa/lot-d-stock` |
| 2.6 | Caisse : annulation à l'écran, statuts, « Virement » | ⬜ | D5 (stk-014) |
| 2.7 | Prix négatif, fiche article, sortie à 0,00 €, stock initial | ⬜ | D6, D7, D8 |
| 2.8 | Inventaire, alerte stock bas, points non testés | ⬜ | D9, D12, D13 |
| 2.10 | Plan comptable à solde 0, plan vide | ⬜ | F1 (cpt-001), F3 |
| 2.11 | Type de compte, modèle à 100 %, date hors période | ⬜ | F2, F6, F7 |
| 2.12 | Messages SQL bruts, accents | ⬜ | F4 (= AUD-I04), F5 |
| 2.13 | Section analytique sur la facture, grille de ventilation | ⬜ | G1 (pil-008), G2 |
| 2.14 | Tâche sans parent, Gantt en anglais, constats projets | ⬜ | G3, G4, G5 |
| 2.16 | Types de retour des écrans touchés (voie C) | ⬜ | suite de `c51d468` |

*Il n'y a pas de 2.9 ni de 2.15 dans le plan.*

### Partie 3 — Chaînages : finir L3 et L4

| Tâche | Objet | État | Preuve / reste |
|---|---|---|---|
| 3.1 | Recompter les maillons RPC | ⬜ | — |
| 3.2 | Paie versée tracée par son chemin d'appel | ✅ | `430` (ex-`415`, 11 scénarios) sur `partie-3-chainages` |
| 3.3 | Relevé bancaire manuel et maillons RPC restants | ⬜ | — |
| 3.4 | Moteur des 8 épreuves + rapport par maillon | ⬜ | 0 chaînage éprouvé sur 62 |
| 3.5 → 3.7 | Épreuves D1 → D8 | ⬜ | — |
| 3.8 | 7 invariants « non mesurables » | 🔶 | INV-19 rendu mesurable par la partie 5 (`455`, non commitée) ; 6 restent |
| 3.9 | Relevé nocturne et alerte | 🔶 | `414` commitée, en pause |
| 3.10 | Invariants lus par l'écran | 🔶 | `chainCoherence.ts` (`98afde3`) ; à confirmer contre le critère du plan |

### Partie 4 — Montrer, recetter, livrer

| Tâche | Objet | État | Repris de |
|---|---|---|---|
| 4.1 / 4.2 | Pages « Robustesse » et « Cohérence » | ⬜ | L5 |
| 4.3 | Playwright sur chaque PR vers `main` | ⬜ | AUD-J01 |
| 4.4 | 4 parcours qui lisent des chiffres | ⬜ | AUD-J02, QUA-03 |
| 4.5 | Lectures du chemin de l'écran (159 fonctions sautées) | ⬜ | X8, balayage des routes |
| 4.6 | Les 14 parcours à l'écran, 2 sociétés, 4 gabarits | ⬜ | P0-08, recette croisée du plan QA, re-notation X8 |
| 4.7 | Corriger les écarts bloquants de 4.6 | ⬜ | — |
| 4.8 | Rejeu sur copie de production, G7 sous le vrai propriétaire | ⬜ | — |
| 4.9 | Déploiement + relecture des paramètres globaux et de `banks` | ⬜ | X1 |
| 4.11 | Immobilisations à l'écran | ⬜ | E2 (plan QA) |
| 4.12 | Tableaux de bord | ⬜ | H1, H2 (plan QA) |

### Partie 5 — Intégrité référentielle des chaînages (≈ 6 j)

| Étapes | Objet | État |
|---|---|---|
| 5.0 → 5.13 | Plage, suite 450 (14/14), registre des types, existence, orphelins, garde de suppression, libération, INV-19, écran, rejeu | ✅ | `7544ea1`, `4a053ba`, `b1e830f` — [preuve](VAGUE-PARTIE-5-2026-10-02.md) |

---

## 3. Reste-à-faire en 10 phases (24/09) — ce qu'il en reste

### Phase 1 — Décisions et actions humaines

| ID | Sujet | État | Où ça avance |
|---|---|---|---|
| D-4 | `generate-pdf` (SSRF AUD-H03) | 🔶 | ➜ 1.13 |
| D-5 | OCR / prestataire IA | 🔶 `318` fait | ➜ 1.11 (code) + **DPA** 👤 |
| D-7 | Contraste : 7 couples sous 4,5:1, tolérés | ⬜ décision | passe de thème devant un écran |
| D-10 | Compte de trésorerie exigé au règlement | ✅ | `b37cc6a` |
| D-11 | Périmètre de la localisation (DJ-EP / DJ-ADM, arabe en v1 ?) | ⬜ décision | bloque le lot K |
| D-13 | Séparation des tâches | ✅ | `271` |
| D-G | Signature des bulletins d'or de la `276` | ⬜ 👤-4 | bloque le déploiement de la `276` |
| 👤-1 | Tourner la clé `sb_secret_…` (AUD-H05) | ⬜ 👤 | — |
| 👤-2 | Secrets E2E dans GitHub | ⬜ 👤 | bloque 4.3/4.4 |
| 👤-4 | Expert-comptable référent | ⬜ 👤 | bloque D-G, P1 |
| 👤-5 | Les 14 documents djiboutiens | ⬜ 👤 | bloque le lot K |
| 👤-6 | 2 à 3 pilotes | ⬜ 👤 | — |
| — | Comptes des 9 intégrations (Chorus Pro, Yousign, GoCardless, Resend, EFI, SIRENE/VIES, Stripe, Gotenberg, Sentry) | ⬜ 👤 | tableau B de `RESTE-OUVERT` |

### Phases 2 à 6 — fermées

W4 (`256`), W9 (`263`→`266`), W6 (`257`→`259`), W5 (`260`), W7 (`300`→`309`), W8 (`301`→`303`) : ✅.
Les 9 scénarios transverses (phase 6) : ➜ absorbés par L1/L2/L4. Reste de W5 (tranches d'heures sup) : ➜ 2.3.

### Phases 7 à 9 — Chaînages L0 → L24

| Lot | Objet | État | Preuve / porté par |
|---|---|---|---|
| L0 | Socle | ✅ | `252` |
| L1 | Rétro-instrumentation (23 effets, 23 contrats + caisse) | ✅ | `400`→`412` (ex-`310`→`321`) |
| L2 | Portes CI G1 → G7 | ✅ | preuve L2 + G7 |
| L3 | Maillons RPC + banc D1 → D8 | 🔶 | réception, fermetures, caisse, paie (`415`, partie 3) ✅ ; relevé et banc ➜ partie 3 |
| L4 | 20 invariants, indice, relevé nocturne | 🔶 | `413` (13/20 mesurables), `414` en pause ➜ partie 3 ; INV-19 ➜ partie 5 |
| L5 | Pages Robustesse / Cohérence | ⬜ | ➜ 4.1/4.2 |
| L6 | Vue Chaîne (I-01) | ⬜ | **aucun plan** |
| L7 | Contrats d'effet (I-02) | ✅ | `313` |
| L8 → L15 | Les 62 règles d'état (ventes, achats, trésorerie, paie/RH, projets, production, conformité, budgets) | ⬜ | **aucun plan** (≈ 42 j) |
| L16 → L22 | Chaînages internes, couples inter-modules, régénération, lettrage, moteur de règles | ⬜ | plage `415→429` inscrite (**ALR-01**), aucune tâche |
| L23 | Événements et webhooks unifiés (I-06) | 🔶 | `415` commité (`99bc04e`) — tranche 1 |
| L17 | Capacité ↔ absence | 🔶 | `416_chain_l17_capacite_absence` non suivi (pris au registre) |
| L24 | Explicabilité, régularisation guidée, assistant (I-08, I-09, I-12) | ⬜ | **aucun plan** |

### Phase 10 — La couverture

| Chantier | État | Porté par |
|---|---|---|
| Contrat d'entrée des 20 fonctions Edge | ✅ | W6 (tests Deno) |
| Parcours complets des fonctions Edge (avec prestataires) | ⬜ 👤 | comptes des intégrations |
| e2e qui remplissent un formulaire et lisent un chiffre (0/5) | ⬜ | ➜ 4.3, 4.4 |
| 16 modules jamais audités par exécution | 🔶 | audit fonctionnel X (28/09) + essaim QA + recette 29/09 ; **re-notation** ➜ 4.6 |
| Authentification forte | ⬜ | ➜ **ORPH-01** |
| Tables coquilles | ⬜ | ➜ **ORPH-02** |

---

## 4. Plan QA correctif (29/09) — où va chaque lot

| Lot QA | Fait | Reste ➜ tâche |
|---|---|---|
| A — Tiers et comptes auxiliaires | ✅ A1 → A6 | — |
| B — Ventes | ✅ B1 → B12 | — |
| C — Paie | ✅ C1, C2, C2 bis | C2 ter, C3 → C6 ➜ 2.1 → 2.4 |
| D — Stock, production, caisse | ✅ D1, D2, D4 ; 🔶 D3 | D3 ➜ 2.5 ; D5 → D13 ➜ 2.6 → 2.8 |
| E — Immobilisations | ✅ E1 | E2 ➜ 4.11 |
| F — Comptabilité générale | — | F1 → F7 ➜ 2.10 → 2.12 |
| G — Analytique, projets, budgets | — | G1 → G5 ➜ 2.13, 2.14 |
| H — Tableaux de bord, trésorerie | — | H1, H2 ➜ 4.12 |
| Recette finale et contrôle croisé | — | ➜ 4.6 |

⚠️ Tout le « fait » de ce tableau vit sur les branches `qa/*` (ALR-03) : il ne compte pour la
ligne principale qu'après 1.6.

---

## 5. Correctif audit A → K (21/09) et lot X

| Lot | État | Reste ➜ |
|---|---|---|
| A → G | ✅ | vagues V1 → V3, en production jusqu'à `227` |
| H Sécurité | 🔶 | H01, H02, H06, H07 ✅ · H03 ➜ 1.13 · H04 ➜ 1.11 + DPA · H05 ➜ 👤-1 |
| I Ergonomie et i18n | 🔶 | I06 ✅, I03 ✅ en grande partie · I01 ➜ 1.8 · I02 ➜ 1.10 · I04 ➜ 2.12 · I05 = D-7 |
| J Qualité, CI | 🔶 | J03, J04, J05, J06 ✅ · J07 plafond gelé (mesure §0) · J01 ➜ 4.3 · J02 ➜ 4.4 |
| K Localisation Djibouti | 🔶 amorcé | `191`, `201` ; ≈ 74 j ➜ **aucun plan** (bloqué par D-11 et 👤-5) |
| X Outillage (X01, X02) | ✅ | W0 |

---

## 6. Chantiers qu'aucun plan ne portait — ouverts ici

| ID | Chantier | Constat (mesuré le 02/10) | Charge PROPOSÉE | Critère de sortie |
|---|---|---|---|---|
| **ORPH-01** | **Authentification forte** (`api_keys`, `user_totp`) | **0** suite SQL ; seul `src/__tests__/phase5-enterprise-features.test.ts` les nomme, avec Supabase **simulé** ; aucun test Edge de `public-api` sur la clé | 1 j | une suite SQL : émission, usage, révocation, rejeu d'une clé ; activation/vérification TOTP ; un test Edge « clé révoquée → 401 » ; chaque scénario vu rouge d'abord |
| **ORPH-02** | **Tables coquilles** | **37** tables (liste §0) que ni l'écran ni une fonction Edge ne nomment et que le SQL ne nomme qu'en DDL (le 24/09 : 41 — méthode du jour dans le script) | 1,5 j | chaque table **branchée** (son chantier ci-dessous) ou **supprimée** par une migration motivée ; le compte §0 ne peut que baisser (le rendre bloquant en CI) |
| **ORPH-03** | **Recompter le plan de perfection 9,5** | 141 chantiers, jamais recochés ; première passe au §7 (preuve pour les ✅, ❓ pour le reste) | 1 j | 0 ❓ au §7 : chaque chantier ✅ avec preuve, ⬜ avec son lot, ou **écarté** avec sa raison |
| ORPH-04 | Vue Chaîne, 62 règles d'état, L16 → L24, lot K, P1 → P8 | sans tâche dans les 5 parties | ≈ 100 j + ≈ 74 j + ≈ 25 j | un « horizon suivant » daté, découpé en parties comme le plan du 02/10 |

*Les tables coquilles se recoupent avec le §7 : `collective_agreements` / `collective_classifications`
(PAY-08), `crm_sequences` / `crm_scoring_rules` (CRM-01, CRM-02), `group_*` / `intra_group_transactions`
(GRP-01 → 03), `uom_categories` (STK-07), `landed_cost_lines` (STK-08), `reorder_rules` /
`stock_count_cycles` (STK-09), `stock_transfer_lines` (STK-14), `maintenance_records` /
`work_center_calendars` (PRD-07, PRD-11), `job_postings` / `job_applications` (RH-03),
`custom_field_*` (PRJ-04), `report_definitions` (BI-01), `notification_center` /
`business_alert_rules` (NOT-01, NOT-02), `business_connectors` (API-03), `document_attachments`
(GED-01), `employee_self_service` (PTL-01). **Brancher ou supprimer une coquille, c'est décider
du chantier 9,5 correspondant.***

---

## 7. Plan de perfection 9,5 — recomptage, première passe (02/10)

> Les ✅ et 🔶 portent leur preuve. Les ❓ n'ont **pas** été vérifiés dans cette passe :
> c'est le travail d'ORPH-03.

| ID | Chantier | État | Preuve / porté par |
|---|---|---|---|
| SOC-01 | Écriture validée avant ses lignes | ✅ | noyau strict `187` (lot C) |
| SOC-02 | Tests d'intégration base en CI | ✅ | job `db-integration`, 102 suites |
| SOC-03 | TypeScript strict | ✅ | `"strict": true` (app, test) |
| SOC-04 | Agrégations financières côté serveur | ✅ | états réécrits côté base (`189`) |
| SOC-05 | Table présente, jamais branchée | 🔶 | ➜ ORPH-02 |
| SOC-06 | Numéros de migration en doublon | ✅ | runner + crochet pre-commit + CI + `migration-numero.mjs` (02/10) |
| SOC-07 | Fichiers monstres | ✅ | plus gros fichier de requêtes : 1 424 lignes |
| SOC-08 | Nettoyage du dépôt (`.bak`) | ✅ | 0 fichier `.bak` |
| SOC-09 | Gestion d'erreur uniforme | 🔶 | W6 (erreurs lues), `errorMessage()` ; messages SQL bruts ➜ 2.12 |
| ACC-01 | Comptes auxiliaires sur les écritures automatiques | ❓ | lot E (V3) à confirmer |
| ACC-02 | TVA multi-taux et code TVA | 🔶 | lot E, `197` ; correctif 198 ➜ 1.7 |
| ACC-03 | Comptes de produit/charge par article | ❓ | stock : `resolve_stock_account` (`241`) ; ventes/achats à vérifier |
| ACC-04 | Plan comptable de la législation | 🔶 | `201` (FR/DJ) ; comptes codés en dur (S-10) ➜ lot K |
| ACC-05 | Exercice, à-nouveaux, affectation | ✅ | lot D, R-02 |
| ACC-06 | Lettrage complet | 🔶 | R-01 (écarts) ; dérivés ➜ L21 |
| ACC-07 | Immobilisations complètes | 🔶 | W5 `260` ; E2 ➜ 4.11 |
| ACC-08 | Analytique effective | 🔶 | `304` (ventes, achats) ; paie/stock/caisse/production non |
| PAY-01 | Deux corrections immédiates | ❓ | lot F probable |
| PAY-02 | Plafond de sécurité sociale et tranches | ✅ | `276` (signature D-G 👤) |
| PAY-03 | Prorata entrée/sortie/absence | 🔶 | absence : W9 ; entrée/sortie ❓ |
| PAY-04 | Cumuls, régularisation progressive | ✅ | `247` |
| PAY-05 | Net imposable, scission CSG | ✅ | `276` |
| PAY-06 | Réduction générale (RGDU) | ✅ | `276` |
| PAY-07 | Heures sup conformes | 🔶 | W5 ; tranches ➜ 2.3 |
| PAY-08 | Conventions collectives | ⬜ | tables coquilles (ORPH-02) |
| PAY-09 | Maladie, IJSS, subrogation | 🔶 | W9, W10 (`calculate_sick_leave_pay`) |
| PAY-10 | Bulletin réglementaire | 🔶 | recette QA (bulletin, `310→324` QA) ➜ 1.6 |
| PAY-11 | Solde de tout compte | ❓ | — |
| PAY-12 | Architecture cible du moteur | ❓ | — |
| RH-01 | Temps et activités | 🔶 | W9 ; heures sup ➜ 2.2 |
| RH-02 | Congés conformes | 🔶 | W4, W9 |
| RH-03 | Recrutement et intégration | ⬜ | tables coquilles |
| STK-01 | Vocabulaire des mouvements | ✅ | `280` |
| STK-02 | CUMP incrémental | ✅ | `254` |
| STK-03 | FIFO / LIFO | ⬜ | écarté de fait (`254` : inertes) — à écrire comme décision |
| STK-04 | Une seule valorisation | ✅ | `254` |
| STK-05 | Réservations | ✅ | `242`, `410` ; libération ➜ partie 5 (`454`) |
| STK-06 | Lots et séries | 🔶 | `241` refuse sans lot ; pas d'écran de saisie |
| STK-07 | Unités de mesure | ⬜ | `convertUom` retirée (W10), coquilles |
| STK-08 | Frais accessoires | ⬜ | `landed_cost_lines` coquille |
| STK-09 | Réappro, inventaire tournant | ⬜ | coquilles ; inventaire ➜ 2.8 |
| STK-10 | Comptes de stock par catégorie | ✅ | `241` |
| STK-11 | Emplacements | ⬜ | — |
| STK-12 | Préparation et expédition | 🔶 | BL depuis la commande (`280`) |
| STK-13 | Contrôle qualité | 🔶 | `251` ; plans de contrôle coquilles |
| STK-14 | Transferts, variantes | ⬜ | coquille ; ➜ L13 |
| PRD-01 | Valoriser les OF | ✅ | `302` ; écran ➜ 2.5 |
| PRD-02 | MRP récursif | ✅ | `302` (explosion multi-niveaux) |
| PRD-03 | Sources du besoin | ❓ | — |
| PRD-04 | Délais, stock de sécurité | ❓ | — |
| PRD-05 | Commandes en cours déduites | ❓ | — |
| PRD-06 | Déclaration et rebuts | ✅ | `302` |
| PRD-07 | Capacité finie | ⬜ | coquilles ; ➜ L17 |
| PRD-08 | MRP en base | ❓ | `run_mrp` existe (W10) |
| PRD-09 | Sous-traitance | 🔶 | maillons tracés (L1) |
| PRD-10 | Workflows et équivalences | ❓ | — |
| PRD-11 | Maintenance | ⬜ | coquilles |
| ACH-01 | Accords-cadres | ❓ | — |
| ACH-02 | Évaluation fournisseur | ❓ | — |
| ACH-03 | Contrôle budgétaire à l'engagement | ✅ | `307` |
| VTE-01 | Grilles tarifaires | ❓ | `price_list_customers` peu lue |
| VTE-02 | Encours client | 🔶 | `customer_credit_score` (W10) |
| VTE-03 | Remises, escomptes, conditions | ❓ | — |
| VTE-04 | Relances | ✅ | `258` |
| BNQ-01 | Formats bancaires | ✅ | R-10 (OFX, CFONB, MT940) |
| BNQ-02 | Rapprochement par score | 🔶 | `smart_bank_reconciliation` |
| BNQ-03 | État de rapprochement | ✅ | R-09 (`223`) |
| BNQ-04 | SEPA complet | ❓ | — |
| TRE-01 | Prévisionnel enrichi | ❓ | — |
| TRE-02 | Multidevise | ✅ | `306`, `309` |
| POS-01 | Comptabiliser, décrémenter | ✅ | `281` |
| POS-02 | Paiements multiples | ✅ | `281` |
| POS-03 | Loi anti-fraude | 🔶 | `250`, `255`, `267` ; certification hors dépôt |
| POS-04 | Ergonomie de caisse | 🔶 | ➜ 2.6 |
| CRM-01 | Séquences de relance | ⬜ | coquilles |
| CRM-02 | Scoring de lead | ⬜ | coquille |
| CRM-03 | Suivi d'e-mails | ❓ | — |
| PRJ-01 | Dépendances, chemin critique | ❓ | — |
| PRJ-02 | Capacité par ressource | ⬜ | `resource_capacities` coquille |
| PRJ-03 | Temps réel multi-utilisateur | 🔶 | real-time sur `projects`, `project_tasks` |
| PRJ-04 | Champs personnalisés | ⬜ | coquilles |
| PRJ-05 | Rentabilité de projet | 🔶 | `301` (refacturation) |
| PRJ-06 | Modèles et jalons | ❓ | — |
| PRJ-07 | Référence de planning | ❓ | — |
| PRJ-08 | Automatisations | ⬜ | ➜ L22/L23 |
| PRJ-09 | Portefeuille, permissions | ❓ | — |
| BI-01 | Générateur d'états | ⬜ | `report_definitions` coquille |
| BI-02 | Indicateurs normés | 🔶 | `278` (`get_kpis` au grand livre) ; ➜ L19 |
| BI-03 | Performance des tableaux de bord | ❓ | — |
| DAT-01 | Pagination | 🔶 | `fetchAllRows` |
| DAT-02 | Types réels | 🔶 | plafond `any` gelé (mesure §0), voie C ➜ 2.16 |
| DAT-03 | Index de couverture | 🔶 | G1 (index de société) |
| SEC-01 | Isolation multi-tenant | ✅ | `105` (340/340), W1 |
| SEC-02 | Authentification renforcée | ⬜ | ➜ ORPH-01 |
| SEC-03 | Journal d'audit applicatif | ❓ | — |
| SEC-04 | RGPD | 🔶 | D-5 (`318`) ; DPA 👤 |
| SEC-05 | Stockage de fichiers | 🔶 | `317` (bucket privé) |
| PRF-01 | Agrégations serveur | ✅ | = SOC-04 |
| PRF-02 | Poids du bundle | ✅ | index 26,5 ko gzip |
| PRF-03 | Rendu React | ❓ | — |
| PRF-04 | Équilibre en `FOR EACH STATEMENT` | ❓ | — |
| QUA-01 | Tests de base de données | ✅ | = SOC-02 |
| QUA-02 | Tests métier de référence | 🔶 | bulletins d'or (`276`), `266` |
| QUA-03 | Bout en bout | ⬜ | ➜ 4.3, 4.4 |
| QUA-04 | Couverture mesurée et verrouillée | 🔶 | plafonds gelés ; couverture non mesurée |
| UX-01 | i18n | ✅ | parité fr/en/ar + clés utilisées en CI |
| UX-02 | Accessibilité | 🔶 | essaim QA (0 défaut) ; D-7 |
| UX-03 | Remplacer `window.confirm()` | 🔶 | 0 `window.confirm` nu, mais `confirmSync` l'enveloppe ➜ 1.8 |
| UX-04 | États chargement / vide / erreur | ✅ | essaim QA, société vide |
| UX-05 | Saisie au clavier | ❓ | `useKeyboardEntry` existe |
| CNF-01 | Intégrations en simulation | 🔶 | W6 (tests Deno) |
| CNF-02 | Facturation électronique | 🔶 | W6 ; compte Chorus 👤 |
| CNF-03 | NF525 | 🔶 | = POS-03 |
| ADM-01 | Assistant de paramétrage | ❓ | — |
| ADM-02 | Rôles et permissions | ✅ | `239`, `271` |
| ADM-03 | Paramétrage comptable et fiscal | ❓ | — |
| ADM-04 | Modèles de documents | ⬜ | dépend de D-4 |
| ADM-05 | Journal d'audit exposé | ❓ | — |
| IMP-01 | Reprise de balance et d'historique | ✅ | `308` |
| IMP-02 | Import générique | 🔶 | `ai-import-mapping` (garde ➜ 1.11) |
| IMP-03 | Reprise tiers, articles, stocks, salariés | ❓ | — |
| IMP-04 | Passerelles concurrents | 🔶 | import Sage ; P3 ➜ propositions |
| API-01 | API publique | 🔶 | idempotence, OpenAPI ; clés ➜ ORPH-01 |
| API-02 | Webhooks fiables | 🔶 | W6 ; ➜ L23 |
| API-03 | Connecteurs métier | ⬜ | coquille |
| NOT-01 | Centre de notifications | ⬜ | coquille |
| NOT-02 | Alertes proactives | ⬜ | coquille |
| NOT-03 | Canaux de diffusion | ❓ | Resend 👤 |
| GED-01 | Rattachement universel | ⬜ | coquille |
| GED-02 | Numérisation des factures | 🔶 | OCR + consentement (`318`) |
| GED-03 | Archivage probant | 🔶 | `317` |
| GED-04 | Signature électronique | 🔶 | W6 ; Yousign 👤 |
| PTL-01 | Libre-service salarié | 🔶 | portail salarié (essaim QA) |
| PTL-02 | Espace responsable | 🔶 | `/manager/approvals` |
| PTL-03 | Mobile et hors ligne | ⬜ | — |
| GRP-01 | Structure de groupe | ⬜ | coquilles |
| GRP-02 | Opérations intra-groupe | ⬜ | coquille |
| GRP-03 | Consolidation | ⬜ | — |
| ONB-01 | Parcours d'inscription | ✅ | lot B, P0-09 |
| ONB-02 | Invitations et équipe | ❓ | — |
| ONB-03 | Abonnement du service | 🔶 | Stripe en attente 👤 |

**Compte de la passe du 02/10** : 141 chantiers — **35 ✅ · 47 🔶 · 27 ⬜ · 32 ❓**. À recompter à chaque passe ; l'objectif d'ORPH-03 est **0 ❓**.

---

## 8. Journal du suivi

| Date | Qui | Ce qui a changé |
|---|---|---|
| 02/10/2026 22:35 | partie 1 | 1.6 en cours dans `p1-fusion` (4 conflits) ⇒ 1.8 bloquée ; `340` pris par essai puis rendu ; `partie-1-stabiliser` et `partie-5-integrite-chainages` poussées |
| 02/10/2026 soir | partie 1 | 1.10 et 1.11 livrées sur `partie-1-stabiliser` (la mesure §0 lit la copie principale, qui ne les porte pas encore) |
| 02/10/2026 soir | numérotation | ALR-01 fermée (`430`→`432`), ALR-04 et ALR-05 ouvertes, partie 5 livrée, SOC-06 ✅ |
| 02/10/2026 | création | recoupement de tous les plans ; ALR-01 (collision `415`) trouvée par la mesure ; ORPH-01 → 04 ouverts ; première passe du 9,5 |
