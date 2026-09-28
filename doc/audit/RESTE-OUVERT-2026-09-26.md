# Ce qui reste ouvert — état au 26 septembre 2026 (mises à jour : 27/09 W5, W10 ; 28/09 W7 partielle, **W8 fermée**)

> **Objet.** Une seule page, à jour, de **tout ce qui n'est pas fermé** après la
> vague W6 : ce qui attend une décision, ce qui vit hors du dépôt, ce qui reste
> à coder — et, depuis le 28/09, **un registre de CI vide** : les deux échecs qui
> y étaient inscrits (`231 M-17-01`, `245 T08`) sont fermés.
> ⚠️ **Numérotation** : une session parallèle écrit `270` → `272` ; cette
> session-ci prend **`300`+** (`300` CA3, `301` refacturation, `302` production,
> `303` projets).
> **Règle de lecture.** `MESURÉ` = obtenu par exécution ; `PROPOSÉ` = charge
> estimée, à valider. Ce document ne remplace pas les plans : il les **résume**.
> **Sources.** [Plan correctif complet](PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md),
> [Reste-à-faire et plan par phases](RESTE-A-FAIRE-ET-PLAN-PHASES-2026-09-24.md),
> [Référentiel des chaînages](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md),
> [Couverture d'audit par module](COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md), et
> les preuves de vague ([W0](PREUVES-W0-2026-09-24.md),
> [W1](VAGUE-W1-ISO02-04-PERM01-2026-09-24.md), [W2/W3](VAGUE-W2-W3-2026-09-24.md),
> [W4](VAGUE-W4-2026-09-26.md), [W6](VAGUE-W6-2026-09-26.md),
> [W9](VAGUE-W9-2026-09-26.md), [W5](VAGUE-W5-2026-09-27.md),
> [W10](VAGUE-W10-2026-09-27.md), [W7/W8 partielles](VAGUE-W7-W8-2026-09-28.md)).
> **Mémoire.** Ce document est référencé par `AGENTS.md` (section « Reste
> ouvert ») : c'est le point d'entrée pour reprendre le travail.

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
| **W7 (partie 1)** | **`ANA-01/02`** (`304` : les deux déclencheurs analytiques étaient des placebos, la section circule de la **ligne de document** vers la ligne d'écriture) · **`ANA-03`** (la balance analytique est **bornée à l'exercice**) · **`FEC-01`** (`305` : la 2ᵉ implémentation du FEC, 9 colonnes sur 18, est supprimée) | [W7](VAGUE-W7-2026-09-28.md) |

État mesuré sur base neuve : **243 migrations, 0 erreur** (dont `270`→`272` d'une
session parallèle) ; **82/82** contrôles et suites rejoués sur la base migrée
(8 contrôles + 74 suites, dont `302` 8/8 et `303` 6/6) ; front `tsc` 0,
`oxlint` 0, **Vitest 1 502**, **32 tests Edge Deno** ; les **trois** scanners de
code (`check-written-columns`, `check-unchecked-writes`, `check-rpc-contract`) à
**0**, baselines vides.

---

## 2. Ce qui reste ouvert, par nature

### A. Ce qui attend une décision (elle n'appartient pas au dépôt)

| ID | Sujet | Où c'est dit |
|---|---|---|
| **D-4** | `generate-pdf` : **défaut appliqué** le 26/09 (HTML client refusé, valeurs échappées, **retirée du déploiement**). Reste à trancher : la rebrancher derrière un Gotenberg durci, ou la supprimer | `RESTE-A-FAIRE` §3.1 |
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
| **Gotenberg** | décision `D-4` | HTML client refusé, valeurs échappées |
| **Sentry** | `VITE_SENTRY_DSN` | code prêt (ErrorBoundary) |

### C. Le plan correctif : les vagues restantes (PROPOSÉ)

| Vague | Défauts | Charge | Contenu |
|---|---:|---:|---|
| **W7 — Comptabilité avancée** | 10 (3 🔴) | 6 j | ✅ **le CA non taxé entre dans la CA3** (`245 T08`, `300`) · ✅ **analytique** (`304` : les deux déclencheurs cessent d'être des placebos, la section **circule** du document vers l'écriture, la balance de l'écran est **bornée à l'exercice**) · ✅ **un seul FEC** (`305`) — restent `M01-01→03` le taux de change **appliqué** aux écritures en devise, `BUD-01→04` réalisé non borné à l'exercice et engagements jamais libérés, `SAGE-01→03` import en brouillon, soldes écrasés, non transactionnel ([preuve](VAGUE-W7-2026-09-28.md)) |
| **W8 — Production et projets** ✅ **fermée (302, 303, 28/09)** | 0 (était 5) | 3 j | ✅ la **refacturation des temps** existe (`231 M-17-01` fermé le 28/09 par la `301`) ; `302` : nomenclature **multi-niveaux** explosée par **une** fonction qui sert aussi au coût et aux sorties, quantité produite **déclarée** respectée, rebuts impossibles **refusés**, **écart de coût** chiffré (`cost_variance`), écriture datée de l'OF ; `303` : avancement **pondéré** par une seule règle (parent et projet), **anti-cycle** des tâches ([preuves](VAGUE-W8-2026-09-28.md)) |
| **T1 → T9** | 9 scénarios transverses | 5 j | commande → livraison → facture → encaissement → lettrage → clôture ; achat → réception → qualité → facture → paiement ; temps → projet → facture → marge ; **absence → paie → DSN → coût projet** (fait, `266`) ; caisse → clôture → comptabilité → TVA ; immobilisation → amortissement → cession ; budget → engagement → réalisé ; import → lettrage → états ; **contre-épreuve de falsification** |
| | **Total** | **≈ 14 j** | |

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

**Charge : ≈ 116 j** (détail : `RESTE-A-FAIRE` §3.3 et
`PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md`). Le socle `L0` (`252`) est fait,
et W9 a livré la chaîne de l'absence de bout en bout.

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

### F. Les deux échecs encore inscrits au registre de la CI

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

## 3. Le total restant (chiffres)

| Bloc | Charge |
|---|---:|
| Plan correctif — phases 5 et 6 (W7 : 10 défauts + les 9 transverses) | ≈ 6 j |
| Chaînages — phases 7 à 9 (L1 → L24) | ≈ 116 j |
| Couverture d'audit — phase 10 | ≈ 15 j |
| **Total restant au 28/09/2026** | **≈ 139 j** |
| Déjà livré et prouvé (W0 → W10 — dont W5 `260`, W10 `267`, **W8 fermée** `302`/`303`, **W7 analytique et FEC** `304`/`305` — et chaînages L0) | ≈ 26,5 j |

Au 24/09 le total était de ≈ 169 j ; W4 (4 j), W6 (3,5 j), la chaîne de l'absence
(W9, 4 j), W5 (2 j), les deux défauts du registre fermés le 28/09 — le `M-17-01`
de la refacturation des temps (**W8**, `301`) et le `T08` du CA non taxé dans la
CA3 (**W7**, `300`), ≈ 2 j à eux deux — la **fin de W8** (production et projets,
`302`/`303`, ≈ 2 j) et la **première partie de W7** (analytique et FEC,
`304`/`305`, ≈ 2 j) l'amènent à **≈ 139 j** aujourd'hui.
**W10 (≈ 2 j)** s'ajoute aux livraisons sans réduire ce total : elle était **hors
plan**, découverte par un angle mort (les appels de fonction), pas retirée du
plan. **W7 reste ouverte** : 10 défauts (`M01`, `BUD`, `SAGE`).

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

# 2. Les contrôles et les suites, dans l'ordre de la CI (voir .github/workflows/ci.yml)
docker exec pg_w6b psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /work/sql/ci/check_tenant_guard.sql
#    check_status_writes, check_trigger_reachability, check_composite_fks,
#    check_policy_duplicates, check_roles_opposables, check_anon_grants,
#    audit_registry_selftest, check_plpgsql (installer l'extension dans le conteneur)

# 3. Front et fonctions Edge
cd app
npx tsc -b --noEmit && npx oxlint --max-warnings=0
node scripts/check-i18n.mjs && node scripts/check-i18n-usage.mjs
npx vitest run                     # 1 488
npm run edge:test                  # 32 (Deno requis ; sinon : npx -y deno test …)
DATABASE_URL=… node scripts/check-written-columns.mjs   # 0 attendu
node scripts/check-unchecked-writes.mjs                 # 0 attendu
DATABASE_URL=… node scripts/check-rpc-contract.mjs       # 0 attendu (W10)
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
| `doc/audit/VAGUE-W7-2026-09-28.md` | la preuve de la **première partie de W7** (analytique : la section circule des documents vers les écritures, balance bornée à l'exercice ; FEC : une seule implémentation) |
| `app/sql/ci/expected_failures.sql` | le registre des défauts prouvés — **VIDE depuis le 28/09/2026** ; un échec hors registre casse la CI |
