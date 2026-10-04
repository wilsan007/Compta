# Vague L3 — tranche 1 : les chemins d'annulation ferment leurs liens — 2 octobre 2026

> **Objet.** Tenir le reste que la 319 avait nommé en toutes lettres : « il
> n'appelle pas le cycle du lien (`chain_lien_fermer`) sur le chemin
> d'annulation. Aucun maillon ne le fait encore — **c'est le reste de L3** » — et
> le geste que le §8 de la 312 avait écrit à l'avance pour les maillons
> (« `chain_liens_fermer` au moment de l'annulation, puis le maillon reprend son
> cours »). C'est la **première tranche du lot L3** : elle ne touche ni les neuf
> maillons RPC, ni le banc d'épreuves D1→D8 (tranches 2 et 3, §6).
> **Livré.** Migration
> [320](../../app/sql/320_chain_lien_fermetures.sql) : **trois déclencheurs
> compagnons `zz_l3_`** (un par chemin d'annulation qui **contrépasse** un effet
> déjà tracé), **une réécriture de corps** — la seule du fichier — qui rend son
> **entrée** au maillon des réservations, et suite d'acceptation
> [320](../../app/sql/320_chain_lien_fermetures_tests.sql) : **8 scénarios**.
> Câblage CI, et **une assertion de la suite 311 précisée** (T02), datée et
> motivée — la doctrine du dépôt pour un verdict que le monde a rendu plus fort.
> ⚠️ **Historique, dit** : cette tranche a été portée par le commit `e5bb05a`,
> dont le message décrit le correctif voisin (le filtre analytique) — l'entrée
> est ici, datée, comme le dépôt l'exige d'une trace qui ne dit que ce qui était
> vrai au moment de sa publication.

---

## 1. Le défaut, mesuré — un cycle de vie que personne n'utilisait

La 312 a donné au lien son **cycle de vie** (`actif` → `remplace` | `rompu`,
avec date, motif et auteur), rendu l'index d'idempotence **partiel** (seuls les
liens actifs sont uniques), compté les **tours** et fait redevenir **vrai**
`chain_avant` après une fermeture. Le prérequis était en place — et **rien ne
l'utilisait** :

| Mesure (base compilée, avant la 320) | Valeur |
|---|---|
| Fonctions dont le corps mentionne `chain_lien_fermer` / `_rompre` / `_remplacer` | **2** — et ce sont les deux portes de la 312 elle-même (`chain_lien_remplacer`, `chain_lien_rompre`) |
| Maillons métier qui ferment leurs liens à l'annulation | **0** |

La conséquence est un **mensonge silencieux**, et il était nommé depuis la 319 :

* une **commande annulée** gardait ses liens `actif` alors que ses réservations
  venaient d'être **libérées** (STK-02c) ;
* un **bon de livraison annulé** gardait le sien alors que sa sortie de stock
  venait d'être **contrepassee** (253) ;
* une **réception annulée** gardait les siens — posés **par ligne** par la 319 la
  veille — alors que l'entrée venait d'être **contrepassee** (251).

Ce que ce mensonge coûte, mesuré par la suite 320 (T01) : `chain_integrity_ok`
(M-03) rend **vrai** sur un effet retiré — l'annulation d'une pièce « intacte »
ne peut donc pas refuser comme le prévoit M-03 — et la vue chaîne du lot L6
lirait « ce document a produit cet effet » sur un effet qui n'existe plus.

---

## 2. Ce que la migration fait, et pourquoi ainsi

### 2.1 Trois compagnons, parce qu'ici le compagnon suffit

La doctrine de la 310 pose un **déclencheur compagnon** (`zz_l3_…`, même table,
même événement, trié APRÈS le maillon métier par ordre alphabétique — mesuré :
les 15 déclencheurs de ces trois tables portent un nom qui trie avant `zz_`).
Elle est **disponible** ici pour une raison précise : la fermeture **constate**
un effet réversible, elle ne **décide** de rien du travail du maillon — là où
`chain_avant` (qui décide de produire) exige d'être appelé **avant** l'effet.
Les trois corps métier (`release_stock_on_sales_order_cancel`, la 253, la 251)
ne sont donc **pas touchés** : ils ont été mesurés par leurs propres suites, et
les recopier serait le chemin le plus court vers une régression silencieuse.

| Table | Transition qui contrépasse (garde recopiée du métier) | Effets rompus |
|---|---|---|
| `sales_orders` | `confirmée → annulée` (STK-02c libère les réservations) | `sale.order.reserved` |
| `delivery_notes` | `expédié \| livré → annulé` (la 253 écrit la sortie miroir) | `sale.delivery.stock_out` |
| `goods_receipts` | `reçue \| partielle → annulée` (la 251 écrit la sortie miroir) | `purchase.receipt.stock_in` |

La garde est **recopiée volontairement** de celle du maillon d'annulation : ce
qui est fermé est exactement ce qui a été contrepasse. Un chemin d'annulation
qui ne retire pas le stock (une commande confirmée repassée en brouillon) ne
### 2.2 La fermeture GLOBALE, pas la ciblée — et c'est la décision qui compte

La 312 écrit la différence entre ses quatre portes, et elle est décisive ici :
la ciblée (`chain_lien_rompre`) **REFUSE** quand il n'y a rien à fermer (« son
appelant affirme savoir qu'un lien existe ») ; la globale (`chain_liens_fermer`)
**RAPPORTE** le nombre fermé. Or sur un chemin d'annulation, « zéro lien actif »
est un état **légitime** : un BL annulé sans avoir jamais été expédié, une
réception d'avant la 310, une commande annulée depuis un état où rien n'avait
été réservé. Faire échouer l'annulation d'un document ordinaire serait un
défaut, pas une garde — la suite le mesure (T06 : l'annulation ne lève pas,
n'écrit ni lien, ni événement, ni trace).

### 2.3 La seule réécriture de corps : le maillon des réservations regagne son entrée

La 311 avait dû **retirer** l'entrée (`chain_avant`) de
`reserve_stock_on_sales_order_confirm`, et l'écrire : la clé du socle n'avait
pas de **tour**, `chain_avant` retrouvait le lien de la première confirmation,
rendait faux, et la reconfirmation d'une commande annulée ne réservait plus
**rien** — le rouge mesuré de la suite 230 (T04 : réservé = 0 au lieu de 10).
La 312 a levé exactement cela ; la 320 tient la promesse : le maillon appelle
son entrée **par ligne**.

C'est une réécriture, et sa justification est celle de la 319 : `chain_avant`
doit être appelé **avant** l'effet (il décide de le produire) ; un compagnon
s'exécute **après** et ne peut donc pas le porter. Le corps est repris de la
311 **à l'identique** ; s'y ajoutent l'entrée et le `CONTINUE` qu'elle impose.

Une conséquence **mesurée**, et elle est une amélioration (T05) : confirmer une
commande **deux fois** sans l'annuler (le rejeu) insérait auparavant une
**seconde** réservation par ligne — la quantité réservée doublait, et le lien
était mis à jour vers la nouvelle, masquant la fuite. Avec l'entrée : le rejeu
saute la ligne, la réservation n'est plus doublée, la trace dit `ignore` —
l'idempotence de l'effet est structurelle, pas seulement celle du traçage.

### 2.4 Ce qu'une fermeture n'écrit pas

**Aucune `chain_traces`.** Une trace mesure l'exécution d'un maillon (durée,
lignes écrites, résultat) ; fermer un lien est un acte de gestion, pas un
maillon qui tourne — c'est la doctrine écrite dans la 312. Le journal du cycle
de vie est `domain_events` (un `chain.link_broken` par lien fermé, écrit par la
312) et `document_links` lui-même (état, date, motif, auteur).

---

## 3. Les huit scénarios, et ce qu'ils prouvent

| # | Ce que le scénario mesure | Verdict mesuré |
|---|---|---|
| T01 | Commande confirmée puis annulée : les 2 liens du tour 1 passent `rompu`, **datés, motivés, signés**, un `chain.link_broken` par lien, et l'effet n'est plus « intact » (M-03 : `chain_integrity_ok` vrai avant, faux après) | ✅ rompus=2, événements=2, motif nominatif |
| T02 | BL expédié puis annulé : les **2 liens par ligne** passent `rompu` en gardant l'**aval de la sortie d'origine** (la contrepassation de la 253 est un fait **neuf**, le lien n'est pas réécrit) | ✅ aval ligne 1 inchangé, 2 contrepassations, 2 sorties intactes |
| T03 | Réception reçue puis annulée : les **2 liens par ligne** de la 319 sont rompus, chacun sur SA ligne ; les 2 entrées reçoivent leur contrepassation (251) | ✅ actifs=0, rompus=2, contrepassations=2 |
| T04 | Le REJEU : annuler deux fois ne double ni fermeture ni événement — la garde du compagnon est la **transition**, comme celle du métier | ✅ rompus=2, événements=2 |
| T05 | L'ENTRÉE retrouvée : confirmer deux fois sans annuler ne réserve qu'une fois (2 réservations, pas 4), une trace `applique`, les `ignore` du rejeu | ✅ réservations=2, applique=1, ignore=2 |
| T06 | Aucun lien à fermer est un cas **ordinaire** : annuler un document jamais expédié ne lève pas, n'écrit rien (fermeture globale : rapporte 0) | ✅ exception=f, 0 lien, 0 événement, 0 trace |
| T07 | CLOISONNEMENT : A annule — SES 2 liens rompus, ceux de B intacts ; B ne voit ni liens, ni traces, ni événements de A (RLS) | ✅ A rompus=2, B actifs=2, vus par B : 0 partout |
| T08 | STRUCTURE : 3 fonctions SECURITY DEFINER **non exposées**, 3 déclencheurs APRÈS sur UPDATE, **aucun** déclencheur métier qui trie après eux (une propriété, pas un compte), le corps réécrit porte son entrée | ✅ 3/3, exposées=0, métier après eux=0 |
---

## 4. La non-régression, mesurée — et l'assertion précisée

### 4.1 La base neuve et les portes

**270 migrations, 0 erreur** sur base neuve (stubs → `00_schema_dump.sql` →
`run-sql-migrations.mjs`). Les **12 contrôles du dépôt** dans l'ordre de la CI,
AVANT les suites (c'est l'ordre de la CI, et la G1 l'exige — un contrôle tourné
après les suites voit les partitions mensuelles de la 252, dit-il lui-même) :

| Contrôle | Verdict |
|---|---|
| `check_plpgsql` (toutes les fonctions PL/pgSQL, dont les deux corps réécrits) | **0 erreur** |
| `check_bt_grid` (G1 — RLS forcée, index de société) | **OK — la grille est celle du 30/09/2026, aucun nombre n'a bougé** |
| `check_effects_contract` (G2) | **OK — 46 constats, 43→46 avec la 320 et la 321, 0 au registre** |
| `check_anon_grants` (les 3 fonctions neuves sont révoquées) | **OK — 2 exposées, toutes inscrites** (l'état d'avant) |
| `check_tenant_guard`, `check_trigger_reachability`, `check_status_writes`, `check_policy_duplicates`, `check_composite_fks`, `check_roles_opposables`, `check_forced_rls_writers` (G7) | **OK** |
| `check_chain_performance` (G6 — 1 000 tours) | **OK — p95 dans le budget, coût stable** |

### 4.2 Les suites

Sur la base neuve (l'ordre de la CI) : **230** 5/5 · **241** 7/7 · **242** 6/6 ·
**251** 6/6 · **253** 5/5 · **280** 10/10 · **310** 15/15 · **311** 12/12 ·
**312** 12/12 · **313** 11/11 · **314** 10/10 · **316** 12/12 · **319** 7/7 ·
**320** 8/8 · **321** 6/6. Et la **batterie complète du dépôt rejouée :
98 suites, 0 rouge** (les suites créent chacune leur société, la batterie a pu
tourner sur une base déjà habitée).

### 4.3 L'assertion de la 311 T02, précisée — et pourquoi c'est une amélioration

La T02 de la suite 311 mesurait : « commande annulée puis reconfirmée : l'effet
est reproduit **et les liens restent au nombre de deux, mis à jour vers la
réservation courante** ». C'était la vérité **du monde d'avant** — quand aucun
maillon ne fermait, et où `link_documents` mettait donc le lien à jour en place.
La 320 change la vérité : le lien du tour 1 est **conservé rompu** et un
**nouveau** naît au tour 2 — c'est la phrase de la 312, « un lien remplacé, pas
réécrit », enfin jouée par le flux réel.

L'assertion est donc devenue **plus forte**, pas plus faible : elle exige
toujours l'effet reproduit (2 réservations actives) **et** l'historique des deux
tours (2 rompus + 2 actifs), là où l'ancienne tolérait une réécriture. Le
changement est **daté dans le fichier**, l'outillage `_l311_liens` a gagné
`etat` et `tour` (avec le `DROP` avant `CREATE` qu'exige le dépôt pour une
signature qui change), et les **deux verdicts sont conservés** : « deux liens
actifs pointant la réservation courante » était vrai avant par réécriture, il
l'est après par remplacement. C'est la doctrine déjà appliquée aux T01/T11/T12
de la 310 par la 313, et aux T09/T11 de la 311 par la tranche 5.

La suite **312 C12** — qui joue le geste « à la main » sur le vrai flux — est
**inchangée et verte** : elle fermait 2 liens à la main puis mesurait
4 liens / 2 tours après reconfirmation ; le maillon produit aujourd'hui
exactement la même histoire, sans le geste manuel.

---

## 5. Les limites, dites

* **Un chemin d'annulation qui ne contrépasse pas ne ferme rien.** Une commande
  confirmée qui repasserait en brouillon, un BL qui reviendrait à `pending` :
  l'effet existe toujours, donc le lien reste actif — le fermer serait le
  mensonge inverse. Écrire ces transitions-là est une **règle d'état** (phase
  D, `R-001` → `R-062`), pas une fermeture.
* **Les neuf maillons RPC** (caisse, paie versée, relevé manuel) **et le banc
  d'épreuves D1→D8** restent : ce sont les tranches 2 et 3 du lot L3 (§6).
* **Une fermeture ne survit pas à un rollback** : c'est une propriété de
  PostgreSQL, dite au §5 de la 252, et elle vaut ici comme ailleurs.
* **La vue chaîne (L6) n'est pas écrite** : la 320 rend le registre *vrai*, le
  lot qui le *montre* au client reste à faire — et il lira `etat`, `tour`,
  `ferme_le`, `motif`, que la 312 a déjà posés.

---

## 6. Ce qui reste pour L3, nommé

1. **Tranche 2 — les neuf maillons RPC** (inventaire de la tranche 4, §2) :
   `pos_refund_ticket`, `create_pos_ticket`, `payroll_payment_inner`,
   `payroll_post_run`, `post_bank_statement_line`,
   `reconcile_bank_statement_line`, `unreconcile_bank_statement_line` — un
   compagnon ne peut pas s'y accrocher, il faut les tracer **par leur chemin
   d'appel** : choisir où l'entrée du maillon est posée, et le prouver.
2. **Tranche 3 — le banc d'épreuves D1→D8** : un moteur de test paramétré par
   chaînage (rejeu, concurrence, panne partielle, annulation, réouverture,
   retour arrière, volume, isolation) et son **rapport par maillon** — la
   « note de robustesse prouvée » qui transforme le traçage en preuve
   opposable, et la matière des pages « Robustesse » du lot L5.

La 320 a livré le **prérequis des deux** : sans cycle de vie *utilisé* par les
maillons, le banc D1→D8 aurait mesuré des liens qui mentent à l'annulation, et
les maillons RPC auraient hérité d'un socle dont personne n'avait prouvé le
geste central.
ferme **rien** — et c'est cohérent, l'effet existe toujours (§5).