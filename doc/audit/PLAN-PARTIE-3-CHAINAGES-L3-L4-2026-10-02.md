# Partie 3 / 4 — Chaînages : finir L3 (maillons RPC, banc D1→D8) et L4 (indice de cohérence)

> **Plan en 4 parties du 02/10/2026** — charges équilibrées (≈ 9 j chacune, ≈ 36 j au total)
>
> | Partie | Objet | Charge | Document |
> |---|---|---:|---|
> | 1 | Stabiliser : une branche, une CI verte, des gardes honnêtes | ≈ 9,25 j | [PLAN-PARTIE-1](PLAN-PARTIE-1-STABILISER-2026-10-02.md) |
> | 2 | Finir les défauts métier de la recette (paie, stock, compta, analytique) | ≈ 9,5 j | [PLAN-PARTIE-2](PLAN-PARTIE-2-DEFAUTS-METIER-2026-10-02.md) |
> | **3** | **Chaînages : finir L3 et L4** | **≈ 9 j** | ce document |
> | 4 | Montrer, recetter, livrer (L5, e2e, recette écran, production) | ≈ 10 j | [PLAN-PARTIE-4](PLAN-PARTIE-4-RECETTE-LIVRAISON-2026-10-02.md) |

---

## 0. Point de départ (mesuré le 02/10 sur `9ea2eae`)

- **Livré et vert** : L0 (socle), L1 tranches 1 → 7 (23 effets tracés et 23 contrats, plus
  la caisse par son chemin d'appel en `412`), L2 (portes G1 → G7), L7 (contrats d'effet),
  L3 tranche 1 (fermeture des liens à l'annulation, `410`), L4 inscrit (`413` : 20
  invariants, **13 mesurables, 7 non mesurables**, suite 8/8 après correction de l'index).
  Suites `400` → `413` toutes vertes, y compris sur une base mise à niveau depuis les
  anciens noms `310` → `322`.
- **En cours** : le **banc d'épreuves D1 → D8** existe et JOUE (`434`) ; il est
  éprouvé sur **1 maillon sur 7** (`releve.comptabilise`) — **5 verdicts `tenu`
  sur 8**, 3 `non_joue` avec leur raison. L'indice de cohérence est passé de
  **13/20 à 17/20** (`435`) ; 3 invariants restent non mesurables, pour des
  raisons **vérifiées** et non supposées. Reste **3.10** (lecture du registre
  par un écran).
- **Entrée** : partie 1 close. La partie 3 **peut** tourner en même temps que la partie 2
  **seulement si** les deux sessions respectent leurs plages et ne modifient jamais le même
  fichier ; sinon, elle vient après.
- **Déjà en vol au 02/10** : `414_chain_l4_alerte_degradation.sql` et sa suite (tâche 3.9),
  **non suivis** dans le dossier principal. Le numéro est conforme à la plage. Ils se
  commitent sur `partie-3-chainages` avec les types, G1, G7 et le plafond des tables non
  lues **dans le même commit**. La branche principale est rouge sur exactement ces deux
  portes depuis le commit L4 du 02/10.
- **Branche** : `partie-3-chainages`. **Numéros** : `414` → `449`.
- **Règle** : chaque migration qui pose un maillon déclare son **contrat d'effet** dans le
  même fichier (porte G2) ; chaque table nouvelle met à jour **G1, G7, les types et le
  plafond des tables non lues dans le même commit** — c'est précisément ce qui a manqué au
  commit L4 du 02/10.

## 1. Les tâches

### Bloc L3-a — Les maillons RPC restants (≈ 2 j)

| # | Tâche | Preuve attendue | Charge | État |
|---|---|---|---:|---|
| 3.1 | **Recompter** les maillons RPC de l'inventaire tranche 4 (« Maillon / RPC, à tracer — lot L3 ») ; rayer la caisse (faite en `412`) ; publier la liste restante avec verdict | tableau daté dans l'inventaire | 0,25 j | ⬜ |
| 3.2 | **Paie versée** : tracer par son chemin d'appel (même doctrine que `412` : corps `_inner` non exposé, enveloppe `SECURITY DEFINER`, `chain_avant` / `link_documents` / `chain_apres`) | suite dédiée : liens, traces `applique`, refus en mode `refuse`, cloisonnement | 0,75 j | ⬜ |
| 3.3 | **Relevé bancaire manuel / rapprochement** et maillons RPC restants du recomptage | une suite par maillon, même structure | 1 j | ⬜ |

### Bloc L3-b — Le banc d'épreuves D1 → D8 (≈ 5 j, charge du plan des chaînages)

| # | Épreuve | Ce que le banc prouve, par chaînage | Charge | État |
|---|---|---|---:|---|
| 3.4 | Le **moteur** paramétré par chaînage (une description du maillon → les 8 épreuves) et le **rapport par maillon** (table + vue) | un chaînage déclaré = 8 verdicts datés | 1,5 j | ✅ |
| 3.5 | **D1 rejeu** (aucun doublement) · **D2 concurrence** (deux appels simultanés) | 0 effet doublé, verrous tenus | 1 j | D1 ✅ / D2 `non_joue` |
| 3.6 | **D3 panne partielle** (tout ou rien) · **D4 annulation** (lien fermé, effet retiré) | 0 effet orphelin | 1 j | D4 ✅ / D3 `non_joue` |
| 3.7 | **D5 réouverture / reconfirmation** (nouveau tour) · **D6 retour arrière** · **D7 volume** (budget G6) · **D8 isolation** (deux sociétés) | rapport complet ; p95 dans le budget | 1,5 j | D6 D7 D8 ✅ / D5 `non_joue` |

### Bloc L4 — L'indice de cohérence publié (≈ 2 j)

| # | Tâche | Preuve attendue | Charge | État |
|---|---|---|---:|---|
| 3.8 | Rendre **mesurables** les 7 invariants « non mesurables » (ou en retirer avec raison écrite) | `13 / 20` → `20 / 20` mesurés, ou la raison de chaque exclusion | 1 j | 17/20 — 3 restent nommés |
| 3.9 | *(en vol : `414`)* **Relevé nocturne** par `pg_cron` (`audit_chains` par société), historique daté, **alerte** quand l'indice baisse | job inscrit ; une baisse provoquée lève l'alerte | 0,5 j | ⬜ |
| 3.10 | `chain_invariants` et `chain_invariant_results` **lus par l'écran** (lecture minimale, sans les pages de la partie 4) — ferme durablement l'écart du plafond des tables non lues | `check-unused-tables` revient au plafond sans le relever | 0,5 j | ⬜ |

| | **Total** | | **≈ 9 j** | |

## 2. Ordre

3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6 → 3.7 → 3.8 → 3.9 → 3.10.
Le banc (3.4 → 3.7) s'applique **aussi** aux maillons posés en 3.2 et 3.3.

## 3. Critères de sortie (tous requis)

- [ ] tous les maillons RPC recomptés en 3.1 sont tracés, avec suite et contrat ;
- [ ] le banc D1 → D8 tourne en CI ; rapport par maillon : **62 / 62** éprouvés, ou la liste
      des exclus avec leur raison ;
- [ ] indice de cohérence **20 / 20** mesurés, relevé chaque nuit, alerte vérifiée ;
- [ ] portes G1 → G7, types et plafonds à jour **dans les mêmes commits** ; passage GitHub
      vert ;
- [ ] tableau de suivi du plan des chaînages (§6) mis à jour : L3 ✅, L4 ✅.

## 3 bis. Ce qui a été fait, et ce qui reste — état au 02/10/2026

**Livré et vérifié sur base neuve (PostgreSQL 16, 273 migrations + 414, 430,
432, 433 ; portes G1, G2, G5, G7 et la porte 3.1 vertes) :**

- [x] **3.1** — les maillons RPC recomptés, et **tenus par une porte CI**
      (`ci/check_chain_rpc_inventory.sql`, auto-testée). Mesuré : **14 maillons
      RPC transverses — 7 tracés, 7 écartés avec leur raison, aucun en attente.**
- [x] **3.2** — **paie versée et comptabilisation du bulletin** (`430`),
      tracées au POINT DE CONVERGENCE `payroll_post_run` (trois chemins d'appel
      couverts, suite 430 : **11 scénarios, 11 verts**).
- [x] **3.3** — **relevé bancaire manuel** (`432`), trois maillons ; suite 432 :
      **8 scénarios, 8 verts**. Le dé-lettrage **ferme** ses liens (doctrine
      320) au lieu d'ouvrir une trace `applique`.
- [x] **3.4** — le **moteur du banc** (`433`) : une description par maillon,
      les huit épreuves en dérivées, le rapport **dans la base**. Mesuré :
      7 maillons × 8 épreuves = **56 verdicts datés et motivés**.
- [x] **3.9** — **alerte de dégradation** (`414`) câblée en CI et vérifiée.
- [x] le **déblocage de la branche** : G1, G2, G5, G7, types et plafonds remis
      dans le même commit que leur table — la 414 avait été commitée seule, ce
      qui rendait la branche rouge exactement là où le plan l'annonçait.

**Reste — et c'est dit sans arrondir :**

- [x] **3.5, 3.6, 3.7** — les épreuves **D1 → D8 sont écrites ET jouées** (`434`) ;
      suite 434 : **8 scénarios, 8 verts**. Le verdict écrit est celui qui a été
      **mesuré**, jamais un `tenu` par défaut :
      - **D1 rejeu** — `tenu` : +0 lien, +0 trace. Le 2ᵉ appel est **refusé**
        (SQLSTATE `23505`), pas silencieux : le refus métier est un mode de
        tenue aussi valide que le silence, et c'est le SQLSTATE qui distingue
        un refus d'une panne — sans quoi un maillon cassé qui plante avant
        d'écrire passerait pour un rejeu correct.
      - **D4 annulation** — `tenu`, via un geste **dédié**
        (`appat_annul` → `unreconcile_bank_statement_line`). Rejouer le
        producteur pour « annuler » demandait un **second effet, pas sa
        suppression**.
      - **D6 retour arrière**, **D7 volume** — `tenu` : p95 sur **19 stimuli
        distincts**, pas 19 rejeux de la même ligne (on aurait mesuré le coût
        d'un refus en l'appelant une performance), et `percentile_cont(0.95)`
        réel.
      - **D8 isolation** — `tenu`, mesuré depuis une **session réelle** en
        `authenticated`. En `SECURITY DEFINER` la RLS est contournée : compter
        avec `tenant_id <> v_tid` donnait un vert **par construction**.
      - **D2, D3 et D5 restent `non_joue`**, chacune avec sa raison : D2 exige
        une **seconde connexion** (PostgreSQL interdit `SET ROLE` dans une
        fonction `SECURITY DEFINER`), D3 un **point d'échec instrumenté**, et
        D5 bute sur `uniq_journal_entry_number_tenant` — le numéro d'écriture
        étant dérivé de la ligne, **la réouverture est impossible**. T07
        vérifie qu'aucune ne devient verte par défaut.
      - **Ce qui reste acquis et non arrondi :** le banc n'est éprouvé que sur
        **un maillon** (`releve.comptabilise`). Les 6 autres portent leurs
        gabarits et leurs gestes au catalogue, mais **62 / 62 éprouvés n'est
        toujours pas atteint** : la preuve attendue est à **1 / 7**.
- [x] **3.8** — l'indice de cohérence passe de **13 / 20 à 17 / 20** (`435`).
      Quatre des sept invariants non mesurables le deviennent **par
      agrégation, sans aucune nouvelle colonne** : le reproche « la donnée
      n'est pas stockée » est sans objet quand les deux côtés de l'égalité se
      répondent. Le côté manquant se **calcule** — reste à facturer (INV-05),
      réalisé budgétaire (INV-06), solde de relevé (INV-08), amont existant
      (INV-19).
      **INV-07, INV-10 et INV-12 restent non mesurables**, et c'est dit :
      - INV-07 (lien groupe de lettrage ↔ ligne de TVA) et INV-10 (montant
        absent de `dsn_declarations`) exigent une colonne ou une clé sur des
        tables métier **partagées avec d'autres chantiers** — hors périmètre,
        pour ne pas créer une seconde vérité à désynchroniser ;
      - INV-12 aurait pu « passer » en comparant « facturé − temps » au coût
        publié, mais `v_project_profitability` n'agrège que des **heures** :
        cela aurait mesuré un invariant **plus faible sous le même nom**. Un
        test (T07) verrouille ce refus.
- [ ] **3.10** — `chain_invariants` et `chain_invariant_results` ne sont pas
      lus par l'écran. Le plafond des tables non lues reste donc au-dessus de
      sa valeur : mesuré à **79 pour 75**, dont 3 tables L4 et **76 de dette
      antérieure à L4**.

> **Rouge connu, préexistant, hors périmètre de la 434 :** `414` /
> `T07 isolation` est rouge — la propriétaire `AL6` voit **0** de ses **1**
> alerte. Les contrôles `check_chain_rpc_inventory`, `check_forced_rls_writers`
> et `check_bt_grid` restent verts, et aucun fichier de la 414 n'a été touché
> par la 434.

## 4. Ce qui n'est PAS dans cette partie

Les pages « Robustesse » et « Cohérence » (L5 → partie 4) ; la vue Chaîne et les lots
L6 → L24 (horizon suivant) ; les propositions P1 → P8 (après L5).
