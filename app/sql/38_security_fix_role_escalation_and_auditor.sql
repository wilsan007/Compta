-- ============================================
-- SECURITY FIX: Prevent self-role-escalation + add auditor role
-- ============================================
-- This script:
-- 1. Adds a trigger to prevent non-admins from changing their own role/permissions/status
-- 2. Adds the 'auditor' role to can_perform() SQL function
-- 3. Adds a constraint to allow 'auditor' in tenant_users.role
-- ============================================

-- ============================================
-- 1. PREVENT SELF-ROLE-ESCALATION
-- ============================================
-- The existing RLS UPDATE policy on tenant_users allows
-- auth_id = auth.uid() (self-update). This trigger blocks
-- non-admin users from changing role, permissions, or status
-- on their own row.

CREATE OR REPLACE FUNCTION prevent_role_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- If the updater is updating their own row and is NOT an admin
  IF auth.uid() = NEW.auth_id AND current_user_role() != 'admin' THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'SECURITY: Cannot change own role';
    END IF;
    IF NEW.permissions IS DISTINCT FROM OLD.permissions THEN
      RAISE EXCEPTION 'SECURITY: Cannot change own permissions';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'SECURITY: Cannot change own status';
    END IF;
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
      RAISE EXCEPTION 'SECURITY: Cannot change own tenant_id';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_role_escalation ON tenant_users;
CREATE TRIGGER prevent_role_escalation
  BEFORE UPDATE ON tenant_users
  FOR EACH ROW EXECUTE FUNCTION prevent_role_escalation();

-- ============================================
-- 2. ADD AUDITOR ROLE TO can_perform()
-- ============================================
-- The client-side canPerform() already handles 'auditor' (select-only)
-- but the SQL function was missing it, causing RLS to block all
-- auditor queries.

CREATE OR REPLACE FUNCTION can_perform(p_table text, p_action text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT CASE
    WHEN current_user_role() = 'admin' THEN true
    WHEN current_user_role() = 'accountant' AND p_action IN ('select', 'insert', 'update') THEN true
    WHEN current_user_role() = 'accountant' AND p_action = 'delete' AND p_table IN ('journal_entries', 'journal_lines', 'invoice_lines', 'quote_lines', 'credit_note_lines') THEN true
    WHEN current_user_role() = 'manager' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'manager' AND p_action IN ('insert', 'update') AND p_table IN ('invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines') THEN true
    WHEN current_user_role() = 'viewer' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'auditor' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'custom' THEN
      COALESCE(
        (current_user_permissions() -> p_table ->> p_action)::boolean,
        false
      )
    ELSE false
  END
$$;

-- ============================================
-- 3. UPDATE CONSTRAINT TO ALLOW 'auditor' ROLE
-- ============================================
-- The existing CHECK constraint on tenant_users.role may not
-- include 'auditor'. We need to drop and recreate it.

DO $$
BEGIN
  -- Drop the old constraint if it exists
  EXECUTE 'ALTER TABLE tenant_users DROP CONSTRAINT IF EXISTS tenant_users_role_check';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not drop role constraint: %', SQLERRM;
END $$;

DO $$
BEGIN
  -- Add the new constraint with 'auditor' included
  EXECUTE 'ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_role_check CHECK (role IN (''admin'', ''accountant'', ''manager'', ''viewer'', ''auditor'', ''custom''))';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not add role constraint: %', SQLERRM;
END $$;

-- ============================================
-- DONE
-- ============================================
-- After running this script:
-- 1. Non-admin users can no longer escalate their own role/permissions/status
-- 2. The 'auditor' role is fully supported in SQL RLS policies
-- 3. The tenant_users table accepts 'auditor' as a valid role
-- ============================================
