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
- **Pas commencé** : le **banc d'épreuves D1 → D8** (`0 / 62` chaînages éprouvés),
  l'indice de cohérence **publié et relevé chaque nuit**.
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
| 3.4 | Le **moteur** paramétré par chaînage (une description du maillon → les 8 épreuves) et le **rapport par maillon** (table + vue) | un chaînage déclaré = 8 verdicts datés | 1,5 j | ⬜ |
| 3.5 | **D1 rejeu** (aucun doublement) · **D2 concurrence** (deux appels simultanés) | 0 effet doublé, verrous tenus | 1 j | ⬜ |
| 3.6 | **D3 panne partielle** (tout ou rien) · **D4 annulation** (lien fermé, effet retiré) | 0 effet orphelin | 1 j | ⬜ |
| 3.7 | **D5 réouverture / reconfirmation** (nouveau tour) · **D6 retour arrière** · **D7 volume** (budget G6) · **D8 isolation** (deux sociétés) | rapport complet ; p95 dans le budget | 1,5 j | ⬜ |

### Bloc L4 — L'indice de cohérence publié (≈ 2 j)

| # | Tâche | Preuve attendue | Charge | État |
|---|---|---|---:|---|
| 3.8 | Rendre **mesurables** les 7 invariants « non mesurables » (ou en retirer avec raison écrite) | `13 / 20` → `20 / 20` mesurés, ou la raison de chaque exclusion | 1 j | ⬜ |
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

## 4. Ce qui n'est PAS dans cette partie

Les pages « Robustesse » et « Cohérence » (L5 → partie 4) ; la vue Chaîne et les lots
L6 → L24 (horizon suivant) ; les propositions P1 → P8 (après L5).
