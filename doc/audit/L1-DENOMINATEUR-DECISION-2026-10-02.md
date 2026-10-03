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
Le détail des 99 noms, et le tri par nature, sont dans le §2 de la tranche 4, à
rejouer après chaque tranche.