-- ============================================================
-- 272_master_data_defaults.sql — vague X7 : données de base
-- Audit fonctionnel exécuté du 28/09/2026 : M2 (e-mail vide), M13 (devise, TVA)
--
-- M2. L'écran envoie `email: ''` quand le champ est laissé vide ; la contrainte
--     de format de `customers`, `suppliers`, `employees` et `company_settings`
--     n'accepte que NULL ou une adresse : un tiers sans e-mail était impossible à
--     créer. Le front normalise désormais (`blankEmailToNull`) ; la base aussi,
--     pour tous les autres chemins (API publique, imports). La contrainte n'est
--     PAS affaiblie : une adresse invalide reste refusée.
--
-- M13. (a) `invoices`, `credit_notes`, `purchase_invoices` avaient
--     `currency_code DEFAULT 'EUR'`, et l'écran n'envoie pas de devise : une
--     société en DJF facturait en EUR. Le défaut de colonne disparaît ; la devise
--     absente est celle de la société (paramètres, sinon société, sinon EUR).
--     (b) Une société neuve n'avait aucun taux de TVA : les taux de référence
--     sont rangés par pack sous la société technique `…0001`, et rien ne les
--     copiait. L'inscription les copie (pack de législation, sinon pays) ; les
--     sociétés existantes sans taux sont rattrapées ici.
--
-- LIMITE DITE. Le pack Djibouti (DJ) n'a pas de taux de référence : la décision
-- D-11 (taux et localisation) est ouverte. Une société DJ reste sans taux, comme
-- avant — ce n'est plus un oubli de l'inscription, c'est une donnée manquante.
--
-- Tests : 272_master_data_defaults_tests.sql (T01–T05, 4 rouges avant).
-- ============================================================

BEGIN;

-- ── M2 : '' → NULL ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION normalize_blank_email()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.email := NULLIF(btrim(NEW.email), '');
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION normalize_blank_email() FROM PUBLIC, anon;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['customers', 'suppliers', 'employees', 'company_settings'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'tg_' || t || '_blank_email', t);
    -- Le nom commence par « a_ » : les BEFORE s'exécutent par ordre alphabétique,
    -- et la normalisation doit précéder tout autre contrôle de la ligne.
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'a_' || t || '_blank_email', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF email ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION normalize_blank_email()', 'a_' || t || '_blank_email', t);
  END LOOP;
END $$;

-- ── M13 (a) : la devise d'un document est celle de la société ──
CREATE OR REPLACE FUNCTION default_document_currency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.currency_code IS NULL OR btrim(NEW.currency_code) = '' THEN
    SELECT COALESCE(
             (SELECT NULLIF(cs.currency, '') FROM company_settings cs WHERE cs.tenant_id = NEW.tenant_id LIMIT 1),
             (SELECT NULLIF(te.currency, '') FROM tenants te WHERE te.id = NEW.tenant_id),
             'EUR')
      INTO NEW.currency_code;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION default_document_currency() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['invoices', 'credit_notes', 'purchase_invoices'] LOOP
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN currency_code DROP DEFAULT', t);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'a_' || t || '_default_currency', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION default_document_currency()', 'a_' || t || '_default_currency', t);
  END LOOP;
END $$;

-- ── M13 (b) : les taux de TVA de la société ──────────────────
-- La clé posée par le générateur ISO-02 (237) était composite :
-- (tenant_id, pack_code) → legislation_packs(tenant_id, code). Or
-- `legislation_packs` est un RÉFÉRENTIEL (clé primaire `code`), rangé sous la
-- société technique `…0001` : aucune société réelle ne pouvait donc porter un
-- taux rattaché à son pack — ni en recevoir à l'inscription. La clé redevient
-- simple, sur le code du pack ; elle est inscrite, avec sa raison, au registre
-- de ci/check_composite_fks.sql.
ALTER TABLE tax_rates DROP CONSTRAINT IF EXISTS tax_rates_pack_code_fkey;
ALTER TABLE tax_rates ADD CONSTRAINT tax_rates_pack_code_fkey
  FOREIGN KEY (pack_code) REFERENCES legislation_packs(code) ON DELETE CASCADE;

-- Fonction interne (appelée par bootstrap_tenant et par le rattrapage) :
-- non exposée, comme le socle des diviseurs (256) — check_tenant_guard refuse
-- une fonction SECURITY DEFINER exposée qui prend une société en paramètre.
CREATE OR REPLACE FUNCTION seed_tenant_tax_rates(p_tenant_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_pack text; v_n int := 0;
BEGIN
  IF EXISTS (SELECT 1 FROM tax_rates WHERE tenant_id = p_tenant_id) THEN
    RETURN 0;   -- la société a déjà ses taux : on ne les double ni ne les écrase
  END IF;
  SELECT COALESCE(te.legislation_pack_code, te.country_code) INTO v_pack
  FROM tenants te WHERE te.id = p_tenant_id;
  IF v_pack IS NULL THEN RETURN 0; END IF;

  INSERT INTO tax_rates (tenant_id, pack_code, name, category, rate, account_code, is_default,
    effective_from, effective_to, account_collectee, account_deductible, type, mode, amount_type,
    type_tax_use, sequence, tax_exigibility, cash_basis_transition_account, price_include,
    include_base_amount, is_base_affected, analytic, fixed_amount)
  SELECT p_tenant_id, r.pack_code, r.name, r.category, r.rate, r.account_code, r.is_default,
    r.effective_from, r.effective_to, r.account_collectee, r.account_deductible, r.type, r.mode, r.amount_type,
    r.type_tax_use, r.sequence, r.tax_exigibility, r.cash_basis_transition_account, r.price_include,
    r.include_base_amount, r.is_base_affected, r.analytic, r.fixed_amount
  FROM tax_rates r
  WHERE r.tenant_id = '00000000-0000-0000-0000-000000000001' AND r.pack_code = v_pack
    AND r.parent_tax_id IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION seed_tenant_tax_rates(uuid) FROM PUBLIC, anon, authenticated;

-- L'inscription copie les taux : garde insérée dans bootstrap_tenant après les
-- journaux, par ancre exacte (même méthode que la 271 — la migration échoue si
-- le corps a changé).
DO $$
DECLARE
  v_ancre constant text := E'  PERFORM ensure_standard_journals(p_tenant_id);\n';
  v_def text; v_pos int;
BEGIN
  v_def := pg_get_functiondef('bootstrap_tenant'::regproc);
  IF position('seed_tenant_tax_rates' IN v_def) > 0 THEN RETURN; END IF;
  v_pos := position(v_ancre IN v_def);
  IF v_pos = 0 THEN
    RAISE EXCEPTION '[X7] ancre « ensure_standard_journals » introuvable dans bootstrap_tenant';
  END IF;
  v_def := overlay(v_def PLACING v_ancre ||
    E'  -- X7-272 (M13) : les taux de TVA du pack de la société\n  PERFORM seed_tenant_tax_rates(p_tenant_id);\n'
    FROM v_pos FOR length(v_ancre));
  EXECUTE v_def;
END $$;

-- Rattrapage des sociétés existantes
DO $$
DECLARE r record; v_total int := 0; v_n int;
BEGIN
  FOR r IN SELECT id FROM tenants WHERE id <> '00000000-0000-0000-0000-000000000001' LOOP
    v_n := seed_tenant_tax_rates(r.id);
    v_total := v_total + v_n;
  END LOOP;
  RAISE NOTICE '[X7/M13] % taux de TVA copiés vers les sociétés qui n''en avaient pas', v_total;
END $$;

COMMIT;
