-- ============================================================
-- 187_accounting_kernel_strict.sql — lot C du plan correctif du 21/09
-- (doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md, vague V2)
--
-- Le noyau de saisie acceptait des écritures qu'aucun logiciel comptable
-- n'accepte. Défauts prouvés par sql/178_accounting_kernel_tests.sql :
--
--   AUD-C01  tolérance d'équilibre de 0,01 : 50 écritures à un centime d'écart
--            faussaient la balance de 0,50 (A02, A03)
--   AUD-C02  en-tête inséré directement en « posted », sans ligne (A04)
--   AUD-C03  ligne au débit ET au crédit, ou ligne 0/0 (A05) ; une facture
--            exonérée générait une ligne de TVA 0/0 (A09)
--   AUD-C04  compte absent du plan, déprécié ou de regroupement accepté (A06, A08)
--   AUD-C05  saisie dans un exercice clos non découpé en périodes (B02)
--   AUD-C06  écriture datée hors de tout exercice (B03)
--   AUD-C07  période close contournée sans contexte tenant : le contrôle lisait
--            current_tenant_id() et non la société de l'écriture (B04)
--   AUD-C08  fiscal_period_id jamais renseigné : grille de saisie vide (C05)
--   AUD-C09  deux écritures au même numéro si journal_code est NULL (C02)
--   AUD-C11  aucun numéro définitif continu attribué à la validation (C06)
--
-- Conséquences voulues sur les flux existants :
--   - les écritures automatiques imputaient des comptes absents du plan semé
--     (4457000, 4456000, 641/645/431/421, 713550, 665/666/766/654) : elles
--     imputent désormais les comptes du plan (445710, 445660, 641000…) ;
--   - les journaux utilisés par les écritures automatiques (ST, OF, POS, CL)
--     sont créés pour chaque société ;
--   - une ligne 0/0 (ligne de grille vide, TVA exonérée) n'est pas enregistrée ;
--     une ligne ramenée à 0/0 par modification bloque la validation.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Journaux standard (AUD-C09) — les écritures automatiques en dépendent
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION ensure_standard_journals(p_tenant_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO journals (tenant_id, code, name, type, account_counterpart, status, locked, next_number)
  VALUES
    (p_tenant_id, 'VT',  'Journal des ventes',       'sale',     '411000', 'active', false, 1),
    (p_tenant_id, 'AC',  'Journal des achats',       'purchase', '401000', 'active', false, 1),
    (p_tenant_id, 'BQ',  'Journal de banque',        'bank',     '512000', 'active', false, 1),
    (p_tenant_id, 'CA',  'Journal de caisse',        'cash',     '530000', 'active', false, 1),
    (p_tenant_id, 'OD',  'Opérations diverses',      'general',  NULL,     'active', false, 1),
    (p_tenant_id, 'AN',  'À-nouveaux',               'general',  NULL,     'active', false, 1),
    (p_tenant_id, 'CL',  'Clôture',                  'general',  NULL,     'active', false, 1),
    (p_tenant_id, 'ST',  'Stocks',                   'general',  NULL,     'active', false, 1),
    (p_tenant_id, 'OF',  'Production',               'general',  NULL,     'active', false, 1),
    (p_tenant_id, 'POS', 'Point de vente',           'cash',     '530000', 'active', false, 1)
  ON CONFLICT (tenant_id, code) DO NOTHING;
$$;
REVOKE ALL ON FUNCTION ensure_standard_journals(uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 1. Reprise des données existantes (triggers utilisateur suspendus :
--    les écritures validées sont immuables et certaines tombent en période close)
-- ------------------------------------------------------------
ALTER TABLE journal_entries DISABLE TRIGGER USER;
ALTER TABLE journal_lines DISABLE TRIGGER USER;

-- AUD-C09 : écritures sans journal → OD
UPDATE journal_entries SET journal_code = 'OD' WHERE journal_code IS NULL OR btrim(journal_code) = '';

-- Journaux standard pour chaque société, puis journal manquant pour tout code déjà utilisé
SELECT ensure_standard_journals(id) FROM tenants;
INSERT INTO journals (tenant_id, code, name, type, status, next_number)
SELECT DISTINCT je.tenant_id, je.journal_code, je.journal_code, 'general', 'active', 1
FROM journal_entries je
WHERE NOT EXISTS (SELECT 1 FROM journals j WHERE j.tenant_id = je.tenant_id AND j.code = je.journal_code);

-- AUD-C01 : montants au centime. Les vues dépendantes sont recréées à l'identique
-- (définition, options et droits), car ALTER TYPE ne traverse pas une vue.
CREATE TEMP TABLE _v187 ON COMMIT DROP AS
SELECT DISTINCT c.oid, c.relname, pg_get_viewdef(c.oid) AS def, c.reloptions, c.relacl
FROM pg_depend d
JOIN pg_rewrite r ON r.oid = d.objid
JOIN pg_class c ON c.oid = r.ev_class
WHERE d.refobjid IN ('journal_lines'::regclass, 'journal_entries'::regclass)
  AND c.relkind = 'v' AND c.oid NOT IN ('journal_lines'::regclass, 'journal_entries'::regclass);

DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT relname FROM _v187 LOOP
    EXECUTE format('DROP VIEW public.%I', v.relname);
  END LOOP;
END $$;

ALTER TABLE journal_lines
  ALTER COLUMN debit  TYPE numeric(18,2) USING round(COALESCE(debit, 0), 2),
  ALTER COLUMN credit TYPE numeric(18,2) USING round(COALESCE(credit, 0), 2);
ALTER TABLE journal_lines ALTER COLUMN debit SET NOT NULL, ALTER COLUMN credit SET NOT NULL;
ALTER TABLE journal_entries
  ALTER COLUMN total_debit  TYPE numeric(18,2) USING round(COALESCE(total_debit, 0), 2),
  ALTER COLUMN total_credit TYPE numeric(18,2) USING round(COALESCE(total_credit, 0), 2);

DO $$
DECLARE v record; a record;
BEGIN
  FOR v IN SELECT * FROM _v187 LOOP
    EXECUTE format('CREATE VIEW public.%I %s AS %s', v.relname,
      CASE WHEN v.reloptions IS NULL THEN '' ELSE 'WITH (' || array_to_string(v.reloptions, ', ') || ')' END,
      v.def);
    FOR a IN
      SELECT x.grantee, string_agg(x.privilege_type, ', ') AS privs
      FROM aclexplode(v.relacl) x
      WHERE x.grantee <> 0 AND x.grantee <> (SELECT relowner FROM pg_class WHERE relname = v.relname AND relnamespace = 'public'::regnamespace)
      GROUP BY x.grantee
    LOOP
      EXECUTE format('GRANT %s ON public.%I TO %I', a.privs, v.relname, a.grantee::regrole);
    END LOOP;
  END LOOP;
END $$;

-- AUD-C08 / AUD-C11 : exercice, période et numéro définitif portés par l'écriture
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS fiscal_year_id uuid REFERENCES fiscal_years(id) ON DELETE RESTRICT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS posting_seq integer;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS posting_number text;
COMMENT ON COLUMN journal_entries.number IS
  'Numéro de saisie (provisoire en brouillard, libre pour les écritures générées). Le numéro légal est posting_number.';
COMMENT ON COLUMN journal_entries.posting_number IS
  'AUD-C11 — numéro définitif attribué à la validation : continu et chronologique par journal et par exercice (EcritureNum du FEC).';

UPDATE journal_entries je SET fiscal_year_id = fy.id
FROM fiscal_years fy
WHERE fy.tenant_id = je.tenant_id AND je.date BETWEEN fy.start_date AND fy.end_date
  AND je.fiscal_year_id IS DISTINCT FROM fy.id;

UPDATE journal_entries je SET fiscal_period_id = fp.id
FROM fiscal_periods fp
WHERE fp.tenant_id = je.tenant_id AND fp.fiscal_year_id = je.fiscal_year_id
  AND je.date BETWEEN fp.start_date AND fp.end_date
  AND je.fiscal_period_id IS DISTINCT FROM fp.id;

-- Numéros définitifs des écritures déjà validées : ordre chronologique puis de saisie
WITH ordre AS (
  SELECT id, journal_code, fiscal_year_id,
         row_number() OVER (PARTITION BY tenant_id, journal_code, fiscal_year_id
                            ORDER BY date, created_at, number, id) AS seq
  FROM journal_entries
  WHERE status = 'posted' AND fiscal_year_id IS NOT NULL
)
UPDATE journal_entries je
SET posting_seq = o.seq,
    posting_number = je.journal_code || '-' || fy.code || '-' || lpad(o.seq::text, 6, '0')
FROM ordre o JOIN fiscal_years fy ON fy.id = o.fiscal_year_id
WHERE je.id = o.id;

-- AUD-C03 : les lignes 0/0 des brouillards n'ont aucune valeur comptable
DELETE FROM journal_lines jl USING journal_entries je
WHERE je.id = jl.journal_id AND je.status = 'draft' AND jl.debit = 0 AND jl.credit = 0;

ALTER TABLE journal_entries ENABLE TRIGGER USER;
ALTER TABLE journal_lines ENABLE TRIGGER USER;

-- ------------------------------------------------------------
-- 2. Contraintes
-- ------------------------------------------------------------
-- AUD-C09
ALTER TABLE journal_entries ALTER COLUMN journal_code SET NOT NULL;
ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_journal_fkey
  FOREIGN KEY (tenant_id, journal_code) REFERENCES journals (tenant_id, code);

-- AUD-C11
CREATE UNIQUE INDEX IF NOT EXISTS uniq_journal_entries_posting_seq
  ON journal_entries (tenant_id, journal_code, fiscal_year_id, posting_seq)
  WHERE posting_seq IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_journal_entries_fiscal_year ON journal_entries (fiscal_year_id);

CREATE TABLE IF NOT EXISTS journal_posting_sequences (
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  journal_code   text NOT NULL,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  last_seq       integer NOT NULL DEFAULT 0,
  PRIMARY KEY (tenant_id, journal_code, fiscal_year_id)
);
ALTER TABLE journal_posting_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_posting_sequences FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_select_journal_posting_sequences ON journal_posting_sequences
  FOR SELECT USING (tenant_id = current_tenant_id());
GRANT SELECT ON journal_posting_sequences TO authenticated;

INSERT INTO journal_posting_sequences (tenant_id, journal_code, fiscal_year_id, last_seq)
SELECT tenant_id, journal_code, fiscal_year_id, max(posting_seq)
FROM journal_entries WHERE posting_seq IS NOT NULL
GROUP BY 1, 2, 3
ON CONFLICT (tenant_id, journal_code, fiscal_year_id) DO UPDATE SET last_seq = EXCLUDED.last_seq;

-- AUD-C03 : une ligne est au débit OU au crédit. Une ligne 0/0 n'est pas
-- enregistrée (tg_journal_line_account) et ne peut pas être validée.
ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_one_side
  CHECK (debit = 0 OR credit = 0) NOT VALID;
DO $$
BEGIN
  ALTER TABLE journal_lines VALIDATE CONSTRAINT journal_lines_one_side;
EXCEPTION WHEN check_violation THEN
  RAISE WARNING 'journal_lines_one_side : des lignes validées historiques portent débit et crédit — contrainte appliquée aux seules nouvelles lignes';
END $$;

-- AUD-C04 : recherche des sous-comptes
CREATE INDEX IF NOT EXISTS idx_chart_accounts_parent ON chart_accounts (parent_id) WHERE parent_id IS NOT NULL;

-- Exercices sans chevauchement : une date appartient à un seul exercice (AUD-C06, C11)
CREATE OR REPLACE FUNCTION check_fiscal_year_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_code text;
BEGIN
  SELECT code INTO v_code FROM fiscal_years
  WHERE tenant_id = NEW.tenant_id AND id <> NEW.id
    AND daterange(start_date, end_date, '[]') && daterange(NEW.start_date, NEW.end_date, '[]')
  LIMIT 1;
  IF v_code IS NOT NULL THEN
    RAISE EXCEPTION 'L''exercice % chevauche l''exercice % existant', NEW.code, v_code
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_fiscal_year_overlap ON fiscal_years;
CREATE TRIGGER tg_fiscal_year_overlap
  BEFORE INSERT OR UPDATE OF start_date, end_date, tenant_id ON fiscal_years
  FOR EACH ROW EXECUTE FUNCTION check_fiscal_year_overlap();

-- ------------------------------------------------------------
-- 3. Garde de l'en-tête d'écriture (AUD-C02, C05, C06, C07, C08, C11)
--    Remplace check_fiscal_period_open, qui lisait current_tenant_id().
--    Nommé tg_* : s'exécute après set_tenant_id_journal_entries et après les
--    contrôles d'équilibre et de permission — le numéro définitif n'est donc
--    consommé que par une validation acceptée.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION journal_entry_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fy fiscal_years%ROWTYPE;
  v_period fiscal_periods%ROWTYPE;
  v_closing boolean;
  v_seq integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- AUD-C02 : une écriture naît en brouillard ; la validation est une
    -- transition contrôlée (équilibre, période, permission, numéro définitif)
    IF NEW.status IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION 'Une écriture est créée en brouillard puis validée après ses lignes (statut demandé : %)', NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.total_debit := 0;
    NEW.total_credit := 0;
    NEW.posting_seq := NULL;
    NEW.posting_number := NULL;
  ELSIF OLD.status = 'posted' THEN
    -- prevent_posted_entry_modification a déjà refusé toute modification
    RETURN NEW;
  END IF;

  IF NEW.journal_code IS NULL OR NOT EXISTS (
       SELECT 1 FROM journals WHERE tenant_id = NEW.tenant_id AND code = NEW.journal_code) THEN
    RAISE EXCEPTION 'Journal % inexistant pour cette société', COALESCE(NEW.journal_code, '(vide)')
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- AUD-C06 : la date appartient à un exercice de la société de l'écriture
  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = NEW.tenant_id AND NEW.date BETWEEN start_date AND end_date
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aucun exercice ne couvre le % : créez l''exercice avant de saisir', to_char(NEW.date, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_period FROM fiscal_periods
  WHERE tenant_id = NEW.tenant_id AND fiscal_year_id = v_fy.id
    AND NEW.date BETWEEN start_date AND end_date
  LIMIT 1;

  -- AUD-D03 : seule la clôture en cours écrit dans l'exercice qu'elle clôture,
  -- et seulement dans le journal CL.
  v_closing := NEW.journal_code = 'CL'
    AND current_setting('app.closing_in_progress', true) = v_fy.id::text;

  -- AUD-C05 / C07 : exercice et période lus pour la société de l'écriture
  IF NOT v_closing THEN
    IF v_fy.status IN ('closed', 'locked') THEN
      RAISE EXCEPTION 'Exercice % clos — écriture interdite (date=%)', v_fy.code, NEW.date
        USING ERRCODE = 'check_violation';
    END IF;
    IF v_period.status IN ('closed', 'locked') THEN
      RAISE EXCEPTION 'Période fiscale close — écriture interdite (date=%)', NEW.date
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- AUD-C08
  NEW.fiscal_year_id := v_fy.id;
  NEW.fiscal_period_id := v_period.id;

  IF TG_OP = 'UPDATE' THEN
    -- AUD-C02 : totaux calculés, jamais saisis
    SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0)
      INTO NEW.total_debit, NEW.total_credit
    FROM journal_lines WHERE journal_id = NEW.id;

    -- AUD-C11 : numéro définitif à la validation, sans trou (le compteur est
    -- annulé avec la transaction si la validation échoue plus loin)
    IF NEW.status = 'posted' THEN
      INSERT INTO journal_posting_sequences AS s (tenant_id, journal_code, fiscal_year_id, last_seq)
      VALUES (NEW.tenant_id, NEW.journal_code, v_fy.id, 1)
      ON CONFLICT (tenant_id, journal_code, fiscal_year_id) DO UPDATE SET last_seq = s.last_seq + 1
      RETURNING last_seq INTO v_seq;
      NEW.posting_seq := v_seq;
      NEW.posting_number := NEW.journal_code || '-' || v_fy.code || '-' || lpad(v_seq::text, 6, '0');
      NEW.validated_at := COALESCE(NEW.validated_at, now());
    END IF;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS check_fiscal_period_open ON journal_entries;
DROP FUNCTION IF EXISTS check_fiscal_period_open();
DROP TRIGGER IF EXISTS tg_journal_entry_guard ON journal_entries;
CREATE TRIGGER tg_journal_entry_guard
  BEFORE INSERT OR UPDATE ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION journal_entry_guard();

-- ------------------------------------------------------------
-- 4. Équilibre strict (AUD-C01) et lignes 0/0 retirées à la validation (AUD-C03)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_journal_entry_balance_on_post()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_debit numeric;
  v_credit numeric;
  v_lines int;
  v_empty int;
BEGIN
  SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0), count(*),
         count(*) FILTER (WHERE debit = 0 AND credit = 0)
  INTO v_debit, v_credit, v_lines, v_empty
  FROM journal_lines WHERE journal_id = NEW.id;

  IF v_lines = 0 THEN
    RAISE EXCEPTION 'Écriture % sans ligne : validation impossible', NEW.id;
  END IF;
  IF v_empty > 0 THEN
    RAISE EXCEPTION 'Écriture % : % ligne(s) sans montant, à compléter ou supprimer avant validation', NEW.id, v_empty
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_debit <> v_credit THEN
    RAISE EXCEPTION 'Écriture % non équilibrée : débit % ≠ crédit %', NEW.id, v_debit, v_credit;
  END IF;

  NEW.total_debit := v_debit;
  NEW.total_credit := v_credit;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION assert_journal_entries_balanced(p_entry_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT je.id, je.status,
           COALESCE(SUM(jl.debit), 0) AS total_debit,
           COALESCE(SUM(jl.credit), 0) AS total_credit
    FROM journal_entries je
    LEFT JOIN journal_lines jl ON jl.journal_id = je.id
    WHERE je.id = ANY (p_entry_ids)
    GROUP BY je.id, je.status
  LOOP
    IF r.status IS DISTINCT FROM 'draft' AND r.total_debit <> r.total_credit THEN
      RAISE EXCEPTION 'Écriture % non équilibrée : débit % ≠ crédit %', r.id, r.total_debit, r.total_credit;
    END IF;
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- 5. Compte imputable (AUD-C04) : présent au plan de la société, non déprécié,
--    sans sous-compte
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION journal_line_account_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_code text;
  v_acc record;
BEGIN
  -- AUD-C03 : une ligne sans montant (ligne de grille vide, TVA d'une opération
  -- exonérée) n'a aucune valeur comptable : elle n'est pas enregistrée.
  IF TG_OP = 'INSERT' AND NEW.debit = 0 AND NEW.credit = 0 THEN
    RETURN NULL;
  END IF;
  FOREACH v_code IN ARRAY ARRAY[NEW.account_code, NULLIF(NEW.account_general, NEW.account_code)] LOOP
    CONTINUE WHEN v_code IS NULL;
    SELECT id, deprecated INTO v_acc FROM chart_accounts
    WHERE tenant_id = NEW.tenant_id AND code = v_code;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Compte % absent du plan comptable de la société', v_code
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_acc.deprecated THEN
      RAISE EXCEPTION 'Compte % fermé (déprécié) : imputation interdite', v_code
        USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM chart_accounts WHERE parent_id = v_acc.id) THEN
      RAISE EXCEPTION 'Compte % : compte de regroupement, imputer un de ses sous-comptes', v_code
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_journal_line_account ON journal_lines;
CREATE TRIGGER tg_journal_line_account
  BEFORE INSERT OR UPDATE OF account_code, account_general, tenant_id ON journal_lines
  FOR EACH ROW EXECUTE FUNCTION journal_line_account_guard();

-- Totaux d'un brouillard tenus à jour quand ses lignes changent (AUD-C02)
CREATE OR REPLACE FUNCTION refresh_draft_entry_totals(p_entry_ids uuid[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE journal_entries je
  SET total_debit = s.d, total_credit = s.c
  FROM (
    SELECT e.id, COALESCE(sum(jl.debit), 0) AS d, COALESCE(sum(jl.credit), 0) AS c
    FROM unnest(p_entry_ids) AS e(id)
    LEFT JOIN journal_lines jl ON jl.journal_id = e.id
    GROUP BY e.id
  ) s
  WHERE je.id = s.id AND je.status = 'draft'
    AND (je.total_debit IS DISTINCT FROM s.d OR je.total_credit IS DISTINCT FROM s.c);
$$;
REVOKE ALL ON FUNCTION refresh_draft_entry_totals(uuid[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION check_journal_entry_balance_ins()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_ids uuid[] := ARRAY(SELECT DISTINCT journal_id FROM new_table);
BEGIN
  PERFORM assert_journal_entries_balanced(v_ids);
  PERFORM refresh_draft_entry_totals(v_ids);
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION check_journal_entry_balance_upd()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_ids uuid[] := ARRAY(SELECT journal_id FROM new_table UNION SELECT journal_id FROM old_table);
BEGIN
  PERFORM assert_journal_entries_balanced(v_ids);
  PERFORM refresh_draft_entry_totals(v_ids);
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION check_journal_entry_balance_del()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_ids uuid[] := ARRAY(SELECT DISTINCT journal_id FROM old_table);
BEGIN
  PERFORM assert_journal_entries_balanced(v_ids);
  PERFORM refresh_draft_entry_totals(v_ids);
  RETURN NULL;
END $$;

-- ------------------------------------------------------------
-- 6. Écritures automatiques : comptes du plan semé (AUD-C04) et journaux standard
--    Seuls les codes de compte changent ; le reste des fonctions est inchangé.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_journal_on_invoice_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_collectif text := '411000';
  v_tiers text;
  v_third_party uuid;
  v_compte_tva text;
  v_ordre int := 2;
  v_vat RECORD;
  v_ligne RECORD;
  v_defaut_vente text := '707000';
BEGIN
  IF NEW.validation_status IS DISTINCT FROM OLD.validation_status
     AND NEW.validation_status = 'validated' THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'VT' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01 : récupérer le compte collectif et le compte auxiliaire du client
    SELECT COALESCE(c.account_collectif, '411000'), c.account_tiers, c.id
    INTO v_collectif, v_tiers, v_third_party
    FROM customers c
    WHERE c.id = NEW.customer_id AND c.tenant_id = NEW.tenant_id;

    v_number := 'JE-INV-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'VT', 'draft', 'Facture vente ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    -- Ligne client (débit)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      account_tiers, third_party_id, echeance_date,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, v_collectif, v_collectif,
      v_tiers, v_third_party, NEW.due_date,
      NEW.total, 0, 'Client ' || NEW.number, 0
    );

    -- ACC-03 : boucle sur les lignes de facture regroupées par compte de produit
    -- LOT2-01 : il.subtotal → il.total (subtotal n'existe pas sur invoice_lines)
    FOR v_ligne IN
      SELECT
        COALESCE(p.sale_account_code, pc.sale_account_code, v_defaut_vente) AS compte,
        SUM(il.total) AS montant
      FROM invoice_lines il
      LEFT JOIN products p ON p.id = il.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      GROUP BY 1
    LOOP
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_ligne.compte, v_ligne.compte,
        0, v_ligne.montant, 'Ventes ' || v_ligne.compte || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback si pas de lignes détaillées
    IF v_ordre = 2 AND NEW.subtotal > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_defaut_vente, v_defaut_vente,
        0, NEW.subtotal, 'Ventes ' || NEW.number, 1
      );
      v_ordre := 3;
    END IF;

    -- ACC-02 : boucle sur les taux de TVA
    FOR v_vat IN
      SELECT il.vat_code,
             SUM(il.total) AS base_ht,
             SUM(il.vat_amount) AS montant_tva
      FROM invoice_lines il
      WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      GROUP BY il.vat_code
    LOOP
      SELECT account_code INTO v_compte_tva
      FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = v_vat.vat_code
        AND direction = 'collected'
      ORDER BY tenant_id DESC
      LIMIT 1;

      v_compte_tva := COALESCE(v_compte_tva, '445710');

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
        v_vat.vat_code, v_vat.montant_tva,
        0, v_vat.montant_tva,
        'TVA collectée ' || v_vat.vat_code || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback TVA
    IF v_ordre = 2 AND NEW.vat_total > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, '445710', '445710',
        'FR20', NEW.vat_total,
        0, NEW.vat_total, 'TVA collectée ' || NEW.number, 2
      );
    END IF;

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.post_pos_session_on_close()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_ht numeric;
  v_vat numeric;
  v_ttc numeric;
  v_vat_code text;
  v_vat_amount numeric;
  v_compte_tva text;
  v_ordre int := 2;
  v_ligne RECORD;
BEGIN
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN
    RETURN NEW;
  END IF;

  -- LOT2-11 : pos_tickets.subtotal existe, pas pos_ticket_lines.subtotal
  SELECT COALESCE(sum(subtotal), 0), COALESCE(sum(vat_total), 0), COALESCE(sum(total), 0)
  INTO v_ht, v_vat, v_ttc
  FROM pos_tickets
  WHERE session_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'completed';

  IF v_ttc = 0 THEN
    RETURN NEW;
  END IF;

  -- LOT2-12 : utiliser NEW.closed_at au lieu de entry_date
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number
  ) VALUES (
    NEW.tenant_id, 'JE-POS-' || NEW.id, COALESCE(NEW.closed_at, NOW())::date, 'CA',
    'draft', 'Clôture caisse ' || NEW.id, 'POS-' || NEW.id
  )
  RETURNING id INTO v_entry_id;

  -- Ligne caisse (débit)
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    debit, credit, description, line_order
  ) VALUES (
    NEW.tenant_id, v_entry_id, '531000', '531000',
    v_ttc, 0, 'Caisse', 0
  );

  -- LOT2-11 : tl.subtotal → tl.line_total (pos_ticket_lines a line_total, pas subtotal)
  FOR v_ligne IN
    SELECT
      COALESCE(p.sale_account_code, pc.sale_account_code, '707000') AS compte,
      SUM(tl.line_total) AS montant
    FROM pos_ticket_lines tl
    JOIN pos_tickets tk ON tk.id = tl.ticket_id AND tk.tenant_id = NEW.tenant_id
    LEFT JOIN products p ON p.id = tl.product_id AND p.tenant_id = NEW.tenant_id
    LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
    WHERE tk.session_id = NEW.id AND tk.tenant_id = NEW.tenant_id AND tk.status = 'completed'
    GROUP BY 1
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, v_ligne.compte, v_ligne.compte,
      0, v_ligne.montant, 'Ventes comptoir ' || v_ligne.compte, v_ordre
    );
    v_ordre := v_ordre + 1;
  END LOOP;

  -- Fallback si pas de lignes détaillées
  IF v_ordre = 2 AND v_ht > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '707000', '707000',
      0, v_ht, 'Ventes comptoir', 1
    );
    v_ordre := 3;
  END IF;

  -- TVA : pos_ticket_lines n'a pas vat_code/vat_total, on utilise vat_rate
  FOR v_vat_code, v_vat_amount IN
    SELECT 'FR' || REPLACE(tl.vat_rate::text, '.', ''), SUM(tl.line_total * tl.vat_rate / 100)
    FROM pos_ticket_lines tl
    JOIN pos_tickets tk ON tk.id = tl.ticket_id AND tk.tenant_id = NEW.tenant_id
    WHERE tk.session_id = NEW.id AND tk.tenant_id = NEW.tenant_id AND tk.status = 'completed'
      AND tl.vat_rate > 0
    GROUP BY 1
  LOOP
    SELECT account_code INTO v_compte_tva
    FROM vat_account_mapping
    WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
      AND vat_code = v_vat_code AND direction = 'collected'
    ORDER BY tenant_id DESC LIMIT 1;

    v_compte_tva := COALESCE(v_compte_tva, '445710');

    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      vat_code, vat_amount,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
      v_vat_code, v_vat_amount,
      0, v_vat_amount, 'TVA collectée ' || v_vat_code, v_ordre
    );
    v_ordre := v_ordre + 1;
  END LOOP;

  -- Fallback TVA
  IF v_ordre <= 3 AND v_vat > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '445710', '445710',
      0, v_vat, 'TVA collectée', v_ordre
    );
  END IF;

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;

  -- Sorties de stock
  INSERT INTO stock_movements (
    tenant_id, product_id, movement_type, type, quantity,
    unit_cost, reference, reference_type, reference_id,
    date, movement_date, warehouse_id
  )
  SELECT
    NEW.tenant_id, l.product_id, 'out', 'out', sum(l.quantity),
    max(COALESCE(sq.unit_cost, p.cost_price, 0)),
    'POS-' || NEW.id, 'pos_session', NEW.id,
    COALESCE(NEW.closed_at, NOW())::date, COALESCE(NEW.closed_at, NOW())::date, t.warehouse_id
  FROM pos_ticket_lines l
  JOIN pos_tickets tk ON tk.id = l.ticket_id AND tk.tenant_id = NEW.tenant_id
  JOIN pos_terminals t ON t.id = tk.terminal_id AND t.tenant_id = NEW.tenant_id
  JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
  LEFT JOIN stock_quantities sq ON sq.product_id = l.product_id
    AND sq.warehouse_id = t.warehouse_id AND sq.tenant_id = NEW.tenant_id
  WHERE tk.session_id = NEW.id AND tk.tenant_id = NEW.tenant_id AND l.product_id IS NOT NULL
  GROUP BY l.product_id, t.warehouse_id;

  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.post_pos_session_on_close_multi()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := NEW.tenant_id;
  v_je_id uuid;
  v_line_num int := 1;
  v_total_sales numeric := 0;
  v_total_vat numeric := 0;
  v_ticket record;
  v_payment record;
  v_method_amount numeric;
  v_product record;
  v_je_number text;
  v_session_ref text;
  v_close_date date := COALESCE(NEW.closed_at, NOW())::date;
BEGIN
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN
    RETURN NEW;
  END IF;

  -- LOT2-13 : utiliser NEW.id::text comme fallback
  v_session_ref := COALESCE(NEW.session_number, NEW.id::text);

  -- Calculer le total des ventes et TVA
  SELECT COALESCE(SUM(subtotal), 0), COALESCE(SUM(vat_total), 0)
  INTO v_total_sales, v_total_vat
  FROM pos_tickets
  WHERE session_id = NEW.id AND tenant_id = v_tid AND status = 'completed';

  IF v_total_sales = 0 THEN
    RETURN NEW;
  END IF;

  v_je_number := 'POS-' || NEW.id;

  -- LOT2-12 : utiliser v_close_date au lieu de CURRENT_DATE
  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'POS', v_je_number, v_close_date,
    'Clôture caisse session ' || v_session_ref, 'draft', now()
  )
  RETURNING id INTO v_je_id;

  -- Une ligne de débit par moyen de paiement
  FOR v_payment IN
    SELECT ppm.account_code, SUM(pp.amount) AS total
    FROM pos_payments pp
    JOIN pos_payment_methods ppm ON ppm.id = pp.payment_method_id AND ppm.tenant_id = v_tid
    JOIN pos_tickets pt ON pt.id = pp.ticket_id AND pt.tenant_id = v_tid
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND pp.tenant_id = v_tid
    GROUP BY ppm.account_code
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, line_order, account_code,
      debit, credit, created_at
    ) VALUES (
      v_tid, v_je_id, v_line_num, v_payment.account_code,
      v_payment.total, 0, now()
    );
    v_line_num := v_line_num + 1;
  END LOOP;

  -- Crédit des ventes (707000)
  INSERT INTO journal_lines (
    tenant_id, journal_id, line_order, account_code,
    debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_line_num, '707000', 0, v_total_sales, now()
  );
  v_line_num := v_line_num + 1;

  -- Crédit de la TVA (4457100)
  IF v_total_vat > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, line_order, account_code,
      debit, credit, created_at
    ) VALUES (
      v_tid, v_je_id, v_line_num, '445710', 0, v_total_vat, now()
    );
    v_line_num := v_line_num + 1;
  END IF;

  -- Poster l'écriture
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je_id;

  -- Créer les mouvements de stock sortants
  FOR v_product IN
    SELECT ptl.product_id, SUM(ptl.quantity) AS total_qty, pt2.warehouse_id
    FROM pos_ticket_lines ptl
    JOIN pos_tickets pt ON pt.id = ptl.ticket_id AND pt.tenant_id = ptl.tenant_id
    JOIN pos_sessions ps ON ps.id = pt.session_id AND ps.tenant_id = pt.tenant_id
    JOIN pos_terminals pt2 ON pt2.id = ps.terminal_id AND pt2.tenant_id = ps.tenant_id
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND ptl.tenant_id = v_tid
    GROUP BY ptl.product_id, pt2.warehouse_id
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type,
      quantity, unit_cost, reference, reference_type, reference_id,
      date, movement_date, created_at
    )
    SELECT
      v_tid, v_product.product_id, v_product.warehouse_id, 'out', 'out',
      v_product.total_qty,
      COALESCE(sq.unit_cost, 0),
      'POS-' || v_session_ref, 'pos_session', NEW.id,
      v_close_date, v_close_date, now()
    FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid AND sq.product_id = v_product.product_id
    LIMIT 1;

    -- Décrémenter le stock
    UPDATE stock_quantities
    SET quantity = quantity - v_product.total_qty, updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_product.product_id;
  END LOOP;

  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.create_journal_on_purchase_invoice_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_collectif text := '401000';
  v_tiers text;
  v_third_party uuid;
  v_compte_tva text;
  v_ordre int := 0;
  v_vat RECORD;
  v_ligne RECORD;
  v_defaut_achat text := '607000';
BEGIN
  IF NEW.approval_status IS DISTINCT FROM OLD.approval_status
     AND NEW.approval_status = 'approved' THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'AC' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01
    SELECT COALESCE(s.account_collectif, '401000'), s.account_tiers, s.id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers s
    WHERE s.id = NEW.supplier_id AND s.tenant_id = NEW.tenant_id;

    v_number := 'JE-PI-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'AC', 'draft', 'Facture achat ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    -- ACC-03 : boucle sur les lignes d'achat regroupées par compte de charge
    -- LOT2-02 : pil.subtotal → pil.total (subtotal n'existe pas sur purchase_invoice_lines)
    FOR v_ligne IN
      SELECT
        COALESCE(p.purchase_account_code, pc.purchase_account_code, v_defaut_achat) AS compte,
        SUM(pil.total) AS montant
      FROM purchase_invoice_lines pil
      LEFT JOIN products p ON p.id = pil.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE pil.purchase_invoice_id = NEW.id AND pil.tenant_id = NEW.tenant_id
      GROUP BY 1
    LOOP
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_ligne.compte, v_ligne.compte,
        v_ligne.montant, 0, 'Achats ' || v_ligne.compte || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback si pas de lignes détaillées
    IF v_ordre = 0 AND NEW.subtotal > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_defaut_achat, v_defaut_achat,
        NEW.subtotal, 0, 'Achats ' || NEW.number, 0
      );
      v_ordre := 1;
    END IF;

    -- ACC-02 : boucle sur les taux de TVA déductibles
    FOR v_vat IN
      SELECT pil.vat_code,
             SUM(pil.total) AS base_ht,
             SUM(pil.vat_amount) AS montant_tva
      FROM purchase_invoice_lines pil
      WHERE pil.purchase_invoice_id = NEW.id AND pil.tenant_id = NEW.tenant_id
      GROUP BY pil.vat_code
    LOOP
      SELECT account_code INTO v_compte_tva
      FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = v_vat.vat_code
        AND direction = 'deductible'
      ORDER BY tenant_id DESC
      LIMIT 1;

      v_compte_tva := COALESCE(v_compte_tva, '445660');

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
        v_vat.vat_code, v_vat.montant_tva,
        v_vat.montant_tva, 0, 'TVA déductible ' || v_vat.vat_code || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback TVA
    IF v_ordre <= 1 AND NEW.vat_total > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, '445660', '445660',
        'FR20', NEW.vat_total,
        NEW.vat_total, 0, 'TVA déductible ' || NEW.number, v_ordre
      );
      v_ordre := v_ordre + 1;
    END IF;

    -- Ligne fournisseur (crédit)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      account_tiers, third_party_id, echeance_date,
      debit, credit, description, line_order
    ) VALUES (
      New.tenant_id, v_entry_id, v_collectif, v_collectif,
      v_tiers, v_third_party, NEW.due_date,
      0, NEW.total, 'Fournisseur ' || NEW.number, 99
    );

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE purchase_invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.create_journal_on_payroll_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_entry_number text;
  v_gross_total numeric;
  v_tax_total numeric;
  v_net_total numeric;
  v_employer_contributions numeric;
BEGIN
  -- Ne réagir qu'au passage à 'paid' (statut final de validation paie)
  IF NEW.status != 'paid' THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'paid' THEN
    RETURN NEW;
  END IF;

  v_gross_total := COALESCE(NEW.gross_total, 0);
  v_tax_total := COALESCE(NEW.tax_total, 0);
  v_net_total := COALESCE(NEW.net_total, 0);

  -- Récupérer les cotisations employeur depuis les fiches de paie
  SELECT COALESCE(SUM(employer_contributions), 0) INTO v_employer_contributions
  FROM pay_slips
  WHERE pay_run_id = NEW.id AND tenant_id = NEW.tenant_id;

  -- Générer un numéro d'écriture
  v_entry_number := 'OD-' || to_char(NOW(), 'YYYYMMDD') || '-' || NEW.number;

  -- Créer l'écriture comptable
  INSERT INTO journal_entries (
    tenant_id, number, date, description, reference,
    status, journal_code, total_debit, total_credit
  ) VALUES (
    NEW.tenant_id, v_entry_number, NEW.pay_date,
    'Écriture de paie - ' || NEW.number,
    'PAYROLL-' || NEW.number,
    'draft', 'OD',
    v_gross_total + v_employer_contributions,
    v_gross_total + v_employer_contributions
  ) RETURNING id INTO v_entry_id;

  -- Ligne 1: Débit - Charges de personnel (compte 641)
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    debit, credit, description, line_order
  ) VALUES (
    NEW.tenant_id, v_entry_id, '641000', '641000',
    v_gross_total, 0, 'Salaires bruts', 1
  );

  -- Ligne 2: Débit - Cotisations patronales (compte 645)
  IF v_employer_contributions > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '645000', '645000',
      v_employer_contributions, 0, 'Cotisations patronales', 2
    );
  END IF;

  -- Ligne 3: Crédit - Cotisations sociales URSSAF (compte 431)
  IF v_tax_total > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '431000', '431000',
      0, v_tax_total, 'Cotisations sociales', 3
    );
  END IF;

  -- Ligne 4: Crédit - Net à payer (compte 421)
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    debit, credit, description, line_order
  ) VALUES (
    NEW.tenant_id, v_entry_id, '421000', '421000',
    0, v_net_total, 'Net à payer', 4
  );

  -- Ligne 5: Crédit - Cotisations patronales (compte 431) si > 0
  IF v_employer_contributions > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '431000', '431000',
      0, v_employer_contributions, 'Cotisations patronales à payer', 5
    );
  END IF;

  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.create_stock_on_manufacturing_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_cost jsonb;
  v_unit_cost numeric;
  v_cost_material numeric;
  v_cost_labor numeric;
  v_cost_overhead numeric;
  v_cost_total numeric;
  v_ordre int := 0;
  v_component RECORD;
  v_component_cost numeric;
BEGIN
  -- Ne traiter que la transition vers 'completed'
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'completed' THEN

    -- Calculer le coût de production
    v_cost := calculate_manufacturing_cost(NEW.id, NEW.tenant_id);
    IF (v_cost->>'success')::boolean THEN
      v_cost_material := (v_cost->>'cost_material')::numeric;
      v_cost_labor := (v_cost->>'cost_labor')::numeric;
      v_cost_overhead := (v_cost->>'cost_overhead')::numeric;
      v_cost_total := (v_cost->>'cost_total')::numeric;
      v_unit_cost := (v_cost->>'unit_cost')::numeric;
    ELSE
      v_unit_cost := 0;
      v_cost_total := 0;
    END IF;

    -- Mouvement d'entrée du produit fini AVEC unit_cost
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, movement_date, reference_type
    ) VALUES (
      NEW.tenant_id, NEW.product_id, NEW.warehouse_id, 'in',
      NEW.quantity, v_unit_cost, NEW.number, CURRENT_DATE, 'production'
    );

    -- Sortie des composants du stock avec leur CUMP courant
    FOR v_component IN
      SELECT bl.product_id, bl.quantity * NEW.quantity AS qty,
             COALESCE(NULLIF(sq.unit_cost, 0), NULLIF(p.cost_price, 0), bl.unit_cost, 0) AS comp_cost
      FROM bom_lines bl
      JOIN products p ON p.id = bl.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN stock_quantities sq
        ON sq.product_id = bl.product_id
       AND sq.warehouse_id = NEW.warehouse_id
       AND sq.tenant_id = NEW.tenant_id
      WHERE bl.bom_id = NEW.bom_id AND bl.tenant_id = NEW.tenant_id
    LOOP
      v_component_cost := v_component.qty * v_component.comp_cost;

      INSERT INTO stock_movements (
        tenant_id, product_id, warehouse_id, movement_type,
        quantity, unit_cost, reference, movement_date, reference_type
      ) VALUES (
        NEW.tenant_id, v_component.product_id, NEW.warehouse_id, 'out',
        v_component.qty, v_component.comp_cost, NEW.number, CURRENT_DATE, 'production'
      );
    END LOOP;

    -- Écriture comptable de production
    v_number := 'JE-OF-' || NEW.number;
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND reference = v_number LIMIT 1;

    IF v_existing IS NULL AND COALESCE(v_cost_total, 0) > 0 THEN
      INSERT INTO journal_entries (
        tenant_id, number, date, journal_code, status,
        description, reference
      ) VALUES (
        NEW.tenant_id, v_number, CURRENT_DATE, 'OF', 'draft',
        'Production OF ' || NEW.number, v_number
      )
      RETURNING id INTO v_entry_id;

      -- Sortie des matières (débit 601, crédit 31x)
      IF v_cost_material > 0 THEN
        INSERT INTO journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id, '601000', '601000',
          v_cost_material, 0, 'Consommation matières — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;

        INSERT INTO journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id, '310000', '310000',
          0, v_cost_material, 'Sortie stock matières — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;
      END IF;

      -- Main-d'œuvre et frais généraux : déjà constatés en charges (paie, factures) ;
      -- ils sont absorbés dans la valeur du produit fini via 355 / 713, sans nouvelle charge.

      -- Entrée du produit fini (débit 355, crédit 71355 production stockée)
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id, '355000', '355000',
        v_cost_total, 0, 'Entrée produit fini — ' || NEW.number, v_ordre
      );
      v_ordre := v_ordre + 1;

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id, '713500', '713500',
        0, v_cost_total, 'Production stockée — ' || NEW.number, v_ordre
      );

      -- Bascule en 'posted' APRÈS les lignes (SOC-01)
      UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    END IF;

    -- Mettre à jour les quantités produites
    UPDATE manufacturing_orders
    SET qty_produced = NEW.quantity
    WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.generate_residual_entry(p_group_id uuid, p_residual_type text, p_amount numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_group record;
  v_je_id uuid;
  v_account_code text;
BEGIN
  SELECT * INTO v_group FROM lettrage_groups WHERE id = p_group_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Groupe de lettrage introuvable'; END IF;

  -- Compte selon le type d'écart
  v_account_code := CASE p_residual_type
    WHEN 'escompte' THEN '665000'
    WHEN 'perte_change' THEN '666000'
    WHEN 'gain_change' THEN '766000'
    WHEN 'creance_irrecouvrable' THEN '654000'
    ELSE NULL
  END;

  IF v_account_code IS NULL THEN
    RAISE EXCEPTION 'Type d''écart inconnu: %', p_residual_type;
  END IF;

  -- Créer l'écriture d'écart
  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'OD', 'ECART-' || p_group_id, CURRENT_DATE,
    'Écart de règlement - ' || p_residual_type, 'posted', now()
  )
  RETURNING id INTO v_je_id;

  -- Ligne d'écart
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_name, debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_account_code,
    CASE p_residual_type
      WHEN 'escompte' THEN 'Escompte accordé'
      WHEN 'perte_change' THEN 'Perte de change'
      WHEN 'gain_change' THEN 'Gain de change'
      WHEN 'creance_irrecouvrable' THEN 'Créance irrécouvrable'
    END,
    CASE WHEN p_residual_type IN ('escompte', 'perte_change', 'creance_irrecouvrable') THEN p_amount ELSE 0 END,
    CASE WHEN p_residual_type = 'gain_change' THEN p_amount ELSE 0 END,
    now()
  );

  -- Mettre à jour le groupe
  UPDATE lettrage_groups SET residual_amount = p_amount, residual_type = p_residual_type, status = 'closed'
  WHERE id = p_group_id;

  RETURN v_je_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.bootstrap_tenant(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_tenant record;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_fy_id uuid;
  v_period_start date;
  v_period_end date;
  v_labels text[] := ARRAY['Janvier','Fevrier','Mars','Avril','Mai','Juin','Juillet','Aout','Septembre','Octobre','Novembre','Decembre'];
BEGIN
  PERFORM assert_can_provision_tenant(p_tenant_id);

  SELECT * INTO v_tenant FROM tenants WHERE id = p_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tenant % not found', p_tenant_id;
  END IF;

  -- 1. CHART OF ACCOUNTS
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id) THEN
    PERFORM seed_standard_chart_unchecked(p_tenant_id);
  END IF;

  -- 2. STANDARD JOURNALS (AUD-C09 : y compris CL, ST, OF, POS des écritures automatiques)
  PERFORM ensure_standard_journals(p_tenant_id);

  -- 3. CURRENCIES — devises par défaut + devise de la société (AUD-B03)
  INSERT INTO currencies (code, name, symbol, exchange_rate, tenant_id)
  VALUES
    ('EUR', 'Euro',            '€', 1.0,    p_tenant_id),
    ('USD', 'Dollar US',       '$', 1.08,   p_tenant_id),
    ('GBP', 'Livre Sterling',  '£', 0.85,   p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;

  IF v_tenant.currency IS NOT NULL THEN
    INSERT INTO currencies (code, name, symbol, exchange_rate, tenant_id)
    SELECT v_tenant.currency, COALESCE(ref.name, v_tenant.currency), COALESCE(ref.symbol, v_tenant.currency),
           COALESCE(ref.exchange_rate, 1.0), p_tenant_id
    FROM (SELECT 1) one
    LEFT JOIN currencies ref ON ref.tenant_id IS NULL AND ref.code = v_tenant.currency
    ON CONFLICT (tenant_id, code) DO NOTHING;
  END IF;

  -- 4. FISCAL YEAR + 12 MONTHLY PERIODS (current year)
  -- Un exercice existant qui couvre déjà l'année (autre code) suffit : pas de chevauchement
  IF NOT EXISTS (SELECT 1 FROM fiscal_years WHERE tenant_id = p_tenant_id
                 AND daterange(start_date, end_date, '[]') && daterange(make_date(v_year, 1, 1), make_date(v_year, 12, 31), '[]')) THEN
    INSERT INTO fiscal_years (code, start_date, end_date, status, tenant_id)
    VALUES ('FY' || v_year, make_date(v_year, 1, 1), make_date(v_year, 12, 31), 'open', p_tenant_id)
    RETURNING id INTO v_fy_id;

    FOR v_month IN 1 .. 12 LOOP
      v_period_start := make_date(v_year, v_month, 1);
      v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::date;
      INSERT INTO fiscal_periods (fiscal_year_id, period_number, period_label, start_date, end_date, status, tenant_id)
      VALUES (v_fy_id, v_month, v_labels[v_month] || ' ' || v_year, v_period_start, v_period_end, 'open', p_tenant_id);
    END LOOP;
  END IF;

  -- 5. COMPANY SETTINGS
  IF NOT EXISTS (SELECT 1 FROM company_settings WHERE tenant_id = p_tenant_id) THEN
    INSERT INTO company_settings (name, legal_name, vat_number, siret, address, city, postal_code, country, currency, fiscal_year_start, tenant_id)
    VALUES (
      v_tenant.name,
      COALESCE(v_tenant.legal_name, v_tenant.name),
      v_tenant.vat_number,
      v_tenant.siret,
      v_tenant.address,
      v_tenant.city,
      v_tenant.postal_code,
      COALESCE(v_tenant.country, 'France'),
      COALESCE(v_tenant.currency, 'EUR'),
      '01-01',
      p_tenant_id
    );
  END IF;
END;
$function$;


-- ------------------------------------------------------------
-- 7. Comptes de TVA du paramétrage présents au plan (AUD-C04, S03)
--    vat_account_mapping impute 445661…445664 et 445711…445714, que le plan
--    standard ne contenait pas : toute facture à TVA aurait été refusée.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION seed_vat_accounts(p_tenant_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO chart_accounts (tenant_id, code, name, type)
  SELECT DISTINCT ON (m.account_code) p_tenant_id, m.account_code,
         CASE m.direction WHEN 'collected' THEN 'TVA collectée ' ELSE 'TVA déductible ' END || m.vat_code,
         CASE m.direction WHEN 'collected' THEN 'liability' ELSE 'asset' END
  FROM vat_account_mapping m
  WHERE m.tenant_id IN (p_tenant_id, '00000000-0000-0000-0000-000000000000')
  ORDER BY m.account_code, (m.tenant_id = p_tenant_id) DESC, m.vat_code
  ON CONFLICT (tenant_id, code) DO NOTHING;
$$;
REVOKE ALL ON FUNCTION seed_vat_accounts(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.seed_standard_chart_unchecked(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  INSERT INTO chart_accounts (code, name, type, balance, tenant_id)
  VALUES
    -- Classe 1 - Capitaux
    ('101000', 'Capital social', 'equity', 0, p_tenant_id),
    ('101100', 'Capital non appele', 'equity', 0, p_tenant_id),
    ('104000', 'Primes liees au capital social', 'equity', 0, p_tenant_id),
    ('106000', 'Reserves', 'equity', 0, p_tenant_id),
    ('106100', 'Reserve legale', 'equity', 0, p_tenant_id),
    ('106800', 'Autres reserves', 'equity', 0, p_tenant_id),
    ('108000', 'Compte de l exploitant', 'equity', 0, p_tenant_id),
    ('109000', 'Actionnaires - capital souscrit non appele', 'equity', 0, p_tenant_id),
    ('110000', 'Report a nouveau (solde crediteur)', 'equity', 0, p_tenant_id),
    ('119000', 'Report a nouveau (solde debiteur)', 'equity', 0, p_tenant_id),
    ('120000', 'Resultat de l exercice (benefice)', 'equity', 0, p_tenant_id),
    ('129000', 'Resultat de l exercice (perte)', 'equity', 0, p_tenant_id),
    ('151000', 'Provisions pour risques', 'liability', 0, p_tenant_id),
    ('153000', 'Provisions pour pensions', 'liability', 0, p_tenant_id),
    ('158000', 'Autres provisions pour charges', 'liability', 0, p_tenant_id),
    ('163000', 'Emprunts aupres des etablissements de credit', 'liability', 0, p_tenant_id),
    ('164000', 'Emprunts aupres des autres partenaires', 'liability', 0, p_tenant_id),
    ('165000', 'Depots et cautionnements recus', 'liability', 0, p_tenant_id),
    ('168000', 'Autres emprunts et dettes assimilees', 'liability', 0, p_tenant_id),
    ('171000', 'Dettes rattachees a des participations', 'liability', 0, p_tenant_id),
    ('181000', 'Comptes de liaison etablissements', 'liability', 0, p_tenant_id),
    ('186000', 'Biens en credit-bail', 'liability', 0, p_tenant_id),
    ('187000', 'Biens en credit-bail - contrepartie', 'liability', 0, p_tenant_id),
    ('188000', 'Biens en location-vente', 'liability', 0, p_tenant_id),
    ('189000', 'Biens en location-vente - contrepartie', 'liability', 0, p_tenant_id),
    -- Classe 2 - Immobilisations
    ('201000', 'Frais d etablissement', 'asset', 0, p_tenant_id),
    ('205000', 'Concessions, brevets, licences, logiciels', 'asset', 0, p_tenant_id),
    ('206000', 'Droit au bail', 'asset', 0, p_tenant_id),
    ('207000', 'Fonds commercial', 'asset', 0, p_tenant_id),
    ('208000', 'Autres immobilisations incorporelles', 'asset', 0, p_tenant_id),
    ('210000', 'Terrains', 'asset', 0, p_tenant_id),
    ('211000', 'Agencements et ameliororations de terrains', 'asset', 0, p_tenant_id),
    ('212000', 'Constructions', 'asset', 0, p_tenant_id),
    ('213000', 'Constructions sur sol d autrui', 'asset', 0, p_tenant_id),
    ('215000', 'Installations techniques, materiels et outillage', 'asset', 0, p_tenant_id),
    ('215400', 'Materiel industriel', 'asset', 0, p_tenant_id),
    ('218000', 'Materiel informatique', 'asset', 0, p_tenant_id),
    ('218100', 'Materiel de bureau et informatique', 'asset', 0, p_tenant_id),
    ('218200', 'Mobilier', 'asset', 0, p_tenant_id),
    ('218300', 'Materiel de bureau', 'asset', 0, p_tenant_id),
    ('218400', 'Materiel et outillage', 'asset', 0, p_tenant_id),
    ('218500', 'Embages et equipements', 'asset', 0, p_tenant_id),
    ('220000', 'Immobilisations corporelles en cours', 'asset', 0, p_tenant_id),
    ('230000', 'Immobilisations en cours - incorporelles', 'asset', 0, p_tenant_id),
    ('231000', 'Immobilisations en cours - corporelles', 'asset', 0, p_tenant_id),
    ('238000', 'Avances et acomptes verses sur commandes', 'asset', 0, p_tenant_id),
    ('240000', 'Participations et creances rattachees', 'asset', 0, p_tenant_id),
    ('250000', 'Titres de participation', 'asset', 0, p_tenant_id),
    ('260000', 'Titres immobilises', 'asset', 0, p_tenant_id),
    ('270000', 'Participations et creances rattachees (droit de propriete)', 'asset', 0, p_tenant_id),
    ('271000', 'Titres immobilises (droit de propriete)', 'asset', 0, p_tenant_id),
    ('275000', 'Depots et cautionnements verses', 'asset', 0, p_tenant_id),
    ('280000', 'Amortissements des immobilisations incorporelles', 'asset', 0, p_tenant_id),
    ('280500', 'Amortissements des concessions, brevets, licences, logiciels', 'asset', 0, p_tenant_id),
    ('281000', 'Amortissements des immobilisations corporelles', 'asset', 0, p_tenant_id),
    ('281200', 'Amortissements des constructions', 'asset', 0, p_tenant_id),
    ('281500', 'Amortissements des installations techniques', 'asset', 0, p_tenant_id),
    ('281800', 'Amortissements du materiel', 'asset', 0, p_tenant_id),
    ('290000', 'Depreciations des immobilisations incorporelles', 'asset', 0, p_tenant_id),
    ('291000', 'Depreciations des immobilisations corporelles', 'asset', 0, p_tenant_id),
    ('293000', 'Depreciations des immobilisations en cours', 'asset', 0, p_tenant_id),
    ('296000', 'Depreciations des participations et creances rattachees', 'asset', 0, p_tenant_id),
    ('297000', 'Depreciations des autres immobilisations financieres', 'asset', 0, p_tenant_id),
    -- Classe 3 - Stocks
    ('310000', 'Matieres premieres (et fournitures)', 'asset', 0, p_tenant_id),
    ('320000', 'Matieres consommables', 'asset', 0, p_tenant_id),
    ('321000', 'Matieres consommables', 'asset', 0, p_tenant_id),
    ('322000', 'Fournitures consommables', 'asset', 0, p_tenant_id),
    ('330000', 'En-cours de production de biens', 'asset', 0, p_tenant_id),
    ('340000', 'Etudes en cours', 'asset', 0, p_tenant_id),
    ('345000', 'Travaux en cours', 'asset', 0, p_tenant_id),
    ('350000', 'Produits intermediaires et finis', 'asset', 0, p_tenant_id),
    ('351000', 'Produits intermediaires', 'asset', 0, p_tenant_id),
    ('352000', 'Produits finis', 'asset', 0, p_tenant_id),
    ('354000', 'Produits residuels', 'asset', 0, p_tenant_id),
    ('355000', 'Produits finis (group A)', 'asset', 0, p_tenant_id),
    ('358000', 'Produits finis (group B)', 'asset', 0, p_tenant_id),
    ('360000', 'Stocks provenant d immobilisations', 'asset', 0, p_tenant_id),
    ('370000', 'Stocks de marchandises', 'asset', 0, p_tenant_id),
    ('371000', 'Marchandises (group A)', 'asset', 0, p_tenant_id),
    ('372000', 'Marchandises (group B)', 'asset', 0, p_tenant_id),
    ('380000', 'Stocks a tres rapide rotation', 'asset', 0, p_tenant_id),
    ('390000', 'Depreciations des stocks', 'asset', 0, p_tenant_id),
    ('391000', 'Depreciations des matieres premieres', 'asset', 0, p_tenant_id),
    ('392000', 'Depreciations des matieres consommables', 'asset', 0, p_tenant_id),
    ('393000', 'Depreciations des en-cours de production', 'asset', 0, p_tenant_id),
    ('395000', 'Depreciations des produits', 'asset', 0, p_tenant_id),
    ('397000', 'Depreciations des marchandises', 'asset', 0, p_tenant_id),
    -- Classe 4 - Tiers
    ('400000', 'Fournisseurs et comptes rattaches', 'liability', 0, p_tenant_id),
    ('401000', 'Fournisseurs', 'liability', 0, p_tenant_id),
    ('401100', 'Fournisseurs - achats de biens et services', 'liability', 0, p_tenant_id),
    ('401700', 'Fournisseurs - retenues de garantie', 'liability', 0, p_tenant_id),
    ('403000', 'Fournisseurs - effets a payer', 'liability', 0, p_tenant_id),
    ('404000', 'Fournisseurs d immobilisations', 'liability', 0, p_tenant_id),
    ('405000', 'Fournisseurs d immobilisations - effets a payer', 'liability', 0, p_tenant_id),
    ('408000', 'Fournisseurs - factures non parvenues', 'liability', 0, p_tenant_id),
    ('408100', 'Fournisseurs - factures non parvenues (biens et services)', 'liability', 0, p_tenant_id),
    ('408400', 'Fournisseurs - factures non parvenues (immobilisations)', 'liability', 0, p_tenant_id),
    ('409000', 'Fournisseurs debiteurs', 'asset', 0, p_tenant_id),
    ('409100', 'Fournisseurs - avances et acomptes verses', 'asset', 0, p_tenant_id),
    ('409600', 'Fournisseurs - avoirs a recevoir', 'asset', 0, p_tenant_id),
    ('409700', 'Fournisseurs - autres avoirs', 'asset', 0, p_tenant_id),
    ('410000', 'Clients et comptes rattaches', 'asset', 0, p_tenant_id),
    ('411000', 'Clients', 'asset', 0, p_tenant_id),
    ('411100', 'Clients - ventes de biens et services', 'asset', 0, p_tenant_id),
    ('411700', 'Clients - retenues de garantie', 'asset', 0, p_tenant_id),
    ('413000', 'Clients - effets a recevoir', 'asset', 0, p_tenant_id),
    ('416000', 'Clients douteux ou litigieux', 'asset', 0, p_tenant_id),
    ('417000', 'Clients - creances sur travaux non encore facturables', 'asset', 0, p_tenant_id),
    ('418000', 'Clients - produits non encore factures', 'asset', 0, p_tenant_id),
    ('419000', 'Clients crediteurs', 'liability', 0, p_tenant_id),
    ('419100', 'Clients - avances et acomptes recus', 'liability', 0, p_tenant_id),
    ('419600', 'Clients - avoirs a etablir', 'liability', 0, p_tenant_id),
    ('419700', 'Clients - autres avoirs a etablir', 'liability', 0, p_tenant_id),
    ('420000', 'Personnel et comptes rattaches', 'liability', 0, p_tenant_id),
    ('421000', 'Personnel - remunerations dues', 'liability', 0, p_tenant_id),
    ('422000', 'Comites d entreprise, d etablissement, etc.', 'liability', 0, p_tenant_id),
    ('424000', 'Participation des salaries aux resultats', 'liability', 0, p_tenant_id),
    ('425000', 'Personnel - avances et acomptes', 'asset', 0, p_tenant_id),
    ('426000', 'Personnel - depots', 'liability', 0, p_tenant_id),
    ('427000', 'Personnel - oppositions', 'liability', 0, p_tenant_id),
    ('428000', 'Personnel - charges a payer et produits a recevoir', 'liability', 0, p_tenant_id),
    ('428200', 'Conges payes', 'liability', 0, p_tenant_id),
    ('428400', 'Comptes courants des salaries', 'liability', 0, p_tenant_id),
    ('428600', 'Personnel - produits a recevoir', 'asset', 0, p_tenant_id),
    ('430000', 'Securite sociale et autres organismes sociaux', 'liability', 0, p_tenant_id),
    ('431000', 'Securite sociale', 'liability', 0, p_tenant_id),
    ('432000', 'Autres organismes sociaux', 'liability', 0, p_tenant_id),
    ('437000', 'Autres organismes sociaux', 'liability', 0, p_tenant_id),
    ('438000', 'Organismes sociaux - charges a payer et produits a recevoir', 'liability', 0, p_tenant_id),
    ('438200', 'Charges de securite sociale et de prevoyance', 'liability', 0, p_tenant_id),
    ('438600', 'Organismes sociaux - produits a recevoir', 'asset', 0, p_tenant_id),
    ('440000', 'Etat et autres collectivites publiques', 'liability', 0, p_tenant_id),
    ('441000', 'Etat - subventions a recevoir', 'asset', 0, p_tenant_id),
    ('442000', 'Etat - impots et taxes recuperables', 'asset', 0, p_tenant_id),
    ('443000', 'Operations particulieres avec l Etat', 'liability', 0, p_tenant_id),
    ('444000', 'Etat - impots sur les benefices', 'liability', 0, p_tenant_id),
    ('445000', 'Etat - taxes sur le chiffre d affaires', 'liability', 0, p_tenant_id),
    ('445200', 'TVA due intracommunautaire', 'liability', 0, p_tenant_id),
    ('445510', 'TVA a deduire (biens et services)', 'asset', 0, p_tenant_id),
    ('445560', 'TVA a dedeductible (autres biens et services)', 'asset', 0, p_tenant_id),
    ('445570', 'TVA deductible (immobilisations)', 'asset', 0, p_tenant_id),
    ('445620', 'TVA due (biens et services)', 'liability', 0, p_tenant_id),
    ('445660', 'TVA deductible', 'liability', 0, p_tenant_id),
    ('445670', 'TVA deductible (immobilisations)', 'liability', 0, p_tenant_id),
    ('445710', 'TVA collectee', 'liability', 0, p_tenant_id),
    ('445800', 'TVA a regulariser', 'liability', 0, p_tenant_id),
    ('447000', 'Autres impots, taxes et versements assimiles', 'liability', 0, p_tenant_id),
    ('448000', 'Etat - charges a payer et produits a recevoir', 'liability', 0, p_tenant_id),
    ('448200', 'Etat - charges a payer', 'liability', 0, p_tenant_id),
    ('448600', 'Etat - produits a recevoir', 'asset', 0, p_tenant_id),
    ('449000', 'Etat - subventions a reverser', 'liability', 0, p_tenant_id),
    ('450000', 'Groupes et associes', 'liability', 0, p_tenant_id),
    ('451000', 'Groupes', 'liability', 0, p_tenant_id),
    ('455000', 'Associes - comptes courants', 'liability', 0, p_tenant_id),
    ('456000', 'Associes - operations sur le capital', 'liability', 0, p_tenant_id),
    ('456100', 'Associes - apports en nature', 'liability', 0, p_tenant_id),
    ('456200', 'Associes - apports en numeraire', 'liability', 0, p_tenant_id),
    ('456300', 'Associes - versements restant a effectuer', 'liability', 0, p_tenant_id),
    ('456400', 'Associes - versements anticipes', 'asset', 0, p_tenant_id),
    ('457000', 'Associes - dividendes a payer', 'liability', 0, p_tenant_id),
    ('458000', 'Associes - operations faites en commun', 'liability', 0, p_tenant_id),
    ('460000', 'Debiteurs divers et crediteurs divers', 'asset', 0, p_tenant_id),
    ('461000', 'Debiteurs divers', 'asset', 0, p_tenant_id),
    ('462000', 'Crediteurs divers', 'liability', 0, p_tenant_id),
    ('463000', 'Debiteurs et crediteurs divers', 'asset', 0, p_tenant_id),
    ('464000', 'Debiteurs et crediteurs divers', 'liability', 0, p_tenant_id),
    ('465000', 'Comptes de liaison des etablissements', 'liability', 0, p_tenant_id),
    ('467000', 'Autres comptes debiteurs ou crediteurs', 'asset', 0, p_tenant_id),
    ('468000', 'Divers - charges a payer et produits a recevoir', 'liability', 0, p_tenant_id),
    ('468600', 'Divers - produits a recevoir', 'asset', 0, p_tenant_id),
    ('468700', 'Divers - charges a payer', 'liability', 0, p_tenant_id),
    ('470000', 'Comptes d attente', 'liability', 0, p_tenant_id),
    ('471000', 'Comptes d attente', 'liability', 0, p_tenant_id),
    ('480000', 'Comptes de regularisation', 'liability', 0, p_tenant_id),
    ('481000', 'Charges constatees d avance', 'asset', 0, p_tenant_id),
    ('486000', 'Charges reparties dans le temps', 'asset', 0, p_tenant_id),
    ('487000', 'Produits constates d avance', 'liability', 0, p_tenant_id),
    ('488000', 'Comptes de repartition periodique des charges et produits', 'liability', 0, p_tenant_id),
    ('490000', 'Depreciations des comptes de clients', 'asset', 0, p_tenant_id),
    ('491000', 'Depreciations des comptes de clients', 'asset', 0, p_tenant_id),
    ('495000', 'Depreciations des comptes de debiteurs divers', 'asset', 0, p_tenant_id),
    ('496000', 'Depreciations des creances diverses', 'asset', 0, p_tenant_id),
    -- Classe 5 - Comptes financiers
    ('500000', 'Valeurs mobilieres de placement', 'asset', 0, p_tenant_id),
    ('501000', 'Titres de placement', 'asset', 0, p_tenant_id),
    ('502000', 'Actions propres', 'asset', 0, p_tenant_id),
    ('503000', 'Actions', 'asset', 0, p_tenant_id),
    ('504000', 'Obligations', 'asset', 0, p_tenant_id),
    ('505000', 'Bons du Tresor et bons de caisse', 'asset', 0, p_tenant_id),
    ('506000', 'Obligations et bons emis par la societe', 'asset', 0, p_tenant_id),
    ('507000', 'Bons du Tresor et bons de caisse (emis par la societe)', 'asset', 0, p_tenant_id),
    ('508000', 'Autres valeurs mobilieres de placement', 'asset', 0, p_tenant_id),
    ('509000', 'Versements restant a effectuer sur VMP', 'liability', 0, p_tenant_id),
    ('510000', 'Banques, etablissements financiers et assimiles', 'asset', 0, p_tenant_id),
    ('511000', 'Valeurs a l encaissement', 'asset', 0, p_tenant_id),
    ('511100', 'Coupons echus non encaisses', 'asset', 0, p_tenant_id),
    ('511200', 'Dividendes a encaisser', 'asset', 0, p_tenant_id),
    ('511300', 'Effets a encaisser', 'asset', 0, p_tenant_id),
    ('511400', 'Effets a l encaissement', 'asset', 0, p_tenant_id),
    ('511500', 'Effets remis a l escompte', 'asset', 0, p_tenant_id),
    ('512000', 'Banque', 'asset', 0, p_tenant_id),
    ('512100', 'Comptes en monnaie nationale', 'asset', 0, p_tenant_id),
    ('512400', 'Comptes en devises', 'asset', 0, p_tenant_id),
    ('514000', 'Banques - etablissements financiers', 'asset', 0, p_tenant_id),
    ('515000', 'Caisses du Tresor et des PTT', 'asset', 0, p_tenant_id),
    ('516000', 'Societes de bourse', 'asset', 0, p_tenant_id),
    ('517000', 'Banques a l etranger', 'asset', 0, p_tenant_id),
    ('518000', 'Interets courus a payer', 'liability', 0, p_tenant_id),
    ('518100', 'Interets courus a payer (emprunts)', 'liability', 0, p_tenant_id),
    ('518600', 'Interets courus a recevoir', 'asset', 0, p_tenant_id),
    ('518800', 'Interets courus a payer (autres)', 'liability', 0, p_tenant_id),
    ('519000', 'Concours bancaires courants', 'liability', 0, p_tenant_id),
    ('519100', 'Credit de mobilisation de creances commerciales', 'liability', 0, p_tenant_id),
    ('519300', 'Mobilisation de creances nes a l etranger', 'liability', 0, p_tenant_id),
    ('519400', 'Autres concours bancaires courants', 'liability', 0, p_tenant_id),
    ('519500', 'Credit de mobilisation de creances commerciales (escompte)', 'liability', 0, p_tenant_id),
    ('519700', 'Autres concours bancaires courants', 'liability', 0, p_tenant_id),
    ('520000', 'Instruments de tresorerie', 'asset', 0, p_tenant_id),
    ('521000', 'Instruments de tresorerie - droits', 'asset', 0, p_tenant_id),
    ('522000', 'Instruments de tresorerie - obligations', 'liability', 0, p_tenant_id),
    ('530000', 'Caisse', 'asset', 0, p_tenant_id),
    ('531000', 'Caisse - siege social', 'asset', 0, p_tenant_id),
    ('532000', 'Caisse - succursale ou usine', 'asset', 0, p_tenant_id),
    ('535000', 'Caisse - etablissement a l etranger', 'asset', 0, p_tenant_id),
    ('540000', 'Regies d avances et accréditifs', 'asset', 0, p_tenant_id),
    ('550000', 'Caisse - monnaies etrangeres', 'asset', 0, p_tenant_id),
    ('580000', 'Virements internes', 'asset', 0, p_tenant_id),
    ('590000', 'Depreciations des comptes financiers', 'asset', 0, p_tenant_id),
    ('590100', 'Depreciations des VMP', 'asset', 0, p_tenant_id),
    ('590800', 'Depreciations des autres valeurs mobilieres', 'asset', 0, p_tenant_id),
    -- Classe 6 - Charges
    ('600000', 'Achats (sauf 603)', 'expense', 0, p_tenant_id),
    ('601000', 'Achats de matieres premieres', 'expense', 0, p_tenant_id),
    ('601100', 'Achats de matieres premieres (group A)', 'expense', 0, p_tenant_id),
    ('601200', 'Achats de matieres premieres (group B)', 'expense', 0, p_tenant_id),
    ('602000', 'Achats de matieres consommables', 'expense', 0, p_tenant_id),
    ('602100', 'Achats de matieres consommables', 'expense', 0, p_tenant_id),
    ('602200', 'Achats de fournitures consommables', 'expense', 0, p_tenant_id),
    ('602210', 'Achats de fournitures de bureau', 'expense', 0, p_tenant_id),
    ('602220', 'Achats de fournitures d atelier', 'expense', 0, p_tenant_id),
    ('602400', 'Achats de combustibles', 'expense', 0, p_tenant_id),
    ('602500', 'Achats de produits d entretien', 'expense', 0, p_tenant_id),
    ('602600', 'Achats de fournitures d emballage', 'expense', 0, p_tenant_id),
    ('603000', 'Variations des stocks', 'expense', 0, p_tenant_id),
    ('603100', 'Variation des stocks de matieres premieres', 'expense', 0, p_tenant_id),
    ('603200', 'Variation des stocks de matieres et fournitures consommables', 'expense', 0, p_tenant_id),
    ('603700', 'Variation des stocks de marchandises', 'expense', 0, p_tenant_id),
    ('604000', 'Achats d etudes et de prestations de services', 'expense', 0, p_tenant_id),
    ('605000', 'Achats de materiels, equipements et travaux', 'expense', 0, p_tenant_id),
    ('606000', 'Achats non stockes de matieres et fournitures', 'expense', 0, p_tenant_id),
    ('606100', 'Fournitures non stockables (eau, energie)', 'expense', 0, p_tenant_id),
    ('606110', 'Eau', 'expense', 0, p_tenant_id),
    ('606120', 'Energie (gaz, electricite)', 'expense', 0, p_tenant_id),
    ('606130', 'Carburants', 'expense', 0, p_tenant_id),
    ('606400', 'Fournitures d entretien non stockables', 'expense', 0, p_tenant_id),
    ('606410', 'Produits d entretien', 'expense', 0, p_tenant_id),
    ('606500', 'Fournitures de bureau', 'expense', 0, p_tenant_id),
    ('606600', 'Fournitures de bureau non stockables', 'expense', 0, p_tenant_id),
    ('606800', 'Autres achats non stockes de matieres et fournitures', 'expense', 0, p_tenant_id),
    ('607000', 'Achats de marchandises', 'expense', 0, p_tenant_id),
    ('607100', 'Achats de marchandises (group A)', 'expense', 0, p_tenant_id),
    ('607200', 'Achats de marchandises (group B)', 'expense', 0, p_tenant_id),
    ('608000', 'Frais accessoires d achats', 'expense', 0, p_tenant_id),
    ('608100', 'Frais accessoires d achats sur matieres premieres', 'expense', 0, p_tenant_id),
    ('608200', 'Frais accessoires d achats sur matieres consommables', 'expense', 0, p_tenant_id),
    ('608700', 'Frais accessoires d achats sur marchandises', 'expense', 0, p_tenant_id),
    ('609000', 'Rabais, remises et ristournes obtenus sur achats', 'expense', 0, p_tenant_id),
    ('609100', 'Rabais, remises et ristournes sur achats de matieres premieres', 'expense', 0, p_tenant_id),
    ('609400', 'Rabais, remises et ristournes sur achats d etudes et prestations', 'expense', 0, p_tenant_id),
    ('609600', 'Rabais, remises et ristournes sur achats non stockes', 'expense', 0, p_tenant_id),
    ('609700', 'Rabais, remises et ristournes sur achats de marchandises', 'expense', 0, p_tenant_id),
    ('609800', 'Rabais, remises et ristournes sur frais accessoires d achats', 'expense', 0, p_tenant_id),
    ('610000', 'Services exterieurs', 'expense', 0, p_tenant_id),
    ('611000', 'Sous-traitance generale', 'expense', 0, p_tenant_id),
    ('611100', 'Sous-traitance generale', 'expense', 0, p_tenant_id),
    ('611200', 'Sous-traitance generale (group B)', 'expense', 0, p_tenant_id),
    ('611400', 'Sous-traitance generale (autres)', 'expense', 0, p_tenant_id),
    ('612000', 'Redevances de credit-bail', 'expense', 0, p_tenant_id),
    ('612100', 'Redevances de credit-bail mobilier', 'expense', 0, p_tenant_id),
    ('612200', 'Redevances de credit-bail immobilier', 'expense', 0, p_tenant_id),
    ('612500', 'Redevances de contrats de location-vente', 'expense', 0, p_tenant_id),
    ('613000', 'Locations', 'expense', 0, p_tenant_id),
    ('613100', 'Locations de terrains', 'expense', 0, p_tenant_id),
    ('613200', 'Locations de constructions', 'expense', 0, p_tenant_id),
    ('613500', 'Locations de materiels et outillages', 'expense', 0, p_tenant_id),
    ('613600', 'Locations de materiels et outillages (group B)', 'expense', 0, p_tenant_id),
    ('614000', 'Charges locatives et de copropriete', 'expense', 0, p_tenant_id),
    ('615000', 'Entretien et reparations', 'expense', 0, p_tenant_id),
    ('615100', 'Entretien et reparations de biens immobiliers', 'expense', 0, p_tenant_id),
    ('615200', 'Entretien et reparations de biens mobiliers', 'expense', 0, p_tenant_id),
    ('615500', 'Entretien et reparations de materiels', 'expense', 0, p_tenant_id),
    ('615600', 'Entretien et reparations de materiels de transport', 'expense', 0, p_tenant_id),
    ('616000', 'Assurances', 'expense', 0, p_tenant_id),
    ('616100', 'Assurances multirisques', 'expense', 0, p_tenant_id),
    ('616200', 'Assurances obligatoires dommages construction', 'expense', 0, p_tenant_id),
    ('616300', 'Assurances transports', 'expense', 0, p_tenant_id),
    ('616360', 'Assurances transports (sur achats)', 'expense', 0, p_tenant_id),
    ('616370', 'Assurances transports (sur ventes)', 'expense', 0, p_tenant_id),
    ('616400', 'Assurances risques d exploitation', 'expense', 0, p_tenant_id),
    ('616500', 'Assurances automobiles', 'expense', 0, p_tenant_id),
    ('616600', 'Assurances personnels', 'expense', 0, p_tenant_id),
    ('616800', 'Autres assurances', 'expense', 0, p_tenant_id),
    ('617000', 'Etudes et recherches', 'expense', 0, p_tenant_id),
    ('618000', 'Documentation', 'expense', 0, p_tenant_id),
    ('618100', 'Documentation generale', 'expense', 0, p_tenant_id),
    ('618200', 'Documentation technique', 'expense', 0, p_tenant_id),
    ('618300', 'Documentation commerciale', 'expense', 0, p_tenant_id),
    ('618400', 'Documentation administrative', 'expense', 0, p_tenant_id),
    ('619000', 'Rabais, remises et ristournes obtenus sur services exterieurs', 'expense', 0, p_tenant_id),
    ('620000', 'Autres services exterieurs', 'expense', 0, p_tenant_id),
    ('621000', 'Personnel exterieur a l entreprise', 'expense', 0, p_tenant_id),
    ('621100', 'Personnel integre', 'expense', 0, p_tenant_id),
    ('621400', 'Personnel detache par d autres entreprises', 'expense', 0, p_tenant_id),
    ('621600', 'Personnel exterieur a l entreprise (autres)', 'expense', 0, p_tenant_id),
    ('622000', 'Remuneration d intermediaires et honoraires', 'expense', 0, p_tenant_id),
    ('622100', 'Honoraires (non retenus par la source)', 'expense', 0, p_tenant_id),
    ('622200', 'Commissions et courtages sur achats', 'expense', 0, p_tenant_id),
    ('622400', 'Commissions et courtages sur ventes', 'expense', 0, p_tenant_id),
    ('622500', 'Frais de recouvrement', 'expense', 0, p_tenant_id),
    ('622600', 'Frais d actes et de contentieux', 'expense', 0, p_tenant_id),
    ('622700', 'Frais de reunion, de reception et de representant', 'expense', 0, p_tenant_id),
    ('622800', 'Divers', 'expense', 0, p_tenant_id),
    ('623000', 'Publicite, publications, relations publiques', 'expense', 0, p_tenant_id),
    ('623100', 'Annonces et insertions', 'expense', 0, p_tenant_id),
    ('623200', 'Echantillons, catalogues et prospectus', 'expense', 0, p_tenant_id),
    ('623300', 'Foires et expositions', 'expense', 0, p_tenant_id),
    ('623400', 'Cadeaux a la clientele', 'expense', 0, p_tenant_id),
    ('623500', 'Primes', 'expense', 0, p_tenant_id),
    ('623600', 'Catalogues et imprimes', 'expense', 0, p_tenant_id),
    ('623700', 'Publicite directe', 'expense', 0, p_tenant_id),
    ('623800', 'Divers (pourboires, etc.)', 'expense', 0, p_tenant_id),
    ('624000', 'Transports de biens et transports collectifs du personnel', 'expense', 0, p_tenant_id),
    ('624100', 'Transports sur achats', 'expense', 0, p_tenant_id),
    ('624200', 'Transports sur ventes', 'expense', 0, p_tenant_id),
    ('624300', 'Transports entre etablissements', 'expense', 0, p_tenant_id),
    ('624400', 'Transports administratifs', 'expense', 0, p_tenant_id),
    ('624700', 'Transports collectifs du personnel', 'expense', 0, p_tenant_id),
    ('625000', 'Deplacements, missions et receptions', 'expense', 0, p_tenant_id),
    ('625100', 'Voyages et deplacements', 'expense', 0, p_tenant_id),
    ('625600', 'Missions', 'expense', 0, p_tenant_id),
    ('625700', 'Receptions', 'expense', 0, p_tenant_id),
    ('626000', 'Frais postaux et de telecommunications', 'expense', 0, p_tenant_id),
    ('626100', 'Frais postaux', 'expense', 0, p_tenant_id),
    ('626300', 'Frais de telecommunications', 'expense', 0, p_tenant_id),
    ('626500', 'Frais de telecommunications (autres)', 'expense', 0, p_tenant_id),
    ('627000', 'Services bancaires et assimiles', 'expense', 0, p_tenant_id),
    ('627100', 'Frais de tenue de compte', 'expense', 0, p_tenant_id),
    ('627200', 'Commissions sur acceptation et negociation de creances', 'expense', 0, p_tenant_id),
    ('627500', 'Commissions et frais sur encaissements', 'expense', 0, p_tenant_id),
    ('627600', 'Commissions et frais sur encaissements (autres)', 'expense', 0, p_tenant_id),
    ('627800', 'Autres frais et commissions sur prestations de services', 'expense', 0, p_tenant_id),
    ('628000', 'Divers', 'expense', 0, p_tenant_id),
    ('628100', 'Concours divers (cotisations, etc.)', 'expense', 0, p_tenant_id),
    ('628400', 'Frais de recrutement de personnel', 'expense', 0, p_tenant_id),
    ('629000', 'Rabais, remises et ristournes obtenus sur autres services exterieurs', 'expense', 0, p_tenant_id),
    ('630000', 'Autres charges', 'expense', 0, p_tenant_id),
    ('631000', 'Impots, taxes et versements assimiles sur remunerations', 'expense', 0, p_tenant_id),
    ('631100', 'Impots, taxes et versements assimiles sur remunerations (administrations)', 'expense', 0, p_tenant_id),
    ('631200', 'Impots, taxes et versements assimiles sur remunerations (autres organismes)', 'expense', 0, p_tenant_id),
    ('631300', 'Participation des employeurs a la formation professionnelle continue', 'expense', 0, p_tenant_id),
    ('631400', 'Participation des employeurs a l effort de construction', 'expense', 0, p_tenant_id),
    ('631600', 'Impots, taxes et versements assimiles sur remunerations (autres)', 'expense', 0, p_tenant_id),
    ('631800', 'Autres impots, taxes et versements assimiles sur remunerations', 'expense', 0, p_tenant_id),
    ('633000', 'Impots, taxes et versements assimiles sur immobilisations', 'expense', 0, p_tenant_id),
    ('635000', 'Impots, taxes et versements assimiles sur le chiffre d affaires', 'expense', 0, p_tenant_id),
    ('635100', 'Impots, taxes et versements assimiles sur le chiffre d affaires (TVA)', 'expense', 0, p_tenant_id),
    ('635200', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', 0, p_tenant_id),
    ('635300', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', 0, p_tenant_id),
    ('635400', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', 0, p_tenant_id),
    ('635500', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', 0, p_tenant_id),
    ('635800', 'Autres impots, taxes et versements assimiles sur le chiffre d affaires', 'expense', 0, p_tenant_id),
    ('636000', 'Impots, taxes et versements assimiles sur le capital', 'expense', 0, p_tenant_id),
    ('637000', 'Autres impots, taxes et versements assimiles', 'expense', 0, p_tenant_id),
    ('637100', 'Impots, taxes et versements assimiles (autres)', 'expense', 0, p_tenant_id),
    ('637200', 'Impots, taxes et versements assimiles (autres)', 'expense', 0, p_tenant_id),
    ('637300', 'Impots, taxes et versements assimiles (autres)', 'expense', 0, p_tenant_id),
    ('637400', 'Impots, taxes et versements assimiles (autres)', 'expense', 0, p_tenant_id),
    ('637800', 'Autres impots, taxes et versements assimiles', 'expense', 0, p_tenant_id),
    ('638000', 'Autres impots, taxes et versements assimiles', 'expense', 0, p_tenant_id),
    ('639000', 'Rabais, remises et ristournes obtenus sur autres charges externes', 'expense', 0, p_tenant_id),
    ('640000', 'Charges de personnel', 'expense', 0, p_tenant_id),
    ('641000', 'Remunerations du personnel', 'expense', 0, p_tenant_id),
    ('641100', 'Apprentis', 'expense', 0, p_tenant_id),
    ('641200', 'Stagiaires', 'expense', 0, p_tenant_id),
    ('641300', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641400', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641500', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641600', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641700', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641800', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('642000', 'Remunerations du personnel de direction', 'expense', 0, p_tenant_id),
    ('643000', 'Remunerations du personnel de direction', 'expense', 0, p_tenant_id),
    ('644000', 'Remuneration du travail de l exploitant', 'expense', 0, p_tenant_id),
    ('645000', 'Charges sociales', 'expense', 0, p_tenant_id),
    ('645100', 'Cotisations a l URSSAF', 'expense', 0, p_tenant_id),
    ('645200', 'Cotisations aux mutuelles', 'expense', 0, p_tenant_id),
    ('645300', 'Cotisations caisses de retraite', 'expense', 0, p_tenant_id),
    ('645400', 'Cotisations aux ASSEDIC', 'expense', 0, p_tenant_id),
    ('645500', 'Prevoyances', 'expense', 0, p_tenant_id),
    ('645800', 'Cotisations aux autres organismes sociaux', 'expense', 0, p_tenant_id),
    ('646000', 'Cotisations sociales personnelles de l exploitant', 'expense', 0, p_tenant_id),
    ('647000', 'Autres charges sociales', 'expense', 0, p_tenant_id),
    ('647100', 'Prestations de retraites', 'expense', 0, p_tenant_id),
    ('647200', 'Prestations directes', 'expense', 0, p_tenant_id),
    ('647300', 'Prestations de retraites (autres)', 'expense', 0, p_tenant_id),
    ('647400', 'Prestations directes (autres)', 'expense', 0, p_tenant_id),
    ('647500', 'Medecine du travail, pharmacie', 'expense', 0, p_tenant_id),
    ('647800', 'Autres charges sociales', 'expense', 0, p_tenant_id),
    ('648000', 'Autres charges de personnel', 'expense', 0, p_tenant_id),
    ('649000', 'Rabais, remises et ristournes obtenus sur charges de personnel', 'expense', 0, p_tenant_id),
    ('650000', 'Autres charges de gestion courante', 'expense', 0, p_tenant_id),
    ('651000', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'expense', 0, p_tenant_id),
    ('651100', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'expense', 0, p_tenant_id),
    ('651600', 'Droits d auteur', 'expense', 0, p_tenant_id),
    ('651800', 'Autres redevances', 'expense', 0, p_tenant_id),
    ('653000', 'Jetons de presence', 'expense', 0, p_tenant_id),
    ('654000', 'Pertes sur creances irrecouvrables', 'expense', 0, p_tenant_id),
    ('654100', 'Pertes sur creances clients', 'expense', 0, p_tenant_id),
    ('654400', 'Pertes sur creances autres', 'expense', 0, p_tenant_id),
    ('655000', 'Quotes-parts de resultat sur operations faites en commun', 'expense', 0, p_tenant_id),
    ('655100', 'Quotes-parts de benefice', 'expense', 0, p_tenant_id),
    ('655200', 'Quotes-parts de pertes', 'expense', 0, p_tenant_id),
    ('656000', 'Pertes de change', 'expense', 0, p_tenant_id),
    ('656100', 'Pertes de change (autres)', 'expense', 0, p_tenant_id),
    ('656600', 'Pertes de change (autres)', 'expense', 0, p_tenant_id),
    ('656800', 'Ecarts de conversion - actif', 'expense', 0, p_tenant_id),
    ('657000', 'Charges de gestion courante (autres)', 'expense', 0, p_tenant_id),
    ('658000', 'Charges diverses de gestion courante', 'expense', 0, p_tenant_id),
    ('658100', 'Pertes sur operations a terme', 'expense', 0, p_tenant_id),
    ('658200', 'Pertes sur operations de change a terme', 'expense', 0, p_tenant_id),
    ('658600', 'Autres charges diverses de gestion courante', 'expense', 0, p_tenant_id),
    ('658800', 'Rabais, remises et ristournes obtenus sur autres charges de gestion courante', 'expense', 0, p_tenant_id),
    ('660000', 'Charges financieres', 'expense', 0, p_tenant_id),
    ('661000', 'Charges d interets', 'expense', 0, p_tenant_id),
    ('661100', 'Interets sur emprunts et dettes', 'expense', 0, p_tenant_id),
    ('661110', 'Interets sur emprunts', 'expense', 0, p_tenant_id),
    ('661120', 'Interets sur dettes financieres', 'expense', 0, p_tenant_id),
    ('661130', 'Interets sur comptes courants et depots crediteurs', 'expense', 0, p_tenant_id),
    ('661160', 'Interets bancaires et sur operations de financement', 'expense', 0, p_tenant_id),
    ('661170', 'Interets sur autres operations de financement', 'expense', 0, p_tenant_id),
    ('661180', 'Interets des obligations', 'expense', 0, p_tenant_id),
    ('661500', 'Interets bancaires et sur operations de financement (escompte)', 'expense', 0, p_tenant_id),
    ('661600', 'Interets sur autres operations de financement', 'expense', 0, p_tenant_id),
    ('661700', 'Interets sur autres operations de financement (autres)', 'expense', 0, p_tenant_id),
    ('661800', 'Interets sur autres operations de financement (autres)', 'expense', 0, p_tenant_id),
    ('662000', 'Pertes de change', 'expense', 0, p_tenant_id),
    ('664000', 'Pertes sur creances liees a des participations', 'expense', 0, p_tenant_id),
    ('665000', 'Escomptes accordes', 'expense', 0, p_tenant_id),
    ('666000', 'Pertes de change', 'expense', 0, p_tenant_id),
    ('667000', 'Charges nettes sur cessions d immobilisations financieres', 'expense', 0, p_tenant_id),
    ('668000', 'Autres charges financieres', 'expense', 0, p_tenant_id),
    ('668100', 'Interets sur obligations', 'expense', 0, p_tenant_id),
    ('668200', 'Interets sur bons de caisse', 'expense', 0, p_tenant_id),
    ('668400', 'Autres charges financieres (autres)', 'expense', 0, p_tenant_id),
    ('668800', 'Frais financiers sur emprunts', 'expense', 0, p_tenant_id),
    ('669000', 'Rabais, remises et ristournes obtenus sur charges financieres', 'expense', 0, p_tenant_id),
    ('670000', 'Charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('671000', 'Charges exceptionnelles sur operations de gestion', 'expense', 0, p_tenant_id),
    ('671100', 'Penalites sur marches', 'expense', 0, p_tenant_id),
    ('671200', 'Penalites, amendes fiscales et penales', 'expense', 0, p_tenant_id),
    ('671300', 'Dons, liberalites', 'expense', 0, p_tenant_id),
    ('671400', 'Subventions accordees', 'expense', 0, p_tenant_id),
    ('671500', 'Rappels d impots (autres que sur le benefice)', 'expense', 0, p_tenant_id),
    ('671700', 'Rappels d impots (sur le benefice)', 'expense', 0, p_tenant_id),
    ('671800', 'Autres charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('672000', 'Charges sur exercices anterieurs', 'expense', 0, p_tenant_id),
    ('672100', 'Charges sur exercices anterieurs (operations de gestion)', 'expense', 0, p_tenant_id),
    ('672200', 'Charges sur exercices anterieurs (operations de capital)', 'expense', 0, p_tenant_id),
    ('675000', 'Valeurs comptables des elements d actif cedes', 'expense', 0, p_tenant_id),
    ('675100', 'Immobilisations incorporelles', 'expense', 0, p_tenant_id),
    ('675200', 'Immobilisations corporelles', 'expense', 0, p_tenant_id),
    ('675300', 'Immobilisations financieres', 'expense', 0, p_tenant_id),
    ('675400', 'Stocks', 'expense', 0, p_tenant_id),
    ('675500', 'Autres elements d actif', 'expense', 0, p_tenant_id),
    ('675600', 'Actions propres', 'expense', 0, p_tenant_id),
    ('675800', 'Autres valeurs comptables des elements d actif cedes', 'expense', 0, p_tenant_id),
    ('676000', 'Pertes de change', 'expense', 0, p_tenant_id),
    ('678000', 'Autres charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('678100', 'Bonis provenant de clauses d indexation', 'expense', 0, p_tenant_id),
    ('678200', 'Malis provenant de clauses d indexation', 'expense', 0, p_tenant_id),
    ('678300', 'Subventions d equilibrage', 'expense', 0, p_tenant_id),
    ('678400', 'Subventions d investissement a reprendre', 'expense', 0, p_tenant_id),
    ('678800', 'Autres charges exceptionnelles (autres)', 'expense', 0, p_tenant_id),
    ('679000', 'Rabais, remises et ristournes obtenus sur charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('680000', 'Dotations aux amortissements et aux provisions', 'expense', 0, p_tenant_id),
    ('681000', 'Dotations aux amortissements et aux provisions - charges d exploitation', 'expense', 0, p_tenant_id),
    ('681100', 'Dotations aux amortissements sur immobilisations incorporelles', 'expense', 0, p_tenant_id),
    ('681110', 'Dotations aux amortissements des frais d etablissement', 'expense', 0, p_tenant_id),
    ('681120', 'Dotations aux amortissements des concessions, brevets, licences, logiciels', 'expense', 0, p_tenant_id),
    ('681150', 'Dotations aux amortissements des fonds commercial', 'expense', 0, p_tenant_id),
    ('681200', 'Dotations aux amortissements sur immobilisations corporelles', 'expense', 0, p_tenant_id),
    ('681210', 'Dotations aux amortissements des terrains', 'expense', 0, p_tenant_id),
    ('681220', 'Dotations aux amortissements des constructions', 'expense', 0, p_tenant_id),
    ('681230', 'Dotations aux amortissements des installations techniques', 'expense', 0, p_tenant_id),
    ('681240', 'Dotations aux amortissements du mobilier', 'expense', 0, p_tenant_id),
    ('681250', 'Dotations aux amortissements du materiel', 'expense', 0, p_tenant_id),
    ('681260', 'Dotations aux amortissements du materiel de transport', 'expense', 0, p_tenant_id),
    ('681700', 'Dotations aux amortissements des immobilisations en cours', 'expense', 0, p_tenant_id),
    ('681500', 'Dotations aux provisions pour risques d exploitation', 'expense', 0, p_tenant_id),
    ('681600', 'Dotations aux provisions pour depreciation des immobilisations incorporelles', 'expense', 0, p_tenant_id),
    ('681610', 'Dotations aux provisions pour depreciation des immobilisations corporelles', 'expense', 0, p_tenant_id),
    ('681620', 'Dotations aux provisions pour depreciation des stocks', 'expense', 0, p_tenant_id),
    ('681630', 'Dotations aux provisions pour depreciation des creances', 'expense', 0, p_tenant_id),
    ('681640', 'Dotations aux provisions pour depreciation des titres de placement', 'expense', 0, p_tenant_id),
    ('681650', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681800', 'Autres dotations aux amortissements et aux provisions', 'expense', 0, p_tenant_id),
    ('681810', 'Dotations aux provisions pour risques et charges d exploitation', 'expense', 0, p_tenant_id),
    ('681820', 'Dotations aux provisions pour depreciation des actifs circulant', 'expense', 0, p_tenant_id),
    ('681830', 'Dotations aux provisions pour depreciation des comptes de tiers', 'expense', 0, p_tenant_id),
    ('681840', 'Dotations aux provisions pour depreciation des comptes financiers', 'expense', 0, p_tenant_id),
    ('681850', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681860', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681870', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681880', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681890', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('686000', 'Dotations aux amortissements et aux provisions - charges financieres', 'expense', 0, p_tenant_id),
    ('686100', 'Dotations aux amortissements des immobilisations financieres', 'expense', 0, p_tenant_id),
    ('686500', 'Dotations aux provisions pour risques financiers', 'expense', 0, p_tenant_id),
    ('686600', 'Dotations aux provisions pour depreciation des immobilisations financieres', 'expense', 0, p_tenant_id),
    ('686700', 'Dotations aux provisions pour depreciation des valeurs mobilieres de placement', 'expense', 0, p_tenant_id),
    ('686800', 'Autres dotations aux provisions financieres', 'expense', 0, p_tenant_id),
    ('687000', 'Dotations aux amortissements et aux provisions - charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('687100', 'Dotations aux amortissements exceptionnels des immobilisations', 'expense', 0, p_tenant_id),
    ('687200', 'Dotations aux provisions reglementees (immobilisations)', 'expense', 0, p_tenant_id),
    ('687300', 'Dotations aux provisions reglementees (stocks)', 'expense', 0, p_tenant_id),
    ('687400', 'Dotations aux autres provisions reglementees', 'expense', 0, p_tenant_id),
    ('687500', 'Dotations aux provisions pour risques et charges exceptionnels', 'expense', 0, p_tenant_id),
    ('687600', 'Dotations aux provisions pour depreciation exceptionnelles', 'expense', 0, p_tenant_id),
    ('687700', 'Dotations aux autres provisions exceptionnelles', 'expense', 0, p_tenant_id),
    -- Classe 7 - Produits
    ('700000', 'Ventes de marchandises, production vendue (biens et services)', 'income', 0, p_tenant_id),
    ('701000', 'Ventes de produits finis', 'income', 0, p_tenant_id),
    ('701100', 'Ventes de produits finis (group A)', 'income', 0, p_tenant_id),
    ('701200', 'Ventes de produits finis (group B)', 'income', 0, p_tenant_id),
    ('702000', 'Ventes de produits intermediaires', 'income', 0, p_tenant_id),
    ('702100', 'Ventes de produits intermediaires (group A)', 'income', 0, p_tenant_id),
    ('702200', 'Ventes de produits intermediaires (group B)', 'income', 0, p_tenant_id),
    ('703000', 'Ventes de produits residuels', 'income', 0, p_tenant_id),
    ('704000', 'Travaux', 'income', 0, p_tenant_id),
    ('704100', 'Travaux de construction', 'income', 0, p_tenant_id),
    ('704200', 'Travaux de montage', 'income', 0, p_tenant_id),
    ('705000', 'Etudes', 'income', 0, p_tenant_id),
    ('706000', 'Prestations de services', 'income', 0, p_tenant_id),
    ('706100', 'Prestations de services (group A)', 'income', 0, p_tenant_id),
    ('706200', 'Prestations de services (group B)', 'income', 0, p_tenant_id),
    ('707000', 'Ventes de marchandises', 'income', 0, p_tenant_id),
    ('707100', 'Ventes de marchandises (group A)', 'income', 0, p_tenant_id),
    ('707200', 'Ventes de marchandises (group B)', 'income', 0, p_tenant_id),
    ('708000', 'Produits des activites annexes', 'income', 0, p_tenant_id),
    ('708100', 'Produits des services exploités dans l interet du personnel', 'income', 0, p_tenant_id),
    ('708200', 'Commissions et courtages', 'income', 0, p_tenant_id),
    ('708300', 'Locations diverses', 'income', 0, p_tenant_id),
    ('708400', 'Mise a disposition de personnel', 'income', 0, p_tenant_id),
    ('708500', 'Ports et frais accessoires factures', 'income', 0, p_tenant_id),
    ('708600', 'Bonis sur reprises de emballages consignés', 'income', 0, p_tenant_id),
    ('708800', 'Autres produits d activites annexes', 'income', 0, p_tenant_id),
    ('709000', 'Rabais, remises et ristournes accordes par l entreprise', 'income', 0, p_tenant_id),
    ('709100', 'Rabais, remises et ristournes sur ventes de produits finis', 'income', 0, p_tenant_id),
    ('709600', 'Rabais, remises et ristournes sur prestations de services', 'income', 0, p_tenant_id),
    ('709700', 'Rabais, remises et ristournes sur ventes de marchandises', 'income', 0, p_tenant_id),
    ('709800', 'Rabais, remises et ristournes sur produits des activites annexes', 'income', 0, p_tenant_id),
    ('710000', 'Variation des stocks et production stockee', 'income', 0, p_tenant_id),
    ('713000', 'Variation des stocks (en-cours de production, produits)', 'income', 0, p_tenant_id),
    ('713100', 'Variation des stocks de produits en cours', 'income', 0, p_tenant_id),
    ('713300', 'Variation des stocks de produits', 'income', 0, p_tenant_id),
    ('713400', 'Variation des stocks de services en cours', 'income', 0, p_tenant_id),
    ('713500', 'Variation des stocks de produits finis', 'income', 0, p_tenant_id),
    ('713600', 'Variation des stocks de produits residuels', 'income', 0, p_tenant_id),
    ('713700', 'Variation des stocks de marchandises', 'income', 0, p_tenant_id),
    ('720000', 'Production immobilisee', 'income', 0, p_tenant_id),
    ('721000', 'Production immobilisee - immobilisations incorporelles', 'income', 0, p_tenant_id),
    ('722000', 'Production immobilisee - immobilisations corporelles', 'income', 0, p_tenant_id),
    ('740000', 'Subventions d exploitation', 'income', 0, p_tenant_id),
    ('740100', 'Subventions d exploitation du budget de l Etat', 'income', 0, p_tenant_id),
    ('740200', 'Subventions d exploitation des collectivites locales', 'income', 0, p_tenant_id),
    ('740300', 'Subventions d exploitation des etablissements publics', 'income', 0, p_tenant_id),
    ('740400', 'Subventions d exploitation des entreprises publiques', 'income', 0, p_tenant_id),
    ('740500', 'Subventions d exploitation des autres organismes', 'income', 0, p_tenant_id),
    ('740600', 'Subventions d exploitation des autres organismes (autres)', 'income', 0, p_tenant_id),
    ('740700', 'Subventions d exploitation des autres organismes (autres)', 'income', 0, p_tenant_id),
    ('740800', 'Subventions d exploitation des autres organismes (autres)', 'income', 0, p_tenant_id),
    ('741000', 'Subventions d equilibrage', 'income', 0, p_tenant_id),
    ('748000', 'Autres subventions d exploitation', 'income', 0, p_tenant_id),
    ('750000', 'Autres produits de gestion courante', 'income', 0, p_tenant_id),
    ('751000', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'income', 0, p_tenant_id),
    ('751100', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'income', 0, p_tenant_id),
    ('751600', 'Droits d auteur', 'income', 0, p_tenant_id),
    ('751800', 'Autres redevances', 'income', 0, p_tenant_id),
    ('752000', 'Revenus des immeubles non affectes a l exploitation professionnelle', 'income', 0, p_tenant_id),
    ('753000', 'Jetons de presence et remuneration d administrateurs', 'income', 0, p_tenant_id),
    ('754000', 'Quotes-parts de resultat sur operations faites en commun', 'income', 0, p_tenant_id),
    ('754100', 'Quotes-parts de perte', 'income', 0, p_tenant_id),
    ('754200', 'Quotes-parts de benefice', 'income', 0, p_tenant_id),
    ('755000', 'Quotes-parts de perte sur operations faites en commun', 'income', 0, p_tenant_id),
    ('756000', 'Gains de change', 'income', 0, p_tenant_id),
    ('756100', 'Gains de change (autres)', 'income', 0, p_tenant_id),
    ('756600', 'Gains de change (autres)', 'income', 0, p_tenant_id),
    ('756800', 'Ecarts de conversion - passif', 'income', 0, p_tenant_id),
    ('757000', 'Produits de gestion courante (autres)', 'income', 0, p_tenant_id),
    ('758000', 'Produits divers de gestion courante', 'income', 0, p_tenant_id),
    ('758100', 'Gains sur operations a terme', 'income', 0, p_tenant_id),
    ('758200', 'Gains sur operations de change a terme', 'income', 0, p_tenant_id),
    ('758600', 'Autres produits divers de gestion courante', 'income', 0, p_tenant_id),
    ('758800', 'Rabais, remises et ristournes obtenus sur autres produits de gestion courante', 'income', 0, p_tenant_id),
    ('760000', 'Produits financiers', 'income', 0, p_tenant_id),
    ('761000', 'Produits de participations', 'income', 0, p_tenant_id),
    ('761100', 'Revenus des titres de participation', 'income', 0, p_tenant_id),
    ('761600', 'Revenus sur autres formes de participation', 'income', 0, p_tenant_id),
    ('761700', 'Quotes-parts de resultat sur operations faites en commun', 'income', 0, p_tenant_id),
    ('761800', 'Revenus des creances rattachees a des participations', 'income', 0, p_tenant_id),
    ('762000', 'Produits des autres immobilisations financieres', 'income', 0, p_tenant_id),
    ('762100', 'Revenus des titres immobilises', 'income', 0, p_tenant_id),
    ('762600', 'Revenus des pretes', 'income', 0, p_tenant_id),
    ('762700', 'Revenus des creances commerciales', 'income', 0, p_tenant_id),
    ('763000', 'Revenus des autres creances', 'income', 0, p_tenant_id),
    ('763100', 'Revenus des creances commerciales', 'income', 0, p_tenant_id),
    ('763200', 'Revenus des creances diverses', 'income', 0, p_tenant_id),
    ('764000', 'Revenus des valeurs mobilieres de placement', 'income', 0, p_tenant_id),
    ('764100', 'Revenus des actions', 'income', 0, p_tenant_id),
    ('764200', 'Revenus des obligations', 'income', 0, p_tenant_id),
    ('764300', 'Revenus des bons de caisse et du Tresor', 'income', 0, p_tenant_id),
    ('764400', 'Revenus des autres valeurs mobilieres de placement', 'income', 0, p_tenant_id),
    ('765000', 'Escomptes obtenus', 'income', 0, p_tenant_id),
    ('766000', 'Gains de change', 'income', 0, p_tenant_id),
    ('767000', 'Produits nets sur cessions d immobilisations financieres', 'income', 0, p_tenant_id),
    ('768000', 'Autres produits financiers', 'income', 0, p_tenant_id),
    ('768100', 'Interets sur obligations', 'income', 0, p_tenant_id),
    ('768200', 'Interets sur bons de caisse', 'income', 0, p_tenant_id),
    ('768400', 'Autres produits financiers (autres)', 'income', 0, p_tenant_id),
    ('768800', 'Produits des operations de financement', 'income', 0, p_tenant_id),
    ('769000', 'Rabais, remises et ristournes obtenus sur produits financiers', 'income', 0, p_tenant_id),
    ('770000', 'Produits exceptionnels', 'income', 0, p_tenant_id),
    ('771000', 'Produits exceptionnels sur operations de gestion', 'income', 0, p_tenant_id),
    ('771100', 'Dedommagements recus', 'income', 0, p_tenant_id),
    ('771200', 'Dégrèvements d impots', 'income', 0, p_tenant_id),
    ('771300', 'Liberalites recues', 'income', 0, p_tenant_id),
    ('771400', 'Subventions d equilibrage', 'income', 0, p_tenant_id),
    ('771500', 'Subventions d investissement', 'income', 0, p_tenant_id),
    ('771700', 'Rentrées sur creances amorties', 'income', 0, p_tenant_id),
    ('771800', 'Autres produits exceptionnels', 'income', 0, p_tenant_id),
    ('772000', 'Produits sur exercices anterieurs', 'income', 0, p_tenant_id),
    ('772100', 'Produits sur exercices anterieurs (operations de gestion)', 'income', 0, p_tenant_id),
    ('772200', 'Produits sur exercices anterieurs (operations de capital)', 'income', 0, p_tenant_id),
    ('775000', 'Produits des cessions d elements d actif', 'income', 0, p_tenant_id),
    ('775100', 'Immobilisations incorporelles', 'income', 0, p_tenant_id),
    ('775200', 'Immobilisations corporelles', 'income', 0, p_tenant_id),
    ('775300', 'Immobilisations financieres', 'income', 0, p_tenant_id),
    ('775400', 'Stocks', 'income', 0, p_tenant_id),
    ('775500', 'Autres elements d actif', 'income', 0, p_tenant_id),
    ('775600', 'Actions propres', 'income', 0, p_tenant_id),
    ('775800', 'Autres produits des cessions d elements d actif', 'income', 0, p_tenant_id),
    ('776000', 'Gains de change', 'income', 0, p_tenant_id),
    ('777000', 'Quotes-parts des subventions d investissement inscrites au resultat de l exercice', 'income', 0, p_tenant_id),
    ('778000', 'Autres produits exceptionnels', 'income', 0, p_tenant_id),
    ('778100', 'Bonis provenant de clauses d indexation', 'income', 0, p_tenant_id),
    ('778200', 'Malis provenant de clauses d indexation', 'income', 0, p_tenant_id),
    ('778300', 'Subventions d equilibrage', 'income', 0, p_tenant_id),
    ('778400', 'Subventions d investissement a reprendre', 'income', 0, p_tenant_id),
    ('778800', 'Autres produits exceptionnels (autres)', 'income', 0, p_tenant_id),
    ('779000', 'Rabais, remises et ristournes accordes sur produits exceptionnels', 'income', 0, p_tenant_id),
    ('780000', 'Reprises sur amortissements et provisions', 'income', 0, p_tenant_id),
    ('781000', 'Reprises sur amortissements et provisions - charges d exploitation', 'income', 0, p_tenant_id),
    ('781100', 'Reprises sur amortissements des immobilisations incorporelles', 'income', 0, p_tenant_id),
    ('781200', 'Reprises sur amortissements des immobilisations corporelles', 'income', 0, p_tenant_id),
    ('781500', 'Reprises sur provisions pour risques d exploitation', 'income', 0, p_tenant_id),
    ('781600', 'Reprises sur provisions pour depreciation des immobilisations incorporelles', 'income', 0, p_tenant_id),
    ('781610', 'Reprises sur provisions pour depreciation des immobilisations corporelles', 'income', 0, p_tenant_id),
    ('781620', 'Reprises sur provisions pour depreciation des stocks', 'income', 0, p_tenant_id),
    ('781630', 'Reprises sur provisions pour depreciation des creances', 'income', 0, p_tenant_id),
    ('781640', 'Reprises sur provisions pour depreciation des titres de placement', 'income', 0, p_tenant_id),
    ('781700', 'Reprises sur provisions pour depreciation des autres elements d actif', 'income', 0, p_tenant_id),
    ('781800', 'Autres reprises sur amortissements et provisions', 'income', 0, p_tenant_id),
    ('786000', 'Reprises sur amortissements et provisions - charges financieres', 'income', 0, p_tenant_id),
    ('786100', 'Reprises sur amortissements des immobilisations financieres', 'income', 0, p_tenant_id),
    ('786500', 'Reprises sur provisions pour risques financiers', 'income', 0, p_tenant_id),
    ('786600', 'Reprises sur provisions pour depreciation des immobilisations financieres', 'income', 0, p_tenant_id),
    ('786700', 'Reprises sur provisions pour depreciation des valeurs mobilieres de placement', 'income', 0, p_tenant_id),
    ('786800', 'Autres reprises sur provisions financieres', 'income', 0, p_tenant_id),
    ('787000', 'Reprises sur amortissements et provisions - charges exceptionnelles', 'income', 0, p_tenant_id),
    ('787100', 'Reprises sur amortissements exceptionnels des immobilisations', 'income', 0, p_tenant_id),
    ('787200', 'Reprises sur provisions reglementees (immobilisations)', 'income', 0, p_tenant_id),
    ('787300', 'Reprises sur provisions reglementees (stocks)', 'income', 0, p_tenant_id),
    ('787400', 'Reprises sur autres provisions reglementees', 'income', 0, p_tenant_id),
    ('787500', 'Reprises sur provisions pour risques et charges exceptionnels', 'income', 0, p_tenant_id),
    ('787600', 'Reprises sur provisions pour depreciation exceptionnelles', 'income', 0, p_tenant_id),
    ('787700', 'Reprises sur autres provisions exceptionnelles', 'income', 0, p_tenant_id),
    ('790000', 'Transferts de charges', 'income', 0, p_tenant_id),
    ('791000', 'Transferts de charges d exploitation', 'income', 0, p_tenant_id),
    ('796000', 'Transferts de charges financieres', 'income', 0, p_tenant_id),
    ('797000', 'Transferts de charges exceptionnelles', 'income', 0, p_tenant_id),
    -- Classe 8 - Comptes speciaux
    ('800000', 'Engagements financiers', 'liability', 0, p_tenant_id),
    ('801000', 'Engagements de garantie', 'liability', 0, p_tenant_id),
    ('801100', 'Avals, cautions, garanties', 'liability', 0, p_tenant_id),
    ('801400', 'Credits de signature par endossement', 'liability', 0, p_tenant_id),
    ('801700', 'Hypotèques', 'liability', 0, p_tenant_id),
    ('801800', 'Gages sur stocks', 'liability', 0, p_tenant_id),
    ('804000', 'Engagements financiers recus', 'asset', 0, p_tenant_id),
    ('804100', 'Avals, cautions, garanties recus', 'asset', 0, p_tenant_id),
    ('804400', 'Credits de signature par endossement recus', 'asset', 0, p_tenant_id),
    ('804500', 'Hypotèques recues', 'asset', 0, p_tenant_id),
    ('804800', 'Gages sur stocks recus', 'asset', 0, p_tenant_id),
    ('808000', 'Engagements divers', 'liability', 0, p_tenant_id),
    ('808100', 'Engagements divers donnes', 'liability', 0, p_tenant_id),
    ('808400', 'Engagements divers recus', 'asset', 0, p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;
  -- AUD-C04 : comptes de TVA du paramétrage (445661…, 445711…) imputés par les factures
  PERFORM seed_vat_accounts(p_tenant_id);
END;
$function$;

SELECT seed_vat_accounts(t.id) FROM tenants t
WHERE EXISTS (SELECT 1 FROM chart_accounts ca WHERE ca.tenant_id = t.id);

-- ------------------------------------------------------------
-- 8. post_journal_entry : journal OD par défaut (AUD-C09)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.post_journal_entry(p_entry jsonb, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_requested_status text := COALESCE(NULLIF(p_entry ->> 'status', ''), 'draft');
  v_entry_id uuid;
  v_number text;
  v_journal_code text;
BEGIN
  IF v_requested_status NOT IN ('draft', 'posted') THEN
    RAISE EXCEPTION 'Statut d''écriture inconnu : %', v_requested_status;
  END IF;

  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- AUD-C09 : sans journal précisé, l'écriture va en opérations diverses (même règle
  -- que la reprise des écritures historiques sans journal)
  v_journal_code := COALESCE(NULLIF(btrim(p_entry ->> 'journal_code'), ''), 'OD');

  -- Numérotation atomique si pas de numéro fourni
  IF p_entry ->> 'number' IS NULL OR p_entry ->> 'number' = '' THEN
    v_number := get_next_piece_number(v_journal_code);
  ELSE
    v_number := p_entry ->> 'number';
  END IF;

  -- 1. Insérer l'entête
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref, piece_number
  ) VALUES (
    v_tid,
    v_number,
    (p_entry ->> 'date')::date,
    v_journal_code,
    'draft',  -- AUD-C10 : toujours en brouillard ; validation après les lignes
    p_entry ->> 'description',
    p_entry ->> 'invoice_ref',
    v_number
  )
  RETURNING id INTO v_entry_id;

  -- 2. Insérer toutes les lignes en un seul INSERT (le trigger statement-level
  --    check_journal_entry_balance_ins se déclenche une seule fois après
  --    l'insertion de toutes les lignes, ce qui permet la vérification
  --    d'équilibre sur l'écriture complète).
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_name, account_general,
    account_tiers, third_party_id, debit, credit, description, line_order,
    lettrage_code, lettrage_date, piece_number, reference,
    analytic_section_id, analytic_amount, analytic_distribution,
    line_date, vat_code, vat_amount, echeance_date, quantity,
    marking_code, tax_tag_ids, product_id, product_uom
  )
  SELECT
    v_tid,
    v_entry_id,
    l ->> 'account_code',
    l ->> 'account_name',
    l ->> 'account_general',
    l ->> 'account_tiers',
    NULLIF(l ->> 'third_party_id', '')::uuid,
    COALESCE((l ->> 'debit')::numeric, 0),
    COALESCE((l ->> 'credit')::numeric, 0),
    l ->> 'description',
    COALESCE((l ->> 'line_order')::integer, 0),
    l ->> 'lettrage_code',
    NULLIF(l ->> 'lettrage_date', '')::date,
    COALESCE(l ->> 'piece_number', v_number),
    l ->> 'reference',
    NULLIF(l ->> 'analytic_section_id', '')::uuid,
    NULLIF(l ->> 'analytic_amount', '')::numeric,
    l -> 'analytic_distribution',
    COALESCE(NULLIF(l ->> 'line_date', '')::date, (p_entry ->> 'date')::date),
    l ->> 'vat_code',
    COALESCE((l ->> 'vat_amount')::numeric, 0),
    NULLIF(l ->> 'echeance_date', '')::date,
    NULLIF(l ->> 'quantity', '')::numeric,
    l ->> 'marking_code',
    CASE WHEN l ? 'tax_tag_ids' THEN
      ARRAY(SELECT jsonb_array_elements_text(l -> 'tax_tag_ids'))
    ELSE '{}'::text[] END,
    NULLIF(l ->> 'product_id', '')::uuid,
    l ->> 'product_uom'
  FROM jsonb_array_elements(p_lines) AS t(l);

  -- ACC-02: Valider qu'au moins une ligne non-nulle existe
  IF jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Écriture vide: aucune ligne fournie';
  END IF;

  -- AUD-C10 : validation demandée → bascule APRÈS l'insertion des lignes. Les
  -- triggers de validation (équilibre, période, permission) s'appliquent ici ;
  -- s'ils refusent, toute l'écriture est annulée et son numéro rendu.
  IF v_requested_status = 'posted' THEN
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;
  END IF;

  -- Le trigger check_journal_entry_balance vérifie l'équilibre automatiquement

  RETURN jsonb_build_object('success', true, 'entry_id', v_entry_id, 'number', v_number);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;
