# Plan d'Implémentation Détaillé — 42 Éléments (Odoo Gaps)

> **Objectif** : Combler les 42 gaps identifiés dans le comparatif Odoo 19 vs Projet Compta
> **Référence** : Documents `11_COMPARATIF` à `15_COMPARATIF` + `02_DEEP_SCRAPING_01_ACCOUNTING.md`
> **Priorité** : 21 éléments critiques (Clusters 1-8) + 21 éléments à fort apport (Clusters 9-14)

---

## TABLE DES MATIÈRES

### Phase 1 — Éléments critiques (21)
1. [Cluster 1 : Multi-Devises Natif (#33, #57, #79, #85, #88)](#cluster-1)
2. [Cluster 2 : Moteur Taxes Avancé (#11, #18, #20, #21)](#cluster-2)
3. [Cluster 3 : Position Fiscale (#32, #56, #66)](#cluster-3)
4. [Cluster 4 : Analytique Multi-Axes (#45, #46)](#cluster-4)
5. [Cluster 5 : Comptes Liés Immobilisation (#90, #91, #92)](#cluster-5)
6. [Cluster 6 : Multi-Contacts (#62)](#cluster-6)
7. [Cluster 7 : Sync Bancaire API (#69)](#cluster-7)
8. [Cluster 8 : Types de Comptes Précis (#1)](#cluster-8)

### Phase 2 — Éléments à fort apport (21)
9. [Cluster 9 : Multi-Devises Étendu (#5, #9, #86, #87, #89)](#cluster-9)
10. [Cluster 10 : Taxes Intermédiaires (#12, #13, #14, #19, #22, #23, #24)](#cluster-10)
11. [Cluster 11 : Écritures (#30, #34, #39, #40, #42, #47)](#cluster-11)
12. [Cluster 12 : Tiers (#63, #64, #65)](#cluster-12)
13. [Cluster 13 : Banque (#70, #72, #80)](#cluster-13)
14. [Cluster 14 : Immobilisation + Chéquier (#93, #82)](#cluster-14)

---

<a id="cluster-1"></a>
## CLUSTER 1 : Multi-Devises Natif (#33, #57, #79, #85, #88)

### 1.1 Vue d'ensemble
Rendre le multi-devises natif sur tous les objets comptables + taux de change automatiques via API.

### 1.2 Élément #33 — Devise sur les Écritures (JournalEntry)
**Table** : `journal_entries`
**Champs à ajouter** :
- `currency_code` (text, nullable) — code ISO 4217 (ex: EUR, USD, MAD)
- `functional_currency` (text, default 'EUR') — devise tenue du dossier
- `exchange_rate` (numeric(12,6), default 1.0) — taux de change à la date de l'écriture
- `exchange_rate_date` (date, nullable) — date du taux (peut différer de la date comptable)

**SQL** :
```sql
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS functional_currency text DEFAULT 'EUR';
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS exchange_rate_date date;
```

**Type TypeScript** (`types/index.ts`) :
```typescript
interface JournalEntry {
  // ... existing
  currency_code: string;         // #33
  functional_currency: string;   // #33
  exchange_rate: number;         // #33
  exchange_rate_date: string | null; // #33
}
```

**UI** : `JournalSaisiePage.tsx` + `SaisieParPiecePage.tsx`
- Ajouter un sélecteur de devise dans l'en-tête de l'écriture
- Afficher le taux de change (auto-récupéré si API connectée, sinon saisie manuelle)
- Colonne "Montant devise" à côté de "Débit" / "Crédit" dans la grille
- Colonne "Taux" dans l'en-tête
- Bouton "Actualiser le taux" → récupère le taux du jour via API

**Page/Composant** :
- `CurrencySelector` composant réutilisable (dropdown avec drapeaux + code ISO)
- Modification dans `JournalSaisiePage.tsx` : ajout colonnes "Devise", "Montant devise", "Taux"
- Modification dans `SaisieParPiecePage.tsx` : ajout devise + taux dans l'en-tête

### 1.3 Élément #57 — Devise sur les Journaux (Journal)
**Table** : `journals`
**Champs à ajouter** :
- `currency_code` (text, default 'EUR') — devise du journal
- `sequence` (integer, default 0) — ordre d'affichage dans le dashboard

**SQL** :
```sql
ALTER TABLE journals ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE journals ADD COLUMN IF NOT EXISTS sequence integer DEFAULT 0;
```

**UI** : `JournalsPage.tsx`
- Ajouter champ "Devise" dans le formulaire du journal (dropdown)
- Ajouter champ "Ordre d'affichage" (nombre entier)
- Colonne "Devise" dans la liste des journaux
- Trier la liste par `sequence` au lieu de `created_at`

### 1.4 Élément #79 — Devise sur les Comptes (ChartAccount)
**Table** : `chart_accounts`
**Champs à ajouter** :
- `currency_code` (text, nullable) — devise forcée (null = devise tenue)
- `reconcile` (boolean, default false) — compte réconciliable (lettrage)
- `deprecated` (boolean, default false) — compte obsolète

**SQL** :
```sql
ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS currency_code text;
ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS reconcile boolean DEFAULT false;
ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS deprecated boolean DEFAULT false;
```

**UI** : `ChartAccountsPage.tsx`
- Ajouter colonne "Devise" dans la liste (affiche code ISO ou "Tenue")
- Ajouter checkbox "Réconciliable" dans la fiche compte
- Ajouter checkbox "Obsolète" dans la fiche compte
- Filtrer les comptes obsolètes par défaut (toggle "Afficher obsolètes")
- Griser les comptes obsolètes dans la saisie

### 1.5 Élément #85 — Devise sur les Paiements
**Tables** : `customer_payments`, `supplier_payments`, `payment_orders`
**Champs à ajouter** :
- `currency_code` (text, default 'EUR')
- `exchange_rate` (numeric(12,6), default 1.0)
- `amount_currency` (numeric(14,2)) — montant dans la devise d'origine
- `exchange_gain_loss` (numeric(14,2), default 0) — écart de change

**SQL** :
```sql
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS amount_currency numeric(14,2);
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS exchange_gain_loss numeric(14,2) DEFAULT 0;

ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS amount_currency numeric(14,2);
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS exchange_gain_loss numeric(14,2) DEFAULT 0;
```

**UI** :
- `CustomerPaymentsPage.tsx` : ajout devise + taux + montant devise + écart de change
- `SupplierPaymentsPage.tsx` : idem
- `PaymentGenerationPage.tsx` : prise en compte de la devise du tiers
- `PaymentOrdersPage.tsx` : devise sur l'ordre de paiement

### 1.6 Élément #88 — Taux de Change Automatiques (API)
**Nouvelle table** : `exchange_rates`
```sql
CREATE TABLE IF NOT EXISTS exchange_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  base_currency text NOT NULL,        -- ex: 'EUR'
  quote_currency text NOT NULL,       -- ex: 'USD'
  rate numeric(12,6) NOT NULL,        -- ex: 1.0852
  rate_date date NOT NULL,
  source text DEFAULT 'manual',       -- 'ecb' | 'manual' | 'user'
  created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_exchange_rates_unique
  ON exchange_rates(tenant_id, base_currency, quote_currency, rate_date);
```

**Nouvelle edge function** : `supabase/functions/fetch-exchange-rates/index.ts`
- Appel API Banque Centrale Européenne (ECB) : `https://api.frankfurter.app/latest`
- Récupère les taux pour 30+ devises
- Stocke dans `exchange_rates`
- Peut être appelée manuellement ou via cron

**Nouvelle page UI** : `ExchangeRatesPage.tsx`
- Tableau des taux de change par date
- Graphique d'évolution sur 30 jours
- Bouton "Actualiser les taux" → appelle l'edge function
- Saisie manuelle de taux personnalisés
- Dropdown paire de devises (base + quote)

**Nouveau composant** : `CurrencyRatePicker`
- Sélectionne une paire de devises + une date
- Récupère automatiquement le taux depuis `exchange_rates`
- Si pas de taux trouvé → propose saisie manuelle
- Utilisé dans : JournalSaisiePage, SaisieParPiecePage, CustomerPayments, SupplierPayments, Invoices, PurchaseInvoices

**Nouvelle lib** : `src/lib/currencyRates.ts`
- `getRate(base, quote, date)` — récupère le taux depuis Supabase
- `getLatestRate(base, quote)` — récupère le dernier taux disponible
- `convertAmount(amount, fromCurrency, toCurrency, date)` — convertit un montant
- `formatCurrency(amount, currency)` — formate avec symbole et locale

---

<a id="cluster-2"></a>
## CLUSTER 2 : Moteur Taxes Avancé (#11, #18, #20, #21)

### 2.1 Élément #11 — Taxes Groupées (children_tax_ids)
**Table** : `tax_rates`
**Champs à ajouter** :
- `amount_type` (text, default 'percent') — 'fixed' | 'percent' | 'group' | 'division'
- `type_tax_use` (text, default 'none') — 'sale' | 'purchase' | 'none'
- `sequence` (integer, default 10) — ordre d'application
- `parent_tax_id` (uuid, nullable) — pour les taxes enfants d'un groupe

**SQL** :
```sql
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS amount_type text DEFAULT 'percent';
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS type_tax_use text DEFAULT 'none';
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS sequence integer DEFAULT 10;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS parent_tax_id uuid REFERENCES tax_rates(id);
```

**Nouvelle table** : `tax_groups`
```sql
CREATE TABLE IF NOT EXISTS tax_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,           -- ex: "TVA 20% + CRL 0,1%"
  country_code text,            -- ex: 'DZ'
  created_at timestamptz DEFAULT now()
);
```

**UI** : `TaxRatesPage.tsx`
- Onglet "Taxes groupées" (nouvel onglet à côté de "Taux", "Rubriques", "Assistant")
- Création d'une taxe groupée : sélection de taxes enfants + ordre d'application
- Visualisation en arbre des taxes parent → enfants
- Calcul en cascade : applique chaque taxe enfant dans l'ordre de `sequence`

### 2.2 Élément #18 — Répartition des Taxes par Compte
**Nouvelle table** : `tax_repartition_lines`
```sql
CREATE TABLE IF NOT EXISTS tax_repartition_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  tax_id uuid NOT NULL REFERENCES tax_rates(id) ON DELETE CASCADE,
  document_type text NOT NULL,     -- 'invoice' | 'refund'
  repartition_type text NOT NULL,  -- 'base' | 'tax'
  factor numeric(5,2) DEFAULT 100, -- pourcentage (100% = tout sur ce compte)
  account_code text,               -- compte à débiter/créditer
  tag_ids text[],                  -- tags fiscaux (ex: case CA3)
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tax_repartition_tax ON tax_repartition_lines(tax_id);
```

**UI** : `TaxRatesPage.tsx` → fiche taxe
- Nouvel onglet "Répartition" dans la fiche d'une taxe
- Tableau à 2 sections : "Sur facture" et "Sur avoir"
- Chaque section : lignes avec type (base/taxe), facteur (%), compte, tags
- Bouton "Ajouter une ligne de répartition"
- Visualisation : pour une taxe à 20%, montrer comment les 20% sont répartis sur quels comptes

### 2.3 Élément #20 — TVA sur Encaissement avec Compte de Transition
**Table** : `tax_rates`
**Champs à ajouter** :
- `tax_exigibility` (text, default 'on_invoice') — 'on_invoice' | 'on_payment'
- `cash_basis_transition_account` (text, nullable) — compte de transition

**SQL** :
```sql
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS tax_exigibility text DEFAULT 'on_invoice';
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS cash_basis_transition_account text;
```

**Nouvelle table** : `tax_cash_basis_entries`
```sql
CREATE TABLE IF NOT EXISTS tax_cash_basis_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  tax_id uuid REFERENCES tax_rates(id),
  payment_id uuid,               -- lien vers le paiement qui déclenche l'exigibilité
  journal_entry_id uuid,         -- écriture de bascule générée
  base_amount numeric(14,2),
  tax_amount numeric(14,2),
  transition_date date,
  status text DEFAULT 'pending', -- 'pending' | 'posted'
  created_at timestamptz DEFAULT now()
);
```

**Logique métier** :
- Lors du paiement d'une facture avec TVA sur encaissement :
  1. Génère une écriture de bascule : débit compte de transition → crédit compte de TVA collectée
  2. Enregistre dans `tax_cash_basis_entries`
  3. Met à jour la déclaration TVA

**UI** :
- `TaxRatesPage.tsx` : champ "Exigibilité" (débits/encaissements) déjà présent, ajouter "Compte de transition"
- `VatReturnsPage.tsx` : onglet "TVA sur encaissement" montrant les bascules
- `CustomerPaymentsPage.tsx` : lors d'un paiement, si la facture a des taxes sur encaissement → générer la bascule

### 2.4 Élément #21 — Taxes Forfaitaires et par Division
**Table** : `tax_rates`
**Champs à ajouter** :
- `price_include` (boolean, default false) — taxe incluse dans le prix (TTC)
- `include_base_amount` (boolean, default false) — inclure dans la base des taxes suivantes
- `is_base_affected` (boolean, default true) — affecte la base des taxes suivantes
- `analytic` (boolean, default false) — force la saisie analytique sur la ligne de taxe
- `fixed_amount` (numeric(14,2), nullable) — montant forfaitaire (si amount_type = 'fixed')

**SQL** :
```sql
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS price_include boolean DEFAULT false;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS include_base_amount boolean DEFAULT false;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS is_base_affected boolean DEFAULT true;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS analytic boolean DEFAULT false;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS fixed_amount numeric(14,2);
```

**Logique de calcul** (`src/lib/taxCalculator.ts` — nouveau fichier) :
```typescript
function calculateTax(baseAmount: number, tax: TaxRate): {
  taxAmount: number;
  newBase: number;
} {
  switch (tax.amount_type) {
    case 'percent':
      return { taxAmount: baseAmount * (tax.rate / 100), newBase: baseAmount };
    case 'fixed':
      return { taxAmount: tax.fixed_amount, newBase: baseAmount };
    case 'division':
      // Taxe incluse dans le prix TTC : taxAmount = TTC * rate / (100 + rate)
      return { taxAmount: baseAmount * (tax.rate / (100 + tax.rate)), newBase: baseAmount - (baseAmount * (tax.rate / (100 + tax.rate))) };
    case 'group':
      // Applique les taxes enfants en séquence
      return calculateGroupTax(baseAmount, tax);
  }
}
```

**UI** : `TaxRatesPage.tsx`
- Champ "Type de montant" : Pourcentage | Forfaitaire | Groupé | Par division
- Si forfaitaire → champ "Montant forfaitaire" (€)
- Checkbox "Incluse dans le prix" (price_include)
- Checkbox "Incluse dans la base des taxes suivantes" (include_base_amount)
- Checkbox "Affecte la base des taxes suivantes" (is_base_affected)
- Checkbox "Compte analytique requis" (analytic)

---

<a id="cluster-3"></a>
## CLUSTER 3 : Position Fiscale (#32, #56, #66)

### 3.1 Élément #32 — Position Fiscale (account.fiscal.position)
**Nouvelle table** : `fiscal_positions`
```sql
CREATE TABLE IF NOT EXISTS fiscal_positions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,              -- ex: "Export UE - Belgique"
  country_code text,               -- ex: 'BE'
  country_group_id text,           -- groupe de pays
  zip_from text,                   -- plage de code postal (pour les pays avec fédéralisme fiscal)
  zip_to text,
  auto_apply boolean DEFAULT false, -- application automatique selon le pays du tiers
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
```

### 3.2 Élément #56 — Mapping Fiscal par Pays
**Nouvelle table** : `fiscal_position_mappings`
```sql
CREATE TABLE IF NOT EXISTS fiscal_position_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_position_id uuid NOT NULL REFERENCES fiscal_positions(id) ON DELETE CASCADE,
  source_tax_id uuid REFERENCES tax_rates(id),     -- taxe d'origine (ex: TVA 20% FR)
  target_tax_id uuid REFERENCES tax_rates(id),     -- taxe de destination (ex: TVA 0% export)
  source_account_code text,                        -- compte d'origine
  target_account_code text,                        -- compte de destination
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fiscal_mapping_position ON fiscal_position_mappings(fiscal_position_id);
```

### 3.3 Élément #66 — Application Automatique sur Factures
**Logique** :
- Lors de la création d'une facture (client ou fournisseur) :
  1. Vérifier le pays du tiers
  2. Si `auto_apply` sur une position fiscale correspondante → appliquer
  3. Appliquer les mappings : remplacer les taxes et comptes selon les règles
  4. Afficher la position fiscale dans la facture

**Champs à ajouter sur les factures** :
```sql
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS fiscal_position_id uuid REFERENCES fiscal_positions(id);
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS fiscal_position_id uuid REFERENCES fiscal_positions(id);
```

**Nouvelle page UI** : `FiscalPositionsPage.tsx`
- Liste des positions fiscales (nom, pays, auto_apply, active)
- Fiche position fiscale : 2 onglets
  - **Onglet "Général"** : nom, pays, application auto, plage de code postal
  - **Onglet "Mappings"** : tableau des mappings taxe/compte (source → destination)
- Bouton "Tester" : sélectionne un tiers et montre quelle position fiscale s'applique

**Modification UI** :
- `InvoicesPage.tsx` : ajout champ "Position fiscale" dans l'en-tête de facture
- `PurchaseInvoicesPage.tsx` : idem
- `CustomersPage.tsx` : ajout champ "Position fiscale par défaut" sur le tiers
- `SuppliersPage.tsx` : idem

---

<a id="cluster-4"></a>
## CLUSTER 4 : Analytique Multi-Axes (#45, #46)

### 4.1 Élément #45 — Distribution Analytique Multi-Axes (JSON)
**Table** : `journal_lines`
**Champ à ajouter** :
- `analytic_distribution` (jsonb, nullable) — distribution multi-axes multi-plans

**Format JSON** (comme Odoo) :
```json
{
  "plan_1": {
    "section_5": 50,
    "section_6": 50
  },
  "plan_2": {
    "section_10": 100
  }
}
```

**SQL** :
```sql
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS analytic_distribution jsonb;
```

### 4.2 Élément #46 — Distribution Multi-Sections par Plan avec Pourcentages
**Nouvelle table** : `analytic_distribution_lines`
```sql
CREATE TABLE IF NOT EXISTS analytic_distribution_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  journal_line_id uuid REFERENCES journal_lines(id) ON DELETE CASCADE,
  plan_id uuid REFERENCES analytic_plans(id),
  section_id uuid REFERENCES analytic_sections(id),
  percentage numeric(5,2) NOT NULL,   -- ex: 50.00
  amount numeric(14,2),                -- montant calculé (line_amount * percentage / 100)
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_analytic_dist_line ON analytic_distribution_lines(journal_line_id);
```

**Nouveau composant** : `AnalyticDistributionEditor`
- Modal/panel qui s'ouvre depuis une ligne de saisie
- Pour chaque plan analytique : tableau des sections avec pourcentages
- Validation : la somme des pourcentages par plan doit = 100%
- Bouton "Répartir uniformément" (divise 100% par le nombre de sections)
- Bouton "Appliquer une grille" → utilise `DistributionGrill` existant

**Modification UI** :
- `JournalSaisiePage.tsx` : bouton "Analytique" sur chaque ligne → ouvre `AnalyticDistributionEditor`
- `SaisieParPiecePage.tsx` : idem
- `InvoicesPage.tsx` : sur les lignes de facture, bouton "Ventilation analytique"
- `PurchaseInvoicesPage.tsx` : idem

**Modification `AnalyticBalancePage.tsx`** :
- Prendre en compte `analytic_distribution` au lieu de `analytic_section_id` seul
- Afficher par plan, par section, avec les pourcentages

---

<a id="cluster-5"></a>
## CLUSTER 5 : Comptes Liés Immobilisation (#90, #91, #92)

### 5.1 Éléments #90, #91, #92 — Comptes Comptables Liés + Journal
**Table** : `fixed_assets`
**Champs à ajouter** :
- `account_asset_code` (text) — compte d'immobilisation (ex: 215000)
- `account_depreciation_code` (text) — compte d'amortissement cumulé (ex: 281500)
- `account_expense_depreciation_code` (text) — compte de dotation aux amortissements (ex: 681100)
- `journal_id` (uuid, nullable) — journal pour la génération auto des écritures (#93)
- `partner_id` (uuid, nullable) — tiers lié (fournisseur de l'immobilisation)
- `currency_code` (text, default 'EUR') — devise (#86)

**SQL** :
```sql
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS account_asset_code text;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS account_depreciation_code text;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS account_expense_depreciation_code text;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS journal_id uuid;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS partner_id uuid;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
```

**Logique métier** :
- Lors de la génération d'une écriture d'amortissement :
  1. Débit : `account_expense_depreciation_code` (681100)
  2. Crédit : `account_depreciation_code` (281500)
  3. Journal : `journal_id` de l'immobilisation
  4. Si devise étrangère : convertir avec le taux du jour

**UI** : `FixedAssetsPage.tsx`
- Onglet "Comptabilité" dans la fiche immobilisation (nouvel onglet)
- Champs : compte immobilisation, compte amortissement, compte dotation, journal, tiers, devise
- Bouton "Générer l'écriture d'amortissement" → crée l'écriture dans le journal lié
- Bouton "Générer toutes les écritures d'amortissement" (batch) pour toutes les immos de la période

---

<a id="cluster-6"></a>
## CLUSTER 6 : Multi-Contacts (#62)

### 6.1 Élément #62 — Contacts Enfants (adresses livraison/facturation)
**Nouvelle table** : `partner_contacts`
```sql
CREATE TABLE IF NOT EXISTS partner_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  partner_type text NOT NULL,        -- 'customer' | 'supplier'
  partner_id uuid NOT NULL,          -- ID du Customer ou Supplier
  contact_type text NOT NULL,        -- 'invoice' | 'delivery' | 'other' | 'primary'
  name text NOT NULL,
  email text,
  phone text,
  mobile text,
  function text,                     -- fonction (ex: "Directeur Achats")
  address text,
  postal_code text,
  city text,
  country text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_partner_contacts_partner ON partner_contacts(partner_type, partner_id);
```

**Nouvelle page UI** : `PartnerContactsModal.tsx`
- Modal accessible depuis `CustomersPage.tsx` et `SuppliersPage.tsx`
- Bouton "Contacts" sur chaque tiers → ouvre le modal
- Tableau des contacts : nom, type, email, téléphone, fonction, adresse
- CRUD complet des contacts
- Types : Facturation, Livraison, Autre, Principal
- Checkbox "Adresse par défaut" par type

**Modification UI** :
- `CustomersPage.tsx` : bouton "Contacts" (icône users) sur chaque ligne
- `SuppliersPage.tsx` : idem
- `InvoicesPage.tsx` : lors de la sélection d'un client, proposer le choix de l'adresse de facturation parmi ses contacts
- `PurchaseInvoicesPage.tsx` : idem pour l'adresse de livraison
- `SalesOrdersPage.tsx` : choix adresse de livraison
- `PurchaseOrdersPage.tsx` : idem

---

<a id="cluster-7"></a>
## CLUSTER 7 : Sync Bancaire API (#69)

### 7.1 Élément #69 — Connexion Bancaire Directe (API)
**Nouvelle table** : `bank_connections`
```sql
CREATE TABLE IF NOT EXISTS bank_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  provider text NOT NULL,            -- 'gocardless' | 'plaid' | 'saltedge' | 'manual'
  provider_connection_id text,       -- ID côté provider
  bank_account_id uuid REFERENCES bank_accounts(id),
  status text DEFAULT 'pending',     -- 'pending' | 'active' | 'error' | 'expired'
  last_sync_at timestamptz,
  sync_frequency text DEFAULT 'daily', -- 'hourly' | 'daily' | 'weekly' | 'manual'
  next_sync_at timestamptz,
  error_message text,
  metadata jsonb,                    -- données brutes du provider
  created_at timestamptz DEFAULT now()
);
```

**Nouvelle edge function** : `supabase/functions/bank-sync/index.ts`
- Connexion à l'API GoCardless (gratuit, open banking EU)
- Récupère les transactions depuis la dernière sync
- Insère dans `bank_transactions`
- Met à jour `last_sync_at` et `next_sync_at`
- Gestion des erreurs et retry

**Nouvelle page UI** : `BankSyncPage.tsx`
- **Onglet "Connexions"** :
  - Liste des connexions bancaires (banque, statut, dernière sync, prochaine sync)
  - Bouton "Connecter une banque" → redirige vers GoCardless auth flow
  - Bouton "Synchroniser maintenant" sur chaque connexion
  - Statut en temps réel (badge coloré : vert=actif, rouge=erreur, gris=en attente)
- **Onglet "Transactions"** :
  - Transactions récupérées automatiquement (non importées manuellement)
  - Filtre par compte bancaire, date, montant
  - Bouton "Réconcilier" → redirige vers `BankReconciliationPage.tsx`
- **Onglet "Paramètres"** :
  - Fréquence de synchronisation (horaire, quotidienne, hebdomadaire, manuelle)
  - Clé API GoCardless (stockée en secret Supabase)
  - Test de connexion

**Modification** :
- `BankingDashboardPage.tsx` : ajout d'une carte "Sync automatique" avec statut des connexions
- `BankReconciliationPage.tsx` : badge "Auto-synced" sur les transactions synchronisées
- `App.tsx` : ajout route `/bank-sync`

---

<a id="cluster-8"></a>
## CLUSTER 8 : Types de Comptes Précis (#1)

### 8.1 Élément #1 — Classification Fine des Comptes (17+ types)
**Table** : `chart_accounts`
**Champ à modifier** :
- `type` → ajouter un nouveau champ `account_type` (text) avec 19 valeurs précises

**Valeurs** (alignées sur Odoo + ajout français) :
```typescript
type AccountType =
  | 'asset_receivable'          // Créances clients
  | 'asset_cash'                // Banque et caisse
  | 'asset_current'             // Actifs courants
  | 'asset_non_current'         // Actifs non courants
  | 'asset_prepayments'         // Prépaiements (CCA)
  | 'asset_fixed'               // Immobilisations corporelles
  | 'liability_payable'         // Dettes fournisseurs
  | 'liability_credit_card'     // Cartes de crédit
  | 'liability_current'         // Passifs courants
  | 'liability_non_current'     // Passifs non courants (emprunts)
  | 'equity'                    // Capitaux propres
  | 'equity_unaffected'         // Résultat de l'exercice
  | 'income'                    // Revenus (ventes)
  | 'income_other'              // Autres revenus
  | 'expense'                   // Dépenses (achats)
  | 'expense_other'             // Autres dépenses
  | 'expense_depreciation'      // Amortissements
  | 'expense_direct_cost'       // Coût des ventes (COGS)
  | 'off_balance';              // Hors bilan
```

**SQL** :
```sql
ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS account_type text;
-- Migration : mapper les anciens types vers les nouveaux
UPDATE chart_accounts SET account_type = CASE
  WHEN type = 'asset' AND code LIKE '41%' THEN 'asset_receivable'
  WHEN type = 'asset' AND code LIKE '51%' THEN 'asset_cash'
  WHEN type = 'asset' AND code LIKE '53%' THEN 'asset_cash'
  WHEN type = 'asset' AND code LIKE '2%' THEN 'asset_fixed'
  WHEN type = 'asset' THEN 'asset_current'
  WHEN type = 'liability' AND code LIKE '40%' THEN 'liability_payable'
  WHEN type = 'liability' AND code LIKE '1%' THEN 'liability_non_current'
  WHEN type = 'liability' THEN 'liability_current'
  WHEN type = 'equity' THEN 'equity'
  WHEN type = 'income' THEN 'income'
  WHEN type = 'expense' AND code LIKE '68%' THEN 'expense_depreciation'
  WHEN type = 'expense' THEN 'expense'
  ELSE 'asset_current'
END;
```

**UI** : `ChartAccountsPage.tsx`
- Remplacer le dropdown de type (5 valeurs) par le nouveau (19 valeurs)
- Grouper les options par catégorie : Actifs, Passifs, Capitaux, Revenus, Dépenses, Hors bilan
- Filtre par `account_type` dans la liste
- Colonne "Type précis" dans la liste
- Utiliser `account_type` pour générer automatiquement le Bilan et le P&L

**Modification** :
- `BalanceSheetPage.tsx` : utiliser `account_type` pour classer automatiquement (actif/passif)
- `ReportsPage.tsx` : filtrer par type précis
- `TrialBalancePage.tsx` : filtre par type précis

---

<a id="cluster-9"></a>
## CLUSTER 9 : Multi-Devises Étendu (#5, #9, #86, #87, #89)

### 9.1 Élément #5 — Devise sur Factures
**Tables** : `invoices`, `purchase_invoices`, `credit_notes`, `purchase_credit_notes`
**Champs** :
```sql
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_untaxed_currency numeric(14,2);
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_tax_currency numeric(14,2);
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_total_currency numeric(14,2);

-- Idem pour purchase_invoices, credit_notes, purchase_credit_notes
```

**UI** :
- `InvoicesPage.tsx` : devise + taux dans l'en-tête, montants en devise + en EUR
- `PurchaseInvoicesPage.tsx` : idem
- Lignes de facture : `price_unit_currency`, `price_subtotal_currency`, `price_total_currency`

### 9.2 Élément #9 — Écarts de Change sur Règlements
**Nouvelle table** : `exchange_gain_loss_entries`
```sql
CREATE TABLE IF NOT EXISTS exchange_gain_loss_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  payment_id uuid,                  -- paiement qui déclenche l'écart
  invoice_id uuid,                  -- facture concernée
  type text NOT NULL,               -- 'gain' | 'loss'
  amount numeric(14,2),
  exchange_rate_original numeric(12,6),
  exchange_rate_payment numeric(12,6),
  account_gain_code text,           -- compte de gain de change (766000)
  account_loss_code text,           -- compte de perte de change (666000)
  journal_entry_id uuid,            -- écriture comptable générée
  created_at timestamptz DEFAULT now()
);
```

**Logique** :
- Lors du paiement d'une facture en devise étrangère :
  1. Comparer le taux de la facture avec le taux du paiement
  2. Si taux différent → calculer l'écart de change
  3. Générer une écriture : gain (766000) ou perte (666000)

**UI** :
- `CustomerPaymentsPage.tsx` : afficher l'écart de change calculé
- `SupplierPaymentsPage.tsx` : idem
- Nouvelle page `ExchangeGainLossPage.tsx` : liste des écarts de change par période

### 9.3 Élément #86 — Devise sur Immobilisation
Déjà couvert dans Cluster 5 (champ `currency_code` sur `fixed_assets`).

### 9.4 Élément #87 — Devise sur Tiers (déjà présent mais en string)
**Tables** : `customers`, `suppliers`
- Le champ `currency` (string) existe déjà
- Ajouter `currency_code` (text, default 'EUR') pour normaliser avec le reste
- Migration : copier `currency` → `currency_code`

### 9.5 Élément #89 — Actualisation des Taux à l'Ouverture et en Saisie
**Logique** :
- Au chargement de l'application → récupérer les derniers taux via `currencyRates.ts`
- En saisie d'écriture → si devise ≠ EUR, auto-remplir le taux avec le dernier connu
- Bouton "Actualiser" dans tous les formulaires qui ont un taux de change
- Alerte si le taux est vieux de plus de 7 jours

**Composant** : `CurrencyRateDisplay`
- Affiche la paire de devises + le taux + la date du taux
- Bouton refresh
- Couleur : vert si récent (< 1 jour), orange si < 7 jours, rouge si > 7 jours

---

<a id="cluster-10"></a>
## CLUSTER 10 : Taxes Intermédiaires (#12, #13, #14, #19, #22, #23, #24)

### 10.1 Éléments #12, #13, #14, #19, #23, #24 — Champs sur TaxRate
Déjà couverts dans Cluster 2 (champs `sequence`, `price_include`, `include_base_amount`, `type_tax_use`, `analytic`, `is_base_affected`).

### 10.2 Élément #22 — Tags Fiscaux
**Nouvelle table** : `account_tags`
```sql
CREATE TABLE IF NOT EXISTS account_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,               -- ex: "TVA collectée 20%"
  applicability text NOT NULL,      -- 'accounts' | 'taxes' | 'operations'
  color text,                       -- couleur pour l'affichage
  country_code text,                -- ex: 'FR'
  created_at timestamptz DEFAULT now()
);
```

**Nouvelle table** : `account_tag_mappings` (many2many)
```sql
CREATE TABLE IF NOT EXISTS account_tag_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES account_tags(id) ON DELETE CASCADE,
  entity_type text NOT NULL,        -- 'account' | 'tax' | 'journal_line'
  entity_id text NOT NULL,          -- code du compte, ID de la taxe, ID de la ligne
  created_at timestamptz DEFAULT now()
);
```

**Nouvelle page UI** : `AccountTagsPage.tsx`
- Liste des tags (nom, applicabilité, couleur, pays)
- CRUD complet
- Onglet "Application" : associer des tags à des comptes ou des taxes en masse

**Modification** :
- `ChartAccountsPage.tsx` : onglet "Tags" dans la fiche compte, afficher les tags associés
- `TaxRatesPage.tsx` : afficher les tags fiscaux sur chaque taxe
- `JournalSaisiePage.tsx` : colonne "Tags fiscaux" optionnelle

---

<a id="cluster-11"></a>
## CLUSTER 11 : Écritures (#30, #34, #39, #40, #42, #47)

### 11.1 Élément #30 — Montant Résiduel sur Lignes
**Table** : `journal_lines`
```sql
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS amount_residual numeric(14,2) DEFAULT 0;
```
- Calculé : `amount_residual = debit - credit - montant_réconcilié`
- Mis à jour lors du lettrage / paiement

### 11.2 Élément #34 — Annulation/Extourne Automatique
**Nouvelle table** : `extourne_log` (déjà existe dans `25_sage100_accounting_features.sql`)
- Vérifier que la table existe et est utilisée
- **Nouvelle page** : `ExtournePage.tsx`
  - Sélection d'une écriture à extourner
  - Génération de l'écriture d'extourne (inverse : débit↔crédit)
  - Lien entre l'écriture originale et l'extourne
  - Bouton "Extourner" sur `JournalEntriesPage.tsx`

### 11.3 Élément #39 — Tags Fiscaux sur Lignes d'Écriture
**Table** : `journal_lines`
```sql
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS tax_tag_ids text[] DEFAULT '{}';
```
- Permet de taguer des lignes pour la déclaration fiscale
- UI : multi-select de tags dans la grille de saisie (colonne optionnelle)

### 11.4 Élément #40 — Produit sur Ligne d'Écriture
**Table** : `journal_lines`
```sql
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS product_id uuid;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS product_uom text;
```
- Lien vers le catalogue produit (pour les écritures générées depuis factures)
- UI : colonne "Produit" optionnelle dans la grille de saisie

### 11.5 Élément #42 — Pourcentage Analytique sur Ligne
Déjà couvert dans Cluster 4 (`analytic_distribution` JSON + `analytic_distribution_lines`).

### 11.6 Élément #47 — Restant Dû sur Factures (payment_state)
**Tables** : `invoices`, `purchase_invoices`
```sql
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_state text DEFAULT 'not_paid';
-- Valeurs: 'not_paid' | 'in_payment' | 'paid' | 'partial'
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS payment_state text DEFAULT 'not_paid';
```
- Mis à jour automatiquement lors d'un paiement
- UI : badge de statut de paiement dans la liste des factures

---

<a id="cluster-12"></a>
## CLUSTER 12 : Tiers (#63, #64, #65)

### 12.1 Élément #63 — Hiérarchie Groupe (parent_id + is_company)
**Tables** : `customers`, `suppliers`
```sql
ALTER TABLE customers ADD COLUMN IF NOT EXISTS parent_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS is_company boolean DEFAULT true;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS parent_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS is_company boolean DEFAULT true;
```

**UI** :
- `CustomersPage.tsx` : champ "Société parent" (dropdown des autres clients)
- Affichage en arbre (vue hiérarchique optionnelle)
- Checkbox "Société" vs "Individu"

### 12.2 Élément #64 — Catégories/Tags de Tiers
**Nouvelle table** : `partner_categories`
```sql
CREATE TABLE IF NOT EXISTS partner_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,               -- ex: "Grand compte", "PME", "Export"
  color text,
  parent_id uuid,                   -- hiérarchie de catégories
  created_at timestamptz DEFAULT now()
);
```

**Nouvelle table** : `partner_category_mappings`
```sql
CREATE TABLE IF NOT EXISTS partner_category_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES partner_categories(id) ON DELETE CASCADE,
  partner_type text NOT NULL,       -- 'customer' | 'supplier'
  partner_id uuid NOT NULL,
  created_at timestamptz DEFAULT now()
);
```

**Nouvelle page UI** : `PartnerCategoriesPage.tsx`
- CRUD des catégories (nom, couleur, parent)
- Association en masse de tiers à des catégories

**Modification** :
- `CustomersPage.tsx` : filtre par catégorie, tags colorés dans la liste
- `SuppliersPage.tsx` : idem

### 12.3 Élément #65 — Commercial Assigné
**Tables** : `customers`, `suppliers`
```sql
ALTER TABLE customers ADD COLUMN IF NOT EXISTS sales_rep_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS sales_rep_id uuid;
```
- Lien vers `tenant_users` (utilisateur du tenant)
- UI : dropdown "Commercial assigné" dans la fiche tiers
- Filtre par commercial dans la liste des tiers

---

<a id="cluster-13"></a>
## CLUSTER 13 : Banque (#70, #72, #80)

### 13.1 Élément #70 — Soldes Relevé
**Table** : `bank_accounts`
```sql
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS statement_balance numeric(14,2) DEFAULT 0;
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS statement_balance_date date;
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS calculated_balance numeric(14,2) DEFAULT 0;
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS reconciliation_diff numeric(14,2) DEFAULT 0;
```
- `statement_balance` : solde du dernier relevé importé
- `calculated_balance` : solde calculé depuis les écritures
- `reconciliation_diff` : écart entre relevé et calculé

**UI** :
- `BankAccountsPage.tsx` : afficher les 3 soldes (relevé, calculé, écart)
- Badge rouge si écart ≠ 0

### 13.2 Élément #72 — Multi-Devises Rapprochement
- `BankReconciliationPage.tsx` : prise en compte de la devise du compte bancaire
- Si compte en devise étrangère : afficher les montants en devise + en EUR
- Calcul des écarts de change lors du rapprochement

### 13.3 Élément #80 — Banque Tiers (res.partner.bank)
**Nouvelle table** : `partner_bank_accounts`
```sql
CREATE TABLE IF NOT EXISTS partner_bank_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  partner_type text NOT NULL,       -- 'customer' | 'supplier'
  partner_id uuid NOT NULL,
  account_number text NOT NULL,     -- IBAN ou RIB
  bank_name text,
  bic text,                         -- SWIFT/BIC
  bank_code text,
  sort_code text,                   -- code guichet
  account_key text,                 -- clé RIB
  currency_code text DEFAULT 'EUR',
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
```

**UI** :
- `PartnerContactsModal.tsx` → onglet "Comptes bancaires"
- CRUD des RIB/IBAN par tiers
- Validation IBAN (checksum)
- Sélection du compte bancaire lors d'un paiement

---

<a id="cluster-14"></a>
## CLUSTER 14 : Immobilisation + Chéquier (#93, #82)

### 14.1 Élément #93 — Journal Lié Immobilisation
Déjà couvert dans Cluster 5 (champ `journal_id` sur `fixed_assets`).

### 14.2 Élément #82 — Suivi des Chèques
**Nouvelle table** : `check_books`
```sql
CREATE TABLE IF NOT EXISTS check_books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  bank_account_id uuid REFERENCES bank_accounts(id),
  journal_id uuid,
  name text NOT NULL,               -- ex: "Chéquier n°3"
  first_check_number text NOT NULL,
  last_check_number text NOT NULL,
  next_check_number text NOT NULL,
  status text DEFAULT 'active',     -- 'active' | 'exhausted' | 'cancelled'
  issued_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);
```

**Nouvelle table** : `checks`
```sql
CREATE TABLE IF NOT EXISTS checks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  check_book_id uuid REFERENCES check_books(id),
  check_number text NOT NULL,
  amount numeric(14,2) NOT NULL,
  payee text NOT NULL,              -- bénéficiaire
  issue_date date NOT NULL,
  due_date date,                    -- date d'encaissement prévue
  status text DEFAULT 'draft',      -- 'draft' | 'issued' | 'cashed' | 'cancelled' | 'lost'
  journal_entry_id uuid,            -- écriture comptable générée
  payment_id uuid,                  -- paiement lié
  notes text,
  created_at timestamptz DEFAULT now()
);
```

**Nouvelle page UI** : `CheckBooksPage.tsx`
- **Onglet "Chéquiers"** :
  - Liste des chéquiers (nom, banque, n° premier/dernier chèque, statut)
  - Bouton "Nouveau chéquier" (saisie plage de numéros)
  - Statut : actif / épuisé / annulé
- **Onglet "Chèques"** :
  - Tableau des chèques (n°, montant, bénéficiaire, date, statut)
  - Bouton "Émettre un chèque" (sélectionne le prochain n° disponible)
  - Bouton "Encaissé" (marque le chèque comme encaissé → génère l'écriture)
  - Bouton "Annuler"
  - Filtres : par chéquier, par statut, par date
- **Onglet "Impression"** :
  - Aperçu du chèque (format normalisé français)
  - Bouton "Imprimer" (génère un PDF)

---

## ORDRE D'IMPLÉMENTATION RECOMMANDÉ

### Sprint 1 (Semaines 1-2) : Fondations
1. **#1** Types de comptes précis (Cluster 8) — impact sur tous les rapports
2. **#88** Taux de change auto + table `exchange_rates` (Cluster 1) — fondation multi-devises
3. **#57** Devise sur journaux (Cluster 1) — simple ALTER + UI

### Sprint 2 (Semaines 3-4) : Multi-Devises Core
4. **#33** Devise sur écritures (Cluster 1) — le plus complexe
5. **#79** Devise sur comptes (Cluster 1) — simple ALTER + UI
6. **#85** Devise sur paiements (Cluster 1) — avec écarts de change

### Sprint 3 (Semaines 5-6) : Moteur Taxes
7. **#21** Taxes forfaitaires/division + champs avancés (Cluster 2)
8. **#11** Taxes groupées (Cluster 2)
9. **#18** Répartition par compte (Cluster 2)
10. **#20** TVA sur encaissement + compte de transition (Cluster 2)

### Sprint 4 (Semaines 7-8) : Position Fiscale + Tags
11. **#32, #56, #66** Position fiscale complète (Cluster 3)
12. **#22** Tags fiscaux (Cluster 10)

### Sprint 5 (Semaines 9-10) : Analytique + Écritures
13. **#45, #46** Distribution multi-axes (Cluster 4)
14. **#30, #34, #39, #40, #42, #47** Écritures (Cluster 11)

### Sprint 6 (Semaines 11-12) : Tiers + Immobilisation
15. **#62** Multi-contacts (Cluster 6)
16. **#63, #64, #65** Hiérarchie + catégories + commercial (Cluster 12)
17. **#90, #91, #92, #93** Comptes liés + journal immobilisation (Cluster 5)

### Sprint 7 (Semaines 13-14) : Banque
18. **#69** Sync bancaire API (Cluster 7)
19. **#70, #72, #80** Soldes relevé + multi-devises + banque tiers (Cluster 13)

### Sprint 8 (Semaines 15-16) : Finalisation
20. **#5, #9, #86, #87, #89** Multi-devises étendu (Cluster 9)
21. **#82** Chéquier (Cluster 14)
22. **#12, #13, #14, #19, #23, #24** Taxes intermédiaires (Cluster 10) — déjà implémentés dans Sprint 3

---

## INVENTAIRE DES NOUVEAUX FICHIERS

### SQL (migrations)
| Fichier | Contenu |
|---------|---------|
| `sql/39_multi_currency.sql` | Tables + ALTER multi-devises (Clusters 1, 9) |
| `sql/40_advanced_taxes.sql` | Taxes groupées, répartition, cash basis, tags (Clusters 2, 10) |
| `sql/41_fiscal_positions.sql` | Positions fiscales + mappings (Cluster 3) |
| `sql/42_analytic_multi_axes.sql` | Distribution multi-axes (Cluster 4) |
| `sql/43_asset_accounts.sql` | Comptes liés immobilisation (Cluster 5) |
| `sql/44_partner_contacts.sql` | Contacts enfants + banque tiers (Clusters 6, 13) |
| `sql/45_bank_sync.sql` | Connexions bancaires API (Cluster 7) |
| `sql/46_account_types.sql` | Types de comptes précis (Cluster 8) |
| `sql/47_writings_enhancements.sql` | Écritures : residual, extourne, tags, produit (Cluster 11) |
| `sql/48_partner_hierarchy.sql` | Hiérarchie + catégories + commercial (Cluster 12) |
| `sql/49_check_books.sql` | Chéquiers + chèques (Cluster 14) |

### Pages TSX (nouvelles)
| Page | Cluster | Description |
|------|---------|-------------|
| `ExchangeRatesPage.tsx` | 1 | Taux de change + graphique + actualisation |
| `BankSyncPage.tsx` | 7 | Connexions bancaires API + sync auto |
| `FiscalPositionsPage.tsx` | 3 | Positions fiscales + mappings |
| `AccountTagsPage.tsx` | 10 | Tags fiscaux CRUD + application |
| `PartnerCategoriesPage.tsx` | 12 | Catégories de tiers CRUD |
| `PartnerContactsModal.tsx` | 6 | Modal contacts enfants |
| `PartnerBankAccountsModal.tsx` | 13 | Modal comptes bancaires tiers |
| `ExtournePage.tsx` | 11 | Extourne automatique |
| `ExchangeGainLossPage.tsx` | 9 | Écarts de change |
| `CheckBooksPage.tsx` | 14 | Chéquiers + chèques + impression |

### Composants réutilisables
| Composant | Description |
|-----------|-------------|
| `CurrencySelector` | Dropdown devise avec drapeaux + code ISO |
| `CurrencyRatePicker` | Sélection paire + date → taux auto |
| `CurrencyRateDisplay` | Affichage taux + date + bouton refresh |
| `AnalyticDistributionEditor` | Modal distribution multi-axes multi-plans |
| `FiscalPositionSelector` | Dropdown position fiscale sur factures |
| `PartnerContactSelector` | Sélection adresse parmi contacts du tiers |

### Librairies (src/lib/)
| Fichier | Description |
|---------|-------------|
| `currencyRates.ts` | Récupération taux, conversion, formatage |
| `taxCalculator.ts` | Calcul taxes (percent, fixed, group, division) |
| `fiscalPositionMapper.ts` | Application mappings fiscaux sur factures |
| `exchangeGainLoss.ts` | Calcul écarts de change sur paiements |
| `ibanValidator.ts` | Validation IBAN (checksum + format) |
| `checkPrinter.ts` | Génération PDF chèques (format français) |

### Edge Functions
| Fonction | Description |
|----------|-------------|
| `fetch-exchange-rates` | Récupération taux ECB + stockage |
| `bank-sync` | Sync transactions bancaires via GoCardless |

### Modifications de pages existantes
| Page | Modifications |
|------|---------------|
| `ChartAccountsPage.tsx` | Types précis, devise, reconcile, deprecated, tags |
| `JournalsPage.tsx` | Devise, séquence d'affichage |
| `TaxRatesPage.tsx` | Amount_type, taxes groupées, répartition, cash basis, price_include |
| `JournalSaisiePage.tsx` | Devise, taux, montant devise, distribution analytique multi-axes, tags fiscaux, produit |
| `SaisieParPiecePage.tsx` | Devise, taux, distribution analytique |
| `InvoicesPage.tsx` | Devise, taux, position fiscale, payment_state, montants devise |
| `PurchaseInvoicesPage.tsx` | Devise, taux, position fiscale, payment_state |
| `CustomerPaymentsPage.tsx` | Devise, taux, écart de change |
| `SupplierPaymentsPage.tsx` | Devise, taux, écart de change |
| `CustomersPage.tsx` | Contacts, parent_id, is_company, catégories, commercial |
| `SuppliersPage.tsx` | Contacts, parent_id, is_company, catégories, commercial |
| `FixedAssetsPage.tsx` | Comptes liés, journal, tiers, devise, génération auto |
| `BankReconciliationPage.tsx` | Multi-devises, soldes relevé |
| `BankAccountsPage.tsx` | Soldes relevé, calculé, écart |
| `BankingDashboardPage.tsx` | Carte sync auto |
| `BalanceSheetPage.tsx` | Utiliser account_type pour classification |
| `TrialBalancePage.tsx` | Filtre par type précis |
| `ReportsPage.tsx` | Filtre par type précis |
| `AnalyticBalancePage.tsx` | Prendre en compte distribution JSON |
| `JournalEntriesPage.tsx` | Bouton extourne |
| `PaymentGenerationPage.tsx` | Devise du tiers |
| `PaymentOrdersPage.tsx` | Devise sur ordre |
| `App.tsx` | Nouvelles routes |

---

## ESTIMATION

| Sprint | Durée | Éléments | Nouvelles tables | Nouvelles pages | Modifications pages |
|--------|-------|----------|-----------------|----------------|-------------------|
| 1 | 2 sem | 3 | 1 | 1 | 3 |
| 2 | 2 sem | 3 | 0 | 0 | 4 |
| 3 | 2 sem | 4 | 2 | 0 | 2 |
| 4 | 2 sem | 3 | 2 | 2 | 3 |
| 5 | 2 sem | 8 | 1 | 1 | 4 |
| 6 | 2 sem | 7 | 2 | 2 | 3 |
| 7 | 2 sem | 4 | 1 | 1 | 3 |
| 8 | 2 sem | 10 | 1 | 1 | 2 |
| **Total** | **16 sem** | **42** | **10** | **8** | **24** |

---

## DÉPENDANCES ENTRE CLUSTERS

```
Cluster 8 (Types comptes) ──→ Cluster 1 (Multi-devises) ──→ Cluster 9 (Devises étendu)
                                    │
                                    ├──→ Cluster 11 (Écritures) ──→ Cluster 4 (Analytique)
                                    │
                                    └──→ Cluster 5 (Immobilisation) ──→ Cluster 14 (Chéquier)

Cluster 2 (Taxes avancé) ──→ Cluster 3 (Position fiscale) ──→ Cluster 10 (Tags fiscaux)

Cluster 6 (Multi-contacts) ──→ Cluster 12 (Tiers) ──→ Cluster 13 (Banque) ──→ Cluster 7 (Sync API)
```

> **Fin du plan d'implémentation — 42 éléments en 8 sprints sur 16 semaines**
