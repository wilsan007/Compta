# Partie 4 / 4 — Montrer, recetter, livrer

> **Plan en 5 parties du 02/10/2026** — la 5e ajoutée après coup — charges équilibrées (≈ 6 j la 5e, ≈ 42 j au total)
>
> | Partie | Objet | Charge | Document |
> |---|---|---:|---|
> | 1 | Stabiliser : une branche, une CI verte, des gardes honnêtes | ≈ 9,25 j | [PLAN-PARTIE-1](PLAN-PARTIE-1-STABILISER-2026-10-02.md) |
> | 2 | Finir les défauts métier de la recette (paie, stock, compta, analytique) | ≈ 9,5 j | [PLAN-PARTIE-2](PLAN-PARTIE-2-DEFAUTS-METIER-2026-10-02.md) |
> | 3 | Chaînages : finir L3 (maillons RPC, banc D1→D8) et L4 (indice de cohérence) | ≈ 9 j | [PLAN-PARTIE-3](PLAN-PARTIE-3-CHAINAGES-L3-L4-2026-10-02.md) |
> | **4** | **Montrer, recetter, livrer** | **≈ 10 j** | ce document |
> | **5** | **L'intégrité référentielle des chaînages** | **≈ 6 j** | [PLAN-PARTIE-5](PLAN-PARTIE-5-INTEGRITE-CHAINAGES-2026-10-02.md) |

---

## 0. Point de départ

- **Entrée** : parties 2 **et** 3 closes (passages GitHub verts).
- **Constats du 02/10** que cette partie ferme :
  - les tests **Playwright ne tournent pas** en CI (« skipped ») — AUD-J01 / J02 ;
  - le chemin de l'écran est vert (**125 / 125** verdicts) mais son balayage des lectures
    n'exerce que **82 fonctions sur 241** (159 sautées faute d'arguments) ;
  - la **recette à l'écran P0-08** (14 parcours) n'a jamais été passée ;
  - rien de ce qui a été livré depuis la `188` n'a été **rejoué sur une copie de
    production** ;
  - la grille de paie `276` attend la **signature de l'expert (D-G)** ;
  - la porte **G7** (le socle écrit-il sous `FORCE ROW LEVEL SECURITY` ?) n'a jamais été
    jouée sur la production, alors qu'elle a été écrite pour ça. (D-4 est passé en partie 1, tâche 1.13.)
- **Branche** : `partie-4-livraison`. **Numéros** : `370` → `399`.

## 1. Les tâches

### Bloc A — Montrer la preuve : L5 (≈ 3 j, charge du plan des chaînages)

| # | Tâche | Preuve attendue | Charge | État |
|---|---|---|---:|---|
| 4.1 | Page **« Robustesse »** : résultat des 8 épreuves par chaînage (rapport du banc de la partie 3) | capture + scénario e2e | 1,5 j | ⬜ |
| 4.2 | Page **« Cohérence »** : indice, écarts, historique du relevé nocturne | capture + scénario e2e | 1,5 j | ⬜ |

### Bloc B — Les tests de bout en bout réellement joués (≈ 2,5 j)

| # | Tâche | Preuve attendue | Charge | État |
|---|---|---|---:|---|
| 4.3 | **Playwright en CI** sur chaque push de la branche principale et chaque PR vers `main` (AUD-J01) | job e2e « success », plus jamais « skipped » | 0,5 j | ⬜ |
| 4.4 | **Quatre parcours qui lisent des chiffres** (AUD-J02) : inscription → plan semé ; vente complète → écriture et TVA ; paie → bulletin et écriture ; caisse → clôture et stock | montants vérifiés à l'écran, au centime | 1,5 j | ⬜ |
| 4.5 | **Balayage des lectures du chemin de l'écran** : fournir des arguments réels aux 159 fonctions sautées | `SKIP_ARGS` ≤ 10, toutes justifiées | 0,5 j | ⬜ |

### Bloc C — La recette à l'écran P0-08 (≈ 3 j)

| # | Tâche | Preuve attendue | Charge | État |
|---|---|---|---:|---|
| 4.6 | Passer les **14 parcours** sur l'application locale (jamais une URL distante), avec la société remplie et la société vide, sur les 4 gabarits ; y inclure **D13** et **H2** de la recette QA | procès-verbal daté : un verdict par parcours, captures | 1,5 j | ⬜ |
| 4.11 | **E2 — immobilisations** (déplacée de la partie 2) : dérouler la fiche E2 à l'écran (acquisition, dotation, cession), corriger ce qu'elle trouve | fiche E2 close, scénario d'écran | 0,5 j | ⬜ |
| 4.12 | **H1 — tableaux de bord** (déplacée de la partie 2) : « Encaissements » lus sur les règlements, **un seul** solde bancaire (le comptable, cf. `277`) ; dérouler H2 | scénario d'écran chiffré | 0,5 j | ⬜ |
| 4.7 | Corriger les écarts **bloquants** trouvés en 4.6 (les autres sont inscrits pour l'horizon suivant) | chaque correctif avec test et passage GitHub vert | 0,5 j | ⬜ |

### Bloc D — Livrer (≈ 1,5 j, plus ce qui dépend de vous)

| # | Tâche | Preuve attendue | Charge | État |
|---|---|---|---:|---|
| 4.8 | **Rejeu sur une copie de production** : sauvegarde, restauration locale, application de toutes les migrations depuis l'état réel de la production, suites et sondes ; jouer la porte **G7** sous le vrai rôle propriétaire et **prendre la décision** (les trois issues sont dans son message) ; **exécuter `select chain_fermer_orphelins(NULL)` et noter le nombre** dans le journal de rejeu (partie 5, migration 452 : elle ferme — et n'efface jamais — les liens dont l'amont ou l'aval a disparu avant la garde de suppression ; sur une base neuve elle rend 0) | 0 erreur ; journal de rejeu archivé ; décision G7 écrite | 1 j | ⬜ |
| 4.9 | **Déploiement** des migrations et des fonctions Edge (après 4.8 et vos validations ci-dessous) ; relecture des paramètres globaux et de `banks` après déploiement | journal de déploiement ; requêtes de contrôle | 0,5 j | ⬜ |

| | **Total (développement)** | | **≈ 10 j** | |

### Ce qui ne dépend que de vous (hors charge, mais bloquant pour 4.9)

| Action | Pourquoi |
|---|---|
| Faire tourner la clé `sb_secret_…` (AUD-H05) | elle est restée en clair dans l'historique git |
| Faire signer les **bulletins d'or** de la `276` par l'expert-comptable (D-G) | la grille de paie ne se déploie pas sans |
| Renseigner les secrets : `RESEND_API_KEY`, `STRIPE_WEBHOOK_SECRET`, `VITE_SENTRY_DSN`, Chorus Pro, Yousign, GoCardless, EFI, SIRENE | les intégrations répondent « non configuré » tant qu'ils manquent |
| Signer le **DPA** du prestataire OCR (D-5) | condition légale de l'envoi de documents |
| Trancher **D-7, D-10, D-11, D-13** | décisions ouvertes au 02/10 |

## 2. Ordre

Bloc A et bloc B en parallèle **dans la même session** → bloc C → bloc D.

## 3. Critères de sortie (tous requis) — fin du plan en 4 parties

- [ ] pages « Robustesse » et « Cohérence » en service (L5 ✅) ;
- [ ] job e2e vert sur la branche principale, avec les 4 parcours chiffrés ;
- [ ] procès-verbal de recette P0-08 signé, 0 écart bloquant ouvert ;
- [ ] rejeu sur copie de production à 0 erreur ; déploiement fait et contrôlé ;
- [ ] `RESTE-OUVERT` réécrit : il ne contient plus que l'**horizon suivant**.

## 4. L'horizon suivant (à replanifier en 4 parties équilibrées le jour où celle-ci est close)

- chaînages **L6 → L24** (vue Chaîne, moteur de règles, explicabilité… ≈ 100 j) ;
- **couverture d'audit phase 10** : 16 modules sur 20 jamais audités par exécution (≈ 15 j,
  `RESTE-OUVERT` § E). Elle trouvera des défauts que ce plan ne compte pas ;
- **la fin de la dette de types** : les états hors des écrans de la partie 2, jusqu'à
  `useState<any[]>` = 0 ;
- **localisation Djibouti** (lot K, cahier `doc/localisation`, ≈ 74 j + textes + pilote) ;
- propositions **P1 → P8** (P1 certificat d'intégrité en premier, dès L5).
