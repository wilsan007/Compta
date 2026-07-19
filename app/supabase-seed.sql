-- ============================================
-- Compta App - Test Data Seed
-- Execute this AFTER supabase-schema.sql
-- ============================================

-- ============================================
-- COMPANY SETTINGS
-- ============================================
insert into company_settings (name, legal_name, vat_number, siret, address, city, postal_code, country, currency, email, phone, website)
values ('TechCorp Solutions', 'TechCorp Solutions SARL', 'FR12345678901', '12345678900012', '15 rue de la Innovation', 'Paris', '75001', 'France', 'EUR', 'contact@techcorp.fr', '0123456789', 'https://techcorp.fr')
on conflict do nothing;

-- ============================================
-- USERS
-- ============================================
insert into users (name, email, role, active, last_login) values
  ('Admin Demo', 'admin@compta.fr', 'admin', true, now()),
  ('Marie Comptable', 'marie@compta.fr', 'accountant', true, now() - interval '1 day'),
  ('Jean Manager', 'jean@compta.fr', 'manager', true, now() - interval '3 days'),
  ('Sophie Viewer', 'sophie@compta.fr', 'viewer', false, null)
on conflict do nothing;

-- ============================================
-- CHART OF ACCOUNTS
-- ============================================
insert into chart_accounts (code, name, type, balance, vat_rate, description) values
  -- Classe 1 — Capitaux
  ('101000', 'Capital social', 'equity', 50000, '0', 'Capital de depart'),
  ('106000', 'Réserves', 'equity', 12000, '0', 'Réserves constituées'),
  ('108000', 'Compte de l''exploitant', 'equity', 0, '0', 'Apports exploitant'),
  ('110000', 'Report à nouveau', 'equity', 3500, '0', 'Report à nouveau créditeur'),
  ('120000', 'Résultat de l''exercice', 'equity', 0, '0', 'Résultat annuel'),
  ('131000', 'Subventions d''équipement', 'equity', 15000, '0', 'Subventions d''investissement reçues'),
  ('139000', 'Subventions d''investissement inscrites au résultat', 'equity', 3000, '0', 'Quote-part des subventions virée au résultat'),
  ('151000', 'Provisions pour risques', 'liability', 5000, '0', 'Provisions pour litiges'),
  ('164000', 'Emprunts auprès des établissements de crédit', 'liability', 20000, '0', 'Emprunt bancaire'),
  ('168000', 'Autres emprunts et dettes', 'liability', 4500, '0', 'Dettes financières diverses'),
  -- Classe 2 — Immobilisations
  ('205000', 'Concessions, brevets, licences', 'asset', 8000, '0', 'Logiciels et licences'),
  ('211000', 'Terrains', 'asset', 0, '0', 'Terrains propriété'),
  ('213000', 'Constructions', 'asset', 0, '0', 'Bâtiments'),
  ('215000', 'Installations techniques, matériel et outillage', 'asset', 15000, '0', 'Matériel de production'),
  ('218000', 'Materiel informatique', 'asset', 25000, '20', 'Ordinateurs et serveurs'),
  ('218300', 'Mobilier', 'asset', 6000, '0', 'Mobilier de bureau'),
  ('281000', 'Amortissements des immobilisations', 'asset', -12000, '0', 'Amortissements cumulés'),
  -- Classe 3 — Stocks
  ('310000', 'Matières premières', 'asset', 8500, '0', 'Stock matières premières'),
  ('330000', 'En-cours de production', 'asset', 3200, '0', 'Travaux en cours'),
  ('350000', 'Produits finis', 'asset', 12000, '0', 'Stock produits finis'),
  ('370000', 'Stocks de marchandises', 'asset', 9500, '0', 'Stock marchandises'),
  -- Classe 4 — Tiers
  ('401000', 'Fournisseurs', 'liability', 8900, '0', 'Compte fournisseur global'),
  ('401100', 'Fournisseurs - achats de biens', 'liability', 5200, '0', 'Fournisseurs biens'),
  ('401200', 'Fournisseurs - prestations de services', 'liability', 3700, '0', 'Fournisseurs services'),
  ('411000', 'Clients', 'asset', 12500, '0', 'Compte client global'),
  ('411100', 'Clients - ventes de biens', 'asset', 9500, '0', 'Clients biens'),
  ('411200', 'Clients - prestations de services', 'asset', 3000, '0', 'Clients services'),
  ('421000', 'Personnel - rémunérations dues', 'liability', 14000, '0', 'Salaires à payer'),
  ('431000', 'Sécurité sociale', 'liability', 6800, '0', 'Cotisations URSSAF'),
  ('445200', 'TVA due intracommunautaire', 'liability', 0, '0', 'TVA acquisitions IC'),
  ('445510', 'TVA collectée', 'liability', 17120, '0', 'TVA sur ventes'),
  ('445660', 'TVA déductible sur biens et services', 'asset', 9800, '0', 'TVA récupérable'),
  ('445670', 'Crédit de TVA à reporter', 'asset', 1200, '0', 'Crédit TVA précédent'),
  ('445710', 'TVA collectée 20%', 'liability', 17120, '0', 'TVA collectée taux normal'),
  ('445800', 'TVA à régulariser', 'liability', 0, '0', 'TVA en attente'),
  ('467000', 'Autres comptes débiteurs ou créditeurs', 'liability', 2300, '0', 'Comptes divers'),
  -- Classe 5 — Financiers
  ('510000', 'Valeurs mobilières de placement', 'asset', 0, '0', 'Titres de placement'),
  ('512000', 'Banque', 'asset', 38500, '0', 'Compte bancaire principal'),
  ('512100', 'Banque - Compte épargne', 'asset', 6700, '0', 'Compte épargne'),
  ('514000', 'Banque - Carte de crédit pro', 'asset', -1200, '0', 'Carte de crédit professionnelle'),
  ('530000', 'Caisse', 'asset', 200, '0', 'Espèces en caisse'),
  ('531000', 'Caisse - espèces', 'asset', 200, '0', 'Fonds de caisse'),
  ('580000', 'Virements internes', 'asset', 0, '0', 'Transferts inter-comptes'),
  -- Classe 6 — Charges
  ('601000', 'Achats stockés - matières premières', 'expense', 12000, '20', 'Achats matières'),
  ('607000', 'Achats de marchandises', 'expense', 32000, '20', 'Achats produits'),
  ('611000', 'Sous-traitance générale', 'expense', 5500, '20', 'Sous-traitance'),
  ('613000', 'Locations', 'expense', 8400, '20', 'Loyer bureau'),
  ('615000', 'Entretien et réparations', 'expense', 2300, '20', 'Maintenance'),
  ('616000', 'Primes d''assurance', 'expense', 3600, '0', 'Assurances'),
  ('618000', 'Documentation générale', 'expense', 800, '0', 'Abonnements presse'),
  ('622000', 'Honoraires', 'expense', 4500, '20', 'Comptable, avocat'),
  ('623000', 'Publicité, publications', 'expense', 2800, '20', 'Marketing'),
  ('626000', 'Frais postaux et télécommunications', 'expense', 1500, '20', 'Tel, internet, courrier'),
  ('635000', 'Impôts et taxes divers', 'expense', 3200, '0', 'CFE, CVAE, taxes diverses'),
  ('641000', 'Salaires', 'expense', 28000, '0', 'Salaires bruts'),
  ('645000', 'Charges de sécurité sociale et prévoyance', 'expense', 12500, '0', 'Cotisations sociales'),
  ('661000', 'Charges d''intérêts', 'expense', 850, '0', 'Agios et intérêts emprunts'),
  -- Classe 7 — Produits
  ('701000', 'Ventes de produits finis', 'income', 45000, '20', 'Ventes production'),
  ('706000', 'Prestations de services', 'income', 35000, '20', 'Ventes services'),
  ('707000', 'Ventes de marchandises', 'income', 85600, '20', 'CA produits'),
  ('708000', 'Produits des activités annexes', 'income', 4200, '20', 'Ventes annexes'),
  ('740000', 'Subventions d''exploitation', 'income', 2000, '0', 'Subventions d''exploitation reçues'),
  ('758000', 'Produits divers de gestion courante', 'income', 1500, '0', 'Produits divers'),
  ('771000', 'Produits exceptionnels sur opérations de gestion', 'income', 800, '0', 'Produits exceptionnels')
on conflict (code) do nothing;

-- ============================================
-- CUSTOMERS
-- ============================================
insert into customers (name, email, phone, address, city, postal_code, country, vat_number, contact_name, balance, credit_limit, payment_terms, currency) values
  ('Societe ABC', 'contact@abc.fr', '0123456789', '10 rue du Commerce', 'Lyon', '69001', 'France', 'FR98765432109', 'Pierre Martin', 1200, 10000, '30 days', 'EUR'),
  ('Entreprise XYZ', 'finance@xyz.fr', '0234567890', '25 avenue des Arts', 'Marseille', '13001', 'France', 'FR56789012345', 'Sarah Dubois', 0, 5000, '15 days', 'EUR'),
  ('Entreprise DEF', 'compta@def.fr', '0345678901', '8 boulevard Tech', 'Bordeaux', '33000', 'France', 'FR45678901234', 'Marc Leroy', 800, 8000, '30 days', 'EUR'),
  ('Global Services', 'info@globalservices.com', '0456789012', '55 rue Internationale', 'Lille', '59000', 'France', 'FR34567890123', 'Emma Wilson', 3500, 15000, '45 days', 'EUR'),
  ('Startup Lab', 'hello@startuplab.fr', '0567890123', '3 rue de l Innovation', 'Nantes', '44000', 'France', 'FR23456789012', 'Lucas Petit', 0, 3000, '30 days', 'EUR')
on conflict do nothing;

-- ============================================
-- SUPPLIERS
-- ============================================
insert into suppliers (name, email, phone, address, city, postal_code, country, vat_number, contact_name, balance, payment_terms, currency) values
  ('Fournisseur GHI', 'achat@ghi.fr', '0678901234', '12 rue des Fournisseurs', 'Toulouse', '31000', 'France', 'FR89012345678', 'Nathalie Roux', 890, '30 days', 'EUR'),
  ('Cloud Services Pro', 'billing@cloudpro.com', '0789012345', '7 rue du Cloud', 'Nice', '06000', 'France', 'FR78901234567', 'Thomas Blanc', 450, '15 days', 'EUR'),
  ('Office Supplies Co', 'commandes@officesupplies.fr', '0890123456', '20 rue du Bureau', 'Strasbourg', '67000', 'France', 'FR67890123456', 'Julie Moreau', 0, '30 days', 'EUR'),
  ('Marketing Agency', 'factures@marketing.fr', '0901234567', '33 rue de la Pub', 'Rennes', '35000', 'France', 'FR56789012345', 'Antoine Girard', 1200, '45 days', 'EUR')
on conflict do nothing;

-- ============================================
-- PRODUCTS
-- ============================================
insert into products (name, sku, description, type, sale_price, purchase_price, vat_rate, stock_quantity, reorder_level, unit, category) values
  ('Licence Logiciel Pro', 'LIC-PRO-001', 'Licence annuelle logiciel Pro', 'service', 1200, 0, 20, 0, 0, 'licence', 'Logiciels'),
  ('Consultation Technique', 'CON-001', 'Journee de consultation technique', 'service', 800, 0, 20, 0, 0, 'jour', 'Services'),
  ('Ordinateur Portable', 'ORD-PORT-001', 'Ordinateur portable 15 pouces', 'stock', 950, 650, 20, 15, 5, 'unite', 'Materiel'),
  ('Souris Sans Fil', 'ACC-SOUR-001', 'Souris sans fil ergonomique', 'stock', 35, 18, 20, 50, 10, 'unite', 'Accessoires'),
  ('Abonnement Support', 'ABO-SUP-001', 'Abonnement support mensuel', 'service', 150, 0, 20, 0, 0, 'mois', 'Services')
on conflict (sku) do nothing;

-- ============================================
-- INVOICES (Sales)
-- ============================================
insert into invoices (number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, notes, recurring) values
  ('FAC-2024-042', (select id from customers where name = 'Societe ABC' limit 1), 'Societe ABC', current_date, current_date + 30, 'sent', 1000, 200, 1200, 0, 1200, 'Facture pour services de consultation', false),
  ('FAC-2024-041', (select id from customers where name = 'Entreprise XYZ' limit 1), 'Entreprise XYZ', current_date - 5, current_date + 25, 'paid', 2083.33, 416.67, 2500, 2500, 0, 'Paiement recu - merci', false),
  ('FAC-2024-040', (select id from customers where name = 'Global Services' limit 1), 'Global Services', current_date - 10, current_date + 20, 'viewed', 2916.67, 583.33, 3500, 0, 3500, 'Contrat annuel - paiement a 45j', false),
  ('FAC-2024-039', (select id from customers where name = 'Societe XYZ' limit 1), 'Societe XYZ', current_date - 15, current_date - 5, 'overdue', 1500, 300, 1800, 0, 1800, 'Relance 1 envoyee', false),
  ('FAC-2024-038', (select id from customers where name = 'Startup Lab' limit 1), 'Startup Lab', current_date - 20, current_date + 10, 'paid', 625, 125, 750, 750, 0, '', false),
  ('FAC-2024-035', (select id from customers where name = 'Entreprise DEF' limit 1), 'Entreprise DEF', current_date - 30, current_date - 8, 'overdue', 666.67, 133.33, 800, 0, 800, 'Retard de paiement - 22 jours', false),
  ('FAC-2024-034', (select id from customers where name = 'Global Services' limit 1), 'Global Services', current_date - 35, current_date - 5, 'paid', 4166.67, 833.33, 5000, 5000, 0, 'Paiement recu', false),
  ('FAC-2024-033', (select id from customers where name = 'Societe ABC' limit 1), 'Societe ABC', current_date - 40, current_date - 10, 'paid', 1250, 250, 1500, 1500, 0, '', false),
  ('FAC-2024-032', (select id from customers where name = 'Startup Lab' limit 1), 'Startup Lab', current_date - 45, current_date - 15, 'draft', 500, 100, 600, 0, 600, 'En cours de preparation', false),
  ('FAC-2024-031', (select id from customers where name = 'Entreprise XYZ' limit 1), 'Entreprise XYZ', current_date - 50, current_date - 20, 'cancelled', 1000, 200, 1200, 0, 1200, 'Annulee - erreur de saisie', false)
on conflict (number) do nothing;

-- ============================================
-- INVOICE LINES
-- ============================================
insert into invoice_lines (invoice_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order) values
  ((select id from invoices where number = 'FAC-2024-042' limit 1), 'Consultation technique - 1 jour', 1, 800, 20, 800, 160, 0),
  ((select id from invoices where number = 'FAC-2024-042' limit 1), 'Frais de deplacement', 1, 200, 20, 200, 40, 1),
  ((select id from invoices where number = 'FAC-2024-041' limit 1), 'Licence Logiciel Pro - 1 an', 1, 1200, 20, 1200, 240, 0),
  ((select id from invoices where number = 'FAC-2024-041' limit 1), 'Abonnement Support - 8 mois', 8, 150, 20, 1200, 240, 1),
  ((select id from invoices where number = 'FAC-2024-040' limit 1), 'Abonnement Support - 12 mois', 12, 150, 20, 1800, 360, 0),
  ((select id from invoices where number = 'FAC-2024-040' limit 1), 'Consultation technique - 2 jours', 2, 800, 20, 1600, 320, 1)
on conflict do nothing;

-- ============================================
-- PURCHASE INVOICES (Bills)
-- ============================================
insert into purchase_invoices (number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due) values
  ('ACH-2024-015', (select id from suppliers where name = 'Fournisseur GHI' limit 1), 'Fournisseur GHI', current_date - 3, current_date + 27, 'sent', 741.67, 148.33, 890, 0, 890),
  ('ACH-2024-014', (select id from suppliers where name = 'Cloud Services Pro' limit 1), 'Cloud Services Pro', current_date - 7, current_date + 8, 'sent', 375, 75, 450, 0, 450),
  ('ACH-2024-013', (select id from suppliers where name = 'Office Supplies Co' limit 1), 'Office Supplies Co', current_date - 14, current_date + 16, 'paid', 250, 50, 300, 300, 0),
  ('ACH-2024-012', (select id from suppliers where name = 'Marketing Agency' limit 1), 'Marketing Agency', current_date - 21, current_date + 24, 'sent', 1000, 200, 1200, 0, 1200),
  ('ACH-2024-011', (select id from suppliers where name = 'Fournisseur GHI' limit 1), 'Fournisseur GHI', current_date - 28, current_date - 3, 'overdue', 500, 100, 600, 0, 600),
  ('ACH-2024-010', (select id from suppliers where name = 'Cloud Services Pro' limit 1), 'Cloud Services Pro', current_date - 35, current_date - 5, 'paid', 625, 125, 750, 750, 0),
  ('ACH-2024-009', (select id from suppliers where name = 'Office Supplies Co' limit 1), 'Office Supplies Co', current_date - 42, current_date - 12, 'draft', 125, 25, 150, 0, 150)
on conflict (number) do nothing;

-- ============================================
-- BANK ACCOUNTS
-- ============================================
insert into bank_accounts (name, type, account_number, sort_code, balance, currency, bank_name, last_reconciled, connected) values
  ('Compte Courant Principal', 'chequing', 'FR7612345678901234567890123', '12345', 38500, 'EUR', 'BNP Paribas', current_date - 5, true),
  ('Compte Epargne', 'savings', 'FR7698765432109876543210987', '98765', 6700, 'EUR', 'BNP Paribas', current_date - 10, true),
  ('Carte de Credit Pro', 'credit_card', '4532XXXXXXXX1234', '00000', -1200, 'EUR', 'Visa Business', current_date - 2, true),
  ('Caisse', 'cash', 'CAISSE-001', '00000', 200, 'EUR', 'Especes', current_date - 1, false)
on conflict do nothing;

-- ============================================
-- BANK TRANSACTIONS
-- ============================================
insert into bank_transactions (account_id, date, description, reference, type, amount, category, reconciled, matched) values
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 1, 'Virement recu - Societe XYZ', 'VIR-IN-001', 'credit', 2500, 'Ventes', true, true),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 2, 'Prelevement - Cloud Services Pro', 'PRLV-001', 'debit', 75, 'Achats', true, true),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 3, 'Virement recu - Global Services', 'VIR-IN-002', 'credit', 5000, 'Ventes', true, true),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 5, 'Paiement salaires - Decembre', 'SAL-001', 'debit', 28000, 'Salaires', true, true),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 7, 'Loyer bureau - Decembre', 'LOY-001', 'debit', 1200, 'Loyer', true, true),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 10, 'Virement recu - Startup Lab', 'VIR-IN-003', 'credit', 750, 'Ventes', true, true),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 12, 'Achat materiel - Fournisseur GHI', 'ACH-001', 'debit', 890, 'Achats', false, false),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 15, 'Frais bancaires', 'FRA-001', 'debit', 15, 'Frais bancaires', false, false),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 18, 'Remboursement assurance', 'RMB-001', 'credit', 340, 'Autres', false, false),
  ((select id from bank_accounts where name = 'Compte Courant Principal' limit 1), current_date - 20, 'Abonnement logiciel - Cloud Pro', 'ABO-001', 'debit', 75, 'Abonnements', true, true),
  ((select id from bank_accounts where name = 'Compte Epargne' limit 1), current_date - 30, 'Virement epargne mensuel', 'VIR-EP-001', 'debit', 500, 'Transfert', true, true),
  ((select id from bank_accounts where name = 'Carte de Credit Pro' limit 1), current_date - 5, 'Repas client - Restaurant', 'CB-001', 'debit', 85, 'Repas', false, false),
  ((select id from bank_accounts where name = 'Carte de Credit Pro' limit 1), current_date - 10, 'Achat fournitures bureau', 'CB-002', 'debit', 120, 'Fournitures', true, true),
  ((select id from bank_accounts where name = 'Carte de Credit Pro' limit 1), current_date - 15, 'Abonnement en ligne', 'CB-003', 'debit', 35, 'Abonnements', true, true),
  ((select id from bank_accounts where name = 'Caisse' limit 1), current_date - 1, 'Encaissement espece - vente directe', 'CAI-001', 'credit', 50, 'Ventes', true, true)
on conflict do nothing;

-- ============================================
-- BANK RULES
-- ============================================
insert into bank_rules (name, condition_field, condition_operator, condition_value, action_category, action_account_code, action_vat_rate, priority, active) values
  ('Salaires mensuels', 'description', 'contains', 'SALAIRES', 'Salaires', '641000', 0, 1, true),
  ('Loyer bureau', 'description', 'contains', 'LOYER', 'Loyer', '613000', 20, 2, true),
  ('Frais bancaires', 'description', 'contains', 'FRAIS BANCAIRES', 'Frais bancaires', '627000', 0, 3, true),
  ('Abonnements logiciels', 'description', 'contains', 'ABONNEMENT', 'Abonnements', '611000', 20, 4, true),
  ('Virements clients', 'type', 'equals', 'credit', 'Ventes', '707000', 20, 5, true)
on conflict do nothing;

-- ============================================
-- QUOTES
-- ============================================
insert into quotes (number, customer_id, customer_name, date, expiry_date, status, subtotal, vat_total, total, notes) values
  ('DEV-2024-008', (select id from customers where name = 'Global Services' limit 1), 'Global Services', current_date, current_date + 30, 'sent', 5000, 1000, 6000, 'Proposition pour contrat annuel'),
  ('DEV-2024-007', (select id from customers where name = 'Startup Lab' limit 1), 'Startup Lab', current_date - 10, current_date + 20, 'accepted', 2500, 500, 3000, 'Devis accepte - en cours de facturation'),
  ('DEV-2024-006', (select id from customers where name = 'Societe ABC' limit 1), 'Societe ABC', current_date - 20, current_date - 5, 'expired', 1500, 300, 1800, 'Devis expire sans reponse'),
  ('DEV-2024-005', (select id from customers where name = 'Entreprise DEF' limit 1), 'Entreprise DEF', current_date - 30, current_date - 10, 'rejected', 3000, 600, 3600, 'Devis refuse - budget insuffisant')
on conflict (number) do nothing;

-- ============================================
-- CREDIT NOTES
-- ============================================
insert into credit_notes (number, customer_id, customer_name, date, status, subtotal, vat_total, total, reason) values
  ('AV-2024-003', (select id from customers where name = 'Societe ABC' limit 1), 'Societe ABC', current_date - 15, 'applied', 100, 20, 120, 'Remise commerciale - erreur de facturation'),
  ('AV-2024-002', (select id from customers where name = 'Entreprise XYZ' limit 1), 'Entreprise XYZ', current_date - 30, 'draft', 250, 50, 300, 'Retour produit - en cours de validation')
on conflict (number) do nothing;

-- ============================================
-- JOURNAL ENTRIES
-- ============================================
insert into journal_entries (number, date, description, reference, status, total_debit, total_credit) values
  ('JN-2024-050', current_date - 1, 'Encaissement facture FAC-2024-041 - Entreprise XYZ', 'ENC-041', 'posted', 2500, 2500),
  ('JN-2024-049', current_date - 2, 'Paiement fournisseur Cloud Services Pro', 'PAY-CSPro', 'posted', 450, 450),
  ('JN-2024-048', current_date - 3, 'Vente marchandises - Global Services', 'SALE-GS', 'posted', 5000, 5000),
  ('JN-2024-047', current_date - 5, 'Salaire Decembre 2024', 'PAYROLL-DEC', 'posted', 28000, 28000),
  ('JN-2024-046', current_date - 7, 'Loyer bureau - Decembre', 'RENT-DEC', 'posted', 1200, 1200),
  ('JN-2024-045', current_date - 10, 'Amortissement materiel Q4', 'AMORT-Q4', 'posted', 2500, 2500),
  ('JN-2024-044', current_date - 12, 'Achat fournitures bureau', 'ACH-FORN', 'posted', 120, 120),
  ('JN-2024-043', current_date - 15, 'Regularisation TVA Q3', 'VAT-Q3', 'posted', 5600, 5600),
  ('JN-2024-042', current_date - 20, 'Provision clients douteux', 'PROV-001', 'draft', 800, 800),
  ('JN-2024-041', current_date - 25, 'Honoraires comptable', 'HON-CPT', 'posted', 600, 600),
  ('JN-2024-040', current_date - 28, 'Subvention exploitation recue', 'SUB-EXP', 'posted', 2000, 2000)
on conflict (number) do nothing;

-- ============================================
-- JOURNAL LINES
-- ============================================
insert into journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order) values
  -- JN-2024-050: Encaissement facture XYZ
  ((select id from journal_entries where number = 'JN-2024-050' limit 1), '512000', 'Banque', 2500, 0, 'Encaissement client XYZ', 0),
  ((select id from journal_entries where number = 'JN-2024-050' limit 1), '411000', 'Clients', 0, 2500, 'Solde facture FAC-2024-041', 1),
  -- JN-2024-049: Paiement fournisseur
  ((select id from journal_entries where number = 'JN-2024-049' limit 1), '401000', 'Fournisseurs', 450, 0, 'Paiement Cloud Services Pro', 0),
  ((select id from journal_entries where number = 'JN-2024-049' limit 1), '512000', 'Banque', 0, 450, 'Prelevement bancaire', 1),
  -- JN-2024-048: Vente Global Services
  ((select id from journal_entries where number = 'JN-2024-048' limit 1), '411000', 'Clients', 5000, 0, 'Facture Global Services', 0),
  ((select id from journal_entries where number = 'JN-2024-048' limit 1), '707000', 'Ventes de marchandises', 0, 4166.67, 'Vente HT', 1),
  ((select id from journal_entries where number = 'JN-2024-048' limit 1), '445710', 'TVA collectee 20%', 0, 833.33, 'TVA collectee', 2),
  -- JN-2024-047: Salaires
  ((select id from journal_entries where number = 'JN-2024-047' limit 1), '641000', 'Salaires', 28000, 0, 'Salaires bruts Decembre', 0),
  ((select id from journal_entries where number = 'JN-2024-047' limit 1), '421000', 'Personnel - remunerations dues', 0, 28000, 'Net a payer', 1),
  -- JN-2024-046: Loyer
  ((select id from journal_entries where number = 'JN-2024-046' limit 1), '613000', 'Locations', 1000, 0, 'Loyer bureau HT', 0),
  ((select id from journal_entries where number = 'JN-2024-046' limit 1), '445660', 'TVA deductible sur biens et services', 200, 0, 'TVA deductible', 1),
  ((select id from journal_entries where number = 'JN-2024-046' limit 1), '512000', 'Banque', 0, 1200, 'Prelevement loyer', 2),
  -- JN-2024-045: Amortissement
  ((select id from journal_entries where number = 'JN-2024-045' limit 1), '681100', 'Dotations aux amortissements', 2500, 0, 'Amortissement Q4', 0),
  ((select id from journal_entries where number = 'JN-2024-045' limit 1), '281000', 'Amortissements des immobilisations', 0, 2500, 'Amortissement cumule', 1),
  -- JN-2024-044: Achat fournitures
  ((select id from journal_entries where number = 'JN-2024-044' limit 1), '607000', 'Achats de marchandises', 100, 0, 'Fournitures bureau HT', 0),
  ((select id from journal_entries where number = 'JN-2024-044' limit 1), '445660', 'TVA deductible sur biens et services', 20, 0, 'TVA deductible', 1),
  ((select id from journal_entries where number = 'JN-2024-044' limit 1), '514000', 'Banque - Carte de credit pro', 0, 120, 'Paiement CB', 2),
  -- JN-2024-043: Regularisation TVA
  ((select id from journal_entries where number = 'JN-2024-043' limit 1), '445710', 'TVA collectee 20%', 17120, 0, 'TVA collectee Q3', 0),
  ((select id from journal_entries where number = 'JN-2024-043' limit 1), '445660', 'TVA deductible sur biens et services', 0, 9800, 'TVA deductible Q3', 1),
  ((select id from journal_entries where number = 'JN-2024-043' limit 1), '445200', 'TVA due intracommunautaire', 0, 1720, 'TVA a payer', 2),
  ((select id from journal_entries where number = 'JN-2024-043' limit 1), '512000', 'Banque', 5600, 0, 'Reglement TVA Q3', 3),
  -- JN-2024-042: Provision (draft)
  ((select id from journal_entries where number = 'JN-2024-042' limit 1), '681700', 'Dotations aux provisions', 800, 0, 'Provision client douteux', 0),
  ((select id from journal_entries where number = 'JN-2024-042' limit 1), '491000', 'Provisions pour depréciation des comptes clients', 0, 800, 'Provision', 1),
  -- JN-2024-041: Honoraires
  ((select id from journal_entries where number = 'JN-2024-041' limit 1), '622000', 'Honoraires', 500, 0, 'Honoraires comptable HT', 0),
  ((select id from journal_entries where number = 'JN-2024-041' limit 1), '445660', 'TVA deductible sur biens et services', 100, 0, 'TVA deductible', 1),
  ((select id from journal_entries where number = 'JN-2024-041' limit 1), '512000', 'Banque', 0, 600, 'Paiement honoraires', 2),
  -- JN-2024-040: Subvention
  ((select id from journal_entries where number = 'JN-2024-040' limit 1), '512000', 'Banque', 2000, 0, 'Recu subvention exploitation', 0),
  ((select id from journal_entries where number = 'JN-2024-040' limit 1), '740000', 'Subventions d''exploitation', 0, 2000, 'Subvention recue', 1)
on conflict do nothing;

-- ============================================
-- VAT RETURNS
-- ============================================
insert into vat_returns (period_start, period_end, status, box1_output_vat, box2_input_vat, box3_vat_due, box4_repayment_due, box5_net_vat, total_sales, total_purchases, submitted_date) values
  ('2024-10-01', '2024-12-31', 'draft', 17120, 6480, 10640, 0, 10640, 85600, 32400, null),
  ('2024-07-01', '2024-09-30', 'submitted', 15400, 5200, 10200, 0, 10200, 77000, 26000, '2024-10-15'),
  ('2024-04-01', '2024-06-30', 'paid', 14200, 4800, 9400, 0, 9400, 71000, 24000, '2024-07-10')
on conflict do nothing;

-- ============================================
-- PROJECTS
-- ============================================
insert into projects (name, description, customer_id, status, budget, actual_cost, start_date, end_date) values
  ('Migration Cloud Global Services', 'Migration infrastructure vers AWS', (select id from customers where name = 'Global Services' limit 1), 'active', 50000, 32000, '2024-09-01', '2025-03-31'),
  ('Refonte site Startup Lab', 'Refonte complete du site web', (select id from customers where name = 'Startup Lab' limit 1), 'active', 12000, 4500, '2024-11-15', '2025-02-28'),
  ('Audit securite ABC', 'Audit de securite informatique', (select id from customers where name = 'Societe ABC' limit 1), 'completed', 8000, 6500, '2024-06-01', '2024-08-31'),
  ('Support XYZ', 'Contrat de support technique', (select id from customers where name = 'Entreprise XYZ' limit 1), 'on_hold', 15000, 3000, '2024-10-01', '2025-06-30')
on conflict do nothing;

-- ============================================
-- PURCHASE CREDIT NOTES
-- ============================================
insert into purchase_credit_notes (number, supplier_id, supplier_name, date, status, subtotal, vat_total, total, reason) values
  ('AVF-2024-001', (select id from suppliers where name = 'Tech Supply Co' limit 1), 'Tech Supply Co', '2024-11-20', 'draft', 500, 100, 600, 'Produit défectueux'),
  ('AVF-2024-002', (select id from suppliers where name = 'Office Depot Pro' limit 1), 'Office Depot Pro', '2024-12-05', 'applied', 200, 40, 240, 'Retour marchandise')
on conflict do nothing;

insert into purchase_credit_lines (purchase_credit_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order) values
  ((select id from purchase_credit_notes where number = 'AVF-2024-001' limit 1), 'Écran HP 24" défectueux', 1, 500, 20, 500, 100, 0),
  ((select id from purchase_credit_notes where number = 'AVF-2024-002' limit 1), 'Ramette papier A4', 10, 20, 20, 200, 40, 0)
on conflict do nothing;

-- ============================================
-- FIXED ASSETS
-- ============================================
insert into fixed_assets (name, code, category, purchase_date, purchase_value, current_value, depreciation_method, useful_life_years, residual_value, status) values
  ('Ordinateur portable Dell', 'IMMO-001', 'Matériel informatique', '2023-01-15', 1800, 1080, 'straight_line', 5, 0, 'active'),
  ('Meubles de bureau', 'IMMO-002', 'Mobilier', '2022-06-01', 5000, 3000, 'straight_line', 10, 0, 'active'),
  ('Véhicule utilitaire', 'IMMO-003', 'Transport', '2021-03-10', 25000, 10000, 'straight_line', 5, 5000, 'active'),
  ('Logiciel comptable', 'IMMO-004', 'Logiciels', '2023-09-01', 3000, 1500, 'straight_line', 3, 0, 'active')
on conflict do nothing;

-- ============================================
-- EMPLOYEES
-- ============================================
insert into employees (name, email, phone, position, department, salary, hire_date, status) values
  ('Marie Dupont', 'marie.dupont@compta.fr', '0612345678', 'Comptable', 'Finance', 3500, '2022-03-01', 'active'),
  ('Pierre Martin', 'pierre.martin@compta.fr', '0623456789', 'Développeur', 'IT', 4200, '2023-01-15', 'active'),
  ('Sophie Bernard', 'sophie.bernard@compta.fr', '0634567890', 'Responsable RH', 'RH', 3800, '2021-09-01', 'active'),
  ('Luc Petit', 'luc.petit@compta.fr', '0645678901', 'Commercial', 'Ventes', 3000, '2024-02-01', 'active'),
  ('Julie Moreau', 'julie.moreau@compta.fr', '0656789012', 'Assistante administrative', 'Administration', 2500, '2023-06-01', 'on_leave')
on conflict do nothing;

-- ============================================
-- PAY RUNS
-- ============================================
insert into pay_runs (number, period_start, period_end, pay_date, status, gross_total, tax_total, net_total, employee_count) values
  ('PAY-2024-11', '2024-11-01', '2024-11-30', '2024-11-30', 'paid', 17000, 3910, 13090, 4),
  ('PAY-2024-12', '2024-12-01', '2024-12-31', '2024-12-31', 'approved', 17000, 3910, 13090, 4),
  ('PAY-2025-01', '2025-01-01', '2025-01-31', '2025-01-31', 'draft', 17000, 3910, 13090, 4)
on conflict do nothing;

-- ============================================
-- TIMESHEETS
-- ============================================
insert into timesheets (employee_id, date, hours, description, project_id, status) values
  ((select id from employees where name = 'Pierre Martin' limit 1), '2025-01-15', 8, 'Développement module facturation', (select id from projects where name = 'Migration Cloud Global Services' limit 1), 'approved'),
  ((select id from employees where name = 'Pierre Martin' limit 1), '2025-01-16', 7, 'Tests et debug', (select id from projects where name = 'Migration Cloud Global Services' limit 1), 'pending'),
  ((select id from employees where name = 'Marie Dupont' limit 1), '2025-01-15', 4, 'Saisie comptable', null, 'approved'),
  ((select id from employees where name = 'Luc Petit' limit 1), '2025-01-15', 6, 'Visite client ABC', (select id from projects where name = 'Audit securite ABC' limit 1), 'pending')
on conflict do nothing;

-- ============================================
-- STOCK MOVEMENTS
-- ============================================
insert into stock_movements (product_id, type, quantity, reference, date) values
  ((select id from products where name = 'Ordinateur portable Pro' limit 1), 'in', 50, 'BC-2024-001', '2024-10-01'),
  ((select id from products where name = 'Ordinateur portable Pro' limit 1), 'out', 5, 'BL-2024-010', '2024-11-15'),
  ((select id from products where name = 'Souris sans fil' limit 1), 'in', 100, 'BC-2024-002', '2024-10-15'),
  ((select id from products where name = 'Souris sans fil' limit 1), 'out', 20, 'BL-2024-011', '2024-12-01'),
  ((select id from products where name = 'Clavier mécanique' limit 1), 'adjustment', 30, 'INV-2024', '2024-12-31')
on conflict do nothing;

-- ============================================
-- CURRENCIES
-- ============================================
insert into currencies (code, name, symbol, exchange_rate, is_base) values
  ('EUR', 'Euro', '€', 1.0, true),
  ('USD', 'Dollar américain', '$', 1.0850, false),
  ('GBP', 'Livre sterling', '£', 0.8530, false),
  ('CHF', 'Franc suisse', 'CHF', 0.9520, false),
  ('MAD', 'Dirham marocain', 'DH', 10.8500, false)
on conflict do nothing;
