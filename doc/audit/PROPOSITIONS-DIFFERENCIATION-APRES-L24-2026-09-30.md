# Propositions de différenciation — **après L24** (30 septembre 2026)

> **Statut : PROPOSÉ, non planifié.** Ce document **n'est pas** dans le plan des
> chaînages (`L0` → `L24`) : il vient **après**. Son objet est d'être **exécuté**
> à la suite du travail en cours, et d'être **retrouvable** le jour où on y
> arrive — c'est pourquoi il est signalé dans `AGENTS.md` (« À faire plus tard »)
> et dans `RESTE-OUVERT` (§2.I et §5).
>
> **Garde-fou d'entrée — non négociable.** Rien ici n'est commençable avant que
> **L3 → L4 → L5** soient livrés **et prouvés** (`P6` attend en plus L6/L23/L24) :
> ces propositions ne sont pas des fonctions, ce sont des **lecteurs de la
> preuve** — sans les 8 épreuves (`L3`) et l'indice de cohérence (`L4`), il n'y a
> **rien à certifier, rien à rejouer, rien à citer**.
>
> **Ce qui est déjà au plan (à ne pas se réapproprier)** : les **12 innovations**
> `I-01` → `I-12` (Vue Chaîne, contrat d'effet, indice de cohérence, simulateur
> d'impact, banc d'épreuve publié, événements unifiés, règles client,
> explicabilité, régularisation guidée, absence transverse, localisation,
> assistant) et les lots `L16` → `L24`. Voir
> [`PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md`](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md)
> §Phase F, et [`REFERENTIEL…`](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md) §D.4.

---

## 0. Le terrain : on ne bat pas SAP sur la largeur

Le référentiel a **compilé** les mécanismes des éditeurs cités (partie C, sources
en lien), et j'ai **revérifié ponctuellement** (30/09) : la page SAP *Document
Flow* dit mot pour mot **« the individual documents form document chains »** et
affiche **« all preceding and subsequent documents »**, l'annulation **comprise**
(« invoice and invoice reversal ») ; ERPNext **gèle la période** par type de
document (*Accounting Period*) ; chez **Odoo**, la chaîne est surtout apportée par
des **modules tiers** (cherchés le 30/09 : « Sale Order Trace Report », « Stock
Move Traceability »…), donc **pas native**.

**Conclusion opérationnelle :** avoir une chaîne, une vue, un score n'est **pas**
un différenciateur — SAP le fait depuis vingt ans, et les concurrents des PME
(Sage, Odoo, Pennylane) en ont des morceaux. On se différencie sur **cinq
faiblesses de SAP qui ne sont pas des bugs, mais son architecture** :

| Faiblesse structurelle | Pourquoi elle ne se corrige pas |
|---|---|
| Lourd : des mois de mise en œuvre, des consultants | c'est son modèle (conseil) |
| Flux documentaire **par module** — la paie n'y est pas | découpage historique SD/MM/FI/HR |
| Le « pourquoi ce chiffre » exige un consultant | la connaissance est dans les têtes, pas dans le produit |
| **Le client ne peut pas vérifier** : les tests sont internes | aucun éditeur ne publie ses écarts |
| Sortir coûte cher | l'enfermement est une rente |

**D'où la thèse de ce document :** notre différenciateur n'est pas « plus de
fonctions », c'est **la preuve, l'explication et la sortie libre**.

---

## 1. Les huit propositions

> Charges **PROPOSÉES** (ordres de grandeur à valider), mesures **à produire**.
> Chaque proposition porte **un indicateur** : c'est la doctrine du dépôt — un
> lot qui ne bouge pas un chiffre n'est pas un lot.

### P1 — Le certificat d'intégrité, signé et daté 🏆

| | |
|---|---|
| **Le client voit** | Une attestation : *« au 30/09/2026 à 14 h 02, cette comptabilité est cohérente : 20/20 invariants, 62/62 chaînes éprouvées, 0 écart »*, la **liste des écarts** s'il y en a, et l'**empreinte** de la chaîne d'événements (`nf525_event_log`, revérifiée par `verify_nf525_chain`) |
| **Pourquoi un leader ne le fait pas** | il faudrait **publier ses écarts** ; et le flux SAP est éclaté par module |
| **Dépend de** | `L4` (`audit_chains`, `chain_invariants`), `L3` (rapport d'épreuves), `verify_nf525_chain` (`91`/`267`, déjà là) |
| **Charge PROPOSÉE** | **2-3 j** |
| **L'indicateur qui bouge** | nombre de certificats **remis à un tiers** (expert-comptable, banque, assureur) |
| **Limite à dire** | un certificat **n'est pas un avis d'audit** — le mot doit être choisi avec l'expert-comptable ; et il faut décider **qui signe** (la société, le système, un tiers) et **ce qui est exposé** |

### P2 — Le banc d'épreuves exécuté sur les données du prospect (avant la signature)

| | |
|---|---|
| **Le prospect voit** | *« Donnez-nous votre FEC / votre fichier Sage : sous 24 h vous recevez le rapport des 8 épreuves sur **vos** données — 7 chaînes fragiles, voici lesquelles. »* |
| **Pourquoi SAP ne le fait pas** | l'installation prend des mois ; ses tests ne sortent pas |
| **Dépend de** | `L3` (moteur paramétré), l'import `308` (livré), le harnais de test existant (`_mk_tenant`, `_rec`, registre) |
| **Charge PROPOSÉE** | **3-4 j** |
| **L'indicateur qui bouge** | taux de conversion des démos faites **avec** le rapport |
| **Limite à dire** | **confidentialité** : les données d'un prospect ne rentrent pas dans la base de production — il faut un **bac à sable jetable**, et l'écrire noir sur blanc |

### P3 — L'audit de reprise, à l'import

| | |
|---|---|
| **Le client voit** | non pas « 1 200 écritures importées », mais *« 42 anomalies dans votre ancienne base : 12 comptes orphelins, 8 doublons, 6 écritures déséquilibrées — les voici, voici la correction »* |
| **Pourquoi c'est fort** | c'est le moment où le client **constate que son ancien outil lui mentait** — avant d'avoir payé. Et l'écran d'import Sage **existe déjà** |
| **Dépend de** | `308` (import en **une** transaction : équilibré, validé, soldes cumulés — livré), `300` (CA), `SageImportPage` |
| **Charge PROPOSÉE** | **2-3 j** |
| **L'indicateur qui bouge** | anomalies détectées par reprise ; **temps de reprise** |
| **Limite à dire** | **rapporter, pas bloquer** : un déséquilibre global est déjà refusé (`308`) ; les autres anomalies se **listent** |

### P4 — La machine à remonter le temps (« vos comptes tels qu'au 31/12 à 23 h 59 »)

| | |
|---|---|
| **Le client voit** | il choisit une date **passée** et l'état se **rejoue** : quels liens étaient **actifs**, à quel **tour**, quelles écritures, quelle version d'un prix de revient — et *« voici ce que le mois dernier a changé dans les mois précédents »* |
| **Pourquoi SAP ne le fait pas facilement** | il sait le faire **par morceaux** (simulations, versions) ; pas de bout en bout **avec la paie, le stock et les projets** en un clic |
| **Pourquoi c'est presque gratuit chez nous** | chaque lien est **daté**, chaque effet est **versionné** (`document_links.tour`, `312`), chaque événement est **horodaté** (`domain_events`) — la matière existe depuis `310`/`312` |
| **Charge PROPOSÉE** | **3-5 j** (lecture + un écran ; pas de réécriture de l'existant) |
| **L'indicateur qui bouge** | **0 heure de consultant** pour répondre à un contrôle ou à une demande de banque |
| **Limite à dire** | ce n'est **pas** une réécriture du passé : la reconstruction est **en lecture seule**, elle ne « remet pas » les données dans cet état |

### P5 — La documentation vivante (le contrat d'effet rendu au client)

| | |
|---|---|
| **Le client voit** | un **catalogue** : « pour chaque action, voici **exactement** ce que le logiciel va écrire — quel compte, quel journal, quel stock, quelle paie » |
| **Pourquoi c'est unique** | SAP vend des **manuels** ; ici le catalogue est **généré depuis le code** et **garanti par la CI** — la porte `G2` (`check_effects_contract.sql`) refuse toute dérive : **une documentation qui ne peut pas mentir** |
| **Dépend de** | `document_effects` (`313`, livré) + la porte `G2` (livrée) + un écran de lecture |
| **Charge PROPOSÉE** | **3 j** |
| **L'indicateur qui bouge** | écart doc ↔ code : **impossible par construction** (c'est la porte qui le garantit) |
| **Limite à dire** | 32 chaînages non nommés n'ont **pas** de contrat aujourd'hui : le catalogue sera **partiel** tant que L1/L3 ne les couvrent pas — et `G2` **cassera** quand l'un arrivera sans contrat, ce qui est voulu |

### P6 — L'IA qui cite (et qui refuse de répondre sans preuve)

| | |
|---|---|
| **Le client voit** | *« Pourquoi le solde de ce fournisseur est-il 12 400 ? »* → réponse **avec les pièces** (facture, avoir, règlement, écart de change) ; et si la preuve manque : *« je ne peux pas répondre : la chaîne de ce montant est incomplète »* |
| **Pourquoi c'est possible ici** | le modèle répond **uniquement** en lisant `document_links` + `domain_events` + le contrat d'effet : **l'hallucination devient structurellement impossible** sur un chiffre. Ligne de vente : *« notre IA n'invente pas : elle cite. »* |
| **Dépend de** | `I-01` (`L6`), `I-06` (`L23`), `I-08` (`L24`), `I-12` (`L24`) |
| **Charge PROPOSÉE** | **5 j** (après L24) |
| **L'indicateur qui bouge** | **0** réponse chiffrée sans citation — et un **test qui exige le refus** quand la preuve manque |
| **Limite à dire** | c'est le domaine où il est le plus facile de **mentir en marketing**. Règle du dépôt : **un test rouge d'abord** sur « l'assistant refuse sans preuve », sinon la promesse n'existe pas. Et l'IA reste **hors des écritures** : elle lit, elle n'écrit jamais |

### P7 — La sortie aussi rapide que l'entrée (anti-enfermement)

| | |
|---|---|
| **Le client voit** | un export **intégral** en un clic : `FEC` + les pièces + **la chaîne** + les événements — et on le **dit** |
| **Pourquoi c'est un argument** | l'enfermement est **la rente** de SAP ; la sortie libre est un **argument de confiance** face à un éditeur installé |
| **Charge PROPOSÉE** | **2 j** (tout est dans une seule base ; le FEC existe, `M1`) |
| **L'indicateur qui bouge** | temps de sortie mesuré, **publié** |

### P8 — L'API « chaîne » + les packs de règles par pays

| | |
|---|---|
| **Le client voit** | chaque maillon est un **événement** : un partenaire (expert-comptable, intégrateur) branche ses automatisations ; et des **packs de règles prêts** par pays/métier (« DJ-EP », SYSCOHADA…) |
| **Pourquoi c'est un levier** | c'est l'**effet de réseau** que SAP tire de son écosystème, ramené à l'échelle des PME et **par pays** |
| **Dépend de** | `I-06`/`L23` (événements + webhooks), `I-07`/`L22` (règles client), `I-11`/`L24` (localisation) |
| **Charge PROPOSÉE** | **2 j** de socle (l'API), les packs venant **avec les pays** |
| **Limite à dire** | un pack de règles non testé est un **piège** : il devra passer les mêmes portes (`G2`, suites) que le reste |

---

## 2. L'ordre d'exécution (et ce qui bloque quoi)

```
L3 (banc D1→D8) ─▶ L4 (indice de cohérence) ─▶ L5 (écrans Robustesse / Cohérence)
                          │
                          ├─▶ P1 (certificat)          ← 2-3 j : monétise tout ce qui précède
                          ├─▶ P2 (banc prospect)       ← 3-4 j : l'arme commerciale
                          ├─▶ P3 (audit de reprise)    ← 2-3 j : l'entrée chez le client
                          ├─▶ P4 (remonter le temps)   ← 3-5 j : la dimension temps
                          └─▶ P5 (documentation vive)  ← 3 j  : la doc qui ne peut pas mentir
                                    │
                                    └─▶ L6 / L23 / L24 ─▶ P6 (IA qui cite)
```

**P7 et P8** ne dépendent d'aucun lot futur : P7 est un **export** (2 j, faisable
dès maintenant), P8 attend `L23`/`L22`/`L24`.

**Ordre conseillé** : **P1 → P3 → P2 → P4 → P5 → (L6/L23/L24) → P6**. P1 d'abord
parce qu'il **monétise** ce que L3/L4/L5 viennent de produire ; P3 ensuite parce
qu'il sert **à l'entrée** d'un client (l'import), là où le besoin est immédiat.

---

## 3. Le positionnement, en une phrase

> **SAP vend un ERP. Nous ne vendrons pas « un ERP moins cher » : nous vendrons
> la première comptabilité qui *prouve* ses chiffres** — avec un **certificat**
> qu'on peut remettre à un tiers.

---

## 4. Ce qu'il ne faut PAS tenter (l'honnêteté)

| Ne pas essayer | Pourquoi |
|---|---|
| La **profondeur industrielle** (MRP-II avancé, GPAO/GMAO de niveau SAP) | 40 ans d'écart, aucun rendement pour le marché visé |
| Les **certifications sectorielles** (aéronautique, pharma, automobile) | délais et coûts déraisonnables |
| La **personnalisation illimitée** | c'est **la maladie** de SAP : chaque client devient impossible à mettre à jour. Le plan l'a déjà bornée (règles `I-07` + contrats `I-02`, **tous deux testés**) — ne pas rouvrir cette porte |
| **Beaucoup de pays d'un coup** | le délai externe le plus long du projet, ce sont les **14 documents djiboutiens**. Un pays, puis deux |
| Une **IA qui écrit** dans la comptabilité | elle doit **lire et citer**, jamais écrire : le contrôle des écritures reste le noyau (`187`/`273`) |

---

## 5. Le signalement : où ce document est référencé (pour ne pas l'oublier)

| Où | Ce qui y a été ajouté le 30/09 |
|---|---|
| [`AGENTS.md`](../../AGENTS.md) — section **« À faire plus tard (rappels) »** | un rappel nommé renvoyant ici, avec les 3 propositions prioritaires (P1, P3, P2) |
| [`RESTE-OUVERT-2026-09-26.md`](RESTE-OUVERT-2026-09-26.md) — **§2.I** | la liste des huit propositions, avec le garde-fou d'entrée (rien avant `L3`→`L4`→`L5`) |
| [`RESTE-OUVERT-2026-09-26.md`](RESTE-OUVERT-2026-09-26.md) — **§5** (mémoire du dépôt) | la ligne de ce document, pour qu'il soit trouvé en même temps que les preuves |
| **Ce document** | le détail de chaque proposition, sa dépendance, son indicateur et ses limites |

**La règle à appliquer le jour où on y arrive** : le jour où **`L3` est livré et
prouvé**, relire ce document, ouvrir **P1** (le moins risqué, le plus vendable),
puis **P3** — et **mettre à jour ce §5** avec la date et la preuve, comme pour
tout lot du dépôt (un lot = un indicateur qui bouge, une preuve dans le même
commit).

---

## 6. Les cinq questions, et **les réponses proposées** (30/09)

> ⚠️ **Statut : PROPOSÉES.** Elles sont argumentées, et appuyées sur ce que le
> dépôt possède **déjà** (vérifié le 30/09) — mais **la décision appartient au
> produit**. Le jour où elle est prise, on écrit ici **la date et le choix**,
> sans effacer la proposition : c'est ainsi que ce document reste utilisable.

**Ce que le dépôt a déjà, et qui a pesé sur ces réponses :**

| Déjà là | Où le constater |
|---|---|
| Une **attestation par période** existe déjà | `get_nf525_attestation(p_period)` (`152`) lit `nf525_period_closures` et appelle `verify_nf525_chain` |
| La **vérification de la chaîne** existe | `verify_nf525_chain(début, fin)` (`134`) |
| Le **canal vers le comptable existe** | `AccountantPortalPage.tsx` ; rôles **`accountant`** et **`auditor`**, **lecture seule** (`view`), accès auditeur **expirant** (`auto_revoke_expired_auditors`) |
| ⚠️ L'**expert-comptable référent n'est pas désigné** | `👤-4`, ouvert dans `RESTE-OUVERT` |

### Q1 — Qui signe ? → **proposé : le système émet, la société endosse ; jamais un tiers**

Le certificat est un **fait technique**, pas une opinion : *« au 30/09 à 14 h 02,
sur la base X, **version de migrations Y**, ces 20 invariants tenaient, ces 62
chaînes ont été éprouvées, empreinte `a41f…` »*. Seul le **système** peut
l'affirmer ; ce qui engage quelqu'un, c'est **qui le remet** → la **société**
(nom + date) l'endosse.

**Pourquoi jamais un tiers :** un audit et une attestation d'expert-comptable
sont des **missions réglementées** (normes NEP en France) — on ne peut pas les
produire, et les faire signer par un tiers expose **et** coûte. Surtout, cela
détruit le différenciateur, qui est d'être **automatique, rejouable et daté**.

**Le mot compte : « attestation d'intégrité technique »**, avec la mention
écrite une fois pour toutes : *« ne constitue ni un audit, ni une attestation de
l'expert-comptable, ni une certification légale »* — sinon le premier comptable
venu la refuse, et il aura raison.

### Q2 — À qui en premier ? → **proposé : l'expert-comptable, et deux lectures pour un seul document**

**Lui d'abord**, parce que c'est **le seul destinataire qui dira non si c'est
faux** : un certificat validé par quelqu'un qui ne peut pas le vérifier ne vaut
rien. Et **la distribution existe déjà** (portail comptable ; rôle `auditor`
**en lecture seule**, dont l'accès **expire tout seul**). La **banque** vient
deuxième — elle veut un **bilan**, pas une chaîne d'événements ; l'assureur,
très loin derrière.

⚠️ **Le blocage réel** : `👤-4` n'est pas fait, et en PME djiboutienne
l'expert-comptable n'existe pas toujours. D'où **un artefact, deux lectures** :

| | Contenu | Pour qui |
|---|---|---|
| **Page 1** | le **score**, les écarts, en langage simple (« 20/20 invariants, 0 écart ») | le **dirigeant** |
| **Annexe** | les invariants, les **empreintes**, et **le moyen de re-vérifier** (`verify_nf525_chain`, `audit_chains`) | l'**expert-comptable**, la **banque** |

👉 **Un certificat que le destinataire ne peut pas vérifier est un PDF
décoratif** : il ne quitte pas le tiroir.

### Q3 — Où tournent les données du prospect ? → **proposé : chez lui si possible ; chez nous, base jetable ; jamais la production**

| # | Où | Pourquoi |
|---|---|---|
| **1** | **Il l'exécute lui-même** (une commande, un conteneur documenté) | zéro transfert, zéro exposition — **et c'est plus vendeur** : « voici comment vous vérifiez vous-même » |
| **2** | **Base jetable chez nous** : conteneur éphémère, **sans sauvegarde**, détruit sous **24-72 h**, NDA signé, on ne garde que **l'agrégat** | le défaut réaliste quand le prospect n'est pas technique |
| **3** | ❌ **une « société prospect » dans la base de production** | **la faute classique** : elle entre dans les **sauvegardes**, les exports et la **RLS** — et un jour dans un audit. **À exclure par écrit** |

**Règle de conception :** le rapport est **agrégé d'abord** (une page de
scores) ; les pièces (numéros, montants) **seulement si le prospect le demande**.

### Q4 — L'empreinte NF-525 ? → **proposé : oui, en annexe, comme un mécanisme vérifiable — jamais comme une conformité**

**Oui**, parce que c'est la **meilleure preuve de non-modification** disponible
aujourd'hui, et qu'elle est **déjà testée** (`nf525_event_log`,
`verify_nf525_chain`, `get_nf525_attestation`, `nf525_period_closures`).

| ✅ À écrire | ❌ À ne jamais écrire |
|---|---|
| *« Empreinte de la chaîne d'événements de caisse (**mécanisme NF-525**), vérifiable par `verify_nf525_chain` »* | *« **Conforme NF-525** »* — règle **française**, **pas la loi à Djibouti** |

**Sans caisse** : la ligne dit **« sans objet »**, jamais « 0 événement » — **une
absence de preuve n'est pas une preuve**.

**Le vrai idéal est la généralisation** : quand `L23` (registre d'événements
unifié) arrivera, la chaîne d'empreintes devra couvrir **tous** les événements
(`domain_events`), pas seulement la caisse. C'est **une décision de conception à
écrire maintenant**, pas le jour de la livraison.

### Q5 — Combien de temps mesurer ? → **proposé : un trimestre, trois chiffres, un critère d'arrêt écrit d'avance**

**Pas un mois** : le cycle de valeur, c'est **une clôture + une déclaration + un
passage chez le comptable** — il faut **deux clôtures** pour distinguer « ça
marche » de « ça n'a pas encore servi ».

| # | Le chiffre | Ce qu'il dit |
|---|---|---|
| **1** | certificats **effectivement remis à un tiers par un client** (jamais par nous, en démo) | **le seul signal réel** |
| **2** | fois où il **change une décision** (prêt, dossier, remarque du comptable, litige évité) | sa valeur en argent |
| **3** | heures pour le produire, écarts soulevés | son coût |

**Critère d'arrêt, écrit avant de commencer** : si après un trimestre **aucun
client n'a remis un certificat à un tiers**, ce n'est **pas un produit** mais une
**fonction de démonstration** → la reclasser en `P2` (outil de vente), ou
l'arrêter. C'est la doctrine du dépôt (« un lot = un indicateur qui bouge »)
appliquée à une **idée**, pas à du code.

**Deux exceptions, plus rapides** : `P2`/`P3` se mesurent en **1 mois / 10-15
démos** — côté vente, le signal est immédiat. Et la production du certificat suit
l'**horloge du produit** : **à chaque clôture de période** et à la demande, la
forme de `get_nf525_attestation(p_period)`.

### Les trois pièges à éviter

1. **Laisser croire à une signature d'expert-comptable** → une mission réglementée qu'on ne peut pas rendre.
2. **Mettre les données d'un prospect dans la base de production** → sauvegardes, exports, RLS : un incident qui attend son heure.
3. **Promettre une conformité** (NF-525, « audit ») **au lieu d'un mécanisme vérifiable** → le premier professionnel qui lit la phrase disqualifie.

### Ce qu'il reste à décider (proprement)

| # | Question | Réponse proposée | État |
|---|---|---|---|
| **Q1** | Qui signe | le **système émet**, la **société endosse** — jamais un tiers | **proposé — à trancher** |
| **Q2** | À qui en premier | l'**expert-comptable** (deux lectures : dirigeant / comptable-banque) | **proposé — dépend de `👤-4`** |
| **Q3** | Où tournent les données | chez le prospect / **base jetable** 24-72 h — jamais la production | **proposé — à trancher** |
| **Q4** | Empreinte NF-525 | **oui, en annexe**, comme mécanisme vérifiable ; « sans objet » sans caisse | **proposé — à trancher** |
| **Q5** | Durée de mesure | **1 trimestre, 2 clôtures**, 3 chiffres, arrêt si non remis à un tiers | **proposé — à trancher** |

---

## 7. Comment re-mesurer ce que ce document affirme

```bash
# ce qui existe déjà et sur quoi ces propositions s'appuient
grep -rn 'document_links\|chain_traces' app/sql/252_chain_socle.sql | head
grep -n 'tour\|etat' app/sql/312_chain_lien_cycle.sql | head          # le cycle du lien
grep -rn 'document_effects' app/sql/313_chain_effects_contract.sql | head
ls app/sql/ci/check_effects_contract.sql app/sql/ci/check_bt_grid.sql # les portes G1/G2
# les 12 innovations déjà au plan (à ne pas confondre avec ce document)
grep -n 'I-0[1-9]\|I-1[0-2]' doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md | head -15
# l'import Sage (base de P2 et P3)
grep -n 'import_fec_entries' app/sql/308_sage_import.sql | head -3
```
