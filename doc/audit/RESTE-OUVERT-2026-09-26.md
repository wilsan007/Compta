# Ce qui reste ouvert — état au 26 septembre 2026

> **Mises à jour.** 27/09 : W5, W10 · 28/09 : W7 partielle, **W8 fermée** ·
> **30/09 : W7 fermée, L1 (tranches 1 à 5), L2, L7, essaim QA** — voir §0.

> **Objet.** Une seule page, à jour, de **tout ce qui n'est pas fermé** après la
> vague W6 : ce qui attend une décision, ce qui vit hors du dépôt, ce qui reste
> à coder — et, depuis le 28/09, **un registre de CI vide** : les deux échecs qui
> y étaient inscrits (`231 M-17-01`, `245 T08`) sont fermés.
> **Règle de lecture.** `MESURÉ` = obtenu par exécution ; `PROPOSÉ` = charge
> estimée, à valider. Ce document ne remplace pas les plans : il les **résume**.
> **Sources.** [Plan correctif complet](PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md),
> [Reste-à-faire et plan par phases](RESTE-A-FAIRE-ET-PLAN-PHASES-2026-09-24.md),
> [Référentiel des chaînages](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md),
> [Plan des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md),
> [Couverture d'audit par module](COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md), et
> les preuves de vague ([W0](PREUVES-W0-2026-09-24.md),
> [W1](VAGUE-W1-ISO02-04-PERM01-2026-09-24.md), [W2/W3](VAGUE-W2-W3-2026-09-24.md),
> [W4](VAGUE-W4-2026-09-26.md), [W6](VAGUE-W6-2026-09-26.md),
> [W9](VAGUE-W9-2026-09-26.md), [W5](VAGUE-W5-2026-09-27.md),
> [W10](VAGUE-W10-2026-09-27.md), [W7](VAGUE-W7-2026-09-28.md),
> [W8](VAGUE-W8-2026-09-28.md), [W7/W8 partielles](VAGUE-W7-W8-2026-09-28.md),
> [L1](VAGUE-L1-2026-09-29.md),
> [L1 tranche 3](VAGUE-L1-TRANCHE3-CYCLE-DU-LIEN-2026-09-30.md),
> [L1 tranche 4](INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md),
> [L2](VAGUE-L2-PORTES-CI-2026-09-30.md),
> [L7](VAGUE-L7-CONTRATS-DEFFET-2026-09-30.md),
> [essaim QA](QA-ESSAIM-2026-09-29.md)).
> **Mémoire.** Ce document est référencé par `AGENTS.md` (section « Reste
> ouvert ») : c'est le point d'entrée pour reprendre le travail.

---

## 0. Mise à jour du 30/09/2026 — deux lignes périmées, et ce qu'elles coûtaient

Cette page portait encore, après le 28/09 au soir, **deux affirmations fausses** —
au point qu'une reprise de travail en a déduit un reste de « ≈ 2 j » qui **n'existe
plus** (le défaut était déjà corrigé, testé et branché en CI) :

| Ce qui était écrit ici (§1 et §3) | Le fait | Où le constater |
|---|---|---|
| « **W7 reste ouverte** : 10 défauts (`M01`, `BUD`, `SAGE`) », « reste de W7 ≈ 2 j » | **W7 est fermée** (28/09) : ses **quinze** défauts sont corrigés par `300` → `309` | [VAGUE-W7](VAGUE-W7-2026-09-28.md) §9 ; commit `5a222cd` |
| Rien au-delà de W8 | **L1** (`310`, `311`, `312`, `314`), **L2** (les six portes CI), **L7** (`313`) et l'**essaim QA** (registre vide) sont livrés et prouvés | [L1](VAGUE-L1-2026-09-29.md) · [L1 tr. 3](VAGUE-L1-TRANCHE3-CYCLE-DU-LIEN-2026-09-30.md) · [L2](VAGUE-L2-PORTES-CI-2026-09-30.md) · [L7](VAGUE-L7-CONTRATS-DEFFET-2026-09-30.md) · [QA](QA-ESSAIM-2026-09-29.md) |

**`SAGE-01→03`, nommément** — c'est le défaut qu'on vient chercher ici, et il est
**livré** par la **`308`** : `import_fec_entries(p_entries jsonb)` fait **une**
transaction, contrôle l'équilibre **global** avant toute écriture, **valide** les
écritures par le chemin unique (`validate_journal_entries`, `273`), **cumule** les
soldes des comptes et crée les comptes manquants du plan. La suite **`308`** est
branchée en CI (étape « AUD : import d'écritures en une transaction (308) »),
**5/5**, après un rouge d'abord **pour la bonne raison**
(`function public.import_fec_entries(jsonb) does not exist`).
[Preuve](VAGUE-W7-2026-09-28.md) §7.

> ⚠️ **Numérotation** — un numéro se **constate**, il ne se réserve pas. État
> constaté le 30/09 : `270` → `272` (session parallèle, audit fonctionnel),
> `273` → `281` (audit fonctionnel, parties 1 à 3), `300` → `309` (**W7**),
> `310` → `314` (**L1** tranches 1 à 4, **L2**, **L7**), `315` → `316` (**L1**
> tranche 5 : les cinq candidats directs et la valeur `sans_effet`), `317` et
> au-delà : la **session parallèle en cours** (chaînages).

---

## 1. Ce qui est fermé (rappel, avec la preuve)

| Vague | Contenu | Preuve |
|---|---|---|
| **W0** | CI capable de prouver : registre d'échecs par (fichier, test), scanners de colonnes écrites et d'erreurs non lues, contrôle des politiques jumelles | [PREUVES-W0](PREUVES-W0-2026-09-24.md) |
| **W1** | Isolation et droits : déclencheurs filtrés par société, clés étrangères composites (413 tenues par la base, 0 mono-colonne), politiques jumelles dédoublonnées, rôles opposables (62 tables) | [W1](VAGUE-W1-ISO02-04-PERM01-2026-09-24.md) |
| **W2** | Inaltérabilité NF-525 de la caisse (montants, date, numéro, empreinte — pour tout le monde ; sortie honnête `void_pos_ticket()`) | [W2/W3](VAGUE-W2-W3-2026-09-24.md) |
| **W3** | Chaîne stock : réception → dépôt → couche → écriture ; livraison → réservation libérée ; chemins d'annulation (réception **et** BL) ; une seule vérité de valorisation (CUMP) | idem + `253`, `254` |
| **W4** | Paie : un seul diviseur mensuel par société, bornes de période calculées, notes de frais au grand livre, idempotence par document source | [W4](VAGUE-W4-2026-09-26.md) |
| **W6** | Fonctions Edge et écrans placebos : 20 colonnes réelles, relance idempotente, un écran ne peut plus tamponner un succès, **les deux baselines de W0 à zéro**, contrat d'entrée des 20 fonctions testé (32 tests Deno), fonctions sans appelant branchées ou neutralisées | [W6](VAGUE-W6-2026-09-26.md) |
| **W9** | Chaînage de l'absence : registre `employee_absence_days`, gardes en aval, une seule retenue de paie, 34 assertions transverses | [W9](VAGUE-W9-2026-09-26.md) |
| **W5** | Un seul moteur par grandeur : `calculate_depreciation` supprimée, méthode d'amortissement **lue** (dégressif paramétré, `units_of_production` retirée), exercice **borné**, lot à verdict par immobilisation, heures supplémentaires à **un** seuil / **un** taux / **un** montant | [W5](VAGUE-W5-2026-09-27.md) |
| **W10** | Le contrat d'appel front ↔ base : le contrôle `check-rpc-contract` (baseline **à zéro**), les **14 appels** que la base ne pouvait pas servir (4 fonctions de déclencheur appelées depuis des écrans vivants, stock compté deux fois, période NF-525 envoyée comme une date, IJSS calculées sur un couple salarié/jours), et la **267** qui rend la clôture NF-525 possible (append-only, elle cesse d'écrire dans le journal inaltérable et remplit `nf525_period_closures`) | [W10](VAGUE-W10-2026-09-27.md) |
| **W7 (partielle)** | Le **CA non taxé** entre dans la CA3 (`245 T08`, `300`) : la base hors taxe n'est plus reconstituée depuis la TVA, elle se lit sur les comptes de produits (classe 70) | [W7/W8](VAGUE-W7-W8-2026-09-28.md) |
| **W8 (partielle)** | La **refacturation des temps** existe (`231 M-17-01`, `301`) : brouillon de facture par projet, ligne rattachée au temps (unicité société + temps), saisie directe couverte, suppression en chaîne mesurée | [W7/W8](VAGUE-W7-W8-2026-09-28.md) |
| **W8 ✅ fermée** | Les 5 défauts restants : **PROD-01→03** (`302` : nomenclature **explosée** sur tous les niveaux, quantité produite **déclarée** respectée, rebuts impossibles refusés, **écart de coût** chiffré, écriture datée de l'OF) et **PROJ-02/03** (`303` : avancement **pondéré** par une seule règle aux deux niveaux, anti-cycle nommé) | [W8](VAGUE-W8-2026-09-28.md) |
| **Audit fonctionnel exécuté (28/09)** | Parties 1 à 3 du [plan](PLAN-CORRECTIF-AUDIT-FONCTIONNEL-2026-09-28.md) : écriture anonyme fermée, droits, comptabilité, paie (grille 2026 : signature de l'expert en attente), trésorerie, **stock et logistique, caisse, production** (`280`, `281`) — le registre du **chemin de l'écran** est **vide** | [X4/X5/X8](VAGUE-X4-X5-X8-2026-09-28.md) |
| **W7 (partie 1)** | **`ANA-01/02`** (`304` : les deux déclencheurs analytiques étaient des placebos, la section circule de la **ligne de document** vers la ligne d'écriture) · **`ANA-03`** (la balance analytique est **bornée à l'exercice**) · **`FEC-01`** (`305` : la 2ᵉ implémentation du FEC, 9 colonnes sur 18, est supprimée) | [W7](VAGUE-W7-2026-09-28.md) |
| **W7 (partie 2)** | **`M01-01/02`** (`306` : **le taux de change s'applique** — 1 000 USD à 0,90 → 900 EUR ; la ligne porte devise, montant en devise et taux ; une pièce en devise **sans taux** est refusée) · **`BUD-01→04`** (`307` : réalisé **borné à l'exercice**, brouillons et AN/CL exclus, **une** requête par exercice au lieu de deux par budget ; les engagements d'une commande sont **créés** puis **consommés** à la facturation) | [W7](VAGUE-W7-2026-09-28.md) |
| **W7 ✅ fermée** | Les **quinze** défauts du plan sont fermés : `300` (CA non taxé dans la CA3), `304` (l'analytique des documents circule jusqu'aux lignes d'écriture), `305` (une seule implémentation du FEC), `306` (le taux de change s'applique), `307` (budgets : réalisé borné, engagements créés et consommés), **`308` — `SAGE-01→03` : l'import d'écritures est un acte unique** (équilibre global contrôlé, écritures **validées** par le noyau, soldes **cumulés**), `309` (écart de change au règlement et réévaluation de clôture) | [W7](VAGUE-W7-2026-09-28.md) |
| **L1 — tranches 1 à 5** (29 et 30/09) | **22 effets** de la chaîne ventes → trésorerie → comptabilité **tracés** et **22 contrats déclarés** (`310`, `311`, `314`, `316`) ; **le lien a un cycle de vie** (`312` : `actif` → `remplace` \| `rompu`, index d'idempotence **partiel**, `chain_avant` rend vrai après fermeture) ; le vocabulaire de trace gagne **`sans_effet`** (`315`) ; **61 scénarios** d'acceptation (les cinq tranches L1) ; non-régression **689 verdicts verts, 0 rouge** sur base neuve (**265 migrations**) | [L1](VAGUE-L1-2026-09-29.md) · [tr. 3](VAGUE-L1-TRANCHE3-CYCLE-DU-LIEN-2026-09-30.md) · [tr. 4](INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md) · [tr. 5](VAGUE-L1-TRANCHE5-2026-09-30.md) |
| **L2 — les six portes CI** | `G1` grille BT (RLS et index de société, plafond daté) · `G2` contrat d'effet (vu **rouge** sur un maillon neuf non déclaré) · `G3` colonnes et écritures muettes · `G4` garde de société · `G5` câblage des suites (**90 suites, 90 branchées** — c'est elle qui a trouvé la `312` que personne n'avait branchée) · `G6` banc des chaînages (**p95 1,002 ms** pour 50 ms de budget) | [L2](VAGUE-L2-PORTES-CI-2026-09-30.md) |
| **L7 — les contrats d'effet** | `313` : les maillons ne tracent plus « sans contrat » — **1 132** traces `tolere` pour 1 117 `applique` **avant**, **5** `tolere` (toutes provoquées par les scénarios qui éteignent un contrat) **après** ; le mode `refuse` devient utilisable | [L7](VAGUE-L7-CONTRATS-DEFFET-2026-09-30.md) |
| **Essaim QA** | **668 visites, 334 routes, 0 défaut**, quatre gabarits et deux sociétés (remplie et vide) ; le registre `.qa-baseline.json` est **vide** | [QA](QA-ESSAIM-2026-09-29.md) |

État mesuré sur base neuve : **265 migrations, 0 erreur** ; **12 contrôles** du
dépôt à 0 erreur (`check_plpgsql` **non exécutable** dans l'image locale —
extension `plpgsql_check` absente) et **93 suites** branchées (porte `G5`) ;
**689 verdicts** de non-régression verts, **0 rouge** (84 fichiers de suite) ;
front `tsc` 0, `oxlint` 0, parité i18n fr/en/ar,
**Vitest 1 513**, **32 tests Edge Deno** ; les **trois** scanners de code
(`check-written-columns`, `check-unchecked-writes`, `check-rpc-contract`) à
**0**, baselines vides.

---

## 2. Ce qui reste ouvert, par nature

### A. Ce qui attend une décision (elle n'appartient pas au dépôt)

| ID | Sujet | Où c'est dit |
|---|---|---|
| **D-4** | `generate-pdf` — **défaut appliqué** le 26/09, **voie A ouverte** le 30/09 : la migration **`317`** pose le bucket d'archive (`generated-pdfs`, privé, PDF seulement, lecture bornée à la société ET au module) et la fonction ne ment plus (`503` sans convertisseur au lieu du HTML en `200`, `500` au lieu de `success: true` avec `url: null`, `upsert: false`). Restent : **A1** (convertisseur injoignable du réseau interne), `GOTENBERG_URL`, **un appelant**, le déploiement | [note d'aide à la décision](DECISION-D4-GENERATE-PDF-2026-09-30.md) §9 · `RESTE-A-FAIRE` §3.1 |
| **D-5** | OCR : périmètre et fournisseur | idem |
| **D-7** | Contraste : seuils retenus pour les thèmes | idem |
| **D-10**, **D-13** | À confirmer | idem |
| **D-11** | Périmètre de la localisation (les 14 documents djiboutiens) | idem |
| 👤-1 | Tourner la clé `sb_secret_…` exposée | `RESTE-A-FAIRE` §3.2 |
| 👤-2 | Secrets E2E (Playwright) | idem |
| 👤-4 | Expert-comptable (recette des états) | idem |
| 👤-5 | Les 14 documents djiboutiens (textes de référence) | idem |
| 👤-6 | Pilotes (utilisateurs réels) | idem |
| **P0-08** | Les 14 parcours à l'écran (recette) — ce n'est pas une charge de développement, c'est un passage obligé | `RESTE-A-FAIRE` §5 |

### B. Hors du dépôt : la recette des intégrations réelles

Ce que W6 **ne peut pas** prouver sans comptes configurés — et ce qui est prouvé
à la place, dans chaque cas :

| Intégration | Ce qui reste à faire | Ce qui est déjà prouvé |
|---|---|---|
| **Chorus Pro** (`submit-e-invoice`) | compte + `CHORUS_PRO_TOKEN` + un dépôt réel | trace écrite et relue, refus du **double envoi**, « non configuré » honnête (503) |
| **Yousign** (`request-signature`) | compte + `YOUSIGN_API_KEY` + une signature réelle | demande enregistrée (prestataire, identifiant, statut, signataires, date), échec d'enregistrement signalé |
| **GoCardless** (`sync-bank-transactions`) | compte + `GOCARDLESS_API_TOKEN` + un compte de test | colonnes réelles, idempotence par `provider_transaction_id`, état d'erreur visible sur la connexion |
| **Resend** (`cron-payment-reminders`, e-mails) | `RESEND_API_KEY` | prise de la relance **avant** l'envoi, clôture avec l'heure réelle et l'erreur du prestataire |
| **EFI / impots.gouv** (`submit-vat-return`) | `EFI_API_TOKEN` + une télédéclaration de test | l'écran ne dit « déposée » que sur confirmation |
| **INSEE SIRENE / VIES** (`verify-siret`, `validate-vat-vies`) | `SIRENE_API_TOKEN` | le verdict **local** (Luhn, longueur, format) est vérifié par test ; l'écran nomme la source (« à la source » ou « format et clé seulement ») |
| **Stripe** | `STRIPE_WEBHOOK_SECRET` + webhooks pointés sur `handle-stripe-webhook` | sans secret : refus 500 nommé ; sans signature : refus 400 nommé |
| **Gotenberg** | décision `D-4` (**voie A ouverte** le 30/09) | HTML client refusé, valeurs échappées ; `503` nommé sans `GOTENBERG_URL` ; l'archive est posée (bucket `generated-pdfs`, suite `317` 9/9) — il manque le **convertisseur isolé** (A1) et le secret |
| **Sentry** | `VITE_SENTRY_DSN` | code prêt (ErrorBoundary) |

### C. Le plan correctif : les vagues restantes (PROPOSÉ)

| Vague | Défauts | Charge | Contenu |
|---|---:|---:|---|
| **W7 — Comptabilité avancée** ✅ **fermée (300 → 309, 28/09)** | 0 (était 14) | 6 j | ✅ **le CA non taxé entre dans la CA3** (`300`) · ✅ **analytique** (`304`) · ✅ **un seul FEC** (`305`) · ✅ **devises** (`306` : le taux s'applique ; `309` : **écart de change au règlement** 666/766 et **réévaluation de clôture**) · ✅ **budgets** (`307`) · ✅ **import d'écritures en une transaction** (`308`) ([preuve](VAGUE-W7-2026-09-28.md)) |
| **W8 — Production et projets** ✅ **fermée (302, 303, 28/09)** | 0 (était 5) | 3 j | ✅ la **refacturation des temps** existe (`231 M-17-01` fermé le 28/09 par la `301`) ; `302` : nomenclature **multi-niveaux** explosée par **une** fonction qui sert aussi au coût et aux sorties, quantité produite **déclarée** respectée, rebuts impossibles **refusés**, **écart de coût** chiffré (`cost_variance`), écriture datée de l'OF ; `303` : avancement **pondéré** par une seule règle (parent et projet), **anti-cycle** des tâches ([preuves](VAGUE-W8-2026-09-28.md)) |
| **T1 → T9** — les 9 scénarios transverses | **absorbés par les lots de chaînages** | **0 j** au titre du plan correctif | ils existent désormais comme suites chiffrées qui traversent les modules : `310` (**15** scénarios ventes → trésorerie → comptabilité), `311` (**12**), `312` (**12**, cycle du lien), `314` (**11**), `266` (absence → paie → DSN → coût projet) — et la **contre-épreuve de falsification** est devenue **permanente** : les portes `G2` (contrat d'effet) et `G5` (câblage des suites) ont été **vues rouges**, l'une sur un maillon neuf non déclaré, l'autre sur une suite non branchée. Le reste du transverse est **L4** (les 20 invariants, `INV-01→INV-20`), compté **dans** les 116 j ci-dessous |
| | **Total du plan correctif** | **0 j** | les vagues W sont **toutes fermées** (W0 → W10, `238` → `309`) et les transverses sont absorbés par L1/L2/L4 |

> **W5 a été exécutée le 27/09** (2 j, `260`) : elle sort de ce tableau. Elle
> laisse un point ouvert pour la phase 6 : `calculate_overtime_pay` (tranches et
> exonération de 7 500 €) n'a plus d'appelant, et le chemin de paie applique la
> **première** tranche — les bandes supérieures ne sont donc pas appliquées.
>
> **W10 (27/09) n'était pas au plan** : elle vient de l'angle mort que les trois
> contrôles existants laissaient ouvert — **les appels de fonction**. Elle a
> coûté ≈ 2 j et n'entre donc dans aucune ligne de ce tableau : l'audit des
> modules restants en produira d'autres du même genre.

### D. Les chaînages (le gros du reste)

Les **62 maillons** entre modules, en 24 lots (L1 → L24) — dont la
rétro-instrumentation, les 6 portes CI, le banc d'épreuve D1→D8, les 20
invariants transversaux, les pages « Robustesse » et « Cohérence », la vue
Chaîne, le contrat d'effet, les 62 règles d'état, la régénération généralisée,
la TVA sur encaissements, le moteur de règles client, les automatisations
unifiées et l'explicabilité.

**Charge : ≈ 116 j** — c'est le **chiffre brut du plan**, non déduit de ce qui est
déjà livré : c'est un **plafond**, pas un reste exact (détail :
`RESTE-A-FAIRE` §3.3 et `PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md`).

**Déjà livré sur ce bloc :** le socle `L0` (`252`) ; **L1, tranches 1 à 5** (`310`,
`311`, `312`, `314`, `316` — **22 effets tracés** et **22 contrats déclarés**, 15
déclencheurs compagnons `zz_l1_`, 4 corps réécrits pour lier **par ligne**, le
vocabulaire de trace enrichi de **`sans_effet`** (`315`), 61 scénarios
d'acceptation) ; **L2** (les six portes `G1` → `G6`) ; **L7** (`313`) ;
et W9 a livré la chaîne de l'absence de bout en bout. La méthode de l'inventaire,
**rejouée le 30/09**, compte **99 fonctions** transverses (62 au 24/09) dont
**32 écrivent dans ≥ 2 modules** — classées avec leur verdict et leur raison.

**Ce qui reste, nommé :** dans L1, **5 candidats directs** et **9 maillons RPC**,
plus la **réception de marchandise** (elle demande la réécriture du corps, pas un
compagnon) — [inventaire de la tranche 4](INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md).

### E. La couverture d'audit (phase 10, en continu)

| Chantier | Aujourd'hui | Cible | Charge |
|---|---|---|---:|
| Modules jamais audités par exécution | 16 / 20 | 0 | inclus |
| Fonctions Edge : contrat d'entrée | **20 / 20** ✅ (W6, 32 tests Deno) | — | — |
| Fonctions Edge : parcours complets (base + prestataires) | 0 / 20 | 20 | avec les comptes (tableau B) |
| Parcours e2e Playwright qui remplissent un formulaire | 0 / 5 | 5 | inclus |
| Tables coquilles vides (brancher ou supprimer) | 41 | 0 | inclus |
| Authentification forte (`api_keys`, `user_totp`) : émission, usage, révocation, rejeu | aucun scénario | 1 | inclus |
| **Total phase 10** | | | **≈ 15 j** |

### F. Le registre de la CI : vide, et ce qu'il portait

`app/sql/ci/expected_failures.sql` est **VIDE depuis le 28/09/2026** : les deux
défauts qui y figuraient sont corrigés, et leurs lignes ont disparu dans le commit
du correctif — c'est le rappel qui l'exige (la CI **échoue** si un test corrigé
reste au registre).

| Fichier | Test | Le défaut, en une phrase | Fermé par |
|---|---|---|---|
| `231` | `M-17-01` | les heures facturables n'atteignent aucune facture (`create_billable_line_on_timesheet_stop` ne crée qu'une notification) | **W8**, `301` (28/09) |
| `245` | `T08` | le chiffre d'affaires **non taxé** (exonéré, export, livraison intracommunautaire) n'entre pas dans le CA déclaré : la base de la CA3 est reconstituée depuis la TVA | **W7**, `300` (28/09) |

### G. Ce que W6 laisse explicitement non fermé

* **Cinq parcours Playwright** : dépôt électronique, synchronisation bancaire,
  demande de signature, vérification SIRET et IBAN — ils exigent une application
  servie avec un jeu de données (phase 10).
* **La recette réseau** des neuf intégrations (tableau B).
* **La décision `D-4`** (tableau A).

### H. Ce que W10 laisse explicitement non fermé

* **Deux boutons ont été retirés** (« Appliquer les règles » au rapprochement
  bancaire, « Vérifier la limite de crédit » sur la fiche client) : ils
  appelaient des fonctions de **déclencheur**, que PostgREST n'expose jamais. Si
  l'action manuelle est voulue un jour, elle demande une **vraie** fonction —
  c'est un ajout, pas un rebranchement.
* **Faut-il refuser l'écriture d'un événement NF-525 dans une période déjà
  clôturée ?** Aujourd'hui non : l'interdire changerait le sort d'une vente ou
  d'une facture saisie après coup. C'est une **décision de gestion** (candidat
  au tableau A), pas un correctif. L'attestation revérifie la chaîne et recompte
  les événements (`verify_nf525_chain`), donc l'écart est visible.
* **Le contrôle d'appel ne suit pas les indirections** : `.rpc(nomVariable)`
  (aucun aujourd'hui) et `.schema('x').rpc(…)` (aucun non plus) échapperaient à
  la confrontation — le premier est compté « non vérifiable », le second n'est
  pas suivi. Et `calculate_payslip` restera non vérifiable tant que son objet
  d'arguments sera une variable.

---

### I. Ce qui vient **après** les chaînages — propositions, non planifiées

**Rien de ceci n'est commencé, et rien ne doit l'être avant que `L3` → `L4` → `L5`
soient livrés et prouvés** (et `L6`/`L23`/`L24` pour `P6`) : ces propositions sont
des **lecteurs de la preuve**, pas des fonctions. Détail, dépendances, charges,
indicateurs et questions à trancher — **les cinq questions ont des
[**réponses proposées**](PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md#6-les-cinq-questions-et-les-réponses-proposées-3009),
la décision restant au produit :
[**PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md**](PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md).

| # | Proposition | Charge | Ce qu'elle débloque |
|---|---|---:|---|
| **P1** | **Certificat d'intégrité** signé et daté | 2-3 j | monétise `L3`/`L4`/`L5` ; ouvre le canal **expert-comptable / banque** |
| **P2** | Banc d'épreuves exécuté sur les **données du prospect** | 3-4 j | l'arme commerciale : la preuve **avant** la signature |
| **P3** | **Audit de reprise** à l'import (Sage / FEC) | 2-3 j | l'entrée chez le client : *« votre ancien outil vous mentait »* |
| **P4** | Remonter le temps (« vos comptes tels qu'au 31/12 à 23 h 59 ») | 3-5 j | contentieux, contrôle, banque — **sans consultant** |
| **P5** | **Documentation vivante** (le contrat d'effet rendu au client) | 3 j | une doc **qui ne peut pas mentir** (garantie par la porte `G2`) |
| **P6** | L'**IA qui cite** (refuse de répondre sans preuve) | 5 j | après `L6`/`L23`/`L24` : hallucination **structurellement** impossible |
| **P7** | Sortie aussi rapide que l'entrée | 2 j | l'anti-enfermement, **dit et mesuré** |
| **P8** | API « chaîne » + packs de règles par pays | 2 j + pays | l'effet de réseau, à l'échelle des PME |

**Ce qui est déjà au plan — et qu'il ne faut donc pas compter ici** : les **12
innovations** `I-01` → `I-12` et les lots `L16` → `L24` (voir
[plan](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md) §Phase F et
[référentiel](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md) §D.4).
**Ordre conseillé** : `P1` → `P3` → `P2` → `P4` → `P5` → (`L6`/`L23`/`L24`) → `P6`.

---

## 3. Le total restant (chiffres)

| Bloc | Charge |
|---|---:|
| Plan correctif — les vagues W | **0 j** — **toutes fermées** (W0 → W10), les 9 transverses absorbés par L1/L2/L4 |
| Chaînages — L1 → L24 (**plafond brut** : non déduit de L0, des tranches 1 à 5 de L1, de L2 et de L7) | ≈ 116 j |
| Couverture d'audit — phase 10 | ≈ 15 j |
| **Total restant au 30/09/2026** | **≈ 131 j** |
| Hors charge de développement | **P0-08** (14 parcours à l'écran), la recette des neuf intégrations (tableau B), les décisions du tableau A |
| Déjà livré et prouvé (W0 → W10, chaînages L0 + L1 tr. 1 à 5 + L2 + L7, essaim QA) | ≈ 37 j |

Au 24/09 le total était de **≈ 169 j** ; il est passé à **≈ 139 j** le 28/09
(W4, W6, la chaîne de l'absence W9, W5, les deux défauts du registre, la fin de
W8, la première partie de W7). Les deux corrections qui restaient — `309`
(**M01-03** : écart de change au règlement et réévaluation de clôture) et `308`
(**`SAGE-01→03`** : l'import d'écritures en **une** transaction) — **ferment W7** :
**≈ 133 j**. Il n'y a **plus de reste** au titre du plan correctif ; le chiffre
affiché ici (**≈ 131 j**) retire les 2 j de W7 et **garde** les 116 j du plan des
chaînages **sans les déduire** de ce qui est livré : il est donc **majorant**, et
il le dit, plutôt que de fabriquer une précision qu'aucune mesure ne porte.
**W10 (≈ 2 j)** reste, comme avant, **hors plan** : elle vient d'un angle mort
(les appels de fonction), pas d'une ligne du plan.

**Ce que ces chiffres ne comptent pas** : les défauts que l'audit des 16 modules
restants révélera, les délais externes (les 14 documents djiboutiens,
l'expert-comptable, les pilotes), et la recette à l'écran (P0-08), qui n'est pas
une charge de développement mais un passage obligé.

---

## 4. Comment reprendre (la méthode, non négociable)

1. **Un défaut** = un test chiffré qui **échoue avant** le correctif, pour la
   bonne raison (le « rouge d'abord » se consigne) ;
2. **une migration** numérotée `NNN_<nom>.sql`, rejouable, **sans perte de
   données** — et un numéro se **constate** dans le dépôt, il ne se réserve pas
   (`257`, `258`, `259` ont été pris au moment de l'exécution de W6) ;
3. **le test branché dans `.github/workflows/ci.yml` dans le même commit** ;
3. **bis — si la migration change le schéma** (colonne, table, vue, valeur d'un
   `CHECK`) : **`npm run db:types` dans le même commit**. La CI régénère
   `src/types/database-generated.ts` depuis une base neuve et **refuse tout
   écart** ; c'est une **porte du même genre que `G5`**, et elle a parlé le 30/09
   (les 5 colonnes de la `312`, **15 lignes**) jusqu'à ce que `b3eac3b` les
   porte. Ne pas la contourner en relançant la CI : **régénérer et commiter** ;
4. **la ligne du registre** `ci/expected_failures.sql` retirée si le défaut y
   figurait (la CI échoue si un test corrigé y reste) ;
5. **les non-régressions** (`105`, `178`, `181`, `219`, `189` et les suites du
   module touché) rejouées, pas supposées ;
6. **le chiffre du tableau de bord** mis à jour, avec sa date.

**Et la leçon du 24/09, qui reste vraie** : le travail non commité n'existe pas.

### Les commandes de re-vérification (telles qu'exécutées pour W6)

```bash
# 1. Base neuve + migrations
docker run -d --name pg_w6b -e POSTGRES_PASSWORD=postgres -p 5459:5432 \
  -v "$PWD/app:/work" postgres:16
docker exec -w /work pg_w6b psql -U postgres -v ON_ERROR_STOP=1 -f sql/ci/00_supabase_stubs.sql
docker exec -w /work pg_w6b psql -U postgres -v ON_ERROR_STOP=1 -f sql/00_schema_dump.sql
cd app && DATABASE_URL=postgresql://postgres:postgres@localhost:5459/postgres node run-sql-migrations.mjs
#    puis les types générés — ils font partie du commit dès que le schéma change :
DATABASE_URL=postgresql://postgres:postgres@localhost:5459/postgres node scripts/generate-db-types.mjs
git diff --stat src/types/database-generated.ts   # doit être VIDE (c'est ce que la CI exige)

# 2. Les contrôles et les suites, dans l'ordre de la CI (voir .github/workflows/ci.yml)
docker exec pg_w6b psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /work/sql/ci/check_tenant_guard.sql
#    check_status_writes, check_trigger_reachability, check_composite_fks,
#    check_policy_duplicates, check_roles_opposables, check_anon_grants,
#    audit_registry_selftest, check_plpgsql (installer l'extension dans le conteneur)

# 3. Front et fonctions Edge
cd app
npx tsc -b --noEmit && npx oxlint --max-warnings=0
node scripts/check-i18n.mjs && node scripts/check-i18n-usage.mjs
npx vitest run                     # 1 513 (30/09)
npm run edge:test                  # 32 (Deno requis ; sinon : npx -y deno test …)
DATABASE_URL=… node scripts/check-written-columns.mjs   # 0 attendu
node scripts/check-unchecked-writes.mjs                 # 0 attendu
DATABASE_URL=… node scripts/check-rpc-contract.mjs       # 0 attendu (W10)

# 4. Les portes des chaînages (L2, 30/09) et l'essaim QA
node scripts/check-test-suites.mjs                       # G5 : « 0 suite non branchée »
docker exec pg_w6b psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /work/sql/ci/check_bt_grid.sql          # G1
docker exec pg_w6b psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /work/sql/ci/check_effects_contract.sql # G2
docker exec pg_w6b psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /work/sql/ci/check_chain_performance.sql # G6
# (G3 et G4 sont les scanners déjà listés ci-dessus : colonnes écrites, garde de société)

# 5. L'essaim QA — pile locale + application servie sur :5174 (jamais une URL distante)
cd app && npm run qa:seed -- --workers=4 && npm run qa:amorce \
  && npm run qa:run -- --workers=4 --viewports=all && npm run qa:validate -- --baseline
```

---

## 5. La mémoire du dépôt

| Où | Ce qu'on y trouve |
|---|---|
| **`AGENTS.md`** | l'état du projet, vague par vague, avec les chiffres et les liens de preuve — et le renvoi vers ce document |
| **ce document** | ce qui reste ouvert, par nature, avec les charges et les blocages |
| `doc/audit/RESTE-A-FAIRE-ET-PLAN-PHASES-2026-09-24.md` | le plan par phases (détail, critères de sortie, décisions) |
| `doc/audit/VAGUE-W6-2026-09-26.md` | la preuve de la vague W6 (mesures avant/après, « rouge d'abord », limites) |
| `doc/audit/VAGUE-W5-2026-09-27.md` | la preuve de la vague W5 (moteurs uniques : mesures avant/après, « rouge d'abord », limites dites) |
| `doc/audit/VAGUE-W7-W8-2026-09-28.md` | la preuve des deux défauts du registre fermés (CA non taxé dans la CA3, refacturation des temps : mesures avant/après, limites, et **ce que W7/W8 ne sont pas**) |
| `doc/audit/VAGUE-W8-2026-09-28.md` | la preuve de la **fin de W8** (production : nomenclature multi-niveaux, écarts chiffrés, date de l'OF ; projets : avancement pondéré, anti-cycle) — et la note de **numérotation 300+** |
| `doc/audit/VAGUE-W7-2026-09-28.md` | la preuve de **W7, entière** : analytique (`304`), FEC unique (`305`), devises (`306`), budgets (`307`), **import d'écritures en une transaction (`308`, `SAGE-01→03`)** et écart de change (`309`) — mesures d'entrée rouges, mesures de sortie vertes, limites dites |
| `doc/audit/VAGUE-L1-2026-09-29.md` · `VAGUE-L1-TRANCHE3-CYCLE-DU-LIEN-2026-09-30.md` · `INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md` | **L1** : les effets tracés (`310`, `311`), le **cycle de vie du lien** (`312`), la **chaîne achats et notes de frais** (`314`) — et la méthode d'inventaire, rejouable, avec les verdicts et les raisons des 99 fonctions transverses |
| `doc/audit/VAGUE-L2-PORTES-CI-2026-09-30.md` | **L2** : les **six portes** `G1` → `G6`, chacune avec ce qu'elle a vu **rouge** et les limites qu'elle ne voit **pas** |
| `doc/audit/VAGUE-L7-CONTRATS-DEFFET-2026-09-30.md` | **L7** : les contrats d'effet déclarés (`313`) — l'indicateur passe de 0 % à 100 % de maillons métier tracés **avec** contrat |
| `doc/audit/QA-ESSAIM-2026-09-29.md` | l'**essaim QA** : 335 écrans, quatre gabarits, deux sociétés, registre et rapport — et les onze points sur lesquels **le harnais lui-même** se trompait |
| `doc/audit/DECISION-D4-GENERATE-PDF-2026-09-30.md` | la **note d'aide à la décision `D-4`** (rebrancher ou supprimer `generate-pdf`) : ce qui est vrai aujourd'hui, ce que chaque option exige, ce qu'aucune ne change |
| `doc/audit/PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md` | ce qui viendra **après** les chaînages (`P1` → `P8`) : la preuve, l'explication et la sortie libre — **proposé**, avec son garde-fou d'entrée (§2.I) |
| `app/sql/ci/expected_failures.sql` | le registre des défauts prouvés — **VIDE depuis le 28/09/2026** ; un échec hors registre casse la CI |
