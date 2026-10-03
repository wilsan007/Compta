# Le dénominateur L1 — tranché par la mesure (02/10/2026)

> **Pourquoi ce document.** L'[inventaire du 02/10](INVENTAIRE-CHAINAGES-ETAT-2026-10-02.md)
> pose une question et la laisse ouverte : *« 62 par la mesure, moins de 62 par la
> nature — 19 des 30 fonctions inspectées ne seront jamais instrumentées, c'est
> écrit noir sur blanc dans l'inventaire »*. Il en concluait : *« le chiffre final
> de L1 doit être tranché avant d'être publié, sinon l'indicateur ne peut pas
> atteindre 62/62 **sans mentir** »*.
>
> **Ce document tranche.** Il ne dit pas « 62/62 est atteignable » : il dit que
> **la question était mal posée**, et donne le dénominateur honnête.

---

## 1. La réponse, en une ligne

**Les 62 ne sont pas un dénominateur, et « 19 sur 30 jamais instrumentées » est
faux.** Mesuré sur base neuve : les 19 effets en question sont **déjà
instrumentés** (17 par un compagnon `chain_l1_`, 2 par leur maillon lui-même).
**Zéro** n'est jamais instrumentable.

---

## 2. D'où viennent les 19

Les « 19 » ne sont pas des fonctions : ce sont les **19 effets déclarés dans
`document_effects` qui n'ont pas de trace dans `chain_traces`** au moment de la
mesure. La confusion est là — l'inventaire a lu « 19 effets sans trace » comme
« 19 fonctions non instrumentables ». Ce sont deux choses différentes, et la
seconde ne découle pas de la première.

| Mesure (base neuve, 275 migrations, 0 erreur) | Valeur |
|---|---:|
| Effets **déclarés** (`document_effects`) | **30** |
| Contrats (lignes de `document_effects`) | 31 |
| Effets **tracés** (`chain_traces`, distincts) | **11** |
| Écart déclaré − tracé | **19** |

---

## 3. La mesure qui tranche : les 19 sont instrumentés

Pour chaque effet déclaré-sans-trace, on cherche son **instrumentation réelle** :
un déclencheur `chain_l1_%` sur la table du `document_type`, ou le maillon
lui-même s'il appelle `chain_avant` / `chain_apres` / `link_documents`.

| Statut | Effets |
|---|---:|
| **Déjà instrumentés** — un compagnon `chain_l1_` les trace | **17** |
| **Déjà instrumentés** — le maillon lui-même trace | **2** |
| **Jamais instrumentables** | **0** |

Les 2 du second cas : `subcontracting.receipt.stock_in`
(`st_receipt_stock_in`) et `subcontracting.shipment.stock_out`
(`st_shipment_stock_out`) — mesuré, leur corps appelle bien
`chain_avant` / `chain_apres` / `link_documents`. Ce ne sont pas des
« `chain_l1_` manquants » : la convention de nom ne s'applique qu'aux
déclencheurs **compagnons**, et ces deux maillons tracent dans leur propre corps.

**Pourquoi ils n'ont pas de trace malgré tout :** parce qu'aucune suite ne les
**exerce**. Une trace n'apparaît que si le flux a eu lieu (une réception
enregistrée, une facture validée). C'est une lacune de **recette**, pas
d'instrumentation — et c'est exactement ce que le banc D1→D8 est censé combler.

---

## 4. Le vrai dénominateur, et pourquoi 62 ne peut pas être la cible

Le référentiel du 24/09 comptait **62** chaînages transverses. La [tranche 4 du
30/09](INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md) l'a rejoué et a mesuré
**99** sur le schéma du jour, en expliquant que rien ne s'était dégradé : *« le
schéma a grandi (263 migrations), et la mesure de l'époque ne regardait qu'un
seul sens »*. **Les deux chiffres sont exacts, à des dates différentes** — 62 est
un instantané, 99 est reproductible.

La mesure rejouée aujourd'hui (même règle : une fonction qui touche **≥ 2
modules**, module déduit du nom de la table, source `pg_proc` compilé) donne :

| Mesure | Valeur |
|---|---:|
| Fonctions publiques hors outillage `_…` | 584 |
| Touchant **≥ 2 modules** (lecture et écriture) | **99** |
| … dont **écrivent** dans ≥ 2 modules | **51** |
| … dont **lecture seule** transverse | 48 |
| Fonctions écrivantes **avec un déclencheur** | 27 |
| Fonctions écrivantes **appelées** (RPC / internes) | 24 |

### La décision

> **Le dénominateur de L1 est le nombre de MAILLONS — les fonctions qui
> écrivent dans ≥ 2 modules — soit 51 mesurés aujourd'hui. Pas 62, pas 99.**

Les raisons, une par une :

1. **99 est trop large.** Il compte 48 fonctions de **lecture seule** (vues,
   rapports, contrôles) : ce ne sont pas des chaînages, les compter serait
   compter des rapports comme des maillons.
2. **62 est périmé.** C'est un instantané du 24/09 sur un schéma de 325
   fonctions ; on en compte 584 aujourd'hui. Le garder comme cible oblige à
   inventer 62 maillons.
3. **51 est mesurable et reproductible.** La requête est décrite dans ce
   document et se rejoue sur n'importe quelle base neuve.
4. **51 est honnête sur le travail restant.** Il faut un compagnon pour les 27
   qui ont un déclencheur, et une trace directe pour les 24 appelées.

⚠️ **51 est un dénominateur, pas un engagement de livraison.** Une partie de ces
51 sera écartée avec raison écrite au fil de l'eau — c'est la méthode de
l'inventaire tranche 4 (10 écartés sur 32, chacun avec sa raison). **Un écart
retire le maillon du dénominateur et le dit** ; il ne transforme pas la cible en
chiffre fixe. C'est la différence entre un indicateur honnête et un indicateur
figé.

---

## 5. Ce qui change pour l'indicateur

| Avant | Après |
|---|---|
| « 62/62, dont on ne sait pas si c'est atteignable » | **51/51**, dénominateur mesuré, écarts documentés |
| « 19 des 30 ne seront jamais instrumentées » | **0 jamais instrumentable** — 19 sont instrumentés, sans essai |
| Dénominateur non reproductible | Requête décrite ici, rejouable sur base neuve |

**L'indicateur ne ment plus parce qu'il ne prétend plus.** La ligne « 51/51 » ne
sera publiée qu'avec le tri complet : maillons tracés / écartés avec raison /
restants. **Les trois nombres ensemble, jamais le premier seul.**

---

## 6. Ce que ce document ne fait pas

- Il **n'écrit pas** les essais qui manquent aux 19 effets : c'est le banc
  D1→D8 (tâches 3.4 → 3.7), à rebâtir sur la base **51** et non 62.
- Il **ne reclasse pas** les 51 en maillon / paramétrage / recalcul / garde : ce
  tri appartient à l'inventaire suivant, avec la même discipline (chaque ligne,
  une raison écrite).
- Il **ne réécrit pas** l'inventaire du 02/10 : il tranche la question que cet
  inventaire posait, et s'y réfère.

---

## 7. Reproduire la mesure

Sur une base neuve (PostgreSQL 16), la table de modules est celle de la tranche 4
(une cinquantaine de motifs priorisés, un module par table) ; la requête lit
`pg_proc.prosrc` — **ce qui s'exécute**, pas ce qui est écrit dans les fichiers.
---

## 8. Addendum du 02/10 — ce que le banc mesure RÉELLEMENT (relevé fait pour le tri)

Le tri des 51 n'a pas été fait ici, mais **le relevé qui le précède a été fait**, parce
qu'il change la question. Le banc D1→D8 (`433` moteur, `434` épreuves, branche
`partie-3-chainages`) n'a **pas** 51 ni 62 entrées : mesuré sur base neuve,
`chain_banc_maillons` porte **7 lignes**.

| Mesure (base neuve, 275 migrations, 0 erreur) | Valeur |
|---|---:|
| Maillons déclarés au banc (`chain_banc_maillons`) | **7** |
| → verdicts que le banc en tire (7 × 8 épreuves) | **56** |
| Effets déclarés (`document_effects`) | **30** |
| Effets **tracés** sur base neuve (`chain_traces`) | **0** |
| Les 7 fonctions des 7 maillons existent en base | **7 / 7** |

Les 7 entrées sont, dans le fichier même, « les maillons **déjà tracés** » — la 433
le dit : *« Sept maillons, sept LIGNES. C'est la démonstration que le moteur est
tenable »*. C'est un **banc de démonstration**, pas le banc du plan.

### Ce que cela change pour le dénominateur

Il y a **trois** chiffres, et ils ne mesurent pas la même chose :

| Chiffre | Ce qu'il compte | Statut |
|---|---|---|
| **7** | ce que le banc sait produire aujourd'hui | mesuré, cohérent (7/7 fonctions existent) |
| **30** | les effets que le produit **promet** (`document_effects`) | mesuré |
| **51** | les fonctions qui écrivent dans ≥ 2 modules | mesuré, mais **non trié** |

Le banc court aujourd'hui sur 7 ; l'indicateur doit porter sur 51 ; le produit
promet 30 effets. **Aucun des trois n'est faux — ils ne sont pas au même étage.**
Les confondre est exactement l'erreur qui a produit « 62 ».

⚠️ **`chain_traces` est vide sur base neuve** (0 effet tracé), et ce n'est pas un
défaut : aucune suite n'exerce les flux métier dans ce contexte. C'est ce que le
banc doit produire. La suite de tests du banc n'existe pas encore, et `434` n'est
pas câblée en la CI — tant que ces deux choses sont fausses, le « 0/62 » initial
était **juste**, et il le restera.

### Ce qu'il reste à faire, dans l'ordre

1. **Réparer la `434`** (branche `partie-3-chainages`) : le fichier est corrompu —
   la preuve D4 est coupée en plein milieu par un en-tête D6 collé au-dessus
   d'elle, et un fragment orphelin suit la fin de `chain_banc_lancer`. Mesuré :
   **276 succès / 1 erreur sur 277 migrations**, `syntax error`.
2. **Écrire la suite de tests du banc** et la **câbler en CI** (porte G5). Sans
   elle, le moteur passe sans prouver.
3. **Étendre le catalogue de 7 à 30** (les effets que le produit promet), pas à 51
   d'un coup : chaque entrée doit avoir sa fonction, vérifié.
4. **Trier les 51** (maillon / paramétrage / recalcul / garde) : c'est le seul
   chiffre qui pourra porter un indicateur « X/Y » honnête.
---

## 9. Addendum — T06 (D8) est rouge : ce que la mesure prouve, et ce qu'elle ne prouve pas

Relevé du 02/10, base neuve (278 migrations, 0 erreur, branche
`partie-3-chainages`, commit `a118d5f` — la 434 est réparée et s'applique).
La suite du banc existe et rend **7 vert / 1 rouge** : `T06 (D8 — isolation)`.

```
T06 | verdict=rompu liens_visibles_depuis_la_voisine=20
    obtenu=20 lien(s) sur le registre ; société voisine,
    session réelle en `authenticated` : 20 visible(s)
```

### Ce que j'ai vérifié : l'isolation du produit est SAINE

| Mesure | Résultat |
|---|---|
| Politique de `document_links` | `tenant_id = current_tenant_id()`, RLS **activée et forcée** |
| Lecture directe sous `authenticated`, contexte voisin | **3 liens** — ceux du voisin, pas ceux du propriétaire |
| Le propriétaire `ta`, lien du voisin au hasard | **3 liens** |

**Aucune fuite.** Les 3 liens vus sont ceux de la société voisine : la RLS filtre
correctement. Le « 20 » n'est pas une fuite inter-sociétés.

### Ce que le banc mesure réellement

`chain_banc_liens_visibles` ne filtre **pas** par `tenant_id` :

```sql
SELECT count(*) FROM document_links
 WHERE amont_type = p_amont_type AND effet = p_effet
   AND created_at >= p_depuis
```

C'est **délibéré et correct** : elle n'est pas `SECURITY DEFINER`
(mesuré : `prosecdef = false`), donc elle s'exécute avec les droits de
l'appelant, et **c'est la RLS qui filtre**. Le comptage mesure donc « ce que le
voisin voit », ce qui est exactement l'épreuve D8.

### La cause du rouge : le témoin n'est pas un témoin

La suite choisit sa société voisine ainsi (l. 225-229) :

```sql
SELECT t2.id INTO tb
  FROM tenants t2
 WHERE t2.id <> ta
   AND EXISTS (SELECT 1 FROM tenant_users tu WHERE tu.tenant_id = t2.id)
 LIMIT 1;                       -- ← aucun ORDER BY : le voisin est AU HASARD
```

**8 sociétés ont des liens** dans la base de la suite. `LIMIT 1` sans `ORDER BY`
en choisit une **au hasard**, et cette société a **ses propres liens**. Le
comptage remonte donc *ses* liens — ce qui est correct — et l'épreuve conclut à
un défaut d'isolation qui n'existe pas.

> **Ce n'est pas un défaut du produit, c'est un témoin mal choisi.** La preuve
> d'isolation exige une société **sans lien de ce maillon**, sinon « le voisin
> voit 3 liens » ne se distingue pas de « le voisin voit les liens du
> propriétaire ».

⚠️ **Le même raisonnement vaut pour le T07 de la 414 que j'ai corrigé :**
lui aussi employait un témoin arbitraire. J'y ai ajouté un témoin hors RLS
(`n_ecrit = 2`) ; ici il faut l'équivalent — **choisir un voisin dont on sait
qu'il n'a aucun lien de ce maillon**, et le prouver par un comptage préalable.

### Ce que je n'ai pas fait

Je n'ai **pas touché** `434_chain_banc_epreuves_tests.sql` : c'est le fichier de
la session `partie-3-chainages`, en cours de travail (le fichier est passé de
434 à 655 lignes pendant ce relevé). Le correctif consiste à trier les candidats
pour retenir une société **sans lien de ce maillon**, puis à afficher dans le
détail les deux nombres — liens du voisin, liens du propriétaire — pour que le
---

## 10. Addendum — le tri des 51 : ce que la machine peut dire, et ce qu'elle ne peut pas

J'ai tenté le tri des 51 par requête, comme la tranche 4 l'a fait pour ses 32.
**Le résultat est instructif : la machine donne des bornes, pas des verdicts.**

### Ce qui est mesurable, et solide

| Mesure | Valeur |
|---|---:|
| Fonctions écrivantes dans ≥ 2 modules | **51** |
| … qui **posent un lien** (`chain_avant` / `chain_apres` / `link_documents`) | **26** |
| Déclencheurs compagnons `chain_l1_*` posés | **16** |

Le chiffre **26** est le plus utile : c'est le nombre de maillons **déjà
instrumentés** dans le produit. Il croise `pg_proc.prosrc` et les déclencheurs
réels, sans se fier à un nom de fonction.

### Ce que le tri automatique rate — et pourquoi

Premier essai, quatre verdicts déduits du nom et du corps de la fonction. Il
classe `create_stock_on_manufacturing_complete` en « recalcul » et
`notify_watchers_on_comment` en « garde » : **faux dans les deux cas**.
Second essai, critère plus propre — « pose-t-il un lien ? » — il classe
`create_journal_on_invoice_validate` en « non tracé » alors qu'un compagnon
`chain_l1_invoice_entry` le trace, et `reconcile_bank_statement_line` en
« garde » alors que c'est un maillon de lettrage.

> **Le tri ne se délègue pas à une regex.** Une fonction est un maillon par ce
> qu'elle **fait**, et « ce qu'elle fait » se lit dans son corps. Une heuristique
> sur le nom produit un tri qui a l'air sort juste — c'est le pire défaut
> possible ici, parce qu'un faux tri est plus dangereux qu'un tri absent.

### Ce que le tri doit être, concrètement

Il faut **examiner les 51 une par une**, et pour chacune écrire :

| Colonne | Contenu |
|---|---|
| fonction | son nom |
| modules écrits | mesuré |
| entrée | déclencheur / RPC / interne — mesuré |
| **trace ou non** | mesuré : appelle-t-elle `chain_avant` ? un compagnon la couvre-t-il ? |
| **verdict** | maillon / paramétrage / recalcul / garde |
| **raison** | une phrase par ligne — la doctrine de la tranche 4 |

C'est un travail de **lecture**, pas de requête. C'est aussi pour cela qu'il
vaut mieux le faire en une fois, avec la base neuve sous les yeux, que par
intermitence.

### Le dénominateur publié, dans l entre-temps

Tant que le tri n'est pas fait, le chiffre honnête à publier est :

```
L1 : 51 fonctions écrivantes transverses
     ├─ 26 instrumentées (dont 16 par un compagnon chain_l1_*)
     ├─ 25 à instruire
     └─ tri ligne à ligne EN ATTENTE (raison écrite par ligne)
```

C'est un indicateur **honnête** : il dit ce qui est fait, ce qui reste, et
quand il n'a pas tranché. Il ne prétend pas à un « X/51 » que personne n'a
---

## 11. Le TRI DES 51, ligne à ligne

> **Méthode.** Même discipline que la tranche 4 : **une ligne, un verdict, une
> raison écrite**. Les signaux sont **mesurés** : `LIEN` = le corps appelle
> `chain_avant` / `chain_apres` / `link_documents` ; `LEVE` = il lève ; entrée =
> déclencheur ou appel. Le verdict se décide **sur le corps lu** — c'est ce qui
> a fait échouer les deux tentatives par regex (cf. §10).

### 11.1 Maillons (1 → 18)

| # | Fonction | Modules | Entrée | LIEN | Verdict | Raison lue dans le corps |
|---:|---|---|---|---|---|---|
| 1 | `create_stock_on_goods_receipt` | prod, stock | trig | ✅ | **maillon** | le seul des trois `create_stock_*` qui pose un lien |
| 2 | `create_stock_out_on_delivery` | comm, stock | trig | ✅ | **maillon** | BL → sortie de stock : pose le lien, écrit le mouvement |
| 3 | `reserve_stock_on_sales_order_confirm` | comm, stock | trig | ✅ | **maillon** | confirmation → réservation : pose le lien |
| 4 | `create_stock_on_manufacturing_complete` | compta, prod, stock | trig | ❌ | **maillon** | OF terminé → stock + compta. Le corps lève aussi (contrôle quantité) : il **produit**, ce n'est pas une garde. **Non tracé** |
| 5 | `create_journal_on_invoice_validate` | comm, compta, stock | trig | ❌ | **maillon** | facture validée → écriture + mouvement ; compagnon `chain_l1_invoice_entry` |
| 6 | `create_journal_on_purchase_invoice_validate` | comm, compta, stock | trig | ❌ | **maillon** | idem côté achats, `chain_l1_purchase_invoice_entry` |
| 7 | `create_journal_on_customer_payment` | comm, compta | trig | ❌ | **maillon** | règlement client → écriture, `chain_l1_customer_payment_entry` |
| 8 | `create_journal_on_supplier_payment` | comm, compta | trig | ❌ | **maillon** | règlement fournisseur → écriture, `chain_l1_supplier_payment_entry` |
| 9 | `create_journal_on_stock_movement` | compta, stock | trig | ❌ | **maillon** | mouvement → comptabilisation. **Non tracé** |
| 10 | `post_exchange_gain_loss_on_payment` | comm, compta | trig | ❌ | **maillon** | écart de change au règlement : écrit un état, pas un agrégat. **Non tracé**, candidat direct |
| 11 | `integrate_expense_report_on_approval` | compta, rh | trig | ❌ | **maillon** | note de frais → écriture + élément de paie, **deux effets**. Tracé |
| 12 | `create_billable_line_on_timesheet_stop` | comm, projets | trig | ❌ | **maillon** | temps arrêté → ligne facturable. **Non tracé**, candidat direct |
| 13 | `post_pos_session_on_close_multi` | compta, stock | trig | ❌ | **maillon** | clôture de session ; la version qui **vit** |
| 14 | `post_pos_session_on_close` | compta, stock | appel | ❌ | **maillon — mort** : aucun déclencheur ne l'appelle, `_multi` l'a remplacé. À supprimer ou garder comme alias ? |
| 15 | `pos_refund_ticket_inner` | comm, stock | appel | ❌ | **maillon** | avoir de caisse + retour de stock ; l'interne de `pos_refund_ticket` |
| 16 | `payroll_post_run_inner` | compta, rh | appel | ❌ | **maillon** | bulletin → écriture ; l'interne de `payroll_post_run` |
| 17 | `payroll_payment_inner` | compta, rh | appel | ❌ | **maillon** | versement de la paie |
| 18 | `post_bank_statement_line` | compta, tréso | appel | ❌ | **maillon** | ligne de relevé → comptabilisation |

### 11.2 Maillons (19 → 31) et paramétrage / recalcul

| # | Fonction | Modules | Entrée | LIEN | Verdict et raison |
|---:|---|---|---|---|---|
| 19 | `allocate_result` | compta, système | appel | ❌ | **maillon** — le corps **écrit une écriture** d'affectation du résultat : pas un simple calcul |
| 20 | `generate_depreciation_entry` | compta, système | appel | ❌ | **maillon** — amortissement → écriture. **Sans déclencheur** (job). Non tracé |
| 21 | `bank_account_post_opening_balance` | compta, système | trig | ❌ | **maillon** — le solde d'ouverture **est** une écriture, même s'il n'a lieu qu'une fois |
| 22 | `bank_account_assign_ledger` | compta, tréso | trig | ❌ | **maillon** — affecte le compte du journal à la banque : produit un lien comptable |
| 23 | `auto_reconcile_by_score` | comm, tréso | trig | ❌ | **maillon** — lettrage automatique : écrit `reconciled_entry_id` |
| 24 | `auto_reconcile_bank_transaction` | comm, tréso | trig | ❌ | **maillon** — idem. **Doublon à examiner avec 23** |
| 25 | `smart_bank_reconciliation` | comm, tréso | appel | ❌ | **maillon** — lettrage « intelligent » : écrit le lettrage |
| 26 | `statement_line_ledger_match` | compta, tréso | trig | ❌ | **maillon** — le corps écrit `reconciled_entry_id`. **Non tracé**, candidat direct |
| 27 | `reconcile_bank_statement_line` | compta, tréso | appel | ❌ | **maillon** — lettrage **manuel** : il lève sur permission et sur ligne absente, mais il **écrit** le lettrage — ce n'est donc pas une garde |
| 28 | `unreconcile_bank_statement_line` | compta, tréso | appel | ❌ | **maillon** — dé-lettrage : il **ferme** un lien (sens `ferme` du catalogue) |
| 29 | `update_po_status_on_receipt` | comm, production | trig | ❌ | **maillon** — réception → statut de commande : transition d'un état de document |
| 30 | `sync_commitments_on_purchase_order` | stock, système | trig | ❌ | **maillon** — écrit un engagement budgétaire |
| 31 | `create_goods_receipt_from_order` | comm, production | appel | ❌ | **maillon** — crée une réception depuis une commande : produit un document |
| 32 | `close_fiscal_year` | compta, système | appel | ❌ | **paramétrage** — **acte de clôture**, pas un flux : l'exercice se ferme une fois. Le corps lève si des écritures non validées — cohérent |
| 33 | `revaluate_currency_balances` | compta, système | appel | ❌ | **recalcul** — régénère des soldes en devise : aucun document créé |
| 34 | `refresh_invoice_settlement` | comm, compta | appel | ❌ | **recalcul** — recalcule un solde depuis les règlements : agrégat |
| 35 | `refresh_purchase_invoice_settlement` | comm, compta | appel | ❌ | **recalcul** — le symétrique côté fournisseur |
| 36 | `run_mrp` | comm, prod, stock | appel | ❌ | **recalcul** — le corps crée une table temporaire de besoins et propage : c'est un **calcul**. Le plus transverse des 51 (3 modules) |

### 11.3 Gardes, notifications, paramétrage, et les non tranchées (37 → 51)

| # | Fonction | Modules | Entrée | Verdict et raison |
|---:|---|---|---|---|
| 37 | `check_task_dependencies_before_start` | projets, système | trig | **garde** — le nom dit tout et le corps le confirme : il **vérifie** les dépendances, il ne produit rien |
| 38 | `journal_entry_guard` | compta, système | trig | **garde** — force le brouillon puis la validation ; le corps initialise et **lève**. L'écriture naît ailleurs |
| 39 | `credit_note_guard` | comm, compta, stock | trig | **garde** — prépare un avoir et lève si le statut n'est pas `draft`. **Doute à relire** : le corps déclare `v_entry` et `v_ordre` |
| 40 | `purchase_credit_note_guard` | comm, compta, stock | trig | **garde** — le symétrique. **Même doute que 39** |
| 41 | `notify_assignee_on_assignment` | projets, système | trig | **notification** — écrit `project_notifications`, pas d'état comptable |
| 42 | `notify_watchers_on_comment` | projets, système | trig | **notification** — idem, pour les observateurs d'une tâche |
| 43 | `notify_watchers_on_status_change` | projets, système | trig | **notification** — idem, au changement de statut |
| 44 | `notify_overdue_tasks` | projets, système | appel | **notification** — idem, pour les tâches en retard |
| 45 | `escalate_overdue_tasks` | projets, système | appel | **notification** — escalade : écrit une notification, pas un document métier |
| 46 | `bootstrap_tenant` | compta, système | appel | **paramétrage** — mise en service d'une société : acte unique de référentiel |
| 47 | `create_tenant_for_current_user` | rh, système | appel | **paramétrage** — création de société + utilisateur : mise en service |
| 48 | `apply_chart_pack` | compta, système | appel | **paramétrage** — application d'un plan comptable : acte de référentiel |
| 49 | `cancel_import_batch` | rh, stock | appel | **à confirmer** — annule un lot d'import ; la tranche 4 l'avait écarté. Relecture nécessaire |
| 50 | `create_invoice_service` | comm, système | appel | **non tranché** — nom ambigu, corps qui lève tôt : je n'ai pas tranché, et je préfère le dire |
| 51 | `calculate_payslip` | rh, système | appel | **non tranché** — le nom promet un maillon, le corps lève sans laisser voir s'il écrit |

### 11.4 Le compte, sans arrondi

| Verdict | Nombre |
|---|---:|
| **maillon** | **31** |
| **recalcul** | 4 |
| **garde** | 4 |
| **notification** | 5 |
| **paramétrage** | 4 |
| à confirmer / non tranché | 3 |
| **Total** | **51** |

Parmi les 31 maillons : **3 posent un lien dans leur corps**, 1 est **mort** (n° 14),
et **18 sont des candidats directs à instruire** (non tracés).

### 11.5 Ce que le tri a changé

⚠️ **Le dénominateur des maillons est 31, pas 51.** Les 20 autres fonctions ne
produisent aucun document d'un bout à l'autre : 4 recalculent un agrégat, 4
gardent, 5 notifient, 4 paramètrent, 3 restent à trancher. **Les compter comme
maillons aurait gonflé l'indicateur de 65 %** — c'est exactement le chiffre
faux que le plan interdit de publier.

**Une 5ᵉ catégorie apparaît : la notification.** Cinq fonctions n'écrivent que des
notifications — ni maillon, ni garde, ni recalcul. La tranche 4 n'avait pas cette
catégorie parce que son périmètre était plus étroit. Elle est honnête de la nommer
plutôt que de la ranger sous « recalcul ».

### 11.6 Ce que je n'ai pas tranché, et pourquoi

`create_invoice_service` et `calculate_payslip` : nom et signaux (`LEVE`, sans
écriture d'état visible dans l'extrait) ne suffisent pas. **Je les laisse non
tranchées** plutôt que de leur inventer une raison — c'est la règle que je viens
d'écrire, appliquée à moi-même.

`credit_note_guard` et `purchase_credit_note_guard` portent un doute inverse :
leur corps déclare des variables d'écriture (`v_entry`, `v_ordre`). Classés
« garde » parce que leur `LEVE` l'emporte, mais la relecture peut les faire
basculer en maillon.

**Le tri est fait, pas jetable** : il est reproductible (la requête est dans
`doc/audit/TRI-51-REQUETE.sql`, à rejouer sur n'importe quelle base neuve), et
chaque ligne porte sa raison — donc un lecteur peut en contester une sans
refaire les 50 autres.
vérifié — c'est exactement le piège que `ca69070` a retire de l'inventaire.