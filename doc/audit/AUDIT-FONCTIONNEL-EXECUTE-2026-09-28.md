# Audit fonctionnel exécuté, module par module — 28 septembre 2026

> **Méthode** : rien n'est noté « à la lecture ». Chaque constat vient d'une exécution :
> base PostgreSQL 16 neuve (schéma + **236 migrations, 0 erreur**), **PostgREST réel** et une
> passerelle d'authentification (JWT) devant elle, **le vrai front** (Vite) connecté à ce banc,
> et **les vraies fonctions de requête des écrans** (`src/lib/queries/*`) appelées avec la
> **charge utile exacte** que chaque écran envoie, sous RLS réelle, avec quatre comptes
> (admin A, comptable A, lecteur A, admin B — société djiboutienne).
> Harnais rejouable : [`harnais-audit-2026-09-28/`](harnais-audit-2026-09-28/).

## 0. Ce que disent les contrôles existants (tous verts)

| Contrôle | Résultat |
|---|---|
| Suites SQL + contrôles CI (rejoués dans l'ordre de la CI) | **77/77** fichiers verts (2 rouges attendus au registre : 231 M-17-01, 245 T08) |
| `tsc -b`, `oxlint`, i18n, a11y, contraste, knip, tables mortes | tous à 0 / conformes |
| Vitest | **1 502 / 1 502** |
| Fonctions Edge (Deno) | **32 / 32** |
| `check-written-columns`, `check-unchecked-writes`, `check-rpc-contract`, `check-embeds` (1 500 requêtes) | 0 / 0 / 0 / 0 |

**Tout est vert, et pourtant les défauts ci-dessous sont réels.** Raisons mesurées :
les tests unitaires **simulent** Supabase (`src/test/setup.ts`) ; les suites SQL insèrent
leurs données **directement en base**, jamais par le chemin de l'écran ; `check-written-columns`
ne regarde que l'objet écrit **dans la même requête** que le `.from()`, alors que le chemin
normal est *écran → fonction → `.insert(param)`*.

## 1. Notes par module

| Module | Note | Verdict en une ligne |
|---|---:|---|
| Ventes (devis, factures, avoirs, règlements) | **6/10** | Le cœur est juste ; commandes et BL sans lignes, marges en panne, client sans e-mail impossible |
| Achats | **4/10** | Facture et paiement justes ; commande et réception sans lignes → jamais de stock ; approbation sans contrôle |
| Comptabilité générale | **4/10** | États justes ; **une écriture saisie à la main ne peut jamais être validée** ; FEC non conforme |
| Trésorerie | **4/10** | Import et rapprochement corrects ; soldes affichés faux ; opérations identiques perdues |
| Stock | **3/10** | L'inventaire marche ; le mouvement de la fiche article est **fantôme** ; stock initial sans origine |
| Production | **2/10** | Un OF créé à l'écran **ne peut jamais être terminé** |
| RH & Paie | **3/10** | Absences solides ; **lot de paie impossible à créer** ; grille France juridiquement fausse ; 3ᵉ moteur marocain |
| Caisse (POS) | **2/10** | **Aucune session avec ventes ne peut être clôturée** ; la vente ne sort pas le stock |
| Immobilisations | **3/10** | Moteur SQL juste (260) mais **création impossible depuis l'écran** |
| Projets | **6/10** | Projet et tâches OK ; refacturation des temps absente (W8, connu) |
| CRM | **7/10** | Opportunités OK (périmètre testé réduit) |
| Tableaux de bord | **3/10** | Encours clients, trésorerie, CA et marge **contredisent le grand livre** |
| Reporting & états légaux | **4/10** | Balance, bilan, CR justes ; FEC rejeté par son propre validateur ; écran des marges en panne |
| Système, sécurité, droits | **4/10** | Isolation entre sociétés tenue ; **écriture anonyme** sur des tables globales ; un lecteur bloque la facturation |
| Qualité du code & outillage | **6/10** | Typage, lint, i18n impeccables ; contrôles aveugles au chemin écran ; code mort de moteurs parallèles |

## 2. Défauts prouvés, par gravité

### Critiques (fonction principale inopérante, ou donnée faussée)

| # | Module | Constat | Preuve |
|---|---|---|---|
| C1 | Sécurité | Un **visiteur non connecté** modifie, crée et supprime des lignes de `webhook_event_catalog` (politique `ALL USING (true)`) | PATCH/POST/DELETE anonymes → 200 |
| C2 | Sécurité / Paie | **N'importe qui, anonyme compris**, réécrit les **paramètres légaux globaux** (`payroll_legal_params_all` : `tenant_id IS NULL OR …` en écriture) : SMIC horaire mis à 1 €, majoration des heures sup à 0, pour **toutes** les sociétés | PATCH anonyme et PATCH lecteur → 200 |
| C3 | Sécurité | Un **lecteur** modifie `document_number_sequences` : remis à 2, **toute validation de facture échoue ensuite** (doublon, rollback) — la facturation est bloquée | `viewer-sweep` + validation → 409 |
| C4 | Compta | **Aucun chemin d'interface ne valide une écriture manuelle** : `JournalEntriesPage`, `JournalSaisiePage`, `SaisieParPiecePage` créent en `draft` ; « clôturer la saisie » ne pose que `status_detail` ; les seuls `status: 'posted'` du front sont l'extourne et le report. Les OD n'atteignent jamais balance, bilan, TVA ni FEC | C03 : `status_detail=closed`, `status=draft` |
| C5 | Paie | **Créer un lot de paie échoue toujours** : `PayRunsPage` envoie `employer_contributions_total`, absente de `pay_runs` (PGRST204) | W06 |
| C6 | Paie | La grille « France 2024-2025 » livrée par les migrations applique : SS 6,98 % sal. / 29,74 % pat. sans plafond, retraite 11,40 % sur tout le brut, CSG/CRDS 9,20 % sur 100 % du brut sans part déductible, chômage salarial 0,24 %, aucune réduction générale. **2 500 € brut → 1 615 € net** (≈ 1 950 € attendus), charges patronales 52 % | H06, `calc_inputs` |
| C7 | Paie | `PayRunsPage` porte un **troisième moteur** (CNSS/AMO/IR **marocains**, plafond 6 000 MAD) qui écrit les totaux du lot : le lot affiche 5 938,86 € de net, ses bulletins 4 199,13 € | H05 |
| C8 | Stock | Le mouvement de la **fiche article** envoie `type` sans `movement_type` ; le déclencheur ne lit que `movement_type` : **entrée, sortie (même 5 000 sur 57) acceptées, affichées, sans aucun effet** | ST03, ST05, ST06 |
| C9 | Achats / Stock | Commande fournisseur et réception se créent **sans aucune ligne** ; aucune fonction (front ou SQL) n'écrit `goods_receipt_lines` : une réception « reçue » **n'entre jamais rien**, et l'écran affiche « Stock : **Entré** » | ST08 + page réelle |
| C10 | Ventes / Stock | Commande client et BL : en-tête seul, **TVA à 0**, aucune ligne — la chaîne BL → sortie → écriture ST (230/253) est inatteignable | ST09 |
| C11 | Production | L'écran crée l'OF avec `product_id: null` ; le déclencheur de fin lit `NEW.product_id` → **un OF ne peut jamais être terminé** (erreur NOT NULL) ; la colonne « Stock » affiche « Généré » dès le statut `completed` | M04 |
| C12 | Caisse | L'écriture de clôture débite `pos_payments`, que l'écran de caisse **n'écrit jamais** (et une société neuve n'a aucun moyen de paiement) : **clôture refusée** (« débit 0 ≠ crédit 72 ») | K06 |
| C13 | Immobilisations | `FixedAssetsPage` envoie `derogatory_depreciation`, `subvention_*` inexistantes : **aucune immobilisation créable** | W04 |
| C14 | Compta | Création/modification d'un **compte de tiers** (23 colonnes absentes), d'un **journal** (4), d'une **section analytique**, d'un **compte à la volée** : toujours en échec | W01, W02, W03, W05 |

### Majeurs (résultat faux, perte de données, non-conformité)

| # | Module | Constat |
|---|---|---|
| M1 | Compta / FEC | FEC rejeté par **son propre validateur** (CompteLib vide) ; `JournalLib` = « Journal » partout ; `CompAuxLib` vide ; point décimal ; `DateLet` vide avec `EcritureLet` ; nom `FEC_000000000_…` au lieu de `SirenFECAAAAMMJJ` |
| M2 | Ventes / Achats / RH | **Client, fournisseur, salarié sans e-mail impossibles** : l'écran envoie `''`, la contrainte n'accepte que `NULL` |
| M3 | Trésorerie | `bank_accounts.balance` (affiché) **n'est mis à jour par rien** : 1 000 € affichés sous 4 décaissements de 360 € ; le solde initial saisi n'est jamais comptabilisé |
| M4 | Trésorerie | Import de relevé : deux opérations **légitimes identiques** le même jour (2 CB de 12,50 €) → la seconde est **supprimée comme doublon** |
| M5 | Tableaux de bord | Accueil : encours clients **0** (réel 3 775,65), trésorerie **3 000** (grand livre −81,45) ; tableau financier : CA **1 258,55** (accueil 4 222), charges **TTC** 1 440 (grand livre 1 116 HT) → marge fausse |
| M6 | Stock | Stock initial saisi à la création de l'article : **ni mouvement, ni couche, ni écriture** (50 unités sans valeur au bilan) |
| M7 | Caisse | La vente en caisse **ne sort pas le stock** ; un lecteur ouvre une session de caisse |
| M8 | Droits | Un lecteur modifie **16 des 41** tables testables (dont `fiscal_periods`, `stock_valuation_layers`, `journals`), crée des écritures brouillon (`post_journal_entry` sans contrôle de permission), relance le calcul des bulletins |
| M9 | Achats | Approbation d'une facture d'achat **par son auteur** acceptée ; `approved_by` **jamais écrit** |
| M10 | Reporting | `/sales/margins` lit `invoice_lines.line_total` (inexistante) → écran en erreur |
| M11 | Système | `/settings/nf525-audit` **fait tomber toute l'application** (`<Select>` sans `options`) |
| M12 | Sécurité | `analytic_distribution_lines` garde une politique héritée (`tenant_id IS NULL OR … app.tenant_id`, GUC jamais posé) : lignes « sans société » inscriptibles et visibles de tous ; `project_docs` cloisonne sur `SELECT id FROM tenants LIMIT 1` |
| M13 | Localisation | Facture d'une société en DJF enregistrée en **EUR** ; une société neuve n'a **aucun taux de TVA** |

### Mineurs
Écriture brouillon déséquilibrée acceptée par l'API ; `/hr/employee-documents` envoie `employee_id=eq.` (400) ;
`<tbody>`/`<tr>` mal imbriqués (`/reporting/bi`, `/stock/boms`) ; `confirm()` nu dans `JournalSaisiePage`
(échappe au contrôle UX-03) ; l'`ErrorBoundary` ne se réinitialise pas au changement de route.

## 3. Ce qui a été prouvé juste

- **Isolation entre sociétés** : même jeton, en-tête de l'autre société → 0 ligne ; 17 scénarios 236, 410 FK composites.
- **Facture** : brouillon sans écriture ; validation → `FAC-2026-000004`, écriture VT **D411 1 258,55 / C707 1 055,50 / C445711 200 / C445713 3,05** ; montants et suppression verrouillés ; en-tête falsifié recalculé (99,99 / 20 / 119,99) ; hors exercice refusé.
- **Règlements** : partiel 500 puis solde → payée, 411 lettré ; trop-perçu → 419100 (avance client).
- **Devis → facture → avoir** : 240 TTC, `AV-2026-000001`, contrepassation D707 200 / D445711 40 / C411 240, facture soldée.
- **Facture d'achat** (par un comptable) : AC D607 300 / D445661 60 / C401 360 ; décaissement → 401 soldé.
- **États** : balance = grand livre (9 356,75 = 9 356,75) ; bilan écart 0 ; CR = classes 6/7 ; TVA de septembre = grand livre (collectée 812,20, déductible 240, nette 572,20).
- **Inventaire** (`InventoryPage`) : ajustement/initial mettent à jour article, dépôt, couches et journal ST (D31 84 / C603 84).
- **Relevé MT940** : lu, solde de clôture repris, virement de 500 rapproché, état de rapprochement cohérent.
- **Lectures** : 333 écrans parcourus, 167 lecteurs sans argument appelés — 3 erreurs HTTP seulement.

## 4. Limites de cet audit (dites)

Non exécutés ici : intégrations externes (Stripe, Resend, Chorus Pro, Yousign, GoCardless, VIES réel —
secrets hors dépôt), temps réel (WebSocket), stockage de fichiers, e-mails, parcours e2e Playwright.
La clôture d'exercice, les amortissements, l'absence et la TVA autoliquidée ne sont couverts que par
les suites SQL existantes (vertes), pas par le chemin de l'écran. Les 63 colonnes inexistantes du
contrôle `screen-writes.mjs` sont confirmées en exécution pour 6 fonctions ; les autres sont à confirmer
une à une. Le CRM et les projets ont été testés sur leur flux principal seulement.
