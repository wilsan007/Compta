# Ce qui reste ouvert — état au 26 septembre 2026

> **Objet.** Une seule page, à jour, de **tout ce qui n'est pas fermé** après la
> vague W6 : ce qui attend une décision, ce qui vit hors du dépôt, ce qui reste
> à coder, et les deux échecs encore inscrits au registre de la CI.
> **Règle de lecture.** `MESURÉ` = obtenu par exécution ; `PROPOSÉ` = charge
> estimée, à valider. Ce document ne remplace pas les plans : il les **résume**.
> **Sources.** [Plan correctif complet](PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md),
> [Reste-à-faire et plan par phases](RESTE-A-FAIRE-ET-PLAN-PHASES-2026-09-24.md),
> [Référentiel des chaînages](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md),
> [Couverture d'audit par module](COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md), et
> les preuves de vague ([W0](PREUVES-W0-2026-09-24.md),
> [W1](VAGUE-W1-ISO02-04-PERM01-2026-09-24.md), [W2/W3](VAGUE-W2-W3-2026-09-24.md),
> [W4](VAGUE-W4-2026-09-26.md), [W6](VAGUE-W6-2026-09-26.md),
> [W9](VAGUE-W9-2026-09-26.md)).
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

État mesuré sur base neuve : **234 migrations, 0 erreur** ; **66/66 suites**,
**8/8 contrôles** (dont `check_plpgsql` : 0 erreur) ; front `tsc` 0, `oxlint` 0,
parité i18n fr/en/ar, **Vitest 1 488**, **32 tests Edge Deno**, plafond de code
mort **66/66**.

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
| **W5 — Un seul moteur par grandeur** | 8 (1 🔴) | 2 j | deux moteurs d'amortissement (`generate_depreciation_entry` concurrent de l'écran) ; reste des heures supplémentaires |
| **W7 — Comptabilité avancée** | 15 (4 🔴) | 6 j | M01-01→03 le taux de change est saisi… et **jamais appliqué** ; ANA-01→03 analytique ; BUD-01→04 réalisé non borné à l'exercice ; SAGE-01→03 import équilibré et transactionnel ; FEC-01 **une 2ᵉ implémentation du FEC** à 9 colonnes sur 18, à supprimer |
| **W8 — Production et projets** | 6 (1 🔴) | 3 j | PROD-01→03 nomenclature à **un seul niveau**, ni rebuts ni écarts, écriture datée du jour de clôture ; PROJ-01→03 la **refacturation des temps n'existe pas** (c'est le `M-17-01` encore rouge au registre) |
| **T1 → T9** | 9 scénarios transverses | 5 j | commande → livraison → facture → encaissement → lettrage → clôture ; achat → réception → qualité → facture → paiement ; temps → projet → facture → marge ; **absence → paie → DSN → coût projet** (fait, `266`) ; caisse → clôture → comptabilité → TVA ; immobilisation → amortissement → cession ; budget → engagement → réalisé ; import → lettrage → états ; **contre-épreuve de falsification** |
| | **Total** | **≈ 16 j** | |

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

`app/sql/ci/expected_failures.sql` porte **deux lignes** — et la CI **échoue** si
l'un de ces tests se met à passer : c'est le rappel qui oblige à retirer la ligne
dans le commit du correctif.

| Fichier | Test | Le défaut, en une phrase | Vague qui le ferme |
|---|---|---|---|
| `231` | `M-17-01` | les heures facturables n'atteignent aucune facture (`create_billable_line_on_timesheet_stop` ne crée qu'une notification) | **W8** |
| `245` | `T08` | le chiffre d'affaires **non taxé** (exonéré, export, livraison intracommunautaire) n'entre pas dans le CA déclaré : la base de la CA3 est reconstituée depuis la TVA | **W7** |

### G. Ce que W6 laisse explicitement non fermé

* **Cinq parcours Playwright** : dépôt électronique, synchronisation bancaire,
  demande de signature, vérification SIRET et IBAN — ils exigent une application
  servie avec un jeu de données (phase 10).
* **La recette réseau** des neuf intégrations (tableau B).
* **La décision `D-4`** (tableau A).

---

## 3. Le total restant (chiffres)

| Bloc | Charge |
|---|---:|
| Plan correctif — phases 5 et 6 (W5, W7, W8 + les 9 transverses) | ≈ 16 j |
| Chaînages — phases 7 à 9 (L1 → L24) | ≈ 116 j |
| Couverture d'audit — phase 10 | ≈ 15 j |
| **Total restant au 26/09/2026** | **≈ 147 j** |
| Déjà livré et prouvé (W0 → W3, W4, W6, W9, chaînages L0) | ≈ 18,5 j |

Au 24/09 le total était de ≈ 169 j ; W4 (4 j) et W6 (3,5 j) en sont sortis, ainsi
que la chaîne de l'absence (W9, 4 j) — d'où **≈ 147 j** aujourd'hui.

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
```

---

## 5. La mémoire du dépôt

| Où | Ce qu'on y trouve |
|---|---|
| **`AGENTS.md`** | l'état du projet, vague par vague, avec les chiffres et les liens de preuve — et le renvoi vers ce document |
| **ce document** | ce qui reste ouvert, par nature, avec les charges et les blocages |
| `doc/audit/RESTE-A-FAIRE-ET-PLAN-PHASES-2026-09-24.md` | le plan par phases (détail, critères de sortie, décisions) |
| `doc/audit/VAGUE-W6-2026-09-26.md` | la preuve de la vague W6 (mesures avant/après, « rouge d'abord », limites) |
| `app/sql/ci/expected_failures.sql` | les deux défauts encore rouges, avec leur raison |
