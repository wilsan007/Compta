-- ═══════════════════════════════════════════════════════════════════════════
-- 450 — Partie 5 : le registre des types de document des chaînages
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Défaut mesuré le 02/10/2026 : `document_links.amont_type` et `aval_type` sont
-- des textes libres. La base accepte un lien de type « commande » ou
-- « livraison » alors qu'aucune table de ce nom n'existe (relevé : 36 liens de
-- ce genre après les suites 252 et 402).
--
-- Ce fichier :
--   1. crée `chain_document_types` (un type = une table, et sa table de lignes) ;
--   2. y inscrit les 27 types réellement employés par les 23 maillons ;
--   3. pose une clé étrangère de `amont_type` et `aval_type` vers ce registre ;
--   4. ajoute l'index qui manquait pour retrouver un lien par sa ligne amont.
--
-- RÈGLE POUR LA SUITE : tout nouveau maillon qui emploie un type absent d'ici
-- l'inscrit DANS LA MÊME MIGRATION, et pose la garde de suppression (453) sur
-- sa table. La suite 450 (T01, T11) échoue sinon.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.chain_document_types (
  code        text PRIMARY KEY,
  table_name  text NOT NULL UNIQUE,
  ligne_table text,
  libelle_fr  text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chain_document_types_code_check CHECK (code = table_name),
  CONSTRAINT chain_document_types_libelle_check CHECK (btrim(libelle_fr) <> '')
);

COMMENT ON TABLE public.chain_document_types IS
  '450 : registre des types de document qu''un lien de chaînage peut relier. Un type = une table (code = nom de la table), avec sa table de lignes si le maillon lie ligne à ligne. Lu par link_documents (451), par la garde de suppression (453) et par INV-19 (455).';

-- Lecture pour tout utilisateur connecté (l'écran lit les libellés), écriture
-- réservée aux migrations : aucune politique d'écriture, aucun droit d'écriture.
ALTER TABLE public.chain_document_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_document_types_lecture ON public.chain_document_types;
CREATE POLICY chain_document_types_lecture ON public.chain_document_types
  FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.chain_document_types FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.chain_document_types TO authenticated;

INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('bank_accounts',             'bank_accounts',             NULL,                  'Compte bancaire'),
  ('bank_transactions',         'bank_transactions',         NULL,                  'Opération bancaire'),
  ('chart_accounts',            'chart_accounts',            NULL,                  'Compte comptable'),
  ('credit_notes',              'credit_notes',              NULL,                  'Avoir client'),
  ('customer_payments',         'customer_payments',         NULL,                  'Règlement client'),
  ('delivery_notes',            'delivery_notes',            'delivery_note_lines', 'Bon de livraison'),
  ('expense_reports',           'expense_reports',           NULL,                  'Note de frais'),
  ('goods_receipts',            'goods_receipts',            'goods_receipt_lines', 'Réception de marchandise'),
  ('invoice_lines',             'invoice_lines',             NULL,                  'Ligne de facture'),
  ('invoices',                  'invoices',                  NULL,                  'Facture client'),
  ('journal_entries',           'journal_entries',           NULL,                  'Écriture comptable'),
  ('journal_lines',             'journal_lines',             NULL,                  'Ligne d''écriture'),
  ('journals',                  'journals',                  NULL,                  'Journal comptable'),
  ('manufacturing_orders',      'manufacturing_orders',      NULL,                  'Ordre de fabrication'),
  ('payroll_variable_elements', 'payroll_variable_elements', NULL,                  'Élément variable de paie'),
  ('pay_runs',                  'pay_runs',                  NULL,                  'Lot de paie'),
  ('pos_payments',              'pos_payments',              NULL,                  'Paiement de caisse'),
  ('pos_sessions',              'pos_sessions',              NULL,                  'Session de caisse'),
  ('pos_tickets',               'pos_tickets',               NULL,                  'Ticket de caisse'),
  ('project_time_entries',      'project_time_entries',      NULL,                  'Temps passé sur projet'),
  ('purchase_invoices',         'purchase_invoices',         NULL,                  'Facture fournisseur'),
  ('sales_orders',              'sales_orders',              'sales_order_lines',   'Commande client'),
  ('stock_movements',           'stock_movements',           NULL,                  'Mouvement de stock'),
  ('stock_reservations',        'stock_reservations',        NULL,                  'Réservation de stock'),
  ('st_receipts',               'st_receipts',               'st_receipt_lines',    'Réception de sous-traitance'),
  ('st_shipments',              'st_shipments',              'st_shipment_lines',   'Expédition de sous-traitance'),
  ('supplier_payments',         'supplier_payments',         NULL,                  'Règlement fournisseur')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- Chaque table inscrite existe, porte `id` et `tenant_id` : sinon la garde et le
-- contrôle d'existence ne pourraient pas fonctionner. On le vérifie ICI, à
-- l'application, pour qu'une faute de frappe fasse échouer la migration.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT t.code, x.tbl
    FROM public.chain_document_types t
    CROSS JOIN LATERAL (VALUES (t.table_name), (t.ligne_table)) AS x(tbl)
    WHERE x.tbl IS NOT NULL
  LOOP
    IF to_regclass('public.' || r.tbl) IS NULL THEN
      RAISE EXCEPTION '450 : le type % désigne la table % qui n''existe pas.', r.code, r.tbl;
    END IF;
    IF (SELECT count(*) FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = r.tbl
           AND column_name IN ('id', 'tenant_id')) <> 2 THEN
      RAISE EXCEPTION '450 : la table % (type %) doit porter id ET tenant_id.', r.tbl, r.code;
    END IF;
  END LOOP;
END $$;

-- Les clés étrangères sur les TYPES. Posées « NOT VALID » puis validées : sur une
-- base neuve (CI, production où les chaînages ne sont pas encore déployés) la
-- validation passe ; sur une base de développement qui garde des liens de test
-- à type inventé, la contrainte protège quand même toute NOUVELLE ligne et un
-- avis nomme les types à nettoyer.
ALTER TABLE public.document_links
  DROP CONSTRAINT IF EXISTS document_links_amont_type_fk,
  DROP CONSTRAINT IF EXISTS document_links_aval_type_fk;
ALTER TABLE public.document_links
  ADD CONSTRAINT document_links_amont_type_fk FOREIGN KEY (amont_type)
    REFERENCES public.chain_document_types (code) NOT VALID,
  ADD CONSTRAINT document_links_aval_type_fk FOREIGN KEY (aval_type)
    REFERENCES public.chain_document_types (code) NOT VALID;

DO $$
DECLARE v_inconnus text;
BEGIN
  SELECT string_agg(DISTINCT t, ', ') INTO v_inconnus
  FROM (SELECT amont_type AS t FROM public.document_links
        UNION SELECT aval_type FROM public.document_links) x
  WHERE NOT EXISTS (SELECT 1 FROM public.chain_document_types d WHERE d.code = x.t);
  IF v_inconnus IS NULL THEN
    ALTER TABLE public.document_links VALIDATE CONSTRAINT document_links_amont_type_fk;
    ALTER TABLE public.document_links VALIDATE CONSTRAINT document_links_aval_type_fk;
  ELSE
    RAISE NOTICE '450 : types inconnus présents (%) — contraintes posées NOT VALID. Nettoyez ces liens de test puis : ALTER TABLE document_links VALIDATE CONSTRAINT document_links_amont_type_fk (et _aval_type_fk).', v_inconnus;
  END IF;
END $$;

-- La garde de suppression (453) cherche un lien par sa ligne amont : il faut un
-- index (seul `aval_ligne_id` en avait un).
CREATE INDEX IF NOT EXISTS ix_document_links_amont_ligne
  ON public.document_links (tenant_id, amont_ligne_id)
  WHERE amont_ligne_id IS NOT NULL AND etat = 'actif';
