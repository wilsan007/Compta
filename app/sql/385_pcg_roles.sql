-- ═══════════════════════════════════════════════════════════════════════════
-- 385 — pcg_roles : les RÔLES du pack PCG (le PCG en données)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Les 67 rôles de l'annexe B, MAPPÉS sur les comptes du PCG.
-- **Prérequis de `LOC1-06`** : réécrire les triggers de ventes/achats sur
-- `resolve_account(...)` suppose que le pack PORTE ses rôles — sinon la
-- résolution échoue (`ROLE_NON_MAPPE`). C'est aussi la recette de `LOC1-05`
-- (« société FR : `resolve_account(t,'CLIENTS')` = `411000` »). Cahier §5,
-- tâches LOC1-13 (« PCG en données ») et LOC1-56 (pack FR à l'identique).
--
-- SUR LE RÉFÉRENTIEL, PAS SUR LE PAYS. L'annexe C range les rôles sous
-- `PCG/roles.yaml` (le référentiel), et `FR/` (le pays) n'en porte que ses
-- écarts. On sème donc sur **`PCG`** : `FR` les hérite par la lignée
-- (`pack_lineage` → `pack_account_role`).
--
-- DEUX RÔLES VOLONTAIREMENT ABSENTS : `IMMOBILISATIONS` et `AMORTISSEMENTS`
-- n'ont pas UN compte mais un compte PAR CATÉGORIE (`21xxxx`, `281xxx`) :
-- ils se résolvent par le contexte (`asset_family_id`), pas par le pack.
--
-- ⚠ Les comptes `418100`, `476000`, `477000`, `695000` (marqués « à créer » au
-- cahier) sont mappés À LEUR NUMÉRO PRÉVU : si le plan d'une société ne les
-- contient pas encore, `resolve_account` lèvera `COMPTE_ABSENT` — c'est le
-- comportement voulu (échec explicite), pas un repli silencieux.
--
-- REJOUABLE : `INSERT … ON CONFLICT DO NOTHING` (le pack est la clé).
--
-- Numéro pris le 2026-10-05T20:36:36.567Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Les rôles de comptes du référentiel PCG (annexe B.1)
-- ─────────────────────────────────────────────────────────────
INSERT INTO pack_account_roles (pack_code, role, account_code) VALUES
  ('PCG', 'CLIENTS',                            '411000'),
  ('PCG', 'CLIENTS_DOUTEUX',                    '416000'),
  ('PCG', 'CLIENTS_EFFETS_A_RECEVOIR',          '413000'),
  ('PCG', 'CLIENTS_AVANCES_RECUES',             '419100'),
  ('PCG', 'CLIENTS_FACTURES_A_ETABLIR',         '418100'),
  ('PCG', 'FOURNISSEURS',                       '401000'),
  ('PCG', 'FOURNISSEURS_IMMOBILISATIONS',       '404000'),
  ('PCG', 'FOURNISSEURS_AVANCES_VERSEES',       '409100'),
  ('PCG', 'FOURNISSEURS_FACTURES_NON_PARVENUES','408100'),
  ('PCG', 'FOURNISSEURS_EFFETS_A_PAYER',        '403000'),
  ('PCG', 'TVA_COLLECTEE',                      '445710'),
  ('PCG', 'TVA_DEDUCTIBLE_BIENS_SERVICES',      '445660'),
  ('PCG', 'TVA_DEDUCTIBLE_IMMOBILISATIONS',     '445620'),
  ('PCG', 'TVA_A_DECAISSER',                    '445510'),
  ('PCG', 'CREDIT_TVA',                         '445670'),
  ('PCG', 'TVA_EN_ATTENTE',                     '445800'),
  ('PCG', 'IMPOT_BENEFICES_CHARGE',             '695000'),
  ('PCG', 'ETAT_IMPOT_BENEFICES',               '444000'),
  ('PCG', 'ETAT_RETENUES_A_LA_SOURCE',          '447000'),
  ('PCG', 'IMPOTS_TAXES_CHARGE',                '635000'),
  ('PCG', 'ETAT_IMPOT_SALAIRES',                '442000'),
  ('PCG', 'SALAIRES_BRUTS',                     '641000'),
  ('PCG', 'CHARGES_SOCIALES_PATRONALES',        '645000'),
  ('PCG', 'PERSONNEL_REMUNERATIONS_DUES',       '421000'),
  ('PCG', 'PERSONNEL_AVANCES',                  '425000'),
  ('PCG', 'ORGANISME_SOCIAL',                   '431000'),
  ('PCG', 'BANQUE',                             '512000'),
  ('PCG', 'CAISSE',                             '530000'),
  ('PCG', 'CAISSE_POS',                         '531000'),
  ('PCG', 'VIREMENTS_INTERNES',                 '580000'),
  ('PCG', 'MOYENS_PAIEMENT_A_ENCAISSER',        '511000'),
  ('PCG', 'VENTES_MARCHANDISES',                '707000'),
  ('PCG', 'VENTES_PRODUITS_FINIS',              '701000'),
  ('PCG', 'PRESTATIONS_SERVICES',               '706000')
ON CONFLICT (pack_code, role) DO NOTHING;

INSERT INTO pack_account_roles (pack_code, role, account_code) VALUES
  ('PCG', 'RRR_ACCORDES',                       '709000'),
  ('PCG', 'ACHATS_MARCHANDISES',                '607000'),
  ('PCG', 'ACHATS_MATIERES',                    '601000'),
  ('PCG', 'SERVICES_EXTERIEURS',                '604000'),
  ('PCG', 'SOUS_TRAITANCE',                     '611000'),
  ('PCG', 'RRR_OBTENUS',                        '609000'),
  ('PCG', 'ESCOMPTES_ACCORDES',                 '665000'),
  ('PCG', 'ESCOMPTES_OBTENUS',                  '765000'),
  ('PCG', 'GAINS_CHANGE',                       '766000'),
  ('PCG', 'PERTES_CHANGE',                      '666000'),
  ('PCG', 'ECART_CONVERSION_ACTIF',             '476000'),
  ('PCG', 'ECART_CONVERSION_PASSIF',            '477000'),
  ('PCG', 'PERTES_CREANCES_IRRECOUVRABLES',     '654000'),
  ('PCG', 'STOCK_MARCHANDISES',                 '370000'),
  ('PCG', 'STOCK_MATIERES',                     '310000'),
  ('PCG', 'STOCK_PRODUITS_FINIS',               '355000'),
  ('PCG', 'VARIATION_STOCK_MARCHANDISES',       '603700'),
  ('PCG', 'VARIATION_STOCK_MATIERES',           '603100'),
  ('PCG', 'PRODUCTION_STOCKEE',                 '713500'),
  ('PCG', 'DOTATIONS_AMORTISSEMENTS',           '681100'),
  ('PCG', 'VALEUR_COMPTABLE_CESSIONS',          '675000'),
  ('PCG', 'PRODUITS_CESSIONS',                  '775000'),
  ('PCG', 'REPRISE_SUBVENTIONS_INVESTISSEMENT', '777000'),
  ('PCG', 'RESULTAT_BENEFICE',                  '120000'),
  ('PCG', 'RESULTAT_PERTE',                     '129000'),
  ('PCG', 'REPORT_A_NOUVEAU_CREDITEUR',         '110000'),
  ('PCG', 'REPORT_A_NOUVEAU_DEBITEUR',          '119000'),
  ('PCG', 'RESERVE_LEGALE',                     '106100'),
  ('PCG', 'AUTRES_RESERVES',                    '106800'),
  ('PCG', 'ASSOCIES_DIVIDENDES_A_PAYER',        '457000'),
  ('PCG', 'COMPTE_ATTENTE',                     '471000')
ON CONFLICT (pack_code, role) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 2. Les rôles de JOURNAUX du référentiel PCG (annexe B.2)
--    `JOURNAL_PAIE` est LAISSÉ ABSENT : le pack PCG ne définit pas encore de
--    journal de paie (le cahier le note « à créer »). Le mapper à `'OD'`
--    ferait disparaître la question ; on préfère l'échec explicite quand la
--    paie l'exigera (LOC1-07).
-- ─────────────────────────────────────────────────────────────
INSERT INTO pack_journal_roles (pack_code, role, journal_code, journal_type) VALUES
  ('PCG', 'JOURNAL_VENTES',     'VT', 'sale'),
  ('PCG', 'JOURNAL_ACHATS',     'AC', 'purchase'),
  ('PCG', 'JOURNAL_BANQUE',     'BQ', 'bank'),
  ('PCG', 'JOURNAL_CAISSE',     'CA', 'cash'),
  ('PCG', 'JOURNAL_OD',         'OD', 'general'),
  ('PCG', 'JOURNAL_A_NOUVEAUX', 'AN', 'opening'),
  ('PCG', 'JOURNAL_STOCK',      'ST', 'general')
ON CONFLICT (pack_code, role) DO NOTHING;
