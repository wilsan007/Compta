-- ============================================================
-- 228_function_grants_tests.sql — H09 : ce qu'un visiteur non connecté appelle
--
-- Mesuré AVANT la 228, sur base neuve (202 migrations) : 332 des 389 fonctions
-- de `public` exécutables par `anon`, dont 75 des 96 RPC de l'écran. T01 à T03
-- ont été vus VERTS sous le rôle anon avant correctif — c'est-à-dire que trois
-- fonctions SECURITY DEFINER qui écrivent s'exécutaient sans aucun jeton.
--
-- T04 et T05 sont les non-régressions qui empêchent la révocation d'être trop
-- large : la page d'inscription lit des tables de référence dont les politiques
-- RLS appellent current_tenant_id(), et l'utilisateur connecté garde ses RPC.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '228', false);
DELETE FROM _audit_results WHERE file = '228';

-- T01 : un visiteur non connecté ne révoque pas les auditeurs expirés
DO $$
DECLARE refuse boolean := false; err text := '—';
BEGIN
  PERFORM set_config('role', 'anon', true);
  BEGIN
    PERFORM auto_revoke_expired_auditors();
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T01', 'anon : révocation des auditeurs expirés refusée', refuse, format('refus=%s | %s', refuse, left(err, 90)));
END $$;

-- T02 : un visiteur non connecté ne crée pas de tâches récurrentes
DO $$
DECLARE refuse boolean := false; err text := '—';
BEGIN
  PERFORM set_config('role', 'anon', true);
  BEGIN
    PERFORM generate_recurring_tasks();
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T02', 'anon : génération des tâches récurrentes refusée', refuse, format('refus=%s | %s', refuse, left(err, 90)));
END $$;

-- T03 : un visiteur non connecté ne purge pas la table d'idempotence
DO $$
DECLARE refuse boolean := false; err text := '—';
BEGIN
  PERFORM set_config('role', 'anon', true);
  BEGIN
    PERFORM cleanup_expired_idempotency();
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T03', 'anon : purge de l''idempotence refusée', refuse, format('refus=%s | %s', refuse, left(err, 90)));
END $$;

-- T04 : non-régression — la page d'inscription lit toujours ses référentiels
--       (leurs politiques RLS appellent current_tenant_id()) et la liste des pays
DO $$
DECLARE n_cur int; n_banks int; n_pays int; err text := '—'; ok boolean := false;
BEGIN
  PERFORM set_config('role', 'anon', true);
  BEGIN
    SELECT count(*) INTO n_cur FROM currencies;
    SELECT count(*) INTO n_banks FROM banks;
    SELECT count(*) INTO n_pays FROM available_signup_countries();
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T04', 'anon : devises, banques et pays d''inscription toujours lisibles',
    ok AND n_cur > 0 AND n_banks > 0 AND n_pays > 0,
    format('devises=%s banques=%s pays=%s | %s', n_cur, n_banks, n_pays, left(err, 90)));
END $$;

-- T05 : non-régression — l'utilisateur connecté garde ses RPC
--       (échantillon de fonctions appelées par l'écran, toutes familles)
DO $$
DECLARE v_manquantes text;
BEGIN
  SELECT string_agg(f, ', ' ORDER BY f) INTO v_manquantes
  FROM unnest(ARRAY[
    'create_invoice_atomic', 'post_journal_entry', 'calculate_payslip', 'post_payroll_journal',
    'close_fiscal_year', 'allocate_result', 'convert_quote_to_invoice', 'get_bank_reconciliation_state',
    'create_tenant_for_current_user', 'available_signup_countries'
  ]) AS f
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    WHERE p.proname = f AND has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  PERFORM _rec('T05', 'authenticated : les RPC de l''écran restent exécutables',
    v_manquantes IS NULL, format('sans droit=%s', COALESCE(v_manquantes, 'aucune')));
END $$;

-- T06 : plus aucune fonction n'est exposée à PUBLIC (le droit par défaut de CREATE FUNCTION)
DO $$
DECLARE n int; noms text;
BEGIN
  SELECT count(*), string_agg(p.proname, ', ' ORDER BY p.proname) INTO n, noms
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace AND ns.nspname = 'public'
  WHERE p.proname NOT LIKE '\_%'   -- outillage des suites de test, absent de la production
    AND (p.proacl IS NULL            -- NULL = droit par défaut = EXECUTE à PUBLIC
         OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                    WHERE (a).privilege_type = 'EXECUTE' AND (a).grantee = 0));
  PERFORM _rec('T06', 'aucune fonction de public n''est exécutable par PUBLIC',
    n = 0, format('exposées=%s : %s', n, left(COALESCE(noms, '—'), 120)));
END $$;

-- T07 : le droit PUBLIC revient sur toute fonction créée ensuite — et c'est le
--       contrôle CI qui l'attrape, pas les privilèges par défaut.
--       Mesuré : `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM
--       PUBLIC` ne retire pas le droit PUBLIC de CREATE FUNCTION (proacl reste
--       NULL, donc EXECUTE à PUBLIC). Ce scénario fige les deux faits : la
--       fonction neuve EST exposée, et le prédicat de ci/check_anon_grants.sql
--       la signale.
DO $$
DECLARE v_expose boolean; v_signalee boolean; v_auth boolean;
BEGIN
  EXECUTE 'CREATE OR REPLACE FUNCTION public.h09_derive_temoin() RETURNS int LANGUAGE sql AS $f$ SELECT 1 $f$';
  SELECT has_function_privilege('anon', p.oid, 'EXECUTE'),
         has_function_privilege('authenticated', p.oid, 'EXECUTE')
    INTO v_expose, v_auth
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.proname = 'h09_derive_temoin';

  -- le prédicat du contrôle : exposée à PUBLIC ou à anon, et hors registre
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    WHERE p.proname = 'h09_derive_temoin'
      AND (p.proacl IS NULL
           OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                      WHERE (a).privilege_type = 'EXECUTE'
                        AND ((a).grantee = 0 OR (a).grantee = (SELECT oid FROM pg_roles WHERE rolname = 'anon'))))
  ) INTO v_signalee;

  EXECUTE 'DROP FUNCTION public.h09_derive_temoin()';
  PERFORM _rec('T07', 'une fonction créée après la 228 redevient exposée, et le contrôle CI la signale',
    v_expose AND v_signalee AND v_auth,
    format('exposée à anon=%s signalée par le contrôle=%s authenticated=%s', v_expose, v_signalee, v_auth));
END $$;

SELECT _audit_assert('228');
