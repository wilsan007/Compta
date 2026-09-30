# Vague L7 — les contrats d'effet déclarés — 30 septembre 2026

> **Objet.** Poser le lot **L7** du
> [plan d'implémentation des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md) :
> la doctrine **M-05** (« chaque type de document déclare son effet, y compris
> aucun ») et son indicateur — **contrats d'effet déclarés : 0 % → 100 %**.
> **État d'entrée.** Le socle (252) avait la table et la règle (`chain_autorise`
> est fermé par défaut) ; la porte **G2** (L2) avait le contrôle ; il manquait les
> **déclarations**. Conséquence mesurée sur la base de test, après la batterie :
> **1 132 traces `tolere`** (« contrat manquant ») pour **1 117 `applique`** —
> chaque exécution d'un effet non déclaré écrivait **deux** lignes dans
> `chain_traces`. Le registre de la porte G2 portait les **25 défauts** de L1
> (14 effets + 11 couples) et ne pouvait que rétrécir.
> **Livré.** Migration **313** (les **14 contrats** standard, un drapeau par
> mesure), suite d'acceptation **313** (**11 scénarios**), **registre de G2 vidé**
> (0 ligne — la porte l'a exigé, ses 25 entrées ont été refusées puis retirées
> dans le même commit), et **trois assertions de la suite 310 adaptées** (leur
> verdict attendu a changé parce que le comportement a changé — §5).

---

## 1. Le défaut, et ce qu'il coûtait

`chain_avant` est l'entrée de chaque maillon. Sans contrat déclaré, il fait deux
choses : il trace `tolere` (avec le message nominatif du maillon) **puis** rend
`true` — l'effet est produit quand même, parce que le mode par défaut est
`observe`. C'est voulu (une société ne doit pas être bloquée par une déclaration
manquante), mais cela produisait, sur une batterie complète :

| Trace | Avant L7 | Après L7 |
|---|---:|---:|
| `applique` | 1 117 | **1 120** |
| `tolere` | **1 132** | **5** |
| `ignore` | 4 | 4 |

Les **5** traces `tolere` qui restent sont **toutes provoquées délibérément** :
`effet.non.declare` (2, l'effet synthétique de la suite 252 qui éprouve les modes),
`sale.invoice.generated_entry` (2, les scénarios 310/313 qui **éteignent** le
contrat pour une société) et `cycle.avant` (1, l'effet synthétique de la 312).
**Aucun maillon métier ne trace plus « sans contrat »** : c'est la mesure qui dit
que le lot est fini, pas l'intention.

Deux autres conséquences, plus graves que le bruit de mesure :

1. **Le mode `refuse` était inutilisable.** `chain_autorise` rend faux pour tout
   ce qui n'est pas déclaré : une société qui passait en `refuse` bloquait
   **tous** ses chaînages, y compris les 14 légitimes. Le drapeau `observe →
   avertit → refuse` (posé par la 252) n'avait donc aucun état intermédiaire
   utilisable ;
2. **Rien n'était nommé.** Le plan le dit ainsi : ce qui n'est pas déclaré doit
   être **déclaré**, pas deviné — et la vue chaîne (lot L6/L5) ne peut pas
   afficher un effet que personne n'a nommé.

---

## 2. Les 14 contrats, et la mesure de chaque drapeau

Les **couples** (document, événement, effet) ne sont pas choisis : ils sont
**extraits du code** — les appels à `chain_avant` pour onze d'entre eux, et pour
les trois effets des quatre maillons réécrits par la 311 (qui n'appellent que
`link_documents`), les tables document/événement que la 311 elle-même déclare
(`sales_orders/confirmed`, `st_shipments/shipped`, `st_receipts/received`).

Les **drapeaux** viennent de la mesure des **écritures réelles** de chaque maillon
métier (relevé des tables cibles de ses `INSERT` / `UPDATE` / `DELETE` sur
`pg_proc`) :

| Contrat | `ecrit_comptable` | `touche_stock` | `journal_code` | `reversible` | `obligatoire` |
|---|---|---|---|---|---|
| `invoices/validated/sale.invoice.generated_entry` | ✅ | — | `VT` | ✅ | ✅ |
| `credit_notes/validated/sale.credit_note.generated_entry` | ✅ | — | `VT` | ✅ | ✅ |
| `supplier_payments/recorded/purchase.payment.generated_entry` | ✅ | — | *calculé* | ✅ | ✅ |
| `customer_payments/recorded/sale.payment.generated_entry` | ✅ | — | *calculé* | ✅ | ✅ |
| `bank_accounts/created/treasury.bank_account.journal` | — | — | — | **non** | — |
| `bank_accounts/created/treasury.bank_account.account` | — | — | — | **non** | — |
| `sales_orders/confirmed/sale.order.reserved` | — | ✅ | — | ✅ | — |
| `delivery_notes/shipped/sale.delivery.stock_out` | — | ✅ | — | ✅ | — |
| `st_shipments/shipped/subcontracting.shipment.stock_out` | — | ✅ | — | ✅ | — |
| `st_receipts/received/subcontracting.receipt.stock_in` | — | ✅ | — | ✅ | — |
| `pos_sessions/closed/pos.session.closure` | ✅ | ✅ | — | **non** | ✅ |
| `bank_transactions/reconciled/treasury.bank_transaction.reconciled` | — | — | — | ✅ | — |
| `manufacturing_orders/completed/production.order.generated_entry` | ✅ | — | — | ✅ | ✅ |
| `manufacturing_orders/completed/production.order.stock_in` | — | ✅ | — | ✅ | — |

**Les trois « non réversibles » ne sont pas des aveux, ce sont des déclarations
motivées** (point 4 de la définition de « terminé », §4.1 du plan) :

* les **deux lignes de trésorerie** sont du **référentiel** (journals, plan
  comptable) : elles se désactivent, elles ne s'extournent pas ;
* la **clôture de caisse** est **inaltérable** (vagues W2/W3) : elle se corrige
  par une écriture de régularisation, elle ne se défait pas.

**La décision d'écart, écrite** : le plan prévoyait `journal_code` pour toutes les
écritures. Mesuré : seuls `create_journal_on_invoice_validate` et
`credit_note_guard` portent un code **littéral** (`VT`) ; les autres le
**calculent** (compte de trésorerie, sens du règlement). La colonne vaut donc
`NULL` pour eux, avec le motif dans la note du contrat — plutôt qu'un code
inventé. C'est écrit dans la migration, pas caché.

---

## 3. Ce qui agit, et ce qui déclare seulement

**Mesuré, et c'est le point le plus important du lot** :

| Drapeau | Lecteur dans le code | Ce qu'il fait |
|---|---|---|
| **`actif`** | **`chain_autorise`** (le seul) | il décide — c'est lui qui fait disparaître les traces `tolere` et qui arme le mode `refuse` |
| `ecrit_comptable`, `journal_code`, `touche_stock`, `touche_paie`, `reversible`, `obligatoire` | **aucun** | ils **déclarent** ce que la porte G2 confronte au réel et ce que les écrans du lot L5 publieront |

Vérifié par requête sur `pg_proc` : une seule fonction de `public` mentionne
`document_effects` **et** un de ses drapeaux — `chain_autorise`, pour `.actif`.
Les six autres n'ont **aucun lecteur**. Le scénario **D11** de la suite mesure
cela et l'imprime : *un drapeau sans lecteur ne protège rien*, et le jour où l'un
d'eux sera lu, le compte changera et il faudra le dire. C'est la seule manière
honnête de livrer un schéma déclaratif sans laisser croire qu'il contraint.

---

## 4. Les mesures, et la non-régression

| Mesure | Avant la 313 | Après la 313 | Où c'est prouvé |
|---|---|---|---|
| Contrats déclarés | **0** | **14** | 313 D01, D08 |
| `chain_autorise` pour les 14 | **faux** | **vrai** | 313 D02 |
| Traces `tolere` sur une facture validée | **1** (+ 1 `applique`) | **0** (+ 1 `applique`) | 313 D03, 310 T01 |
| Registre de la porte G2 | **25 lignes** | **0** | `check_effects_contract` |
| Effets déclarés **jamais appelés** | — | **0** | `check_effects_contract` (contrats en base : 14) |
| Mode `refuse` | bloquait **tout** | bloque **ce qui n'est pas autorisé** | 313 D05 |
| Base neuve | 261 migrations | **262 migrations, 0 erreur** | ce document |

**Non-régression rejouée sur base neuve** (migrations, puis les 11 contrôles,
puis les suites — l'ordre de la CI) : **16 suites, 155 scénarios verts** —
`252` 16, `310` 15, `311` 12, `312` 12, **`313` 11**, `230` 5, `180` 22, `192` 15,
`210` 6, `213` 6, `229` 6, `302` 8, `222` 5, `277` 5, `281` 8, `170` 3/3.
Les 11 contrôles permanents du dépôt sont verts, dont `check_effects_contract`
(0 effet appelé sans contrat, 0 au registre), `check_bt_grid` et
`check_chain_performance`. Le registre `ci/expected_failures.sql` reste **vide**.

---

## 5. Trois assertions de la suite 310 ont changé — et pourquoi c'est plus fort

Quand l'état mesuré change **par conception**, les tests qui le mesuraient doivent
changer aussi. C'est arrivé pour trois scénarios de la suite 310 (tranché 1), et
chacun porte désormais la trace de son ancien verdict :

| Scénario | Avant la 313 | Après la 313 | Pourquoi c'est plus fort, pas plus faible |
|---|---|---|---|
| **T01** | `tolere = 1` **et** `applique = 1` | `tolere = 0`, `applique = 1` | il mesure le **contrat en vigueur** : une seule trace, et le détail publie `tolere=0` |
| **T11** | le message du contrat manquant, sur un effet jamais déclaré | le même message, sur un effet **éteint pour la société** | il éprouve le seul chemin qui reste — celui qu'un client empruntera — au lieu d'un état qui n'existe plus |
| **T12** | « sans contrat » puis « avec contrat » | contrat **éteint** puis **rallumé** (`actif`) | il teste le drapeau qui **agit** (mesuré en D11), pas une absence de ligne |

Le fichier 310 conserve les deux verdicts dans ses commentaires (⚠️ « verdict
attendu changé le 30/09/2026 par le lot L7 ») et dans son en-tête, et la suite 313
prend la relève sur les propriétés neuves. **Aucune assertion n'a été supprimée** :
trois ont été réécrites sur l'état réel.

---

## 6. Les limites, dites

* **Les déclarations portent sur les 14 effets tracés, pas sur les 62 chaînages.**
  Les 32 chaînages non encore nommés n'ont pas de contrat : dès qu'un maillon les
  appellera, la porte **G2** cassera la construction — c'est ce qu'on lui demande,
  et c'est la tranche suivante de L1 qui les nommera.
* **La confrontation « réel vs déclaration » est faite par exécution pour deux
  effets** (un comptable : D06 ; un de stock : D07). Les douze autres demandent
  leurs douze décors métier. Une première version confrontait la déclaration au
  **code** (`pg_proc`) : elle a été **retirée** parce qu'elle produisait de faux
  verdicts — le déclencheur *frère* d'un effet peut écrire plus que l'effet, et
  `pos_sessions` a un maillon `BEFORE` là où son compagnon est `AFTER` (mesuré).
  La confrontation par exécution des douze autres est du lot **L3**.
* **Six drapeaux sur sept n'ont aucun lecteur** (§3) : ils informent, ils ne
  contraignent pas encore.
* **Le mode `refuse` devient utilisable, mais rien ne l'active.** Aucune société
  ne passe en `refuse` dans ce lot : c'est un geste d'exploitation
  (`chain_set_enforcement`), mesuré par la 252 (T15) et éprouvé par la 313 (D05),
  pas décidé ici.
* **La trace d'un refus ne survit toujours pas au rollback** : `chain_avant` écrit
  la trace `refuse` **puis** lève l'exception, et la transaction annule les deux.
  Limite transactionnelle de PostgreSQL, dite par la 252 (§5) et reconstatée par la
  VAGUE-L1 ; la 313 ne la change pas.
* **`plpgsql_check` n'a pas été exécuté localement** (extension absente du
  conteneur) : la CI le lance sur toutes les fonctions — et la 313 n'en crée
  aucune, elle n'écrit que des lignes.

---

## 7. Ce que la suite doit produire

1. **L1 — tranche suivante** : les **32 chaînages non encore nommés**
   ([inventaire](INVENTAIRE-CHAINAGES-L1-2026-09-29.md) §3) — chacun devra arriver
   **avec son contrat**, sinon la porte G2 casse la construction ;
2. **L3 — les 62 maillons** : poser `chain_avant` là où le cycle de vie le permet
   (le geste de fermeture est écrit dans la 312 §8) et étendre la confrontation
   par exécution aux douze effets qui attendent leur décor ;
3. **L4 — l'indice de cohérence** (20 invariants) et le banc sur copie de
   production, qui remplacera la mesure locale du banc **G6** ;
4. **L5 — les écrans** : c'est là que les six drapeaux déclaratifs trouveront leur
   lecteur — et le tableau de bord des **refus** devra lire le message remonté au
   client, puisque la trace ne survit pas au rollback (§6).


