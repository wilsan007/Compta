# AGENTS.md — Onusuite/compta

> ## ⚡ Session qui démarre ici, ou qui va écrire une migration : lisez d'abord
> **[`doc/audit/NUMEROTATION-MIGRATIONS.md`](doc/audit/NUMEROTATION-MIGRATIONS.md)**
> — la règle de numérotation, les plages prises par chaque session, et
> l'histoire du 02 octobre où deux sessions se sont marchées dessus. Une
> session qui écrit une migration sans l'avoir lu a déjà cassé le dépôt
> une fois.

## Reste ouvert — au 30 septembre 2026

**Le point d'entrée pour reprendre : [`doc/audit/RESTE-OUVERT-2026-09-26.md`](doc/audit/RESTE-OUVERT-2026-09-26.md)**
(ce qui attend une décision, ce qui vit hors du dépôt, les charges restantes, et —
depuis le 28/09 — **un registre de CI vide** : plus aucun défaut prouvé ouvert).
L'essentiel en huit lignes :

> ⚠️ **Numérotation des migrations** — un numéro se **constate**, il ne se réserve
> pas. **Mais il se CONSTATE : l'inscription dans le présent paragraphe est
> obligatoire, et elle est datée.** Une session qui prend des numéros sans les
> inscrire ici les vole à la session suivante, qui les avait inscrits.
>
> 🔴 **Le 02/10, les chaînages ont été renumérotés en `400` → `413`** et la
> **session recette** (`qa/recette-2026-09-29`) s'est attribué **`310` → `324`**
> **sans l'inscrire ici**. Les deux series se chevauchaient : après fusion,
> `run-sql-migrations.mjs` aurait refusé de démarrer (doublon de numéro =
> `exit(1)`, porte SOC-06). Les **douze** tests de la recette
> (`310`→`321`) portant des noms HOMONYMES mais des contenus DIFFÉRENTS —
> `310_chain_l1_maillons` ≠ `310_legislation_packs_readable` — l'ordre de
> fusion aurait en plus appliqué les deux au même rang. **Le chaînage a
> été déplacé**, parce que c'est lui qui était inscrit ici depuis le
> 30/09. *Les sessions en cours au moment de ce déplacement : votre
> migration était en `3xx` et porte maintenant un `4xx`. Reprenez le
> numéro depuis cette table.*
>
> | Plage | Session | Inscrite le |
> |---|---|---|
> | `100` → `129` | fondations produit | — |
> | `130` → `197` | sessions fonctionnelles | 2026-09 |
> | `200` → `209` | socles | — |
> | `210` → `299` | audits fonctionnels, W7/W8, L7 | 2026-09-28 |
> | **`300` → `309`** | **W7** : CA3, temps, production, projets, analytique, FEC, devises, budgets, import Sage, écart de change | 2026-09-28 |
> | **`310` → `324`** | **session recette** (`qa/recette-2026-09-29`) : paquets lisibles, bulletin de paie, tiers, soldes clients, livraison, sorties de stock, valorisation, facture directe, identité tiers, simulateur, prorata, autoliquidation UE, IBAN | **2026-10-02** |
> | **`400` → `413`** | **chaînages** (L1, L2, L3, L4) — les 14 chaînages et leurs suites | **2026-10-02** |
> | `325` → `399` | **libre** | — |
>
> *Règle de coexistence : une session qui travaille sur une série déjà
> occupée prend la **prochaine libre** et l'inscrit ici. Le runner échoue
> déjà sur un doublon (SOC-06) — c'est un garde-fou, pas un plan.*

* **W8 fermée (28/09)** : les 6 défauts du plan sont corrigés — `PROJ-01`
  (refacturation des temps, `301`), `PROD-01→03` (nomenclature multi-niveaux,
  écarts de quantité et de coût chiffrés, écriture datée de l'OF, `302`),
  `PROJ-02/03` (avancement **pondéré** par une seule règle, anti-cycle, `303`).
  [Preuve](doc/audit/VAGUE-W8-2026-09-28.md) : `302` **8/8**, `303` **6/6**,
  batterie **82/82**, base neuve **243 migrations, 0 erreur**.
* **W7 fermée (28/09)** : ses **quinze** défauts sont corrigés — le CA non taxé
  dans la CA3 (`300`), l'**analytique** qui circule (`304`), **un seul** FEC
  (`305`), le **taux de change appliqué** (`306`), les **budgets** (`307` :
  réalisé borné, engagements créés et consommés), l'**import d'écritures en une
  transaction** (`308`) et l'**écart de change au règlement + la réévaluation de
  clôture** (`309`). [Preuve](doc/audit/VAGUE-W7-2026-09-28.md) : `304` 5/5,
  `305` 2/2, `306` 6/6, `307` 4/4, `308` 5/5, `309` 5/5.
* **L1 — tranches 1, 2 et 3 livrées (29 et 30/09)** : **14 effets** de la chaîne
  ventes → trésorerie → comptabilité sont **tracés** (migrations **310** et
  **311**) — facture, avoir, décaissement, encaissement, journal et compte de
  trésorerie, **réservation de commande**, **sortie de BL**, expédition et
  réception de sous-traitance (ces quatre-là **par ligne**, M-09), clôture de
  caisse, rapprochement bancaire automatique, écriture et entrée de produit fini
  d'un OF. Deux doctrines, écrites : **compagnon** `zz_l1_` quand l'aval est unique
  (8), **réécriture du corps** quand la correspondance ligne → ligne ne se devine
  pas de l'extérieur (4, et c'est la seule justification). Preuves : suites **310**
  (15 scénarios) et **311** (12) vertes et rejouables, **non-régression rejouée**
  sur 17 suites du dépôt (230, 242, 251, 253, 280, 229, 302, 222, 281, 252, 180,
  192, 210, 213, 277…), **9 contrôles du dépôt à 0 erreur**, migrations rejouables.
  [Preuve](doc/audit/VAGUE-L1-2026-09-29.md) ·
  [Inventaire](doc/audit/INVENTAIRE-CHAINAGES-L1-2026-09-29.md).
  ⚠️ **Deux trouvailles** : le socle n'a **pas de notion de tour** — `chain_avant`
  voit le lien de la première confirmation et saute l'effet d'une commande
  **annulée puis reconfirmée** (mesuré : la suite **230** a rougi, réservé = 0 au
  lieu de 10) ; il n'est donc posé que sur les maillons **à sens unique**, et le
  **cycle de vie du lien** est une entrée de **L3** — **livré le 30/09 par la
  `312`, voir ci-dessous**. Et **`post_pos_session_on_close`
  (187), nommé « artère » au référentiel, n'a plus AUCUN déclencheur** : c'est
  `_multi` (281) qui vit. Limites dites : la trace d'un refus ne survit pas au
  rollback (0 ligne `refuse` mesurée) ; les effets à N lignes **sans ligne amont**
  (composants d'OF calculés, sorties de caisse agrégées par produit) sont
  **comptés au payload**, pas liés.
* **Le cycle de vie du lien est livré (30/09)** — migration **312**, suite **312**
  (**12 scénarios**), et c'est la **trouvaille de la tranche 2 qui est levée** : un
  lien a désormais un cycle (`actif` → `remplace` | `rompu`, daté, motivé, signé),
  l'index d'idempotence devient **PARTIEL** (seuls les liens actifs sont uniques),
  `tour` compte les rounds, et `chain_avant` rend **vrai** après une fermeture.
  C'était **le prérequis pour le poser partout** : un maillon qui se reproduit
  après annulation ne perd plus son effet (`chain_lien_fermer` /
  `chain_lien_rompre` / `chain_liens_fermer`). Le scénario **C12** rejoue le rouge
  de la 230 sur le vrai flux : la réservation est reproduite, l'historique garde
  **deux tours**. Limites dites : **aucun maillon n'appelle encore le cycle**
  (c'est L3), et une trouvaille est ouverte — **le socle écrit sous `FORCE ROW
  LEVEL SECURITY`** sans politique d'écriture : mesuré, un propriétaire **non
  superutilisateur** est refusé, ce que la CI ne peut pas voir (son `postgres` est
  superutilisateur). **Mesuré et gardé le 30/09** (§8 de la preuve, porte **G7**
  `ci/check_forced_rls_writers.sql`) : l'expérience à **une seule variable** donne
  `42501` pour un propriétaire nu, et l'écriture pour un rôle `BYPASSRLS` ou
  superutilisateur ; l'inventaire est de **311 tables sous `FORCE` RLS, dont 12
  sans aucune politique d'écriture** (les six du socle en font partie). La porte
  publie le **verdict de l'environnement** et échoue s'il est muet : elle est donc
  le **diagnostic**, exécutable en une commande sur la copie de production — où
  reste à prendre **la décision** (les trois issues sont dans son message).
  [Preuve](doc/audit/VAGUE-L1-TRANCHE3-CYCLE-DU-LIEN-2026-09-30.md).
* **L2 livré (30/09) — les six portes CI** : `G1` **grille BT** (`check_bt_grid.sql` :
  RLS activée/forcée et index de société sur les 360 tables cloisonnées, **plafond
  daté** — un nombre qui monte **et** un nombre qui baisse cassent la CI) ; `G2`
  **contrat d'effet** (`check_effects_contract.sql` : lit `pg_proc`, confronte les
  **25 constats** — 14 effets, 11 couples — au contrat, registre qui ne peut que
  rétrécir ; **vu rouge** sur un maillon neuf non déclaré **et** sur une
  déclaration non nettoyée) ; `G3` colonnes et écritures muettes **déjà en place**
  (mesuré : 465 fichiers, 0 suspect, `supabase/functions` compris) ; `G4` garde de
  société étendue **déjà en place** (152 fonctions SECURITY DEFINER qui écrivent,
  **0** sans mention de la société) ; `G5` **câblage des suites**
  (`check-test-suites.mjs` : 90 suites, 90 branchées — il a trouvé la 312 que
  personne n'avait branchée) ; `G6` **banc** (`check_chain_performance.sql` :
  1 000 tours, p95 total **1,002 ms** pour un budget de 50 ms, transaction
  annulée ; index d'arbitrage retiré, il échoue **immédiatement** — mais il ne voit
  **pas** la perte du seul index d'historique à N = 1 000, et c'est écrit).
  [Preuve](doc/audit/VAGUE-L2-PORTES-CI-2026-09-30.md).
* **L7 livré (30/09) — les contrats d'effet déclarés** : migration **313**, suite
  **313** (**11 scénarios**), et c'est **l'indicateur du plan qui passe de 0 % à
  100 %**. Le défaut mesuré : **1 132 traces `tolere`** (« contrat manquant »)
  pour 1 117 `applique` — chaque exécution écrivait deux lignes. Après : **5
  `tolere`**, toutes provoquées par les scénarios qui éteignent un contrat, et
  **aucun maillon métier** ne trace plus « sans contrat ». Effets de bord mesurés :
  `chain_autorise` rend vrai pour les 14, le mode **`refuse` devient utilisable**
  (il bloquait tout, faute de contrats), et le **registre de la porte G2 s'est
  vidé** (ses 25 entrées ont été refusées par le contrôle puis retirées dans le
  même commit — la moitié « le registre ne peut que rétrécir » a été vue à
  l'œuvre). Décision écrite : **`actif` est le seul drapeau lu par un code**
  (`chain_autorise`) ; les six autres (`ecrit_comptable`, `journal_code`,
  `touche_stock`, `touche_paie`, `reversible`, `obligatoire`) **déclarent** —
  mesuré, publié, et le jour où l'un sera lu, le compte changera. **Trois
  assertions de la suite 310 ont changé de verdict attendu** (T01, T11, T12) parce
  que le comportement a changé : elles sont plus fortes, pas affaiblies, et les
  deux verdicts sont conservés en commentaire. Limites dites : douze des
  quatorze confrontations « réel vs déclaration » attendent leur décor métier
  (lot L3), et les 32 chaînages non nommés n'ont **pas** de contrat — la porte G2
  cassera quand l'un d'eux arrivera sans.
  [Preuve](doc/audit/VAGUE-L7-CONTRATS-DEFFET-2026-09-30.md).
* **L1 — tranche 4 livrée (30/09) : la chaîne achats et les notes de frais.** La
  méthode de l'inventaire §3 a été **rejouée** sur le schéma du jour : **99
  fonctions** touchent ≥ 2 modules (le référentiel en comptait 62 le 24/09),
  dont **32 ÉCRIVENT dans ≥ 2 modules** — ce sont les effets qui traversent
  vraiment ; 67 ne font que lire. La migration **314** trace **3 effets** de ce
  lot par **2 déclencheurs compagnons** (doctrine 310 : maillon `AFTER` + aval
  identifié par une clé mesurée dans son corps) et **déclare leurs 3 contrats
  dans le même fichier** — la porte **G2** l'exige depuis L7. Effets :
  **facture d'achat approuvée → écriture « AC »** (le symétrique exact de la
  facture de vente, tracée depuis la 310), **note de frais approuvée → écriture
  « OD » ET élément de paie** (deux effets, un fait métier). Cumul L1 : **17
  effets tracés, 17 contrats**, 10 compagnons `zz_l1_`, **11 scénarios** de plus
  (suite **314**). Non-régression : **165 scénarios verts** sur base neuve
  (**263 migrations**). ⚠️ **Une régression trouvée et corrigée** : la suite
  **311 T11** comptait 8 compagnons (un **compte** figé sur la tranche 2) —
  l'assertion est devenue une **propriété** (tous APRÈS, tous sauf la caisse
  après leur frère par le nom, aucun frère après eux), et le changement est daté
  dans le fichier. Le classement des 32 (verdict + raison de chacun) et les
  limites (dont : le vocabulaire de trace n'a pas de valeur pour « exécuté,
  aucun effet ») sont dans l'
  [inventaire](doc/audit/INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md).

* **L1 — tranche 5 livrée (30/09) : les cinq candidats directs, et le vocabulaire
  de la trace.** Les **5 effets** que l'inventaire de la tranche 4 avait rangés
  « candidat direct » sont tracés par la migration **316** : **écart de change au
  règlement**, **facturation des temps**, **rappels de paie**, **acomptes de
  paie**, **appariement d'une ligne de relevé**. Trois points de méthode : pour un
  effet qui intègre **N documents en un passage** (rappels, acomptes), le lien est
  au niveau du **DOCUMENT** (payload `lien_par_ligne = false`, décompte et
  identifiants) ; le compagnon **relit** le marqueur du maillon dans la table —
  jamais dans `NEW`, car le maillon le pose par un `UPDATE` à l'intérieur de SON
  déclencheur `AFTER`, et la copie `NEW` ne le porte pas (l'écart de change et
  l'appariement bancaire ne posaient ainsi **aucun** lien, mesuré par la suite) ;
  et le **cas ordinaire ne se trace pas** (`sans_effet` est réservé au manque, pas
  au silence normal). La migration **315** ferme la **limite de vocabulaire** de la
  tranche 4 : `sans_effet` entre dans le `CHECK` de `chain_traces.resultat`, prouvé
  par **252 T17** (**17/17 verts**). Des trois branches d'anomalie, celle de
  l'écart de change est exercée (**316 T03**) ; les deux autres sont **publiées
  comme non couvertes**. Cumul L1 : **22 effets tracés, 22 contrats**,
  **15 compagnons** `zz_l1_`, et **12 scénarios** de plus (suite **316**, 12/12).
  Non-régression : **265 migrations**, **689 verdicts verts, 0 rouge** sur base
  neuve, **93/93 suites branchées** (porte G5), 12 contrôles du dépôt verts
  (`check_plpgsql` **non exécutable** dans l'image locale — extension absente).
  ⚠️ **Trois assertions du socle ont été précisées** parce qu'elles mesuraient plus
  large que leur étiquette — rouges **sur base neuve** uniquement : **310 T10** et
  **311 T11** (l'ordre ne se compare qu'entre déclencheurs **métier**, tous deux
  `AFTER` et partageant un événement : un `BEFORE` est avant par la phase, et deux
  compagnons L1 voisins n'ont entre eux aucun ordre qui compte) et **311 T09** (le
  scénario mesure **son** effet, pas tous les liens du document). Détail, chiffres
  et limites : [preuve](doc/audit/VAGUE-L1-TRANCHE5-2026-09-30.md).
* **L1 — tranche 6 livrée (02/10) : le sixième candidat direct, la
  contrepassation de paie.** L'inventaire de la tranche 4 marquait **six** lignes
  « candidat direct » et la tranche 5 en a tracé **cinq** : la **ligne 22**
  (`payroll_reverse_posted_run`, déclencheur de la **248**) portait le même
  verdict, et la mesure confirmait « ni trace ni contrat » — c'est
  l'incohérence de l'inventaire qui a rendu le sixième visible. La migration
  **321** le trace : le compagnon `zz_l1_payroll_run_reversal` constate la
  contrepassation **par la clé écrite dans le corps du maillon**
  (`journal_entries.reference = 'PAYROLL-REV-' || pay_runs.number`), donc il
  s'exécute après lui ; le contrat `payroll.run.reversed` est déclaré, et
  l'annulation d'un lot **comptabilisé** produit **un** lien
  `pay_runs → journal_entries` (`reversed_by`) + un événement + **une** trace
  `applique`. La retenue de la tranche 5 est reprise : **le cas ordinaire
  (lot jamais comptabilisé) ne se trace pas**, et l'anomalie (écriture de paie
  `posted` sans contrepassation) trace **`sans_effet`** — visible, pas muette.
  Cumul L1 : **23 effets tracés, 23 contrats**, **17 compagnons** `zz_l1_`,
  **6 scénarios** (suite **321**, 6/6). Non-régression : **271 migrations**, les
  **14** contrôles du dépôt verts (`check_plpgsql` **0 erreur** — extension
  installée), les suites `252/310/311/312/313/314/316/319/320/321/241/247`
  vertes, et les types générés **sans écart** après régénération sur base neuve
  (les suites n'y ont pas tourné). Limite dite : la branche d'anomalie n'a
  qu'**un** décor (le pont passé à `cancelled` à la main), et les neuf maillons
  RPC de l'inventaire restent du lot **L3** — un compagnon ne s'accroche pas à
  un appel de fonction. Détail, chiffres et limites :
  [preuve](doc/audit/VAGUE-L1-TRANCHE6-2026-10-02.md).
* **L3 — premier maillon livré (30/09) : la réception de marchandise, tracée PAR
  LIGNE.** L'inventaire de L1 en avait fait la seule « réécriture du corps »
  justifiée : N mouvements à partir de N lignes, et la correspondance ligne → ligne
  ne se devine **pas** de l'extérieur (les N mouvements portent le même
  `reference_id`, et l'ordre d'insertion n'est pas une garantie) — la doctrine 311
  n'admet rien d'autre. La migration **`319`** reprend le corps de la `241`
  **à l'identique** et y ajoute l'entrée du maillon (`chain_avant`, **par ligne**),
  le lien **par ligne** (`link_documents` sur la ligne, pas sur l'en-tête) et la
  sortie (`emit_domain_event` + `chain_apres`), **avec son contrat d'effet déclaré
  dans le même fichier** — la porte **G2** l'exige, et sans lui chaque réception
  tracerait « contrat manquant ». **Non-régression mesurée, pas supposée** : la
  suite **`241`** rend **7/7 avant et 7/7 après** le remplacement du corps, les
  huit suites de la chaîne (`310`→`314`, `316`) restent vertes, et `plpgsql_check`
  donne **0 erreur**. Suite **`319`** : **7 scénarios** (deux lignes → deux liens,
  chacun sur SA ligne ; la bonne quantité et le bon dépôt ; la trace `applique` et
  l'événement ; la ligne à zéro qui n'existe pas ; le rejeu qui ne double rien ; le
  contrat actif ; le cloisonnement). Cumul : **23 effets tracés, 23 contrats**.
  ⚠️ **Ce que ce maillon n'appelle pas encore** : le **cycle du lien**
  (`chain_lien_fermer`) sur l'annulation — aucun maillon ne le fait, c'est le
  reste de L3, et c'est écrit dans l'en-tête de la migration pour que la prochaine
  tranche ne le cherche pas ailleurs. **Restent aussi les neuf maillons RPC**
  (caisse, paie, relevé), qui se tracent par leur **chemin d'appel** — un
  compagnon ne peut pas s'y accrocher —, et le **banc des 8 épreuves**
  (`D1`→`D8`) avec son rapport par maillon.
* **L3, tranche 1 livrée (02/10) : les chemins d'annulation FERMENT leurs liens
  (`320`), et le maillon des réservations regagne son entrée.** C'est le reste
  que la 319 nommait (« aucun maillon n'appelle le cycle du lien sur
  l'annulation ») et le geste que la 312 écrivait à l'avance. Mesuré avant : le
  socle comptait **2 appelants** de `chain_lien_fermer` — les deux portes de la
  312 elle-même — donc une commande annulée gardait ses liens `actif` alors que
  ses réservations sont **libérées** (STK-02c), un BL annulé aussi (la 253
  contrepasse), une réception aussi (la 251) : `chain_integrity_ok` (M-03)
  disait « intact » sur un effet retiré. La `320` pose **trois compagnons
  `zz_l3_`** (un par chemin qui CONTRÉPASSE un effet tracé — compagnon, car la
  fermeture CONSTATE, elle ne décide pas ; fermeture GLOBALE, car zéro lien à
  l'annulation est un état LÉGITIME, suite 320 T06) et **une seule réécriture
  de corps** : `reserve_stock_on_sales_order_confirm` regagne `chain_avant`
  **par ligne** — l'entrée que la 311 avait dû retirer (rouge de la 230 T04).
  Amélioration mesurée (T05) : le rejeu ne **double plus la réservation** (2,
  pas 4 — l'ancien `ON CONFLICT` masquait la fuite). Suite **320 : 8
  scénarios** ; **311 T02 précisée** (datée : le lien est REMPLACÉ, pas
  réécrit — assertion plus forte, les deux verdicts conservés), **312 C12
  inchangée et verte**. Non-régression : **270 migrations, 0 erreur** sur base
  neuve, **12 contrôles verts** (G1 : la grille n'a pas bougé ; G2 : 46
  constats, 0 au registre ; `plpgsql_check` : 0 erreur), **98 suites, 0 rouge**.
  [Preuve](doc/audit/VAGUE-L3-FERMETURES-2026-10-02.md)
  *(portée par le commit `e5bb05a`, dont le message décrit le correctif voisin —
  la preuve le dit).*
  ⚠️ **Restent pour L3** : les **9 maillons RPC** (caisse, paie versée, relevé)
  — par leur chemin d'appel — et le **banc D1→D8** avec son rapport par
  maillon.





* **≈ 133 j restants** : **plan correctif des vagues W fermé** ; chaînages
* **≈ 131 j restants** (recompté le 30/09 : le « ≈ 133 j » porté jusqu'ici
  reprenait 2 j de **W7 déjà livrés**) : **plan correctif des vagues W fermé**
  (0 j) ; chaînages **L1 → L24** (≈ 116 j — **plafond brut** du plan, non déduit
  de L0, des tranches 1 à 5 de L1, de L2 et de L7, déjà livrés), couverture
  d'audit phase 10 (≈ 15 j), et la recette à l'écran (P0-08, hors charge de
  développement).
* **W10 livrée le 27/09** (≈ 2 j, **hors plan**) : le **contrat d'appel** entre
  l'écran et la base. Trois contrôles regardaient les lectures, les colonnes
  écrites et l'erreur non lue — aucun ne regardait les **appels de fonction**.
  Mesure : **14 appels que la base ne pouvait pas servir** (4 fonctions de
  déclencheur appelées depuis des écrans vivants, le stock compté deux fois, la
  période NF-525 envoyée comme une date, les IJSS calculées sur un couple
  salarié/jours). Le contrôle `check-rpc-contract` (baseline **à zéro**) les
  interdit désormais, et la **267** rend la clôture NF-525 possible.
* **Les deux défauts du registre sont FERMÉS (28/09)** — `app/sql/ci/expected_failures.sql`
  est **vide** : `231 M-17-01` (la refacturation des temps → **W8**, `301` :
  brouillon de facture par projet, ligne rattachée au temps, unicité
  `(société, temps)`, saisie directe couverte) et `245 T08` (le CA non taxé absent
  de la CA3 → **W7**, `300` : le CA se lit sur les comptes de produits).
  [Preuve](doc/audit/VAGUE-W7-W8-2026-09-28.md) : 10 scénarios `231` et 9 `245`
  verts, batterie **76/76**, base neuve **238 migrations, 0 erreur**.
  ⚠️ **Cette ligne, écrite le 28/09, était périmée le soir même** : **W7 est
  fermée** — ses **quinze** défauts sont corrigés par `300` → `309`, dont
  **`308`, `SAGE-01→03`** (l'import d'écritures est **une** transaction :
  équilibré, validé, soldes cumulés). Corrigée le 30/09 ; voir le bullet
  « W7 fermée (28/09) » en tête de fichier.
* **Décisions qui bloquent** : `D-4` (**ouverte, et la voie A est désormais
  ouverte** : le 30/09 la migration **`317`** a posé le bucket d'archive
  (`generated-pdfs`, privé, PDF seulement, lecture bornée à la société ET au
  module) et la fonction ne ment plus — `503` sans convertisseur au lieu du HTML
  en `200`, `500` au lieu de `success: true` avec `url: null` ; il reste A1, le
  convertisseur injoignable du réseau interne, le secret `GOTENBERG_URL` et un
  appelant — **note d'aide à la décision** :
  [D-4](doc/audit/DECISION-D4-GENERATE-PDF-2026-09-30.md), dont le §9 dit ce qui
  a été fait), `D-5` (**tranchée partiellement le 30/09, voie « garder
  encadré »** : la migration **`318`** pose un consentement **daté et signé par
  la base** — déclencheur, pas drapeau client —, réglable dans **Paramètres →
  Société**, et `ocr-invoice-import` **refuse en `409` avant tout envoi** ; suite
  **`318` 5/5**. ⚠️ **Restent** : le **DPA** (hors dépôt) et **deux fonctions qui
  parlent au même prestataire sans garde** — `parse-bank-statement` et
  `ai-import-mapping`, nommées, pas tues), `D-7` (contraste),
  `D-10`, `D-11` (localisation), `D-13`.
* **Hors du dépôt** : les secrets et la recette des neuf intégrations (Chorus Pro,
  Yousign, GoCardless, Resend, EFI, SIRENE, VIES, Stripe, Gotenberg) ; la clé
  `sb_secret_…` à tourner ; les secrets E2E ; l'expert-comptable ; les 14
  documents djiboutiens ; les pilotes. Ce qui est **prouvé** en attendant est dit
  dans le tableau B du document.
* **Recette à l'écran (P0-08)** : 14 parcours à passer — un passage obligé, pas
  une charge de développement.
* **Rappel de méthode** : un défaut = un test **rouge avant**, une migration qui
  se **constate** (un numéro ne se réserve pas), le câblage CI et la preuve dans
  **le même commit**. Le travail non commité n'existe pas.
  ⚠️ **Et si la migration change le schéma** (colonne, table, vue, valeur d'un
  `CHECK`) : **`npm run db:types` dans le même commit**. La CI régénère
  `src/types/database-generated.ts` depuis une base neuve et **refuse tout
  écart**. Mesuré le 30/09 : les **5 colonnes** du cycle de vie du lien (`312`)
  — `document_links.etat`, `.tour`, `.ferme_le`, `.ferme_par`, `.motif` — ont
  fait échouer la CI — **15 lignes**, `Row`/`Insert`/`Update` — jusqu'à
  `b3eac3b` ; régénérer sur une base neuve de **265 migrations, 0 erreur**
  redonne **exactement** le fichier commité. (Le message de `b3eac3b` nomme
  `chain_traces` : c'est une **étiquette fausse**, la table est `document_links`
  — mesuré sur la base neuve, `information_schema` ; le contenu du fichier, lui,
  est le bon. La table est écrite ici pour que la prochaine lecture ne s'y trompe
  pas.)

## À faire plus tard (rappels)

### 🔭 Après les chaînages — les propositions de différenciation (`P1` → `P8`)
- **Statut :** **PROPOSÉ, non planifié** — à exécuter **après** `L3` → `L4` → `L5`
  (et `L6`/`L23`/`L24` pour `P6`). **Rien avant** : ces propositions sont des
  **lecteurs de la preuve** — sans les 8 épreuves (`L3`) et l'indice de cohérence
  (`L4`), il n'y a rien à certifier, ni à rejouer, ni à citer.
- **Document : [`doc/audit/PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md`](doc/audit/PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md)**
- **À ouvrir en premier, le jour où `L3` est livré :** `P1` le **certificat
  d'intégrité** (2-3 j — il monétise l'indice de cohérence, et ouvre le canal
  **expert-comptable / banque**), puis `P3` l'**audit de reprise** à l'import
  (2-3 j), puis `P2` le **banc d'épreuves sur les données du prospect** (3-4 j) ;
  ensuite `P4` remonter le temps, `P5` la documentation vivante, `P7` la sortie
  intégrale, `P8` l'API + les packs par pays, et `P6` l'**IA qui cite** (après
  `L24`).
- **Le principe :** on ne bat pas SAP sur la largeur — on se différencie par
  **la preuve, l'explication et la sortie libre**. ⚠️ Les **12 innovations
  `I-01` → `I-12`** sont **déjà au plan** (`L6`, `L22`, `L23`, `L24`) : ce
  document vient **après**, il ne les remplace pas.
- **Cinq questions à trancher avant de commencer** (§6 du document) : qui signe
  le certificat, à qui on le remet en premier, où tournent les données du
  prospect, empreinte NF-525 ou pas, et **combien de temps on mesure**.

### Stripe — Webhooks et paiements
- **Statut:** En attente — l'utilisateur traitera Stripe plus tard
- **À configurer quand l'utilisateur sera prêt:**
  1. Créer un compte Stripe (si pas déjà fait)
  2. Récupérer `STRIPE_WEBHOOK_SECRET` depuis Dashboard Stripe > Developers > Webhooks
  3. Ajouter le secret dans Supabase Dashboard > Settings > Edge Functions > Secrets
  4. L'Edge Function `handle-stripe-webhook` est déjà déployée sur le cloud — elle attend juste le secret
  5. Configurer les webhooks Stripe pour pointer vers: `https://ndtaedcgwnaopopugiql.supabase.co/functions/v1/handle-stripe-webhook`
  6. Tester avec un événement Stripe de test

### Resend — Emails transactionnels
- **Statut:** En attente — `RESEND_API_KEY` à ajouter
- **À configurer:**
  1. Créer un compte sur https://resend.com
  2. Générer une clé API sur https://resend.com/api-keys
  3. Ajouter `RESEND_API_KEY` dans Supabase Dashboard > Settings > Edge Functions > Secrets
  4. L'Edge Function `send-notification-email` est déjà déployée

### Sentry — Monitoring d'erreurs
- **Statut:** Code prêt, DSN à configurer
- **À configurer:**
  1. Créer un projet sur https://sentry.io
  2. Copier le DSN
  3. Ajouter `VITE_SENTRY_DSN=<dsn>` dans `app/.env.local` (local) et variables d'environnement de production

## État du projet (2026-09-09)

### Edge Functions — 20/20 déployées sur le cloud
- Projet Supabase: `ndtaedcgwnaopopugiql` (compta, West Europe)
- Toutes les fonctions sont déployées et actives
- Secrets configurés: `APP_URL`, `CRON_SECRET`, `OPENAI_API_KEY`, `RESEND_FROM`
- Secrets manquants: `RESEND_API_KEY` (Resend), `STRIPE_WEBHOOK_SECRET` (Stripe — plus tard)

### pg_cron — Configuré sur le cloud
- `payment-reminders-daily` — 9h tous les jours
- `refresh-exchange-rates-daily` — 6h tous les jours
- `revoke-expired-auditors-daily` — 0h tous les jours

### Base de données (2026-09-11)
- 377 tables sur le cloud (toutes avec RLS activé)
- 225 fonctions, 389 triggers, 1 779 policies RLS
- 138 migrations déployées et marquées (100–129)
- 5 vues (toutes avec `security_invoker=true` + filtre `current_tenant_id()`)
- Tables ajoutées: `profiles`, `webhook_endpoints`, `webhook_delivery_logs`, et 70+ tables Vague 2/3
- Fonction ajoutée: `auth_email_exists(p_email text)`
- Migration: `supabase/migrations/0001_add_missing_tables.sql`
- Seed data: `supabase/seed_business_data.sql` (5 clients, 3 fournisseurs, 5 produits, 5 factures, 5 écritures, 5 employés, 3 projets, 12 tâches)

### Vague W1 — isolation et droits (2026-09-24) ✅
- **ISO-01 (236)** : 18 fonctions `SECURITY DEFINER` filtraient mal la société
  (`UPDATE … WHERE id = …` sans `tenant_id`) : A modifiait les données de B.
  17 scénarios, contrôle `ci/check_tenant_guard.sql` (règle 2, 137 fonctions
  écrivantes examinées).
- **ISO-02 (237 + 249)** : 408 clés étrangères mono-colonnes reliaient deux
  tables cloisonnées — A référençait une ligne de B que la RLS lui cachait.
  Générateur `scripts/generate-composite-fks.mjs` (clés composites
  `(tenant_id, colonne)`, `ON DELETE SET NULL (colonne)` sur 200 d'entre elles) ;
  2 clés nées **après** la 237 (241 en ajoute une, 244 en recrée une
  mono-colonne) reprises par la **249**. Contrôle `ci/check_composite_fks.sql` :
  410 clés composites, 0 mono-colonne.
- **ISO-03 / ISO-04 (238)** : 495 couples (table, commande) portaient deux
  politiques RLS permissives — la plus large gagnait et les 57 gardes
  `can_perform` étaient annulées. 506 politiques en trop et 12 index en double
  retirés ; registre gelé de `ci/check_policy_duplicates.sql` vidé.
- **PERM-01 / décision D-6 (239)** : un `viewer` créait une facture et
  supprimait un client par appel direct. Le rôle devient opposable sur **41
  tables sensibles** (123 politiques gardées par `can_perform`) ; les **257
  autres** tables écrites restent sous la garde de société et le nombre est
  **publié** par `ci/check_roles_opposables.sql` à chaque exécution.
- **Suites adaptées** : 236 (fabrication d'état hostile par désactivation des
  seuls déclencheurs de clés étrangères, T02 inversé et retiré du registre),
  105 (recollage des clés composites par `unnest … WITH ORDINALITY` — la
  couverture passe de 333 à **340 tables visibles sur 340**).
- Preuves : `doc/audit/VAGUE-W1-ISO02-04-PERM01-2026-09-24.md`.

### Vagues W2 et W3 — inaltérabilité de la caisse et chemins d'annulation (2026-09-24) ✅
- **W2 / POS-01→04 (250)** : un ticket de caisse « inaltérable » se réécrivait
  (120 € → 12 €, empreinte inchangée), ses lignes se modifiaient et se
  supprimaient, le numéro était attribué par `MAX+1` sans verrou, `created_at`
  venait du client (et un ticket dont le client omettait la société recevait un
  hachage calculé sur NULL, donc une chaîne invalide) ; le statut n'était pas
  contraint, donc une vente pouvait sortir de la clôture en silence. La **250**
  pose la garde d'inaltérabilité (montants, date, numéro, empreinte — pour
  l'appel direct **et** pour le propriétaire de la table), l'unicité
  `(tenant, caisse, numéro)` sous `pg_advisory_xact_lock`, la reprise des
  doublons (numéros **et** empreintes recalculés), et la sortie honnête
  `void_pos_ticket()` (tracée, événement NF-525, refusée après clôture — un
  avoir corrige alors). `cancelPosTicket()` de l'écran passe par cette RPC.
  11 scénarios, **vus rouges avant** (0 vert), **11/11 après**.
- **W3 / S-12, S-13 (251)** : annuler une réception reçue ne remettait ni le
  stock, ni la couche de valorisation, ni l'écriture, et le statut `received`
  était rejouable ; un contrôle qualité en échec rebutait **tout** le reçu
  (10 rebutés pour 3 contrôlés) sur un mouvement sans dépôt (l'article baissait,
  le dépôt non). La **251** contrepasse l'annulation (sortie miroir au même
  coût + écriture inverse au journal ST, l'écriture d'origine restant intacte),
  refuse la réédition d'une réception comme la double contrepassation, et ne
  rebute que la quantité contrôlée (ou rebutée), au dépôt de la réception.
  6 scénarios : 2 verts de non-régression, **4 rouges avant**, **6/6 après**.
- **Contrôles et suites** : `check_anon_grants`, `check_tenant_guard`,
  `check_status_writes`, `check_trigger_reachability`, `check_composite_fks`,
  `check_policy_duplicates`, `check_roles_opposables` verts après les deux
  migrations ; batterie complète (54 suites + 8 contrôles, base neuve
  **223 migrations, 0 erreur**) verte, hors les deux rouges du registre
  (`231 M-17-01`, `245 T08`). `tsc -b` exit 0, `oxlint` 0 avertissement.
- **Numéros** : `245`→`249` étaient déjà pris (TVA, cumuls de paie, seconde
  passe des clés composites). W2 prend **250**, W3 prend **251** ; les vagues
  suivantes prennent le premier numéro libre **au moment de leur exécution**
  (252 est déjà pris par le socle des chaînages, `252_chain_socle.sql`) — un
  numéro se constate dans le dépôt, il ne se réserve pas.
- Preuves : `doc/audit/VAGUE-W2-W3-2026-09-24.md` (mesures d'entrée, batteries,
  limites dites).
- ⚠️ **Incident de session, et ce qu'il apprend** : une synchronisation externe
  (iCloud/Desktop) a remplacé le dossier `app/sql` par un état antérieur —
  fichiers **non suivis** perdus (`237`→`249`, `ci/check_composite_fks.sql`,
  `ci/check_roles_opposables.sql`) et quatre modifications non commitées
  perdues avec eux. Tout a été restauré depuis les checkpoints de l'éditeur
  (`5e37af8` pour les fichiers suivis, `e876c08` pour les non suivis), mais la
  leçon est celle du plan (`AUD-X02`) : **le travail non commité n'existe pas**.

### Dettes de W2/W3 soldées, et le plan par phases (2026-09-24) ✅
- **`253` — annulation d'un BL expédié** (le pendant de la 251 côté vente) : sortie
  miroir au coût que la comptabilité a sorti, écriture inverse au journal ST,
  l'écriture d'origine intacte, refus de la double contrepassation. Le coût de la
  sortie d'origine n'est pas toujours posé (la comptabilité dérive le CUMP) :
  recopier `0` ne créait ni couche ni écriture — mesuré, puis corrigé dans la
  même migration avant son commit. 5 scénarios, **T02/T03/T05 rouges avant**.
- **`254` — une seule vérité de valorisation** : la comptabilité sort au **CUMP**
  pendant que les couches consommaient en **FIFO** (100 € d'écart mesuré sur un
  cas de 100@10 + 100@14). Les couches portent désormais le CUMP, la quantité
  consommée reste FIFO. Le TEST 3 de `173` est **réécrit** dans le même commit —
  doctrine changée, test non vidé. 5 scénarios, 3 rouges avant.
- **`255` — l'avoir d'un ticket de caisse clôturé** : la 250 refusait d'annuler
  après clôture et renvoyait vers « un avoir » qui n'existait pas. Le schéma
  interdit les montants négatifs sur `pos_tickets` (`*_nonneg`) : l'avoir est une
  **pièce commerciale** (`credit_notes`), créée puis validée quand elle peut
  l'être, avec les lignes de la vente ; le stock revient au CUMP, la vente passe à
  `refunded` (montants et empreinte intacts) et l'événement NF-525 est écrit.
  5 scénarios (dont une vente sans client : refusée — un avoir crédite quelqu'un).
- **Formulaire de contrôle qualité** : `quantity_checked` / `quantity_rejected` et
  le statut « partiel » sont exposés (fr / en / ar).
- **Le reste à faire et le plan par phases** :
  `doc/audit/RESTE-A-FAIRE-ET-PLAN-PHASES-2026-09-24.md` — **≈ 169 j restants**
  (34 défauts du plan correctif + 25 lots de chaînages + la couverture d'audit),
  en **10 phases**, avec les charges, les dépendances, les critères de sortie et
  les décisions qui bloquent.
- ⚠️ **Mesuré le 24/09 sur base neuve** : le socle des chaînages
  (`252_chain_socle.sql`, session parallèle) fait **échouer la suite 105**
  (`permission denied for table chain_traces_2026_09`) — les partitions
  `domain_events_*` / `chain_traces_*` sont à traiter (GRANT + RLS) avant son
  commit, sinon la CI tombe sur l'isolation.

### Vagues W4 et W9 — la paie, puis le chaînage de l'absence (2026-09-26) ✅
- **W4 / RH-05 → RH-10 (256)** : quatre conventions mensuelles contradictoires
  (retard `weekly_hours × 4,33`, congé sans solde `/ 30`, heures sup `/ 151,67`,
  front `/ 21`), un import qui échouait cinq mois sur douze (`-31` refusé par
  PostgreSQL, 22008), une note de frais entrée en paie pour 0 (`Number(exp.amount)`,
  colonne inexistante), sans TVA ni écriture, un congé à cheval sur deux mois omis,
  et des titres-restaurant doublés au réimport. **Un** diviseur par société
  (`payroll_legal_parameters`, défaut calculé `35 × 52 / 12` et `5 × 52 / 12`),
  index unique `(société, salarié, période, type, source, source_id)`, notes de
  frais au grand livre (D charge HT + D TVA / C 421). 8/8 scénarios, 17 tests
  Vitest. [Preuve](doc/audit/VAGUE-W4-2026-09-26.md)
- **W9 / TRV-01 → TRV-16 (263, 264, 265, 266)** : les quatre sources d'absence
  (congé approuvé, arrêt de maladie, arrêt de travail, pointage d'absence —
  `timesheets.absence_type` existait depuis la 104 et **n'était écrite par
  personne**) ne se parlaient pas ; rien ne lisait l'absence en aval ; **deux**
  chemins de retenue existaient pour la même journée, dont un **inerte** (il
  écrivait `unpaid_absence_deduction`, un type qu'aucun moteur de bulletin ne
  lit) ; `leave_rules.affects_pay` n'était lu par personne. La **263** pose le
  registre `employee_absence_days` (un jour, un salarié, une vérité), le journal
  des conflits, le recalcul idempotent et l'API de lecture ; la **264** rend le
  registre opposable (pointage, heures supplémentaires, temps projet, frais,
  tâches) et pose le contrôle quotidien ; la **265** ramène la paie à **un seul**
  chemin (une retenue par journée, identifiant `day_uid` déterministe,
  contre-passation d'un élément déjà intégré, régularisation d'une période close,
  et rattachement au classeur des éléments posés avant lui) ; la **266** traverse
  cinq modules en **34 assertions** (une absence d'un jour apparaît **une fois**
  dans la paie, la DSN, le coût projet et le plafond). Base neuve **231
  migrations, 0 erreur** ; **63/63 suites**, 8/8 contrôles ; front `tsc` 0,
  `oxlint` 0, i18n fr/en/ar, **Vitest 1 474**. Le **T04 de la 256** est réécrit
  dans le même commit (doctrine changée : la retenue est indexée sur la journée,
  pas sur le document source). [Preuve](doc/audit/VAGUE-W9-2026-09-26.md)
- **Cohérence UI ↔ base, sur cette vague** : quatre écritures de
  `leave_balances` retirées du front (elles doublaient le déclencheur), le
  cinquième diviseur `/ 21` de la provision de congés ramené sur
  `payroll_divisors()`, une seule liste de types de congé pour les trois écrans
  (`special` était offert et refusé par la base), `affects_pay` et
  `requires_justification` enfin exposés dans l'écran des règles, et un écran
  **`/hr/absence-anomalies`** (TRV-16) qui lit le contrôle sans rien réparer tout
  seul.

### Vague W6 — les fonctions Edge et les écrans placebos (2026-09-26) ✅
- **Les deux baselines gelées par W0 sont à ZÉRO** : `check-written-columns`
  **20 → 0** et `check-unchecked-writes` **25 → 0** (notes réécrites, le plafond
  ne peut toujours que baisser).
- **`257` — les colonnes que les fonctions croyaient écrire** : `cron-payment-reminders`
  écrivait trois colonnes absentes de `collection_reminders` (la relance n'était
  jamais tracée), `request-signature` cinq absentes de `electronic_signatures`
  (la demande n'était **jamais enregistrée**), `submit-e-invoice` quatre
  `e_invoice_*` absentes d'`invoices` (**double envoi**), `sync-bank-transactions`
  un `provider_transaction_id` absent, `handle-stripe-webhook` un `metadata`
  absent, et le front `leave_requests.manager_comment` /
  `bank_transactions.matched_line_id`. La migration pose les colonnes réelles
  **avec leurs garanties** (unicité `(société, compte)` sur
  `provider_transaction_id`, clé composite `matched_line_id` →
  `journal_lines`, énumérations élargies de `collection_reminders` — le niveau 4
  « procédure de recouvrement » **ne pouvait pas être enregistré**) et aligne le
  code là où un équivalent existait (`http_status` → `response_code`,
  `provider_requisition_id` → `provider_connection_id`, `link_url`/`user_id` →
  `metadata`). 8/8 scénarios, **8 rouges avant**.
- **`258` — une relance de paiement part une fois** : `.single()` sur une
  recherche vide interrompait **tout le cron** dès la première facture (`EF-01`),
  et l'enregistrement raté sans lecture d'erreur faisait **relancer le client
  tous les jours**, niveaux « mise en demeure » compris (`EF-02`). Reprise des
  doublons (ramenés à une, `cancelled` avec la raison — aucune suppression),
  unicité partielle `(société, facture, niveau)`, `claim_collection_reminder()`
  (prise **avant** l'envoi, `NULL` si déjà prouvé, reprise possible d'un échec) et
  `finalize_collection_reminder()` (un seul chemin « envoyée »/« en échec »,
  réservé au `service_role`). 5/5 scénarios.
- **`259` — un écran ne peut plus tamponner un succès** : `submitEdiTva`
  fabriquait `EDI-<Date.now()>` et `syncBankConnection` tamponnait
  `last_sync_at` **sans rien transmettre** ; `EInvoicePage` ne soumettait rien.
  Les trois écrans passent par les fonctions Edge (et **lèvent** sans
  confirmation) ; la base refuse à `anon`/`authenticated` tout changement de
  `vat_returns.edi_status`, `invoices.e_invoice_status` et
  `bank_connections.last_sync_at`. 3/3 scénarios.
- **Erreurs lues partout** : les 7 écritures muettes d'`outgoing-webhooks`
  (dont le journal de livraison qui écrivait `http_status` au lieu de
  `response_code`), les 5 des fonctions d'e-mail (`try { await } catch {}` ne
  suffisait pas : PostgREST **ne lève pas**, il rend `{ error }`) et les 13
  écritures du front attribuées à d'autres vagues — `throw` quand la donnée est
  indispensable, `console.error` explicite quand l'écriture est réellement
  best-effort.
- **Cohérence UI ↔ backend, vérifiée** : nouveau
  `app/src/lib/__tests__/edge-wiring.test.ts` (8 tests) — chaque écran appelle la
  fonction Edge attendue, lève sans confirmation, et **aucune écriture directe**
  de `edi_status`/`e_invoice_status`/`last_sync_at` ne subsiste dans `src/`
  (miroir statique de la porte SQL). Relevé : 8 fonctions Edge appelées par le
  front ; restent sans appelant `request-signature`, `validate-vat-vies`,
  `verify-iban`, `verify-siret`, `generate-pdf` (phase 10 — fonctions sans porte
  d'entrée, pas placebos).
- Base neuve **234 migrations, 0 erreur** ; **66/66 suites**, 8/8 contrôles ;
  `check_plpgsql` **rejoué localement** (0 erreur, 34 avertissements) ;
  `tsc` 0, `oxlint` 0, parité i18n fr/en/ar, **Vitest 1 488**, **32 tests Edge**
  (`npm run edge:test` — Deno requis, sinon `npx -y deno test …`).
  [Preuve](doc/audit/VAGUE-W6-2026-09-26.md)
- **Seconde passe — tout ce qui restait ouvert est fermé** :
  - **« un jeton, une réponse » exécuté** : harnais Deno
    (`app/supabase/functions/__tests__/`, `serve` et le client Supabase
    remplacés, ni base ni réseau) → **30 tests**, dont le contrat d'entrée des
    **20 fonctions**. Deux **défauts réels** en sont tombés :
    **`refresh-exchange-rates` lisait le jeton sans jamais le comparer**
    (n'importe qui déclenchait la mise à jour des taux → la clé de service est
    désormais exigée, celle que pg_cron envoie déjà) et
    **`ai-import-mapping` refusait tous les appels du front** (la fonction exige
    un jeton, `aiImportMapping.ts` n'en envoyait aucun : le repli IA n'a
    **jamais** pu fonctionner) ;
  - **les cinq fonctions sans appelant ont une porte d'entrée** :
    `verify-siret` et `validate-vat-vies` dans **Paramètres → Société**,
    `verify-iban` dans **Comptes tiers → Banques**, `request-signature` dans
    **Documents du salarié** — chacune dit ce qu'elle a vérifié et **où** (« à la
    source » INSEE/VIES, ou « format et clé seulement ») ; `generate-pdf` reste
    **non déployée** (défaut de la décision `D-4`) et son code est durci (HTML
    client refusé — SSRF `AUD-H03`, valeurs échappées, 2 tests) ;
  - **le déploiement cesse d'être tout en `--no-verify-jwt`** :
    `deploy-all-functions.sh` distingue **13 fonctions à JWT vérifié par la
    passerelle**, **6 points d'entrée publics** (garde propre) et **1 non
    déployée**.

### Vague W5 — un seul moteur par grandeur (2026-09-27) ✅
- **IMMO-01 → IMMO-05 + RH-04 (260)** : le défaut n'était pas le calcul, c'est
  qu'il y en avait **plusieurs**. Trois moteurs d'amortissement se contredisaient
  (le moteur SQL qui comptabilise, la RPC `calculate_depreciation`, le front en
  `floor(jours / 365,25)`), `depreciation_method` n'était lue par **personne**
  (linéaire et dégressif amortissaient pareil, `units_of_production` était
  linéaire en silence), un recalcul partait de `Date.now()` (il écrasait la
  valeur d'un exercice clos) et le lot du front **avalait** ses échecs
  (`console.error`) en rendant une liste partielle comme un succès. La 260 :
  `calculate_depreciation` **supprimée**, méthode **lue** (linéaire ; dégressif
  avec coefficient légal **paramétré** — `payroll_legal_parameters`,
  `AMORT_COEFF_DEGRESSIF_3_4/_5_6/_7_PLUS` = 1,5 / 2 / 2,5 — et **bascule** sur
  le linéaire du restant ; `units_of_production` **retirée** : la fiche ne porte
  aucun compteur d'unités produites), exercice **borné** (dotation d'exercice
  clos refusée), lot **`generate_depreciation_entries`** qui rend un verdict
  **par immobilisation** (`comptabilisees`, `sans_objet`, `echecs` nommés).
  Heures supplémentaires : **un** seuil (l'horaire prévu → `overtime_minutes`),
  **un** taux (diviseur de la société × `overtime_majoration` : première tranche
  d'`overtime_tiers` sinon paramètre `MAJORATION_HEURES_SUP`), **un** montant
  (`payroll_overtime_amount`) — le déclencheur écrit désormais **37,09 €** là où
  il écrivait **0**. 10 scénarios, **9 rouges avant**, 10/10 après.
- **Le trou trouvé en chemin (bouché)** : la 256 avait posé l'index unique
  `uniq_payroll_element_source` ; l'`upsert` de l'ancien
  `importTimesheetElements` était **avalé** par `ON CONFLICT DO NOTHING`, donc un
  élément écrit **avant** la création du lot gardait `pay_run_id = NULL` — et
  `calculate_payslip` lit **par `pay_run_id`** : l'heure supplémentaire n'était
  **pas payée**. L'écran ne recalcule plus, il **rattache**
  (`attachTimesheetElements`) et **dit** combien (`0` compris).
- **Cohérence UI ↔ base, mesurée** : `misc.ts` perd ses **deux** fonctions
  d'amortissement ; `businessFunctions.ts` perd la RPC et gagne
  `previewOvertimePay` + `getOvertimeMajoration` (`calculateOvertimePay`
  appelait `calculate_overtime_pay` avec des paramètres **inexistants** :
  l'appel échouait toujours) ; `FixedAssetsPage` passe par le moteur **et** son
  lot, affiche les échecs, n'offre plus `units_of_production` et crée ses fiches
  à la valeur d'acquisition (plus de `Date.now()`) ; la modale des heures sup
  n'a plus de **taux saisi** — elle lit le taux majoré et le montant de la base ;
  le simulateur (`PayrollCalcPage`) lit la majoration de la société. Nouveau
  **`src/lib/__tests__/single-engine.test.ts`** (5 tests) : balayage statique de
  `src/` interdisant les symboles du second moteur, commentaires exclus.
- **Le contrôle a servi** : `check_tenant_guard` a **refusé** les trois nouvelles
  fonctions internes (SECURITY DEFINER + `uuid` en paramètre + exposées) avant
  qu'elles ne partent — traitées comme le socle des diviseurs (256) : **non
  exposées**.
- Base neuve **235 migrations, 0 erreur** ; **67/67 suites** ; **9/9 contrôles**
  (`check_plpgsql` : 0 erreur, 33 avertissements) ; `tsc` 0, `oxlint` 0, parité
  i18n fr/en/ar, **Vitest 1 496** (+8), plafond de code mort **66/66**. Le
  registre `ci/expected_failures.sql` n'a pas bougé (`231 M-17-01` → W8,
  `245 T08` → W7). [Preuve](doc/audit/VAGUE-W5-2026-09-27.md)
- **Limites dites** : `units_of_production` n'est pas implémentée (retirée +
  refusée) ; `calculate_overtime_pay` (tranches + exonération de 7 500 €) n'a
  **plus aucun appelant** — le chemin de paie applique la **première** tranche,
  donc les bandes supérieures et l'exonération ne sont **pas** appliquées
  (point ouvert, phase 6) ; coefficients et majoration sont **français** (D-11) ;
  le simulateur garde un **repli** documenté (1,25) hors contexte de société.

### Vague W10 — le contrat d'appel front ↔ base (2026-09-27) ✅
- **L'angle mort** : trois contrôles regardaient les **lectures** (`check-embeds`,
  N4), les **colonnes écrites** (`check-written-columns`, W0.2) et l'**erreur non
  lue** (`check-unchecked-writes`, W0.3). Aucun ne regardait les **appels de
  fonction** — `.rpc('nom', { … })`, que ni `tsc` (client « any »), ni les tests
  (Supabase simulé), ni PostgREST avant exécution ne voient. Mesure : **14
  contrats rompus** sur 117 appels littéraux.
- **Quatre fonctions de DÉCLENCHEUR appelées comme des RPC** (`RETURNS trigger` :
  PostgREST ne les expose **jamais**, 404 garanti) — dont trois depuis des écrans
  vivants : `perform_three_way_match` (rapprochement 3 voies), `check_customer_credit_limit`
  (fiche client 360), `apply_bank_reconciliation_rules` (rapprochement bancaire),
  plus `auto_reconcile_by_score` (sans appelant). Les enveloppes sont **repointées
  sur les vraies lectures** (`run_three_way_match`, `customer_credit_score`,
  `smart_bank_reconciliation`) ou retirées, et **deux boutons placebos
  disparaissent** (ils ne pouvaient qu'échouer).
- **Le stock compté deux fois** : `createStockMovement` appelait
  `increment_stock({ p_id, qty })` / `decrement_stock({ p_id, qty })` après
  l'insertion du mouvement — des noms d'arguments qui n'existent dans aucune
  signature (`p_product_id`, `p_qty`), donc un appel qui échouait toujours et
  aurait doublé la variation si le déclencheur `update_stock_on_movement` n'était
  pas déjà le seul moteur. Les deux appels sont retirés.
- **Signatures dérivées** : `run_mrp(p_horizon_days)` (et non `p_product_id`),
  `calculate_sick_leave_pay(p_sick_leave_id)` (la base calcule sur l'ARRÊT — la
  modale IJSS lit désormais les arrêts déclarés du salarié via `getSickLeaves`),
  `close_nf525_period` / `get_nf525_attestation` avec `p_period` (`AAAA-MM`, et
  l'écran passe de champs *date* à des champs **mois**),
  `increment_download_count(p_document_id)` (le compteur de téléchargements
  n'avait jamais été incrémenté). Deux enveloppes mortes (`convertUom`,
  `distributeLandedCost`) sont supprimées plutôt que devinées.
- **Le trou trouvé en chemin (bouché)** : la clôture NF-525 **ne pouvait pas
  aboutir**. `close_nf525_period` faisait `UPDATE nf525_event_log SET closed =
  true` en comptant sur `SECURITY DEFINER` pour « contourner » le déclencheur
  d'inaltérabilité — un déclencheur ne se contourne pas ainsi, et il lève sans
  condition (`ERROR: NF525: Le journal d'événements est inaltérable`). Ce drapeau
  n'était **lu par personne**, et **rien** n'insérait dans
  `nf525_period_closures`, la table que lit l'attestation : elle levait donc
  « Période non clôturée ». La **267** rend la clôture **append-only** : elle
  n'écrit plus dans le journal, elle y **ajoute** l'événement `period_close` et
  inscrit la clôture (période, événements, empreinte, auteur, date) dans
  `nf525_period_closures` ; elle refuse une période vide, déjà clôturée, ou d'un
  format autre que `AAAA-MM`.
- **Ce qui garde** : `scripts/check-rpc-contract.mjs` (nouveau contrôle, baseline
  **à zéro** — `--update-baseline` refuse d'ajouter), son **miroir statique**
  `src/lib/__tests__/rpc-contract.test.ts` (6 tests ; vérifié **rouge** par une
  sonde hors `__tests__`), la suite `sql/267_nf525_closure_tests.sql` (**6/6**,
  dont **T04 et T05 rouges avant la 267**) et les deux étapes de CI.
- **Cohérence UI ↔ base, mesurée** : `check-written-columns` **0**,
  `check-unchecked-writes` **0**, `check-rpc-contract` **0** (109 appels) ;
  `tsc` 0, `oxlint` 0, parité i18n fr/en/ar, **Vitest 1 502** (+6) ;
  **28/28** contrôles et suites rejoués sur la base migrée (236 migrations,
  0 erreur). [Preuve](doc/audit/VAGUE-W10-2026-09-27.md)
- **Limites dites** : les fonctions de déclencheur **restent** des déclencheurs
  (aucune n'a été convertie) ; la clôture NF-525 **n'interdit pas** d'écrire
  ensuite dans un mois clos — c'est une décision de gestion, pas un correctif
  (l'attestation revérifie la chaîne à la demande) ; le contrôle ne suit pas
  `.rpc(variable)` ni `.schema('x').rpc(…)` ; `calculate_payslip` reste
  « non vérifiable » (objet d'arguments variable).
### W7 et W8 (partielles) — les deux derniers défauts du registre (2026-09-28) ✅
- **Le registre de la CI est VIDE.** Les deux seuls défauts qui y figuraient sont
  fermés, chacun **vu rouge d'abord** sur base neuve (238 migrations, 0 erreur) :
  - **W7 / `245 T08` — `300` : le CA non taxé entre dans la CA3.** La base hors
    taxe était **reconstituée depuis la TVA** (`montant ÷ taux`, 246) : 1 000 €
    taxés + 500 € exonérés + 250 € intracommunautaires déclaraient **1 000** de
    CA. `calculate_vat_ca3` lit désormais le CA sur les **comptes de produits**
    (classe 70). Mesure : `1000.00` → **`1750.00`**, TVA inchangée (200).
  - **W8 / `231 M-17-01` — `301` : les heures facturables atteignent une
    facture.** `create_billable_line_on_timesheet_stop` ne créait **qu'une
    notification** (3 h à 80 → 0 ligne de facture). La 301 pose
    `invoices.project_id` (+ un seul brouillon par projet), une ligne rattachée au
    temps (`invoice_lines.time_entry_id`, unicité `(société, temps)`) et un
    déclencheur branché aussi sur l'**INSERT** — la saisie directe du formulaire
    « temps manuel » n'arrêtait aucun chronomètre et n'atteignait rien (T07).
    Mesure : `lignes=0` → **`lignes=1 quantité=3 montant=240`**. Le brouillon
    **n'est pas** validé automatiquement (T06 : aucune écriture comptable ne naît
    d'un temps passé) ; la suppression suit la chaîne des pièces (T09/T09b :
    la ligne en brouillon part avec sa feuille de temps, une facture validée la
    protège).
- **Batterie** : `231` **10/10**, `245` **9/9**, et **76/76** contrôles et suites
  rejoués dans l'ordre de la CI sur base neuve (hors `check_plpgsql`, dont
  l'extension n'est pas dans l'image locale — la CI l'installe) ; `check_composite_fks`
  **413 clés composites, 0 mono-colonne** (les 2 clés neuves sont composites),
  `check_anon_grants` vert (la fonction réécrite reste révoquée à `PUBLIC`/`anon`) ;
  `tsc` 0, `oxlint` 0. [Preuve](doc/audit/VAGUE-W7-W8-2026-09-28.md)
- **Limites dites** : W7 et W8 **restent ouvertes** (14 et 5 défauts au plan — le
  registre ne portait que le défaut *prouvé* de chacune) ; la **ventilation par
  case** de la CA3 (A2/E1/E2) demande les pièces de vente (lot L14) et
  `total_purchases` reste reconstitué depuis la TVA ; la ligne de temps prend le
  prix de la feuille de temps et le taux de TVA par défaut de la société (ni
  position fiscale du client, ni remise), et une durée modifiée après l'arrêt ne
  met pas la ligne à jour (régénération = lot L20).
### Vague W8 — production et projets : nomenclature, écarts, cycle, avancement (2026-09-28) ✅
- **W8 est fermée** (6/6 défauts du plan). `PROJ-01` (refacturation des temps) a
  été livré par la `301` ; les cinq autres le sont ici, chacun **vu rouge
  d'abord** sur base neuve :
  - **`302` — production (PROD-01→03).** La nomenclature était lue **à un seul
    niveau** : un OF de 10 pièces dont le composant est fabriqué échouait sur
    `Stock insuffisant: disponible=0, demandé=10` (l'atelier consommait le
    sous-ensemble). `manufacturing_requirements()` **explose** désormais la
    nomenclature sur tous ses niveaux (mise à l'échelle par `boms.quantity`,
    arrêt au composant déjà rencontré, 8 niveaux au plus) et sert **les trois**
    usages : coût matière, sorties de stock, écart de coût. `qty_produced`
    **déclarée** n'est plus écrasée, un rebut supérieur au lancé est refusé (il
    était ramené à zéro en silence), l'**écart de coût** est chiffré
    (`cost_variance` = standard − réel) et l'écriture est datée de l'**OF**, pas
    du jour de clôture. Mesures : `MP=20` (au lieu de 0), `qty_produced=88` (au
    lieu de 92), `cost_variance=−10,00`, mouvements et écriture au **15/03**.
  - **`303` — projets (PROJ-02/03).** Deux calculs concurrents d'avancement, tous
    deux en **moyenne simple** : 10 h à 100 % + 90 h à 0 % donnaient **50 %**
    (parent comme projet). `progress_weight()` (heures prévues, à défaut passées,
    à défaut 1) est désormais **la** règle, appelée aux deux niveaux → **10 %**.
    Et la garde qui manquait : `check_task_parent_cycle` refuse une tâche
    **son propre parent** (le refus venait de `stack depth limit exceeded`, la
    récursion des treize déclencheurs épuisant la pile) et tout **cycle**
    A → B → A, en le **nommant**.
- **Batterie** : `302` **8/8**, `303` **6/6**, `229` 6/6, `177` 4/4, et **82/82**
  contrôles et suites sur base neuve (**243 migrations, 0 erreur** — dont `270`
  → `272`, écrites par une **session parallèle**) ; aucun fichier de `src/`
  touché. [Preuve](doc/audit/VAGUE-W8-2026-09-28.md)
- **Numérotation** : la session parallèle prend `270` → `299` ; cette session
  prend **`300`+** (`300` = ex-`268`, `301` = ex-`269`, `302`, `303`). La suite
  prendra `304`, `305`…
- **Limites dites** : un composant fabriqué est **explosé** (nomenclature
  fantôme) — **aucun sous-OF** n'est créé (`parent_mo_id` reste inutilisé) ; le
  jeu de sous-tâches moyenné ne change pas (brouillons et annulées comprises) ;
  les comptes `601000`/`310000`/`355000`/`713500` restent codés en dur (S-10).




### Audit fonctionnel exécuté — partie 1 : X1-urgent, X0, X1, X7 (2026-09-28) ✅
- **Le plan est découpé en trois parties** : **1** = X1-urgent + X0 + X1 + X7 (faite),
  **2** = X2 + X3 + X6 (compta, paie, trésorerie — décisions D-A, D-C, D-G, D-F),
  **3** = X4 + X5 + X8 (stock, production/caisse/immobilisations, recette — D-B, D-D, D-E).
- **`270` — l'écriture anonyme fermée** : un visiteur NON connecté réécrivait le SMIC
  global et le catalogue des webhooks (C1, C2) ; l'admin d'une société réécrivait le
  référentiel `banks` ; `anon` détenait INSERT/UPDATE/DELETE/**TRUNCATE** sur 72 tables.
  Lignes globales réservées à `service_role`, droits d'`anon` révoqués (défauts compris),
  TRUNCATE retiré à `authenticated`. 8 scénarios, **6 rouges avant**.
- **`271` — ce qu'un lecteur ne peut pas faire** : numérotation, stock, couches et
  séquences écrites par leurs seules fonctions (C3) ; périmètre `can_perform` étendu à
  **19 tables** (M8) ; `post_journal_entry` et `calculate_payslip` vérifient le droit
  (H10) ; `purchase_invoices.created_by` + `approved_by` + séparation des tâches (M9) ;
  politiques héritées supprimées (M12). 10 scénarios, **8 rouges avant**.
- **`272` — données de base** : e-mail vide → NULL (M2), devise des pièces = celle de la
  société, taux de TVA copiés à l'inscription (M13) — la clé ISO-02 `tax_rates →
  legislation_packs` l'interdisait (inscrite au registre de `check_composite_fks`).
- **X0 — le chemin de l'écran est en CI** (job `screen-path`) : banc
  `app/scripts/screen-rig/` (PostgREST réel, JWT, comptes créés par l'inscription réelle),
  scénarios `app/src/__screen__/01…15`, registre `expected_failures.json` (**33 rouges**
  des parties 2 et 3, même contrat que le registre SQL), `check-screen-writes` (baseline
  **62** gelée). Final : **15/15 fichiers, 79 verts, 33 rouges inscrits**.
- **Front (X7)** : écran des marges (colonne et coût fictif à 70 %), `<Select>` qui
  faisait tomber **4** écrans, frontière d'erreur réinitialisée par route, 19 `confirm()`
  nus → `confirmSync` (UX-03 étendu), `<tbody>` mal imbriqués, `employee_id` vide.
- Contrôles : `check_anon_grants` couvre les **tables**, nouveau
  `check_global_rows_writable` (écriture **et** lecture). Base neuve **241 migrations,
  0 erreur**, batterie SQL **81/81**, `tsc` 0, `oxlint` 0, knip 66/66, Vitest 1 504.
  [Preuve](doc/audit/VAGUE-X1U-X0-X1-X7-2026-09-28.md)
- ⚠️ **Production** : relire les paramètres légaux globaux et `banks` après déploiement
  (requêtes dans la preuve) — ils ont pu être altérés avant la fermeture.
- **Limites dites** : un `manager` n'écrit plus les 19 tables (décision D-6) ; pack DJ
  sans taux (D-11) ; même défaut ISO-02 sur `company_settings.legislation_pack_code`.


### Vague W7 (partie 1) — analytique qui circule, et un seul FEC (2026-09-28) ✅
- **Quatre défauts fermés** (sur les 14 de W7), chacun **vu rouge d'abord** :
  - **`304` — `ANA-01`, `ANA-02`, `ANA-03`.** Les **deux** déclencheurs de
    `journal_lines` étaient des placebos (`propagate_analytic_section` ne faisait
    que `RETURN NEW`, `check_analytic_balance` n'avait qu'un `IF` commenté : deux
    appels par ligne pour zéro effet), et `analytic_section_id` n'était écrit que
    par la **saisie manuelle** — les lignes de facture n'avaient même pas de
    colonne pour porter une section. La 304 ajoute le porteur
    (`invoice_lines`/`purchase_invoice_lines.analytic_section_id`, clés
    composites), fait **circuler** la section du document vers la ligne
    d'écriture (appariement par `invoice_ref` **et** par compte), **dérive** la
    section d'une ventilation multi-axes, et refuse une ventilation qui ne fait
    pas **100 %** (la règle de l'écran, tenue par la base). Mesures : T01/T02
    `column does not exist` → 1 ligne qui porte la section ; T03 `∅` → section +
    200,00 ; T04 `refus=f` → refus nommé. Et la balance analytique de l'écran est
    **bornée à l'exercice** (`getAnalyticBalance(exercice)`, choix de l'exercice
    dans l'écran), avec un test Vitest qui vérifie les filtres de date.
  - **`305` — `FEC-01`.** Une **seconde** implémentation du FEC vivait en base :
    `fec_export` en deux surcharges, **9 colonnes sur 18**, numéro **provisoire**.
    Aucune n'était appelée (l'écran bâtit son FEC à 18 colonnes et le remet à son
    validateur). Les deux surcharges sont **supprimées** ; T01 était rouge
    (`2 fonction(s) fec_export restante(s)`), il est vert.
- **Batterie** : `304` **5/5**, `305` **2/2**, et **84/84** contrôles et suites
  sur base neuve (**245 migrations, 0 erreur** — dont `270`→`272` d'une session
  parallèle) ; front `tsc` 0, `oxlint` 0, i18n fr/en/ar à parité.
  [Preuve](doc/audit/VAGUE-W7-2026-09-28.md)
- **Limites dites** : la **paie, le stock, la caisse et la production** ne portent
  pas encore de section analytique (aucune de leurs lignes sources n'en porte) —
  l'égalité « balance analytique = balance générale » n'est tenue que pour les
  **ventes et les achats** ; les lignes de TVA n'en portent pas ;
  `analytic_distribution_lines` reste écrit par l'écran.
- **Reste de W7** — énoncé le 28/09 au matin, **périmé le soir même** :
  `M01-01→03` (devise des écritures et taux de change jamais appliqué),
  `BUD-01→04` (réalisé non borné à l'exercice, engagements jamais libérés),
  `SAGE-01→03` (import en brouillon, soldes écrasés, non transactionnel) —
  10 défauts. **Tous fermés** par la suite de la journée : `306` (devises),
  `307` (budgets), **`308` — `SAGE-01→03` : l'import d'écritures est un acte
  unique, équilibré, validé, transactionnel** — et `309` (écart de change au
  règlement, réévaluation de clôture). Voir « W7 fermée (28/09) » en tête de
  fichier et [la preuve](doc/audit/VAGUE-W7-2026-09-28.md).



### Audit fonctionnel exécuté — partie 2, vague X2 : comptabilité (2026-09-28) ✅
- **Numérotation** : cette session prend **273 → 299** ; la série 300+ est à la session W7/W8.
- **`273` — valider une écriture saisie (C4, D-A)** : aucun chemin d'écran ne validait
  (« Clôturer » ne posait que `status_detail`). `validate_journal_entries(uuid[])` rend un verdict
  **par écriture** en déclenchant le noyau existant ; boutons « Valider » / « Valider la sélection »
  (écritures, saisie, brouillard), « Enregistrer et valider » **sans** séparation des tâches ;
  la clôture (journal × période, période fiscale) **refuse** les brouillons en les nommant ;
  `post_journal_entry` garde l'en-tête de la saisie (la saisie par journal échouait sur
  `analytic_section`) ; journaux : `racines_autorisees` contrôlées, `account_attente` vérifiée ;
  `entry_template_id` repointée sur `entry_templates` (toute saisie depuis un modèle était refusée).
- **`274` — données de base comptables** : `section_type` avec sa règle (une section « total »
  n'est jamais imputée) ; **9 tables** (tiers, RIB des tiers, conditions, relances, analytique,
  modèles) sous `can_perform` — un lecteur les écrivait, masqué tant qu'aucune ligne n'existait.
- **Compte de tiers (D-C)** : plus de colonnes plates — tiers lié, `partner_bank_accounts`,
  `payment_term_id`, `credit_limit`. **FEC (M1)** : une seule implémentation
  (`lib/fecValidator.ts` + `getFECExport`), libellés résolus, virgule décimale,
  `{SIREN}FEC{AAAAMMJJ}.txt`, export refusé sans SIREN ou avec une erreur majeure.
- Preuves : 273 **9/9**, 274 **5/5**, batterie **86/86** sur base neuve (247 migrations), chemin de
  l'écran **15/15** avec **21** rouges inscrits (33 → 21), `check-screen-writes` **62 → 4**.
  [Preuve](doc/audit/VAGUE-X2-2026-09-28.md)

### Audit fonctionnel — partie 2, vague X3 : paie (2026-09-28) ✅ (production : signature de l'expert en attente)
- **`275`** : un lot se crée vide ; ses totaux sont l'agrégat de ses bulletins, tenu par la base (l'écran
  les calculait avec un barème **marocain**) ; 13 tables de paie sous `can_perform` (un lecteur écrivait le
  pont paie → grand livre).
- **`276`** : grille **France 2026**, chaque taux sourcé (URSSAF 01/01/2026, RGDU, Agirc-Arrco 2025-16,
  décret Smic 2025-1228 et arrêté du 22/05/2026, BOFiP taux par défaut) ; moteur corrigé (CSG comptée une
  fois, net imposable, PAS en grille, planchers T2, RGDU une fois). Bulletins d'or au centime :
  SMIC → 1 477,93 ; 2 500 → 1 919,53 ; 4 500 cadre → 3 121,70. ⚠️ **Ne pas déployer la 276 avant la
  signature des bulletins d'or par l'expert-comptable (D-G).**
- Preuves : 275 **5/5**, 276 **6/6**, batterie **88/88** (249 migrations), écran **15/15**, registre
  **16** rouges. [Preuve](doc/audit/VAGUE-X3-2026-09-28.md)

### Audit fonctionnel — partie 2, vague X6 : trésorerie et tableaux de bord (2026-09-28) ✅ — partie 2 terminée
- **`277` (M3, D-F)** : le solde bancaire affiché est le solde **comptable** (512x au grand livre) ;
  le solde initial saisi devient un à-nouveau validé AN 512x / 890000 ; `balance` n'est plus lue.
- **M4** : deux opérations identiques le même jour sont deux opérations (référence de banque réelle,
  sinon comptage des occurrences) — `selectNewBankTransactions`.
- **`278` (M5)** : `get_kpis` lit le grand livre pour les **trois** tableaux de bord ; une facture
  validée passe à « émise ».
- Registre du chemin de l'écran : **13** rouges, tous de la **partie 3** (X4, X5).
  [Preuve](doc/audit/VAGUE-X6-2026-09-28.md)

### Audit fonctionnel — partie 3, vagues X4, X5, X8 : stock, caisse, production, contrôles (2026-09-28) ✅ — plan exécuté
- **Le registre du chemin de l'écran est VIDE** (`src/__screen__/expected_failures.json` = `[]`) :
  les 13 derniers rouges (X4, X5) sont fermés, **125/125** verdicts verts, 15/15 fichiers.
- **`280` (X4)** : un mouvement de stock porte son type (C8 — `type`/`movement_type` alignés,
  `NOT NULL`, un mouvement enregistré ne se réécrit plus) ; le stock initial est un mouvement
  `initial` au dépôt et au prix d'achat, `products.stock_quantity` n'est plus écrivable par un écran
  (M6) ; commandes fournisseur et client **à lignes**, totaux calculés par la base
  (`create_purchase_order`, `create_sales_order`) ; la réception naît de la commande confirmée au
  reste à recevoir (`create_goods_receipt_from_order`), le BL de la commande (C9, C10) ; colonnes
  « Stock : Entré / Sorti / Généré » lues sur les mouvements réels. **D-B** : les fantômes sont
  inscrits à `stock_movement_phantoms` et décidés un par un (`resolve_stock_movement_phantom`,
  panneau de l'inventaire) — rien n'est rejoué d'office.
- **`281` (X5)** : `create_pos_ticket` — ticket, lignes, paiements et **sortie de stock** en un
  appel, refusé sur session close (C12, M7) ; clôture comptabilisée (attendu = fond + espèces,
  paiements reconstitués pour les tickets anciens, pas de double sortie) ; `void_pos_ticket` rend le
  stock ; **D-E** : Espèces 530000, Carte et Chèque 511200 par société, `pos_payments` sans droit
  d'écriture ; un OF prend l'article de sa nomenclature (C11) ; dérogatoire et subvention retirés de
  la fiche d'immobilisation (**D-D**, C13).
- **M8 révélé en chemin** : `stock_reservations`, `budget_commitments`, `fixed_assets`,
  `pos_payment_methods` étaient modifiables par un lecteur → sous `can_perform`.
- Preuves : 280 **0/10 → 10/10**, 281 **0/8 → 8/8**, batterie **94/94** sur l'instantané du commit
  (256 migrations, 0 erreur), `check-screen-writes` **3 → 0**, `check-embeds` 1 518/1 518, Vitest
  **1 513**. [Preuve](doc/audit/VAGUE-X4-X5-X8-2026-09-28.md)
- **Reste (hors code)** : re-noter chaque module par une recette complète (avec P0-08) ; balayage des
  routes à rendre permanent dans le job Playwright (fait ici une fois, dans le navigateur).

### Bugs corrigés
- `auth-signup/index.ts:108` — `APP_URL` non défini → fallback string
- `create-user/index.ts:450` — `otpError` non défini → `emailSent`
- `tenant_users` trigger `revoke_expired_auditors` — récursion infinie corrigée (trigger supprimé, remplacé par pg_cron)
- `current_tenant_id()` — passé en SECURITY DEFINER pour bypass RLS sur `tenant_users`

### Sécurité
- RLS activé sur 377/377 tables du cloud (100%)
- Isolation multi-tenant vérifiée: tenant 1 voit ses données, tenant 2 ne voit pas les données du tenant 1
- `current_tenant_id()` vérifie l'appartenance via `tenant_users` + `auth.uid()`
- Aucune table avec `tenant_id` sans RLS
- Migration 94 déployée: 6 problèmes Advisor corrigés
  - `sql_migrations_tracker`: RLS activé + policy service_role uniquement
  - 5 vues (`balance_sheet`, `trial_balance`, `general_ledger`, `vat_summary`, `rls_audit`): `security_invoker=true` + filtre `current_tenant_id()`
  - Grants excessifs révoqués sur les vues (SELECT uniquement pour authenticated)
  - `rls_audit` restreint à service_role uniquement
- 1 779 policies RLS en production
- 0 deadlocks, 0 conflits, taux de rollback 3.49% (normal pour RLS)

### Storage Supabase
- 7 buckets configurés (local + cloud): `project-docs`, `accounting-docs`, `hr-docs`, `commercial-docs`, `general-docs`, `employee-documents`, `tax-grid-sources`
- Uploads/downloads testés avec succès sur local et cloud

### Real-time
- 9 tables activées pour real-time (local + cloud): customers, suppliers, invoices, journal_entries, employees, projects, project_tasks, stock_movements, bank_accounts
- Subscription WebSocket testée sur le cloud (status: SUBSCRIBED)

### Frontend (2026-09-11)
- 1240 tests unitaires passent (Vitest), 13 skipped
- TypeScript: `tsc -b --noEmit` → exit 0 (strict mode)
- Build Vite: réussi
- Bundle splitting: react-vendor, supabase, i18n, pdf, xlsx, charts, date-fns, utils
- **Chunk index: 26.49 ko gzip** (objectif < 250 ko ✅)
- Traductions chargées dynamiquement par langue (fr/en/ar en chunks séparés)
- 267 lazy-loaded routes
- ErrorBoundary avec Sentry intégré (lazy-loaded)
- 0 `window.confirm` dans src/ (remplacés par `confirmSync` de `@/lib/confirm`)
- CI: check anti-`window.confirm` dans `.github/workflows/ci.yml`
- 10 parcours E2E Playwright (`e2e/business-flows.spec.ts`)
- Hooks d'accessibilité: `useConfirm`, `useFocusTrap`, `useAnnouncement`, `useKeyboardEntry`
- `ConfirmProvider` intégré dans `App.tsx`
- xlsx et pdfjs-dist chargés dynamiquement (imports `import()`)
- Pages publiques lazy-loaded (Landing, Login, Terms, Privacy)
- OpenAPI spec publiée (`openapi.json`)
- API publique: idempotence (`Idempotency-Key`), journal des appels, format d'erreur uniforme
- Edge Functions `public-api` et `outgoing-webhooks` déployées sur le cloud

### Monitoring
- Sentry installé (`@sentry/react` v10.68.0)
- `AppErrorBoundary` capture les erreurs React et envoie à Sentry
- 35 `console.error` dans les Edge Functions pour le logging
- Logs Edge Functions visibles via Dashboard Supabase > Functions > Logs

### Essaim QA — deuxième passe : l'outil qui accusait à tort, et les vrais défauts (2026-09-29/30) ✅
- **Le harnais se trompait sur onze points, chacun mesuré** : l'inventaire
  **inventait six routes** (il perdait le parent d'une route auto-fermante —
  `/expenses`, `/documents`, `/manager/approvals` au lieu de `/employee/…`, donc
  le portail salarié n'était **jamais** visité) ; `oversized` ignorait le
  conteneur défilant que son propre commentaire annonçait ; une pile de
  **notifications** (`aria-live`) passait pour une fenêtre ; un clic qui
  **navigue** attribuait la fenêtre d'un autre écran ; `namedFields` ne créditait
  pas un champ **dans son `<label>`** (12 fenêtres, 24 verdicts faux) ; un onglet
  annonçant « (0) » était accusé ; **aucun budget d'interaction** (400 boutons ×
  2,5 s = 16 min par écran — c'est le gel à 156 visites) ; le dossier de shards
  n'était pas vidé (« 7 ouvriers » pour 4) ; un **502** local était imputé aux
  écrans ; l'écran source d'une route était son **enveloppe**
  (`/settings/api-docs` → `ProtectedRoute.tsx`) ; `worklist` omettait des classes
  (`onglet_inchange`). Le harnais porte désormais un **jeton de tournée** (le
  validateur refuse de juger deux tournées mélangées) et un filtre `--routes=`
  pour rejouer une ligne.
- **Corrigé côté produit** : champs de lignes (avoirs vente/achat, devis,
  écritures), **cinq** taux de change, distribution analytique, produit des
  devis (aria-label) ; cibles tactiles (Oui/Non de la banque 23×24 → 24×24,
  barres de Gantt ≥ 24 px, cinq « Copier » de la doc d'API, « Ajouter une
  ligne »/« Équilibrer », boutons « Fermer » partagés, guide de bienvenue) ;
  lettrage en `grid-cols-1 lg:grid-cols-3` (22 px sur téléphone) ; tableau
  « saisie par pièce » (1 100 px sous `overflow-hidden`) qui défile ; **portail
  salarié** : six lectures `employees` en `.single()` → `.maybeSingle()` (un
  compte connecté n'est pas forcément un salarié) — le 406 `PGRST116` disparaît,
  et `/employee` et `/employee/profile` **disent** « Aucun dossier de salarié »
  (fr/en/ar) au lieu de ne rien rendre ; boutons de dépliage nommés ; écran
  « accès refusé » des packs de plan comptable titré.
- **Tournée de confirmation (30/09, 05:38Z → 05:57Z)** : société re-semée par
  l'inscription réelle puis remplie par `qa:amorce` (74 lignes, 0 échec), quatre
  ouvriers, deux gabarits — **668 visites, 334 routes, 0 défaut**, quatre shards
  au même jeton. Le registre `.qa-baseline.json` est **VIDE** : les 47 défauts de
  la tournée du matin, puis les 23 restants, ne se reproduisent plus.
- `tsc` 0 · `oxlint` 0 · parité i18n fr/en/ar ✓ · Vitest **1 513 / 1 513** (38
  ignorés, 52 fichiers) · plafond de code mort **66/66** ✓.
- ⚠️ **Environnement** : la pile locale a été saturée plusieurs heures
  (PostgREST « Thread killed by timeout manager », semis d'un banc neuf
  impossible) et une **session parallèle** travaillait dans le même dépôt — elle
  a remis deux fois le mot de passe du rôle `authenticator` à sa valeur de banc,
  cassant PostgREST. Ces incidents n'ont jamais été imputés aux écrans : la
  tournée **s'arrête** désormais sur un 502/503, et un jeton de tournée empêche
  de juger deux tournées mélangées.
- **Les quatre limites de cette passe sont levées** : le guide de bienvenue est
  porté en i18n (`common.guide.*`, fr/en/ar, 39 clés vérifiées une par une) ; il
  est **mesuré** par un scénario dédié (`scripts/qa/guide.mjs`, cinq étapes,
  Échap, cibles, quatre gabarits — 0 défaut) parce que la tournée le pose comme
  déjà vu ; les **états vides** sont couverts par une seconde société
  (`qa:seed --session=session-vide.json`) et une seconde vague
  (`qa:run --states=remplie,vide`, chacune son jeton et son préfixe de shard) ;
  les **quatre gabarits** sont balayés (`--viewports=all`). En chemin, deux
  défauts de harnais trouvés par la mesure : les états de comptes s'écrivaient
  `accounts/ouvrier-0.json` **sans le nom de la session** (le second banc
  écrasait le premier, la vague « remplie » mesurait la société vide), et un
  écran **encore en chargement** (squelette `animate-pulse`) se mesurait comme un
  écran sans titre ou à liste vide — l'ouvrier attend la fin du squelette et
  recharge une fois avant d'imputer un « Failed to fetch ».
- **Deux défauts trouvés par cette passe large, corrigés** : `/settings/chart-packs`
  ne rendait **rien** pendant la vérification des droits (page blanche sans titre)
  et `/reporting/financial` montrait son état vide **sans titre** ; la société
  neuve a révélé une liste de comptes bancaires **vide** sur
  `/banking/reconciliation-state` (elle dit maintenant « aucun compte »). Rejoués
  sur les **quatre gabarits et les deux sociétés** : **0 défaut**. Et un ouvrier
  qui perd sa session **se reconnecte** (8 reconnexions mesurées sur une passe) ;
  une visite qui voit la pile tomber (502/503/504, réseau) ou la session
  s'évaporer **ne juge rien** — elle est écartée et journalisée (39 « pages
  blanches » de 13 caractères décrivaient la pile, pas les écrans, sous une charge
  hôte de 20 à 46).

