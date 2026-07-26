# PARTIE 1 — Sprint A : Transformations du cycle commercial (4-5j)

> **Objectif** : Cascades Devis → Commande → BL → Facture → Avoir, reliquats, acomptes, frais de port
> **i18n** : `useTranslation` (fr, en, ar) sur tous nouveaux composants
> **SQL** : `app/sql/47_sprint_a_commercial_transformations.sql`

---

## 1.1 Vue d'ensemble

```
Devis ──→ Commande ──→ Bon de livraison ──→ Facture ──→ Avoir
                                    │
                                    └── Facture d'acompte (sur commande)
```

- **Reliquats** : quantité restante = quantité - quantité transformée
- **Frais de port/approche** : table `document_charges` sur tous documents
- **Historique** : table `document_transformations` trace chaque conversion

---

## 1.2 SQL — Nouvelles tables

### `document_charges`
```sql
CREATE TABLE IF NOT EXISTS document_charges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  document_type text NOT NULL,   -- 'quote'|'sales_order'|'delivery_note'|'invoice'|'credit_note'
  document_id uuid NOT NULL,
  charge_type text NOT NULL,     -- 'shipping'|'handling'|'insurance'|'packaging'|'other'
  label text NOT NULL,
  amount numeric(15,2) DEFAULT 0,
  vat_rate numeric(5,2) DEFAULT 0,
  vat_amount numeric(15,2) DEFAULT 0,
  total_amount numeric(15,2) DEFAULT 0,
  supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_doc_charges_doc ON document_charges(document_type, document_id);
ALTER TABLE document_charges ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_document_charges') THEN
    CREATE POLICY "allow_all_document_charges" ON document_charges FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `document_transformations`
```sql
CREATE TABLE IF NOT EXISTS document_transformations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  source_type text NOT NULL,     -- 'quote'|'sales_order'|'delivery_note'|'invoice'
  source_id uuid NOT NULL,
  target_type text NOT NULL,     -- 'sales_order'|'delivery_note'|'invoice'|'credit_note'
  target_id uuid NOT NULL,
  transformation_type text NOT NULL, -- 'full'|'partial'
  transformed_by text,
  transformed_at timestamptz DEFAULT now(),
  notes text
);
CREATE INDEX IF NOT EXISTS idx_doc_trans_src ON document_transformations(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_doc_trans_tgt ON document_transformations(target_type, target_id);
ALTER TABLE document_transformations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_doc_transformations') THEN
    CREATE POLICY "allow_all_doc_transformations" ON document_transformations FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## 1.3 SQL — Extensions de tables existantes

```sql
-- sales_orders
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS quote_id uuid;
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS fully_delivered boolean DEFAULT false;
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS delivery_status text DEFAULT 'pending';

-- sales_order_lines
ALTER TABLE sales_order_lines ADD COLUMN IF NOT EXISTS delivered_quantity numeric(15,2) DEFAULT 0;

-- delivery_notes
ALTER TABLE delivery_notes ADD COLUMN IF NOT EXISTS fully_invoiced boolean DEFAULT false;
ALTER TABLE delivery_notes ADD COLUMN IF NOT EXISTS invoice_status text DEFAULT 'pending';

-- delivery_note_lines
ALTER TABLE delivery_note_lines ADD COLUMN IF NOT EXISTS invoiced_quantity numeric(15,2) DEFAULT 0;
ALTER TABLE delivery_note_lines ADD COLUMN IF NOT EXISTS sales_order_line_id uuid;

-- invoices
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS delivery_note_id uuid;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS sales_order_id uuid;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS quote_id uuid;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS is_advance_invoice boolean DEFAULT false;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS advance_amount numeric(15,2) DEFAULT 0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS invoice_type text DEFAULT 'standard';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS parent_invoice_id uuid;

-- invoice_lines
ALTER TABLE invoice_lines ADD COLUMN IF NOT EXISTS delivery_note_line_id uuid;
ALTER TABLE invoice_lines ADD COLUMN IF NOT EXISTS sales_order_line_id uuid;

-- credit_notes
ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS source_invoice_id uuid;

-- products
ALTER TABLE products ADD COLUMN IF NOT EXISTS barcode text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS weight numeric(10,3);
ALTER TABLE products ADD COLUMN IF NOT EXISTS photo_url text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS supplier_ref text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS criticality_level text DEFAULT 'normal';
ALTER TABLE products ADD COLUMN IF NOT EXISTS cost_price numeric(15,2) DEFAULT 0;

-- quotes
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS transformed_to_order_id uuid;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS transformation_status text DEFAULT 'pending';
```

---

## 1.4 Types TypeScript (`types/index.ts`)

### Nouvelles interfaces
```typescript
export interface DocumentCharge {
  id: string
  tenant_id: string | null
  document_type: 'quote'|'sales_order'|'delivery_note'|'invoice'|'credit_note'|'purchase_order'|'purchase_invoice'
  document_id: string
  charge_type: 'shipping'|'handling'|'insurance'|'packaging'|'other'
  label: string
  amount: number
  vat_rate: number
  vat_amount: number
  total_amount: number
  supplier_id: string | null
  created_at: string
}

export interface DocumentTransformation {
  id: string
  tenant_id: string | null
  source_type: 'quote'|'sales_order'|'delivery_note'|'invoice'
  source_id: string
  target_type: 'sales_order'|'delivery_note'|'invoice'|'credit_note'
  target_id: string
  transformation_type: 'full'|'partial'
  transformed_by: string | null
  transformed_at: string
  notes: string | null
}
```

### Champs à ajouter aux interfaces existantes
| Interface | Champs |
|---|---|
| `SalesOrder` | `quote_id?`, `fully_delivered?`, `delivery_status?` |
| `SalesOrderLine` | `delivered_quantity?`, `remaining_quantity?` |
| `DeliveryNote` | `fully_invoiced?`, `invoice_status?` |
| `DeliveryNoteLine` | `invoiced_quantity?`, `remaining_quantity?`, `sales_order_line_id?` |
| `Invoice` | `delivery_note_id?`, `sales_order_id?`, `quote_id?`, `is_advance_invoice?`, `advance_amount?`, `invoice_type?`, `parent_invoice_id?` |
| `InvoiceLine` | `delivery_note_line_id?`, `sales_order_line_id?` |
| `CreditNote` | `source_invoice_id?` |
| `Product` | `barcode?`, `weight?`, `photo_url?`, `supplier_ref?`, `criticality_level?`, `cost_price?` |
| `Quote` | `transformed_to_order_id?`, `transformation_status?` |

---

## 1.5 Queries (`queries.ts`)

| Fonction | Description |
|---|---|
| `transformQuoteToSalesOrder(quoteId)` | Crée commande depuis devis, copie lignes + frais, marque devis |
| `transformSalesOrderToDeliveryNote(orderId, lineSelection?)` | Crée BL, vérif stock, met à jour `delivered_quantity` |
| `transformDeliveryNoteToInvoice(dnId, lineSelection?)` | Crée facture, met à jour `invoiced_quantity` |
| `transformInvoiceToCreditNote(invoiceId, reason, lineSelection?)` | Crée avoir depuis facture |
| `createAdvanceInvoice(customerId, amount, vatRate)` | Crée facture d'acompte |
| `checkStockAvailability(productId, warehouseId, qty)` | Retourne `{available, currentStock, reserved}` |
| `getStockForecast(productId)` | Retourne `{current, incoming, outgoing, forecast}` |
| `getDocumentCharges(docType, docId)` | Récupère les frais d'un document |
| `addDocumentCharge(charge)` | Ajoute un frais |
| `deleteDocumentCharge(id)` | Supprime un frais |

---

## 1.6 Nouveau composant — `DocumentCharges.tsx`

**Fichier** : `app/src/components/DocumentCharges.tsx`

**Props** : `documentType`, `documentId`, `onTotalChange?`

- Card "Frais de port & approche"
- Tableau des charges (type, label, HT, TVA, TTC)
- Bouton "Ajouter" → modal : `charge_type` (Select), `label` (Input), `amount` (Input number), `vat_rate` (Select 0/5.5/10/20), `supplier_id` (Select transporteur optionnel)
- Calcul auto : `vat_amount = amount * vat_rate / 100`, `total = amount + vat_amount`
- Total des charges en bas
- `useTranslation('sales')`

---

## 1.7 Modifications de pages

### `QuotesPage.tsx`
- Bouton **"Transformer en commande"** à côté de "Convertir en facture"
- Colonne **"Statut transformation"** : badge (pending/transformed/partial)
- Désactiver si `transformation_status === 'transformed'`

### `SalesOrdersPage.tsx`
- Bouton **"Transformer en livraison"**
- Modal sélection des lignes (checkbox + quantité restante) si partielle
- Colonnes reliquats : `delivered_quantity` / `quantity`
- Colonne **"Statut livraison"** : badge (pending/partial/delivered)
- Désactiver si `fully_delivered === true`

### `DeliveryNotesPage.tsx`
- Bouton **"Transformer en facture"**
- Modal sélection des lignes si partielle
- Colonnes reliquats : `invoiced_quantity` / `quantity`
- Colonne **"Statut facturation"** : badge (pending/partial/invoiced)
- Désactiver si `fully_invoiced === true`

### `InvoicesPage.tsx`
- Bouton **"Créer avoir"** → `transformInvoiceToCreditNote(id, reason)`
- Bouton **"Facture d'acompte"** dans le header → modal (client, montant, TVA)
- Colonne **"Type facture"** : badge (standard/advance/balance/proforma)
- Filtre par type
- Composant `DocumentCharges` dans le formulaire

### `CreditNotesPage.tsx`
- Colonne **"Facture source"** avec lien cliquable

---

## 1.8 i18n — Clés à ajouter

### Namespace `sales` — nouvelles sections

| Section | Clés principales |
|---|---|
| `transformations.*` | transformToOrder, transformToDelivery, transformToInvoice, transformToCreditNote, confirmations, messages succès, statuts (pending/partial/transformed/delivered/invoiced), selectLines, remainingQuantity, deliveredQuantity, invoicedQuantity |
| `advanceInvoice.*` | title, new, customer, amount, vatRate, create, created, type, standard, advance, balance, proforma |
| `documentCharges.*` | title, add, type, shipping, handling, insurance, packaging, other, label, amount, vatRate, vatAmount, total, carrier, totalCharges, delete |
| `quotes.*` (ajouts) | transformToOrder, transformedToOrder, transformationStatus |
| `orders.*` (ajouts) | transformToDelivery, deliveredQuantity, remainingQuantity, deliveryStatus |
| `deliveryNotes.*` (ajouts) | transformToInvoice, invoicedQuantity, remainingQuantity, invoiceStatus |
| `invoices.*` (ajouts) | createCreditNote, advanceInvoice, invoiceType, sourceInvoice |
| `creditNotes.*` (ajouts) | sourceInvoice, viewSourceInvoice |

**3 langues** : fr (défaut), en, ar (RTL) — fichiers dans `app/src/i18n/locales/{fr,en,ar}/sales.json`

---

## 1.9 Routes

Aucune nouvelle route — uniquement modifications de pages existantes.
