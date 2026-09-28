-- ============================================================
-- 272_master_data_defaults_tests.sql — vague X7 : données de base
-- (audit fonctionnel exécuté du 28/09/2026 : M2, M13)
--
-- MESURÉ AVANT, par le chemin de l'écran (sur base neuve, 238 migrations) :
--   M2  un client, un fournisseur ou un salarié SANS e-mail était impossible
--       à créer : l'écran envoie `email: ''` et la contrainte de format
--       n'accepte que NULL ou une adresse (23514) ;
--   M13 une facture d'une société en DJF était enregistrée en EUR (défaut de
--       colonne `'EUR'`, l'écran n'envoie pas de devise) ; une société neuve
--       n'avait AUCUN taux de TVA — les taux de référence vivent sous la
--       société technique `…0001`, que `getTaxRates` ne lit pas.
--
-- Ce que ce fichier prouve :
--   T01 client, fournisseur, salarié et paramètres de société acceptent un
--       e-mail vide, enregistré NULL                                     (M2)
--   T02 une adresse invalide reste refusée (la contrainte n'est pas affaiblie)
--   T03 une facture sans devise prend la devise de la société (DJF) ;
--       une devise explicite est gardée                                  (M13)
--   T04 une société française inscrite reçoit les 5 taux de son pack   (M13)
--   T05 une société existante sans taux a été rattrapée par la migration
--
-- T01, T03, T04, T05 sont ROUGES avant la 272.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '272', false);
DELETE FROM _audit_results WHERE file = '272';

-- T01 / T02 — e-mail vide
DO $$
DECLARE t uuid; ok text := ''; ko text := ''; e text; bad text := '—';
BEGIN
  t := _mk_tenant('X7M2');
  PERFORM _as_user();
  BEGIN INSERT INTO customers (tenant_id, name, email) VALUES (t, 'Client sans e-mail', ''); ok := ok || 'client ';
  EXCEPTION WHEN OTHERS THEN ko := ko || 'client (' || SQLERRM || ') '; END;
  BEGIN INSERT INTO suppliers (tenant_id, name, email) VALUES (t, 'Fournisseur sans e-mail', '  '); ok := ok || 'fournisseur ';
  EXCEPTION WHEN OTHERS THEN ko := ko || 'fournisseur (' || SQLERRM || ') '; END;
  BEGIN INSERT INTO employees (tenant_id, employee_number, first_name, last_name, hire_date, status, email)
        VALUES (t, 'M2-01', 'Sans', 'Courriel', '2026-01-01', 'active', ''); ok := ok || 'salarié ';
  EXCEPTION WHEN OTHERS THEN ko := ko || 'salarié (' || SQLERRM || ') '; END;
  BEGIN UPDATE company_settings SET email = '' WHERE tenant_id = t; ok := ok || 'société ';
  EXCEPTION WHEN OTHERS THEN ko := ko || 'société (' || SQLERRM || ') '; END;
  EXECUTE 'RESET ROLE';
  SELECT string_agg(x, ',') INTO e FROM (
    SELECT coalesce(email, 'NULL') x FROM customers WHERE tenant_id = t
    UNION ALL SELECT coalesce(email, 'NULL') FROM suppliers WHERE tenant_id = t
    UNION ALL SELECT coalesce(email, 'NULL') FROM employees WHERE tenant_id = t
    UNION ALL SELECT coalesce(email, 'NULL') FROM company_settings WHERE tenant_id = t) s;
  PERFORM _rec('T01', 'client, fournisseur, salarié et société acceptent un e-mail vide (enregistré NULL)',
    ko = '' AND e !~ '[^NUL,]', format('acceptés : %s | refusés : %s | stockés : %s', ok, nullif(ko, ''), e));

  PERFORM _as_user();
  BEGIN INSERT INTO customers (tenant_id, name, email) VALUES (t, 'Client faux', 'pas-une-adresse'); bad := 'accepté';
  EXCEPTION WHEN check_violation THEN bad := 'refusé';
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T02', 'une adresse invalide reste refusée', bad = 'refusé', bad);
END $$;

-- T03 — devise de la facture
DO $$
DECLARE t uuid; c uuid; i1 uuid; i2 uuid; d1 text; d2 text;
BEGIN
  t := _mk_tenant('X7M13');
  UPDATE tenants SET currency = 'DJF' WHERE id = t;
  UPDATE company_settings SET currency = 'DJF' WHERE tenant_id = t;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client DJ') RETURNING id INTO c;
  PERFORM _as_user();
  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
    VALUES (t, c, 'Client DJ', '2026-09-10', '2026-10-10', 'draft') RETURNING id, currency_code INTO i1, d1;
  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status, currency_code)
    VALUES (t, c, 'Client DJ', '2026-09-10', '2026-10-10', 'draft', 'USD') RETURNING id, currency_code INTO i2, d2;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'une facture sans devise prend celle de la société (DJF) ; une devise explicite est gardée',
    d1 = 'DJF' AND d2 = 'USD', format('sans devise → %s ; USD explicite → %s', d1, d2));
END $$;

-- T04 — taux de TVA à l'inscription
DO $$
DECLARE a uuid := uuid_generate_v4(); r jsonb; t uuid; n int; taux text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (a, 'x7-' || a || '@audit.test');
  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated', 'email', 'x7@audit.test', 'user_metadata', json_build_object('name', 'Admin'))::text, false);
  PERFORM set_config('app.active_tenant_id', '', false);
  PERFORM _as_user();
  r := create_tenant_for_current_user('{"name":"Société X7","country":"France","currency":"EUR"}');
  t := (r->>'tenant_id')::uuid;
  EXECUTE 'RESET ROLE';
  SELECT count(*), string_agg(rate::numeric(6,2)::text, '/' ORDER BY rate DESC) INTO n, taux FROM tax_rates WHERE tenant_id = t;
  PERFORM _rec('T04', 'une société française inscrite reçoit les taux de son pack (20 / 10 / 5,5 / 2,1 / 0)',
    n = 5 AND taux = '20.00/10.00/5.50/2.10/0.00', format('taux=%s (%s)', n, coalesce(taux, 'aucun')));
END $$;

-- T05 — rattrapage : aucune société à pack connu ne reste sans taux
DO $$
DECLARE n int; liste text;
BEGIN
  SELECT count(*), string_agg(te.name, ', ') INTO n, liste
  FROM tenants te
  WHERE te.id <> '00000000-0000-0000-0000-000000000001'
    AND EXISTS (SELECT 1 FROM tax_rates r WHERE r.tenant_id = '00000000-0000-0000-0000-000000000001'
                AND r.pack_code = coalesce(te.legislation_pack_code, te.country_code))
    AND NOT EXISTS (SELECT 1 FROM tax_rates r WHERE r.tenant_id = te.id);
  PERFORM _rec('T05', 'aucune société dont le pack a des taux de référence ne reste sans taux',
    n = 0, format('%s société(s) sans taux : %s', n, left(coalesce(liste, '—'), 200)));
END $$;

SELECT _audit_assert('272');
