# Inventaire des chaînages — tranche 4 (L1) — 30 septembre 2026

> **Objet.** Rendre **opposable** la méthode de
> [l'inventaire de la tranche 1](INVENTAIRE-CHAINAGES-L1-2026-09-29.md) §3, en la
> **rejouant** sur le schéma d'aujourd'hui, et livrer ce qu'elle désigne :
> nommer les effets, les **déclarer** (les contrats du lot L7 sont là), les
> **tracer** (doctrine des déclencheurs compagnons de la 310) et les **prouver**.
> **Ce que ce document n'est pas** : une liste de travaux. C'est un **tri**, avec
> la raison de chaque ligne — *un audit qui ne nomme pas ce qu'il écarte n'est pas
> un audit* (la formule est du référentiel, §B.2).
>
> **Livré par cette tranche** : migration
> [314](../../app/sql/314_chain_l1_achats.sql) — **trois effets** de la chaîne
> achats et notes de frais tracés par **deux déclencheurs compagnons**, leurs
> **trois contrats** déclarés dans le même fichier — et suite
> [314](../../app/sql/314_chain_l1_achats_tests.sql) : **10 scénarios**.
> **Non-régression** : 165 scénarios verts sur base neuve (**263 migrations**),
> dont les suites 310, 311 (**T11 élargi** : un compte y était figé à 8
> compagnons, il devient une propriété — la tranche en ajoute deux), 312, 313.

---

## 1. La mesure, rejouée

La règle du référentiel (§0.3) est reproduite à l'identique : un **chaînage** est
une fonction qui touche **au moins deux modules**, un module étant déduit du nom
de la table. Deux différences, dites :

* la carte de modules est **écrite dans la requête** (une cinquantaine de motifs
  priorisés) : elle est relisible, et **approximative** — `stock_movements` compte
  en « stock » alors que la production et les ventes l'alimentent, comme le
  référentiel l'assume lui-même ;
* la source est la base **compilée** (`pg_proc`), pas les fichiers : ce qui compte
  est ce qui s'exécute.

| Mesure | 24/09 (référentiel) | **30/09** | Comment |
|---|---:|---:|---|
| Fonctions analysées (hors outillage `_…`) | 325 | **~500** | `pg_proc`, schéma `public` |
| Chaînages transverses (touchent ≥ 2 modules) | 62 | **99** | lecture **et** écriture |
| dont **écrivent** dans ≥ 2 modules | — | **32** | le signal fort : l'effet traverse vraiment |
| dont **lecture seule** transverse | — | **67** | vues, rapports, contrôles : pas des chaînages |
| Effets portant un **contrat** (`document_effects`) | 0 | **17** | 14 (L7) + 3 (cette tranche) |
| Effets **tracés** par un maillon | 0 | **17** | idem |

Le référentiel comptait 62 ; il y en a **99** aujourd'hui. Rien ne s'est
« dégradé » : le schéma a grandi (263 migrations), et la mesure de l'époque ne
regardait qu'un seul sens. Ce document ne prétend pas que 99 est le chiffre
exact — il prétend qu'il est **reproductible** : la requête d'extraction est dans
la porte G2, celle de la carte de modules est citée dans le §2.

---

## 2. Les 32 fonctions qui ÉCRIVENT dans ≥ 2 modules — verdict et état

Quatre verdicts, ceux de l'inventaire de la tranche 1 : **maillon** (écriture
d'état d'un document), **paramétrage** (acte de référentiel / mise en service),
**recalcul** (régénération paramétrique), **garde** (empêche, ne produit pas).
« RPC » marque un maillon dont l'entrée est un **appel de fonction** et non un
déclencheur : un compagnon ne peut pas s'y accrocher (doctrine §2 de la 310).

| # | Fonction | Modules écrits | Verdict | État |
|---:|---|---|---|---|
| 1 | `cancel_import_batch` | commercial, rh, stock, système | **Acte d'import** (annulation d'un batch) | écarté — l'inventaire §2 l'a déjà tranché |
| 2 | `create_stock_on_manufacturing_complete` | compta, production, stock | **Maillon** | ✅ tracé (311) |
| 3 | `pos_refund_ticket` | commercial, stock, trésorerie | **Maillon / RPC** (avoir de caisse + retour de stock) | à tracer — lot L3 |
| 4 | `post_exchange_gain_loss_on_payment` | commercial, compta, système | **Maillon / déclencheur** (écart de change au règlement) | à tracer — **candidat direct** |
| 5 | `apply_chart_pack` | compta, système | **Paramétrage** (plan comptable) | écarté |
| 6 | `auto_reconcile_by_score` | commercial, trésorerie | **Maillon** | ✅ tracé (311) |
| 7 | `bootstrap_tenant` | compta, système | **Mise en service** | écarté |
| 8 | `close_fiscal_year` | compta, système | **Acte de clôture** (exercice) | lot dédié — pas un document |
| 9 | `create_billable_line_on_timesheet_stop` | commercial, projets | **Maillon / déclencheur** (temps → facture) | à tracer — **candidat direct** |
| 10 | `create_journal_on_customer_payment` | commercial, compta | **Maillon** | ✅ tracé (310) |
| 11 | `create_journal_on_invoice_validate` | commercial, compta | **Maillon** | ✅ tracé (310) |
| 12 | `create_journal_on_purchase_invoice_validate` | commercial, compta | **Maillon** | ✅ **tracé (314, cette tranche)** |
| 13 | `create_journal_on_supplier_payment` | commercial, compta | **Maillon** | ✅ tracé (310) |
| 14 | `create_pos_ticket` | stock, trésorerie | **Maillon / RPC** (ticket de caisse) | à tracer — lot L3 |
| 15 | `create_tenant_for_current_user` | rh, système | **Mise en service** | écarté |
| 16 | `generate_depreciation_entry` | compta, système | **Maillon sans déclencheur** (appelé par un job) | à tracer — lot L4 (ordonnancement) |
| 17 | `integrate_expense_report_on_approval` | compta, rh | **Maillon** | ✅ **tracé (314, cette tranche)** — deux effets |
| 18 | `integrate_pay_recalls_on_payrun` | rh, système | **Maillon / déclencheur** (rappels de paie) | à tracer — **candidat direct** |
| 19 | `integrate_salary_advances_on_payrun` | rh, système | **Maillon / déclencheur** (acomptes) | à tracer — **candidat direct** |
| 20 | `payroll_payment_inner` | compta, système | **Maillon interne** (appelé par la RPC de versement) | à tracer — lot L3 |
| 21 | `payroll_post_run` | compta, rh | **Maillon / RPC** (validation du bulletin → écriture) | à tracer — lot L3 |
| 22 | `payroll_reverse_posted_run` | compta, rh | **Maillon / déclencheur** (contre-passation de paie) | **tracé — tranche 6 (migration 321, effet `payroll.run.reversed`)** |
| 23 | `post_bank_statement_line` | compta, trésorerie | **Maillon / RPC** (ligne de relevé → lettrage) | à tracer — lot L3 |
| 24 | `post_deferred_charge` | compta, système | **Recalcul** (étalement d'une charge) | écarté — régénère, ne chaîne pas |
| 25 | `post_pos_session_on_close` | compta, stock | **Mort** : aucun déclencheur (mesuré par la 311) | écarté — c'est `_multi` qui vit |
| 26 | `post_pos_session_on_close_multi` | compta, stock | **Maillon** | ✅ tracé (311) |
| 27 | `reconcile_bank_statement_line` | compta, trésorerie | **Maillon / RPC** (rapprochement manuel) | à tracer — lot L3 |
| 28 | `refresh_invoice_settlement` | commercial, compta | **Recalcul** (solde de facture) | écarté |
| 29 | `refresh_purchase_invoice_settlement` | commercial, compta | **Recalcul** (solde fournisseur) | écarté |
| 30 | `revaluate_currency_balances` | compta, système | **Recalcul de clôture** (réévaluation) | écarté — lot L4 |
| 31 | `statement_line_ledger_match` | compta, trésorerie | **Maillon / déclencheur** (appariement automatique) | à tracer — **candidat direct** |
| 32 | `unreconcile_bank_statement_line` | compta, trésorerie | **Maillon / RPC** (dé-lettrage) | à tracer — lot L3 |

**Le compte, sans arrondi** : **8 tracés** (6 avant cette tranche, **2 ici** — qui
font 3 contrats), **10 écartés** avec leur raison, **14 maillons restants** dont
**5 candidats directs** (déclencheur `AFTER` + aval identifiable : écart de
change, temps → facture, rappels et acomptes de paie, appariement de relevé).

**Mise à jour du même jour — tranche 5 (30/09/2026).** Les **cinq candidats
directs** de la ligne ci-dessus sont **tracés** : migration **316**,
suite d'acceptation **316** (**12 scénarios** verts), et la **limite de
vocabulaire** du §5 est **fermée** — migration **315**, la valeur **`sans_effet`**
entre dans le `CHECK` de `chain_traces.resultat`, prouvé par **252 T17**.
Le détail, les chiffres de non-régression et les **trois assertions du socle** que
la base neuve a fait préciser (310 T10, 311 T09 et T11) sont dans la
[preuve de la tranche 5](VAGUE-L1-TRANCHE5-2026-09-30.md).

**La requête de la carte de modules** (reproductible, à rejouer après chaque
tranche) : elle est dans l'en-tête du §2 de ce document — une liste
`(priorité, motif, module)` appliquée au **premier** motif qui matche, puis
`count(DISTINCT module)` par fonction, sur les tables lues **et** écrites
relevées dans `pg_proc.prosrc`.

---

## 3. Ce que la tranche 4 trace — et pourquoi ces trois effets

La doctrine de la 310 exige **deux conditions** pour qu'un compagnon soit
possible : le maillon doit être un **déclencheur `AFTER`** (pour que `zz_l1_`
s'exécute après lui), et son aval doit être **identifiable par une clé mesurée
dans son propre corps** (on ne devine pas une correspondance).

| Effet | Document / événement | Aval, et la clé mesurée dans le maillon |
|---|---|---|
| `purchase.invoice.generated_entry` | `purchase_invoices` / `approved` | `journal_entries`, `invoice_ref = number` **et** `journal_code = 'AC'` (la clé d'idempotence du maillon) |
| `expense.report.generated_entry` | `expense_reports` / `approved` | `journal_entries`, `reference = 'EXPENSE-' ‖ number` |
| `expense.report.payroll_element` | `expense_reports` / `approved` | `payroll_variable_elements`, `source = 'expense_report'` **et** `source_id` (unicité posée par la 256) |

**Pourquoi la facture d'achat d'abord** : la matrice du référentiel donne
**achats → comptabilité** parmi les liens les plus chargés du produit, et la
facture d'achat validée est le **symétrique exact** de la facture de vente —
laquelle est tracée depuis la 310. Un chaînage que le client voit des deux côtés
d'un même flux, dont un seul côté est dans le registre, est l'asymétrie qui fait
perdre confiance à une vue chaîne.

**Les deux déclencheurs compagnons** (`zz_l1_` trie après `create_journal_purchase_invoice`
et après `integrate_expense_report`, mesuré) ; **trois contrats** déclarés dans la
même migration (la porte **G2** l'exige depuis L7 : un effet appelé sans contrat
casse la construction) ; **aucun corps de maillon métier réécrit**.

---

## 4. Les mesures, et la non-régression

| Mesure | Avant la 314 | Après la 314 | Où c'est prouvé |
|---|---|---|---|
| Effets tracés (cumul L1) | 14 | **17** | G2 : 25 → **31 constats** |
| Contrats déclarés | 14 | **17** | 314 T09, porte G2 |
| Compagnons `zz_l1_` | 8 | **10** | 311 T11 (élargi), 314 T07 |
| Liens d'une facture d'achat approuvée | **0** | **1** | 314 T01 |
| Liens d'une note de frais approuvée | **0** | **2** | 314 T03 |
| Événements métier publiés | 14 noms | **+2 noms** | 314 T01, T03, T06 |
| Base neuve | 262 migrations | **263 migrations, 0 erreur** | ce document |

**Non-régression rejouée sur base neuve** (migrations, les **12** contrôles du
dépôt dans l'ordre de la CI, puis les suites) : **17 suites, 165 scénarios
verts** — `252` 16, `310` 15, `311` 12, `312` 12, `313` 11, **`314` 10**, `230` 5,
`180` 22, `192` 15, `210` 6, `213` 6, `229` 6, `302` 8, `222` 5, `277` 5, `281` 8,
`170` 3/3.

**Une régression a été trouvée par cette non-régression, et corrigée** : la suite
**311 T11** comptait **8** compagnons `zz_l1_` et **7** frères triant avant — des
**comptes** figés sur la tranche 2. La tranche 4 en ajoute deux, tous deux
conformes. L'assertion a été **élargie en propriétés** (`tous APRÈS`, `tous sauf
la caisse après leur frère par le nom`, `aucun frère après eux`) : elle ne
vieillira plus à chaque tranche, et elle dit plus que le compte qu'elle
remplace. Le changement est daté dans le fichier.

---

## 5. Les limites, dites

* **Le vocabulaire de `chain_traces.resultat` n'a pas de valeur pour « maillon
  exécuté, aucun effet produit ».** Une note de frais à 0 € n'écrit pas
  d'écriture (le maillon le décide) : le compagnon ne pose alors **ni lien ni
  trace** — le scénario **T04** le mesure (un lien, pas deux). Inventer un lien
  vers rien, ou une trace qui dit `applique` sur un effet absent, serait un
  mensonge que la vue chaîne lirait. **C'est une entrée pour la tranche qui
  ajoutera la valeur manquante** (un `sans_effet`, par exemple), pas un silence.
  → **Fermée le 30/09/2026** : la valeur **`sans_effet`** existe (migration
  **315**, prouvée par **252 T17**), donc le vocabulaire sait dire « attendu et
  absent ». La suite **316** l'emploie là où elle doit (écart de change marqué sans
  écriture : T03) et **ne l'emploie pas** là où le silence est normal (règlement en
  devise de tenue : T02 ; temps non facturable : T07 ; relevé sans contrepartie :
  T09) — c'est cette distinction qui rend la valeur utile plutôt que bruyante.
* **Cinq candidats directs ne sont pas faits** : écart de change au règlement,
  temps → facture, rappels de paie, acomptes de paie, appariement de relevé. Ils
  remplissent les deux conditions de la doctrine — c'est la prochaine tranche,
  pas un « reste » flou.
  → **Faits le 30/09/2026** (migration **316**, suite **316** : 12 scénarios).
  Deux des trois branches d'anomalie que ces effets ouvrent (relevé rapproché sans
  ligne marquée, rappel marqué traité sans élément de paie) restent **sans
  scénario** : c'est écrit dans la [preuve](VAGUE-L1-TRANCHE5-2026-09-30.md) §5.
* **Neuf maillons restants sont des RPC** (caisse, paie, relevé) : un compagnon ne
  peut pas s'y accrocher, il faut les tracer **par leur chemin d'appel**. C'est
  un travail de nature différente (lot **L3**), pas une omission.
  → **RECOMPTÉ le 02/10/2026 (tâche 3.1 du plan de la partie 3).** Le chiffre
  « neuf » ne tenait pas : il comptait des fonctions que le compilateur ne
  qualifiait pas, et il en omettait une. Le recomptage est rejouable — il est
  dans la porte **`ci/check_chain_rpc_inventory.sql`**, câblée en CI, qui lit
  `pg_proc` (ce qui est compilé, pas les fichiers) et **publie l'inventaire à
  chaque passage**. Mesuré sur base neuve (PostgreSQL 16, 273 migrations) :

  **14 maillons RPC transverses** (écrivent dans ≥ 2 modules, entrée par
  appel), dont :

  | # | Maillon (nom public) | Modules | Verdict au 02/10 |
  |---:|---|---|---|
  | 1 | `create_pos_ticket` | caisse, stock | ✅ **tracé (412)** — par son wrapper |
  | 2 | `pos_refund_ticket` | caisse, stock | ✅ **tracé (412)** — par son wrapper |
  | 3 | `post_payroll_payment` | compta, rh | ⬜ **tâche 3.2** (paie versée) |
  | 4 | `payroll_post_run` | compta, rh | ⬜ **tâche 3.2** (validation du bulletin) |
  | 5 | `post_bank_statement_line` | compta, trésorerie | ⬜ **tâche 3.3** (relevé manuel) |
  | 6 | `reconcile_bank_statement_line` | compta, trésorerie | ⬜ **tâche 3.3** (rapprochement) |
  | 7 | `unreconcile_bank_statement_line` | compta, trésorerie | ⬜ **tâche 3.3** (dé-lettrage) |
  | 8 | `apply_chart_pack` | compta, système | écarté — paramétrage (inventaire §2, l. 5) |
  | 9 | `bootstrap_tenant` | compta, système | écarté — mise en service |
  | 10 | `create_tenant_for_current_user` | rh, système | écarté — mise en service |
  | 11 | `cancel_import_batch` | 5 modules | écarté — acte d'import (inventaire §2, l. 1) |
  | 12 | `refresh_invoice_settlement` | commercial, compta | écarté — recalcul paramétrique |
  | 13 | `refresh_purchase_invoice_settlement` | achats, compta | écarté — recalcul paramétrique |
  | 14 | `revaluate_currency_balances` | compta, système | écarté — recalcul de clôture |

  **Trois écarts avec le tableau du 30/09, et pourquoi :**

  * **`payroll_payment_inner` n'existe plus comme entrée** : il a été RENOMMÉ en
    `payroll_payment_inner` en 224, et l'appel public est **`post_payroll_payment`**
    (qui porte la garde de permission R-17). Le nom du §2, ligne 20, ne désigne
    plus rien d'exposable. C'est mesuré, pas déduit : `payroll_payment` — ce
    que donnerait une simple soustraction du suffixe `_inner` — **n'existe pas**.
  * **`apply_chart_pack` apparaît** là où il était invisible : la carte des
    modules du 02/10 a été corrigée (le motif `accounts` ne matchait pas
    `chart_accounts`, qui le *contient* sans le commencer). Le maillon n'est pas
    nouveau ; il était mal compté. Il reste écarté, pour la **même** raison que
    l'inventaire.
  * **`create_stock_on_manufacturing_complete` et `statement_line_ledger_match`
    ne sont pas des RPC** : ce sont des déclencheurs, et leur chaîne est dans des
    compagnons `zz_l1_…`. Les classer « à tracer » était un effet de bord de la
    même extraction.

  **Ce que la porte rend impossible désormais** : un maillon RPC transverse neuf
  qui arrive sans chaîne **casse la CI**, et une entrée du registre devenue
  inutile **casse aussi** (elle doit disparaître dans le commit qui trace le
  maillon). La liste ne peut donc plus mentir en silence.
* **La carte de modules est une heuristique** : un chiffre comme « 99 » dépend de
  la liste de motifs. Le document publie la sienne, ce qui la rend **discutable**
  — et c'est le point : le référentiel avait la même limite, il l'avait dit aussi.
* **La réception de marchandise est TRACÉE (30/09, migration `319`, suite `319`)** :
  l'inventaire la rangeait « réécriture du corps » — N mouvements à partir de N
  lignes, la correspondance ligne → ligne ne se devine pas de l'extérieur (les N
  mouvements portent le même `reference_id`, et l'ordre d'insertion n'est pas une
  garantie). La `319` reprend le corps de la `241` **à l'identique** et y ajoute
  l'entrée du maillon (`chain_avant`, **par ligne**), le lien **par ligne** et la
  sortie (`emit_domain_event` + `chain_apres`), avec son contrat d'effet déclaré
  dans le même fichier (la porte **G2** l'exige). **Non-régression mesurée** : la
  suite `241` rend **7/7 avant et 7/7 après** le remplacement du corps, et
  `plpgsql_check` **0 erreur**. 7 scénarios. C'était **le seul maillon** de la
  liste que la doctrine autorisait à réécrire : les neuf autres sont des **RPC**,
  et se tracent par leur chemin d'appel.

---

## 6. Ce que la suite doit produire

1. **Les cinq candidats directs** (une tranche, avec contrats et suite) —
   ✅ **fait** le 30/09/2026 ([preuve](VAGUE-L1-TRANCHE5-2026-09-30.md)) ;
2. **Les neuf maillons RPC** — tracer par le chemin d'appel, ce qui suppose de
   choisir où l'entrée du maillon est posée (lot **L3**) ;
3. **La réception de marchandise** — ✅ **fait le 30/09/2026** (migration **`319`**,
   suite **`319`**, **7 scénarios**) : liaison **par ligne**, non-régression de la
   `241` mesurée (7/7 avant et après) ;
4. **`close_fiscal_year` et `revaluate_currency_balances`** — actes de clôture :
   ils ne sont pas des documents, et le socle n'a pas de notion de « lot de
   clôture » : c'est un choix de modèle (lot **L4**), pas un oubli ;
5. **Le vocabulaire de trace** (limite §5) : une valeur pour « exécuté, aucun
   effet », sinon le tableau de bord du lot **L5** comptera les notes de frais à
   0 € comme des chaînages qui n'ont rien fait.
   ✅ **fait** le 30/09/2026 : `sans_effet` (migration **315**, **252 T17**), et
   employé par la tranche 5 avec la retenue annoncée ici.


