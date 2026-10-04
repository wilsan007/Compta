# PLAN PRICING ONUSUITE — Stratégie de monétisation

## 1. ESSAI GRATUIT

### Modèle : Reverse Trial 45 jours

- **45 jours** avec tous les modules débloqués, sans carte bancaire
- **60 jours** pour RH/Paie et Production (cycle mensuel obligatoire)
- **Extension +30 jours** automatique sur jalon d'activation :
  - Import réalisé (balance, plan comptable, clients)
  - 100 écritures ou 20 factures saisies
  - 2ᵉ utilisateur invité
  - Session d'onboarding réalisée (30 min visio)
- **Durée max possible : 75–90 jours**

### Bascule après essai (pas de blocage)

Au lieu de bloquer le compte, **bascule automatique sur Onusuite Solo** (gratuit à vie, limité). Le compte n'est jamais perdu, le canal de réactivation reste ouvert.

### Plafonds pendant l'essai

| Élément | Limite |
|---|---|
| Utilisateurs | 10 |
| Sociétés | 3 |
| Écritures comptables | Illimitées |
| Bulletins de paie | 30 |
| Modules | Les 17 débloqués |
| Exports PDF | Filigrane « Émis avec Onusuite — version d'essai » |
| Télédéclarations réelles (EDI-TVA, DGI, CNSS) | Bloquées (simulation OK) |
| Support | Chat + email, pas de SLA |
| Carte bancaire | Non requise |

### Anti-abus

- 1 essai par entité légale (NIF / ICE / RCCM / IFU)
- Email professionnel obligatoire, blocage des domaines jetables
- Détection soft (IP + fingerprint) → revue manuelle
- 2ᵉ essai possible uniquement validé par un commercial

---

## 2. RÉVOCATION PROGRESSIVE

| Phase | Jour | `tenants.status` | Accès |
|---|---|---|---|
| Alertes | J-10, J-5, J-1 | `trial` | Tout — bannière in-app + email + WhatsApp |
| Lecture seule | J0 → J+21 | `read_only` | Consultation + exports illimités + paiement |
| Gel | J+22 → J+90 | `suspended` | Facturation + 1 export complet des données |
| Archivage | J+91 → J+120 | `archived` | Données chiffrées, réactivables à l'identique sur paiement |
| Purge | J+120 | supprimé | Après 2 notifications + 1 export proposé |

**Délai de grâce sur facture échue (payant)** : 15 jours avant `read_only`

**Règle technique** : appliqué en RLS PostgreSQL — `SELECT` toujours permis, `INSERT/UPDATE/DELETE` conditionnés à `status IN ('trial','active')`

---

## 3. GRILLE TARIFAIRE (FCFA HT)

### Tranches d'utilisateurs

| Palier | Utilisateurs | Profil type |
|---|---|---|
| T1 | 1–3 | TPE, cabinet solo |
| T2 | 4–10 | Petite PME |
| T3 | 11–25 | PME (cœur de cible) |
| T4 | 26–60 | PME structurée |
| T5 | 61–150 | ETI |
| T6 | 150+ | Devis |

### Prix mensuels (FCFA HT)

| | T1 (1–3) | T2 (4–10) | T3 (11–25) | T4 (26–60) | T5 (61–150) |
|---|---|---|---|---|---|
| **Frais de plateforme** | 8 000 | 15 000 | 25 000 | 40 000 | 60 000 |
| **Module Cœur** (chacun) | 12 000 | 22 000 | 38 000 | 60 000 | 90 000 |
| **Module Métier** (chacun) | 10 000 | 18 000 | 30 000 | 48 000 | 72 000 |
| **Module Avancé** (chacun) | 15 000 | 28 000 | 45 000 | 70 000 | 105 000 |

### RH/Paie — facturé à l'effectif géré

| Bulletins/mois | Prix mensuel |
|---|---|
| ≤ 25 | 15 000 FCFA |
| ≤ 75 | 30 000 FCFA |
| ≤ 200 | 55 000 FCFA |
| > 200 | Devis |

### Remises de bundle

| Modules activés | Remise |
|---|---|
| 1–2 | 0 % |
| 3 | −15 % |
| 4–5 | −25 % |
| 6–8 | −35 % |
| Les 17 (Suite Complète) | −50 % |

### Offres affichées sur le site

| Offre | T1 (1–3) | T2 (4–10) | T3 (11–25) |
|---|---|---|---|
| **Essentiel** — Socle + Compta + Trésorerie | 29 000 (~44 €) | 59 000 (~90 €) | 99 000 (~151 €) |
| **Gestion** — + Commercial, Achats, Stock | 49 000 (~75 €) | 89 000 (~136 €) | 149 000 (~227 €) |
| **Suite Complète** — les 17 modules | 79 000 (~120 €) | 149 000 (~227 €) | 249 000 (~380 €) |

### Leviers additionnels

- **Engagement annuel prépayé** : −20 % (3 mois offerts)
- **Offre Fondateurs** — 50 premiers tenants : −50 % pendant 12 mois + prix gelé 36 mois
- **Multi-société** : 3 sociétés incluses, puis +15 % par société additionnelle
- **PPP régional** : CI/Sénégal = 100 · Maroc ×1,15 · Tunisie ×0,90 · Europe/diaspora ×2,2
- **Services** : onboarding 150 000–600 000 FCFA · migration Sage offerte · formation 50 000 FCFA/jour
- **Canal experts-comptables** : portail cabinet gratuit + 25 % de revenue share récurrent

---

## 4. FREEMIUM PERMANENT — Onusuite Solo

| Élément | Limite |
|---|---|
| Utilisateurs | 1 |
| Sociétés | 1 |
| Modules | Comptabilité + Trésorerie |
| Écritures/an | 500 |
| Exports PDF | Filigrane |
| Support | Communautaire |

Rôle : haut de funnel pour micro-entrepreneurs et alimentation du canal cabinets.

---

## 5. AFFICHAGE DES PRIX SUR LA PAGE D'ACCUEIL

### Page d'accueil publique (avant login)

Créer une **landing page publique** accessible sans authentification sur la route `/` (ou `/pricing`), avec :

1. **Hero section** — tagline Onusuite, bouton « Démarrer l'essai gratuit »
2. **Section modules** — les 17 modules avec icônes
3. **Section pricing** — 3 offres (Essentiel, Gestion, Suite Complète) avec sélecteur de palier
4. **Sélecteur de devise** — choix manuel + détection automatique par géolocalisation/navigateur
5. **Sélecteur de palier** — T1/T2/T3/T4/T5 avec slider ou onglets
6. **FAQ essai** — durée, limites, bascule freemium, migration Sage offerte
7. **CTA final** — « Démarrer l'essai 45 jours » + « Parler à un commercial »

### Conversion automatique des devises

#### API utilisée : Frankfurter (gratuite, sans clé API)

L'app utilise déjà `https://api.frankfurter.app/latest` dans `currencyRates.ts` (fonction `refreshRatesFromECB`).

#### Devises affichées

| Code | Devise | Pays |
|---|---|---|
| XOF | Franc CFA UEMOA | CI, Sénégal, Burkina, Mali, Bénin, Togo, Niger |
| XAF | Franc CFA CEMAC | Cameroun, Gabon, Tchad, Congo, RCA, Guinée Éq. |
| MAD | Dirham marocain | Maroc |
| TND | Dinar tunisien | Tunisie |
| DZD | Dinar algérien | Algérie |
| EUR | Euro | Europe / référence |
| USD | Dollar US | International |

#### Logique de détection

1. **Détection automatique** : `navigator.language` + `Intl.DateTimeFormat().resolvedOptions().timeZone` pour déduire le pays
2. **Fallback manuel** : sélecteur de drapeau en haut de la section pricing
3. **Sauvegarde locale** : `localStorage.setItem('preferred_currency', code)` pour mémoriser le choix

#### Taux de conversion hebdomadaires

- **Cron Supabase** (Edge Function ou pg_cron) : tous les lundis à 06h00 UTC, appelle Frankfurter API et stocke les taux dans la table `exchange_rates`
- **Table existante** : `exchange_rates` (déjà en place avec `base_currency`, `quote_currency`, `rate`, `rate_date`, `source`)
- **Source** : `source = 'frankfurter'` pour les taux auto, `source = 'manual'` pour les taux manuels
- **Affichage** : « Prix mis à jour le [date] · Taux : 1 EUR = 655,957 XOF »

#### Conversion des prix

```
Prix de base en FCFA (XOF) → conversion vers la devise sélectionnée
1. Récupérer le taux XOF → [devise cible] depuis exchange_rates
2. Si taux direct indisponible : XOF → EUR → [devise cible]
3. Arrondir au millier supérieur pour l'affichage commercial
```

#### Affichage dual

Pour chaque prix, afficher :
- **Prix principal** dans la devise locale détectée (ex: 99 000 FCFA)
- **Prix secondaire** en EUR et/ou USD en gris plus petit (ex: ≈ 151 € · ≈ $163)

---

## 6. KPIs DE PILOTAGE

| Métrique | Cible |
|---|---|
| Essai → payant (self-serve) | 18–25 % |
| Essai → payant (accompagné) | > 40 % |
| Time-to-value (1ʳᵉ écriture ou facture) | < 48 h |
| Modules activés par tenant | ≥ 5 |
| Payback CAC | < 9 mois |
| Churn mensuel | < 5 % |
| NRR | > 110 % |

---

## 7. PHASES DE DÉPLOIEMENT

### Phase 1 (maintenant → 6 mois) : Acquisition & preuve sociale
- Reverse trial 45 jours + Freemium permanent
- 20 design partners gratuits 12 mois
- Canal cabinets comptables (portail gratuit + 25 % revenue share)
- Migration Sage offerte
- Paiement : virement + Wave (manuel/semi-auto)

### Phase 2 (6–12 mois) : Monétisation
- Conversion freemium → payant
- Tarification v2 active
- Offre Fondateurs

### Phase 3 (12–18 mois) : Expansion
- Partenariat Mobile Money / PSP (crédits prépayés)
- Embedded fintech (paiements fournisseurs, décaissement paie)
- Distribution bancaire / télécom