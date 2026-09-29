-- ============================================================
-- 313_customer_balances_from_ledger_tests.sql — recette /qa du 29/09/2026
--
--   ven-017 🟠  le « Solde dû » de la liste des clients et le « Crédit utilisé »
--               du contrôle crédit affichent 0,00 € partout, alors que le 411
--               porte de l'argent : les deux écrans lisaient `customers.balance`
--               et `customers.credit_used`, deux colonnes que rien ne tient.
--
-- Ce fichier tient la fermeture : le solde d'un client est celui de son compte
-- 411 au grand livre (débits − crédits), seules les écritures VALIDÉES comptent,
-- un client sans mouvement vaut 0,00 €, et rien ne franchit une société.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '313', false);
DELETE FROM _audit_results WHERE file = '313';

-- T01 — facture − avoir − règlement = solde du 411 (162,20 attendu dans la
--       recette : ici 540 − 120 − 300 = 120,00)
DO $$
DECLARE t uuid; c uuid; v_code text; solde numeric; mv int; colonne numeric;
BEGIN
  t := _mk_tenant('QA313A');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Dubois Industrie SAS', 'dubois@audit.test', true)
  RETURNING id, account_tiers INTO c, v_code;
  EXECUTE 'RESET ROLE';

  PERFORM _entry(t, 'FAC-313-A', DATE '2026-02-10', jsonb_build_array(
    jsonb_build_object('a', '411000', 'd', 540, 't', v_code),
    jsonb_build_object('a', '707000', 'c', 540)));
  PERFORM _entry(t, 'AV-313-A', DATE '2026-02-12', jsonb_build_array(
    jsonb_build_object('a', '411000', 'c', 120, 't', v_code),
    jsonb_build_object('a', '707000', 'd', 120)));
  PERFORM _entry(t, 'RGT-313-A', DATE '2026-02-20', jsonb_build_array(
    jsonb_build_object('a', '512000', 'd', 300),
    jsonb_build_object('a', '411000', 'c', 300, 't', v_code)));

  SELECT balance, lines_count INTO solde, mv FROM customer_balances WHERE tenant_id = t AND customer_id = c;
  SELECT balance INTO colonne FROM customers WHERE id = c;

  PERFORM _rec('T01', 'le solde d''un client est celui de son 411 (facture − avoir − règlement)',
    solde = 120 AND mv = 3,
    format('solde=%s (120 attendu), %s mouvement(s) ; colonne customers.balance=%s (jamais tenue)',
           solde, mv, colonne));
END $$;

-- T02 — un brouillon ne compte pas dans le solde
DO $$
DECLARE t uuid; c uuid; v_code text; solde numeric;
BEGIN
  t := _mk_tenant('QA313B');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Client brouillon', 'b@audit.test', true)
  RETURNING id, account_tiers INTO c, v_code;
  EXECUTE 'RESET ROLE';

  PERFORM _entry(t, 'FAC-313-B', DATE '2026-02-10', jsonb_build_array(
    jsonb_build_object('a', '411000', 'd', 200, 't', v_code),
    jsonb_build_object('a', '707000', 'c', 200)));
  PERFORM _entry(t, 'FAC-BROUILLON-313-B', DATE '2026-02-11', jsonb_build_array(
    jsonb_build_object('a', '411000', 'd', 999, 't', v_code),
    jsonb_build_object('a', '707000', 'c', 999)), false);

  SELECT balance INTO solde FROM customer_balances WHERE tenant_id = t AND customer_id = c;
  PERFORM _rec('T02', 'une écriture en brouillon ne compte pas dans le solde',
    solde = 200, format('solde=%s (200 attendu ; le brouillon de 999 est exclu)', solde));
END $$;

-- T03 — un client sans mouvement est présent à 0,00 €
DO $$
DECLARE t uuid; c uuid; n int; solde numeric;
BEGIN
  t := _mk_tenant('QA313C');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Martin Sans Mouvement', 'martin@audit.test', true)
  RETURNING id INTO c;
  EXECUTE 'RESET ROLE';

  SELECT count(*), min(balance) INTO n, solde FROM customer_balances WHERE tenant_id = t AND customer_id = c;
  PERFORM _rec('T03', 'un client sans mouvement vaut 0,00 € (et reste listé)',
    n = 1 AND solde = 0, format('%s ligne(s), solde=%s', n, solde));
END $$;

-- T04 — isolation : le solde d'une société ne se voit pas depuis une autre
DO $$
DECLARE ta uuid; tb uuid; ua uuid; ca text; cb text; sa numeric; sb numeric; vu int;
BEGIN
  ta := _mk_tenant('QA313D');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (ta, 'Client A', 'a@audit.test', true)
  RETURNING account_tiers INTO ca;
  EXECUTE 'RESET ROLE';
  PERFORM _entry(ta, 'FAC-313-D', DATE '2026-02-10', jsonb_build_array(
    jsonb_build_object('a', '411000', 'd', 411, 't', ca),
    jsonb_build_object('a', '707000', 'c', 411)));

  tb := _mk_tenant('QA313E');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (tb, 'Client B', 'b@audit.test', true)
  RETURNING account_tiers INTO cb;
  EXECUTE 'RESET ROLE';
  PERFORM _entry(tb, 'FAC-313-E', DATE '2026-02-10', jsonb_build_array(
    jsonb_build_object('a', '411000', 'd', 222, 't', cb),
    jsonb_build_object('a', '707000', 'c', 222)));

  -- on revient sur le compte de A : la vue ne doit montrer que ses clients
  SELECT auth_id INTO ua FROM tenant_users WHERE tenant_id = ta ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', ua::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  PERFORM _as_user();
  SELECT count(*), max(balance) INTO vu, sa FROM customer_balances;
  EXECUTE 'RESET ROLE';
  SELECT balance INTO sb FROM customer_balances WHERE tenant_id = tb AND name = 'Client B';

  PERFORM _rec('T04', 'le solde d''une société ne se voit pas depuis une autre',
    vu = 1 AND sa = 411 AND sb = 222,
    format('vus par A : %s client(s) de solde %s ; société B : %s', vu, sa, sb));
END $$;

-- T05 — deux clients de la même société ont deux soldes distincts (aucun
--       regroupement par compte collectif)
DO $$
DECLARE t uuid; c1 uuid; c2 uuid; v1 text; v2 text; s1 numeric; s2 numeric;
BEGIN
  t := _mk_tenant('QA313F');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Client un', 'u@audit.test', true)
  RETURNING id, account_tiers INTO c1, v1;
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Client deux', 'd@audit.test', true)
  RETURNING id, account_tiers INTO c2, v2;
  EXECUTE 'RESET ROLE';

  PERFORM _entry(t, 'FAC-313-F1', DATE '2026-02-10', jsonb_build_array(
    jsonb_build_object('a', '411000', 'd', 300, 't', v1),
    jsonb_build_object('a', '707000', 'c', 300)));
  PERFORM _entry(t, 'FAC-313-F2', DATE '2026-02-10', jsonb_build_array(
    jsonb_build_object('a', '411000', 'd', 250, 't', v2),
    jsonb_build_object('a', '707000', 'c', 250)));

  SELECT balance INTO s1 FROM customer_balances WHERE tenant_id = t AND customer_id = c1;
  SELECT balance INTO s2 FROM customer_balances WHERE tenant_id = t AND customer_id = c2;

  PERFORM _rec('T05', 'chaque client porte son propre solde (300,00 et 250,00)',
    s1 = 300 AND s2 = 250 AND v1 <> v2,
    format('client un (%s)=%s, client deux (%s)=%s', v1, s1, v2, s2));
END $$;

-- T06 — le même solde pour les fournisseurs (401), la liste des fournisseurs
--       affichant le même « Solde dû » à 0,00 €.
DO $$
DECLARE t uuid; s uuid; v_code text; solde numeric;
BEGIN
  t := _mk_tenant('QA313G');
  PERFORM _as_user();
  INSERT INTO suppliers (tenant_id, name, email, active)
  VALUES (t, 'Gants & Fournitures SA', 'gf@audit.test', true)
  RETURNING id, account_tiers INTO s, v_code;
  EXECUTE 'RESET ROLE';

  PERFORM _entry(t, 'FF-313-G', DATE '2026-02-10', jsonb_build_array(
    jsonb_build_object('a', '401000', 'c', 360, 't', v_code),
    jsonb_build_object('a', '601000', 'd', 360)));

  SELECT balance INTO solde FROM supplier_balances WHERE tenant_id = t AND supplier_id = s;
  PERFORM _rec('T06', 'le solde d''un fournisseur est celui de son 401 (360,00)',
    solde = -360, format('solde=%s (un dû fournisseur est créditeur : −360 attendu)', solde));
END $$;

SELECT _audit_assert('313');


