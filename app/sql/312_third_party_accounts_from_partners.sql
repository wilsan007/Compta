-- ============================================================
-- 312_third_party_accounts_from_partners.sql — recette /qa du 29/09/2026
-- (lot A, A1 : ven-013 🔴 / cpt-005 🟡)
--
-- LES DÉFAUTS, mesurés à l'écran sur la base de recette :
--   ven-013 🔴  créer un client ou un fournisseur ne l'inscrit PAS au plan des
--               tiers : `third_party_accounts` reste vide (0 ligne pour 4 clients
--               et 4 fournisseurs). En cascade : le lettrage affiche « Aucun tiers
--               trouvé », le plan tiers « 0 compte(s) », la balance âgée retombe
--               sur le type « other » et son filtre « Clients » est vide
--               (ven-014), le FEC n'a pas de libellé de compte auxiliaire, et
--               **quatorze écrans** qui lisent `getThirdPartyAccounts` ne
--               proposent aucun tiers (saisie d'écriture, modèles, RIB, grand
--               livre des tiers, balance progressive…).
--   cpt-005 🟡  le même fait vu du plan comptable : « 0 compte(s) » au plan tiers.
--
-- CE QUI EXISTAIT DÉJÀ, ET POURQUOI CELA NE SUFFISAIT PAS : deux déclencheurs
-- (`generate_customer_account_tiers`, `generate_supplier_account_tiers`) calculent
-- bien un code auxiliaire CLI0000n / FOU0000n — mais ils l'écrivent SEULEMENT dans
-- `customers.account_tiers` / `suppliers.account_tiers`. Or le plan des tiers ne
-- lit QUE `third_party_accounts`. Le code existait donc, sans son compte.
--
-- LE CORRECTIF
--   1. Un déclencheur `AFTER INSERT OR UPDATE` sur `customers`, `suppliers`
--      (nom, code auxiliaire, compte collectif, encours autorisé, actif) et
--      `employees` (nom, matricule, statut) crée ou met à jour LE compte de tiers
--      correspondant : société, code = code auxiliaire, type, nom, compte
--      collectif, rattachement au partenaire. Un renommage, un changement de code
--      ou une désactivation se propagent — la ligne du plan suit son tiers.
--   2. Un rattrapage — `backfill_third_party_accounts(société)`, joué par la
--      migration pour chaque société existante — inscrit les tiers DÉJÀ créés.
--   3. Rien n'est ajouté en double : l'unicité `(tenant_id, code)` existe déjà et
--      implique l'unicité `(tenant_id, type, code)` demandée par le plan ; le
--      rattachement `(tenant_id, customer_id / supplier_id)` est déjà composite
--      (ISO-02, 237).
--
-- CE QUE CETTE MIGRATION NE FAIT PAS — et le dit :
--   * les conditions de paiement ne sont PAS recopiées : `customers.payment_terms`
--     porte du texte libre (« 30 jours »), pas une référence. L'inventer serait
--     inventer une donnée — c'est le lot A4 qui donne au formulaire une vraie
--     liste. Le champ reste tel quel.
--   * le rattrapage n'écrase AUCUN compte déjà présent (`ON CONFLICT DO NOTHING`) :
--     un compte saisi à la main garde la main.
--   * la suppression d'un tiers ne supprime pas son compte : le compte auxiliaire
--     porte l'histoire du grand livre (la clé étrangère est en `SET NULL`, la
--     ligne reste, sans rattachement).
--   * ce déclencheur donne au plan des tiers SES lignes ; il ne remplit pas les
--     soldes — c'est l'objet de la 313 (`customer_balances`, lu au grand livre).
--
-- Preuve : `312_third_party_accounts_from_partners_tests.sql` (T01 à T06, T01/T02
-- vus rouges avant).
-- ============================================================


-- ⚠️ UN DÉCLENCHEUR PAR TABLE, et non un déclencheur partagé — décision de la
-- 280, appliquée ici pour la même raison et avec le même argument.
--
-- La fonction initiale était PARTAGÉE par `customers`, `suppliers` et
-- `employees`, trois tables dont les colonnes diffèrent : elle nommait
-- `NEW.account_tiers` et `NEW.credit_limit` dans une branche,
-- `NEW.employee_number` et `NEW.status` dans une autre. Or `NEW` est un
-- `record` : `plpgsql_check` valide CHAQUE branche contre ce type, qui n'a
-- aucun de ces champs — 3 erreurs, mesurées le 02/10 (sur 7 avant le
-- cherry-pick de `865591a`).
--
-- Le correctif ne fait pas taire le contrôle : il rend le calcul VRAI de la
-- façon la plus simple à lire. Le comportement (extraction du code, du
-- collectif, de l'actif, puis rattachement) est factorisé dans une fonction
-- ordinaire `upsert_third_party_account(...)` qui ne connaît QUE ses
-- paramètres — aucun `record`, donc rien à mal typer. Les trois déclencheurs
-- ne font plus que lire LEURS colonnes et l'appeler.
--
-- Une fonction par table est donc le seul découpage où le contrôle statique a
-- quelque chose à dire : `upsert_third_party_account` n'est pas un déclencheur,
-- `plpgsql_check` ne le valide pas contre une table, et les erreurs ne peuvent
-- pas se reproduire à l'exécution.
CREATE OR REPLACE FUNCTION public.upsert_third_party_account(
  p_tenant_id uuid,
  p_type text,
  p_code text,
  p_name text,
  p_collectif text,
  p_credit numeric,
  p_active boolean,
  p_cust uuid,
  p_supp uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Sans code auxiliaire, il n'y a pas de compte à ouvrir : le déclencheur BEFORE
  -- (generate_*_account_tiers) le pose pour un client ou un fournisseur, un
  -- matricule manquant n'a pas d'équivalent. Rien ne s'invente.
  IF p_code IS NULL THEN
    RETURN;
  END IF;

  BEGIN
    -- Le rattachement se fait par le PARTENAIRE, pas par le code : un code qui
    -- change est un renommage du même compte, pas un compte nouveau.
    UPDATE third_party_accounts t
       SET code = p_code,
           name = p_name,
           account_general_code = p_collectif,
           credit_limit = p_credit,
           active = p_active,
           updated_at = now()
     WHERE t.tenant_id = p_tenant_id
       AND t.type = p_type
       AND ((p_cust IS NOT NULL AND t.customer_id = p_cust)
            OR (p_supp IS NOT NULL AND t.supplier_id = p_supp));

    IF NOT FOUND THEN
      INSERT INTO third_party_accounts
        (tenant_id, code, type, name, account_general_code, credit_limit, active,
         customer_id, supplier_id)
      VALUES
        (p_tenant_id, p_code, p_type, p_name, p_collectif, p_credit, p_active,
         p_cust, p_supp)
      ON CONFLICT (tenant_id, code) DO UPDATE
        SET name = EXCLUDED.name,
            account_general_code = EXCLUDED.account_general_code,
            credit_limit = EXCLUDED.credit_limit,
            active = EXCLUDED.active,
            updated_at = now();
    END IF;
  EXCEPTION WHEN unique_violation THEN
    -- Deux tiers ne partagent pas un compte auxiliaire : le dire en français,
    -- avec le code fautif, plutôt que laisser remonter un 23505 brut (F4).
    RAISE EXCEPTION 'Le code auxiliaire % est déjà porté par un autre tiers : deux tiers ne peuvent pas partager un compte.',
      p_code USING ERRCODE = 'unique_violation';
  END;
END $$;
REVOKE EXECUTE ON FUNCTION public.upsert_third_party_account(uuid, text, text, text, text, numeric, boolean, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Le déclencheur d'un client : il ne nomme que les colonnes de `customers`.
CREATE OR REPLACE FUNCTION public.sync_customer_third_party_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  PERFORM public.upsert_third_party_account(
    NEW.tenant_id,
    'customer',
    NULLIF(btrim(COALESCE(NEW.account_tiers, '')), ''),
    NEW.name,
    COALESCE(NULLIF(btrim(COALESCE(NEW.account_collectif, '')), ''), '411000'),
    COALESCE(NEW.credit_limit, 0),
    COALESCE(NEW.active, true),
    NEW.id,
    NULL);
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.sync_customer_third_party_account() FROM PUBLIC, anon, authenticated;

-- Le déclencheur d'un fournisseur : `suppliers` n'a pas de `credit_limit`.
CREATE OR REPLACE FUNCTION public.sync_supplier_third_party_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  PERFORM public.upsert_third_party_account(
    NEW.tenant_id,
    'supplier',
    NULLIF(btrim(COALESCE(NEW.account_tiers, '')), ''),
    NEW.name,
    COALESCE(NULLIF(btrim(COALESCE(NEW.account_collectif, '')), ''), '401000'),
    0,
    COALESCE(NEW.active, true),
    NULL,
    NEW.id);
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.sync_supplier_third_party_account() FROM PUBLIC, anon, authenticated;

-- Le déclencheur d'un salarié : ni `account_tiers` ni `credit_limit`, mais un
-- matricule et un statut.
CREATE OR REPLACE FUNCTION public.sync_employee_third_party_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  PERFORM public.upsert_third_party_account(
    NEW.tenant_id,
    'employee',
    NULLIF(btrim(COALESCE(NEW.employee_number, '')), ''),
    NEW.name,
    '421000',
    0,
    COALESCE(NEW.status, 'active') <> 'inactive',
    NULL,
    NULL);
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.sync_employee_third_party_account() FROM PUBLIC, anon, authenticated;

-- ── 2. Le rattrapage : les tiers créés AVANT ce déclencheur ─────────────────
-- Une fonction, pour deux raisons : la migration l'appelle société par société,
-- et un test peut la rejouer sur sa propre fixture (T04). Elle n'est pas exposée
-- aux rôles applicatifs : c'est un acte de maintenance, pas un droit d'écran.
CREATE OR REPLACE FUNCTION public.backfill_third_party_accounts(p_tenant_id uuid)
RETURNS int
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_n int := 0;
  v_step int := 0;
BEGIN
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Rattrapage des comptes de tiers : la société est obligatoire' USING ERRCODE = 'null_value_not_allowed';
  END IF;

  INSERT INTO third_party_accounts
    (tenant_id, code, type, name, account_general_code, credit_limit, active, customer_id)
  SELECT c.tenant_id, c.account_tiers, 'customer', c.name,
         COALESCE(NULLIF(btrim(COALESCE(c.account_collectif, '')), ''), '411000'),
         COALESCE(c.credit_limit, 0), COALESCE(c.active, true), c.id
  FROM customers c
  WHERE c.tenant_id = p_tenant_id
    AND NULLIF(btrim(COALESCE(c.account_tiers, '')), '') IS NOT NULL
  ORDER BY c.created_at, c.id
  ON CONFLICT (tenant_id, code) DO NOTHING;
  GET DIAGNOSTICS v_step = ROW_COUNT;
  v_n := v_n + v_step;

  INSERT INTO third_party_accounts
    (tenant_id, code, type, name, account_general_code, credit_limit, active, supplier_id)
  SELECT s.tenant_id, s.account_tiers, 'supplier', s.name,
         COALESCE(NULLIF(btrim(COALESCE(s.account_collectif, '')), ''), '401000'),
         0, COALESCE(s.active, true), s.id
  FROM suppliers s
  WHERE s.tenant_id = p_tenant_id
    AND NULLIF(btrim(COALESCE(s.account_tiers, '')), '') IS NOT NULL
  ORDER BY s.created_at, s.id
  ON CONFLICT (tenant_id, code) DO NOTHING;
  GET DIAGNOSTICS v_step = ROW_COUNT;
  v_n := v_n + v_step;

  -- Les salariés : le grand livre de la paie porte le matricule comme compte
  -- auxiliaire du 421 (mesuré : `421000 / M430080`), donc un salarié sans compte
  -- de tiers est un libellé manquant dans le FEC et dans le lettrage.
  INSERT INTO third_party_accounts
    (tenant_id, code, type, name, account_general_code, credit_limit, active)
  SELECT e.tenant_id, e.employee_number, 'employee', e.name, '421000',
         0, COALESCE(e.status, 'active') <> 'inactive'
  FROM employees e
  WHERE e.tenant_id = p_tenant_id
    AND NULLIF(btrim(COALESCE(e.employee_number, '')), '') IS NOT NULL
  ORDER BY e.created_at, e.id
  ON CONFLICT (tenant_id, code) DO NOTHING;
  GET DIAGNOSTICS v_step = ROW_COUNT;
  v_n := v_n + v_step;

  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.backfill_third_party_accounts(uuid) FROM PUBLIC, anon, authenticated;

-- ── 3. Les déclencheurs ────────────────────────────────────────────────────
-- Un déclencheur par table, chacun attaché à SA fonction : c'est ce qui
-- permet à `plpgsql_check` de valider chaque corps contre les colonnes qui
-- existent vraiment dans la table concernée.
DROP TRIGGER IF EXISTS sync_third_party_partner ON public.customers;
CREATE TRIGGER sync_third_party_partner
  AFTER INSERT OR UPDATE OF name, account_tiers, account_collectif, credit_limit, active
  ON public.customers
  FOR EACH ROW EXECUTE FUNCTION public.sync_customer_third_party_account();

DROP TRIGGER IF EXISTS sync_third_party_partner ON public.suppliers;
CREATE TRIGGER sync_third_party_partner
  AFTER INSERT OR UPDATE OF name, account_tiers, account_collectif, active
  ON public.suppliers
  FOR EACH ROW EXECUTE FUNCTION public.sync_supplier_third_party_account();

DROP TRIGGER IF EXISTS sync_third_party_partner ON public.employees;
CREATE TRIGGER sync_third_party_partner
  AFTER INSERT OR UPDATE OF name, employee_number, status
  ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.sync_employee_third_party_account();

-- L'ancien déclencheur partagé n'est plus appelé par personne : il est
-- supprimé, comme le prescribe la 280 pour le même cas.
DROP FUNCTION IF EXISTS public.sync_partner_third_party_account();

-- ── 4. Le rattrapage des sociétés existantes ───────────────────────────────
DO $$
DECLARE r record; v_total int := 0; v_n int;
BEGIN
  FOR r IN SELECT id FROM tenants ORDER BY created_at, id LOOP
    v_n := backfill_third_party_accounts(r.id);
    v_total := v_total + v_n;
  END LOOP;
  RAISE NOTICE '[A1/312] % compte(s) de tiers rattrapé(s) sur les sociétés existantes', v_total;
END $$;

