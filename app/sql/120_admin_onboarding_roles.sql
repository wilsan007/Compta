-- ============================================================
-- 120_admin_onboarding_roles.sql
-- ADM-01 : Assistant de paramétrage + ADM-02 : Rôles et permissions RLS
-- ============================================================

-- ============================================================
-- ADM-01 : État d'avancement du paramétrage
-- ============================================================
CREATE TABLE IF NOT EXISTS tenant_onboarding_state (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL UNIQUE,
  step_identity boolean DEFAULT false,
  step_legislation boolean DEFAULT false,
  step_fiscal_year boolean DEFAULT false,
  step_chart_accounts boolean DEFAULT false,
  step_journals boolean DEFAULT false,
  step_default_accounts boolean DEFAULT false,
  step_vat_rates boolean DEFAULT false,
  step_payment_methods boolean DEFAULT false,
  step_stock_valuation boolean DEFAULT false,
  step_users boolean DEFAULT false,
  completed boolean DEFAULT false,
  completed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE tenant_onboarding_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_onboarding_tenant ON tenant_onboarding_state
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- ADM-01 : Vérifier si le paramétrage minimal est complet
-- ============================================================
CREATE OR REPLACE FUNCTION is_onboarding_complete()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT completed FROM tenant_onboarding_state WHERE tenant_id = current_tenant_id()),
    false
  )
$$;

-- ============================================================
-- ADM-02 : Rôles personnalisables
-- ============================================================
CREATE TABLE IF NOT EXISTS tenant_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  is_system boolean DEFAULT false,  -- true pour les rôles livrés par défaut
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, name)
);

ALTER TABLE tenant_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_roles_tenant ON tenant_roles
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- ADM-02 : Permissions au format objet.action
-- ============================================================
CREATE TABLE IF NOT EXISTS role_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  role_id uuid NOT NULL REFERENCES tenant_roles(id) ON DELETE CASCADE,
  permission text NOT NULL,  -- ex: 'invoice.create', 'journal_entry.post'
  created_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, role_id, permission)
);

ALTER TABLE role_permissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY role_permissions_tenant ON role_permissions
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- ADM-02 : Lier tenant_users aux rôles personnalisés
-- ============================================================
ALTER TABLE tenant_users ADD COLUMN IF NOT EXISTS custom_role_id uuid REFERENCES tenant_roles(id);

-- ============================================================
-- ADM-02 : Rôles par défaut (sera créé par l'application pour chaque tenant)
-- Désactivé ici car current_tenant_id() retourne NULL sans contexte de session

-- ============================================================
-- ADM-02 : Vérifier une permission pour l'utilisateur courant
-- ============================================================
CREATE OR REPLACE FUNCTION has_permission(p_permission text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM tenant_users tu
    LEFT JOIN role_permissions rp ON rp.tenant_id = tu.tenant_id
      AND (rp.role_id = tu.custom_role_id OR tu.custom_role_id IS NULL)
    WHERE tu.tenant_id = current_tenant_id()
      AND tu.auth_id = auth.uid()
      AND (
        -- Admin a toutes les permissions
        tu.role = 'admin' OR
        -- Permission explicite
        rp.permission = p_permission
      )
  );
$$;

-- ============================================================
-- ADM-02 : Séparation des tâches
-- La personne qui saisit ne peut pas valider
-- ============================================================
CREATE OR REPLACE FUNCTION check_segregation_of_duties(
  p_user_id uuid,
  p_action text,
  p_reference_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_created_by uuid;
  v_tid uuid := current_tenant_id();
BEGIN
  -- Si l'action est 'validate', vérifier que l'utilisateur n'est pas celui qui a créé
  IF p_action = 'validate' THEN
    SELECT created_by INTO v_created_by
    FROM journal_entries
    WHERE id = p_reference_id AND tenant_id = v_tid;

    IF v_created_by = p_user_id THEN
      RETURN false;  -- Séparation des tâches violée
    END IF;
  END IF;

  RETURN true;
END;
$$;

-- ============================================================
-- ADM-02 : RLS sur journal_entries — bloquer la validation
-- si l'utilisateur n'a pas la permission
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_journal_entry_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  -- Si on tente de poster une écriture, vérifier la permission
  IF NEW.status = 'posted' AND (OLD.status IS NULL OR OLD.status <> 'posted') THEN
    IF NOT has_permission('journal_entry.post') THEN
      RAISE EXCEPTION 'Permission refusée : journal_entry.post';
    END IF;

    -- Séparation des tâches : le créateur ne peut pas valider
    IF NOT check_segregation_of_duties(auth.uid(), 'validate', NEW.id) THEN
      RAISE EXCEPTION 'Séparation des tâches : vous ne pouvez pas valider une écriture que vous avez saisie';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_journal_permissions ON journal_entries;
CREATE TRIGGER enforce_journal_permissions
  BEFORE UPDATE ON journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION enforce_journal_entry_permissions();
