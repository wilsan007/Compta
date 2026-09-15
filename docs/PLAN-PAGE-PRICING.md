# PLAN PAGE PRICING ONUSUITE — Spécification fonctionnelle & technique

## 1. OBJECTIF

Créer une **page pricing publique** (sans authentification) qui présente les offres Onusuite avec conversion automatique des devises selon le pays du visiteur.

---

## 2. ROUTES

| Route | Auth | Description |
|---|---|---|
| `/pricing` | Non | Page pricing standalone (publique) |
| `/` | Non | Landing page publique avec section pricing intégrée |

**Note** : Actuellement `/` pointe vers `<DashboardPage />` protégée. Il faut créer une landing page publique sur `/` et déplacer le dashboard vers `/app` ou `/dashboard`.

---

## 3. STRUCTURE DE LA PAGE

### 3.1 Hero Section

- Tagline : **« Onusuite — The Unified Business Suite »**
- Sous-titre : « 17 modules unifiés. Trilingue FR/EN/AR. Conforme fiscalement. »
- Bouton CTA principal : **« Démarrer l'essai gratuit 45 jours »** → `/signup`
- Bouton CTA secondaire : **« Parler à un commercial »** → `mailto:contact@onusuite.com`
- Visuel : fond géométrique avec palette Onusuite (Terracotta #C44536, Indigo #1E2A4A, Sable #F5F0E8)

### 3.2 Section Modules (aperçu)

Grille des 17 modules avec icônes et descriptions courtes :

| Module | Icône | Catégorie |
|---|---|---|
| Comptabilité | BookOpen | Cœur |
| Trésorerie | Wallet | Cœur |
| Commercial (Ventes/Achats) | ShoppingCart | Cœur |
| Stock | Package | Métier |
| Production | Factory | Métier |
| RH/Paie | Users | Métier |
| Gestion de projet | KanbanSquare | Métier |
| CRM | UserCircle | Métier |
| Immobilisations | Building2 | Avancé |
| Analytique | BarChart3 | Avancé |
| Reporting | FileText | Avancé |
| Dashboards | LayoutDashboard | Avancé |
| Banque | Landmark | Avancé |
| Système | Settings | Socle |
| Documentation | HelpCircle | Socle |
| Notifications | Bell | Socle |
| Multi-société | Building | Socle |

### 3.3 Section Pricing (cœur de la page)

#### Sélecteur de palier

Onglets ou slider avec 5 paliers :

| Palier | Utilisateurs | Label |
|---|---|---|
| T1 | 1–3 | Solo / TPE |
| T2 | 4–10 | Petite PME |
| T3 | 11–25 | PME |
| T4 | 26–60 | PME structurée |
| T5 | 61–150 | ETI |

#### 3 offres affichées (cartes côte à côte)

| Offre | Modules inclus | Couleur carte |
|---|---|---|
| **Essentiel** | Socle + Comptabilité + Trésorerie | Sable clair |
| **Gestion** | Essentiel + Commercial + Achats + Stock | Terracotta clair |
| **Suite Complète** | Les 17 modules (−50 % bundle) | Terracotta foncé (mise en avant) |

Chaque carte affiche :
- Nom de l'offre
- Prix mensuel dans la devise sélectionnée (gros)
- Prix secondaire en EUR et USD (petit, gris)
- Liste des modules inclus (avec icônes)
- Bouton « Démarrer l'essai » → `/signup`
- Badge « 45 jours gratuits » sur la carte Suite Complète

#### Prix de base (FCFA HT, T1 → T5)

| Offre | T1 | T2 | T3 | T4 | T5 |
|---|---|---|---|---|---|
| Essentiel | 29 000 | 59 000 | 99 000 | 159 000 | 239 000 |
| Gestion | 49 000 | 89 000 | 149 000 | 239 000 | 359 000 |
| Suite Complète | 79 000 | 149 000 | 249 000 | 399 000 | 599 000 |

#### Options additionnelles (cases à cocher sous les cartes)

- **Engagement annuel** : −20 % (badge « 3 mois offerts »)
- **RH/Paie** : +15 000–55 000 FCFA selon effectif
- **Multi-société** : 3 incluses, +15 % par société supplémentaire

### 3.4 Sélecteur de Devise

Position : haut de la section pricing, à droite.

#### Détection automatique

```typescript
function detectCurrency(): string {
  // 1. Vérifier localStorage
  const saved = localStorage.getItem('preferred_currency')
  if (saved) return saved

  // 2. Déduire du timezone
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
  const tzToCurrency: Record<string, string> = {
    'Africa/Abidjan': 'XOF',
    'Africa/Dakar': 'XOF',
    'Africa/Ouagadougou': 'XOF',
    'Africa/Bamako': 'XOF',
    'Africa/Porto-Novo': 'XOF',
    'Africa/Lome': 'XOF',
    'Africa/Niamey': 'XOF',
    'Africa/Douala': 'XAF',
    'Africa/Libreville': 'XAF',
    'Africa/Ndjamena': 'XAF',
    'Africa/Brazzaville': 'XAF',
    'Africa/Bangui': 'XAF',
    'Africa/Malabo': 'XAF',
    'Africa/Casablanca': 'MAD',
    'Africa/Tunis': 'TND',
    'Africa/Algiers': 'DZD',
    'Europe/Paris': 'EUR',
    'Europe/London': 'EUR',
    'Europe/Berlin': 'EUR',
    'America/New_York': 'USD',
  }
  return tzToCurrency[tz] || 'EUR'
}
```

#### Sélecteur manuel (drapeaux cliquables)

| Drapeau | Code | Devise | Pays |
|---|---|---|---|
| 🇨🇮🇸🇳 | XOF | Franc CFA UEMOA | CI, Sénégal, Burkina, Mali, Bénin, Togo, Niger |
| 🇨🇲🇬🇦 | XAF | Franc CFA CEMAC | Cameroun, Gabon, Tchad, Congo, RCA, Guinée Éq. |
| 🇲🇦 | MAD | Dirham marocain | Maroc |
| 🇹🇳 | TND | Dinar tunisien | Tunisie |
| 🇩🇿 | DZD | Dinar algérien | Algérie |
| 🇪🇺 | EUR | Euro | Europe / référence |
| 🇺🇸 | USD | Dollar US | International |

#### Sauvegarde du choix

```typescript
localStorage.setItem('preferred_currency', currencyCode)
```

### 3.5 Affichage Dual des Prix

Pour chaque prix, afficher deux lignes :

```
99 000 FCFA          ← prix principal (devise sélectionnée), gros, bold
≈ 151 € · ≈ $163     ← prix secondaire (EUR + USD), petit, gris
```

#### Logique de conversion

```typescript
// Prix de base en XOF (FCFA)
const BASE_PRICES = {
  essential: { T1: 29000, T2: 59000, T3: 99000, T4: 159000, T5: 239000 },
  management: { T1: 49000, T2: 89000, T3: 149000, T4: 239000, T5: 359000 },
  suite: { T1: 79000, T2: 149000, T3: 249000, T4: 399000, T5: 599000 },
}

async function convertPrice(amountXOF: number, targetCurrency: string): Promise<number> {
  // 1. Récupérer le taux depuis exchange_rates (tenant_id IS NULL)
  const rate = await getLatestRate('XOF', targetCurrency)
  if (rate) return Math.ceil(amountXOF * rate / 1000) * 1000 // arrondi au millier

  // 2. Fallback : XOF → EUR → target
  const xofToEur = 1 / 655.957
  const eurToTarget = await getLatestRate('EUR', targetCurrency)
  if (eurToTarget) return Math.ceil(amountXOF * xofToEur * eurToTarget / 1000) * 1000

  // 3. Ultimate fallback : taux fixe
  return amountXOF // reste en XOF
}
```

### 3.6 Section FAQ Essai

Accordéon avec questions/réponses (i18n fr/en/ar) :

1. **Combien de temps dure l'essai gratuit ?** → 45 jours (60 pour RH/Paie), extensible à 75–90 jours
2. **Faut-il une carte bancaire ?** → Non, aucune carte requise
3. **Que se passe-t-il après l'essai ?** → Bascule sur Onusuite Solo (gratuit à vie, limité)
4. **Quels modules sont inclus dans l'essai ?** → Les 17 modules débloqués
5. **Peut-on migrer depuis Sage ?** → Oui, migration Sage offerte gratuitement
6. **Quelles limites pendant l'essai ?** → 10 utilisateurs, 3 sociétés, écritures illimitées
7. **Le support est-il inclus ?** → Chat + email pendant l'essai
8. **Peut-on faire des déclarations réelles ?** → Simulation uniquement, déclarations réelles après paiement

### 3.7 CTA Final

Section pleine largeur avec fond Terracotta #C44536 :

- **« Prêt à unifier votre gestion ? »**
- Bouton : **« Démarrer l'essai 45 jours »** → `/signup`
- Bouton : **« Parler à un commercial »** → `mailto:contact@onusuite.com`
- Petit texte : « Sans carte bancaire · Migration Sage offerte · Annulez à tout moment »

---

## 4. INFRASTRUCTURE TECHNIQUE

### 4.1 Composants React à créer

| Fichier | Rôle |
|---|---|
| `app/src/pages/PricingPage.tsx` | Page pricing complète (route `/pricing`) |
| `app/src/pages/LandingPage.tsx` | Landing page publique (route `/`) |
| `app/src/components/pricing/PricingCards.tsx` | Cartes des 3 offres |
| `app/src/components/pricing/TierSelector.tsx` | Sélecteur de palier T1–T5 |
| `app/src/components/pricing/CurrencyPicker.tsx` | Sélecteur de devise avec drapeaux |
| `app/src/components/pricing/PriceDisplay.tsx` | Affichage dual d'un prix (devise locale + EUR/USD) |
| `app/src/components/pricing/TrialFAQ.tsx` | Accordéon FAQ essai |
| `app/src/components/pricing/ModuleShowcase.tsx` | Grille des 17 modules |
| `app/src/lib/pricing.ts` | Données de prix, conversion, détection devise |

### 4.2 Librairie `pricing.ts`

```typescript
// Prix de base en XOF (FCFA HT)
export const BASE_PRICES = {
  essential:  { T1: 29000,  T2: 59000,  T3: 99000,  T4: 159000, T5: 239000 },
  management: { T1: 49000,  T2: 89000,  T3: 149000, T4: 239000, T5: 359000 },
  suite:      { T1: 79000,  T2: 149000, T3: 249000, T4: 399000, T5: 599000 },
}

export const TIERS = [
  { id: 'T1', min: 1,   max: 3,   labelKey: 'pricing.tier.t1' },
  { id: 'T2', min: 4,   max: 10,  labelKey: 'pricing.tier.t2' },
  { id: 'T3', min: 11,  max: 25,  labelKey: 'pricing.tier.t3' },
  { id: 'T4', min: 26,  max: 60,  labelKey: 'pricing.tier.t4' },
  { id: 'T5', min: 61,  max: 150, labelKey: 'pricing.tier.t5' },
]

export const SUPPORTED_CURRENCIES = [
  { code: 'XOF', flag: '🇨🇮', labelKey: 'pricing.currency.xof' },
  { code: 'XAF', flag: '🇨🇲', labelKey: 'pricing.currency.xaf' },
  { code: 'MAD', flag: '🇲🇦', labelKey: 'pricing.currency.mad' },
  { code: 'TND', flag: '🇹🇳', labelKey: 'pricing.currency.tnd' },
  { code: 'DZD', flag: '🇩🇿', labelKey: 'pricing.currency.dzd' },
  { code: 'EUR', flag: '🇪🇺', labelKey: 'pricing.currency.eur' },
  { code: 'USD', flag: '🇺🇸', labelKey: 'pricing.currency.usd' },
]

export function detectCurrencyFromTimezone(): string { ... }
export async function convertPrice(amountXOF: number, target: string): Promise<number> { ... }
export function formatPrice(amount: number, currency: string, locale: string): string { ... }
```

### 4.3 Conversion des devises

- **API** : Frankfurter (`https://api.frankfurter.app/latest`) — gratuite, sans clé, taux BCE
- **Edge Function** : `refresh-exchange-rates` (déjà créée) — stocke les taux dans `exchange_rates`
- **Cron** : tous les lundis 06h00 UTC via `pg_cron` (migration `72_exchange_rate_cron.sql`)
- **Taux fixes** : XOF et XAF = 655,957 EUR (peg officiel)
- **Table** : `exchange_rates` avec `tenant_id = NULL` pour les taux globaux
- **Récupération** : `getLatestRate('XOF', targetCurrency)` depuis `currencyRates.ts`

### 4.4 i18n — Namespace `pricing`

Créer les fichiers de traduction dans :

```
app/src/i18n/locales/fr/pricing.json
app/src/i18n/locales/en/pricing.json
app/src/i18n/locales/ar/pricing.json
```

#### Clés de traduction nécessaires

```json
{
  "hero": {
    "tagline": "Onusuite — The Unified Business Suite",
    "subtitle": "...",
    "ctaTrial": "...",
    "ctaContact": "..."
  },
  "tier": {
    "t1": "Solo / TPE (1–3 utilisateurs)",
    "t2": "Petite PME (4–10 utilisateurs)",
    "t3": "PME (11–25 utilisateurs)",
    "t4": "PME structurée (26–60 utilisateurs)",
    "t5": "ETI (61–150 utilisateurs)"
  },
  "plan": {
    "essential": { "name": "...", "description": "..." },
    "management": { "name": "...", "description": "..." },
    "suite": { "name": "...", "description": "..." }
  },
  "currency": {
    "xof": "Franc CFA UEMOA",
    "xaf": "Franc CFA CEMAC",
    "mad": "Dirham marocain",
    "tnd": "Dinar tunisien",
    "dzd": "Dinar algérien",
    "eur": "Euro",
    "usd": "Dollar US"
  },
  "options": {
    "annual": "Engagement annuel (−20 %)",
    "payroll": "RH/Paie",
    "multiCompany": "Multi-société"
  },
  "faq": {
    "q1": "...", "a1": "...",
    "q2": "...", "a2": "...",
    ...
  },
  "cta": {
    "startTrial": "Démarrer l'essai 45 jours",
    "contactSales": "Parler à un commercial",
    "noCard": "Sans carte bancaire",
    "migration": "Migration Sage offerte",
    "cancelAnytime": "Annulez à tout moment"
  },
  "rateUpdated": "Prix mis à jour le {{date}}",
  "perMonth": "/mois",
  "modules": {
    "accounting": "Comptabilité",
    "treasury": "Trésorerie",
    ...
  }
}
```

### 4.5 Routes dans App.tsx

```tsx
// Route publique (sans ProtectedLayout)
<Route path="/pricing" element={<PricingPage />} />
<Route path="/" element={<LandingPage />} />

// Dashboard déplacé
<Route path="/dashboard" element={<ProtectedLayout><DashboardPage /></ProtectedLayout>} />
```

---

## 5. DESIGN & UX

### 5.1 Palette (brand Onusuite)

| Rôle | Couleur | Hex |
|---|---|---|
| Primaire | Terracotta profonde | #C44536 |
| Texte | Indigo profond | #1E2A4A |
| Fond | Sable clair | #F5F0E8 |
| Accent 1 | Vert émeraude | #2D7D6F |
| Accent 2 | Ambre | #E8A838 |

### 5.2 Cartes pricing

- **Essentiel** : fond `#F5F0E8`, bordure subtile
- **Gestion** : fond blanc, bordure Terracotta clair `#C4453633`
- **Suite Complète** : fond Terracotta foncé `#C44536`, texte blanc, badge « Populaire »
- Animation : `hover:-translate-y-2 hover:shadow-2xl transition-all duration-300`
- Coins arrondis : `rounded-3xl`
- Padding généreux : `p-8`

### 5.3 Responsive

- **Desktop** : 3 cartes côte à côte (`grid-cols-3`)
- **Tablette** : 3 cartes en ligne étroite ou 2+1 (`grid-cols-2` puis carte pleine largeur)
- **Mobile** : cartes empilées (`grid-cols-1`), sélecteur de palier en scroll horizontal

### 5.4 RTL (Arabe)

- `dir="rtl"` sur le conteneur principal
- Cartes pricing : ordre inversé (Suite Complète à droite en RTL)
- Texte aligné à droite
- Sélecteur de devise : drapeaux de droite à gauche

---

## 6. FREEMIUM — Onusuite Solo

Section séparée sous les cartes pricing, encadré discret :

> **Onusuite Solo — Gratuit à vie**
> 1 utilisateur · 1 société · Comptabilité + Trésorerie · 500 écritures/an
> Bouton : **« Commencer gratuitement »** → `/signup?plan=solo`

---

## 7. OFFRE FONDATEURS

Bannière en haut de la section pricing (dismissible) :

> 🎉 **Offre Fondateurs** — 50 premiers tenants : −50 % pendant 12 mois + prix gelé 36 mois.
> Bouton : **« En profiter »** → `/signup?plan=founder`

---

## 8. DÉPENDANCES EXISTANTES À RÉUTILISER

| Fichier | Usage |
|---|---|
| `app/src/lib/currencyRates.ts` | `getLatestRate()`, `formatCurrencyWithCode()`, `refreshRatesFromECB()` |
| `app/src/components/CurrencySelector.tsx` | Référence UI pour sélecteur de devise |
| `app/src/lib/supabase.ts` | Client Supabase pour queries |
| `app/src/lib/auth.ts` | Hook `useAuth` (pour adapter le CTA si déjà connecté) |
| `app/src/i18n/index.ts` | Config i18n, ajout namespace `pricing` |
| Table `exchange_rates` | Taux de change globaux (`tenant_id = NULL`) |

---

## 9. EDGE FUNCTION & CRON (déjà créés)

| Fichier | Statut |
|---|---|
| `supabase/functions/refresh-exchange-rates/index.ts` | ✅ Créé |
| `sql/72_exchange_rate_cron.sql` | ✅ Créé (cron hebdomadaire + seed initial) |

### Déploiement

```bash
# 1. Déployer l'Edge Function
supabase functions deploy refresh-exchange-rates

# 2. Activer pg_cron + pg_net dans Supabase Dashboard > Database > Extensions

# 3. Exécuter la migration SQL dans SQL Editor

# 4. Test manuel
curl -X POST https://[project].supabase.co/functions/v1/refresh-exchange-rates \
  -H "Authorization: Bearer [service-role-key]" \
  -H "Content-Type: application/json" -d '{}'
```

---

## 10. PLAN D'IMPLÉMENTATION

### Étape 1 : Librairie & données
- Créer `app/src/lib/pricing.ts` (prix, devises, détection, conversion)
- Étendre `currencyRates.ts` si besoin (query taux globaux `tenant_id IS NULL`)

### Étape 2 : i18n
- Créer `app/src/i18n/locales/{fr,en,ar}/pricing.json`
- Enregistrer le namespace `pricing` dans `app/src/i18n/index.ts`

### Étape 3 : Composants pricing
- `CurrencyPicker.tsx` — drapeaux + détection auto
- `TierSelector.tsx` — onglets T1–T5
- `PriceDisplay.tsx` — affichage dual
- `PricingCards.tsx` — 3 cartes offres
- `TrialFAQ.tsx` — accordéon
- `ModuleShowcase.tsx` — grille modules

### Étape 4 : Page pricing
- `PricingPage.tsx` — assemblage de tous les composants
- `LandingPage.tsx` — landing avec hero + modules + pricing + FAQ + CTA

### Étape 5 : Routes
- Modifier `App.tsx` : ajouter `/pricing` et `/` publiques, déplacer dashboard

### Étape 6 : Validation
- `npx tsc --noEmit` dans `/app`
- `npm run dev` + browser preview
- Tester les 3 langues (fr/en/ar) + RTL
- Tester la conversion de devise (XOF, MAD, EUR, USD)
- Vérifier responsive (mobile, tablette, desktop)
