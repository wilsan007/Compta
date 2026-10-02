# Partie 2 / 4 — Finir les défauts métier de la recette

> **Plan en 4 parties du 02/10/2026** — charges équilibrées (≈ 9 j chacune, ≈ 36 j au total)
>
> | Partie | Objet | Charge | Document |
> |---|---|---:|---|
> | 1 | Stabiliser : une branche, une CI verte, des gardes honnêtes | ≈ 9,25 j | [PLAN-PARTIE-1](PLAN-PARTIE-1-STABILISER-2026-10-02.md) |
> | **2** | **Finir les défauts métier de la recette (paie, stock, compta, analytique)** | **≈ 9,5 j** | ce document |
> | 3 | Chaînages : finir L3 (maillons RPC, banc D1→D8) et L4 (indice de cohérence) | ≈ 9 j | [PLAN-PARTIE-3](PLAN-PARTIE-3-CHAINAGES-L3-L4-2026-10-02.md) |
> | 4 | Montrer, recetter, livrer (L5, e2e, recette écran, production) | ≈ 10 j | [PLAN-PARTIE-4](PLAN-PARTIE-4-RECETTE-LIVRAISON-2026-10-02.md) |

---

## 0. Point de départ

- **Entrée** : la partie 1 est close (une seule branche, CI GitHub verte).
- **Source des défauts** : `PLAN-QA-CORRECTIF-2026-09-29.md` (fusionné en partie 1). Les
  identifiants (`rh-008`, `stk-010`…) renvoient à ses fiches.
- **Déjà fait et vérifié le 02/10** (ne pas rouvrir) : lots QA **A** (A1→A6) et **B**
  (B1→B12), C1, C2, C2 bis, D1, D2, D4, E1.
- **Déjà en vol au 02/10** (voir le § 1 bis de la partie 1) : **D3** (diagnostic établi et
  test d'écran écrit sur `qa/lot-d-stock`) ; **voie C** des types de la paie (`c51d468`).
  Ces travaux se reprennent ici, sur la branche unique, sans être refaits.
- **Branche** : `partie-2-metier`. **Numéros** : `340` → `369`.
- **Règle** : un défaut = test rouge avant → migration → câblage CI → `db:types` → preuve,
  **dans le même commit** ; « fait » = passage GitHub vert.

## 1. Les tâches

### Bloc C — Paie (≈ 3 j)

| # | Défaut | Ce qu'il faut obtenir | Charge | État |
|---|---|---|---:|---|
| 2.1 | **C2 ter** — titres-restaurant et indemnité de transport hors du bulletin (suite `321`, 3 rouges inscrits au registre) | les deux postes entrent dans le brut, les cotisations et le net selon la grille 2026 **sourcée** ; `321 T02/T03/T05` sortent du registre | 1 j | ⬜ |
| 2.2 | **C3 — rh-008** — heures sup jamais détectées depuis la feuille de temps | une feuille de temps au-delà de l'horaire prévu crée l'élément de paie (chemin unique de la W5) | 0,5 j | ⬜ |
| 2.3 | **Tranches d'heures sup (reste de W5)** — seule la première tranche est appliquée ; `calculate_overtime_pay` (tranches + exonération 7 500 €) n'a plus d'appelant | 25 % / 50 % selon le seuil hebdomadaire, exonération plafonnée ; **un seul** moteur | 1 j | ⬜ |
| 2.4 | **C4 — rh-009** — pointage d'absence impossible ; **C5, C6** — constats hors fiche et défauts bas de paie (à instruire puis corriger) | l'absence pointée entre au registre W9 ; chaque constat C5/C6 a un verdict | 0,5 j | ⬜ |

⚠️ Toute modification de la grille de paie reste soumise à la **signature de
l'expert-comptable (D-G)** avant déploiement — elle est préparée ici, livrée en partie 4.

### Bloc D — Stock, production, caisse (≈ 2,5 j)

| # | Défaut | Ce qu'il faut obtenir | Charge | État |
|---|---|---|---:|---|
| 2.5 | **D3 — stk-010** — OF terminé à 0,00 € et « aucune consommation » (*en vol : l'écran doit lire les colonnes de coût posées par la `302` et les sorties `stock_movements` de référence `production`, pas `of_consumptions`*) ; **D10** — nomenclature sans article, coût 0 ; **D11** — OF refusé qui consomme son numéro | l'OF affiche coût et consommations réels ; numéro attribué à la validation | 1 j | ⬜ |
| 2.6 | **D5 — stk-014** — caisse : pas d'annulation de ticket à l'écran, statut en anglais, « Virement » non paramétré | l'écran appelle `void_pos_ticket` ; statuts traduits ; moyen de paiement paramétrable | 0,5 j | ⬜ |
| 2.7 | **D6, D7, D8** — prix négatif accepté, fiche article non modifiable ; sortie affichée à 0,00 € au lieu du CUMP ; stock initial avec dépôt imposé, date du jour, sans écriture | contraintes en base ; valeur de sortie lue au CUMP ; stock initial daté, au dépôt choisi, avec écriture | 0,75 j | ⬜ |
| 2.8 | **D9, D12, D13** — inventaire (ajustement absent, libellés, écarts en JSON brut) ; alerte « stock bas » à seuil 0 ; points non testés à couvrir | inventaire lisible ; pas d'alerte à seuil 0 ; D13 inscrit à la recette (partie 4) | 0,25 j | ⬜ |

### Bloc F — Comptabilité générale (≈ 1,5 j)

*E2 (immobilisations non testées) passe en partie 4 (4.11) : c'est un parcours de recette avant d'être un défaut.*

| # | Défaut | Ce qu'il faut obtenir | Charge | État |
|---|---|---|---:|---|
| 2.10 | **F1 — cpt-001** — plan comptable à solde 0 alors que 512000 porte 10 000 ; **F3** — plan ouvert vide | soldes lus au grand livre ; liste chargée à l'ouverture | 0,5 j | ⬜ |
| 2.11 | **F2** — tout compte sans type → « Actifs courants » ; **F6** — modèle : le pourcentage 100 recopié comme montant ; **F7** — date proposée hors période | type déduit de la classe ; pourcentage appliqué ; date dans la période | 0,5 j | ⬜ |
| 2.12 | **F4 (= AUD-I04)** — messages SQL bruts à l'écran ; **F5** — libellés sans accents | traduction des erreurs métier (fr/en/ar) ; libellés corrigés | 0,5 j | ⬜ |

### Bloc G — Analytique, projets, et la dette de types (≈ 2,5 j)

*H1 (« Encaissements » = total facturé, deux soldes bancaires) passe en partie 4 (4.12), avec H2 et les tableaux de bord de la recette.*

| # | Défaut | Ce qu'il faut obtenir | Charge | État |
|---|---|---|---:|---|
| 2.13 | **G1 — pil-008** — impossible d'imputer une section analytique sur une facture ; **G2** — grille de ventilation en texte libre | sélecteur de section sur la ligne (le porteur existe depuis la `304`) ; ventilation structurée, 100 % contrôlé | 1 j | ⬜ |
| 2.14 | **G3** — tâche sans parent ni avancement ; **G4** — clé i18n brute, Gantt et calendrier en anglais ; **G5** — constats projets/budgets | formulaire complet (règle d'avancement de la `303`) ; i18n ; verdict sur G5 | 0,5 j | ⬜ |
| 2.16 | **Voie C, suite : les types des écrans touchés par cette partie** (paie, stock, caisse, compta, analytique). Continuer `c51d468` : chaque fonction de requête déclare son type de retour, chaque `useState<any[]>` de l'écran corrigé est nommé. L'état des lieux du 01/10 laissait **85 états sur 128** non typés, avec leurs défauts **encore cachés** | `tsc` 0 ; plafond des `any` en baisse à chaque commit ; chaque défaut révélé par un type passe au registre ou se corrige ici | 1 j | ⬜ |

| | **Total** | | **≈ 9,5 j** | |

## 2. Ordre

Bloc C (le plus grave : paie) → bloc D → bloc F → bloc G. La tâche 2.16 se fait **au fil
des blocs** : le type d'un écran se pose dans le commit qui corrige cet écran. À l'intérieur d'un bloc,
l'ordre du tableau.

## 3. Critères de sortie (tous requis)

- [ ] chaque ligne 2.1 → 2.15 porte : migration (s'il y en a), suite, **lien du passage
      GitHub vert** ;
- [ ] registre `ci/expected_failures.sql` **vide** ;
- [ ] `PLAN-QA-CORRECTIF-2026-09-29.md` : les lots C, D, F, G marqués ✅ avec la même
      preuve (E2, H1 et H2 se ferment en partie 4) ;
- [ ] le chemin de l'écran (`src/__screen__`) porte un scénario pour chaque défaut corrigé
      par l'écran (C3, D3, D5, F1, G1 au minimum) ;
- [ ] plafond des `any` plus bas qu'à l'entrée de la partie, `tsc` 0 ;
- [ ] rejeu base neuve complet : 0 erreur, chiffres ≥ ceux de la sortie de partie 1.

## 4. Ce qui n'est PAS dans cette partie

Les chaînages (→ partie 3), la recette à l'écran par une personne et le déploiement
(→ partie 4), la localisation Djibouti (horizon suivant).
