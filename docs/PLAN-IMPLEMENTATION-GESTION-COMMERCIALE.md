# Plan d'Implémentation — Gestion Commerciale Complète

> **Source** : SAGE-100-REFERENCE-COMPLETE.md (Sections 5, 10, 11, 16)
> **i18n** : Toutes nouvelles pages doivent utiliser `useTranslation` (fr, en, ar)

---

## Analyse comparative

### Déjà implémenté ✅

Clients, Fournisseurs, Devis, Factures vente/achat, Avoirs, Commandes vente/achat, Bons de livraison, Réceptions, Paiements, Articles, Grilles tarifaires, Facturation récurrente, Multi-dépôts, Stock, Mouvements, Inventaire, Réappro, Transfert, BOM, OF, Prospects, Représentants, Emplacements, Qualité, Picking, Série/Lot, Substitution, Plannings livraison, Modèles docs, Stock dormant, Variantes, Dashboards ventes/achats, E-invoice, Relances, Recouvrement, Approbation factures, Automatisation fournisseurs.

### Manquant ❌

**Cycle commercial :** Transformations en cascade (devis→commande→livraison→facture→avoir), reliquats, facture d'acompte, frais de port/approche, codes-barres, circuit validation, création articles/tiers à la volée, promotions/soldes.

**Clients :** Vue 360°, contrôle encours automatique, multi-contacts, paramètres email par tiers, compte bancaire préféré.

**Achats :** Demandes d'achat, tarifs fournisseurs (multi), cadencier, contremarque, criticité réappro, traitement par lot, substitution automatique, CMUP/FIFO/LIFO.

**Stock :** Stock prévisionnel, gammes (tailles/couleurs), conditionnements, alertes seuil actives, affectation utilisateurs par dépôt.

**CRM Force de Vente (tout) :** Opportunités/pipeline, activités, campagnes marketing, secteurs, e-mailing, prévisions ventes, géolocalisation.

**CRM Service Client (tout) :** Tickets, base de connaissances, contrats de service, SLA, extranet clients.

**POS/Caisse (tout) :** Écran de vente, caisses, sessions, tickets, statistiques, certification légale.

**Dématérialisation :** Factur-X, signature électronique, paiement en ligne, partage documents.

**Pilotage :** Simulation CA, analyse marges, listes avancées avec filtres sauvegardables.

---

## Sprint A — Transformations du cycle commercial (4-5j)

### SQL
- `document_charges` (frais port/approche par document)
- `document_transformations` (historique transformations)
- Étendre `sales_orders` : `quote_id`, `delivered_quantity`, `fully_delivered`
- Étendre `delivery_notes` : `sales_order_id`
- Étendre `invoices` : `delivery_note_id`, `sales_order_id`, `quote_id`, `is_advance_invoice`, `advance_amount`
- Étender `sales_order_lines` : `delivered_quantity`
- Étender `delivery_note_lines` : `invoiced_quantity`
- Étender `products` : `barcode`, `weight`, `photo_url`, `supplier_ref`, `criticality_level`

### Queries
- `transformQuoteToSalesOrder(quoteId)` → crée commande depuis devis
- `transformSalesOrderToDeliveryNote(orderId, lineSelection?)` → crée livraison (+ vérif stock + reliquats)
- `transformDeliveryNoteToInvoice(deliveryNoteId, lineSelection?)` → crée facture (+ reliquats)
- `transformInvoiceToCreditNote(invoiceId, reason, lineSelection?)` → crée avoir
- `createAdvanceInvoice(customerId, amount, vatRate)` → facture d'acompte
- `checkStockAvailability(productId, warehouseId, qty)` → { available, currentStock, reserved }
- `getStockForecast(productId)` → { current, incoming, outgoing, forecast }

### Modifs pages
- `QuotesPage` : bouton "Transformer en commande"
- `SalesOrdersPage` : bouton "Transformer en livraison" + colonnes reliquats
- `DeliveryNotesPage` : bouton "Transformer en facture" + colonnes reliquats
- `InvoicesPage` : bouton "Créer avoir" + "Facture d'acompte" + type facture
- `CreditNotesPage` : lien facture source

### Nouveau composant
- `@/components/DocumentCharges.tsx` : frais de port/approche réutilisable

---

## Sprint B — Gestion clients avancée (3j)

### SQL
- `customer_contacts` (multi-contacts)
- `supplier_contacts`
- Étendre `customers` : `bank_account_id`, `price_list_id`, `sales_rep_id`, `email_settings` (jsonb)
- Étendre `suppliers` : idem

### Nouvelle page
- `@/pages/sales/Customer360Page.tsx` : vue 360° (infos, historique, encours, stats, relances, documents)

### Modifs
- `CustomersPage` : nouveaux champs, multi-contacts, paramètres email, bouton "Vue 360°", contrôle encours
- `SuppliersPage` : nouveaux champs, multi-contacts

---

## Sprint C — Gestion achats avancée (3-4j)

### SQL
- `purchase_requests` (demandes d'achat)
- `supplier_price_lists` (multi-tarifs fournisseurs)
- `supplier_delivery_schedules` (cadencier)

### Nouvelles pages
- `@/pages/purchases/PurchaseRequestsPage.tsx` : demandes d'achat + workflow approbation + conversion PO
- `@/pages/purchases/SupplierPriceListsPage.tsx` : tarifs fournisseurs + comparateur + import
- `@/pages/purchases/SupplierDeliverySchedulePage.tsx` : cadencier de livraison

### Modifs
- `ReorderPage` : criticité, traitement par lot, substitution auto, meilleur tarif
- `ProductsPage` : référence fournisseur, criticité, code-barres, poids, photo, prix de revient

---

## Sprint D — Catalogue articles étendu (3j)

### SQL
- `product_grids` (gammes : tailles/couleurs/etc.)
- `product_packagings` (conditionnements)
- `product_links` (articles liés/complémentaires)
- `promotions` (soldes/promotions sur période)

### Nouvelles pages
- `@/pages/sales/PromotionsPage.tsx` : CRUD promotions (remise %, montant, buy X get Y, livraison gratuite)
- `@/pages/stock/ProductGridsPage.tsx` : gammes + vue matricielle stock

### Modifs
- `ProductsPage` : onglets Gammes, Conditionnements, Articles liés, Tarifs fournisseurs, Stock prévisionnel

---

## Sprint E — Stock avancé (2-3j)

### SQL
- Étendre `stock_quantities` : `reserved_quantity`, `incoming_quantity`
- `warehouse_users` (affectation utilisateurs par dépôt)
- `stock_alerts` (alertes de seuil)

### Nouvelle page
- `@/pages/stock/StockForecastPage.tsx` : stock prévisionnel avec code couleur

### Modifs
- `StockQuantitiesPage` : colonnes réservé/disponible/entrant/prévisionnel + alertes
- `WarehousesPage` : affectation utilisateurs
- `InventoryPage` : comparaison théorique/réel + alertes automatiques

---

## Sprint F — CRM Force de Vente (5-6j)

### SQL
- `opportunities` (pipeline commercial)
- `crm_activities` (appels, emails, réunions, tâches)
- `marketing_campaigns` (campagnes + ROI)
- `sales_territories` (secteurs commerciaux)

### Nouvelles pages (7)
- `@/pages/crm/OpportunitiesPage.tsx` : pipeline Kanban + liste + prévisionnel pondéré
- `@/pages/crm/ActivitiesPage.tsx` : agenda + liste activités + relances
- `@/pages/crm/MarketingCampaignsPage.tsx` : campagnes + ROI
- `@/pages/crm/SalesTerritoriesPage.tsx` : secteurs + représentants
- `@/pages/crm/CRMContactsPage.tsx` : contacts unifiés + segmentation + export
- `@/pages/crm/CRMEmailingPage.tsx` : e-mailing + suivi clics + chaînes de prospection
- `@/pages/crm/SalesForecastPage.tsx` : prévisions ventes + comparaison réalisé

### Routes
```tsx
<Route path="/crm" element={<ModuleHubPage moduleId="crm" />} />
<Route path="/crm/opportunities" element={<OpportunitiesPage />} />
<Route path="/crm/activities" element={<ActivitiesPage />} />
<Route path="/crm/campaigns" element={<MarketingCampaignsPage />} />
<Route path="/crm/territories" element={<SalesTerritoriesPage />} />
<Route path="/crm/contacts" element={<CRMContactsPage />} />
<Route path="/crm/emailing" element={<CRMEmailingPage />} />
<Route path="/crm/forecast" element={<SalesForecastPage />} />
```

---

## Sprint G — CRM Service Client (4-5j)

### SQL
- `support_tickets` (tickets avec SLA)
- `ticket_responses` (réponses + notes internes)
- `kb_articles` (base de connaissances)
- `service_contracts` (contrats maintenance/SLA)

### Nouvelles pages (5)
- `@/pages/crm/TicketsPage.tsx` : Kanban tickets + SLA + escalade
- `@/pages/crm/KnowledgeBasePage.tsx` : articles + recherche full-text + votes
- `@/pages/crm/ServiceContractsPage.tsx` : contrats + alertes renouvellement
- `@/pages/crm/CustomerPortalPage.tsx` : portail self-service clients
- `@/pages/crm/SLADashboardPage.tsx` : KPIs (temps réponse/résolution, satisfaction)

### Routes
```tsx
<Route path="/crm/tickets" element={<TicketsPage />} />
<Route path="/crm/knowledge-base" element={<KnowledgeBasePage />} />
<Route path="/crm/contracts" element={<ServiceContractsPage />} />
<Route path="/crm/sla-dashboard" element={<SLADashboardPage />} />
<Route path="/portal" element={<CustomerPortalPage />} />
```

---

## Sprint H — POS / Saisie de Caisse (4-5j)

### SQL
- `pos_registers` (caisses)
- `pos_sessions` (sessions de caisse avec X/Z)
- `pos_tickets` (tickets de caisse)
- `pos_ticket_lines` (lignes de tickets)

### Nouvelles pages (3)
- `@/pages/pos/POSPage.tsx` : écran de caisse plein écran (scan, panier, paiement, mise en attente)
- `@/pages/pos/POSDashboardPage.tsx` : statistiques (palmarès, ventes par caisse/période)
- `@/pages/pos/POSAdminPage.tsx` : config caisses, caissiers, touches, promotions

### Routes
```tsx
<Route path="/pos" element={<POSPage />} />
<Route path="/pos/dashboard" element={<POSDashboardPage />} />
<Route path="/pos/admin" element={<POSAdminPage />} />
```

---

## Sprint I — Dématérialisation (3j)

### Modifs
- `EInvoicePage` : Factur-X (PDF+XML), Sage Network, signature électronique, paiement en ligne, partage
- `PaymentRemindersPage` : liens de paiement Stripe/PayPal dans les relances

### Nouvelles pages
- `@/pages/sales/DocumentSignaturePage.tsx` : envoi + suivi signatures électroniques
- `@/pages/sales/OnlinePaymentPage.tsx` : config Stripe/PayPal + liens de paiement + suivi

---

## Sprint J — Pilotage & Reporting (3j)

### Nouvelles pages
- `@/pages/sales/SalesSimulationPage.tsx` : simulation CA + analyse marges (par produit/client/catégorie)
- `@/pages/sales/AdvancedListsPage.tsx` : listes avec filtres multi-critères sauvegardables + export

### Modifs
- `SalesDashboardPage` : widgets pipeline, top produits/clients, marge, taux conversion, délai paiement
- `PurchasesDashboardPage` : top fournisseurs, délai paiement, réceptions en attente, demandes d'achat

---

## Sprint K — i18n (2j)

### Nouveaux namespaces
- `@/i18n/locales/{fr,en,ar}/commercial.json` : transformations, frais, customer360, contacts, emailSettings, purchaseRequests, supplierPrices, deliverySchedule, productGrids, packagings, promotions, stockForecast, alerts
- `@/i18n/locales/{fr,en,ar}/crm.json` : opportunities, activities, campaigns, territories, tickets, knowledgeBase, contracts, portal
- `@/i18n/locales/{fr,en,ar}/pos.json` : register, ticket, sales, stats

---

## Résumé

| Sprint | Durée | Priorité |
|---|---|---|
| A — Transformations cycle | 4-5j | 🔴 Bloquant |
| B — Clients avancés | 3j | 🔴 Haute |
| C — Achats avancés | 3-4j | 🔴 Haute |
| D — Catalogue étendu | 3j | 🟡 Moyenne |
| E — Stock avancé | 2-3j | 🟡 Moyenne |
| F — CRM Force de Vente | 5-6j | 🔴 Haute |
| G — CRM Service Client | 4-5j | 🟡 Moyenne |
| H — POS / Caisse | 4-5j | 🟡 Moyenne |
| I — Dématérialisation | 3j | 🟡 Moyenne |
| J — Pilotage | 3j | 🟢 Basse |
| K — i18n | 2j | 🔴 Obligatoire |

**Total : ~35-45 jours de développement**
**Nouveaux fichiers : ~30 pages + 9 namespaces i18n + 1 SQL**
**Fichiers modifiés : ~15 pages existantes + queries.ts + types/index.ts + App.tsx**
