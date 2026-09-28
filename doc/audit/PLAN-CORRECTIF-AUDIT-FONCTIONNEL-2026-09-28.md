# Plan correctif — audit fonctionnel exécuté du 28/09/2026

> Source : [`AUDIT-FONCTIONNEL-EXECUTE-2026-09-28.md`](AUDIT-FONCTIONNEL-EXECUTE-2026-09-28.md)
> (14 critiques C1–C14, 13 majeurs M1–M13, mineurs). Harnais : [`harnais-audit-2026-09-28/`](harnais-audit-2026-09-28/).
> Charge totale estimée : **≈ 27 j** (hors validation de la grille de paie par l'expert-comptable).

## 0. Règles du plan

1. **Méthode du projet, inchangée** : un défaut = un test **rouge avant**, puis vert ; migration
   **constatée** (268 et 269 sont pris : prendre le premier numéro libre *au moment* du commit) ;
   câblage CI et preuve **dans le même commit**.
2. **Nouvelle règle, tirée de l'audit** : un correctif est prouvé **par le chemin de l'écran**
   (fonction de requête appelée avec la charge utile de l'écran, sous RLS réelle), pas seulement
   par une suite SQL qui insère en base. D'où la vague **X0** en premier.
3. **La sécurité passe avant tout le reste, en production aussi** : C1 et C2 sont exploitables
   aujourd'hui sur le cloud par un visiteur **non connecté** (vague **X1-urgent**, le jour même).
4. Chaque vague se termine par : rejeu du harnais (scénarios s1–s13 concernés verts), batterie
   SQL complète, `tsc` 0, `oxlint` 0, Vitest, et mise à jour de la note du module.

## 1. Vue d'ensemble

| Vague | Contenu | Défauts | Charge | Dépend de |
|---|---|---|---:|---|
| **X1-urgent** | Fermer l'écriture anonyme et globale | C1, C2 | 0,5 j | — |
| **X0** | Le chemin écran entre en CI | (outillage) | 2 j | — |
| **X1** | Droits : ce qu'un lecteur ne doit pas pouvoir faire | C3, M8, M9, M12 | 2 j | X0 |
| **X2** | Comptabilité : valider, créer, exporter | C4, C14, M1 | 4 j | X0, décision D-A, D-C |
| **X3** | Paie : un lot, un moteur, une grille juste | C5, C6, C7, H10 | 4 j + expert | X0, décision D-G |
| **X4** | Stock et logistique : des documents avec des lignes | C8, C9, C10, M6 | 6 j | X0, décision D-B |
| **X5** | Production, caisse, immobilisations | C11, C12, C13, M7 | 3,5 j | X4, décision D-D, D-E |
| **X6** | Trésorerie et tableaux de bord : une seule vérité | M3, M4, M5 | 3 j | X2, décision D-F |
| **X7** | Données de base, écrans, localisation | M2, M10, M11, M13, mineurs | 1,5 j | — |
| **X8** | Contrôles durables et recette | — | 1 j | tout |
| | **Total** | | **≈ 27 j** | |

Ordre conseillé : **X1-urgent → X0 → X1 → X7** (rapides, débloquent la saisie courante)
→ **X2 → X3 → X4 → X5 → X6 → X8**.

### Découpage en trois parties (28/09/2026)

| Partie | Vagues | Thème | Charge | Décisions à obtenir avant | État |
|---|---|---|---:|---|---|
| **1** | X1-urgent, X0, X1, X7 | Sécurité, outillage « chemin de l'écran », droits, écrans et données de base | ≈ 6 j | aucune (D-11 partielle) | ✅ **faite le 28/09** — [preuve](VAGUE-X1U-X0-X1-X7-2026-09-28.md) |
| **2** | X2, X3, X6 | Comptabilité (validation, créations, FEC), paie, trésorerie et tableaux de bord | ≈ 11 j + expert | D-A, D-C, D-G, D-F **tranchées le 28/09** (§ 2) | ✅ **faite le 28/09** — X2 ([preuve](VAGUE-X2-2026-09-28.md), 273, 274), X3 ([preuve](VAGUE-X3-2026-09-28.md), 275, 276 — production de la grille : signature de l'expert en attente), X6 ([preuve](VAGUE-X6-2026-09-28.md), 277, 278) |
| **3** | X4, X5, X8 | Stock et logistique, production / caisse / immobilisations, contrôles durables et recette | ≈ 10,5 j | D-B, D-D, D-E **tranchées le 28/09** (§ 2) | ✅ **faite le 28/09** — [preuve](VAGUE-X4-X5-X8-2026-09-28.md) (280, 281) ; registre du chemin de l'écran **vide** ; reste la re-notation des modules (recette) |

Pourquoi ce découpage : la partie 1 n'attend **aucune** décision et ferme ce qui est
exploitable aujourd'hui (anonyme, lecteur) ; elle pose aussi l'outil qui prouve les deux
autres (X0). La partie 2 regroupe ce qui touche **le grand livre** (X6 dépend de X2) ; la
partie 3 regroupe **les flux physiques** (X5 dépend de X4) et se termine par X8, qui
suppose tout le reste. Chaque défaut encore ouvert des parties 2 et 3 est **inscrit au
registre** `app/src/__screen__/expected_failures.json`, avec sa vague : le commit qui le
corrige doit retirer sa ligne.

---

## X1-urgent — fermer l'écriture anonyme (0,5 j, aujourd'hui)

| Défaut | Correctif | Rouge avant |
|---|---|---|
| **C1** `webhook_event_catalog` écrivable par tous | Remplacer `webhook_event_catalog_all` par `SELECT` pour `authenticated` ; écriture réservée à `service_role` | PATCH anonyme → 200 attendu **refusé** |
| **C2** paramètres légaux globaux écrivables | Scinder `payroll_legal_params_all` : `SELECT` sur `tenant_id IS NULL OR = current_tenant_id()` ; `INSERT/UPDATE/DELETE` **uniquement** sur `tenant_id = current_tenant_id()` **et** `can_perform('payroll_settings.update')` ; lignes globales réservées à `service_role` | PATCH anonyme et lecteur du SMIC global → refusés |
| Cause racine | `REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon` + `ALTER DEFAULT PRIVILEGES … REVOKE … FROM anon` | 61 tables écrivables par `anon` → 0 |

- **Contrôle CI** : étendre `ci/check_anon_grants.sql` aux **tables** (aujourd'hui fonctions seulement) ;
  nouveau `ci/check_global_rows_writable.sql` : aucune politique d'écriture ne peut contenir
  `IS NULL` sur `tenant_id` ni `USING (true)` hors `service_role`.
- **Production** : après déploiement, **vérifier que les valeurs globales n'ont pas été altérées**
  (`payroll_legal_parameters` où `tenant_id IS NULL` — SMIC_H 11,88, SMIC_M 1 801,80,
  MAJORATION_HEURES_SUP 1,25, PMSS 3 925… ; `webhook_event_catalog.is_active`) et consulter les
  journaux PostgREST pour des PATCH anonymes antérieurs.

## X0 — le chemin écran entre en CI (2 j)

Rendre permanent ce que l'audit a monté à la main.

1. **Job CI `screen-path`** : conteneur Postgres (déjà là) + `postgrest/postgrest` avec
   `PGRST_JWT_SECRET` + la passerelle `gateway.mjs` (déplacée dans `app/scripts/audit/`) + comptes
   créés par `create_tenant_for_current_user` (admin, comptable, lecteur, 2ᵉ société).
2. **Scénarios s1–s13** déplacés dans `app/src/__screen__/*.screen.ts`, config Vitest dédiée
   (`vitest.screen.config.ts`, sans le mock de `src/test/setup.ts`).
3. **Registre d'échecs attendus** (même contrat que `ci/expected_failures.sql`) : chaque assertion
   rouge aujourd'hui y est inscrite avec son identifiant (C4, C8…) ; la CI échoue si une assertion
   inscrite passe (la ligne doit partir dans le commit du correctif).
4. **`check-screen-writes.mjs`** (issu de `screen-writes.mjs`) : suit l'objet littéral **ou la
   variable** de l'écran jusqu'au `.insert/.update` de la fonction de requête. Baseline gelée à
   **62** (6 fonctions : comptes de tiers 46, journaux 8, immobilisations 3, compte à la volée 2,
   sections analytiques 2, lot de paie 1 — le `[field]` calculé est exclu), qui ne peut que baisser.
5. **`check-viewer-writes`** (issu de `viewer-sweep.cjs`) : liste publiée des tables qu'un lecteur
   peut modifier ; plafond gelé à 16, doit tomber à la liste acceptée par D-6.

Critère de sortie : le job tourne en CI, **tous les défauts de l'audit y sont rouges et inscrits**.

## X1 — droits (2 j)

| Défaut | Correctif | Preuve |
|---|---|---|
| **C3** lecteur → `document_number_sequences` (facturation bloquée) | `REVOKE INSERT, UPDATE, DELETE` à `authenticated` ; seules les fonctions `SECURITY DEFINER` de numérotation écrivent. Même traitement pour les tables **alimentées uniquement par déclencheur** : `stock_quantities`, `stock_valuation_layers`, `journal_posting_sequences` | lecteur PATCH → refusé ; validation de facture toujours OK |
| **M8** 16 tables modifiables par un lecteur | Porter sous `can_perform` : `fiscal_periods`, `journals`, `warehouses`, `boms`, `bom_lines`, `manufacturing_orders`, `goods_receipts`, `pos_terminals`, `pos_sessions`, `pos_tickets`, `bank_statement_imports`. Ajouter `can_perform` dans `post_journal_entry` (création), `calculate_payslip` (H10), ouverture de session de caisse | `check-viewer-writes` : 16 → liste D-6 |
| **M9** approbation d'achat par son auteur, sans trace | `purchase_invoices.created_by DEFAULT auth.uid()` ; déclencheur qui pose `approved_by = auth.uid()` et refuse `approved_by = created_by` si `enforce_segregation` | P03 rouge → vert |
| **M12** politiques héritées | `DROP POLICY tenant_isolated_analytic_dist_lines` ; `project_docs` réécrite sur `current_tenant_id()` ; nettoyer les lignes `tenant_id IS NULL` d'`analytic_distribution_lines` | insertion « sans société » refusée |

Contrôle CI : `check_policy_duplicates` étendu aux politiques qui ne mentionnent **pas**
`current_tenant_id()` (motif `LIMIT 1`, GUC `app.tenant_id`).

## X2 — comptabilité (4 j)

### C4 — valider une écriture saisie (1,5 j) — *décision D-A*
- RPC **`validate_journal_entries(p_ids uuid[])`** : `can_perform('journal_entry.post')`, contrôle
  d'équilibre, exercice/période ouverts, numérotation définitive, écrit `validated_by`/`validated_at`
  (ce qui alimente aussi `ValidDate` du FEC et la séparation des tâches H06), rend un verdict par écriture.
- Boutons **« Valider »** (unitaire) dans `JournalEntriesPage` et `JournalSaisiePage`, **« Valider la
  sélection »** dans `BrouillardPage`.
- `createSaisieEntry` passe par `post_journal_entry` (aujourd'hui en-tête puis lignes : non atomique).
- La clôture de période/journal **refuse** s'il reste des brouillons, en les nommant.
- Preuve : C03 rouge → vert ; C01 (brouillon déséquilibré) reste possible mais **invalidable**.

### C14 — écrans de création en échec (1,5 j) — *décision D-C*
| Écran | Colonnes envoyées et absentes | Correctif recommandé |
|---|---|---|
| Comptes de tiers | 23 (adresse, SIRET, IBAN/BIC, conditions, relance…) | Adresse/SIRET/TVA → colonnes ajoutées ; IBAN/BIC → `partner_bank_accounts` (existe) ; conditions → `payment_term_id` (existe) ; relance → `reminder_levels`. **Pas** 23 colonnes plates |
| Journaux | `racines_autorisees`, `compte_attente`, `numerotation`, `reconciliation_mode` | Colonnes ajoutées **et lues** (racines et compte d'attente contrôlés dans `post_journal_entry`), sinon retirées de l'écran |
| Sections analytiques | `section_type` | Colonne ajoutée (énumération) |
| Compte à la volée | `class`, `active` | Aligner sur les colonnes réelles du plan (classe dérivée du code) |

### M1 — FEC conforme A47 A-1 (1 j)
- `getFECData` joint `chart_accounts.name` (CompteLib), `journals.name` (JournalLib), tiers (CompAuxLib).
- Montants à **virgule décimale** ; `DateLet` = `lettrage_date` quand `EcritureLet` est posé ;
  `ValidDate` = `validated_at` ; `Montantdevise`/`Idevise` si devise ≠ fonctionnelle.
- Nom : **`{SIREN}FEC{AAAAMMJJ}.txt`**, export **refusé** sans SIREN (au lieu de `000000000`).
- Export **bloqué** tant que `validateFECData` rend des erreurs majeures.
- Preuve : `s4_fec` (F01–F07) vert ; test de non-régression sur un FEC de référence.

## X3 — paie (4 j + validation externe)

| Défaut | Correctif |
|---|---|
| **C5** lot non créable | Retirer `employer_contributions_total` (et tous les totaux) du formulaire : un lot se crée **vide** |
| **C7** 3ᵉ moteur marocain dans `PayRunsPage` | Supprimer le calcul client ; les totaux du lot sont **agrégés par la base** depuis ses bulletins (déclencheur sur `pay_slips` ou vue). Étendre `single-engine.test.ts` : interdire `0.0448`, `0.0226`, `CNSS`, `AMO`, `MAD` dans `src/` |
| **C6** grille France fausse — *décision D-G* | Nouvelle grille **France 2026** : vieillesse plafonnée/déplafonnée, maladie, allocations familiales (taux réduit/plein), AT/MP, FNAL, CSA, chômage + AGS patronaux, AGIRC-ARRCO T1/T2 + CEG/CET, **CSG 6,80 % déductible / 2,40 % non déductible + CRDS 0,50 % sur 98,25 %** (lue dans `payroll_legal_parameters`, qui existe déjà), **réduction générale** (formule paramétrée). Bornage par `valid_from`/`valid_to` ; l'ancienne grille est **close**, pas modifiée |
| **H10** lecteur relance le calcul | `can_perform('payroll.calculate')` dans `calculate_payslip` |

- **Tests d'or** : 3 bulletins de référence (SMIC ; 2 500 € non cadre ; 4 500 € cadre au-dessus du PMSS)
  **établis et signés par l'expert-comptable** (hors dépôt), rejoués ligne à ligne à 0,01 € près.
- Cycle complet par l'écran : créer le lot → bulletins → approuver → journal (D641 = brut,
  C421 = nets, équilibré) → virement (suite 212). Scénario `s5` entièrement vert.
- **Production** : recenser les bulletins déjà calculés avec l'ancienne grille ; décision de
  recalcul ou de rappel (hors plan technique).

## X4 — stock et logistique (6 j) — *décision D-B*

| Défaut | Correctif | Charge |
|---|---|---:|
| **C8** mouvement fantôme | Déclencheur `BEFORE INSERT` : `movement_type := coalesce(movement_type, type)`, `type := movement_type` ; `movement_type NOT NULL` ; la fiche article envoie les deux, avec dépôt et coût. **Mouvements fantômes existants** : les lister (`movement_type IS NULL`) ; les rejouer ou les marquer « ignorés » selon D-B | 0,5 j |
| **M6** stock initial sans origine | La création d'article ne pose plus `stock_quantity` : si une quantité est saisie, un mouvement `initial` (dépôt + coût d'achat) est créé ; déclencheur qui **refuse** toute écriture directe de `products.stock_quantity` hors moteur | 0,5 j |
| **C9** commande fournisseur et réception sans lignes | Éditeur de lignes (article, quantité, prix, TVA) dans la commande ; totaux **recalculés par la base** (comme les factures) ; la réception se crée **depuis** la commande (reste à recevoir) et écrit `goods_receipt_lines` ; « Reçu » passe par la chaîne 241/251 déjà prouvée | 2,5 j |
| **C10** commande client et BL sans lignes ni TVA | Même éditeur pour la commande client ; BL créé depuis la commande par la fonction existante de livraison partielle (`misc.ts`) ; expédition → chaîne 230/253 | 2 j |
| Placebos | Colonnes « Stock : Entré / Généré » lues depuis le mouvement **réel** (`reference_id`), plus depuis le statut | 0,5 j |

Preuve : `s2` (ST02–ST09) vert par l'écran ; ST05 : une sortie excédentaire est **refusée**.

## X5 — production, caisse, immobilisations (3,5 j)

| Défaut | Correctif |
|---|---|
| **C11** OF jamais terminable | `BEFORE INSERT` : `product_id := coalesce(product_id, bom.product_id)`, refus si aucun ; l'écran envoie l'article de la nomenclature. Test M04 (+10 produits, −20 composants, écriture) |
| **C12** clôture de caisse impossible — *décision D-E* | RPC **`create_pos_ticket`** atomique : ticket + lignes + **`pos_payments`** ; moyens de paiement par défaut (espèces 530, carte 5112) posés à l'inscription et aux sociétés existantes ; attendu en tiroir = **espèces seulement** ; K06 et K07 verts |
| **M7** la vente ne sort pas le stock ; lecteur ouvre la caisse | Sortie de stock par ligne de ticket (au dépôt du terminal) dans la même RPC ; `can_perform('pos.session.open')` |
| **C13** immobilisation non créable — *décision D-D* | Recommandé : **retirer** dérogatoire et subvention du formulaire (non implémentés dans le moteur 260 — limite dite), plutôt que d'ajouter des colonnes que personne ne lit |

## X6 — trésorerie et tableaux de bord (3 j) — *décision D-F*

| Défaut | Correctif |
|---|---|
| **M3** solde bancaire figé | Le solde affiché = **solde comptable du compte 512x** (déjà `calculated_balance`), plus `balance` stockée ; le solde initial saisi crée une **écriture d'ouverture** (contrepartie à décider : 890/à-nouveaux) |
| **M4** opérations identiques perdues | Clé de dédoublonnage = référence de banque (FITID, `:61:` référence) **quand elle existe**, sinon `(date, montant, libellé, rang d'occurrence dans le fichier)` comparé au **nombre** déjà importé. Test B01 (2 CB identiques → 2 lignes ; réimport → 0) |
| **M5** tableaux de bord faux | Une RPC **`get_kpis(p_from, p_to)`** lue sur le grand livre (CA = 70x, charges = 6x HT, encours clients = 411, fournisseurs = 401, trésorerie = 5x) utilisée par **les trois** tableaux ; la facture validée n'est plus « brouillon » (statut `open` à la validation) |

Test : `s9` exige l'égalité **tableau = grand livre** pour chaque indicateur.

## X7 — données de base, écrans, localisation (1,5 j)

- **M2** e-mail vide : normaliser `'' → null` dans les fonctions de requête (clients, fournisseurs,
  salariés, société) **et** en base (`BEFORE INSERT/UPDATE : email := nullif(trim(email), '')`).
- **M10** `/sales/margins` : `line_total` → `total` ; ajouter la requête à `check-embeds`.
- **M11** `/settings/nf525-audit` : `options` manquant ; `<Select>` tolère `options` indéfini ;
  `AppErrorBoundary` réinitialisé au changement de route.
- **M13** devise de la facture = devise de la société ; taux de TVA posés à l'inscription selon
  le pays (FR : 20 / 10 / 5,5 / 2,1 ; DJ : selon **D-11**).
- Mineurs : garde `employee_id` vide (`/hr/employee-documents`), `<tbody>`/`<tr>` imbriqués,
  `confirm()` nu remplacé par `confirmSync` (et contrôle UX-03 étendu à `confirm(`).

## X8 — contrôles durables et recette (1 j)

- `check-screen-writes` **0**, `check-viewer-writes` = liste D-6, `check_anon_grants` (tables) **0**.
- Balayage des **333 routes** dans le job Playwright (aucune réponse ≥ 400, aucun plantage).
- Registre du job `screen-path` **vide**.
- Rejouer l'audit complet et **re-noter chaque module** ; objectif : aucun module sous 7/10.

## 2. Décisions à prendre avant les vagues concernées

| Id | Question | Recommandation | Bloque |
|---|---|---|---|
| **D-A** | Écriture manuelle : validée à la création ou par un bouton ? | Brouillon puis **« Valider »** (séparation des tâches possible) | X2 |
| **D-B** | Mouvements fantômes déjà en base (prod) : rejouer ou ignorer ? | **Lister et faire valider** par l'utilisateur ; ne rien rejouer automatiquement | X4 |
| **D-C** | Comptes de tiers : colonnes plates ou tables existantes ? | Tables existantes (banque, conditions, relances) | X2 |
| **D-D** | Amortissement dérogatoire et subventions : implémenter ou retirer ? | Retirer maintenant, implémenter en phase 6 | X5 |
| **D-E** | Moyens de paiement de caisse et comptes par défaut | Espèces 530, carte 5112, chèque 5112 | X5 |
| **D-F** | Solde bancaire affiché : comptable ou relevé ? | Les deux côte à côte, **comptable** comme référence | X6 |
| **D-G** | Grille de paie France 2026 | Rédigée par nous, **validée par l'expert-comptable** (tests d'or signés) | X3 |
| **D-11** | Taux et localisation Djibouti | Décision existante, toujours ouverte | X7 (partiel) |

### Décisions de la partie 2, tranchées le 28/09/2026

Critère retenu : la solution la plus sûre **juridiquement**, qui réutilise ce que la base
porte déjà plutôt que d'ajouter des colonnes que personne ne lit.

**D-A — Brouillon, puis « Valider » ; « Enregistrer et valider » seulement sans séparation des tâches.**
- Une écriture saisie naît **brouillon** ; « Valider » (unitaire) et « Valider la
  sélection » (brouillard) appellent `validate_journal_entries(uuid[])`, qui rend un verdict
  par écriture.
- Le raccourci « Enregistrer et valider » reste offert **quand la société n'a pas activé
  la séparation des tâches** : c'est déjà la règle de la 232 (`post_journal_entry` avec
  `status = 'posted'` refusé si `enforce_segregation`). Aucune règle nouvelle, un clic de
  moins pour la petite société.
- Pourquoi : c'est ce qui alimente `validated_by` / `validated_at` (donc `ValidDate` du FEC,
  A47 A-1) et garde la séparation des tâches possible ; un brouillon déséquilibré reste
  **invalidable**. Valider à la création aurait rendu toute correction impossible sans
  extourne.
- La clôture de période ou de journal **refuse** s'il reste des brouillons, en les nommant.

**D-C — Aucune colonne plate : chaque donnée va là où la base la porte déjà.**
Mesuré le 28/09 : `third_party_accounts` a déjà `customer_id` / `supplier_id` /
`employee_id`, `payment_term_id`, `default_bank_account_id` et `credit_limit` ;
`customers` / `suppliers` ont adresse, ville, code postal, pays, SIRET et TVA ;
`partner_bank_accounts` et `reminder_levels` existent.

| Champ de l'écran (23 absents) | Destination |
|---|---|
| adresse, code postal, ville, pays, SIRET, TVA intracom., contact | le **tiers** lié (`customers` / `suppliers`) — lus et écrits par la fiche tiers, pas recopiés |
| IBAN, BIC, code banque, guichet, compte, clé | `partner_bank_accounts` + `third_party_accounts.default_bank_account_id` |
| conditions, mode, délai, échéance, escompte | `payment_term_id` (la table `payment_terms` porte délais, fin de mois, escompte) |
| encours autorisé | `credit_limit` (existe) |
| niveau et modèle de relance | **retirés de la fiche** : la relance est une politique de société (`reminder_levels`), pas une donnée du compte |
| zone géographique, catégorie | retirés (lus par aucun état) |

Pourquoi : une seule vérité par donnée ; un compte auxiliaire n'est qu'une vue comptable
du tiers. 23 colonnes recopiées auraient divergé dès la première modification de la fiche
client. Même principe pour les journaux : `racines_autorisees` et `compte_attente`
**ajoutées et contrôlées** par `post_journal_entry` (elles ont un effet), `numerotation`
et `reconciliation_mode` **retirées** de l'écran (aucune règle ne les lirait).

**D-G — Grille France 2026 rédigée par nous, chaque taux sourcé, déploiement conditionné à la signature de l'expert-comptable.**
- Chaque taux, plafond et assiette est une ligne datée de `payroll_legal_parameters`
  (`valid_from` / `valid_to`) avec sa **source officielle** (URSSAF, AGIRC-ARRCO, arrêté du
  PMSS), relevée au moment de l'exécution de X3 — aucune valeur de mémoire.
- La grille « France 2024-2025 » est **close** (`valid_to`), jamais modifiée : les
  bulletins déjà calculés restent explicables.
- Les trois bulletins d'or (SMIC ; 2 500 € non cadre ; 4 500 € cadre au-dessus du PMSS)
  sont d'abord calculés par nous et comparés au simulateur officiel, puis **signés par
  l'expert-comptable** ; ils deviennent les tests de non-régression (à 0,01 €).
- Le code de X3 avance sans attendre ; la **mise en production** de la grille attend la
  signature. D'ici là, la grille actuelle — fausse de ≈ 335 € de net sur 2 500 € — reste
  signalée comme telle dans la preuve.
- Pourquoi : un taux de paie faux engage l'employeur ; ni nous ni un test automatique ne
  peuvent certifier la conformité, seul un professionnel le peut.

**D-F — Les deux soldes côte à côte, le comptable comme référence ; le solde initial est une écriture d'à-nouveau.**
Mesuré le 28/09 : `bank_accounts` porte déjà `calculated_balance` (grand livre),
`statement_balance` / `statement_balance_date` (dernier relevé) et `reconciliation_diff`.
- Affichés : **solde comptable** (512x, référence de tous les états et tableaux de bord),
  **solde du dernier relevé** avec sa date, et **l'écart à rapprocher**. La colonne
  `balance`, que rien ne met à jour, n'est plus affichée ni lue (dépréciée).
- Le solde initial saisi à la création crée une écriture au journal **AN** :
  512x / **890 « Bilan d'ouverture »** (compte à ajouter au plan standard — absent le
  28/09), refusée si l'exercice porte déjà un à-nouveau sur ce compte (pas de double
  ouverture).
- Pourquoi : le solde comptable est le seul que la balance, le bilan et le FEC
  connaissent ; le relevé est la preuve externe ; leur écart est le travail de
  rapprochement, pas une erreur à masquer.

### Décisions de la partie 3, tranchées le 28/09/2026

Même critère que la partie 2 : la solution la plus sûre, qui réutilise ce que la base porte.

**D-B — Les mouvements fantômes sont listés, jamais rejoués d'office.**
La 280 inscrit chaque mouvement enregistré sans effet (`type` sans `movement_type`) à
`stock_movement_phantoms`, l'aligne **sans rien rejouer** et le marque. L'utilisateur décide, un
par un, depuis l'inventaire : **rejouer** (un mouvement neuf, daté du jour de la décision — la
date d'origine ne peut plus être juste pour la valorisation) ou **ignorer**. Un inventaire fantôme
ne se rejoue pas : une quantité comptée à une autre date ne dit rien du stock d'aujourd'hui.
Pourquoi : un rejeu automatique aurait modifié des stocks et des écritures ST sans que personne
ne l'ait vu ; l'inventaire physique reste la seule vérité.

**D-D — Dérogatoire et subvention retirés maintenant, implémentés en phase 6.**
Le moteur d'amortissement (260) ne les calcule pas et aucune colonne ne les porte : les offrir
faisait échouer **toute** création d'immobilisation. Ajouter des colonnes que personne ne lit
aurait fait croire qu'ils étaient gérés.

**D-E — Espèces 530000, carte 511200, chèque 511200.**
Posés pour chaque société existante et à la création d'une société ; seuls les paiements en
**espèces** sont attendus en tiroir à la clôture. Les comptes restent modifiables par
l'administrateur (écran des moyens de paiement), plus par un lecteur.

## 3. Suivi

Chaque vague produit sa preuve `doc/audit/VAGUE-Xn-AAAA-MM-JJ.md` (mesures d'entrée, rouges
avant, verts après, limites dites) et met à jour `AGENTS.md` et `RESTE-OUVERT`.
