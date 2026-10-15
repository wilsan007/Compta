-- ═══════════════════════════════════════════════════════════════════════════
-- 384 — resolve_account : LE point d'appel unique du code vers un compte
--       (LOT 1-B, LOC1-05)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. La fin des numéros de comptes en dur. Le code ne dit plus
-- `'411000'` : il dit `resolve_account(tenant, 'CLIENTS')`. La fonction résout,
-- dans CET ordre :
--   1. la surcharge au niveau de l'OBJET métier (un client a son collectif, une
--      catégorie de produit a son compte de vente…) ;
--   2. la surcharge de la SOCIÉTÉ (`tenant_account_roles`) ;
--   3. le rôle du PACK effectif, par la lignée (`pack_account_roles`, le plus
--      spécifique gagne) ;
--   4. sinon, ÉCHEC EXPLICITE `ROLE_NON_MAPPE` — jamais de repli silencieux ;
--   5. et le compte DOIT exister dans le plan de la société (`COMPTE_ABSENT`).
-- Cahier §5, tâche LOC1-05.
--
-- ⚠️ SECURITY **INVOKER**, pas DEFINER — même motif que `tenant_pack_code` (382) :
-- `tenant_account_roles` et `chart_accounts` sont en RLS de société, donc un
-- appelant ne peut résoudre QUE pour sa propre société. En DEFINER, la porte
-- `ci/check_tenant_guard.sql` refuserait une fonction prenant un uuid société
-- sans vérifier l'appartenance (mesuré sur `tenant_pack_code`).
--
-- REJOUABLE : `CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP POLICY
-- IF EXISTS` + `CREATE`.
--
-- Numéro pris le 2026-10-05T20:25:53.158Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Surcharge PAR SOCIÉTÉ des rôles
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tenant_account_roles (
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  role         text NOT NULL REFERENCES account_role_catalog(role),
  account_code text NOT NULL,
  PRIMARY KEY (tenant_id, role)
);

CREATE TABLE IF NOT EXISTS tenant_journal_roles (
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  role         text NOT NULL REFERENCES journal_role_catalog(role),
  journal_code text NOT NULL,
  PRIMARY KEY (tenant_id, role)
);

ALTER TABLE tenant_account_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_account_roles_all ON tenant_account_roles;
CREATE POLICY tenant_account_roles_all ON tenant_account_roles FOR ALL
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

ALTER TABLE tenant_journal_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_journal_roles_all ON tenant_journal_roles;
CREATE POLICY tenant_journal_roles_all ON tenant_journal_roles FOR ALL
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

-- ─────────────────────────────────────────────────────────────
-- 2. La surcharge par OBJET métier (étape 1 de la résolution)
--    Chaque rôle lit SA colonne de contexte ; un rôle sans contexte rend NULL.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION resolve_account_from_context(p_tenant_id uuid, p_role text, p_context jsonb)
RETURNS text
LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE v text; v_id uuid;
BEGIN
  CASE p_role
    WHEN 'CLIENTS' THEN
      v_id := NULLIF(p_context->>'customer_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(account_collectif), '') INTO v FROM customers
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    WHEN 'FOURNISSEURS' THEN
      v_id := NULLIF(p_context->>'supplier_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(account_collectif), '') INTO v FROM suppliers
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    WHEN 'VENTES_MARCHANDISES', 'VENTES_PRODUITS_FINIS', 'PRESTATIONS_SERVICES' THEN
      v_id := NULLIF(p_context->>'product_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(sale_account_code), '') INTO v FROM products
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
      IF v IS NULL THEN
        v_id := NULLIF(p_context->>'category_id', '')::uuid;
        IF v_id IS NOT NULL THEN
          SELECT NULLIF(btrim(sale_account_code), '') INTO v FROM product_categories
           WHERE id = v_id AND tenant_id = p_tenant_id;
        END IF;
      END IF;
    WHEN 'ACHATS_MARCHANDISES', 'ACHATS_MATIERES', 'SERVICES_EXTERIEURS' THEN
      v_id := NULLIF(p_context->>'product_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(purchase_account_code), '') INTO v FROM products
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
      IF v IS NULL THEN
        v_id := NULLIF(p_context->>'category_id', '')::uuid;
        IF v_id IS NOT NULL THEN
          SELECT NULLIF(btrim(purchase_account_code), '') INTO v FROM product_categories
           WHERE id = v_id AND tenant_id = p_tenant_id;
        END IF;
      END IF;
    WHEN 'STOCK_MARCHANDISES', 'STOCK_MATIERES', 'STOCK_PRODUITS_FINIS' THEN
      v_id := NULLIF(p_context->>'category_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(stock_account_code), '') INTO v FROM product_categories
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    WHEN 'VARIATION_STOCK_MARCHANDISES', 'VARIATION_STOCK_MATIERES' THEN
      v_id := NULLIF(p_context->>'category_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(variation_account_code), '') INTO v FROM product_categories
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    WHEN 'BANQUE' THEN
      v_id := NULLIF(p_context->>'bank_account_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(account_code), '') INTO v FROM bank_accounts
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    WHEN 'TVA_COLLECTEE' THEN
      v_id := NULLIF(p_context->>'vat_rate_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(account_collectee), '') INTO v FROM tax_rates
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    WHEN 'TVA_DEDUCTIBLE_BIENS_SERVICES', 'TVA_DEDUCTIBLE_IMMOBILISATIONS' THEN
      v_id := NULLIF(p_context->>'vat_rate_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(account_deductible), '') INTO v FROM tax_rates
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    WHEN 'IMMOBILISATIONS' THEN
      v_id := NULLIF(p_context->>'asset_family_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(default_account), '') INTO v FROM asset_families
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    WHEN 'AMORTISSEMENTS' THEN
      v_id := NULLIF(p_context->>'asset_family_id', '')::uuid;
      IF v_id IS NOT NULL THEN
        SELECT NULLIF(btrim(default_depreciation_account), '') INTO v FROM asset_families
         WHERE id = v_id AND tenant_id = p_tenant_id;
      END IF;
    ELSE
      v := NULL;  -- aucun contexte métier pour ce rôle
  END CASE;
  RETURN v;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 3. resolve_account — la résolution en quatre étapes
--    (défini en INVOKER : c'est la RLS de la société qui fait la garde)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION resolve_account(p_tenant_id uuid, p_role text, p_context jsonb DEFAULT '{}'::jsonb)
RETURNS text
LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE v text;
BEGIN
  -- 1. surcharge objet métier
  v := resolve_account_from_context(p_tenant_id, p_role, p_context);

  -- 2. surcharge société
  IF v IS NULL THEN
    SELECT account_code INTO v FROM tenant_account_roles
     WHERE tenant_id = p_tenant_id AND role = p_role;
  END IF;

  -- 3. rôle du pack effectif (le plus spécifique gagne)
  IF v IS NULL THEN
    SELECT par.account_code INTO v
      FROM pack_lineage(tenant_pack_code(p_tenant_id)) l
      JOIN pack_account_roles par ON par.pack_code = l.code AND par.role = p_role
     ORDER BY l.depth LIMIT 1;
  END IF;

  -- 4. échec explicite — jamais de repli silencieux
  IF v IS NULL THEN
    RAISE EXCEPTION 'ROLE_NON_MAPPE: le rôle % n''a aucun compte pour la société %', p_role, p_tenant_id
      USING ERRCODE = 'P0001', HINT = 'Paramétrage > Comptes par défaut';
  END IF;

  -- 5. le compte doit exister dans le plan de la société
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id AND code = v) THEN
    RAISE EXCEPTION 'COMPTE_ABSENT: le rôle % pointe vers % absent du plan', p_role, v
      USING ERRCODE = 'P0001';
  END IF;

  RETURN v;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 4. resolve_journal — même schéma, sur les journaux
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION resolve_journal(p_tenant_id uuid, p_role text)
RETURNS text
LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE v text;
BEGIN
  SELECT journal_code INTO v FROM tenant_journal_roles
   WHERE tenant_id = p_tenant_id AND role = p_role;

  IF v IS NULL THEN
    SELECT pjr.journal_code INTO v
      FROM pack_lineage(tenant_pack_code(p_tenant_id)) l
      JOIN pack_journal_roles pjr ON pjr.pack_code = l.code AND pjr.role = p_role
     ORDER BY l.depth LIMIT 1;
  END IF;

  IF v IS NULL THEN
    RAISE EXCEPTION 'ROLE_JOURNAL_NON_MAPPE: %', p_role USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM journals WHERE tenant_id = p_tenant_id AND code = v) THEN
    RAISE EXCEPTION 'JOURNAL_ABSENT: le rôle % pointe vers % absent', p_role, v USING ERRCODE = 'P0001';
  END IF;

  RETURN v;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 5. Droits : appelées par le front et par les triggers d'écriture
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION resolve_account(uuid, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION resolve_journal(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION resolve_account_from_context(uuid, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION resolve_account(uuid, text, jsonb), resolve_journal(uuid, text)
  TO authenticated, service_role;
