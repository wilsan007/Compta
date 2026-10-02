# Vague L23 tranche 1 — le journal d'événements unifié (415) — 02/10/2026

> **Objet.** Lot **L23** du plan des chaînages : « journal unique + automatisations +
> webhooks branchés sur les **mêmes** événements » (I-06). Ses dépendances — **L0** (socle,
> 252) et **L2** (portes CI) — sont livrées : c'est le **premier lot de l'horizon L16 → L24
> qui n'est pas bloqué**, et c'est un prérequis de L22 (moteur de règles) et L24
> (explicabilité, assistant). Les lots voisins de l'horizon sont bloqués : L16 dépend de
> L8 → L15, L17 de L11, L18 de L12/L13 (et de colonnes qui n'existent pas), L19 de L15,
> L21 de L10/L14/L20, L22 de L5/L11, L24 de L6/L21/L23.
>
> **Méthode** — celle de la partie 4 du plan, appliquée point par point : défaut **mesuré
> avant** (test rouge), migration, suite verte, portes G1 → G7, non-régression, preuve
> dans le même commit.

## 1. Le défaut, mesuré avant — chiffres, pas opinions

Base neuve de la branche `partie-1-stabiliser` (39a7107) : **272 migrations, 0 erreur**.

| # | Mesure | Valeur |
|---|---|---|
| 1 | Fonctions qui insèrent dans `webhook_delivery_queue` depuis `domain_events` | **0** — aucun pont |
| 2 | Événements écrits dans `domain_events` par le socle (`emit_domain_event`) | **27** |
| 3 | Ces 27 événements qui atteignent la file de livraison | **0** |
| 4 | Les 2 seules sources historiques (`notify_webhook_invoice_created/_paid`) écrivent dans | `webhook_delivery_logs`, `endpoint_id = NULL` — **le journal des envois, pas une file** : l'Edge Function `outgoing-webhooks` consomme `webhook_delivery_queue` par `claim_webhook_batch` (234) et n'a jamais lu ces lignes |
| 5 | Événements promis par `webhook_event_catalog` | **15** |
| 6 | … dont **sans aucun producteur** (promesse morte : un abonnement ne recevrait rien) | **13** — dont `manufacturing_order.completed`, dont le nom réellement produit est `manufacturing_orders.completed` (le singulier n'existe nulle part) |
| 7 | Producteurs réels absents du catalogue (effets invisibles du client) | **27 sur 27** |
| 8 | `webhook_delivery_queue` sous `FORCE ROW LEVEL SECURITY` | **non** (`relforcerowsecurity = f`) — seule table de la chaîne des webhooks dans ce cas ; §3.5 l'exige |

La conséquence métier : **un client qui configurait un webhook ne recevait jamais rien** —
ni sur les 13 promesses mortes du catalogue, ni sur les 27 événements réels du socle. Les
deux seuls événements jamais « enfilés » (`invoice.created`, `invoice.paid`) étaient
consignés dans une table que personne ne lit pour envoyer.

## 2. Ce que la 415 pose

| Élément | Rôle |
|---|---|
| `chain_l23_enfiler(event_id)` | **LE PONT** : lit l'événement, enfile UNE livraison par point actif de **la société de l'événement** abonné (liste explicite, `*`, ou sans filtre — les trois sémantiques de l'Edge Function). `tenant_id` vient de l'ÉVÉNEMENT, jamais de la session (§4.1 point 7). |
| `uq_webhook_queue_source_event` | **La clé d'idempotence structurelle** : `(tenant, point, source)` — rejouer rend 0, jamais un `IF` recopié. Les lignes sans source (celles de l'Edge Function) ne se voient pas entre elles : comportement actuel préservé. |
| `zz_l23_webhook_fanout` | Déclencheur `AFTER INSERT ON domain_events` : le pont ne peut pas être contourné par un maillon qui émettrait « à la main ». |
| `notify_webhook_invoice_created/_paid` réécrites | Elles **parlent désormais le même langage** : `emit_domain_event` — même pont, même file. Les noms `invoice.created`/`invoice.paid` sont conservés : une intégration existante ne change rien. `webhook_delivery_logs` reste ce qu'il est (le journal des envois, écrit par l'Edge Function). |
| Catalogue **convergent** | Les **29** événements réellement produits sont déclarés actifs (27 du socle + 2 historiques), chacun avec sa catégorie et sa description. Les **13 promesses mortes sont éteintes, pas supprimées** : `is_active = false` avec la RAISON écrite (dont le renvoi au nom pluriel pour `manufacturing_order.completed`). |
| `webhook_guard_abonnement` | Garde `BEFORE INSERT OR UPDATE` sur `webhook_endpoints` : s'abonner à un événement inexistant est **refusé** en le nommant (règle d'urbanisme §E.5, appliquée). |
| Contrat d'effet | `document_effects (domain_events, created, event.webhook.enqueued)` — **non réversible, motif écrit** (§4.1 point 4) : une livraison enfilée ne se « défile » pas ; le refus d'envoi reste tracé par le statut `blocked`. |
| `FORCE ROW LEVEL SECURITY` | Sur la file de livraison (§3.5). |

**Pourquoi un déclencheur et pas un appel dans `emit_domain_event`** : il attrape tout
producteur (y compris demain, un appel direct au journal), il ne change pas la signature
d'une fonction que 25 maillons appellent déjà, et une erreur du pont fait échouer
l'événement métier — c'est voulu : une livraison promise qui ne part pas doit se voir.


## 3. La preuve — la suite 415, rouge avant, verte après

8 scénarios, gabarit §4.1 (T-1 → T-4) + revue §4.3. **Rouge mesuré avant la migration**
(7 rouges, T07 vert — un pont absent ne coûte rien), **8/8 verts après**, sur base neuve
de **273 migrations, 0 erreur** (272 + la 415) :

| Test | Ce qu'il prouve | Avant | Après |
|---|---|---|---|
| T01 | le chemin **réel** (fonction du produit → `emit_domain_event` → file) produit UNE livraison, avec l'URL, le secret et la source | événements=1, livraisons=**0** | livraisons=1, source présente |
| T02 | rejeu (D1) : `chain_l23_enfiler` rappelé sur le même événement rend **0**, la file ne bouge pas — c'est la clé, pas un `IF` | ajout=−1 (fonction absente) | ajout=0, total=1 |
| T03 | la non-réversibilité du pont est **déclarée** avec son motif | contrat introuvable | trouvé, `reversible=false`, motif écrit |
| T04 | isolation (D-8) : contexte posé sur **B**, événement émis pour **A** → la ligne porte A, **B reste vide** | A=0, B=0 | A=1, B=0, contexte=B prouvé |
| T05 | le catalogue est vrai dans les **DEUX sens** — porte **auto-entretenue** : elle relit les corps des fonctions en base | 15 promesses mortes, 27 producteurs invisibles | 0 et 0 |
| T06 | refus explicite : abonnement à `facture.magique` **refusé**, message nommant l'événement, la règle et le module | accepté (point créé) | refusé, 0 point |
| T07 | p95 du pont **mesuré** (200 enfilages, abonnement `*`), confronté au budget §3.3 (≤ 50 ms) | 0,030 ms (rien ne tournait) | **0,072 ms** — le pont coûte ~40 µs par événement fanouté |
| T08 | structure : la file est RLS activée **et forcée**, une politique | forcée=**f** | forcée=**t**, 1 politique |

## 4. Les portes — vues rouges, puis vertes, avant le commit

Deux portes ont **vu rouge pendant l'écriture** (c'est leur rôle) et sont corrigées
dans le même commit :

- **`check_anon_grants`** : les 3 fonctions nouvelles étaient `EXECUTE` pour `PUBLIC` —
  un visiteur **non connecté** pouvait appeler `chain_l23_enfiler`. Corrigé par la
  convention du dépôt (`REVOKE ALL … FROM PUBLIC, anon, authenticated`, cf. 410) ;
  vert après.
- **`check_forced_rls_writers` (G7)** : la file forcée porte le compteur à 314 ;
  plafond réinscrit **daté** (313 → 314) dans le même commit.
- **`check_bt_grid` (G1)** : deux nombres ont **baissé** — `rls_sans_force` 55 → **54**
  (la file passe sous FORCE) et `sans_index_societe` 79 → **78**
  (`uq_webhook_queue_source_event` mène par `tenant_id`, la file gagne son index de
  société). Plafonds réinscrits datés dans le même commit, selon la règle G1
  (« une amélioration s'inscrit, elle ne se constate pas »).

## 5. Non-régression, mesurée

Sur le worktree propre (HEAD 39a7107 + 415 uniquement) :

- **Contrôles verts** : G1 (grille BT), G2 (contrat d'effet — le contrat déclaré n'est
  jamais appelé par un maillon : NOTICE publiée, pas un échec, c'est la moitié assumée
  de la porte), G4 (garde de société — le pont nomme `tenant_id`), G5 (**102/102** suites
  branchées après câblage), G6 (banc : p95 total **0,146 ms** pour 50 ms de budget,
  1 000 tours), G7, anon grants, global rows, status writes, trigger reachability,
  composite FKs, policy duplicates, roles opposables.
- **Suites vertes** : 252 (socle), **234** (file de webhooks), **236** (writes SECURITY
  DEFINER), **257** (colonnes Edge), **270** (accès anonymes), 168 (SSRF), 102, 105, et
  les chaînages **400, 401, 402, 403, 404, 406, 409, 410, 411, 412, 413**, 407, 408.
- **Types générés sans écart** : régénérés sur base neuve **où aucune suite n'a tourné**
  (365 tables) — le fichier commité est identique, car la 415 ne pose ni table ni colonne.
- `check_plpgsql` : non exécuté localement (extension absente de l'image, comme les
  vagues précédentes l'ont documenté) — la CI l'installe.

## 6. Limites dites

- **Le pont n'émet pas de notification applicative** (`notifications`) : c'est un lot
  séparé (L23-b automatisations). La table `notifications` garde ses déclencheurs
  propres ; aucune écriture n'a été retirée.
- **La livraison HTTP reste le rôle de l'Edge Function** : le pont enfile, il n'envoie
  pas. Une URL devenue interdite depuis l'abonnement est bloquée à l'envoi (statut
  `blocked`, garde SSRF), pas à l'enfilage — comportement inchangé.
- **La trace d'un refus d'abonnement ne survit pas au rollback** de la transaction
  appelante (limite transactionnelle de PostgreSQL, dite par le socle 252 §5 et
  reconstatée ici : le message est rendu à l'appelant, c'est lui qui le porte).
- **`invoice.overdue`** est éteint alors que la fonction `notify_invoice_overdue` existe :
  elle écrit dans `notifications`, **pas dans le journal d'événements** — l'événement
  « facture en retard » existe à l'écran, pas sur le bus. La ligne du catalogue sera
  réactivée le jour où un maillon l'émet (T05 l'exigera).
- **T05 est une porte de texte** : elle lit les littéraux des corps de fonctions, pas
  les exécutions. Un événement construit dynamiquement (concaténé) y serait invisible —
  le socle ne le fait pas (vérifié : les 27 noms sont des littéraux), et le jour où un
  maillon le ferait, la revue §4.3 point 1 le verrait.

## 7. Ce qui reste pour L23

- **L23-b** : les automatisations (« devis accepté → créer la commande et notifier ») —
  table de règles d'automatisation branchée sur le journal, moteur, suite dédiée.
- **L23-c** : la lecture écran du journal et du catalogue (l'écran des webhooks liste
  aujourd'hui le catalogue — il affichera désormais des événements **tous réels**, mais
  la raison d'une ligne éteinte doit se lire à l'écran, pas en base).

*Porté par la branche courante ; plage `415` → `429` inscrite dans `AGENTS.md` le 02/10/2026.*
