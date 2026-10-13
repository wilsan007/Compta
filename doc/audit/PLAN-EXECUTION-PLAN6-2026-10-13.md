# Plan d'exécution — corriger et finir le PLAN-6-PARTIES-PARALLELES-2026-10-05

> **Objet.** Plan d'exécution complet dérivé du
> [plan en 6 parties](PLAN-6-PARTIES-PARALLELES-2026-10-05.md) : d'abord
> **corriger** ce qui est prouvé cassé (Phase 0), puis **finir** chaque partie
> dans l'ordre de ses dépendances, jusqu'à la recette.
>
> **Règle de preuve.** Étiquette par ligne : **[MESURÉ]** = exécuté et constaté
> le 13/10/2026 ; **[CI]** = run GitHub (run ID) ; **[DOC]** = fichier de suivi,
> non re-testé. Rien n'est affirmé sans l'une des trois.
>
> **Méthode du dépôt** : rouge d'abord ; numéro par `migration:prendre` ; suite
> enrôlée dans `ci.yml` **dans le même commit** ; `db:types` si le schéma change ;
> preuve dans `PARTIE-<lettre>.md` ; **le travail non commité n'existe pas**.

---

## 0. État de départ mesuré (audit du 13/10/2026)

| Constat | Verdict |
|---|---|
| Batterie SQL locale (base neuve, procédure CI, 216 fichiers) | ✅ **216/216** (`check_plpgsql` vert après installation de l'extension, comme la CI) |
| Vitest · tsc · oxlint · build | ✅ **1 661 tests** · exit 0 · 0 warning · build + secrets du bundle OK |
| Types générés (`db:types`) | ✅ **373 tables, écart vide** |
| **CI `main` (schedule)** | 🔴 **rouge 5 nuits** (09/10 → 13/10) : DB (suite `400` T15), E2E (3/64), Security (gitleaks) — runs `37904949117`, `38036571597`, `38124132490`, `38224245276`, `38372460495` **[CI]** |
| PR **#14** (`integration/plan6-b` → `main`) | 🟠 ouverte depuis le 11/10, derniers runs **verts** — le remède au job DB |
| `npm run suivi:check` | 🟢 **réparé en Phase 0** (éraflait `280/198` vs `283/200`) **[MESURÉ]** |
| Travail non commité | 🟢 **réparé** : `seed.mjs`, suppression `530` (doublon identique de `780`) |
| Numérotation | 🟢 **réparée (v2)** : plage **`780-789` déclarée** + `inscrire`, `530` (doublon identique) supprimé — ⚠️ **leçon payée** : une 1ʳᵉ tentative (`780` → `457`) a **rougi** la CI (`450 T11`, run `38424071395`) : **le numéro est aussi un ORDRE** (voir 0.B3) |
| 3 worktrees avec du travail en vol | 🟢 **finis et committés** (§0.C1) |
| Dépôt | 🟢 `brag*/` ignoré |

**Causes racines des trois échecs `main` [CI]+[MESURÉ] :**

1. **DB** : sur `main`, la suite `400` filtre `LIKE 'chain_l1_%'`, capturant
   **aussi `chain_l16_%`** (accordées à `authenticated` par la `495`) ; le
   correctif (`80f7e48`) n'existe que sur `integration/plan6-b`.
2. **E2E** : le compte de test **n'est plus rattaché à aucune société** — les
   secrets sont configurés (61 tests s'authentifient) → **le plan, qui dit
   « secrets en attente », est périmé sur ce point**.
3. **Security** : gitleaks voit dans l'historique le jeton **anon démo Supabase**
   (`iss: supabase-demo`) de `amorce-chiffres.mjs:26` (branche `plan6/d-ecrans`)
   — reproduction locale : `leaks found: 1`.

---

## PHASE 0 — « Remettre une seule ligne » (intégration seule)

> Tant que `main` est rouge chaque nuit, **aucune régression n'est visible**.

| # | Tâche | État | Preuve |
|---|---|---|---|
| **0.A1** | Réparer le job DB de `main` | 🟠 **prêt** | correctif sur la branche ; **reste : fusionner la PR #14** (déploiement — décision) |
| **0.A2** | Réparer Security (gitleaks) | ✅ | allowlist **précise** (regex `supabase-demo`+`anon` seule) : **rouge avant** (`leaks found: 1`) → **vert après** (`no leaks found`) |
| **0.A3** | Rattacher le compte E2E à une société | ⬜ **hors dépôt** (console) | run `114727725953` : 3 failed / 61 passed |
| **0.B1** | Committer le travail en suspens | ✅ | voir §0.E |
| **0.B2** | Bloc de suivi (étape **0.9**) | ✅ | `--write` puis **`suivi:check` ✅** |
| **0.B3** | Numérotation `780` | ✅ **(v2)** | **Tentative 1 rouge, mesurée** : `780 → 457` a cassé la CI — suite `450` **T11 hors registre** (run `38424071395`) : la boucle de garde ne couvre que le registre **à son passage**, et en `457` les types des lots `475`→`758` n'existent pas encore — **le numéro est aussi un ORDRE**. **Correction** : plage **`780-789` par l'outil**, fichier remis en **`780`** (dernière position), `inscrire`, prise `457` retirée, `530` (doublon) supprimé ; `verifier` ✅ (0/303) ; preuve du bon ordre : `450` **OK** en batterie locale (`780` dernier) |
| **0.B4** | Ignorer `brag*/` | ✅ | `.gitignore` |
| **0.C1** | Finir les 3 lots en vol | ✅ | A3 `9b2771f`, C `62d22e0`, F `a80d377` |
| **0.D** | Gate : 3 schedules verts d'affilée | 🟡 locales vertes ; **CI après push** | — |

### 0.C1 — ce qui a été fini, avec mesure [MESURÉ]

| Worktree | État avant | Correctifs | État après |
|---|---|---|---|
| **`plan6/a3-moteur`** | lot `765` complet, non commité | aucun | `765` **6/6**, non-régression `764` **verte** (base dédiée `pg_wip_a3`) ; G5 **172/172** ; journal « lot 20 » déjà écrit → `9b2771f` |
| **`plan6-c-localisation`** | `396`/`397` non câblées (G5 ❌) ; **`397 T01` rouge** | **T01 = faux écart du TEST** : le motif brut `'digits'` comptait **195 fonctions** (dates, seuils, identifiants) et ne pouvait jamais passer ; prédicat **aligné sur le garde-fou** (`scanSql`) — le garde-fou mesure **SQL = 0** sur cette base | `396` **4/4**, `397` **4/4** ; suites adaptées `281` 8/8, `383` 6/6, `385` 6/6, `412` 8/8, `436` 9/9 ; plafond `sql` **10 → 0** ; câblées sous `plan6:c` (G5 **168/168**) → `62d22e0` |
| **`plan6-f-plateforme`** | `715` **cassée** (bloc T03 non fermé → `syntax error at or near DECLARE`), **sans `_audit_assert`** (G5 ❌), `714`/`715` non câblées **et absentes du registre** | `END $$;` restauré, orphelin retiré, verdict ajouté ; **T07→T12 écrits** pour tenir l'en-tête (déclencheur non-membre `23514`, unicité, **moteur alerte**, **livraison à l'abonné**, **idempotence journalière**, **cloisonnement**) ; `inscrire` (R2) | `714` **25/25**, `715` **15 → 21/21** (rouge-avant relevé en chemin : `vat_amount` → `vat_total`) ; câblées sous `plan6:f` (G5 **166/166**) → `a80d377` |

> **Leçon de chantier** : les rôles PostgreSQL (`anon`, `authenticated`) sont
> **cluster-wide** — trois builds parallèles sur un même conteneur se marchent
> dessus. Chaque worktree WIP a désormais sa propre instance.

### 0.E — les commits de la Phase 0 (main = `integration/plan6-b`)

| Commit | Contenu |
|---|---|
| gitleaks | `.gitleaks.toml` — allowlist datée et justifiée |
| ménage | `.gitignore` (`brag*/`), plage `780-789` + `780` en **dernière** position (après l'échec de la tentative `457`), suppression du doublon `530`, `SUIVI-CHANTIERS.md` régénéré |
| qa | `app/scripts/qa/seed.mjs` — clic sur le libellé exact « Créer mon entreprise » |
| plan | **ce document** |

---

## PHASE 1 — Cadence de gouvernance (continue)

1. **R1-R8 tenus** : une partie = une session = un worktree = une branche ;
   numéro par `prendre` ; hors territoire = demande écrite dans **son**
   `PARTIE-<lettre>.md` (R3) ; `SUIVI-CHANTIERS.md`/`AGENTS.md` **uniquement**
   par l'intégration (R4).
2. **Lots courts** (1-3 j) + **fusion par l'intégration seule** ; batterie
   complète après chaque fusion (R8), puis resynchronisation des parties.
3. **R7 + module de la semaine** : C.1 réécrit des fonctions d'écriture de tous
   les modules → C annonce son module, **B et E s'effacent cette semaine-là** ;
   avant tout `CREATE OR REPLACE` : `git grep -l "FUNCTION <nom>" $(git
   branch --list 'plan6/*' …)`.
4. **Portes rejouées à chaque fusion** (commandes exécutées le 13/10) : base
   neuve (stubs + `00_schema_dump` + migrations) → les 216 fichiers de `ci.yml`
   dans l'ordre → `db:types` (écart vide) → `tsc` · `oxlint` · i18n · G5 ·
   `suivi:check` · `check-embeds` (PostgREST) · `check-written-columns` ·
   `check-rpc-contract` · `check-screen-writes`.

---

## PHASE 2 — Fin des six parties (parallèles, territoires disjoints)

### A3 — moteur L16 → L24 (le plus gros) · `493-499`, `750-759`, `760-769`, `770-779`

État : A3.1 ✅ · A3.2 🟡 **20 maillons** · L23-b ✅ · P1 ✅. **Ordre de reprise
(dépendances respectées)** : ① L20-tranche 2 **régénération en cascade** (le
gros, débloque L21) ② L18-tranche 2 (fabrication à la commande) ③ L19-reporting
(définitions uniques I-08) ④ reste L16 (stock, production, RH, projets) ⑤
INV-07 (lettrage — vérifier si `758` l'a livré) ⑥ **L21** (dérivés du lettrage)
⑦ **L22** (moteur de règles I-07 + simulateur I-04 — bloqué par L5/L11) ⑧
L23-c + L24 (I-09, I-11, I-12) ⑨ dettes : **`419` sans suite `_tests`** (à
couvrir), `421` libre ⑩ A3.4 : P3 → P2 → P4 → P5 → P7 → P8 → P6 (≈ 25 j − P1).

### A1 / A2 — preuve et écrans (quasi clos)

A1 : reste **INV-10** (colonne numérique `dsn_declarations` → **B**), **INV-12**
(marge projet → **E/F**), **INV-07** (→ A3) ; dès réception : mesurer, publier,
**clore A1**. A2 : toutes tâches ✅ ; fermer le constat **`purchase_orders` hors
registre** `chain_document_types`.

### B — 62 règles d'état + paie FR · `500-559` · **≈ 3 j** [DOC]

① clôture B.2 (les types `529` sont **déjà régénérés** — écart vide mesuré) ②
**B.3** : seuil **hebdomadaire** des heures sup + **exonération 7 500 €** (le
point ouvert W5 « `calculate_overtime_pay` sans appelant » se referme ici) ③
**B.4** : arrêt maladie (carence, maintien) ④ **INV-10** ⑤ corriger le
référentiel : **R-006 vise `deliveries`** (→ `delivery_notes`), **R-062 déjà
faite**. Déploiement bloqué par **D-G** (expert-comptable), pas l'écriture.

### C — localisation Djibouti · `370-399`, `600-649` · **≈ 74 j — chemin critique**

⓪ **trancher les réserves C.2** : lignes 392/393 du barème ITS (au-delà de
2 004 999 DJF) — *retirer (trou) ou garder (invention)*, décision du chef de
produit ① ✅ fini en Phase 0 : `396`/`397` ② **C.1 neutralité ≈ 48 j**, module
par module (annonce obligatoire) ③ **C.3 pack ≈ 26 j — bloqué** (D-11, 14
documents, expert) ④ C.4 pilote. `66_critical_rls_isolation_fix.sql` **à ne pas
reprendre** (mesuré : 0 ligne en prod).

### D — écrans, recette · `355-369` · **≈ 25 j + recette** — tout ⬜ [DOC]

**D.1** dialogue de confirmation (100 fichiers, 1 lot/jour/module, **livrer en
premier**) → **D.3** alignement 10 écrans (**re-mesurer** : patch figé sur
`f5cda2f`) → **D.2** typer 80 états → **D.4** 159 lectures non couvertes →
**D.5** Playwright sur chaque PR (**secrets OK — débloquée**, reste 0.A3) +
4 parcours qui lisent un chiffre → **D.8** contraste (**décision D-7**) →
**D.7** rejeu sur copie de production (G7 sous le vrai propriétaire) →
**D.6 recette P0-08** (14 parcours, 2 sociétés, 4 gabarits — **présence de
l'utilisateur**).

### E — opérations · `650-699` · charge inconnue

① **E.1 recomptage des 32 chantiers** (faire/reporter/écarter par chantier —
**semaine 1**, sans lui aucune date) ② E.2 → E.3 → E.4 (sous-OF
`parent_mo_id`) → E.5 (**12 tables coquilles : brancher ou supprimer**) ③
**INV-12 : choisir et figer UNE formule de marge projet** (avec F).

### F — plateforme · `700-749` · charge inconnue

① **F.1 recomptage** (semaine 1) ② **F.2 auth forte** ✅ **déjà livrée**
(`700`) ③ F.3 `generate-pdf` voie A (**D-4**) ④ F.4 → F.5 → F.6 (**`714`/`715`
finis en Phase 0**) → F.7 → F.8 (**25 coquilles**).

---

## PHASE 3 — Décisions **de l'utilisateur** (ce qui ne sort pas du dépôt)

| # | Décision / fourniture | Bloque | Travail parallèle possible |
|---|---|---|---|
| **PR #14** | **Fusionner vers `main` (= déploiement)** | la sortie de `main` du rouge | toutes les phases 2 |
| **0.A3** | rattacher le compte E2E à une société (console) | les 3 échecs E2E nocturnes | — |
| **D-G** | expert-comptable + bulletins d'or | déploiement paie, pack DJ, certificat | écrire B.3/B.4 |
| **D-11** + 14 documents | périmètre localisation | **C.3** | **C.1 libre dès maintenant** |
| **D-4** | convertisseur + `GOTENBERG_URL` | F.3 | — |
| **D-5** | DPA + 2 fonctions sans garde (`parse-bank-statement`, `ai-import-mapping`) | conformité OCR | — |
| **D-7** | contraste (7 couples < 4,5:1) | D.8 | — |
| **Réserves C.2** | lignes 392/393 du barème ITS | finalisation C.2 | — |
| **INV-12** | formule unique de marge projet | A1 clos + E/F | — |
| **5 questions P1→P8** | signataire, destinataire, données du prospect, NF-525, durée de mesure | **P2→P8** | P1 déjà livré |
| Comptes | `sb_secret_…`, 9 intégrations, pilotes, copie de production | recette réelle | — |

---

## PHASE 4 — Recette & livraison

1. **Gate « ligne verte »** : 3 schedules consécutifs + `suivi:check` ✅ +
   registres **vides ou avec raison datée**.
2. **D.6 / P0-08** : 14 parcours à l'écran, essaim QA (`qa:seed → qa:amorce →
   qa:run → qa:validate --baseline`), correction des écarts bloquants,
   re-notation des modules.
3. **D.7** : rejeu sur copie de production (G7 sous le **vrai** propriétaire) +
   relecture des paramètres globaux et de `banks` (altérés avant fermeture W1,
   jamais relus).
4. **Fermeture documentaire** : `PARTIE-*.md` → `SUIVI-CHANTIERS.md` →
   `RESTE-OUVERT` → preuve dans `doc/audit/`.

## PHASE 5 — Après le plan : P2 → P8

**P1 ✅ fait** (écran `/system/certificat` + `770`). Ordre : **P3** (audit de
reprise) → **P2** (banc sur données du prospect) → **P4** → **P5** →
(`L6`/`L23`/`L24`) → **P6** → **P7**, **P8**. **Garde-fou** : rien avant les
épreuves **L3** et l'indice **L4** — ce sont des lecteurs de preuve.

---

## Définition de fin globale (critères mesurables)

- [ ] `main` : **3 schedules verts d'affilée** (DB + E2E + Security) ;
- [ ] `suivi:check` ✅ · `git status` propre · 0 travail non commité dans les
      worktrees ;
- [ ] batterie **216+ fichiers verts** sur base neuve · `db:types` écart vide ·
      G5 toutes suites branchées ;
- [ ] les 6 `PARTIE-*.md` sans tâche ⬜ (E.1/F.1 avec verdicts écrits) ;
- [ ] registres vides · `419` couvert · `457` inscrite ;
- [ ] **P0-08 passé** (D.6) + D.7 sur copie de production ;
- [ ] D-4, D-5, D-7, D-11, D-G, réserves C.2, INV-12, questions P1→P8
      **tranchés et datés**.

**Chemin critique en une phrase** : Phase 0 (≈ 3 j) → en parallèle **C.1 (48 j)
+ D.1→D.5 (≈ 18 j) + A3 (L20 d'abord) + E.1/F.1 (semaine 1)** → **B.3/B.4
(3 j)** → **recette D.6/D.7** → **C.3 dès réception des textes (26 j)** ; le
reste (L21, L22, P2→P8) est **ordonné par dépendances** ci-dessus.

