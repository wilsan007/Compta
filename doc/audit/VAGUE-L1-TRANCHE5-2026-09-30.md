# Vague L1 — tranche 5 : les cinq candidats directs — 30 septembre 2026

> **Objet.** Fermer le classement de
> l'[inventaire de la tranche 4](INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md)
> §2 : sur les **32 fonctions qui écrivent dans ≥ 2 modules**, **5** avaient été
> rangées « **candidat direct** » — un maillon **déclencheur** (pas un appel de
> fonction) dont l'aval est **identifiable par une clé mesurée dans le corps du
> maillon**. Ce sont exactement les deux conditions de la doctrine compagnon de
> la 310. La tranche 5 les trace : **écart de change au règlement**, **facturation
> des temps**, **rappels de paie**, **acomptes de paie**, **appariement d'une
> ligne de relevé**. La même vague ferme la **limite de vocabulaire** que la
> tranche 4 avait publiée (§5 de l'inventaire).
> **État d'entrée.** Le socle savait dire `applique`, `ignore` et `tolere` — pas
> « l'effet était **attendu** et **n'existe pas** ». La **315** ajoute la valeur
> **`sans_effet`** au `CHECK` de `chain_traces.resultat` (une seule instruction au
> niveau du parent : PostgreSQL **propage** la contrainte aux partitions ; le
> premier essai, partition par partition, a échoué sur « constraint already
> exists » — mesuré) et la suite **252 T17** la prouve (**17/17 verts**).
> **Livré.** Migrations **315** (`315_chain_trace_sans_effet.sql`) et **316**
> (`316_chain_l1_candidats.sql`), suite d'acceptation **316**
> (`316_chain_l1_candidats_tests.sql`, **12 scénarios**), câblage CI, et la mise
> à jour des documents de compte (AGENTS.md, plan §441, inventaire de la
> tranche 4).

---

## 1. Les cinq effets, et ce qui les rend mesurables

| # | Fonction du maillon | Effet tracé | Amont → aval | Le fait générateur, **mesuré** |
|---:|---|---|---|---|
| 1 | `post_exchange_gain_loss_on_payment` | `sale.payment.exchange_gain_loss` | `customer_payments` → `journal_entries` | `customer_payments.exchange_gain_loss ≠ 0`, **relu dans la table** (pas dans `NEW`) |
| 2 | `create_billable_line_on_timesheet_stop` | `project.time.billed` | `project_time_entries` → `invoice_lines` | `invoice_lines.time_entry_id = NEW.id` (la clé que la 301 a posée) |
| 3 | `integrate_pay_recalls_on_payrun` | `payroll.pay_recall.integrated` | `pay_runs` → `payroll_variable_elements` | le lot passe en `processing` **et** des éléments `pay_recall` existent pour lui |
| 4 | `integrate_salary_advances_on_payrun` | `payroll.salary_advance.integrated` | `pay_runs` → `payroll_variable_elements` | idem, avec les éléments `advance_deduction` |
| 5 | `statement_line_ledger_match` | `treasury.statement_line.matched` | `bank_transactions` → `journal_lines` | `bank_transactions.matched` **et** `reconciled_entry_id` **relus dans la table** |

Trois points de doctrine, héritées de la tranche 2 et **appliquées** ici :

1. **N éléments en un passage → lien au niveau du DOCUMENT.** Un rappel de paie
   n'est pas une ligne du lot, et un acompte non plus : les écrire dans
   `amont_ligne_id` produirait un lien que la vue chaîne ne saurait pas résoudre.
   Le payload porte donc `lien_par_ligne = false`, le **décompte** (`elements`)
   et les **identifiants** des documents liés (`recall_ids` / `advance_ids`).
2. **Le compagnon s'exécute APRÈS son maillon.** Tous les déclencheurs sont
   `AFTER` et nommés `zz_l1_*` : PostgreSQL les exécute dans l'ordre ASCII du
   nom, donc après les maillons métier (`create_billable_line`,
   `integrate_pay_recalls`, `post_exchange_gain_loss_on_payment`,
   `statement_line_ledger_match`…). La suite **T10** le **mesure** sur le
   catalogue : aucun déclencheur non-`zz_l1_` ne trie après l'un des cinq.
3. **Le cas ordinaire ne se trace pas.** Un règlement en devise de tenue, un
   temps non facturable, un relevé de cent lignes sans contrepartie : rien à
   tracer, et **aucune trace** — la **315** rend `sans_effet` *possible*, elle n'en
   fait pas un bruit de fond. C'est la distinction que T02, T07 et T09 vérifient.

---

## 2. Les deux défauts que la suite a trouvés dans la migration

Écrire l'acceptation **avant** de croire la migration a payé : les deux
compagnons qui semblaient les plus simples ne fonctionnaient pas du tout, et
l'un des deux ne **s'exécutait** même pas.

| Défaut | Ce qu'il produisait | Ce qui l'a vu | Correction |
|---|---|---|---|
| **le marqueur lu dans `NEW`** (écart de change, appariement bancaire) | le maillon métier pose son marqueur par un `UPDATE` **à l'intérieur de SON déclencheur `AFTER`** : la copie `NEW` de mon compagnon — qui s'exécute après lui, sur la même instruction — **ne le porte pas**. Résultat : **aucun lien jamais posé** sur ces deux effets | suite **316 T01** (`liens=1`… mais le lien était celui de la 310, pas le mien) et **T08** | les deux compagnons **relisent** la ligne (`SELECT … FROM customer_payments / bank_transactions WHERE id = NEW.id`), et cette relecture est écrite en commentaire dans la migration |
| **`min(uuid)`** (rappels et acomptes) | `function min(uuid) does not exist` — le compagnon **levait**, donc l'effet n'était jamais tracé | suite **316 T04** et **T05**, dès leur premier passage | l'aval de référence est le **plus petit identifiant**, obtenu par un tri explicite (`ORDER BY pve.id LIMIT 1`) — même choix annoncé, et **déterministe** pour un rejeu |

Le second est un rappel utile : `CREATE OR REPLACE FUNCTION` **accepte** un corps
qui ne s'exécutera jamais (ici une fonction d'agrégat inexistante sur `uuid`) —
la migration s'applique, la porte G2 reste verte, et **rien ne le dit** avant
qu'un scénario ne le touche. C'est précisément le trou que la règle du dépôt
(« un défaut = un test rouge avant, dans le même commit ») ferme.

---

## 3. Les mesures

| Mesure | Valeur | Où |
|---|---|---|
| Scénarios d'acceptation de la tranche 5, **tous verts** | **12** (T01–T12) | `app/sql/316_chain_l1_candidats_tests.sql`, jouée sur `compta_l1t4` |
| Valeur de vocabulaire ajoutée, prouvée | **`sans_effet`**, 252 **T17** — **17/17 verts** | `app/sql/315_chain_trace_sans_effet.sql`, `252_chain_socle_tests.sql` |
| Contrats d'effet en base après la 316 | **46**, dont **41 constats** de maillon — **41 déclarés, 0 au registre** | porte **G2** (`ci/check_effects_contract.sql`) |
| Compagnons de la tranche | **5** fonctions `SECURITY DEFINER`, **0** exposée à `authenticated`, **5** déclencheurs `AFTER` | 316 (bloc de vérification) et suite **T10** |
| Suites branchées dans la CI | **93 / 93** | porte **G5** (`app/scripts/check-test-suites.mjs`) |
| Migrations sur base **neuve** | **265 succès, 0 erreur** (dont **315** et **316**) | `node run-sql-migrations.mjs`, base `compta_l1t5` |
| Batterie complète sur base neuve | **689 verdicts, 0 rouge**, 84 fichiers de suite rapportant des verdicts | base `compta_l1t5` (suites 102 → 316) |
| Contrôles du dépôt sur base neuve | **12 verts** ; `check_plpgsql` **non exécutable** dans l'image locale (extension `plpgsql_check` absente) — voir §5 | `ci/check_*.sql` |

Les 12 scénarios, dans l'ordre du fichier : gain de change (**T01**), règlement
sans écart (**T02**), écart marqué sans écriture → **`sans_effet`** (**T03**),
rappels (**T04**), acomptes (**T05**), temps facturé (**T06**), temps non
facturable (**T07**), appariement (**T08**), relevé sans contrepartie (**T09**),
structure et ordre des déclencheurs (**T10**), isolation RLS avec contrôle
positif (**T11**), cohérence des avals (**T12**).

---

## 4. Ce que la base neuve a trouvé — et fait corriger

La tranche 5 n'a pas seulement ajouté des effets : elle a **déplacé des
déclencheurs existants dans l'ordre ASCII**, et trois assertions de tranches
antérieures ont rougi **sur base neuve** — pas sur la base de travail, où elles
passaient parce que la mesure y avait été prise avant. C'est exactement ce qu'une
construction neuve est là pour montrer.

| Suite | Ce qui a rougi | Pourquoi (mesuré) | Correction, et pourquoi ce n'est pas un affaiblissement |
|---|---|---|---|
| **310 T10** | « aucun frère métier de même événement ne trie après » | la mesure comptait **tout** déclencheur de nom plus grand, compagnons L1 compris : `zz_l1_statement_line_matched` trie après `zz_l1_bank_reconciliation`, `zz_l1_payment_exchange_gain_loss` après `zz_l1_customer_payment_entry`… — or leur ordre relatif est **sans effet** | le frère « après » exclut désormais les `zz_l1_` (la propriété **« après tout déclencheur métier »** est celle qui garantit que le compagnon voit l'aval). L'étiquette du scénario disait déjà « frère métier » : c'est la **mesure** qui était plus large que son étiquette |
| **311 T09** | `liens=2` (1 attendu) | la ligne de relevé porte maintenant **deux liens légitimes** : celui de la tranche 2 (→ l'encaissement créé) et celui de la tranche 5 (→ la ligne du grand livre, car le rapprochement a aussi marqué une écriture) | le scénario mesure **son effet** (`treasury.bank_transaction.reconciled`) et non « tous les liens du document » — il ne dépendait donc plus de la tranche suivante |
| **311 T11** | `frères avant=13` (14 attendus), `frères après=3` (0 attendu) | deux points : la comparaison exigeait un `tgtype` **identique** (un maillon métier peut porter sur INSERT *et* UPDATE — `create_billable_line`, mesuré 21 — là où le compagnon ne porte que sur INSERT, mesuré 5 : il le précède pourtant), et le frère « après » comptait les compagnons L1 | la propriété devient **« APRÈS tous les deux, et au moins un événement en commun »**, sur les **métiers seuls** — un `BEFORE` n'est pas avant par le nom, il est avant par la phase |

Les trois corrections sont **datées dans les fichiers**, avec le chiffre mesuré et
la raison — comme la tranche 4 l'avait fait pour la suite 311 T11. Aucune n'a été
obtenue en baissant une exigence : dans les trois cas, la mesure a été rendue
**plus juste**, et la garantie « le compagnon s'exécute après son maillon » est
vérifiée plus étroitement qu'avant (elle porte sur les métiers, explicitement).

---

## 5. Les limites, dites

1. **`check_plpgsql` n'a pas tourné** sur la base neuve locale : l'image du
   conteneur n'embarque pas l'extension `plpgsql_check`
   (`extension "plpgsql_check" is not available`). Les onze autres contrôles du
   dépôt sont verts. Ce contrôle doit tourner **en CI** — c'est le seul point de
   la batterie qui n'est pas prouvé ici, et il est **écrit** comme tel.
2. **Deux branches d'anomalie sur trois ne sont pas couvertes par un scénario.**
   `sans_effet` est prouvé sur l'écart de change (**T03** : marqueur non nul, aucune
   écriture). Les branches jumelles — ligne de relevé **rapprochée sans ligne du
   grand livre marquée** (compagnon 5) et rappel **marqué traité sans élément de
   paie** (compagnon 3) — existent dans les migrations, sont argumentées, mais
   **aucun scénario ne les exerce** : il faut un décor où le métier a posé son
   marqueur sans produire l'aval, ce que les suites actuelles ne fabriquent pas.
   Écart **publié**, pas dissimulé : c'est le prochain scénario à écrire.
3. **L'isolation (T11) est mesurée sur UN effet** (l'écart de change) : elle porte
   sur les politiques de `document_links`, `domain_events` et `chain_traces`, les
   mêmes pour les cinq — mais seuls le lien, l'événement et la trace de cet effet
   ont été lus depuis la société voisine.
4. **Le seuil de cohérence (T12) est un plancher** (`liens >= 5` sur base neuve),
   pas un compte par effet : il vérifie qu'aucun aval ne sort de sa société et
   qu'aucun type d'aval étranger n'est employé, sur **tous** les liens des cinq
   effets présents en base.
5. **Ce qui reste de l'inventaire** : sur les 14 maillons non traités de la
   tranche 4, **9 sont des RPC** (lot **L3** : ticket de caisse, avoir de caisse,
   postes de paie, lettrage manuel, dé-lettrage…) — un compagnon ne peut pas s'y
   accrocher — et la **réception de marchandise** demande la réécriture du corps
   du maillon (lot suivant). Les 5 candidats directs de ce document sont, eux,
   **traités**.
