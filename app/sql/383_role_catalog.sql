-- ═══════════════════════════════════════════════════════════════════════════
-- 383 — role_catalog : le CATALOGUE FERMÉ des rôles (LOT 1-B, LOC1-04)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Les deux catalogues qui rendent la neutralité POSSIBLE : au lieu
-- de code des numéros de comptes (`310000`, `601000`…), le code demande un
-- RÔLE (`CLIENTS`, `TVA_COLLECTEE`, `VENTES_MARCHANDISES`). Chaque pack mappe
-- ses rôles vers SES comptes (`pack_account_roles`). C'est le mécanisme des
-- leaders : *SystemAccounts* de Xero, `property_*_account_id` d'Odoo, l'attribut
-- « role » du *group chart* de SAP. Cahier §5, tâche LOC1-04 (annexe B : 67 rôles
-- de comptes, 8 rôles de journaux).
--
-- CATALOGUE FERMÉ. Un rôle qui n'est pas ici est refusé par la clé étrangère des
-- tables du pack : on ne peut pas mapper un rôle qu'on n'a pas nommé. Toute
-- fonction qui a besoin d'un nouveau compte AJOUTE un rôle ici, elle ne code
-- jamais un numéro.
--
-- GLOBALES, SANS `tenant_id` (comme les autres tables de pack) : lecture par
-- tout utilisateur connecté, écriture par `service_role` seul.
--
-- REJOUABLE : `CREATE TABLE IF NOT EXISTS`, `INSERT … ON CONFLICT DO NOTHING`,
-- `DROP CONSTRAINT IF EXISTS` + `ADD`, `DROP POLICY IF EXISTS` + `CREATE`.
--
-- Numéro pris le 2026-10-05T20:19:03.889Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Les deux catalogues
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS account_role_catalog (
  role         text PRIMARY KEY,
  family       text NOT NULL,                 -- tiers, taxes, paie, tresorerie, gestion, stock, immobilisations, capitaux, financier, divers
  normal_side  text NOT NULL,
  description  text,
  required_for text[] NOT NULL DEFAULT '{}',  -- modules qui exigent le rôle
  CONSTRAINT account_role_catalog_role_check   CHECK (role ~ '^[A-Z0-9_]+$'),
  CONSTRAINT account_role_catalog_side_check   CHECK (normal_side IN ('debit','credit'))
);

CREATE TABLE IF NOT EXISTS journal_role_catalog (
  role         text PRIMARY KEY,
  journal_type text NOT NULL,
  description  text,
  required_for text[] NOT NULL DEFAULT '{}',
  CONSTRAINT journal_role_catalog_role_check CHECK (role ~ '^[A-Z0-9_]+$')
);

-- ─────────────────────────────────────────────────────────────
-- 2. RLS : lecture par tout connecté, écriture par service_role
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['account_role_catalog','journal_role_catalog'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'select_' || t, t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING (auth.uid() IS NOT NULL)', 'select_' || t, t);
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 3. Les tables du pack ne peuvent mapper QU'UN rôle du catalogue
-- ─────────────────────────────────────────────────────────────
ALTER TABLE pack_account_roles DROP CONSTRAINT IF EXISTS pack_account_roles_role_fkey;
ALTER TABLE pack_account_roles ADD CONSTRAINT pack_account_roles_role_fkey
  FOREIGN KEY (role) REFERENCES account_role_catalog(role);

ALTER TABLE pack_journal_roles DROP CONSTRAINT IF EXISTS pack_journal_roles_role_fkey;
ALTER TABLE pack_journal_roles ADD CONSTRAINT pack_journal_roles_role_fkey
  FOREIGN KEY (role) REFERENCES journal_role_catalog(role);

-- ─────────────────────────────────────────────────────────────
-- 4. Les 67 rôles de comptes (annexe B.1 du cahier)
-- ─────────────────────────────────────────────────────────────
INSERT INTO account_role_catalog (role, family, normal_side, required_for) VALUES
  ('CLIENTS',                          'tiers',   'debit',  ARRAY['sales','pos']),
  ('CLIENTS_DOUTEUX',                  'tiers',   'debit',  ARRAY['sales']),
  ('CLIENTS_EFFETS_A_RECEVOIR',        'tiers',   'debit',  ARRAY['sales']),
  ('CLIENTS_AVANCES_RECUES',           'tiers',   'credit', ARRAY['sales']),
  ('CLIENTS_FACTURES_A_ETABLIR',       'tiers',   'debit',  ARRAY['closing']),
  ('FOURNISSEURS',                     'tiers',   'credit', ARRAY['purchases']),
  ('FOURNISSEURS_IMMOBILISATIONS',     'tiers',   'credit', ARRAY['assets']),
  ('FOURNISSEURS_AVANCES_VERSEES',     'tiers',   'debit',  ARRAY['purchases']),
  ('FOURNISSEURS_FACTURES_NON_PARVENUES','tiers', 'credit', ARRAY['closing']),
  ('FOURNISSEURS_EFFETS_A_PAYER',      'tiers',   'credit', ARRAY['purchases']),
  ('TVA_COLLECTEE',                    'taxes',   'credit', ARRAY['sales','pos']),
  ('TVA_DEDUCTIBLE_BIENS_SERVICES',    'taxes',   'debit',  ARRAY['purchases']),
  ('TVA_DEDUCTIBLE_IMMOBILISATIONS',   'taxes',   'debit',  ARRAY['assets']),
  ('TVA_A_DECAISSER',                  'taxes',   'credit', ARRAY['sales']),
  ('CREDIT_TVA',                       'taxes',   'debit',  ARRAY['sales']),
  ('TVA_EN_ATTENTE',                   'taxes',   'credit', ARRAY['sales']),
  ('IMPOT_BENEFICES_CHARGE',           'taxes',   'debit',  ARRAY['closing']),
  ('ETAT_IMPOT_BENEFICES',             'taxes',   'credit', ARRAY['closing']),
  ('ETAT_RETENUES_A_LA_SOURCE',        'taxes',   'credit', ARRAY['purchases']),
  ('IMPOTS_TAXES_CHARGE',              'taxes',   'debit',  ARRAY['purchases']),
  ('ETAT_IMPOT_SALAIRES',              'paie',    'credit', ARRAY['payroll']),
  ('SALAIRES_BRUTS',                   'paie',    'debit',  ARRAY['payroll']),
  ('CHARGES_SOCIALES_PATRONALES',      'paie',    'debit',  ARRAY['payroll']),
  ('PERSONNEL_REMUNERATIONS_DUES',     'paie',    'credit', ARRAY['payroll']),
  ('PERSONNEL_AVANCES',                'paie',    'debit',  ARRAY['payroll']),
  ('ORGANISME_SOCIAL',                 'paie',    'credit', ARRAY['payroll']),
  ('BANQUE',                           'tresorerie','debit', ARRAY['sales','purchases']),
  ('CAISSE',                           'tresorerie','debit', ARRAY['sales']),
  ('CAISSE_POS',                       'tresorerie','debit', ARRAY['pos']),
  ('VIREMENTS_INTERNES',               'tresorerie','debit', ARRAY['sales']),
  ('MOYENS_PAIEMENT_A_ENCAISSER',      'tresorerie','debit', ARRAY['sales','pos']),
  ('VENTES_MARCHANDISES',              'gestion', 'credit', ARRAY['sales','pos']),
  ('VENTES_PRODUITS_FINIS',            'gestion', 'credit', ARRAY['sales','manufacturing']),
  ('PRESTATIONS_SERVICES',             'gestion', 'credit', ARRAY['sales'])
ON CONFLICT (role) DO NOTHING;

INSERT INTO account_role_catalog (role, family, normal_side, required_for) VALUES
  ('RRR_ACCORDES',                     'gestion', 'debit',  ARRAY['sales']),
  ('ACHATS_MARCHANDISES',              'gestion', 'debit',  ARRAY['purchases']),
  ('ACHATS_MATIERES',                  'gestion', 'debit',  ARRAY['purchases','manufacturing']),
  ('SERVICES_EXTERIEURS',              'gestion', 'debit',  ARRAY['purchases']),
  ('SOUS_TRAITANCE',                   'gestion', 'debit',  ARRAY['manufacturing']),
  ('RRR_OBTENUS',                      'gestion', 'credit', ARRAY['purchases']),
  ('ESCOMPTES_ACCORDES',               'financier','debit', ARRAY['sales']),
  ('ESCOMPTES_OBTENUS',                'financier','credit', ARRAY['purchases']),
  ('GAINS_CHANGE',                     'financier','credit', ARRAY['fx']),
  ('PERTES_CHANGE',                    'financier','debit', ARRAY['fx']),
  ('ECART_CONVERSION_ACTIF',           'financier','debit', ARRAY['fx','closing']),
  ('ECART_CONVERSION_PASSIF',          'financier','credit', ARRAY['fx','closing']),
  ('PERTES_CREANCES_IRRECOUVRABLES',   'gestion', 'debit',  ARRAY['sales']),
  ('STOCK_MARCHANDISES',               'stock',   'debit',  ARRAY['stock']),
  ('STOCK_MATIERES',                   'stock',   'debit',  ARRAY['stock','manufacturing']),
  ('STOCK_PRODUITS_FINIS',             'stock',   'debit',  ARRAY['manufacturing']),
  ('VARIATION_STOCK_MARCHANDISES',     'stock',   'debit',  ARRAY['stock']),
  ('VARIATION_STOCK_MATIERES',         'stock',   'debit',  ARRAY['stock']),
  ('PRODUCTION_STOCKEE',               'stock',   'credit', ARRAY['manufacturing']),
  ('IMMOBILISATIONS',                  'immobilisations','debit',  ARRAY['assets']),
  ('AMORTISSEMENTS',                   'immobilisations','credit', ARRAY['assets']),
  ('DOTATIONS_AMORTISSEMENTS',         'immobilisations','debit',  ARRAY['assets']),
  ('VALEUR_COMPTABLE_CESSIONS',        'immobilisations','debit',  ARRAY['assets']),
  ('PRODUITS_CESSIONS',                'immobilisations','credit', ARRAY['assets']),
  ('REPRISE_SUBVENTIONS_INVESTISSEMENT','immobilisations','credit', ARRAY['assets']),
  ('RESULTAT_BENEFICE',                'capitaux','credit', ARRAY['closing']),
  ('RESULTAT_PERTE',                   'capitaux','debit',  ARRAY['closing']),
  ('REPORT_A_NOUVEAU_CREDITEUR',       'capitaux','credit', ARRAY['closing']),
  ('REPORT_A_NOUVEAU_DEBITEUR',        'capitaux','debit',  ARRAY['closing']),
  ('RESERVE_LEGALE',                   'capitaux','credit', ARRAY['closing']),
  ('AUTRES_RESERVES',                  'capitaux','credit', ARRAY['closing']),
  ('ASSOCIES_DIVIDENDES_A_PAYER',      'capitaux','credit', ARRAY['closing']),
  ('COMPTE_ATTENTE',                   'divers',  'debit',  ARRAY['import','bank'])
ON CONFLICT (role) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 5. Les 8 rôles de journaux (annexe B.2 du cahier)
-- ─────────────────────────────────────────────────────────────
INSERT INTO journal_role_catalog (role, journal_type, required_for) VALUES
  ('JOURNAL_VENTES',      'sale',     ARRAY['sales']),
  ('JOURNAL_ACHATS',      'purchase', ARRAY['purchases']),
  ('JOURNAL_BANQUE',      'bank',     ARRAY['bank','sales','purchases']),
  ('JOURNAL_CAISSE',      'cash',     ARRAY['pos','sales']),
  ('JOURNAL_OD',          'general',  ARRAY['closing']),
  ('JOURNAL_A_NOUVEAUX',  'opening',  ARRAY['closing']),
  ('JOURNAL_STOCK',       'general',  ARRAY['stock']),
  ('JOURNAL_PAIE',        'general',  ARRAY['payroll'])
ON CONFLICT (role) DO NOTHING;
