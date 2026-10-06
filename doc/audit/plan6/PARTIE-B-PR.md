# PR — partie B : les 62 règles d'état (`500` → `519`)

> Branche `plan6/b-regles-etat` → `main`. **La fusion déploie.**
> Plan : [PLAN-6-PARTIES-PARALLELES-2026-10-05.md](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)
> (règle R1 : un worktree, une branche ; R8 : l'intégration fusionne seule).
> Suivi : [PARTIE-B.md](PARTIE-B.md). Inventaire : [B1-INVENTAIRE-62-REGLES-2026-10-05.md](B1-INVENTAIRE-62-REGLES-2026-10-05.md).

## Ce que la branche livre

**20 migrations (`500`→`519`) + 20 suites, 77 scénarios verts.** Base neuve rejouée :
**353 migrations, 0 erreur**. Les **62 règles d'état** du référentiel sont **touchées** ;
l'inventaire B.1 mesurait **13 ✅ / 13 🟨 / 36 ⬜** avant, **0 vierge** après.

| Migration | Règle(s) | Module |
|---|---|---|
| `500` | R-001 devis accepté → commande | Ventes |
| `501` | R-004 commande facturée → rapprochement | Ventes |
| `502` | R-005 commande validée → n° définitif + gel | Ventes |
| `503` | R-003 devis validé → n° définitif + verrou | Ventes |
| `504` | R-002 devis expiré | Ventes |
| `505` | R-017/R-018 facture fournisseur échue / rejetée | Achats |
| `506` | R-059→R-061 relances (horodatage EF-02) | Relances |
| `507` | R-058 engagement libéré | Budgets |
| `508` | R-054→R-056 rejets déclaratifs | Conformité |
| `509` | R-046 OF d'origine MRP | Production |
| `510` | R-011 commande reçue → rapprochement + écart | Achats |
| `511` | R-013/R-015/R-016 réceptions + facture annulée | Achats |
| `512` | R-007 retour client → réintégration stock | Ventes |
| `513` | R-009 BL transformé → lien facture | Ventes |
| `514` | R-048/R-049 SEPA | Trésorerie |
| `515` | R-050/R-051 virement | Trésorerie |
| `516` | R-052/R-053 TVA soumise / payée | Conformité |
| `517` | R-040→R-042 projet | Projets |
| `518` | R-031/R-037→R-039 note de frais, contrats | Paie/RH |
| `519` | R-019/R-044/R-045/R-047 (dernières vierges) | Ventes/Prod/Stock |

## Garde-fous (R7, R5, R3)

- **Aucune fonction existante réécrite** : uniquement des maillons neufs `regle_*` et des
  déclencheurs `zz_b2*` **additifs**. Les `chain_deja_fait` / `chain_avant` du socle sont
  **réutilisés**.
- `ci.yml` modifié **uniquement sous le marqueur `# --- plan6:b ---`** (20 étapes).
- Aucune écriture dans `main`, `SUIVI-CHANTIERS.md` ni `AGENTS.md`.
- Numéros pris par `migration-numero.mjs` ; 0 collision (crochet pré-commit).

## Partielles assumées — l'effet métier est COORDONNÉ, pas écrit

Chaque en-tête le dit ; la liste est dans PARTIE-B.md § « l'état réel ».

- **Stock (parties E/D)** : R-006 (rapprochement facture/POD), R-009 (garde BL brouillon),
  R-013 (entrée stock partielle), R-015 (contrôle qualité), R-043 (contre-passation OF),
  R-044/R-045/R-047 (consommation/réservation/transfert à deux mouvements).
- **Comptabilité (intégration + expert-comptable)** : R-016, R-019 (contre-passations),
  R-020 (immuabilité), R-048→R-051 (écritures de trésorerie), R-052/R-053 (gel de période,
  paiement TVA), R-023/R-024 (dél-letrage), R-025/R-026/R-028/R-029/R-032/R-036 (paie FR,
  **B.3/B.4**).

## Découvertes à porter au référentiel (hors territoire B)

- **R-006 vise `deliveries`, table inexistante** → c'est `delivery_notes`.
- **`quotes` et `purchase_orders` manquaient** au registre `chain_document_types` (450) —
  inscrits par `500`/`510`.
- **`chain_deja_fait` protège par le LIEN** : les maillons « événement » portent une garde
  d'idempotence propre.
- **R-062 est déjà faite** (`pos_tickets_status_check`) ; **R-046 partielle** (le schéma ne
  stocke pas la proposition MRP).

## À faire par l'intégration (R6/R8)

1. Rejouer la batterie sur base neuve ; **régénérer types et plafonds**.
2. Fusionner en `main` (déploie) ; mettre à jour `SUIVI-CHANTIERS.md` depuis `PARTIE-B.md`.
3. Transmettre les demandes hors territoire (référentiel, E/D pour le stock, comptabilité).
