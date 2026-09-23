-- ============================================================
-- 220_payroll_permission.sql — R-17 : les RPC de paie vérifient le rôle
--
-- Constat (plan, R-17) : `post_payroll_journal` et la RPC de versement ne
-- vérifiaient que la société, pas le rôle. Le contrôle générique de la
-- validation d'écriture (`enforce_journal_entry_permissions`, 154) couvre déjà
-- le POST, mais la garde arrive au moment d'écrire — après tout le travail de
-- construction — et ne dit rien du droit métier. Ici la porte elle-même est
-- gardée, avec un message explicite.
--
-- Portée volontairement étroite, comme le demandait R-17 :
--   * `payroll.post` sur `post_payroll_journal` (le bouton « Générer l'écriture
--     de paie ») ;
--   * `payroll.pay` sur `post_payroll_payment` (le versement).
-- La généralisation à toute l'application est H08, qui dépend de D-6 et n'est
-- pas tranchée : ce n'est pas la même décision, et elle n'est pas prise ici.
--
-- Ce qui n'est PAS gardé, et pourquoi :
--   * `payroll_post_run` — appelée en interne par le passage à « payé »
--     (`create_journal_on_payroll_validate`, 191) et par le versement (212).
--     Y mettre la garde casserait des flux légitimes.
--   * `get_bank_reconciliation_state` — c'est une LECTURE STABLE ; un contrôle
--     de rôle y est sans objet. Ses manques sont R-07/R-09, pas R-17.
--   * `convert_quote_to_invoice` — crée une facture en BROUILLON, ne valide
--     rien. Aucune clé commerciale n'existe dans `has_permission` : l'ajouter
--     bloquerait tout le monde sauf l'administrateur. Dépendance de H08/D-6.
--
-- Le socle du rôle `accountant` gagne donc `payroll.post` et `payroll.pay` :
-- c'est son métier, et sans cela la garde bloquerait le comptable — le défaut
-- exact que la 165 avait corrigé pour la validation des écritures.
--
-- Preuve : sql/220_payroll_permission_tests.sql, vu rouge avant.
-- ============================================================

CREATE OR REPLACE FUNCTION has_permission(p_permission text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM tenant_users tu
    WHERE tu.tenant_id = current_tenant_id()
      AND tu.auth_id = auth.uid()
      AND tu.status = 'active'
      AND (
        tu.role = 'admin'
        OR EXISTS (
          SELECT 1 FROM role_permissions rp
          WHERE rp.tenant_id = tu.tenant_id
            AND rp.role_id = tu.custom_role_id
            AND rp.permission = p_permission
        )
        -- 220 : socle du comptable — validation des écritures (165) et paie
        OR (tu.role = 'accountant' AND p_permission IN (
              'journal_entry.post', 'journal_entry.create', 'journal_entry.update',
              'payroll.post', 'payroll.pay'))
      )
  );
$$;

COMMENT ON FUNCTION has_permission(text) IS
  'Permission au format objet.action pour l''utilisateur courant. Admin, rôle '
  'personnalisé, ou socle du rôle métier (165, complété par la 220 : payroll.post '
  'et payroll.pay pour le comptable).';

-- ------------------------------------------------------------
-- 1. Bouton « Générer l'écriture de paie » — payroll.post
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION post_payroll_journal(p_pay_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- R-17 : la porte d'entrée, avant tout travail
  IF NOT has_permission('payroll.post') THEN
    RAISE EXCEPTION 'Permission refusée : payroll.post' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF current_tenant_id() IS NULL OR NOT EXISTS (
       SELECT 1 FROM pay_runs WHERE id = p_pay_run_id AND tenant_id = current_tenant_id()) THEN
    RAISE EXCEPTION 'Lot de paie introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN payroll_post_run(p_pay_run_id);
END $$;
REVOKE ALL ON FUNCTION post_payroll_journal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION post_payroll_journal(uuid) TO authenticated;

COMMENT ON FUNCTION post_payroll_journal(uuid) IS
  'Génère l''écriture de paie du lot. Exige payroll.post (R-17, 220) et délègue à '
  'payroll_post_run, qui reste l''unique auteur de l''écriture.';

-- ------------------------------------------------------------
-- 2. Versement de la paie — payroll.pay
--
-- Le corps du versement n'est pas recopié : il est renommé, puis enveloppé dans
-- une garde. Recopier 300 lignes aurait fait diverger deux versions de la même
-- fonction à la première correction. L'ancien nom est révoqué à tous les rôles
-- de l'application : sans cela, il resterait exposé par PostgREST et la garde
-- serait contournable en l'appelant directement.
-- ------------------------------------------------------------
ALTER FUNCTION public.post_payroll_payment(uuid, uuid, date, text)
  RENAME TO payroll_payment_inner;

REVOKE ALL ON FUNCTION public.payroll_payment_inner(uuid, uuid, date, text) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.payroll_payment_inner(uuid, uuid, date, text) IS
  'Corps du versement de paie (nets, organismes, impôt, acomptes). Non exposée : '
  'appeler post_payroll_payment, qui garde le droit payroll.pay (R-17, 220).';

CREATE OR REPLACE FUNCTION post_payroll_payment(
  p_pay_run_id uuid,
  p_bank_account_id uuid DEFAULT NULL,
  p_date date DEFAULT NULL,
  p_scope text DEFAULT 'all')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- R-17 : la porte d'entrée, avant tout travail
  IF NOT has_permission('payroll.pay') THEN
    RAISE EXCEPTION 'Permission refusée : payroll.pay' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN payroll_payment_inner(p_pay_run_id, p_bank_account_id, p_date, p_scope);
END $$;
REVOKE ALL ON FUNCTION post_payroll_payment(uuid, uuid, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION post_payroll_payment(uuid, uuid, date, text) TO authenticated;

COMMENT ON FUNCTION post_payroll_payment(uuid, uuid, date, text) IS
  'Verse la paie du lot (net par salarié, organismes, impôt, acomptes). Exige '
  'payroll.pay (R-17, 220).';