# Reste à faire et plan par phases — 24 septembre 2026

> **Objet.** Répondre à deux questions, dans l'ordre : **(1)** où en est-on
> exactement — ce qui est fait, ce qui reste —, **(2)** comment exécuter ce qui
> reste, en **phases** qui peuvent être lancées l'une après l'autre, chacune
> laissant le dépôt meilleur et **vérifié**.
> **Sources.** [Plan correctif complet](PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md),
> [Référentiel des chaînages](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md),
> [Plan d'implémentation des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md),
> [Couverture d'audit par module](COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md),
> [Reste à faire au 22/09](RESTE-A-FAIRE-2026-09-22.md), et les preuves de vague
> ([W0](PREUVES-W0-2026-09-24.md), [W1](VAGUE-W1-ISO01-2026-09-24.md),
> [W1 suite](VAGUE-W1-ISO02-04-PERM01-2026-09-24.md),
> [W2/W3](VAGUE-W2-W3-2026-09-24.md)).
> **Règle de lecture.** `MESURÉ` = obtenu par exécution sur base neuve ;
> `PROPOSÉ` = charge estimée, à valider. Ce document ne remplace pas les plans :
> il les **ordonne** et dit ce qui reste.

---

## 1. Ce qui est fait (état au 24 septembre 2026)

| Vague / lot | Contenu | Preuve d'exécution |
|---|---|---|
| **W0** | CI capable de prouver : registre d'échecs par (fichier, test), scanners de colonnes écrites et d'erreurs non lues, contrôle des politiques jumelles ; correctifs `240`→`244` | Base neuve, **5 suites vertes**, 32/46 suites vertes (3 rouges = specs écrites avant leur correctif) |
| **W1** | Isolation et droits : `236` (18 déclencheurs `SECURITY DEFINER` filtrés par société), `237`+`249` (**408** clés étrangères devenues composites), `238` (**495** couples de politiques permissives dédoublonnés, 506 politiques et 12 index retirés), `239` (le rôle devient opposable sur **41 tables**, décision `D-6`) | Base neuve 220 migrations ; 105 : **340 tables isolées, 0 fuite** ; 236 17/17 · 237 8/8 · 238 8/8 · 239 9/9 ; trois contrôles permanents verts |
| **W0 → W3** (chaîne stock) | `240` société du mouvement + addition atomique · `241` réception → dépôt, couche, écriture, comptes résolus, traçabilité qui refuse · `242` livraison → dépôt, couches, réservations libérées | 240 4/4 · 241 7/7 · 242 6/6 |
| **W2** | Inaltérabilité NF-525 de la caisse : `250` — garde en modification (montants, date, numéro, empreinte, **pour tout le monde**), unicité `(société, caisse, numéro)` sous verrou, réparation des doublons avec recalcul des empreintes, `CHECK` de statut, `void_pos_ticket()` comme sortie honnête | **11 scénarios vus rouges avant, 11/11 après** ; `cancelPosTicket()` passe par la RPC |
| **W3** | `251` — annulation d'une réception : contrepassation du stock et de l'écriture, refus de la réédition et de la double contrepassation ; contrôle qualité : la quantité **contrôlée** et **rebutée**, au dépôt de la réception | **4 rouges avant, 6/6 après** |
| **Dettes déclarées (24/09, cette session)** | `253` annulation d'un **BL expédié** (stock, couche, écriture, refus de la double contrepassation) · `254` **une seule vérité de valorisation** (couches alignées sur le CUMP que la comptabilité applique) · `255` **l'avoir d'un ticket clôturé** (avoir commercial, stock rendu, vente marquée `refunded`, NF-525) · le **formulaire de contrôle qualité** expose `quantity_checked`/`quantity_rejected` (+ statut « partiel ») | 253 **5/5** · 254 **5/5** · 255 **5/5** ; `tsc`, `oxlint`, parité i18n fr/en/ar verts ; suites voisines (173, 219, 230, 241, 242, 251, 192) vertes |
| **Chaînages — L0 (socle)** | `252_chain_socle.sql` : 5 tables + `chain_settings`, 6 fonctions utilitaires, gabarit de maillon, partitions mensuelles | **en cours** (session parallèle) — le socle existe, **aucun maillon n'est encore branché** |
| **Exploitation** | Production alignée (29 migrations appliquées le 23/09), inscription réelle vérifiée, `plpgsql_check` 0 erreur sur la prod, 96/96 RPC des écrans présentes | `RESTE-A-FAIRE-2026-09-22.md` §P0-07/P0-09 |

**Ce que cela veut dire en une phrase.** Le socle de la comptabilité, de la
caisse, du stock et des droits est **mesuré et tenu par des tests exécutés** ;
ce qui reste est **la paie et les RH**, **les fonctions Edge**, **les modules
avancés** (devises, budgets, production, projets), **le chaînage de l'absence**,
et le **grand chantier des chaînages transverses** (25 lots).

---

## 2. Ce qui reste — par chantier, avec les chiffres

### A. Le plan correctif : les vagues W4 → W9 et les 9 scénarios transverses

| Vague | Défauts ouverts | Charge | Contenu |
|---|---:|---:|---|
| **W4 — Paie et RH** | 6 | 4 j | RH-05 quatre conventions mensuelles contradictoires (4,33 / 30 / 21 / 151,67) → **un seul diviseur par société** · RH-06 l'import des éléments variables échoue **5 mois sur 12** (`${period}-31` : février, avril, juin, septembre, novembre) · RH-07 notes de frais intégrées en paie pour **0 €** (`exp.amount` au lieu de `total_amount`) · RH-08 ni TVA récupérable, ni écriture 625x / 421 · RH-09 un congé **à cheval sur deux mois** est omis · RH-10 titres restaurant dupliqués au réimport |
| **W5 — Un seul moteur par grandeur** | 8 (1 🔴) | 2 j | deux moteurs d'amortissement (`generate_depreciation_entry` concurrent de l'écran) ; reste des heures supplémentaires |
| **W6 — Fonctions Edge et écrans placebos** | 9 (5 🔴) | 3,5 j | EF-01/02 le cron de relances échoue dès la première facture et la **relance part tous les jours** · EF-03/04 le bouton « Synchroniser » n'appelle **jamais** la fonction Edge, et celle-ci écrit une colonne inexistante en disant `success: true` · EF-05/06 la facture électronique n'est jamais enregistrée → **double envoi** · EF-07 signature jamais enregistrée · EF-08 webhooks (mauvais noms de colonnes) · TVA-01 l'EDI-TVA **n'envoie rien** — **plus** les deux baselines gelées par W0 : **20 écritures impossibles** et **29 erreurs non lues**, à ramener à zéro |
| **W7 — Comptabilité avancée** | 15 (4 🔴) | 6 j | M01-01→03 le taux de change est saisi, protégé… et **jamais appliqué** · ANA-01→03 (balance analytique sur tout l'historique, section non propagée) · BUD-01→04 (réalisé non borné à l'exercice) · SAGE-01→03 (écritures importées en brouillon, soldes **écrasés**, import partiel non transactionnel) · FEC-01 **une 2ᵉ implémentation du FEC** à 9 colonnes sur 18, à supprimer |
| **W8 — Production et projets** | 6 (1 🔴) | 3 j | PROD-01→03 nomenclature à **un seul niveau**, ni rebuts ni écarts, écriture datée du jour de clôture · PROJ-01→03 la **refacturation des temps n'existe pas** (c'est le `M-17-01` encore rouge au registre), avancement en moyenne non pondérée, tâche pouvant être son propre parent |
| **W9 — Chaînage absence** | 16 contrôles, 34 assertions | 4 j | registre d'absence (`employee_absence_days`) : une absence approuvée ne produit **aucun effet de paie** par défaut (`leave_rules.affects_pay` jamais posé), `timesheets.absence_type` n'est **jamais alimenté**, `work_stoppages` est une table morte, `sick_leaves` n'atteint aucun bulletin, + le contrôle quotidien |
| **T1 → T9** | 9 scénarios transverses | 5 j | après les vagues dont ils dépendent (W3 → W9) |

**Chemin critique : W4 → W9** — la paie d'abord, c'est le module où l'audit a
trouvé 4 défauts bloquants et le chaînage social tout entier en dépend.
**Parallélisable sans risque** : W6 (tables disjointes). **À sérialiser** : W5,
W6 et W8 touchent les mêmes écrans (un seul rédacteur par fichier) ; W3 et W7 se
croisent sur `journal_lines`.

### B. Le chantier des chaînages transverses (25 lots, ≈ 116 j)

Le référentiel a mesuré **62 chaînages existants** — note moyenne **3,65/7**,
idempotence **15 %**, trace **11 %** — et **62 états de statut sans effet aval**
(`R-001` → `R-062`).

| Bloc de lots | Contenu | Charge |
|---|---|---:|
| **L0** | socle : 5 tables, 6 fonctions utilitaires, gabarit de maillon, partitions — **en cours de commit** | 3 j |
| **L1** | rétro-instrumentation des **62 maillons** (`link_documents`, `emit_domain_event`) + rattrapage de l'historique | 5 j |
| **L2** | les **6 portes CI** (dont le contrat d'effet) + banc de performance | 3 j |
| **L3** | banc d'épreuve **D1→D8** (rejeu, concurrence, panne partielle, annulation, réouverture, retour arrière, volume, isolation) sur 62 maillons | 5 j |
| **L4-L5** | les **20 invariants transversaux** + `audit_chains` + job nocturne (l'indice de cohérence est aujourd'hui ≈ **5/20**) ; pages « Robustesse » et « Cohérence » | 8 j |
| **L6-L7** | **Vue Chaîne** (vue récursive amont/aval, analyse d'impact) ; **contrat d'effet** sur tous les types de documents | 9 j |
| **L8-L16** | les **62 règles d'état** par domaine (ventes, achats, trésorerie, paie/RH — qui fusionne `TRV-01`→`TRV-16` —, projets, production/stock, conformité, budgets) + les 9 familles de chaînages internes | 45 j |
| **L17-L19** | couples inter-modules : production ↔ RH (capacité ↔ absence), stock/production ↔ projets, production ↔ trésorerie | 12 j |
| **L20-L24** | régénération généralisée avec historique, dérivés du lettrage (TVA sur encaissements), moteur de règles client + simulateur, événements et webhooks unifiés, explicabilité et régularisation guidée | 30 j |

**Dépendance dure** : les lots L8-L16 **exigent** les vagues W1, W3, W4, W6, W7,
W8 et W9. Terminer **W4 et W9 débloque le lot paie/absence (L11)**, le plus
« commercial » du chantier.

### C. La couverture d'audit (ce qui n'a jamais été regardé)

| Mesure (24/09) | Aujourd'hui | Cible |
|---|---:|---:|
| Modules jamais audités par exécution | **16 / 20** | 0 |
| Fonctions Edge sans un test | **20 / 20** | 0 |
| Logique SQL traversée par un scénario | **64 %** | ≥ 90 % |
| Tables atteintes par un scénario | **80 / 341 (23 %)** | ≥ 200 |
| Tables portant de la logique jamais traversée | **24** | 0 |
| Tables sans logique **ni** scénario | 245 | à arbitrer (CRUD d'écran) |
| Tables coquilles vides (ni SQL, ni `src/`) | 41 | 0 (brancher ou supprimer) |
| Fichiers e2e Playwright qui remplissent un formulaire | **0 / 5** | 5 |

Les 24 tables « logique écrite, jamais traversée » incluent `api_keys` et
`user_totp` (**aucun scénario sur l'authentification forte**), `dsn_declarations`,
`landed_costs`, `stock_alerts`, `bank_reconciliation_suggestions`,
`project_milestones`, `lettrage_differences`, `journal_posting_sequences`,
`leave_balances`, `pay_recalls`, `cpf_accounts`, `carry_forward_log`,
`module_documents`, `tracking_warnings`. Depuis, `vat_returns` (245) et
`payroll_cumulative` / `payroll_accounting_entries` (247) sont couvertes.

### D. Ce qui ne dépend que de vous (décisions et accès)

| # | Sujet | État |
|---|---|---|
| 👤-1 | **Tourner la clé `sb_secret_…`** exposée dans l'historique git | 🔴 à faire |
| 👤-2 | Secrets E2E dans GitHub (`E2E_SUPABASE_URL`, `E2E_SUPABASE_KEY`, `E2E_TEST_EMAIL`, `E2E_TEST_PASSWORD`), sur un projet de **test** | 🔴 avant V4 |
| 👤-4 | Désigner l'**expert-comptable référent** (Djibouti) | 🔴 |
| 👤-5 | Collecter les **14 documents officiels djiboutiens** (CGI, loi de finances, TVA, barème ITS, taux CNSS/AMU, code du travail, plan comptable national…) | 🔴 délai externe le plus long |
| 👤-6 | Identifier **2 à 3 entreprises pilotes** | 🟠 |
| **P0-08** | Les **14 parcours à l'écran** — jamais faits depuis V1 ; demande le front déployé sur la base à jour | 🔴 non automatisable |
| D-4 | `generate-pdf` (SSRF prouvée) : supprimer le paramètre, durcir, ou retirer la fonction (aucun appelant) | ouverte |
| D-5 | Import OCR via OpenAI : consentement par société, remplacer, ou retirer | ouverte |
| D-7 | Contraste H2/H3 (18 + 20 usages juste sous 4,5:1) | ouverte |
| D-10 / D-13 | « Marquer payée » sans banque · périmètre de la séparation des tâches | à confirmer |
| D-11 | Localisation : `DJ-EP` seul ou aussi `DJ-ADM` (8 à 10 semaines) ; arabe dès la v1 ? | ouverte |
| Secrets | `STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY`, `VITE_SENTRY_DSN` | en attente (AGENTS.md) |

### E. Limites dites de ce qui est fermé (pour ne pas les redécouvrir)

| Limite | Où c'est dit |
|---|---|
| Le **décaissement** d'un avoir de caisse n'est pas écrit : l'avoir crédite le client, le règlement passe par les écrans de règlement | en-tête de la 255 |
| Une vente de comptoir **sans client** ne reçoit pas d'avoir (un avoir crédite quelqu'un) — la fonction le dit | 255, test T05 |
| Un article **suivi en lot** exigera le lot sur un retour de caisse (le contrôle S-11 le refuse sans) | en-tête de la 255 |
| Les méthodes `fifo` / `lifo` de `company_settings.stock_valuation_method` restent **inertes** (la comptabilité sort au CUMP) | en-tête de la 254, test T05 |
| Après clôture de caisse, la correction est un **avoir** — jamais une réécriture du ticket | 250 + 255 |
| `service_role` n'est pas soumis à `can_perform` : sa surveillance passe par les gardes de fonction (227) | en-tête de la 236 |
| `check_plpgsql` ne s'exécute pas en local (extension absente de l'image) : c'est la CI qui le porte | preuves W2/W3 |

---

## 3. Le plan par phases

**Principe d'ordonnancement.** Une phase commence quand la précédente est
**prouvée** (suites vertes, contrôle permanent vert, commit unique). Les phases 2
à 6 suivent le plan correctif (danger et dépendances) ; les phases 7 à 9 sont le
chantier des chaînages, qui **exige** les vagues ; la phase 10 est continue.

### Phase 1 — Solder et décider (0,5 j) — *peut démarrer aujourd'hui*

| Élément | Détail |
|---|---|
| **Fait** | Les 4 dettes déclarées sont fermées : `253` (annulation d'un BL expédié), `254` (une seule vérité de valorisation), `255` (l'avoir d'un ticket clôturé), formulaire de contrôle qualité |
| **Reste** | Les décisions qui bloquent : D-4 (`generate-pdf`), D-5 (OCR), D-7 (contraste), D-10 et D-13 (à confirmer), D-11 (périmètre de la localisation) |
| **Reste (vous)** | 👤-1 tourner la clé `sb_secret_…` ; 👤-2 les secrets E2E ; P0-08 (14 parcours à l'écran) ; 👤-4 expert-comptable ; 👤-5 les 14 documents djiboutiens ; 👤-6 les pilotes |
| **Critère de sortie** | Chaque décision est tranchée dans le registre (`RESTE-A-FAIRE` §3.2), la clé est tournée, les secrets sont posés — sinon les phases suivantes héritent de trous d'exploitation |

### Phase 2 — W4 : la paie et les RH (4 j) — *le chemin critique*

| Élément | Détail |
|---|---|
| **Défauts** | RH-05 (un seul diviseur mensuel par société), RH-06 (import des éléments variables qui échoue 5 mois sur 12), RH-07 (notes de frais à 0 €), RH-08 (TVA récupérable et écriture 625x/421), RH-09 (congé à cheval sur deux mois), RH-10 (titres restaurant dupliqués) |
| **Livrables** | Une migration (bornes de période calculées, `total_amount`, filtre d'intersection, idempotence par contrainte d'unicité `(tenant, salarié, période, type, source, source_id)`, un jeu de paramètres par société pour le diviseur, notes de frais → grand livre) + une suite par défaut |
| **Critère de sortie** | `243`, `247`, `181`, `212`, `224` non régressés ; **un seul élément de paie par document source** vérifié par la contrainte, pas par un `NOT EXISTS` recopié ; les 4 mois « impossibles » (février, avril, juin, septembre) passent en test |
| **Preuve attendue** | Base neuve, `tsc`/`oxlint`, suite verte, commits `NNN` + test + étape CI |

### Phase 3 — W9 : le chaînage de l'absence (4 j) — *dépend de W4*

| Élément | Détail |
|---|---|
| **Défauts** | Une absence approuvée ne produit **aucun effet de paie** par défaut (`leave_rules.affects_pay` jamais posé) ; `timesheets.absence_type` jamais alimenté ; `work_stoppages` table morte ; `sick_leaves` sans effet ; `expense_report_lines.date` et `project_time_entries.start_time` jamais confrontés à une absence |
| **Livrables** | Le **registre d'absence** (`employee_absence_days`) et les 16 contrôles (TRV-01→TRV-16) avec leurs 34 assertions, dont le contrôle quotidien |
| **Critère de sortie** | 34 assertions vertes, dont : une absence d'un jour apparaît **une fois** dans la paie, la DSN, le coût projet et le plafond ; une absence refusée n'apparaît nulle part |
| **Preuve attendue** | Les 16 contrôles exécutés sur base neuve, avec le « rouge d'abord » consigné |

### Phase 4 — W6 : fonctions Edge et écrans placebos (3,5 j) — *parallélisable*

| Élément | Détail |
|---|---|
| **Défauts** | EF-01/02 (le cron échoue et la relance part tous les jours), EF-03/04 (le bouton ne synchronise rien, la fonction écrit une colonne inexistante et dit `success: true`), EF-05/06 (facture électronique jamais enregistrée → double envoi), EF-07 (signature), EF-08 (webhooks), TVA-01 (l'EDI-TVA n'envoie rien) |
| **Plus** | Les deux baselines gelées par W0 à **ramener à zéro** : **20 écritures impossibles**, **29 erreurs non lues** (le plafond ne peut que baisser : `--update-baseline` refuse d'ajouter) |
| **Critère de sortie** | Toute écriture client correspond à une colonne réelle ; toute erreur d'API est **lue** ; aucun écran ne dit « succès » sur une opération qui n'a rien transmis ; les deux baselines sont à **0** |
| **Preuve attendue** | Le scanner de colonnes écrites et celui des erreurs non lues, réexécutés ; un test par fonction Edge (« un jeton, une réponse ») |

### Phase 5 — W5, W7, W8 : moteurs uniques, comptabilité avancée, production et projets (11 j)

| Vague | Défauts | Charge | Critère de sortie |
|---|---|---:|---|
| **W5** — un seul moteur par grandeur | 8 (1 🔴) | 2 j | **un seul** chemin d'amortissement (l'écran ne peut plus produire un plan différent du moteur) ; les heures supplémentaires ont une seule source ; `assets` non régressé (`211`, `226` verts) |
| **W7** — comptabilité avancée | 15 (4 🔴) | 6 j | le taux de change **appliqué** aux écritures en devise (M01-01→03) ; analytique propagée et bornée à l'exercice ; réalisé budgétaire borné ; import Sage **équilibré et transactionnel**, soldes cumulés ; **une seule** implémentation du FEC (18 colonnes) |
| **W8** — production et projets | 6 (1 🔴) | 3 j | nomenclature **multi-niveaux** explosée ; rebuts et écarts chiffrés ; écriture datée de l'OF ; **refacturation réelle** des temps (le `M-17-01` du registre **doit disparaître** de `ci/expected_failures.sql`) ; anti-cycle des tâches ; avancement pondéré |

> **Note d'exécution.** W5, W7 et W8 touchent des écrans que W6 vient de
> nettoyer : **un seul rédacteur par fichier**, et W7 se sérialise avec W3 sur
> `journal_lines`.

### Phase 6 — Les 9 scénarios transverses (5 j) — *après W3 → W9*

Chaque scénario traverse **plusieurs modules** et vérifie ce qu'aucune suite
mono-module ne peut voir : commande → livraison → facture → encaissement →
lettrage → clôture ; achat → réception → qualité → facture → paiement ;
temps → projet → facture → marge ; absence → paie → DSN → coût projet ;
caisse → clôture → comptabilité → TVA ; immobilisation → amortissement →
cession ; budget → engagement → réalisé ; import → lettrage → états ; et
**la contre-épreuve de falsification** (réintroduire chaque défaut corrigé et
vérifier que la CI le refuse).

**Critère de sortie** : les 9 scénarios verts **et** les 8 contre-épreuves
rouges (un défaut réintroduit doit casser la CI — sinon la suite ne prouve rien).

### Phase 7 — Chaînages, premier bloc : rendre visible, automatique, éprouvé (29 j)

| Lot | Livrable | Charge | Dépend de |
|---|---|---:|---|
| **L1** | rétro-instrumentation des **62 maillons** (chaque maillon trace ce qu'il produit) + rattrapage de l'historique | 5 j | L0 |
| **L2** | les **6 portes CI** (dont le contrat d'effet) + banc de performance | 3 j | L0 |
| **L3** | banc d'épreuve **D1→D8** sur les 62 maillons : rejeu, concurrence, panne partielle, annulation, réouverture, retour arrière, volume, isolation | 5 j | L1, L2 |
| **L4** | les **20 invariants transversaux** + `audit_chains(tenant)` + job nocturne (indice de cohérence : ≈ **5/20** aujourd'hui) | 5 j | L0 |
| **L5** | pages **« Robustesse »** et **« Cohérence »** (le client **voit** la qualité) | 3 j | L3, L4 |
| **L6** | **Vue Chaîne** : vue récursive amont/aval, composant unique branché sur les 10 écrans principaux, analyse d'impact (« si j'annule, voici ce qui sera extourné ») | 5 j | L1, L5 |
| **L7** | **Contrat d'effet** rempli pour tous les types de documents + onglet « Effet comptable » | 4 j | L0, L2 |

**Critère de sortie** : chaque chaînage a une **note de robustesse prouvée**
(et non plus statique) ; l'indice de cohérence est **publié et daté** par société ;
réintroduire une régression casse la CI.

### Phase 8 — Chaînages, deuxième bloc : les 62 règles d'état (45 j) — *exige W1…W9*

| Lot | Domaine | Règles couvertes | Charge |
|---|---|---|---:|
| **L8** | Ventes | `R-001` → `R-009`, `R-019` → `R-021` : devis → commande → livraison → facture → avoir, enfin soldé (pourcentages livré/facturé) | 6 j |
| **L9** | Achats | `R-010` → `R-018` : la réception entre en stock à son coût, l'engagement se libère | 5 j |
| **L10** | Trésorerie | `R-022` → `R-024`, `R-048` → `R-051` : lettrage, délettrage, virements internes, rejets bancaires traités | 4 j |
| **L11** | **Paie et RH** | `R-025` → `R-039` + fusion des `TRV-01` → `TRV-16` : l'absence, le contrat, la paie et la DSN deviennent **une seule chaîne** | 8 j |
| **L12** | Projets | `R-040` → `R-042` : clôture de projet (encours, facturation finale, retenue de garantie) | 3 j |
| **L13** | Production et stock | `R-043` → `R-047` : OF annulé/repris/rebuts, transferts entre dépôts, en-cours | 5 j |
| **L14** | Conformité et déclaratif | `R-052` → `R-056`, `R-062` : TVA, DSN, déclarations sociales | 4 j |
| **L15** | Budgets, engagements, relances | `R-057` → `R-061` + `INV-05` : engagements libérés, relance envoyée **une fois** | 3 j |
| **L16** | Chaînages internes | les 9 familles (comptabilité, stock, projet, RH, caisse…) : plus de tronçon manquant **à l'intérieur** d'un module | 2 j |

**Critère de sortie** : **zéro** état de statut sans effet aval (les 62 `R-xxx`
sont branchés ou explicitement écartés et justifiés) ; chaque règle a un test
d'effet **et** un test d'idempotence (rejouer ne double pas).

### Phase 9 — Chaînages, troisième bloc : entre modules et innovations (42 j)

| Lot | Livrable | Charge |
|---|---|---:|
| **L17** | Production ↔ RH : la capacité connaît les absences ; une charge de production apparaît dans le prévisionnel RH | 4 j |
| **L18** | Stock ↔ Projets et Production ↔ Projets : sortie de stock sur projet (imputation analytique), fabrication à la commande, coût matière dans la marge | 5 j |
| **L19** | Production ↔ Trésorerie ; Reporting ↔ Tous : définitions **uniques** de marge, CA et DSO | 3 j |
| **L20** | Régénération généralisée (changer un taux, un compte, un prix de revient **régénère** les pièces liées, avec historique et retour arrière) | 5 j |
| **L21** | Dérivés du lettrage : TVA sur encaissements, réversibilité conditionnée au lien, refus explicite si le lien est rompu | 5 j |
| **L22** | Moteur de règles client + simulateur d'impact (« voici ce que votre validation va produire ») | 8 j |
| **L23** | Événements, automatisations et webhooks **unifiés** (un journal, des règles, des abonnements) | 4 j |
| **L24** | Explicabilité (« pourquoi ce chiffre ? »), régularisation guidée, localisation par chaînes, assistant qui répond **avec preuve** | 8 j |

### Phase 10 — La couverture, en continu (≈ 15 j répartis)

| Chantier | Aujourd'hui | Cible | Comment |
|---|---|---|---|
| **16 modules jamais audités par exécution** | 16 / 20 | 0 | un scénario chiffré par module, dans l'ordre du danger (le registre estime **une trentaine de défauts**, dont plusieurs bloquants) |
| **20 fonctions Edge sans test** | 20 / 20 | 0 | un test par fonction, y compris **sans jeton** (le 401 doit être un refus, pas un silence) |
| **Authentification forte** | aucun scénario | 1 | `api_keys`, `user_totp` : émission, usage, révocation, rejeu |
| **e2e Playwright** | 0 / 5 remplissent un formulaire | 5 | au moins un montant lu et vérifié par parcours |
| **41 tables coquilles vides** | 41 | 0 | brancher ou supprimer (une table vide est une promesse non tenue) |

**Critère de sortie** : les chiffres du tableau §2.C atteignent leurs cibles, et
`check_unused_tables` / `knip` restent au plafond (jamais au-dessus).

---

## 4. Comment on exécute une phase (la méthode, non négociable)

1. **Un défaut** = un test chiffré qui **échoue avant** le correctif, pour la
   bonne raison (le « rouge d'abord » se consigne) ;
2. **une migration** numérotée `NNN_<nom>.sql`, rejouable, **sans perte de
   données** (reprise des lignes existantes quand un `CHECK` ou une unicité
   arrive — et si la reprise est impossible, la migration **nomme** les lignes
   et refuse, elle n'efface pas) ;
3. **le test branché dans `.github/workflows/ci.yml` dans le même commit** ;
4. **la ligne du registre** `ci/expected_failures.sql` retirée si le défaut y
   figurait (la CI échoue si un test corrigé y reste) ;
5. **les non-régressions** : `105` (isolation), `178`, `181`, `219`, `189` et les
   suites du module touché — rejouées, pas supposées ;
6. **le chiffre du tableau de bord** mis à jour, avec sa date.

Et la leçon du 24/09 : **le travail non commité n'existe pas** — une
synchronisation externe a vidé `app/sql` en pleine session ; les fichiers non
suivis n'ont été sauvés que par les *checkpoints* de l'éditeur. Un correctif vit
avec sa suite, son câblage CI **et son commit**, ou il ne vit pas.

---

## 5. Les charges, en une ligne

| Bloc | Charge |
|---|---:|
| Phases 2 à 6 — plan correctif (W4 → W9 + transverses) | **≈ 38 j** |
| Phases 7 à 9 — chaînages (L1 → L24) | **≈ 116 j** |
| Phase 10 — couverture d'audit (16 modules, 20 fonctions Edge, e2e) | **≈ 15 j** |
| **Total restant** | **≈ 169 j** |
| Déjà livré et prouvé (W0 → W3 + les 4 dettes) | **≈ 15 j** |

**Ce que ce document ne dit pas** : les défauts que l'audit des 16 modules
restants révélera (une trentaine, dont plusieurs bloquants selon le taux
constaté), les délais externes (les 14 documents djiboutiens, l'expert-comptable,
les pilotes), et la recette à l'écran (P0-08), qui n'est pas une charge de
développement mais un passage obligé.




