# PARTIE 5 — Sprints H, I, J & K : POS, Dématérialisation, Pilotage, i18n (12-15j)

> **Sprint H** (4-5j) : Écran de vente, caisses, sessions, tickets, statistiques, certification légale
> **Sprint I** (3j) : Factur-X, signature électronique, paiement en ligne, partage documents
> **Sprint J** (3j) : Simulation CA, analyse marges, listes avancées avec filtres sauvegardables
> **Sprint K** (2j) : i18n — namespaces commercial.json, crm.json, pos.json (fr/en/ar)
> **i18n** : `useTranslation` (fr, en, ar)
> **SQL** : `app/sql/54_sprint_h_pos.sql` + `app/sql/55_sprint_i_dematerialisation.sql` + `app/sql/56_sprint_j_pilotage.sql`

---

# SPRINT H : POS / Saisie de Caisse (4-5j)

## H.1 SQL — Nouvelles tables

### `pos_terminals` (caisses)
```sql
CREATE TABLE IF NOT EXISTS pos_terminals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,                  -- "Caisse 1", "Caisse Boutique"
  warehouse_id uuid REFERENCES warehouses(id) ON DELETE SET NULL,
  location text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE pos_terminals ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pos_terminals') THEN
    CREATE POLICY "allow_all_pos_terminals" ON pos_terminals FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `pos_sessions` (sessions de caisse)
```sql
CREATE TABLE IF NOT EXISTS pos_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  terminal_id uuid NOT NULL REFERENCES pos_terminals(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  opening_amount numeric(15,2) DEFAULT 0,
  closing_amount numeric(15,2),
  expected_amount numeric(15,2),
  difference numeric(15,2),
  status text DEFAULT 'open',         -- 'open'|'closed'
  opened_at timestamptz DEFAULT now(),
  closed_at timestamptz,
  notes text
);
CREATE INDEX IF NOT EXISTS idx_ps_terminal ON pos_sessions(terminal_id);
CREATE INDEX IF NOT EXISTS idx_ps_status ON pos_sessions(status);
ALTER TABLE pos_sessions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pos_sessions') THEN
    CREATE POLICY "allow_all_pos_sessions" ON pos_sessions FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `pos_tickets` (tickets de caisse)
```sql
CREATE TABLE IF NOT EXISTS pos_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  session_id uuid NOT NULL REFERENCES pos_sessions(id) ON DELETE CASCADE,
  terminal_id uuid NOT NULL REFERENCES pos_terminals(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  date timestamptz DEFAULT now(),
  subtotal numeric(15,2) DEFAULT 0,
  vat_total numeric(15,2) DEFAULT 0,
  total numeric(15,2) DEFAULT 0,
  payment_method text,                -- 'cash'|'card'|'check'|'transfer'|'mixed'
  amount_paid numeric(15,2) DEFAULT 0,
  change_given numeric(15,2) DEFAULT 0,
  status text DEFAULT 'completed',    -- 'completed'|'cancelled'|'refunded'
  invoice_id uuid,                    -- lien vers facture si générée
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pt_session ON pos_tickets(session_id);
CREATE INDEX IF NOT EXISTS idx_pt_date ON pos_tickets(date);
ALTER TABLE pos_tickets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pos_tickets') THEN
    CREATE POLICY "allow_all_pos_tickets" ON pos_tickets FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS pos_ticket_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  ticket_id uuid NOT NULL REFERENCES pos_tickets(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  description text NOT NULL,
  quantity numeric(15,2) NOT NULL DEFAULT 1,
  unit_price numeric(15,2) NOT NULL,
  vat_rate numeric(5,2) DEFAULT 0,
  line_total numeric(15,2) NOT NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ptl_ticket ON pos_ticket_lines(ticket_id);
ALTER TABLE pos_ticket_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pos_ticket_lines') THEN
    CREATE POLICY "allow_all_pos_ticket_lines" ON pos_ticket_lines FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## H.2 Types TypeScript

```typescript
export interface PosTerminal {
  id: string
  name: string
  warehouse_id: string | null
  location: string | null
  active: boolean
}

export interface PosSession {
  id: string
  terminal_id: string
  user_email: string
  opening_amount: number
  closing_amount: number | null
  expected_amount: number | null
  difference: number | null
  status: 'open'|'closed'
  opened_at: string
  closed_at: string | null
  notes: string | null
}

export interface PosTicket {
  id: string
  number: string
  session_id: string
  terminal_id: string
  customer_id: string | null
  date: string
  subtotal: number
  vat_total: number
  total: number
  payment_method: 'cash'|'card'|'check'|'transfer'|'mixed' | null
  amount_paid: number
  change_given: number
  status: 'completed'|'cancelled'|'refunded'
  invoice_id: string | null
  notes: string | null
  pos_ticket_lines?: PosTicketLine[]
}

export interface PosTicketLine {
  id: string
  ticket_id: string
  product_id: string | null
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  line_total: number
}
```

## H.3 Queries

| Fonction | Description |
|---|---|
| `getPosTerminals()` | Liste des caisses |
| `createPosTerminal(terminal)` | Crée une caisse |
| `openPosSession(terminalId, openingAmount)` | Ouvre une session |
| `closePosSession(sessionId, closingAmount)` | Ferme une session + calcule écart |
| `getActiveSession(terminalId)` | Session ouverte pour une caisse |
| `createPosTicket(ticket)` | Crée un ticket + lignes |
| `getPosTickets(sessionId?, date?)` | Liste des tickets |
| `cancelPosTicket(id)` | Annule un ticket |
| `convertTicketToInvoice(ticketId)` | Génère une facture depuis le ticket |
| `getPosStats(sessionId)` | Stats caisse : nb tickets, total, par moyen de paiement |

## H.4 Nouvelles pages

### `PosTerminalPage.tsx` (écran de vente)
**Fichier** : `app/src/pages/pos/PosTerminalPage.tsx`
**Route** : `/pos/terminal/:terminalId`

- **Sélection caisse** si non spécifiée
- **Ouverture de session** : montant de fond de caisse
- **Écran de vente** (split 2 colonnes) :
  - **Gauche** : grille de produits (catégories + recherche + scan code-barres)
  - **Droite** : panier (lignes, quantités, sous-total, TVA, total)
- **Paiement** : modal (montant reçu, méthode, rendu monnaie)
- **Impression ticket** : génération PDF ticket
- **Fermeture de session** : montant de clôture + écart
- `useTranslation('pos')`

### `PosSessionsPage.tsx` (historique sessions)
**Fichier** : `app/src/pages/pos/PosSessionsPage.tsx`
**Route** : `/pos/sessions`

- Liste des sessions avec filtres (caisse, date, statut)
- Détail : tickets de la session, total, écart
- `useTranslation('pos')`

### `PosStatsPage.tsx` (statistiques)
**Fichier** : `app/src/pages/pos/PosStatsPage.tsx`
**Route** : `/pos/stats`

- CA par jour/semaine/mois
- CA par caisse
- CA par moyen de paiement
- Top produits vendus
- Heures de pointe
- `useTranslation('pos')`

## H.5 i18n — Nouveau namespace `pos`

**Fichiers** : `app/src/i18n/locales/{fr,en,ar}/pos.json`

| Section | Clés |
|---|---|
| `terminal.*` | title, selectTerminal, openSession, closeSession, openingAmount, closingAmount, expectedAmount, difference, noActiveSession |
| `sale.*` | title, searchProduct, scanBarcode, categories, cart, subtotal, vat, total, payment, paymentMethod, cash, card, check, transfer, mixed, amountReceived, change, pay, cancel, printTicket |
| `sessions.*` | title, terminal, user, openedAt, closedAt, status, open, closed, difference, viewTickets |
| `stats.*` | title, revenueByDay, revenueByTerminal, byPaymentMethod, topProducts, peakHours |

## H.6 Routes

```tsx
<Route path="/pos/terminal" element={<PosTerminalPage />} />
<Route path="/pos/terminal/:terminalId" element={<PosTerminalPage />} />
<Route path="/pos/sessions" element={<PosSessionsPage />} />
<Route path="/pos/stats" element={<PosStatsPage />} />
```

---

# SPRINT I : Dématérialisation (3j)

## I.1 SQL — Nouvelles tables

### `electronic_signatures`
```sql
CREATE TABLE IF NOT EXISTS electronic_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  document_type text NOT NULL,         -- 'invoice'|'quote'|'order'|'delivery_note'|'credit_note'
  document_id uuid NOT NULL,
  signer_name text NOT NULL,
  signer_email text,
  signature_hash text,                 -- hash du document signé
  signature_data text,                 -- base64 ou URL de la signature
  ip_address text,
  signed_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_es_doc ON electronic_signatures(document_type, document_id);
ALTER TABLE electronic_signatures ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_electronic_signatures') THEN
    CREATE POLICY "allow_all_electronic_signatures" ON electronic_signatures FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `online_payments`
```sql
CREATE TABLE IF NOT EXISTS online_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  invoice_id uuid REFERENCES invoices(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  payment_provider text,               -- 'stripe'|'paypal'|'paystack'|'other'
  provider_transaction_id text,
  amount numeric(15,2) NOT NULL,
  currency_code text DEFAULT 'EUR',
  status text DEFAULT 'pending',       -- 'pending'|'completed'|'failed'|'refunded'
  payment_url text,                    -- URL de paiement envoyée au client
  paid_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_op_invoice ON online_payments(invoice_id);
ALTER TABLE online_payments ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_online_payments') THEN
    CREATE POLICY "allow_all_online_payments" ON online_payments FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `document_shares` (partage de documents)
```sql
CREATE TABLE IF NOT EXISTS document_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  document_type text NOT NULL,
  document_id uuid NOT NULL,
  shared_with_email text NOT NULL,
  share_token text NOT NULL,           -- token unique pour accès sans login
  share_url text,                      -- URL complète
  expires_at timestamptz,
  viewed boolean DEFAULT false,
  viewed_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ds_token ON document_shares(share_token);
ALTER TABLE document_shares ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_document_shares') THEN
    CREATE POLICY "allow_all_document_shares" ON document_shares FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## I.2 Types TypeScript

```typescript
export interface ElectronicSignature {
  id: string
  document_type: string
  document_id: string
  signer_name: string
  signer_email: string | null
  signature_hash: string | null
  signature_data: string | null
  ip_address: string | null
  signed_at: string
}

export interface OnlinePayment {
  id: string
  invoice_id: string | null
  customer_id: string | null
  payment_provider: 'stripe'|'paypal'|'paystack'|'other' | null
  provider_transaction_id: string | null
  amount: number
  currency_code: string
  status: 'pending'|'completed'|'failed'|'refunded'
  payment_url: string | null
  paid_at: string | null
  created_at: string
}

export interface DocumentShare {
  id: string
  document_type: string
  document_id: string
  shared_with_email: string
  share_token: string
  share_url: string | null
  expires_at: string | null
  viewed: boolean
  viewed_at: string | null
  created_at: string
}
```

## I.3 Queries

| Fonction | Description |
|---|---|
| `signDocument(docType, docId, signerName, signerEmail)` | Signe électroniquement un document |
| `getSignatures(docType, docId)` | Récupère les signatures d'un document |
| `createOnlinePayment(invoiceId, amount, provider)` | Crée un paiement en ligne (génère URL) |
| `getOnlinePaymentByToken(token)` | Récupère un paiement par token |
| `updateOnlinePaymentStatus(id, status)` | Met à jour le statut (callback provider) |
| `shareDocument(docType, docId, email, expiresIn?)` | Crée un lien de partage sécurisé |
| `getDocumentShare(token)` | Accès au document partagé (sans login) |
| `generateFacturX(invoiceId)` | Génère le PDF Factur-X (XML + PDF embarqué) |

## I.4 Nouvelles pages

### `OnlinePaymentPage.tsx` (page publique de paiement)
**Fichier** : `app/src/pages/pos/OnlinePaymentPage.tsx`
**Route** : `/pay/:token`

- Page publique (sans login admin)
- Affiche : numéro facture, montant, client
- Bouton "Payer" → redirection vers provider (Stripe/PayPal)
- Confirmation de paiement
- `useTranslation('common')`

### `SharedDocumentPage.tsx` (page publique de partage)
**Fichier** : `app/src/pages/pos/SharedDocumentPage.tsx`
**Route** : `/shared/:token`

- Page publique (sans login admin)
- Affiche le document (PDF inline ou HTML)
- Bouton "Télécharger"
- Marque `viewed = true` au chargement
- `useTranslation('common')`

## I.5 Modifications de pages

### `InvoicesPage.tsx`
- Bouton **"Signer électroniquement"** → modal (nom, email)
- Bouton **"Partager"** → modal (email destinataire, durée de validité) → génère lien
- Bouton **"Paiement en ligne"** → génère lien de paiement, copie URL
- Bouton **"Factur-X"** (déjà existant) → améliorer avec `generateFacturX`

### `QuotesPage.tsx`
- Bouton **"Signer électroniquement"** → modal
- Bouton **"Partager"** → modal

## I.6 i18n — Ajouts au namespace `sales`

| Section | Clés |
|---|---|
| `signing.*` | title, signNow, signerName, signerEmail, signedAt, signatureHash, signSuccess |
| `onlinePayment.*` | title, payNow, amount, invoiceNumber, paymentProvider, paymentSuccess, paymentFailed, generateLink |
| `sharing.*` | title, shareNow, sharedWith, shareLink, expiresIn, expires24h, expires7days, expires30days, copyLink, shareSuccess |

## I.7 Routes

```tsx
<Route path="/pay/:token" element={<OnlinePaymentPage />} />
<Route path="/shared/:token" element={<SharedDocumentPage />} />
```

---

# SPRINT J : Pilotage & Reporting (3j)

## J.1 SQL — Nouvelles tables

### `saved_filters` (filtres sauvegardés pour listes)
```sql
CREATE TABLE IF NOT EXISTS saved_filters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  page_name text NOT NULL,             -- 'invoices'|'quotes'|'orders'|'products'|'customers'
  filter_name text NOT NULL,
  filter_criteria jsonb NOT NULL,      -- critères de filtre en JSON
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sf_user_page ON saved_filters(user_email, page_name);
ALTER TABLE saved_filters ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_saved_filters') THEN
    CREATE POLICY "allow_all_saved_filters" ON saved_filters FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## J.2 Types TypeScript

```typescript
export interface SavedFilter {
  id: string
  user_email: string
  page_name: string
  filter_name: string
  filter_criteria: Record<string, any>
  is_default: boolean
  created_at: string
}
```

## J.3 Queries

| Fonction | Description |
|---|---|
| `getSavedFilters(pageName)` | Liste des filtres sauvegardés pour une page |
| `createSavedFilter(filter)` | Crée un filtre |
| `deleteSavedFilter(id)` | Supprime un filtre |
| `getRevenueSimulation(params)` | Simulation CA : {period, growthRate, scenario} → projection |
| `getMarginAnalysis(params)` | Analyse marges : {period, byProduct, byCustomer, byCategory} |
| `getSalesDashboardStats(period)` | Stats globales : CA, marge, nb factures, panier moyen, top clients, top produits |

## J.4 Nouvelles pages

### `RevenueSimulationPage.tsx`
**Fichier** : `app/src/pages/sales/RevenueSimulationPage.tsx`
**Route** : `/sales/simulation`

- Sélection période (mois/trimestre/année)
- Saisie taux de croissance (%) ou scénarios (optimiste, réaliste, pessimiste)
- Graphique : CA actuel vs CA projeté
- Tableau par mois avec projections
- `useTranslation('sales')`

### `MarginAnalysisPage.tsx`
**Fichier** : `app/src/pages/sales/MarginAnalysisPage.tsx`
**Route** : `/sales/margins`

- Sélection période + dimension (par produit, par client, par catégorie)
- Tableau : CA, coût, marge brute, % marge
- Graphique : évolution des marges dans le temps
- Alertes : marges négatives ou sous seuil
- `useTranslation('sales')`

## J.5 Modifications de pages

### Toutes les pages de liste (InvoicesPage, QuotesPage, SalesOrdersPage, etc.)
- **Bouton "Sauvegarder le filtre"** dans la barre de filtres
- **Dropdown "Filtres sauvegardés"** : liste des filtres + appliquer + supprimer
- **Étoile "Filtre par défaut"** : applique automatiquement au chargement de page

## J.6 i18n

**`sales.json`** (fr/en/ar) :
- `simulation.*` : title, period, growthRate, scenario, optimistic, realistic, pessimistic, currentRevenue, projectedRevenue, byMonth
- `margins.*` : title, byProduct, byCustomer, byCategory, revenue, cost, grossMargin, marginPercent, marginTrend, lowMarginAlert
- `savedFilters.*` : title, save, filterName, setDefault, apply, delete, noFilters

## J.7 Routes

```tsx
<Route path="/sales/simulation" element={<RevenueSimulationPage />} />
<Route path="/sales/margins" element={<MarginAnalysisPage />} />
```

---

# SPRINT K : i18n — Finalisation (2j)

## K.1 Vue d'ensemble

Vérifier et compléter toutes les clés de traduction pour les 3 langues (fr, en, ar) sur tous les nouveaux namespaces créés dans les sprints A-J.

## K.2 Namespaces à créer/vérifier

| Namespace | Fichiers | Sprints concernés |
|---|---|---|
| `sales` (extensions) | `app/src/i18n/locales/{fr,en,ar}/sales.json` | A, B, D, I, J |
| `purchases` (nouveau) | `app/src/i18n/locales/{fr,en,ar}/purchases.json` | C |
| `stock` (extensions) | `app/src/i18n/locales/{fr,en,ar}/stock.json` | D, E |
| `crm` (nouveau) | `app/src/i18n/locales/{fr,en,ar}/crm.json` | F, G |
| `pos` (nouveau) | `app/src/i18n/locales/{fr,en,ar}/pos.json` | H |

## K.3 Checklist de vérification

Pour chaque namespace et chaque langue (fr, en, ar) :

1. **Toutes les clés utilisées dans les pages** ont une entrée dans le JSON
2. **Aucune clé manquante** dans aucune des 3 langues
3. **Aucune clé hardcodée** (texte français directement dans le code)
4. **Les namespaces sont correctement déclarés** dans `app/src/i18n/index.ts`
5. **Les traductions ar** sont correctes et le RTL est géré (`dir="rtl"`)
6. **Les clés communes** (`common.*`) sont utilisées pour les actions génériques (save, cancel, delete, confirm, etc.)

## K.4 Configuration i18n

### Ajouter les nouveaux namespaces dans `app/src/i18n/index.ts`

```typescript
// Ajouter les imports pour les nouveaux namespaces
import purchases_fr from './locales/fr/purchases.json'
import purchases_en from './locales/en/purchases.json'
import purchases_ar from './locales/ar/purchases.json'

import crm_fr from './locales/fr/crm.json'
import crm_en from './locales/en/crm.json'
import crm_ar from './locales/ar/crm.json'

import pos_fr from './locales/fr/pos.json'
import pos_en from './locales/en/pos.json'
import pos_ar from './locales/ar/pos.json'

// Ajouter dans les resources pour chaque langue
resources: {
  fr: { ..., purchases: purchases_fr, crm: crm_fr, pos: pos_fr },
  en: { ..., purchases: purchases_en, crm: crm_en, pos: pos_en },
  ar: { ..., purchases: purchases_ar, crm: crm_ar, pos: pos_ar },
}
```

## K.5 Navigation — Ajouts dans `nav.json`

Ajouter les nouvelles routes dans `app/src/i18n/locales/{fr,en,ar}/nav.json` :

| Clé | FR | EN | AR |
|---|---|---|---|
| `items.customer360` | Vue 360° client | Customer 360° view | عرض 360° للعميل |
| `items.purchaseRequests` | Demandes d'achat | Purchase requests | طلبات الشراء |
| `items.supplierPrices` | Tarifs fournisseurs | Supplier prices | أسعار الموردين |
| `items.supplierDeliverySchedule` | Cadencier fournisseurs | Supplier delivery schedule | جدول التسليم |
| `items.promotions` | Promotions | Promotions | العروض الترويجية |
| `items.productGrids` | Gammes produits | Product grids | شبكات المنتجات |
| `items.stockAlerts` | Alertes stock | Stock alerts | تنبيهات المخزون |
| `items.opportunities` | Opportunités | Opportunities | الفرص |
| `items.activities` | Activités CRM | CRM activities | الأنشطة |
| `items.campaigns` | Campagnes | Campaigns | الحملات |
| `items.territories` | Secteurs | Territories | المناطق |
| `items.salesForecasts` | Prévisions ventes | Sales forecasts | توقعات المبيعات |
| `items.tickets` | Tickets support | Support tickets | تذاكر الدعم |
| `items.serviceContracts` | Contrats de service | Service contracts | عقود الخدمة |
| `items.knowledgeBase` | Base de connaissances | Knowledge base | قاعدة المعرفة |
| `items.posTerminal` | Point de vente | Point of sale | نقطة البيع |
| `items.posSessions` | Sessions de caisse | POS sessions | جلسات الصندوق |
| `items.posStats` | Statistiques caisse | POS statistics | إحصائيات الصندوق |
| `items.revenueSimulation` | Simulation CA | Revenue simulation | محاكاة الإيرادات |
| `items.marginAnalysis` | Analyse marges | Margin analysis | تحليل الهوامش |

## K.6 Structure de navigation (menu sidebar)

### Groupe "Commercial" — sous-groupe "Ventes"
- Clients
- **Vue 360° client** (contextuel)
- Devis
- Commandes
- Bons de livraison
- Factures
- Avoirs
- **Promotions** (nouveau)
- **Simulation CA** (nouveau)
- **Analyse marges** (nouveau)
- Factures récurrentes
- Règlements clients
- Facture électronique

### Groupe "Commercial" — sous-groupe "Achats"
- Fournisseurs
- Factures d'achat
- Avoirs fournisseurs
- **Demandes d'achat** (nouveau)
- **Tarifs fournisseurs** (nouveau)
- **Cadencier fournisseurs** (nouveau)
- Commandes fournisseurs
- Réceptions marchandises
- Règlements fournisseurs

### Groupe "Commercial" — sous-groupe "CRM" (nouveau)
- **Opportunités** (nouveau)
- **Activités** (nouveau)
- **Campagnes** (nouveau)
- **Secteurs** (nouveau)
- **Prévisions ventes** (nouveau)
- **Tickets support** (nouveau)
- **Contrats de service** (nouveau)
- **Base de connaissances** (nouveau)

### Groupe "Commercial" — sous-groupe "POS" (nouveau)
- **Terminal de vente** (nouveau)
- **Sessions de caisse** (nouveau)
- **Statistiques caisse** (nouveau)

### Groupe "Stock" — ajouts
- **Gammes produits** (nouveau)
- **Alertes stock** (nouveau)

---

## Récapitulatif global

| Sprint | Durée | Nouvelles tables | Nouvelles pages | Nouveaux namespaces |
|---|---|---|---|---|
| A | 4-5j | 2 | 0 (modifications) | sales (extensions) |
| B | 3j | 2 | 1 (Customer360) | sales (extensions) |
| C | 3-4j | 5 | 3 | purchases (nouveau) |
| D | 3j | 5 | 2 | sales + stock (extensions) |
| E | 2-3j | 2 | 1 | stock (extensions) |
| F | 5-6j | 6 | 5 | crm (nouveau) |
| G | 4-5j | 4 | 4 | crm (extensions) |
| H | 4-5j | 4 | 3 | pos (nouveau) |
| I | 3j | 3 | 2 (publiques) | sales (extensions) |
| J | 3j | 1 | 2 | sales (extensions) |
| K | 2j | 0 | 0 | Tous (vérification) |
| **Total** | **~35-45j** | **34** | **23** | **4 nouveaux** |

## Ordre d'exécution recommandé

1. **Sprint A** en premier (fondations du cycle commercial)
2. **Sprint K** en parallèle (i18n au fur et à mesure)
3. **Sprints B + C** (clients + achats)
4. **Sprints D + E** (catalogue + stock)
5. **Sprints F + G** (CRM)
6. **Sprint H** (POS)
7. **Sprint I** (dématérialisation)
8. **Sprint J** (pilotage)

## Validation après chaque sprint

```bash
cd app && npx tsc --noEmit --pretty
cd app && npm run dev
```

+ `browser_preview` sur `http://localhost:5173` pour vérification visuelle
