-- ============================================================
-- 348_chart_account_type_from_class_tests.sql — tâche 2.11 (F2)
--
--   T01  un compte créé SANS type prend celui de sa classe : 60699901 charge
--        (achats), 70799901 produit, 41199901 créance, 40199901 dette fournisseur,
--        51299901 trésorerie, 68199901 dotation
--   T02  `classe` et `racine` sont recopiées du numéro
--   T03  un type CHOISI est respecté
--   T04  plus aucun compte de classe 6 ou 7 en « actif courant » dans la base
--   T05  le plan livré à la création d'une société est classé par sa classe
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '348', false);
DELETE FROM _audit_results WHERE file = '348';

DO $$
DECLARE
  t uuid := _mk_tenant('P2F2T01', false);
  v jsonb; v_cl text; v_ra text; v_choisi text; n_faux int;
BEGIN
  PERFORM _as_user();
  -- `_mk_tenant` livre le plan complet (712 comptes) : on crée des numéros à huit
  -- chiffres, qu'il ne contient pas.
  INSERT INTO chart_accounts (tenant_id, code, name, type) VALUES
    (t, '60699901', 'Fournitures', 'expense'), (t, '70799901', 'Ventes', 'income'),
    (t, '41199901', 'Clients', 'asset'), (t, '40199901', 'Fournisseurs', 'liability'),
    (t, '51299901', 'Banque', 'asset'), (t, '68199901', 'Dotations', 'expense');
  SELECT jsonb_object_agg(code, account_type) INTO v FROM chart_accounts
   WHERE tenant_id = t AND code IN ('60699901', '70799901', '41199901', '40199901', '51299901', '68199901');
  PERFORM _rec('T01', 'un compte créé sans type prend celui de sa classe (60699901 achats, 70799901 produit, 41199901 créance, 40199901 dette fournisseur, 51299901 trésorerie, 68199901 dotation)',
    v->>'60699901' = 'expense_direct_cost' AND v->>'70799901' = 'income' AND v->>'41199901' = 'asset_receivable'
      AND v->>'40199901' = 'liability_payable' AND v->>'51299901' = 'asset_cash' AND v->>'68199901' = 'expense_depreciation',
    v::text);

  SELECT classe, racine INTO v_cl, v_ra FROM chart_accounts WHERE tenant_id = t AND code = '60699901';
  PERFORM _rec('T02', 'classe et racine sont recopiées du numéro (60699901 → classe 6, racine 606)',
    v_cl = '6' AND v_ra = '606', format('classe=%s racine=%s', v_cl, v_ra));

  INSERT INTO chart_accounts (tenant_id, code, name, type, account_type)
  VALUES (t, '65899901', 'Charges diverses', 'expense', 'expense_other');
  SELECT account_type INTO v_choisi FROM chart_accounts WHERE tenant_id = t AND code = '65899901';
  PERFORM _rec('T03', 'un type choisi est respecté (65899901 enregistré en « autres charges »)',
    v_choisi = 'expense_other', format('account_type=%s', v_choisi));

  EXECUTE 'RESET ROLE';
  PERFORM _rec('T05', 'le plan LIVRÉ à la création de la société est classé par sa classe : aucun compte 6 ou 7 à l''actif, aucun compte sans type',
    (SELECT count(*) FROM chart_accounts WHERE tenant_id = t AND left(code, 1) IN ('6', '7') AND account_type LIKE 'asset%') = 0
      AND (SELECT count(*) FROM chart_accounts WHERE tenant_id = t AND btrim(COALESCE(account_type, '')) = '') = 0,
    format('comptes du plan=%s, 6/7 à l''actif=%s, sans type=%s',
      (SELECT count(*) FROM chart_accounts WHERE tenant_id = t),
      (SELECT count(*) FROM chart_accounts WHERE tenant_id = t AND left(code, 1) IN ('6', '7') AND account_type LIKE 'asset%'),
      (SELECT count(*) FROM chart_accounts WHERE tenant_id = t AND btrim(COALESCE(account_type, '')) = '')));
  SELECT count(*) INTO n_faux FROM chart_accounts
   WHERE left(code, 1) IN ('6', '7') AND account_type = 'asset_current';
  PERFORM _rec('T04', 'plus aucun compte de classe 6 ou 7 classé « actif courant » dans la base',
    n_faux = 0, format('comptes 6/7 en asset_current=%s', n_faux));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'T01 à T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('348');
