-- ============================================
-- SEED DEMO DATA FOR 2025 (closed) AND 2026 (in-progress)
-- Run this in Supabase Dashboard > SQL Editor
-- It seeds data for the first tenant found in the tenants table
-- ============================================

DO $$
DECLARE
  v_tenant_id uuid;
  v_fy_2025_id uuid;
  v_fy_2026_id uuid;
  v_customer_1 uuid;
  v_customer_2 uuid;
  v_customer_3 uuid;
  v_customer_4 uuid;
  v_customer_5 uuid;
  v_supplier_1 uuid;
  v_supplier_2 uuid;
  v_supplier_3 uuid;
  v_product_1 uuid;
  v_product_2 uuid;
  v_product_3 uuid;
  v_bank_1 uuid;
  v_bank_2 uuid;
  v_warehouse_1 uuid;
  v_warehouse_2 uuid;
  v_warehouse_3 uuid;
  v_period_ids uuid[];
  v_period_2026_ids uuid[];
  v_je_id uuid;
  v_month int;
  v_date date;
  v_tmp_id uuid;
BEGIN
  SELECT id INTO v_tenant_id FROM tenants ORDER BY created_at DESC LIMIT 1;
  IF v_tenant_id IS NULL THEN
    RAISE NOTICE 'No tenant found. Please create a tenant first.';
    RETURN;
  END IF;
  RAISE NOTICE 'Seeding data for tenant: %', v_tenant_id;

  -- ============================================
  -- 0. CLEANUP existing seed data for this tenant
  -- ============================================
  DELETE FROM journal_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_entries WHERE tenant_id = v_tenant_id;
  DELETE FROM bank_transactions WHERE tenant_id = v_tenant_id;
  DELETE FROM vat_returns WHERE tenant_id = v_tenant_id;
  DELETE FROM invoice_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM invoices WHERE tenant_id = v_tenant_id;
  DELETE FROM purchase_invoice_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM purchase_invoices WHERE tenant_id = v_tenant_id;
  DELETE FROM fiscal_periods WHERE tenant_id = v_tenant_id;
  DELETE FROM fiscal_years WHERE tenant_id = v_tenant_id;
  DELETE FROM bank_accounts WHERE tenant_id = v_tenant_id;
  DELETE FROM products WHERE tenant_id = v_tenant_id;
  DELETE FROM customers WHERE tenant_id = v_tenant_id;
  DELETE FROM suppliers WHERE tenant_id = v_tenant_id;
  DELETE FROM stock_movements WHERE tenant_id = v_tenant_id;
  DELETE FROM stock_quantities WHERE tenant_id = v_tenant_id;
  DELETE FROM warehouses WHERE tenant_id = v_tenant_id;
  DELETE FROM chart_accounts WHERE tenant_id = v_tenant_id;
  -- Also clean up products with our seed SKUs from any tenant (SKU is globally unique)
  DELETE FROM products WHERE sku IN ('SRV-001', 'PROD-ERP', 'SRV-FORM');
  -- Also clean up any leftover seed data from default tenant from previous runs
  DELETE FROM journal_lines WHERE journal_id IN (SELECT id FROM journal_entries WHERE number LIKE '%-2025-%' OR number LIKE '%-2026-%');
  DELETE FROM journal_entries WHERE number LIKE 'VT-2025-%' OR number LIKE 'VT-2026-%' OR number LIKE 'AC-2025-%' OR number LIKE 'AC-2026-%' OR number LIKE 'BQ-2025-%' OR number LIKE 'BQ-2026-%' OR number LIKE 'OD-2025-%' OR number LIKE 'OD-2026-%';
  DELETE FROM bank_transactions WHERE reference LIKE 'FAC-2025-%' OR reference LIKE 'FAC-2026-%' OR reference LIKE 'FAC-FOU-2025-%' OR reference LIKE 'FAC-FOU-2026-%';
  DELETE FROM invoices WHERE number LIKE 'FAC-2025-%' OR number LIKE 'FAC-2026-%';
  DELETE FROM purchase_invoices WHERE number LIKE 'FAC-FOU-2025-%' OR number LIKE 'FAC-FOU-2026-%';
  DELETE FROM vat_returns WHERE period_start IN ('2025-01-01', '2025-04-01', '2025-07-01', '2025-10-01');
  -- Clean up fiscal years/periods with seed codes from any tenant (code is globally unique)
  DELETE FROM fiscal_periods WHERE fiscal_year_id IN (SELECT id FROM fiscal_years WHERE code IN ('EX-2025', 'EX-2026'));
  DELETE FROM fiscal_years WHERE code IN ('EX-2025', 'EX-2026');
  -- Clean up journals with seed codes (code is globally unique)
  DELETE FROM entry_templates WHERE journal_code IN ('VT', 'AC', 'BQ', 'OD');
  DELETE FROM journals WHERE code IN ('VT', 'AC', 'BQ', 'OD');
  -- Clean up third party accounts with seed codes (code is globally unique)
  DELETE FROM third_party_accounts WHERE code LIKE 'C-%' OR code LIKE 'F-%';
  RAISE NOTICE 'Cleanup done. Re-seeding fresh data.';

  -- ============================================
  -- 1. CHART OF ACCOUNTS
  -- ============================================
  INSERT INTO chart_accounts (code, name, type, tenant_id)
  VALUES
    -- Classe 1 - Capitaux
    ('101000', 'Capital social', 'equity', v_tenant_id),
    ('101100', 'Capital non appele', 'equity', v_tenant_id),
    ('104000', 'Primes liees au capital social', 'equity', v_tenant_id),
    ('106000', 'Reserves', 'equity', v_tenant_id),
    ('106100', 'Reserve legale', 'equity', v_tenant_id),
    ('106800', 'Autres reserves', 'equity', v_tenant_id),
    ('108000', 'Compte de l exploitant', 'equity', v_tenant_id),
    ('109000', 'Actionnaires - capital souscrit non appele', 'equity', v_tenant_id),
    ('110000', 'Report a nouveau (solde crediteur)', 'equity', v_tenant_id),
    ('119000', 'Report a nouveau (solde debiteur)', 'equity', v_tenant_id),
    ('120000', 'Resultat de l exercice (benefice)', 'equity', v_tenant_id),
    ('129000', 'Resultat de l exercice (perte)', 'equity', v_tenant_id),
    ('151000', 'Provisions pour risques', 'liability', v_tenant_id),
    ('153000', 'Provisions pour pensions', 'liability', v_tenant_id),
    ('158000', 'Autres provisions pour charges', 'liability', v_tenant_id),
    ('163000', 'Emprunts aupres des etablissements de credit', 'liability', v_tenant_id),
    ('164000', 'Emprunts aupres des autres partenaires', 'liability', v_tenant_id),
    ('165000', 'Depots et cautionnements recus', 'liability', v_tenant_id),
    ('168000', 'Autres emprunts et dettes assimilees', 'liability', v_tenant_id),
    ('171000', 'Dettes rattachees a des participations', 'liability', v_tenant_id),
    ('181000', 'Comptes de liaison etablissements', 'liability', v_tenant_id),
    ('186000', 'Biens en credit-bail', 'liability', v_tenant_id),
    ('187000', 'Biens en credit-bail - contrepartie', 'liability', v_tenant_id),
    ('188000', 'Biens en location-vente', 'liability', v_tenant_id),
    ('189000', 'Biens en location-vente - contrepartie', 'liability', v_tenant_id),

    -- Classe 2 - Immobilisations
    ('201000', 'Frais d etablissement', 'asset', v_tenant_id),
    ('205000', 'Concessions, brevets, licences, logiciels', 'asset', v_tenant_id),
    ('206000', 'Droit au bail', 'asset', v_tenant_id),
    ('207000', 'Fonds commercial', 'asset', v_tenant_id),
    ('208000', 'Autres immobilisations incorporelles', 'asset', v_tenant_id),
    ('210000', 'Terrains', 'asset', v_tenant_id),
    ('211000', 'Agencements et ameliororations de terrains', 'asset', v_tenant_id),
    ('212000', 'Constructions', 'asset', v_tenant_id),
    ('213000', 'Constructions sur sol d autrui', 'asset', v_tenant_id),
    ('215000', 'Installations techniques, materiels et outillage', 'asset', v_tenant_id),
    ('215400', 'Materiel industriel', 'asset', v_tenant_id),
    ('218000', 'Materiel informatique', 'asset', v_tenant_id),
    ('218100', 'Materiel de bureau et informatique', 'asset', v_tenant_id),
    ('218200', 'Mobilier', 'asset', v_tenant_id),
    ('218300', 'Materiel de bureau', 'asset', v_tenant_id),
    ('218400', 'Materiel et outillage', 'asset', v_tenant_id),
    ('218500', 'Embages et equipements', 'asset', v_tenant_id),
    ('220000', 'Immobilisations corporelles en cours', 'asset', v_tenant_id),
    ('230000', 'Immobilisations en cours - incorporelles', 'asset', v_tenant_id),
    ('231000', 'Immobilisations en cours - corporelles', 'asset', v_tenant_id),
    ('238000', 'Avances et acomptes verses sur commandes', 'asset', v_tenant_id),
    ('240000', 'Participations et creances rattachees', 'asset', v_tenant_id),
    ('250000', 'Titres de participation', 'asset', v_tenant_id),
    ('260000', 'Titres immobilises', 'asset', v_tenant_id),
    ('270000', 'Participations et creances rattachees (droit de propriete)', 'asset', v_tenant_id),
    ('271000', 'Titres immobilises (droit de propriete)', 'asset', v_tenant_id),
    ('275000', 'Depots et cautionnements verses', 'asset', v_tenant_id),
    ('280000', 'Amortissements des immobilisations incorporelles', 'asset', v_tenant_id),
    ('280500', 'Amortissements des concessions, brevets, licences, logiciels', 'asset', v_tenant_id),
    ('281000', 'Amortissements des immobilisations corporelles', 'asset', v_tenant_id),
    ('281200', 'Amortissements des constructions', 'asset', v_tenant_id),
    ('281500', 'Amortissements des installations techniques', 'asset', v_tenant_id),
    ('281800', 'Amortissements du materiel', 'asset', v_tenant_id),
    ('290000', 'Depreciations des immobilisations incorporelles', 'asset', v_tenant_id),
    ('291000', 'Depreciations des immobilisations corporelles', 'asset', v_tenant_id),
    ('293000', 'Depreciations des immobilisations en cours', 'asset', v_tenant_id),
    ('296000', 'Depreciations des participations et creances rattachees', 'asset', v_tenant_id),
    ('297000', 'Depreciations des autres immobilisations financieres', 'asset', v_tenant_id),

    -- Classe 3 - Stocks
    ('310000', 'Matieres premieres (et fournitures)', 'asset', v_tenant_id),
    ('320000', 'Matieres consommables', 'asset', v_tenant_id),
    ('321000', 'Matieres consommables', 'asset', v_tenant_id),
    ('322000', 'Fournitures consommables', 'asset', v_tenant_id),
    ('330000', 'En-cours de production de biens', 'asset', v_tenant_id),
    ('340000', 'Etudes en cours', 'asset', v_tenant_id),
    ('345000', 'Travaux en cours', 'asset', v_tenant_id),
    ('350000', 'Produits intermediaires et finis', 'asset', v_tenant_id),
    ('351000', 'Produits intermediaires', 'asset', v_tenant_id),
    ('352000', 'Produits finis', 'asset', v_tenant_id),
    ('354000', 'Produits residuels', 'asset', v_tenant_id),
    ('355000', 'Produits finis (group A)', 'asset', v_tenant_id),
    ('358000', 'Produits finis (group B)', 'asset', v_tenant_id),
    ('360000', 'Stocks provenant d immobilisations', 'asset', v_tenant_id),
    ('370000', 'Stocks de marchandises', 'asset', v_tenant_id),
    ('371000', 'Marchandises (group A)', 'asset', v_tenant_id),
    ('372000', 'Marchandises (group B)', 'asset', v_tenant_id),
    ('380000', 'Stocks a tres rapide rotation', 'asset', v_tenant_id),
    ('390000', 'Depreciations des stocks', 'asset', v_tenant_id),
    ('391000', 'Depreciations des matieres premieres', 'asset', v_tenant_id),
    ('392000', 'Depreciations des matieres consommables', 'asset', v_tenant_id),
    ('393000', 'Depreciations des en-cours de production', 'asset', v_tenant_id),
    ('395000', 'Depreciations des produits', 'asset', v_tenant_id),
    ('397000', 'Depreciations des marchandises', 'asset', v_tenant_id),

    -- Classe 4 - Tiers
    ('400000', 'Fournisseurs et comptes rattaches', 'liability', v_tenant_id),
    ('401000', 'Fournisseurs', 'liability', v_tenant_id),
    ('401100', 'Fournisseurs - achats de biens et services', 'liability', v_tenant_id),
    ('401700', 'Fournisseurs - retenues de garantie', 'liability', v_tenant_id),
    ('403000', 'Fournisseurs - effets a payer', 'liability', v_tenant_id),
    ('404000', 'Fournisseurs d immobilisations', 'liability', v_tenant_id),
    ('405000', 'Fournisseurs d immobilisations - effets a payer', 'liability', v_tenant_id),
    ('408000', 'Fournisseurs - factures non parvenues', 'liability', v_tenant_id),
    ('408100', 'Fournisseurs - factures non parvenues (biens et services)', 'liability', v_tenant_id),
    ('408400', 'Fournisseurs - factures non parvenues (immobilisations)', 'liability', v_tenant_id),
    ('409000', 'Fournisseurs debiteurs', 'asset', v_tenant_id),
    ('409100', 'Fournisseurs - avances et acomptes verses', 'asset', v_tenant_id),
    ('409600', 'Fournisseurs - avoirs a recevoir', 'asset', v_tenant_id),
    ('409700', 'Fournisseurs - autres avoirs', 'asset', v_tenant_id),
    ('410000', 'Clients et comptes rattaches', 'asset', v_tenant_id),
    ('411000', 'Clients', 'asset', v_tenant_id),
    ('411100', 'Clients - ventes de biens et services', 'asset', v_tenant_id),
    ('411700', 'Clients - retenues de garantie', 'asset', v_tenant_id),
    ('413000', 'Clients - effets a recevoir', 'asset', v_tenant_id),
    ('416000', 'Clients douteux ou litigieux', 'asset', v_tenant_id),
    ('417000', 'Clients - creances sur travaux non encore facturables', 'asset', v_tenant_id),
    ('418000', 'Clients - produits non encore factures', 'asset', v_tenant_id),
    ('419000', 'Clients crediteurs', 'liability', v_tenant_id),
    ('419100', 'Clients - avances et acomptes recus', 'liability', v_tenant_id),
    ('419600', 'Clients - avoirs a etablir', 'liability', v_tenant_id),
    ('419700', 'Clients - autres avoirs a etablir', 'liability', v_tenant_id),
    ('420000', 'Personnel et comptes rattaches', 'liability', v_tenant_id),
    ('421000', 'Personnel - remunerations dues', 'liability', v_tenant_id),
    ('422000', 'Comites d entreprise, d etablissement, etc.', 'liability', v_tenant_id),
    ('424000', 'Participation des salaries aux resultats', 'liability', v_tenant_id),
    ('425000', 'Personnel - avances et acomptes', 'asset', v_tenant_id),
    ('426000', 'Personnel - depots', 'liability', v_tenant_id),
    ('427000', 'Personnel - oppositions', 'liability', v_tenant_id),
    ('428000', 'Personnel - charges a payer et produits a recevoir', 'liability', v_tenant_id),
    ('428200', 'Conges payes', 'liability', v_tenant_id),
    ('428400', 'Comptes courants des salaries', 'liability', v_tenant_id),
    ('428600', 'Personnel - produits a recevoir', 'asset', v_tenant_id),
    ('430000', 'Securite sociale et autres organismes sociaux', 'liability', v_tenant_id),
    ('431000', 'Securite sociale', 'liability', v_tenant_id),
    ('432000', 'Autres organismes sociaux', 'liability', v_tenant_id),
    ('437000', 'Autres organismes sociaux', 'liability', v_tenant_id),
    ('438000', 'Organismes sociaux - charges a payer et produits a recevoir', 'liability', v_tenant_id),
    ('438200', 'Charges de securite sociale et de prevoyance', 'liability', v_tenant_id),
    ('438600', 'Organismes sociaux - produits a recevoir', 'asset', v_tenant_id),
    ('440000', 'Etat et autres collectivites publiques', 'liability', v_tenant_id),
    ('441000', 'Etat - subventions a recevoir', 'asset', v_tenant_id),
    ('442000', 'Etat - impots et taxes recuperables', 'asset', v_tenant_id),
    ('443000', 'Operations particulieres avec l Etat', 'liability', v_tenant_id),
    ('444000', 'Etat - impots sur les benefices', 'liability', v_tenant_id),
    ('445000', 'Etat - taxes sur le chiffre d affaires', 'liability', v_tenant_id),
    ('445200', 'TVA due intracommunautaire', 'liability', v_tenant_id),
    ('445510', 'TVA a deduire (biens et services)', 'asset', v_tenant_id),
    ('445560', 'TVA a dedeductible (autres biens et services)', 'asset', v_tenant_id),
    ('445570', 'TVA deductible (immobilisations)', 'asset', v_tenant_id),
    ('445620', 'TVA due (biens et services)', 'liability', v_tenant_id),
    ('445660', 'TVA deductible', 'liability', v_tenant_id),
    ('445670', 'TVA deductible (immobilisations)', 'liability', v_tenant_id),
    ('445710', 'TVA collectee', 'liability', v_tenant_id),
    ('445800', 'TVA a regulariser', 'liability', v_tenant_id),
    ('447000', 'Autres impots, taxes et versements assimiles', 'liability', v_tenant_id),
    ('448000', 'Etat - charges a payer et produits a recevoir', 'liability', v_tenant_id),
    ('448200', 'Etat - charges a payer', 'liability', v_tenant_id),
    ('448600', 'Etat - produits a recevoir', 'asset', v_tenant_id),
    ('449000', 'Etat - subventions a reverser', 'liability', v_tenant_id),
    ('450000', 'Groupes et associes', 'liability', v_tenant_id),
    ('451000', 'Groupes', 'liability', v_tenant_id),
    ('455000', 'Associes - comptes courants', 'liability', v_tenant_id),
    ('456000', 'Associes - operations sur le capital', 'liability', v_tenant_id),
    ('456100', 'Associes - apports en nature', 'liability', v_tenant_id),
    ('456200', 'Associes - apports en numeraire', 'liability', v_tenant_id),
    ('456300', 'Associes - versements restant a effectuer', 'liability', v_tenant_id),
    ('456400', 'Associes - versements anticipes', 'asset', v_tenant_id),
    ('457000', 'Associes - dividendes a payer', 'liability', v_tenant_id),
    ('458000', 'Associes - operations faites en commun', 'liability', v_tenant_id),
    ('460000', 'Debiteurs divers et crediteurs divers', 'asset', v_tenant_id),
    ('461000', 'Debiteurs divers', 'asset', v_tenant_id),
    ('462000', 'Crediteurs divers', 'liability', v_tenant_id),
    ('463000', 'Debiteurs et crediteurs divers', 'asset', v_tenant_id),
    ('464000', 'Debiteurs et crediteurs divers', 'liability', v_tenant_id),
    ('465000', 'Comptes de liaison des etablissements', 'liability', v_tenant_id),
    ('467000', 'Autres comptes debiteurs ou crediteurs', 'asset', v_tenant_id),
    ('468000', 'Divers - charges a payer et produits a recevoir', 'liability', v_tenant_id),
    ('468600', 'Divers - produits a recevoir', 'asset', v_tenant_id),
    ('468700', 'Divers - charges a payer', 'liability', v_tenant_id),
    ('470000', 'Comptes d attente', 'liability', v_tenant_id),
    ('471000', 'Comptes d attente', 'liability', v_tenant_id),
    ('480000', 'Comptes de regularisation', 'liability', v_tenant_id),
    ('481000', 'Charges constatees d avance', 'asset', v_tenant_id),
    ('486000', 'Charges reparties dans le temps', 'asset', v_tenant_id),
    ('487000', 'Produits constates d avance', 'liability', v_tenant_id),
    ('488000', 'Comptes de repartition periodique des charges et produits', 'liability', v_tenant_id),
    ('490000', 'Depreciations des comptes de clients', 'asset', v_tenant_id),
    ('491000', 'Depreciations des comptes de clients', 'asset', v_tenant_id),
    ('495000', 'Depreciations des comptes de debiteurs divers', 'asset', v_tenant_id),
    ('496000', 'Depreciations des creances diverses', 'asset', v_tenant_id),

    -- Classe 5 - Comptes financiers
    ('500000', 'Valeurs mobilieres de placement', 'asset', v_tenant_id),
    ('501000', 'Titres de placement', 'asset', v_tenant_id),
    ('502000', 'Actions propres', 'asset', v_tenant_id),
    ('503000', 'Actions', 'asset', v_tenant_id),
    ('504000', 'Obligations', 'asset', v_tenant_id),
    ('505000', 'Bons du Tresor et bons de caisse', 'asset', v_tenant_id),
    ('506000', 'Obligations et bons emis par la societe', 'asset', v_tenant_id),
    ('507000', 'Bons du Tresor et bons de caisse (emis par la societe)', 'asset', v_tenant_id),
    ('508000', 'Autres valeurs mobilieres de placement', 'asset', v_tenant_id),
    ('509000', 'Versements restant a effectuer sur VMP', 'liability', v_tenant_id),
    ('510000', 'Banques, etablissements financiers et assimiles', 'asset', v_tenant_id),
    ('511000', 'Valeurs a l encaissement', 'asset', v_tenant_id),
    ('511100', 'Coupons echus non encaisses', 'asset', v_tenant_id),
    ('511200', 'Dividendes a encaisser', 'asset', v_tenant_id),
    ('511300', 'Effets a encaisser', 'asset', v_tenant_id),
    ('511400', 'Effets a l encaissement', 'asset', v_tenant_id),
    ('511500', 'Effets remis a l escompte', 'asset', v_tenant_id),
    ('512000', 'Banque', 'asset', v_tenant_id),
    ('512100', 'Comptes en monnaie nationale', 'asset', v_tenant_id),
    ('512400', 'Comptes en devises', 'asset', v_tenant_id),
    ('514000', 'Banques - etablissements financiers', 'asset', v_tenant_id),
    ('515000', 'Caisses du Tresor et des PTT', 'asset', v_tenant_id),
    ('516000', 'Societes de bourse', 'asset', v_tenant_id),
    ('517000', 'Banques a l etranger', 'asset', v_tenant_id),
    ('518000', 'Interets courus a payer', 'liability', v_tenant_id),
    ('518100', 'Interets courus a payer (emprunts)', 'liability', v_tenant_id),
    ('518600', 'Interets courus a recevoir', 'asset', v_tenant_id),
    ('518800', 'Interets courus a payer (autres)', 'liability', v_tenant_id),
    ('519000', 'Concours bancaires courants', 'liability', v_tenant_id),
    ('519100', 'Credit de mobilisation de creances commerciales', 'liability', v_tenant_id),
    ('519300', 'Mobilisation de creances nes a l etranger', 'liability', v_tenant_id),
    ('519400', 'Autres concours bancaires courants', 'liability', v_tenant_id),
    ('519500', 'Credit de mobilisation de creances commerciales (escompte)', 'liability', v_tenant_id),
    ('519700', 'Autres concours bancaires courants', 'liability', v_tenant_id),
    ('520000', 'Instruments de tresorerie', 'asset', v_tenant_id),
    ('521000', 'Instruments de tresorerie - droits', 'asset', v_tenant_id),
    ('522000', 'Instruments de tresorerie - obligations', 'liability', v_tenant_id),
    ('530000', 'Caisse', 'asset', v_tenant_id),
    ('531000', 'Caisse - siege social', 'asset', v_tenant_id),
    ('532000', 'Caisse - succursale ou usine', 'asset', v_tenant_id),
    ('535000', 'Caisse - etablissement a l etranger', 'asset', v_tenant_id),
    ('540000', 'Regies d avances et accréditifs', 'asset', v_tenant_id),
    ('550000', 'Caisse - monnaies etrangeres', 'asset', v_tenant_id),
    ('580000', 'Virements internes', 'asset', v_tenant_id),
    ('590000', 'Depreciations des comptes financiers', 'asset', v_tenant_id),
    ('590100', 'Depreciations des VMP', 'asset', v_tenant_id),
    ('590800', 'Depreciations des autres valeurs mobilieres', 'asset', v_tenant_id),

    -- Classe 6 - Charges
    ('600000', 'Achats (sauf 603)', 'expense', v_tenant_id),
    ('601000', 'Achats de matieres premieres', 'expense', v_tenant_id),
    ('601100', 'Achats de matieres premieres (group A)', 'expense', v_tenant_id),
    ('601200', 'Achats de matieres premieres (group B)', 'expense', v_tenant_id),
    ('602000', 'Achats de matieres consommables', 'expense', v_tenant_id),
    ('602100', 'Achats de matieres consommables', 'expense', v_tenant_id),
    ('602200', 'Achats de fournitures consommables', 'expense', v_tenant_id),
    ('602210', 'Achats de fournitures de bureau', 'expense', v_tenant_id),
    ('602220', 'Achats de fournitures d atelier', 'expense', v_tenant_id),
    ('602400', 'Achats de combustibles', 'expense', v_tenant_id),
    ('602500', 'Achats de produits d entretien', 'expense', v_tenant_id),
    ('602600', 'Achats de fournitures d emballage', 'expense', v_tenant_id),
    ('603000', 'Variations des stocks', 'expense', v_tenant_id),
    ('603100', 'Variation des stocks de matieres premieres', 'expense', v_tenant_id),
    ('603200', 'Variation des stocks de matieres et fournitures consommables', 'expense', v_tenant_id),
    ('603700', 'Variation des stocks de marchandises', 'expense', v_tenant_id),
    ('604000', 'Achats d etudes et de prestations de services', 'expense', v_tenant_id),
    ('605000', 'Achats de materiels, equipements et travaux', 'expense', v_tenant_id),
    ('606000', 'Achats non stockes de matieres et fournitures', 'expense', v_tenant_id),
    ('606100', 'Fournitures non stockables (eau, energie)', 'expense', v_tenant_id),
    ('606110', 'Eau', 'expense', v_tenant_id),
    ('606120', 'Energie (gaz, electricite)', 'expense', v_tenant_id),
    ('606130', 'Carburants', 'expense', v_tenant_id),
    ('606400', 'Fournitures d entretien non stockables', 'expense', v_tenant_id),
    ('606410', 'Produits d entretien', 'expense', v_tenant_id),
    ('606500', 'Fournitures de bureau', 'expense', v_tenant_id),
    ('606600', 'Fournitures de bureau non stockables', 'expense', v_tenant_id),
    ('606800', 'Autres achats non stockes de matieres et fournitures', 'expense', v_tenant_id),
    ('607000', 'Achats de marchandises', 'expense', v_tenant_id),
    ('607100', 'Achats de marchandises (group A)', 'expense', v_tenant_id),
    ('607200', 'Achats de marchandises (group B)', 'expense', v_tenant_id),
    ('608000', 'Frais accessoires d achats', 'expense', v_tenant_id),
    ('608100', 'Frais accessoires d achats sur matieres premieres', 'expense', v_tenant_id),
    ('608200', 'Frais accessoires d achats sur matieres consommables', 'expense', v_tenant_id),
    ('608700', 'Frais accessoires d achats sur marchandises', 'expense', v_tenant_id),
    ('609000', 'Rabais, remises et ristournes obtenus sur achats', 'expense', v_tenant_id),
    ('609100', 'Rabais, remises et ristournes sur achats de matieres premieres', 'expense', v_tenant_id),
    ('609400', 'Rabais, remises et ristournes sur achats d etudes et prestations', 'expense', v_tenant_id),
    ('609600', 'Rabais, remises et ristournes sur achats non stockes', 'expense', v_tenant_id),
    ('609700', 'Rabais, remises et ristournes sur achats de marchandises', 'expense', v_tenant_id),
    ('609800', 'Rabais, remises et ristournes sur frais accessoires d achats', 'expense', v_tenant_id),
    ('610000', 'Services exterieurs', 'expense', v_tenant_id),
    ('611000', 'Sous-traitance generale', 'expense', v_tenant_id),
    ('611100', 'Sous-traitance generale', 'expense', v_tenant_id),
    ('611200', 'Sous-traitance generale (group B)', 'expense', v_tenant_id),
    ('611400', 'Sous-traitance generale (autres)', 'expense', v_tenant_id),
    ('612000', 'Redevances de credit-bail', 'expense', v_tenant_id),
    ('612100', 'Redevances de credit-bail mobilier', 'expense', v_tenant_id),
    ('612200', 'Redevances de credit-bail immobilier', 'expense', v_tenant_id),
    ('612500', 'Redevances de contrats de location-vente', 'expense', v_tenant_id),
    ('613000', 'Locations', 'expense', v_tenant_id),
    ('613100', 'Locations de terrains', 'expense', v_tenant_id),
    ('613200', 'Locations de constructions', 'expense', v_tenant_id),
    ('613500', 'Locations de materiels et outillages', 'expense', v_tenant_id),
    ('613600', 'Locations de materiels et outillages (group B)', 'expense', v_tenant_id),
    ('614000', 'Charges locatives et de copropriete', 'expense', v_tenant_id),
    ('615000', 'Entretien et reparations', 'expense', v_tenant_id),
    ('615100', 'Entretien et reparations de biens immobiliers', 'expense', v_tenant_id),
    ('615200', 'Entretien et reparations de biens mobiliers', 'expense', v_tenant_id),
    ('615500', 'Entretien et reparations de materiels', 'expense', v_tenant_id),
    ('615600', 'Entretien et reparations de materiels de transport', 'expense', v_tenant_id),
    ('616000', 'Assurances', 'expense', v_tenant_id),
    ('616100', 'Assurances multirisques', 'expense', v_tenant_id),
    ('616200', 'Assurances obligatoires dommages construction', 'expense', v_tenant_id),
    ('616300', 'Assurances transports', 'expense', v_tenant_id),
    ('616360', 'Assurances transports (sur achats)', 'expense', v_tenant_id),
    ('616370', 'Assurances transports (sur ventes)', 'expense', v_tenant_id),
    ('616400', 'Assurances risques d exploitation', 'expense', v_tenant_id),
    ('616500', 'Assurances automobiles', 'expense', v_tenant_id),
    ('616600', 'Assurances personnels', 'expense', v_tenant_id),
    ('616800', 'Autres assurances', 'expense', v_tenant_id),
    ('617000', 'Etudes et recherches', 'expense', v_tenant_id),
    ('618000', 'Documentation', 'expense', v_tenant_id),
    ('618100', 'Documentation generale', 'expense', v_tenant_id),
    ('618200', 'Documentation technique', 'expense', v_tenant_id),
    ('618300', 'Documentation commerciale', 'expense', v_tenant_id),
    ('618400', 'Documentation administrative', 'expense', v_tenant_id),
    ('619000', 'Rabais, remises et ristournes obtenus sur services exterieurs', 'expense', v_tenant_id),
    ('620000', 'Autres services exterieurs', 'expense', v_tenant_id),
    ('621000', 'Personnel exterieur a l entreprise', 'expense', v_tenant_id),
    ('621100', 'Personnel integre', 'expense', v_tenant_id),
    ('621400', 'Personnel detache par d autres entreprises', 'expense', v_tenant_id),
    ('621600', 'Personnel exterieur a l entreprise (autres)', 'expense', v_tenant_id),
    ('622000', 'Remuneration d intermediaires et honoraires', 'expense', v_tenant_id),
    ('622100', 'Honoraires (non retenus par la source)', 'expense', v_tenant_id),
    ('622200', 'Commissions et courtages sur achats', 'expense', v_tenant_id),
    ('622400', 'Commissions et courtages sur ventes', 'expense', v_tenant_id),
    ('622500', 'Frais de recouvrement', 'expense', v_tenant_id),
    ('622600', 'Frais d actes et de contentieux', 'expense', v_tenant_id),
    ('622700', 'Frais de reunion, de reception et de representant', 'expense', v_tenant_id),
    ('622800', 'Divers', 'expense', v_tenant_id),
    ('623000', 'Publicite, publications, relations publiques', 'expense', v_tenant_id),
    ('623100', 'Annonces et insertions', 'expense', v_tenant_id),
    ('623200', 'Echantillons, catalogues et prospectus', 'expense', v_tenant_id),
    ('623300', 'Foires et expositions', 'expense', v_tenant_id),
    ('623400', 'Cadeaux a la clientele', 'expense', v_tenant_id),
    ('623500', 'Primes', 'expense', v_tenant_id),
    ('623600', 'Catalogues et imprimes', 'expense', v_tenant_id),
    ('623700', 'Publicite directe', 'expense', v_tenant_id),
    ('623800', 'Divers (pourboires, etc.)', 'expense', v_tenant_id),
    ('624000', 'Transports de biens et transports collectifs du personnel', 'expense', v_tenant_id),
    ('624100', 'Transports sur achats', 'expense', v_tenant_id),
    ('624200', 'Transports sur ventes', 'expense', v_tenant_id),
    ('624300', 'Transports entre etablissements', 'expense', v_tenant_id),
    ('624400', 'Transports administratifs', 'expense', v_tenant_id),
    ('624700', 'Transports collectifs du personnel', 'expense', v_tenant_id),
    ('625000', 'Deplacements, missions et receptions', 'expense', v_tenant_id),
    ('625100', 'Voyages et deplacements', 'expense', v_tenant_id),
    ('625600', 'Missions', 'expense', v_tenant_id),
    ('625700', 'Receptions', 'expense', v_tenant_id),
    ('626000', 'Frais postaux et de telecommunications', 'expense', v_tenant_id),
    ('626100', 'Frais postaux', 'expense', v_tenant_id),
    ('626300', 'Frais de telecommunications', 'expense', v_tenant_id),
    ('626500', 'Frais de telecommunications (autres)', 'expense', v_tenant_id),
    ('627000', 'Services bancaires et assimiles', 'expense', v_tenant_id),
    ('627100', 'Frais de tenue de compte', 'expense', v_tenant_id),
    ('627200', 'Commissions sur acceptation et negociation de creances', 'expense', v_tenant_id),
    ('627500', 'Commissions et frais sur encaissements', 'expense', v_tenant_id),
    ('627600', 'Commissions et frais sur encaissements (autres)', 'expense', v_tenant_id),
    ('627800', 'Autres frais et commissions sur prestations de services', 'expense', v_tenant_id),
    ('628000', 'Divers', 'expense', v_tenant_id),
    ('628100', 'Concours divers (cotisations, etc.)', 'expense', v_tenant_id),
    ('628400', 'Frais de recrutement de personnel', 'expense', v_tenant_id),
    ('629000', 'Rabais, remises et ristournes obtenus sur autres services exterieurs', 'expense', v_tenant_id),
    ('630000', 'Autres charges', 'expense', v_tenant_id),
    ('631000', 'Impots, taxes et versements assimiles sur remunerations', 'expense', v_tenant_id),
    ('631100', 'Impots, taxes et versements assimiles sur remunerations (administrations)', 'expense', v_tenant_id),
    ('631200', 'Impots, taxes et versements assimiles sur remunerations (autres organismes)', 'expense', v_tenant_id),
    ('631300', 'Participation des employeurs a la formation professionnelle continue', 'expense', v_tenant_id),
    ('631400', 'Participation des employeurs a l effort de construction', 'expense', v_tenant_id),
    ('631600', 'Impots, taxes et versements assimiles sur remunerations (autres)', 'expense', v_tenant_id),
    ('631800', 'Autres impots, taxes et versements assimiles sur remunerations', 'expense', v_tenant_id),
    ('633000', 'Impots, taxes et versements assimiles sur immobilisations', 'expense', v_tenant_id),
    ('635000', 'Impots, taxes et versements assimiles sur le chiffre d affaires', 'expense', v_tenant_id),
    ('635100', 'Impots, taxes et versements assimiles sur le chiffre d affaires (TVA)', 'expense', v_tenant_id),
    ('635200', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', v_tenant_id),
    ('635300', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', v_tenant_id),
    ('635400', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', v_tenant_id),
    ('635500', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', v_tenant_id),
    ('635800', 'Autres impots, taxes et versements assimiles sur le chiffre d affaires', 'expense', v_tenant_id),
    ('636000', 'Impots, taxes et versements assimiles sur le capital', 'expense', v_tenant_id),
    ('637000', 'Autres impots, taxes et versements assimiles', 'expense', v_tenant_id),
    ('637100', 'Impots, taxes et versements assimiles (autres)', 'expense', v_tenant_id),
    ('637200', 'Impots, taxes et versements assimiles (autres)', 'expense', v_tenant_id),
    ('637300', 'Impots, taxes et versements assimiles (autres)', 'expense', v_tenant_id),
    ('637400', 'Impots, taxes et versements assimiles (autres)', 'expense', v_tenant_id),
    ('637800', 'Autres impots, taxes et versements assimiles', 'expense', v_tenant_id),
    ('638000', 'Autres impots, taxes et versements assimiles', 'expense', v_tenant_id),
    ('639000', 'Rabais, remises et ristournes obtenus sur autres charges externes', 'expense', v_tenant_id),
    ('640000', 'Charges de personnel', 'expense', v_tenant_id),
    ('641000', 'Remunerations du personnel', 'expense', v_tenant_id),
    ('641100', 'Apprentis', 'expense', v_tenant_id),
    ('641200', 'Stagiaires', 'expense', v_tenant_id),
    ('641300', 'Remunerations du personnel (autres)', 'expense', v_tenant_id),
    ('641400', 'Remunerations du personnel (autres)', 'expense', v_tenant_id),
    ('641500', 'Remunerations du personnel (autres)', 'expense', v_tenant_id),
    ('641600', 'Remunerations du personnel (autres)', 'expense', v_tenant_id),
    ('641700', 'Remunerations du personnel (autres)', 'expense', v_tenant_id),
    ('641800', 'Remunerations du personnel (autres)', 'expense', v_tenant_id),
    ('642000', 'Remunerations du personnel de direction', 'expense', v_tenant_id),
    ('643000', 'Remunerations du personnel de direction', 'expense', v_tenant_id),
    ('644000', 'Remuneration du travail de l exploitant', 'expense', v_tenant_id),
    ('645000', 'Charges sociales', 'expense', v_tenant_id),
    ('645100', 'Cotisations a l URSSAF', 'expense', v_tenant_id),
    ('645200', 'Cotisations aux mutuelles', 'expense', v_tenant_id),
    ('645300', 'Cotisations caisses de retraite', 'expense', v_tenant_id),
    ('645400', 'Cotisations aux ASSEDIC', 'expense', v_tenant_id),
    ('645500', 'Prevoyances', 'expense', v_tenant_id),
    ('645800', 'Cotisations aux autres organismes sociaux', 'expense', v_tenant_id),
    ('646000', 'Cotisations sociales personnelles de l exploitant', 'expense', v_tenant_id),
    ('647000', 'Autres charges sociales', 'expense', v_tenant_id),
    ('647100', 'Prestations de retraites', 'expense', v_tenant_id),
    ('647200', 'Prestations directes', 'expense', v_tenant_id),
    ('647300', 'Prestations de retraites (autres)', 'expense', v_tenant_id),
    ('647400', 'Prestations directes (autres)', 'expense', v_tenant_id),
    ('647500', 'Medecine du travail, pharmacie', 'expense', v_tenant_id),
    ('647800', 'Autres charges sociales', 'expense', v_tenant_id),
    ('648000', 'Autres charges de personnel', 'expense', v_tenant_id),
    ('649000', 'Rabais, remises et ristournes obtenus sur charges de personnel', 'expense', v_tenant_id),
    ('650000', 'Autres charges de gestion courante', 'expense', v_tenant_id),
    ('651000', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'expense', v_tenant_id),
    ('651100', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'expense', v_tenant_id),
    ('651600', 'Droits d auteur', 'expense', v_tenant_id),
    ('651800', 'Autres redevances', 'expense', v_tenant_id),
    ('653000', 'Jetons de presence', 'expense', v_tenant_id),
    ('654000', 'Pertes sur creances irrecouvrables', 'expense', v_tenant_id),
    ('654100', 'Pertes sur creances clients', 'expense', v_tenant_id),
    ('654400', 'Pertes sur creances autres', 'expense', v_tenant_id),
    ('655000', 'Quotes-parts de resultat sur operations faites en commun', 'expense', v_tenant_id),
    ('655100', 'Quotes-parts de benefice', 'expense', v_tenant_id),
    ('655200', 'Quotes-parts de pertes', 'expense', v_tenant_id),
    ('656000', 'Pertes de change', 'expense', v_tenant_id),
    ('656100', 'Pertes de change (autres)', 'expense', v_tenant_id),
    ('656600', 'Pertes de change (autres)', 'expense', v_tenant_id),
    ('656800', 'Ecarts de conversion - actif', 'expense', v_tenant_id),
    ('657000', 'Charges de gestion courante (autres)', 'expense', v_tenant_id),
    ('658000', 'Charges diverses de gestion courante', 'expense', v_tenant_id),
    ('658100', 'Pertes sur operations a terme', 'expense', v_tenant_id),
    ('658200', 'Pertes sur operations de change a terme', 'expense', v_tenant_id),
    ('658600', 'Autres charges diverses de gestion courante', 'expense', v_tenant_id),
    ('658800', 'Rabais, remises et ristournes obtenus sur autres charges de gestion courante', 'expense', v_tenant_id),
    ('660000', 'Charges financieres', 'expense', v_tenant_id),
    ('661000', 'Charges d interets', 'expense', v_tenant_id),
    ('661100', 'Interets sur emprunts et dettes', 'expense', v_tenant_id),
    ('661110', 'Interets sur emprunts', 'expense', v_tenant_id),
    ('661120', 'Interets sur dettes financieres', 'expense', v_tenant_id),
    ('661130', 'Interets sur comptes courants et depots crediteurs', 'expense', v_tenant_id),
    ('661160', 'Interets bancaires et sur operations de financement', 'expense', v_tenant_id),
    ('661170', 'Interets sur autres operations de financement', 'expense', v_tenant_id),
    ('661180', 'Interets des obligations', 'expense', v_tenant_id),
    ('661500', 'Interets bancaires et sur operations de financement (escompte)', 'expense', v_tenant_id),
    ('661600', 'Interets sur autres operations de financement', 'expense', v_tenant_id),
    ('661700', 'Interets sur autres operations de financement (autres)', 'expense', v_tenant_id),
    ('661800', 'Interets sur autres operations de financement (autres)', 'expense', v_tenant_id),
    ('662000', 'Pertes de change', 'expense', v_tenant_id),
    ('664000', 'Pertes sur creances liees a des participations', 'expense', v_tenant_id),
    ('665000', 'Escomptes accordes', 'expense', v_tenant_id),
    ('666000', 'Pertes de change', 'expense', v_tenant_id),
    ('667000', 'Charges nettes sur cessions d immobilisations financieres', 'expense', v_tenant_id),
    ('668000', 'Autres charges financieres', 'expense', v_tenant_id),
    ('668100', 'Interets sur obligations', 'expense', v_tenant_id),
    ('668200', 'Interets sur bons de caisse', 'expense', v_tenant_id),
    ('668400', 'Autres charges financieres (autres)', 'expense', v_tenant_id),
    ('668800', 'Frais financiers sur emprunts', 'expense', v_tenant_id),
    ('669000', 'Rabais, remises et ristournes obtenus sur charges financieres', 'expense', v_tenant_id),
    ('670000', 'Charges exceptionnelles', 'expense', v_tenant_id),
    ('671000', 'Charges exceptionnelles sur operations de gestion', 'expense', v_tenant_id),
    ('671100', 'Penalites sur marches', 'expense', v_tenant_id),
    ('671200', 'Penalites, amendes fiscales et penales', 'expense', v_tenant_id),
    ('671300', 'Dons, liberalites', 'expense', v_tenant_id),
    ('671400', 'Subventions accordees', 'expense', v_tenant_id),
    ('671500', 'Rappels d impots (autres que sur le benefice)', 'expense', v_tenant_id),
    ('671700', 'Rappels d impots (sur le benefice)', 'expense', v_tenant_id),
    ('671800', 'Autres charges exceptionnelles', 'expense', v_tenant_id),
    ('672000', 'Charges sur exercices anterieurs', 'expense', v_tenant_id),
    ('672100', 'Charges sur exercices anterieurs (operations de gestion)', 'expense', v_tenant_id),
    ('672200', 'Charges sur exercices anterieurs (operations de capital)', 'expense', v_tenant_id),
    ('675000', 'Valeurs comptables des elements d actif cedes', 'expense', v_tenant_id),
    ('675100', 'Immobilisations incorporelles', 'expense', v_tenant_id),
    ('675200', 'Immobilisations corporelles', 'expense', v_tenant_id),
    ('675300', 'Immobilisations financieres', 'expense', v_tenant_id),
    ('675400', 'Stocks', 'expense', v_tenant_id),
    ('675500', 'Autres elements d actif', 'expense', v_tenant_id),
    ('675600', 'Actions propres', 'expense', v_tenant_id),
    ('675800', 'Autres valeurs comptables des elements d actif cedes', 'expense', v_tenant_id),
    ('676000', 'Pertes de change', 'expense', v_tenant_id),
    ('678000', 'Autres charges exceptionnelles', 'expense', v_tenant_id),
    ('678100', 'Bonis provenant de clauses d indexation', 'expense', v_tenant_id),
    ('678200', 'Malis provenant de clauses d indexation', 'expense', v_tenant_id),
    ('678300', 'Subventions d equilibrage', 'expense', v_tenant_id),
    ('678400', 'Subventions d investissement a reprendre', 'expense', v_tenant_id),
    ('678800', 'Autres charges exceptionnelles (autres)', 'expense', v_tenant_id),
    ('679000', 'Rabais, remises et ristournes obtenus sur charges exceptionnelles', 'expense', v_tenant_id),
    ('680000', 'Dotations aux amortissements et aux provisions', 'expense', v_tenant_id),
    ('681000', 'Dotations aux amortissements et aux provisions - charges d exploitation', 'expense', v_tenant_id),
    ('681100', 'Dotations aux amortissements sur immobilisations incorporelles', 'expense', v_tenant_id),
    ('681110', 'Dotations aux amortissements des frais d etablissement', 'expense', v_tenant_id),
    ('681120', 'Dotations aux amortissements des concessions, brevets, licences, logiciels', 'expense', v_tenant_id),
    ('681150', 'Dotations aux amortissements des fonds commercial', 'expense', v_tenant_id),
    ('681200', 'Dotations aux amortissements sur immobilisations corporelles', 'expense', v_tenant_id),
    ('681210', 'Dotations aux amortissements des terrains', 'expense', v_tenant_id),
    ('681220', 'Dotations aux amortissements des constructions', 'expense', v_tenant_id),
    ('681230', 'Dotations aux amortissements des installations techniques', 'expense', v_tenant_id),
    ('681240', 'Dotations aux amortissements du mobilier', 'expense', v_tenant_id),
    ('681250', 'Dotations aux amortissements du materiel', 'expense', v_tenant_id),
    ('681260', 'Dotations aux amortissements du materiel de transport', 'expense', v_tenant_id),
    ('681700', 'Dotations aux amortissements des immobilisations en cours', 'expense', v_tenant_id),
    ('681500', 'Dotations aux provisions pour risques d exploitation', 'expense', v_tenant_id),
    ('681600', 'Dotations aux provisions pour depreciation des immobilisations incorporelles', 'expense', v_tenant_id),
    ('681610', 'Dotations aux provisions pour depreciation des immobilisations corporelles', 'expense', v_tenant_id),
    ('681620', 'Dotations aux provisions pour depreciation des stocks', 'expense', v_tenant_id),
    ('681630', 'Dotations aux provisions pour depreciation des creances', 'expense', v_tenant_id),
    ('681640', 'Dotations aux provisions pour depreciation des titres de placement', 'expense', v_tenant_id),
    ('681650', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', v_tenant_id),
    ('681800', 'Autres dotations aux amortissements et aux provisions', 'expense', v_tenant_id),
    ('681810', 'Dotations aux provisions pour risques et charges d exploitation', 'expense', v_tenant_id),
    ('681820', 'Dotations aux provisions pour depreciation des actifs circulant', 'expense', v_tenant_id),
    ('681830', 'Dotations aux provisions pour depreciation des comptes de tiers', 'expense', v_tenant_id),
    ('681840', 'Dotations aux provisions pour depreciation des comptes financiers', 'expense', v_tenant_id),
    ('681850', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', v_tenant_id),
    ('681860', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', v_tenant_id),
    ('681870', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', v_tenant_id),
    ('681880', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', v_tenant_id),
    ('681890', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', v_tenant_id),
    ('686000', 'Dotations aux amortissements et aux provisions - charges financieres', 'expense', v_tenant_id),
    ('686100', 'Dotations aux amortissements des immobilisations financieres', 'expense', v_tenant_id),
    ('686500', 'Dotations aux provisions pour risques financiers', 'expense', v_tenant_id),
    ('686600', 'Dotations aux provisions pour depreciation des immobilisations financieres', 'expense', v_tenant_id),
    ('686700', 'Dotations aux provisions pour depreciation des valeurs mobilieres de placement', 'expense', v_tenant_id),
    ('686800', 'Autres dotations aux provisions financieres', 'expense', v_tenant_id),
    ('687000', 'Dotations aux amortissements et aux provisions - charges exceptionnelles', 'expense', v_tenant_id),
    ('687100', 'Dotations aux amortissements exceptionnels des immobilisations', 'expense', v_tenant_id),
    ('687200', 'Dotations aux provisions reglementees (immobilisations)', 'expense', v_tenant_id),
    ('687300', 'Dotations aux provisions reglementees (stocks)', 'expense', v_tenant_id),
    ('687400', 'Dotations aux autres provisions reglementees', 'expense', v_tenant_id),
    ('687500', 'Dotations aux provisions pour risques et charges exceptionnels', 'expense', v_tenant_id),
    ('687600', 'Dotations aux provisions pour depreciation exceptionnelles', 'expense', v_tenant_id),
    ('687700', 'Dotations aux autres provisions exceptionnelles', 'expense', v_tenant_id),

    -- Classe 7 - Produits
    ('700000', 'Ventes de marchandises, production vendue (biens et services)', 'income', v_tenant_id),
    ('701000', 'Ventes de produits finis', 'income', v_tenant_id),
    ('701100', 'Ventes de produits finis (group A)', 'income', v_tenant_id),
    ('701200', 'Ventes de produits finis (group B)', 'income', v_tenant_id),
    ('702000', 'Ventes de produits intermediaires', 'income', v_tenant_id),
    ('702100', 'Ventes de produits intermediaires (group A)', 'income', v_tenant_id),
    ('702200', 'Ventes de produits intermediaires (group B)', 'income', v_tenant_id),
    ('703000', 'Ventes de produits residuels', 'income', v_tenant_id),
    ('704000', 'Travaux', 'income', v_tenant_id),
    ('704100', 'Travaux de construction', 'income', v_tenant_id),
    ('704200', 'Travaux de montage', 'income', v_tenant_id),
    ('705000', 'Etudes', 'income', v_tenant_id),
    ('706000', 'Prestations de services', 'income', v_tenant_id),
    ('706100', 'Prestations de services (group A)', 'income', v_tenant_id),
    ('706200', 'Prestations de services (group B)', 'income', v_tenant_id),
    ('707000', 'Ventes de marchandises', 'income', v_tenant_id),
    ('707100', 'Ventes de marchandises (group A)', 'income', v_tenant_id),
    ('707200', 'Ventes de marchandises (group B)', 'income', v_tenant_id),
    ('708000', 'Produits des activites annexes', 'income', v_tenant_id),
    ('708100', 'Produits des services exploités dans l interet du personnel', 'income', v_tenant_id),
    ('708200', 'Commissions et courtages', 'income', v_tenant_id),
    ('708300', 'Locations diverses', 'income', v_tenant_id),
    ('708400', 'Mise a disposition de personnel', 'income', v_tenant_id),
    ('708500', 'Ports et frais accessoires factures', 'income', v_tenant_id),
    ('708600', 'Bonis sur reprises de emballages consignés', 'income', v_tenant_id),
    ('708800', 'Autres produits d activites annexes', 'income', v_tenant_id),
    ('709000', 'Rabais, remises et ristournes accordes par l entreprise', 'income', v_tenant_id),
    ('709100', 'Rabais, remises et ristournes sur ventes de produits finis', 'income', v_tenant_id),
    ('709600', 'Rabais, remises et ristournes sur prestations de services', 'income', v_tenant_id),
    ('709700', 'Rabais, remises et ristournes sur ventes de marchandises', 'income', v_tenant_id),
    ('709800', 'Rabais, remises et ristournes sur produits des activites annexes', 'income', v_tenant_id),
    ('710000', 'Variation des stocks et production stockee', 'income', v_tenant_id),
    ('713000', 'Variation des stocks (en-cours de production, produits)', 'income', v_tenant_id),
    ('713100', 'Variation des stocks de produits en cours', 'income', v_tenant_id),
    ('713300', 'Variation des stocks de produits', 'income', v_tenant_id),
    ('713400', 'Variation des stocks de services en cours', 'income', v_tenant_id),
    ('713500', 'Variation des stocks de produits finis', 'income', v_tenant_id),
    ('713600', 'Variation des stocks de produits residuels', 'income', v_tenant_id),
    ('713700', 'Variation des stocks de marchandises', 'income', v_tenant_id),
    ('720000', 'Production immobilisee', 'income', v_tenant_id),
    ('721000', 'Production immobilisee - immobilisations incorporelles', 'income', v_tenant_id),
    ('722000', 'Production immobilisee - immobilisations corporelles', 'income', v_tenant_id),
    ('740000', 'Subventions d exploitation', 'income', v_tenant_id),
    ('740100', 'Subventions d exploitation du budget de l Etat', 'income', v_tenant_id),
    ('740200', 'Subventions d exploitation des collectivites locales', 'income', v_tenant_id),
    ('740300', 'Subventions d exploitation des etablissements publics', 'income', v_tenant_id),
    ('740400', 'Subventions d exploitation des entreprises publiques', 'income', v_tenant_id),
    ('740500', 'Subventions d exploitation des autres organismes', 'income', v_tenant_id),
    ('740600', 'Subventions d exploitation des autres organismes (autres)', 'income', v_tenant_id),
    ('740700', 'Subventions d exploitation des autres organismes (autres)', 'income', v_tenant_id),
    ('740800', 'Subventions d exploitation des autres organismes (autres)', 'income', v_tenant_id),
    ('741000', 'Subventions d equilibrage', 'income', v_tenant_id),
    ('748000', 'Autres subventions d exploitation', 'income', v_tenant_id),
    ('750000', 'Autres produits de gestion courante', 'income', v_tenant_id),
    ('751000', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'income', v_tenant_id),
    ('751100', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'income', v_tenant_id),
    ('751600', 'Droits d auteur', 'income', v_tenant_id),
    ('751800', 'Autres redevances', 'income', v_tenant_id),
    ('752000', 'Revenus des immeubles non affectes a l exploitation professionnelle', 'income', v_tenant_id),
    ('753000', 'Jetons de presence et remuneration d administrateurs', 'income', v_tenant_id),
    ('754000', 'Quotes-parts de resultat sur operations faites en commun', 'income', v_tenant_id),
    ('754100', 'Quotes-parts de perte', 'income', v_tenant_id),
    ('754200', 'Quotes-parts de benefice', 'income', v_tenant_id),
    ('755000', 'Quotes-parts de perte sur operations faites en commun', 'income', v_tenant_id),
    ('756000', 'Gains de change', 'income', v_tenant_id),
    ('756100', 'Gains de change (autres)', 'income', v_tenant_id),
    ('756600', 'Gains de change (autres)', 'income', v_tenant_id),
    ('756800', 'Ecarts de conversion - passif', 'income', v_tenant_id),
    ('757000', 'Produits de gestion courante (autres)', 'income', v_tenant_id),
    ('758000', 'Produits divers de gestion courante', 'income', v_tenant_id),
    ('758100', 'Gains sur operations a terme', 'income', v_tenant_id),
    ('758200', 'Gains sur operations de change a terme', 'income', v_tenant_id),
    ('758600', 'Autres produits divers de gestion courante', 'income', v_tenant_id),
    ('758800', 'Rabais, remises et ristournes obtenus sur autres produits de gestion courante', 'income', v_tenant_id),
    ('760000', 'Produits financiers', 'income', v_tenant_id),
    ('761000', 'Produits de participations', 'income', v_tenant_id),
    ('761100', 'Revenus des titres de participation', 'income', v_tenant_id),
    ('761600', 'Revenus sur autres formes de participation', 'income', v_tenant_id),
    ('761700', 'Quotes-parts de resultat sur operations faites en commun', 'income', v_tenant_id),
    ('761800', 'Revenus des creances rattachees a des participations', 'income', v_tenant_id),
    ('762000', 'Produits des autres immobilisations financieres', 'income', v_tenant_id),
    ('762100', 'Revenus des titres immobilises', 'income', v_tenant_id),
    ('762600', 'Revenus des pretes', 'income', v_tenant_id),
    ('762700', 'Revenus des creances commerciales', 'income', v_tenant_id),
    ('763000', 'Revenus des autres creances', 'income', v_tenant_id),
    ('763100', 'Revenus des creances commerciales', 'income', v_tenant_id),
    ('763200', 'Revenus des creances diverses', 'income', v_tenant_id),
    ('764000', 'Revenus des valeurs mobilieres de placement', 'income', v_tenant_id),
    ('764100', 'Revenus des actions', 'income', v_tenant_id),
    ('764200', 'Revenus des obligations', 'income', v_tenant_id),
    ('764300', 'Revenus des bons de caisse et du Tresor', 'income', v_tenant_id),
    ('764400', 'Revenus des autres valeurs mobilieres de placement', 'income', v_tenant_id),
    ('765000', 'Escomptes obtenus', 'income', v_tenant_id),
    ('766000', 'Gains de change', 'income', v_tenant_id),
    ('767000', 'Produits nets sur cessions d immobilisations financieres', 'income', v_tenant_id),
    ('768000', 'Autres produits financiers', 'income', v_tenant_id),
    ('768100', 'Interets sur obligations', 'income', v_tenant_id),
    ('768200', 'Interets sur bons de caisse', 'income', v_tenant_id),
    ('768400', 'Autres produits financiers (autres)', 'income', v_tenant_id),
    ('768800', 'Produits des operations de financement', 'income', v_tenant_id),
    ('769000', 'Rabais, remises et ristournes obtenus sur produits financiers', 'income', v_tenant_id),
    ('770000', 'Produits exceptionnels', 'income', v_tenant_id),
    ('771000', 'Produits exceptionnels sur operations de gestion', 'income', v_tenant_id),
    ('771100', 'Dedommagements recus', 'income', v_tenant_id),
    ('771200', 'Dégrèvements d impots', 'income', v_tenant_id),
    ('771300', 'Liberalites recues', 'income', v_tenant_id),
    ('771400', 'Subventions d equilibrage', 'income', v_tenant_id),
    ('771500', 'Subventions d investissement', 'income', v_tenant_id),
    ('771700', 'Rentrées sur creances amorties', 'income', v_tenant_id),
    ('771800', 'Autres produits exceptionnels', 'income', v_tenant_id),
    ('772000', 'Produits sur exercices anterieurs', 'income', v_tenant_id),
    ('772100', 'Produits sur exercices anterieurs (operations de gestion)', 'income', v_tenant_id),
    ('772200', 'Produits sur exercices anterieurs (operations de capital)', 'income', v_tenant_id),
    ('775000', 'Produits des cessions d elements d actif', 'income', v_tenant_id),
    ('775100', 'Immobilisations incorporelles', 'income', v_tenant_id),
    ('775200', 'Immobilisations corporelles', 'income', v_tenant_id),
    ('775300', 'Immobilisations financieres', 'income', v_tenant_id),
    ('775400', 'Stocks', 'income', v_tenant_id),
    ('775500', 'Autres elements d actif', 'income', v_tenant_id),
    ('775600', 'Actions propres', 'income', v_tenant_id),
    ('775800', 'Autres produits des cessions d elements d actif', 'income', v_tenant_id),
    ('776000', 'Gains de change', 'income', v_tenant_id),
    ('777000', 'Quotes-parts des subventions d investissement inscrites au resultat de l exercice', 'income', v_tenant_id),
    ('778000', 'Autres produits exceptionnels', 'income', v_tenant_id),
    ('778100', 'Bonis provenant de clauses d indexation', 'income', v_tenant_id),
    ('778200', 'Malis provenant de clauses d indexation', 'income', v_tenant_id),
    ('778300', 'Subventions d equilibrage', 'income', v_tenant_id),
    ('778400', 'Subventions d investissement a reprendre', 'income', v_tenant_id),
    ('778800', 'Autres produits exceptionnels (autres)', 'income', v_tenant_id),
    ('779000', 'Rabais, remises et ristournes accordes sur produits exceptionnels', 'income', v_tenant_id),
    ('780000', 'Reprises sur amortissements et provisions', 'income', v_tenant_id),
    ('781000', 'Reprises sur amortissements et provisions - charges d exploitation', 'income', v_tenant_id),
    ('781100', 'Reprises sur amortissements des immobilisations incorporelles', 'income', v_tenant_id),
    ('781200', 'Reprises sur amortissements des immobilisations corporelles', 'income', v_tenant_id),
    ('781500', 'Reprises sur provisions pour risques d exploitation', 'income', v_tenant_id),
    ('781600', 'Reprises sur provisions pour depreciation des immobilisations incorporelles', 'income', v_tenant_id),
    ('781610', 'Reprises sur provisions pour depreciation des immobilisations corporelles', 'income', v_tenant_id),
    ('781620', 'Reprises sur provisions pour depreciation des stocks', 'income', v_tenant_id),
    ('781630', 'Reprises sur provisions pour depreciation des creances', 'income', v_tenant_id),
    ('781640', 'Reprises sur provisions pour depreciation des titres de placement', 'income', v_tenant_id),
    ('781700', 'Reprises sur provisions pour depreciation des autres elements d actif', 'income', v_tenant_id),
    ('781800', 'Autres reprises sur amortissements et provisions', 'income', v_tenant_id),
    ('786000', 'Reprises sur amortissements et provisions - charges financieres', 'income', v_tenant_id),
    ('786100', 'Reprises sur amortissements des immobilisations financieres', 'income', v_tenant_id),
    ('786500', 'Reprises sur provisions pour risques financiers', 'income', v_tenant_id),
    ('786600', 'Reprises sur provisions pour depreciation des immobilisations financieres', 'income', v_tenant_id),
    ('786700', 'Reprises sur provisions pour depreciation des valeurs mobilieres de placement', 'income', v_tenant_id),
    ('786800', 'Autres reprises sur provisions financieres', 'income', v_tenant_id),
    ('787000', 'Reprises sur amortissements et provisions - charges exceptionnelles', 'income', v_tenant_id),
    ('787100', 'Reprises sur amortissements exceptionnels des immobilisations', 'income', v_tenant_id),
    ('787200', 'Reprises sur provisions reglementees (immobilisations)', 'income', v_tenant_id),
    ('787300', 'Reprises sur provisions reglementees (stocks)', 'income', v_tenant_id),
    ('787400', 'Reprises sur autres provisions reglementees', 'income', v_tenant_id),
    ('787500', 'Reprises sur provisions pour risques et charges exceptionnels', 'income', v_tenant_id),
    ('787600', 'Reprises sur provisions pour depreciation exceptionnelles', 'income', v_tenant_id),
    ('787700', 'Reprises sur autres provisions exceptionnelles', 'income', v_tenant_id),
    ('790000', 'Transferts de charges', 'income', v_tenant_id),
    ('791000', 'Transferts de charges d exploitation', 'income', v_tenant_id),
    ('796000', 'Transferts de charges financieres', 'income', v_tenant_id),
    ('797000', 'Transferts de charges exceptionnelles', 'income', v_tenant_id),

    -- Classe 8 - Comptes speciaux
    ('800000', 'Engagements financiers', 'liability', v_tenant_id),
    ('801000', 'Engagements de garantie', 'liability', v_tenant_id),
    ('801100', 'Avals, cautions, garanties', 'liability', v_tenant_id),
    ('801400', 'Credits de signature par endossement', 'liability', v_tenant_id),
    ('801700', 'Hypotèques', 'liability', v_tenant_id),
    ('801800', 'Gages sur stocks', 'liability', v_tenant_id),
    ('804000', 'Engagements financiers recus', 'asset', v_tenant_id),
    ('804100', 'Avals, cautions, garanties recus', 'asset', v_tenant_id),
    ('804400', 'Credits de signature par endossement recus', 'asset', v_tenant_id),
    ('804500', 'Hypotèques recues', 'asset', v_tenant_id),
    ('804800', 'Gages sur stocks recus', 'asset', v_tenant_id),
    ('808000', 'Engagements divers', 'liability', v_tenant_id),
    ('808100', 'Engagements divers donnes', 'liability', v_tenant_id),
    ('808400', 'Engagements divers recus', 'asset', v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id;

  -- ============================================
  -- 2. CUSTOMERS
  -- ============================================
  INSERT INTO customers (id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Boulangerie Dupont', 'contact@dupont.fr', '01 23 45 67 89', '12 rue de la Paix', 'Paris', '75001', 'France', 0, '30 days', 'EUR', true, v_tenant_id)
  RETURNING id INTO v_customer_1;

  INSERT INTO customers (id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Societe Martin SARL', 'info@martin-sarl.fr', '02 34 56 78 90', '45 avenue des Champs', 'Lyon', '69000', 'France', 0, '30 days', 'EUR', true, v_tenant_id)
  RETURNING id INTO v_customer_2;

  INSERT INTO customers (id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Tech Innov SAS', 'contact@techinnov.fr', '03 45 67 89 01', '78 boulevard Haussmann', 'Marseille', '13000', 'France', 0, '45 days', 'EUR', true, v_tenant_id)
  RETURNING id INTO v_customer_3;

  INSERT INTO customers (id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Restaurant Le Gourmet', 'contact@legourmet.fr', '04 56 78 90 12', '23 place du Marche', 'Bordeaux', '33000', 'France', 0, '30 days', 'EUR', true, v_tenant_id)
  RETURNING id INTO v_customer_4;

  INSERT INTO customers (id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Entreprise Bernard', 'bernard@entreprise.fr', '05 67 89 01 23', '56 rue du Commerce', 'Lille', '59000', 'France', 0, '30 days', 'EUR', true, v_tenant_id)
  RETURNING id INTO v_customer_5;

  -- ============================================
  -- 3. SUPPLIERS
  -- ============================================
  INSERT INTO suppliers (id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Fournisseur Global SA', 'contact@global-sa.fr', '01 11 22 33 44', '100 rue industrielle', 'Paris', '75011', 'France', 0, '30 days', 'EUR', true, v_tenant_id)
  RETURNING id INTO v_supplier_1;

  INSERT INTO suppliers (id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Distrib Express', 'info@distrib-express.fr', '02 22 33 44 55', '200 zone artisanale', 'Lyon', '69001', 'France', 0, '45 days', 'EUR', true, v_tenant_id)
  RETURNING id INTO v_supplier_2;

  INSERT INTO suppliers (id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Papeterie Centrale', 'contact@papeterie-centrale.fr', '03 33 44 55 66', '300 avenue Foch', 'Marseille', '13001', 'France', 0, '30 days', 'EUR', true, v_tenant_id)
  RETURNING id INTO v_supplier_3;

  -- ============================================
  -- 4. PRODUCTS
  -- ============================================
  INSERT INTO products (id, name, sku, description, type, sale_price, purchase_price, vat_rate, stock_quantity, unit, category, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Consultation comptable', 'SRV-001', 'Prestation comptable horaire', 'service', 120.00, 0, 20.0, 0, 'heure', 'Services', true, v_tenant_id)
  RETURNING id INTO v_product_1;

  INSERT INTO products (id, name, sku, description, type, sale_price, purchase_price, vat_rate, stock_quantity, unit, category, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Logiciel ERP licence annuelle', 'PROD-ERP', 'Licence annuelle ERP', 'stock', 2400.00, 800.00, 20.0, 50, 'licence', 'Logiciels', true, v_tenant_id)
  RETURNING id INTO v_product_2;

  INSERT INTO products (id, name, sku, description, type, sale_price, purchase_price, vat_rate, stock_quantity, unit, category, active, tenant_id)
  VALUES (uuid_generate_v4(), 'Formation utilisateurs', 'SRV-FORM', 'Formation 1 jour', 'service', 800.00, 0, 20.0, 0, 'jour', 'Formations', true, v_tenant_id)
  RETURNING id INTO v_product_3;

  -- ============================================
  -- 4b. WAREHOUSES (dépôts)
  -- ============================================
  INSERT INTO warehouses (id, code, name, address, city, postal_code, country, active, tenant_id)
  VALUES (uuid_generate_v4(), 'DEP-01', 'Dépôt Principal', '12 rue de l''Industrie', 'Paris', '75011', 'France', true, v_tenant_id)
  RETURNING id INTO v_warehouse_1;

  INSERT INTO warehouses (id, code, name, address, city, postal_code, country, active, tenant_id)
  VALUES (uuid_generate_v4(), 'DEP-02', 'Dépôt Secondaire', '45 zone Artisanale', 'Lyon', '69001', 'France', true, v_tenant_id)
  RETURNING id INTO v_warehouse_2;

  INSERT INTO warehouses (id, code, name, address, city, postal_code, country, active, tenant_id)
  VALUES (uuid_generate_v4(), 'DEP-03', 'Dépôt Transit', '78 avenue du Port', 'Marseille', '13002', 'France', true, v_tenant_id)
  RETURNING id INTO v_warehouse_3;

  -- ============================================
  -- 4c. STOCK QUANTITIES (quantités en stock par dépôt)
  -- ============================================
  INSERT INTO stock_quantities (product_id, warehouse_id, quantity, reserved_quantity, min_quantity, max_quantity, reorder_point, unit_cost, tenant_id)
  VALUES
    (v_product_2, v_warehouse_1, 30, 0, 5, 100, 10, 800.00, v_tenant_id),
    (v_product_2, v_warehouse_2, 15, 2, 5, 50, 8, 800.00, v_tenant_id),
    (v_product_2, v_warehouse_3, 5, 0, 3, 30, 5, 800.00, v_tenant_id);

  -- ============================================
  -- 4d. STOCK MOVEMENTS (mouvements de stock)
  -- ============================================
  -- Make old 'type' column nullable (it was NOT NULL from schema-additions, but we use movement_type now)
  ALTER TABLE stock_movements ALTER COLUMN type DROP NOT NULL;
  INSERT INTO stock_movements (product_id, warehouse_id, movement_type, quantity, unit_cost, reference, reference_type, movement_date, notes, tenant_id)
  VALUES
    (v_product_2, v_warehouse_1, 'initial', 50, 800.00, 'INV-INIT-2025', 'inventory', '2025-01-01', 'Stock initial', v_tenant_id),
    (v_product_2, v_warehouse_1, 'out', 5, 800.00, 'BL-2025-001', 'delivery_note', '2025-03-15', 'Sortie livraison client', v_tenant_id),
    (v_product_2, v_warehouse_1, 'in', 10, 800.00, 'BR-2025-001', 'goods_receipt', '2025-06-20', 'Réception fournisseur', v_tenant_id),
    (v_product_2, v_warehouse_1, 'transfer', 15, 800.00, 'TR-2025-001', 'transfer', '2025-09-10', 'Transfert vers dépôt secondaire', v_tenant_id),
    (v_product_2, v_warehouse_2, 'initial', 15, 800.00, 'INV-INIT-2025', 'inventory', '2025-01-01', 'Stock initial', v_tenant_id),
    (v_product_2, v_warehouse_2, 'transfer', 15, 800.00, 'TR-2025-001', 'transfer', '2025-09-10', 'Transfert depuis dépôt principal', v_tenant_id),
    (v_product_2, v_warehouse_3, 'initial', 5, 800.00, 'INV-INIT-2025', 'inventory', '2025-01-01', 'Stock initial', v_tenant_id),
    (v_product_2, v_warehouse_1, 'adjustment', -5, 800.00, 'INV-2025-001', 'inventory', '2025-12-31', 'Ajustement inventaire fin d''année', v_tenant_id),
    (v_product_2, v_warehouse_1, 'in', 20, 800.00, 'BR-2026-001', 'goods_receipt', '2026-02-15', 'Réception fournisseur 2026', v_tenant_id),
    (v_product_2, v_warehouse_2, 'out', 3, 800.00, 'BL-2026-001', 'delivery_note', '2026-04-10', 'Sortie livraison client 2026', v_tenant_id);

  -- ============================================
  -- 5. BANK ACCOUNTS
  -- ============================================
  INSERT INTO bank_accounts (id, name, type, account_number, balance, currency, bank_name, tenant_id)
  VALUES (uuid_generate_v4(), 'Compte courant principal', 'chequing', 'FR76 1234 5678 9012 3456 789', 45200.00, 'EUR', 'Credit Agricole', v_tenant_id)
  RETURNING id INTO v_bank_1;

  INSERT INTO bank_accounts (id, name, type, account_number, balance, currency, bank_name, tenant_id)
  VALUES (uuid_generate_v4(), 'Compte epargne', 'savings', 'FR76 9876 5432 1098 7654 321', 18000.00, 'EUR', 'Credit Agricole', v_tenant_id)
  RETURNING id INTO v_bank_2;

  -- ============================================
  -- 5b. JOURNALS (codes journaux)
  -- ============================================
  INSERT INTO journals (code, name, type, account_counterpart, status, locked, tenant_id)
  VALUES ('VT', 'Journal des ventes', 'sale', '411000', 'active', false, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id;

  INSERT INTO journals (code, name, type, account_counterpart, status, locked, tenant_id)
  VALUES ('AC', 'Journal des achats', 'purchase', '401000', 'active', false, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id;

  INSERT INTO journals (code, name, type, account_counterpart, bank_account_id, status, locked, tenant_id)
  VALUES ('BQ', 'Journal de banque', 'bank', '512000', v_bank_1, 'active', false, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, bank_account_id = EXCLUDED.bank_account_id;

  INSERT INTO journals (code, name, type, status, locked, tenant_id)
  VALUES ('OD', 'Operations diverses', 'general', 'active', false, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id;

  -- ============================================
  -- 5c. THIRD PARTY ACCOUNTS (plan tiers)
  -- ============================================
  INSERT INTO third_party_accounts (code, account_general_code, type, name, customer_id, balance, active, tenant_id)
  VALUES ('C-DUPONT', '411000', 'customer', 'Boulangerie Dupont', v_customer_1, 0, true, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, customer_id = EXCLUDED.customer_id;

  INSERT INTO third_party_accounts (code, account_general_code, type, name, customer_id, balance, active, tenant_id)
  VALUES ('C-MARTIN', '411000', 'customer', 'Societe Martin SARL', v_customer_2, 0, true, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, customer_id = EXCLUDED.customer_id;

  INSERT INTO third_party_accounts (code, account_general_code, type, name, customer_id, balance, active, tenant_id)
  VALUES ('C-TECHINNOV', '411000', 'customer', 'Tech Innov SAS', v_customer_3, 0, true, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, customer_id = EXCLUDED.customer_id;

  INSERT INTO third_party_accounts (code, account_general_code, type, name, customer_id, balance, active, tenant_id)
  VALUES ('C-GOURMET', '411000', 'customer', 'Restaurant Le Gourmet', v_customer_4, 0, true, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, customer_id = EXCLUDED.customer_id;

  INSERT INTO third_party_accounts (code, account_general_code, type, name, customer_id, balance, active, tenant_id)
  VALUES ('C-BERNARD', '411000', 'customer', 'Entreprise Bernard', v_customer_5, 0, true, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, customer_id = EXCLUDED.customer_id;

  INSERT INTO third_party_accounts (code, account_general_code, type, name, supplier_id, balance, active, tenant_id)
  VALUES ('F-GLOBAL', '401000', 'supplier', 'Fournisseur Global SA', v_supplier_1, 0, true, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, supplier_id = EXCLUDED.supplier_id;

  INSERT INTO third_party_accounts (code, account_general_code, type, name, supplier_id, balance, active, tenant_id)
  VALUES ('F-DISTRIB', '401000', 'supplier', 'Distrib Express', v_supplier_2, 0, true, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, supplier_id = EXCLUDED.supplier_id;

  INSERT INTO third_party_accounts (code, account_general_code, type, name, supplier_id, balance, active, tenant_id)
  VALUES ('F-PAPETERIE', '401000', 'supplier', 'Papeterie Centrale', v_supplier_3, 0, true, v_tenant_id)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, tenant_id = EXCLUDED.tenant_id, supplier_id = EXCLUDED.supplier_id;

  -- ============================================
  -- 5d. ENTRY TEMPLATES (modeles de saisie)
  -- ============================================
  INSERT INTO entry_templates (name, journal_code, description, template_lines, is_default, active, tenant_id)
  VALUES ('Vente standard', 'VT', 'Saisie vente standard', '[
    {"account_general":"411000","account_tiers":"","label":"Client","debit_pct":100,"credit_pct":0,"amount_type":"balance","vat_code":"","analytic_section":""},
    {"account_general":"707000","account_tiers":"","label":"Vente de marchandises","debit_pct":0,"credit_pct":100,"amount_type":"input","vat_code":"V20","analytic_section":""},
    {"account_general":"445710","account_tiers":"","label":"TVA collectee","debit_pct":0,"credit_pct":20,"amount_type":"calc_vat","vat_code":"V20","analytic_section":""}
  ]'::jsonb, true, true, v_tenant_id);

  INSERT INTO entry_templates (name, journal_code, description, template_lines, is_default, active, tenant_id)
  VALUES ('Achat standard', 'AC', 'Saisie achat standard', '[
    {"account_general":"607000","account_tiers":"","label":"Achat de marchandises","debit_pct":100,"credit_pct":0,"amount_type":"input","vat_code":"V20","analytic_section":""},
    {"account_general":"445660","account_tiers":"","label":"TVA deductible","debit_pct":20,"credit_pct":0,"amount_type":"calc_vat","vat_code":"V20","analytic_section":""},
    {"account_general":"401000","account_tiers":"","label":"Fournisseur","debit_pct":0,"credit_pct":120,"amount_type":"balance","vat_code":"","analytic_section":""}
  ]'::jsonb, true, true, v_tenant_id);

  INSERT INTO entry_templates (name, journal_code, description, template_lines, is_default, active, tenant_id)
  VALUES ('Encaissement bancaire', 'BQ', 'Encaissement client sur banque', '[
    {"account_general":"512000","account_tiers":"","label":"Banque","debit_pct":100,"credit_pct":0,"amount_type":"input","vat_code":"","analytic_section":""},
    {"account_general":"411000","account_tiers":"","label":"Client","debit_pct":0,"credit_pct":100,"amount_type":"balance","vat_code":"","analytic_section":""}
  ]'::jsonb, true, true, v_tenant_id);

  INSERT INTO entry_templates (name, journal_code, description, template_lines, is_default, active, tenant_id)
  VALUES ('Decaissement bancaire', 'BQ', 'Paiement fournisseur sur banque', '[
    {"account_general":"401000","account_tiers":"","label":"Fournisseur","debit_pct":100,"credit_pct":0,"amount_type":"input","vat_code":"","analytic_section":""},
    {"account_general":"512000","account_tiers":"","label":"Banque","debit_pct":0,"credit_pct":100,"amount_type":"balance","vat_code":"","analytic_section":""}
  ]'::jsonb, false, true, v_tenant_id);

  INSERT INTO entry_templates (name, journal_code, description, template_lines, is_default, active, tenant_id)
  VALUES ('OD diverse', 'OD', 'Operation diverse standard', '[
    {"account_general":"613000","account_tiers":"","label":"Location","debit_pct":100,"credit_pct":0,"amount_type":"input","vat_code":"","analytic_section":""},
    {"account_general":"512000","account_tiers":"","label":"Banque","debit_pct":0,"credit_pct":100,"amount_type":"balance","vat_code":"","analytic_section":""}
  ]'::jsonb, true, true, v_tenant_id);

  -- ============================================
  -- 6. FISCAL YEAR 2025 (CLOSED)
  -- ============================================
  INSERT INTO fiscal_years (id, code, start_date, end_date, status, closed_at, tenant_id)
  VALUES (uuid_generate_v4(), 'EX-2025', '2025-01-01', '2025-12-31', 'closed', '2026-01-15T10:00:00Z', v_tenant_id)
  RETURNING id INTO v_fy_2025_id;

  FOR v_month IN 1..12 LOOP
    v_date := make_date(2025, v_month, 1);
    INSERT INTO fiscal_periods (fiscal_year_id, period_number, period_label, start_date, end_date, status, tenant_id)
    VALUES (
      v_fy_2025_id,
      v_month,
      to_char(v_date, 'YYYY-MM'),
      v_date,
      (v_date + interval '1 month - 1 day')::date,
      'closed',
      v_tenant_id
    )
    RETURNING id INTO v_tmp_id;
    v_period_ids[v_month] := v_tmp_id;
  END LOOP;

  -- ============================================
  -- 7. FISCAL YEAR 2026 (OPEN, in-progress)
  -- ============================================
  INSERT INTO fiscal_years (id, code, start_date, end_date, status, tenant_id)
  VALUES (uuid_generate_v4(), 'EX-2026', '2026-01-01', '2026-12-31', 'open', v_tenant_id)
  RETURNING id INTO v_fy_2026_id;

  FOR v_month IN 1..12 LOOP
    v_date := make_date(2026, v_month, 1);
    INSERT INTO fiscal_periods (fiscal_year_id, period_number, period_label, start_date, end_date, status, tenant_id)
    VALUES (
      v_fy_2026_id,
      v_month,
      to_char(v_date, 'YYYY-MM'),
      v_date,
      (v_date + interval '1 month - 1 day')::date,
      CASE WHEN v_month <= 6 THEN 'closed' ELSE 'open' END,
      v_tenant_id
    )
    RETURNING id INTO v_tmp_id;
    v_period_2026_ids[v_month] := v_tmp_id;
  END LOOP;

  -- ============================================
  -- 8. INVOICES 2025 (all paid, closed year)
  -- ============================================
  INSERT INTO invoices (number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, tenant_id)
  VALUES
    ('FAC-2025-001', v_customer_1, 'Boulangerie Dupont', '2025-01-15', '2025-02-14', 'paid', 1000, 200, 1200, 1200, 0, v_tenant_id),
    ('FAC-2025-002', v_customer_2, 'Societe Martin SARL', '2025-01-28', '2025-02-27', 'paid', 2400, 480, 2880, 2880, 0, v_tenant_id),
    ('FAC-2025-003', v_customer_3, 'Tech Innov SAS', '2025-02-10', '2025-03-12', 'paid', 5000, 1000, 6000, 6000, 0, v_tenant_id),
    ('FAC-2025-004', v_customer_4, 'Restaurant Le Gourmet', '2025-02-20', '2025-03-22', 'paid', 800, 160, 960, 960, 0, v_tenant_id),
    ('FAC-2025-005', v_customer_5, 'Entreprise Bernard', '2025-03-05', '2025-04-04', 'paid', 3200, 640, 3840, 3840, 0, v_tenant_id),
    ('FAC-2025-006', v_customer_1, 'Boulangerie Dupont', '2025-03-18', '2025-04-17', 'paid', 1500, 300, 1800, 1800, 0, v_tenant_id),
    ('FAC-2025-007', v_customer_2, 'Societe Martin SARL', '2025-04-12', '2025-05-12', 'paid', 2800, 560, 3360, 3360, 0, v_tenant_id),
    ('FAC-2025-008', v_customer_3, 'Tech Innov SAS', '2025-04-25', '2025-05-25', 'paid', 4500, 900, 5400, 5400, 0, v_tenant_id),
    ('FAC-2025-009', v_customer_4, 'Restaurant Le Gourmet', '2025-05-08', '2025-06-07', 'paid', 1200, 240, 1440, 1440, 0, v_tenant_id),
    ('FAC-2025-010', v_customer_5, 'Entreprise Bernard', '2025-05-22', '2025-06-21', 'paid', 3600, 720, 4320, 4320, 0, v_tenant_id),
    ('FAC-2025-011', v_customer_1, 'Boulangerie Dupont', '2025-06-10', '2025-07-10', 'paid', 2000, 400, 2400, 2400, 0, v_tenant_id),
    ('FAC-2025-012', v_customer_3, 'Tech Innov SAS', '2025-06-28', '2025-07-28', 'paid', 6000, 1200, 7200, 7200, 0, v_tenant_id),
    ('FAC-2025-013', v_customer_2, 'Societe Martin SARL', '2025-07-15', '2025-08-14', 'paid', 3100, 620, 3720, 3720, 0, v_tenant_id),
    ('FAC-2025-014', v_customer_4, 'Restaurant Le Gourmet', '2025-07-30', '2025-08-29', 'paid', 950, 190, 1140, 1140, 0, v_tenant_id),
    ('FAC-2025-015', v_customer_5, 'Entreprise Bernard', '2025-08-12', '2025-09-11', 'paid', 2800, 560, 3360, 3360, 0, v_tenant_id),
    ('FAC-2025-016', v_customer_1, 'Boulangerie Dupont', '2025-08-25', '2025-09-24', 'paid', 1700, 340, 2040, 2040, 0, v_tenant_id),
    ('FAC-2025-017', v_customer_3, 'Tech Innov SAS', '2025-09-10', '2025-10-10', 'paid', 5200, 1040, 6240, 6240, 0, v_tenant_id),
    ('FAC-2025-018', v_customer_2, 'Societe Martin SARL', '2025-09-22', '2025-10-22', 'paid', 2900, 580, 3480, 3480, 0, v_tenant_id),
    ('FAC-2025-019', v_customer_4, 'Restaurant Le Gourmet', '2025-10-08', '2025-11-07', 'paid', 1100, 220, 1320, 1320, 0, v_tenant_id),
    ('FAC-2025-020', v_customer_5, 'Entreprise Bernard', '2025-10-20', '2025-11-19', 'paid', 3400, 680, 4080, 4080, 0, v_tenant_id),
    ('FAC-2025-021', v_customer_1, 'Boulangerie Dupont', '2025-11-12', '2025-12-12', 'paid', 2200, 440, 2640, 2640, 0, v_tenant_id),
    ('FAC-2025-022', v_customer_3, 'Tech Innov SAS', '2025-11-25', '2025-12-25', 'paid', 5800, 1160, 6960, 6960, 0, v_tenant_id),
    ('FAC-2025-023', v_customer_2, 'Societe Martin SARL', '2025-12-08', '2026-01-07', 'paid', 3300, 660, 3960, 3960, 0, v_tenant_id),
    ('FAC-2025-024', v_customer_4, 'Restaurant Le Gourmet', '2025-12-18', '2026-01-17', 'paid', 1400, 280, 1680, 1680, 0, v_tenant_id);

  -- ============================================
  -- 9. PURCHASE INVOICES 2025 (all paid)
  -- ============================================
  INSERT INTO purchase_invoices (number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, tenant_id)
  VALUES
    ('FAC-FOU-2025-001', v_supplier_1, 'Fournisseur Global SA', '2025-01-20', '2025-02-19', 'paid', 800, 160, 960, 960, 0, v_tenant_id),
    ('FAC-FOU-2025-002', v_supplier_2, 'Distrib Express', '2025-02-15', '2025-03-17', 'paid', 1200, 240, 1440, 1440, 0, v_tenant_id),
    ('FAC-FOU-2025-003', v_supplier_3, 'Papeterie Centrale', '2025-03-10', '2025-04-09', 'paid', 350, 70, 420, 420, 0, v_tenant_id),
    ('FAC-FOU-2025-004', v_supplier_1, 'Fournisseur Global SA', '2025-04-18', '2025-05-18', 'paid', 950, 190, 1140, 1140, 0, v_tenant_id),
    ('FAC-FOU-2025-005', v_supplier_2, 'Distrib Express', '2025-05-22', '2025-06-21', 'paid', 1400, 280, 1680, 1680, 0, v_tenant_id),
    ('FAC-FOU-2025-006', v_supplier_3, 'Papeterie Centrale', '2025-06-12', '2025-07-12', 'paid', 420, 84, 504, 504, 0, v_tenant_id),
    ('FAC-FOU-2025-007', v_supplier_1, 'Fournisseur Global SA', '2025-07-15', '2025-08-14', 'paid', 880, 176, 1056, 1056, 0, v_tenant_id),
    ('FAC-FOU-2025-008', v_supplier_2, 'Distrib Express', '2025-08-20', '2025-09-19', 'paid', 1300, 260, 1560, 1560, 0, v_tenant_id),
    ('FAC-FOU-2025-009', v_supplier_3, 'Papeterie Centrale', '2025-09-14', '2025-10-14', 'paid', 380, 76, 456, 456, 0, v_tenant_id),
    ('FAC-FOU-2025-010', v_supplier_1, 'Fournisseur Global SA', '2025-10-18', '2025-11-17', 'paid', 1020, 204, 1224, 1224, 0, v_tenant_id),
    ('FAC-FOU-2025-011', v_supplier_2, 'Distrib Express', '2025-11-20', '2025-12-20', 'paid', 1450, 290, 1740, 1740, 0, v_tenant_id),
    ('FAC-FOU-2025-012', v_supplier_3, 'Papeterie Centrale', '2025-12-10', '2026-01-09', 'paid', 400, 80, 480, 480, 0, v_tenant_id);

  -- ============================================
  -- 10. BANK TRANSACTIONS 2025
  -- ============================================
  INSERT INTO bank_transactions (account_id, date, description, reference, type, amount, category, reconciled, tenant_id)
  SELECT v_bank_1, i.due_date + interval '5 days', 'Encaissement ' || i.number, i.number, 'credit', i.total, 'sales', true, v_tenant_id
  FROM invoices i WHERE i.tenant_id = v_tenant_id AND i.date >= '2025-01-01' AND i.date <= '2025-12-31';

  INSERT INTO bank_transactions (account_id, date, description, reference, type, amount, category, reconciled, tenant_id)
  SELECT v_bank_1, p.due_date + interval '3 days', 'Paiement ' || p.number, p.number, 'debit', p.total, 'purchases', true, v_tenant_id
  FROM purchase_invoices p WHERE p.tenant_id = v_tenant_id AND p.date >= '2025-01-01' AND p.date <= '2025-12-31';

  -- ============================================
  -- 11. JOURNAL ENTRIES 2025 - Sales (VT)
  -- ============================================
  INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
  SELECT
    'VT-2025-' || lpad(row_number() over()::text, 3, '0'),
    i.date,
    'Vente ' || i.customer_name,
    i.number,
    'posted',
    'VT',
    v_period_ids[extract(month from i.date)::int],
    i.total,
    i.total,
    'closed',
    v_tenant_id
  FROM invoices i
  WHERE i.tenant_id = v_tenant_id AND i.date >= '2025-01-01' AND i.date <= '2025-12-31'
  ORDER BY i.date;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '411000', 'Clients', i.total, 0, 'Client ' || i.customer_name, 1, v_tenant_id
  FROM journal_entries je
  JOIN invoices i ON je.reference = i.number AND i.tenant_id = v_tenant_id
  WHERE je.journal_code = 'VT' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2025;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '707000', 'Ventes de marchandises', 0, i.subtotal, 'Vente HT', 2, v_tenant_id
  FROM journal_entries je
  JOIN invoices i ON je.reference = i.number AND i.tenant_id = v_tenant_id
  WHERE je.journal_code = 'VT' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2025;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '445710', 'TVA collectee 20%', 0, i.vat_total, 'TVA collectee', 3, v_tenant_id
  FROM journal_entries je
  JOIN invoices i ON je.reference = i.number AND i.tenant_id = v_tenant_id
  WHERE je.journal_code = 'VT' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2025;

  -- ============================================
  -- 12. JOURNAL ENTRIES 2025 - Purchases (AC)
  -- ============================================
  INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
  SELECT
    'AC-2025-' || lpad(row_number() over()::text, 3, '0'),
    p.date,
    'Achat ' || p.supplier_name,
    p.number,
    'posted',
    'AC',
    v_period_ids[extract(month from p.date)::int],
    p.total,
    p.total,
    'closed',
    v_tenant_id
  FROM purchase_invoices p
  WHERE p.tenant_id = v_tenant_id AND p.date >= '2025-01-01' AND p.date <= '2025-12-31'
  ORDER BY p.date;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '607000', 'Achats de marchandises', p.subtotal, 0, 'Achat HT', 1, v_tenant_id
  FROM journal_entries je
  JOIN purchase_invoices p ON je.reference = p.number AND p.tenant_id = v_tenant_id
  WHERE je.journal_code = 'AC' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2025;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '445660', 'TVA deductible', p.vat_total, 0, 'TVA deductible 20%', 2, v_tenant_id
  FROM journal_entries je
  JOIN purchase_invoices p ON je.reference = p.number AND p.tenant_id = v_tenant_id
  WHERE je.journal_code = 'AC' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2025;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '401000', 'Fournisseurs', 0, p.total, 'Fournisseur ' || p.supplier_name, 3, v_tenant_id
  FROM journal_entries je
  JOIN purchase_invoices p ON je.reference = p.number AND p.tenant_id = v_tenant_id
  WHERE je.journal_code = 'AC' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2025;

  -- ============================================
  -- 13. JOURNAL ENTRIES 2025 - Bank receipts (BQ)
  -- ============================================
  INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
  SELECT
    'BQ-2025-ENC-' || lpad(row_number() over()::text, 3, '0'),
    i.due_date + interval '5 days',
    'Encaissement client ' || i.number,
    i.number,
    'posted',
    'BQ',
    v_period_ids[extract(month from (i.due_date + interval '5 days'))::int],
    i.total,
    i.total,
    'closed',
    v_tenant_id
  FROM invoices i
  WHERE i.tenant_id = v_tenant_id AND i.date >= '2025-01-01' AND i.date <= '2025-12-31'
  ORDER BY i.date;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '512000', 'Banque', i.total, 0, 'Encaissement', 1, v_tenant_id
  FROM journal_entries je
  JOIN invoices i ON je.reference = i.number AND i.tenant_id = v_tenant_id
  WHERE je.journal_code = 'BQ' AND je.number LIKE 'BQ-2025-ENC-%' AND je.tenant_id = v_tenant_id;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '411000', 'Clients', 0, i.total, 'Client - paiement recu', 2, v_tenant_id
  FROM journal_entries je
  JOIN invoices i ON je.reference = i.number AND i.tenant_id = v_tenant_id
  WHERE je.journal_code = 'BQ' AND je.number LIKE 'BQ-2025-ENC-%' AND je.tenant_id = v_tenant_id;

  -- ============================================
  -- 14. JOURNAL ENTRIES 2025 - Bank payments (BQ)
  -- ============================================
  INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
  SELECT
    'BQ-2025-DEC-' || lpad(row_number() over()::text, 3, '0'),
    p.due_date + interval '3 days',
    'Paiement fournisseur ' || p.number,
    p.number,
    'posted',
    'BQ',
    v_period_ids[extract(month from (p.due_date + interval '3 days'))::int],
    p.total,
    p.total,
    'closed',
    v_tenant_id
  FROM purchase_invoices p
  WHERE p.tenant_id = v_tenant_id AND p.date >= '2025-01-01' AND p.date <= '2025-12-31'
  ORDER BY p.date;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '401000', 'Fournisseurs', p.total, 0, 'Paiement fournisseur', 1, v_tenant_id
  FROM journal_entries je
  JOIN purchase_invoices p ON je.reference = p.number AND p.tenant_id = v_tenant_id
  WHERE je.journal_code = 'BQ' AND je.number LIKE 'BQ-2025-DEC-%' AND je.tenant_id = v_tenant_id;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '512000', 'Banque', 0, p.total, 'Decaissement', 2, v_tenant_id
  FROM journal_entries je
  JOIN purchase_invoices p ON je.reference = p.number AND p.tenant_id = v_tenant_id
  WHERE je.journal_code = 'BQ' AND je.number LIKE 'BQ-2025-DEC-%' AND je.tenant_id = v_tenant_id;

  -- ============================================
  -- 15. JOURNAL ENTRIES 2025 - OD (salaries + rent monthly)
  -- ============================================
  FOR v_month IN 1..12 LOOP
    v_date := make_date(2025, v_month, 28);

    INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
    VALUES ('OD-2025-SAL-' || lpad(v_month::text, 2, '0'), v_date, 'Salaires mois ' || to_char(v_date, 'YYYY-MM'), 'SAL-' || v_month, 'posted', 'OD', v_period_ids[v_month], 5000, 5000, 'closed', v_tenant_id)
    RETURNING id INTO v_je_id;

    INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id) VALUES
      (v_je_id, '641000', 'Remunerations du personnel', 4000, 0, 'Salaire brut', 1, v_tenant_id),
      (v_je_id, '645000', 'Charges sociales', 1000, 0, 'Charges patronales', 2, v_tenant_id),
      (v_je_id, '421000', 'Personnel - remunerations dues', 0, 3200, 'Net a payer', 3, v_tenant_id),
      (v_je_id, '431000', 'Securite sociale', 0, 1800, 'Charges sociales', 4, v_tenant_id);

    INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
    VALUES ('OD-2025-LOC-' || lpad(v_month::text, 2, '0'), v_date, 'Loyer mois ' || to_char(v_date, 'YYYY-MM'), 'LOC-' || v_month, 'posted', 'OD', v_period_ids[v_month], 1200, 1200, 'closed', v_tenant_id)
    RETURNING id INTO v_je_id;

    INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id) VALUES
      (v_je_id, '613000', 'Locations', 1000, 0, 'Loyer HT', 1, v_tenant_id),
      (v_je_id, '445660', 'TVA deductible', 200, 0, 'TVA 20%', 2, v_tenant_id),
      (v_je_id, '512000', 'Banque', 0, 1200, 'Prelevement automatique', 3, v_tenant_id);
  END LOOP;

  -- Depreciation OD (Dec 2025)
  INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
  VALUES ('OD-2025-AMORT', '2025-12-31', 'Dotations aux amortissements 2025', 'AMORT-2025', 'posted', 'OD', v_period_ids[12], 3000, 3000, 'closed', v_tenant_id)
  RETURNING id INTO v_je_id;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id) VALUES
    (v_je_id, '681000', 'Dotations aux amortissements', 3000, 0, 'Dotation annuelle', 1, v_tenant_id),
    (v_je_id, '281000', 'Amortissements des immobilisations', 0, 3000, 'Amortissements cumules', 2, v_tenant_id);

  -- ============================================
  -- 16. VAT RETURNS 2025
  -- ============================================
  INSERT INTO vat_returns (period_start, period_end, status, box1_output_vat, box2_input_vat, box3_vat_due, box4_repayment_due, box5_net_vat, total_sales, total_purchases, submitted_date, tenant_id)
  VALUES
    ('2025-01-01', '2025-03-31', 'paid', 5280, 1380, 3900, 0, 3900, 26400, 6900, '2025-04-20', v_tenant_id),
    ('2025-04-01', '2025-06-30', 'paid', 5640, 1470, 4170, 0, 4170, 28200, 7350, '2025-07-20', v_tenant_id),
    ('2025-07-01', '2025-09-30', 'paid', 5220, 1290, 3930, 0, 3930, 26100, 6450, '2025-10-20', v_tenant_id),
    ('2025-10-01', '2025-12-31', 'paid', 5460, 1410, 4050, 0, 4050, 27300, 7050, '2026-01-20', v_tenant_id);

  -- ============================================
  -- 17. INVOICES 2026 (Jan-Jun paid, Jul sent/overdue)
  -- ============================================
  INSERT INTO invoices (number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, tenant_id)
  VALUES
    ('FAC-2026-001', v_customer_1, 'Boulangerie Dupont', '2026-01-12', '2026-02-11', 'paid', 1800, 360, 2160, 2160, 0, v_tenant_id),
    ('FAC-2026-002', v_customer_3, 'Tech Innov SAS', '2026-01-25', '2026-02-24', 'paid', 5500, 1100, 6600, 6600, 0, v_tenant_id),
    ('FAC-2026-003', v_customer_2, 'Societe Martin SARL', '2026-02-10', '2026-03-12', 'paid', 3000, 600, 3600, 3600, 0, v_tenant_id),
    ('FAC-2026-004', v_customer_5, 'Entreprise Bernard', '2026-02-22', '2026-03-24', 'paid', 3800, 760, 4560, 4560, 0, v_tenant_id),
    ('FAC-2026-005', v_customer_4, 'Restaurant Le Gourmet', '2026-03-08', '2026-04-07', 'paid', 1300, 260, 1560, 1560, 0, v_tenant_id),
    ('FAC-2026-006', v_customer_1, 'Boulangerie Dupont', '2026-03-20', '2026-04-19', 'paid', 2100, 420, 2520, 2520, 0, v_tenant_id),
    ('FAC-2026-007', v_customer_3, 'Tech Innov SAS', '2026-04-12', '2026-05-12', 'paid', 4800, 960, 5760, 5760, 0, v_tenant_id),
    ('FAC-2026-008', v_customer_2, 'Societe Martin SARL', '2026-04-25', '2026-05-25', 'paid', 2600, 520, 3120, 3120, 0, v_tenant_id),
    ('FAC-2026-009', v_customer_5, 'Entreprise Bernard', '2026-05-10', '2026-06-09', 'paid', 3500, 700, 4200, 4200, 0, v_tenant_id),
    ('FAC-2026-010', v_customer_4, 'Restaurant Le Gourmet', '2026-05-22', '2026-06-21', 'paid', 1450, 290, 1740, 1740, 0, v_tenant_id),
    ('FAC-2026-011', v_customer_1, 'Boulangerie Dupont', '2026-06-12', '2026-07-12', 'paid', 2300, 460, 2760, 2760, 0, v_tenant_id),
    ('FAC-2026-012', v_customer_3, 'Tech Innov SAS', '2026-06-28', '2026-07-28', 'paid', 6200, 1240, 7440, 7440, 0, v_tenant_id),
    ('FAC-2026-013', v_customer_2, 'Societe Martin SARL', '2026-07-10', '2026-08-09', 'sent', 3400, 680, 4080, 0, 4080, v_tenant_id),
    ('FAC-2026-014', v_customer_5, 'Entreprise Bernard', '2026-07-01', '2026-07-31', 'overdue', 2900, 580, 3480, 0, 3480, v_tenant_id),
    ('FAC-2026-015', v_customer_4, 'Restaurant Le Gourmet', '2026-07-15', '2026-08-14', 'sent', 1200, 240, 1440, 0, 1440, v_tenant_id);

  -- ============================================
  -- 18. PURCHASE INVOICES 2026 (Jan-Jun paid, Jul sent)
  -- ============================================
  INSERT INTO purchase_invoices (number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, tenant_id)
  VALUES
    ('FAC-FOU-2026-001', v_supplier_1, 'Fournisseur Global SA', '2026-01-18', '2026-02-17', 'paid', 900, 180, 1080, 1080, 0, v_tenant_id),
    ('FAC-FOU-2026-002', v_supplier_2, 'Distrib Express', '2026-02-14', '2026-03-16', 'paid', 1350, 270, 1620, 1620, 0, v_tenant_id),
    ('FAC-FOU-2026-003', v_supplier_3, 'Papeterie Centrale', '2026-03-12', '2026-04-11', 'paid', 380, 76, 456, 456, 0, v_tenant_id),
    ('FAC-FOU-2026-004', v_supplier_1, 'Fournisseur Global SA', '2026-04-16', '2026-05-16', 'paid', 970, 194, 1164, 1164, 0, v_tenant_id),
    ('FAC-FOU-2026-005', v_supplier_2, 'Distrib Express', '2026-05-20', '2026-06-19', 'paid', 1420, 284, 1704, 1704, 0, v_tenant_id),
    ('FAC-FOU-2026-006', v_supplier_3, 'Papeterie Centrale', '2026-06-10', '2026-07-10', 'paid', 410, 82, 492, 492, 0, v_tenant_id),
    ('FAC-FOU-2026-007', v_supplier_1, 'Fournisseur Global SA', '2026-07-12', '2026-08-11', 'sent', 1050, 210, 1260, 0, 1260, v_tenant_id),
    ('FAC-FOU-2026-008', v_supplier_2, 'Distrib Express', '2026-07-18', '2026-08-17', 'sent', 1380, 276, 1656, 0, 1656, v_tenant_id);

  -- ============================================
  -- 19. BANK TRANSACTIONS 2026 (Jan-Jun)
  -- ============================================
  INSERT INTO bank_transactions (account_id, date, description, reference, type, amount, category, reconciled, tenant_id)
  SELECT v_bank_1, i.due_date + interval '5 days', 'Encaissement ' || i.number, i.number, 'credit', i.total, 'sales', true, v_tenant_id
  FROM invoices i WHERE i.tenant_id = v_tenant_id AND i.date >= '2026-01-01' AND i.date <= '2026-06-30' AND i.status = 'paid';

  INSERT INTO bank_transactions (account_id, date, description, reference, type, amount, category, reconciled, tenant_id)
  SELECT v_bank_1, p.due_date + interval '3 days', 'Paiement ' || p.number, p.number, 'debit', p.total, 'purchases', true, v_tenant_id
  FROM purchase_invoices p WHERE p.tenant_id = v_tenant_id AND p.date >= '2026-01-01' AND p.date <= '2026-06-30' AND p.status = 'paid';

  -- ============================================
  -- 20. JOURNAL ENTRIES 2026 - Sales (VT)
  -- ============================================
  INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
  SELECT
    'VT-2026-' || lpad(row_number() over()::text, 3, '0'),
    i.date,
    'Vente ' || i.customer_name,
    i.number,
    'posted',
    'VT',
    v_period_2026_ids[extract(month from i.date)::int],
    i.total,
    i.total,
    CASE WHEN extract(month from i.date) <= 6 THEN 'closed' ELSE 'open' END,
    v_tenant_id
  FROM invoices i
  WHERE i.tenant_id = v_tenant_id AND i.date >= '2026-01-01' AND i.date <= '2026-12-31'
  ORDER BY i.date;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '411000', 'Clients', i.total, 0, 'Client ' || i.customer_name, 1, v_tenant_id
  FROM journal_entries je JOIN invoices i ON je.reference = i.number AND i.tenant_id = v_tenant_id
  WHERE je.journal_code = 'VT' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2026;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '707000', 'Ventes de marchandises', 0, i.subtotal, 'Vente HT', 2, v_tenant_id
  FROM journal_entries je JOIN invoices i ON je.reference = i.number AND i.tenant_id = v_tenant_id
  WHERE je.journal_code = 'VT' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2026;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '445710', 'TVA collectee 20%', 0, i.vat_total, 'TVA collectee', 3, v_tenant_id
  FROM journal_entries je JOIN invoices i ON je.reference = i.number AND i.tenant_id = v_tenant_id
  WHERE je.journal_code = 'VT' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2026;

  -- ============================================
  -- 21. JOURNAL ENTRIES 2026 - Purchases (AC)
  -- ============================================
  INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
  SELECT
    'AC-2026-' || lpad(row_number() over()::text, 3, '0'),
    p.date,
    'Achat ' || p.supplier_name,
    p.number,
    'posted',
    'AC',
    v_period_2026_ids[extract(month from p.date)::int],
    p.total,
    p.total,
    CASE WHEN extract(month from p.date) <= 6 THEN 'closed' ELSE 'open' END,
    v_tenant_id
  FROM purchase_invoices p
  WHERE p.tenant_id = v_tenant_id AND p.date >= '2026-01-01' AND p.date <= '2026-12-31'
  ORDER BY p.date;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '607000', 'Achats de marchandises', p.subtotal, 0, 'Achat HT', 1, v_tenant_id
  FROM journal_entries je JOIN purchase_invoices p ON je.reference = p.number AND p.tenant_id = v_tenant_id
  WHERE je.journal_code = 'AC' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2026;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '445660', 'TVA deductible', p.vat_total, 0, 'TVA deductible 20%', 2, v_tenant_id
  FROM journal_entries je JOIN purchase_invoices p ON je.reference = p.number AND p.tenant_id = v_tenant_id
  WHERE je.journal_code = 'AC' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2026;

  INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id)
  SELECT je.id, '401000', 'Fournisseurs', 0, p.total, 'Fournisseur ' || p.supplier_name, 3, v_tenant_id
  FROM journal_entries je JOIN purchase_invoices p ON je.reference = p.number AND p.tenant_id = v_tenant_id
  WHERE je.journal_code = 'AC' AND je.tenant_id = v_tenant_id AND extract(year from je.date) = 2026;

  -- ============================================
  -- 22. JOURNAL ENTRIES 2026 - OD (salaries + rent Jan-Jun)
  -- ============================================
  FOR v_month IN 1..6 LOOP
    v_date := make_date(2026, v_month, 28);

    INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
    VALUES ('OD-2026-SAL-' || lpad(v_month::text, 2, '0'), v_date, 'Salaires mois ' || to_char(v_date, 'YYYY-MM'), 'SAL-' || v_month, 'posted', 'OD', v_period_2026_ids[v_month], 5200, 5200, 'closed', v_tenant_id)
    RETURNING id INTO v_je_id;

    INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id) VALUES
      (v_je_id, '641000', 'Remunerations du personnel', 4200, 0, 'Salaire brut', 1, v_tenant_id),
      (v_je_id, '645000', 'Charges sociales', 1000, 0, 'Charges patronales', 2, v_tenant_id),
      (v_je_id, '421000', 'Personnel - remunerations dues', 0, 3300, 'Net a payer', 3, v_tenant_id),
      (v_je_id, '431000', 'Securite sociale', 0, 1900, 'Charges sociales', 4, v_tenant_id);

    INSERT INTO journal_entries (number, date, description, reference, status, journal_code, fiscal_period_id, total_debit, total_credit, status_detail, tenant_id)
    VALUES ('OD-2026-LOC-' || lpad(v_month::text, 2, '0'), v_date, 'Loyer mois ' || to_char(v_date, 'YYYY-MM'), 'LOC-' || v_month, 'posted', 'OD', v_period_2026_ids[v_month], 1200, 1200, 'closed', v_tenant_id)
    RETURNING id INTO v_je_id;

    INSERT INTO journal_lines (journal_id, account_code, account_name, debit, credit, description, line_order, tenant_id) VALUES
      (v_je_id, '613000', 'Locations', 1000, 0, 'Loyer HT', 1, v_tenant_id),
      (v_je_id, '445660', 'TVA deductible', 200, 0, 'TVA 20%', 2, v_tenant_id),
      (v_je_id, '512000', 'Banque', 0, 1200, 'Prelevement automatique', 3, v_tenant_id);
  END LOOP;

  -- ============================================
  -- 23. UPDATE CUSTOMER/SUPPLIER BALANCES (2026 outstanding)
  -- ============================================
  UPDATE customers SET balance = (
    SELECT COALESCE(SUM(amount_due), 0) FROM invoices WHERE customer_id = customers.id AND status IN ('sent', 'overdue') AND tenant_id = v_tenant_id
  ) WHERE tenant_id = v_tenant_id;

  UPDATE suppliers SET balance = (
    SELECT COALESCE(SUM(amount_due), 0) FROM purchase_invoices WHERE supplier_id = suppliers.id AND status NOT IN ('paid', 'cancelled', 'draft') AND tenant_id = v_tenant_id
  ) WHERE tenant_id = v_tenant_id;

  RAISE NOTICE 'Seed data created successfully for tenant %', v_tenant_id;
  RAISE NOTICE '2025: 24 invoices (all paid), 12 purchase invoices (all paid), 12 months journal entries, fiscal year CLOSED';
  RAISE NOTICE '2026: 15 invoices (12 paid, 2 sent, 1 overdue), 8 purchase invoices (6 paid, 2 sent), 6 months journal entries, fiscal year OPEN';
END $$;
