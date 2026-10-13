-- ============================================================
-- 665_landed_cost_location_guards_tests.sql — E.3 / E.5 (partie E)
--
-- Mesuré AVANT la 665 : `check_composite_fks` refusait la clé mono-colonne de
-- `landed_cost_receipts`, `check_bt_grid` comptait +2 sur `rls_sans_force`.
-- T02 est la preuve de COMPORTEMENT, pas de forme : une affectation de frais
-- pouvait désigner la dépense d'une société dont l'appelant n'est pas membre.
-- Elle est refusée maintenant (23503).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '665', false);
DELETE FROM _audit_results WHERE file = '665';

-- Une société du test, une réception et une dépense de frais à elle.
CREATE OR REPLACE FUNCTION _mk665(p_nom text, OUT t uuid, OUT gr uuid, OUT lc uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO goods_receipts (tenant_id, number, receipt_date, status)
  VALUES (t, 'GR-' || p_nom, CURRENT_DATE, 'received') RETURNING id INTO gr;
  INSERT INTO landed_costs (tenant_id, invoice_number, total_amount)
  VALUES (t, 'LC-' || p_nom, 100) RETURNING id INTO lc;
END $$;

-- T01 — la clé mono-colonne a disparu, la composite l'a remplacée
DO $$
DECLARE mono int; compo int;
BEGIN
  SELECT count(*) INTO mono
  FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid
  WHERE c.relname = 'landed_cost_receipts' AND con.contype = 'f'
    AND con.confrelid = 'public.landed_costs'::regclass
    AND array_length(con.conkey, 1) = 1;

  SELECT count(*) INTO compo
  FROM pg_constraint con
  WHERE con.conname = 'landed_cost_receipts_landed_cost_fk'
    AND con.contype = 'f'
    AND pg_get_constraintdef(con.oid) LIKE '%(tenant_id, landed_cost_id)%'
    AND pg_get_constraintdef(con.oid) LIKE '%landed_costs(tenant_id, id)%';

  PERFORM _rec('T01', 'la clé étrangère de la dépense est composite (tenant_id, landed_cost_id)',
    (mono = 0 AND compo = 1),
    format('mono-colonne(s)=%s (0 attendu), composite(s)=%s (1 attendu)', mono, compo));
END $$;

-- T02 — le comportement : la dépense d'une autre société est refusée
DO $$
DECLARE tb uuid; grb uuid; lcb uuid; ta uuid; gra uuid; lca uuid;
        v_state text; v_err text;
BEGIN
  SELECT * INTO tb, grb, lcb FROM _mk665('VAL665B02');  -- société étrangère
  SELECT * INTO ta, gra, lca FROM _mk665('VAL665A02');  -- l'appelant est ici
  BEGIN
    -- La réception est bien celle de A ; la DÉPENSE est celle de B.
    INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id)
    VALUES (ta, lcb, gra);
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T02', 'une affectation ne peut pas rattacher la dépense d''une autre société (23503)',
    v_state = '23503',
    format('SQLSTATE=%s ; %s', COALESCE(v_state, 'aucune erreur — l''affectation a été acceptée'),
           left(COALESCE(v_err, ''), 80)));
END $$;

-- T03 — ISO-04 : les deux tables neuves sont sous FORCE RLS
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
  FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
  WHERE ns.nspname = 'public'
    AND c.relname IN ('landed_cost_receipts', 'stock_location_assignments')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _rec('T03', 'les deux tables neuves sont sous FORCE RLS (ISO-04)',
    n = 2, format('%s/2 table(s) avec RLS forcée', n));
END $$;

-- T04 — BUD-04 : les deux tables ont leur index de société
DO $$
DECLARE n int;
BEGIN
  SELECT count(DISTINCT c.relname) INTO n
  FROM pg_class c
  JOIN pg_namespace ns ON ns.oid = c.relnamespace
  JOIN pg_index i ON i.indrelid = c.oid AND i.indisvalid
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = i.indkey[0]
  WHERE ns.nspname = 'public'
    AND c.relname IN ('landed_cost_receipts', 'stock_location_assignments')
    AND a.attname = 'tenant_id' AND a.attnum > 0;
  PERFORM _rec('T04', 'les deux tables neuves ont un index dont la 1re colonne est la société (BUD-04)',
    n = 2, format('%s/2 table(s) indexée(s) sur tenant_id', n));
END $$;

SELECT _audit_assert('665');
