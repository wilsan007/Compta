-- ============================================================
-- 312_third_party_accounts_from_partners_tests.sql — recette /qa du 29/09/2026
--
--   ven-013 🔴  créer un client ou un fournisseur ne l'inscrit pas au plan des
--               tiers : `third_party_accounts` reste vide (0 ligne pour 4 clients
--               et 4 fournisseurs). Le lettrage ne trouve aucun tiers, le plan
--               tiers affiche « 0 compte(s) », la balance âgée retombe sur le type
--               « other » et son filtre « Clients » est vide (ven-014).
--   cpt-005 🟡  le même fait vu du plan comptable.
--
-- Ce fichier tient la fermeture : un tiers créé ou modifié à l'écran a son compte
-- au plan tiers, un renommage et un changement de code se propagent, le
-- rattrapage couvre les tiers d'avant, un salarié a son compte 421, et rien ne
-- franchit une frontière de société.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '312', false);
DELETE FROM _audit_results WHERE file = '312';

-- T01 — un client créé a son compte de tiers 411/CLIxxxxx
DO $$
DECLARE t uuid; c_id uuid; c_code text; n int; tp record;
BEGIN
  t := _mk_tenant('QA312A');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Dubois Industrie SAS', 'contact@dubois.test', true)
  RETURNING id, account_tiers INTO c_id, c_code;
  EXECUTE 'RESET ROLE';

  SELECT count(*) INTO n FROM third_party_accounts
  WHERE tenant_id = t AND customer_id = c_id AND type = 'customer';
  SELECT * INTO tp FROM third_party_accounts WHERE tenant_id = t AND customer_id = c_id;

  PERFORM _rec('T01', 'un client créé à l''écran a son compte au plan des tiers',
    n = 1 AND tp.code = c_code AND tp.name = 'Dubois Industrie SAS'
      AND tp.account_general_code = '411000' AND tp.active,
    format('%s compte(s) ; code=%s (attendu %s), collectif=%s, nom=%s',
           n, tp.code, c_code, tp.account_general_code, tp.name));
END $$;

-- T02 — un fournisseur créé a son compte 401/FOUxxxxx
DO $$
DECLARE t uuid; s_id uuid; s_code text; n int; tp record;
BEGIN
  t := _mk_tenant('QA312B');
  PERFORM _as_user();
  INSERT INTO suppliers (tenant_id, name, email, active)
  VALUES (t, 'Gants & Fournitures SA', 'ventes@gf.test', true)
  RETURNING id, account_tiers INTO s_id, s_code;
  EXECUTE 'RESET ROLE';

  SELECT count(*) INTO n FROM third_party_accounts
  WHERE tenant_id = t AND supplier_id = s_id AND type = 'supplier';
  SELECT * INTO tp FROM third_party_accounts WHERE tenant_id = t AND supplier_id = s_id;

  PERFORM _rec('T02', 'un fournisseur créé à l''écran a son compte au plan des tiers',
    n = 1 AND tp.code = s_code AND tp.name = 'Gants & Fournitures SA'
      AND tp.account_general_code = '401000',
    format('%s compte(s) ; code=%s (attendu %s), collectif=%s',
           n, tp.code, s_code, tp.account_general_code));
END $$;

-- T03 — le compte suit son tiers : un renommage et un changement de code se
--       propagent, SANS créer un second compte
DO $$
DECLARE t uuid; c uuid; n int; tp record;
BEGIN
  t := _mk_tenant('QA312C');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Ancien Nom', 'avant@audit.test', true) RETURNING id INTO c;
  UPDATE customers SET name = 'Nouveau Nom', account_tiers = 'CLI-T03' WHERE id = c;
  EXECUTE 'RESET ROLE';

  SELECT count(*) INTO n FROM third_party_accounts WHERE tenant_id = t AND customer_id = c;
  SELECT * INTO tp FROM third_party_accounts WHERE tenant_id = t AND customer_id = c;

  PERFORM _rec('T03', 'un renommage et un changement de code se propagent au compte de tiers',
    n = 1 AND tp.name = 'Nouveau Nom' AND tp.code = 'CLI-T03',
    format('%s compte(s) ; nom=%s, code=%s (attendu « Nouveau Nom » et CLI-T03)', n, tp.name, tp.code));
END $$;

-- T04 — le rattrapage inscrit les tiers qui n'ont pas encore leur compte, et
--       n'écrase pas un compte saisi à la main (ON CONFLICT DO NOTHING).
--       Remarque de méthode : le test ne DÉSACTIVE aucun déclencheur — un
--       abandon entre le DISABLE et le ENABLE laisserait la base amputée
--       (mesuré) ; il ramène la ligne à l'état d'avant le déclencheur en
--       supprimant le compte, ce qui mesure la même chose sans risque.
DO $$
DECLARE
  t uuid; c1 uuid; c2 uuid; code1 text; code2 text;
  avant int; apres int; n int; tp record; garde text;
BEGIN
  t := _mk_tenant('QA312D');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Client historique', 'hist@audit.test', true)
  RETURNING id, account_tiers INTO c1, code1;
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Client déjà saisi', 'saisi@audit.test', true)
  RETURNING id, account_tiers INTO c2, code2;
  EXECUTE 'RESET ROLE';

  -- c1 revient à l'état d'avant le déclencheur : son compte est absent
  DELETE FROM third_party_accounts WHERE tenant_id = t AND customer_id = c1;
  -- c2 a un compte saisi à la main : le rattrapage ne doit pas l'écraser
  UPDATE third_party_accounts SET name = 'Nom gardé par le comptable'
   WHERE tenant_id = t AND customer_id = c2;

  SELECT count(*) INTO avant FROM third_party_accounts WHERE tenant_id = t AND customer_id = c1;
  n := backfill_third_party_accounts(t);
  SELECT count(*) INTO apres FROM third_party_accounts WHERE tenant_id = t AND customer_id = c1;
  SELECT * INTO tp FROM third_party_accounts WHERE tenant_id = t AND customer_id = c1;
  SELECT name INTO garde FROM third_party_accounts WHERE tenant_id = t AND code = code2;

  PERFORM _rec('T04', 'le rattrapage inscrit les tiers sans compte, sans écraser un compte saisi',
    avant = 0 AND apres = 1 AND n >= 1 AND tp.code = code1 AND tp.name = 'Client historique'
      AND garde = 'Nom gardé par le comptable',
    format('avant=%s, après=%s, rattrapés=%s, code=%s ; compte manuel gardé : %s',
           avant, apres, n, tp.code, garde));
END $$;

-- T05 — isolation : le compte d'une société n'est pas visible depuis une autre,
--       et le rattrapage d'une société ne touche pas les autres
DO $$
DECLARE ta uuid; tb uuid; ua uuid; ia int; ib int; vu int;
BEGIN
  ta := _mk_tenant('QA312E');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active) VALUES (ta, 'Client A', 'a@audit.test', true);
  EXECUTE 'RESET ROLE';

  tb := _mk_tenant('QA312F');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active) VALUES (tb, 'Client B', 'b@audit.test', true);
  EXECUTE 'RESET ROLE';

  -- le rattrapage de A ne doit rien créer chez B
  PERFORM backfill_third_party_accounts(ta);
  SELECT count(*) INTO ia FROM third_party_accounts WHERE tenant_id = ta;
  SELECT count(*) INTO ib FROM third_party_accounts WHERE tenant_id = tb;

  -- on revient sur le compte de A et on compte ce qu'il VOIT
  SELECT auth_id INTO ua FROM tenant_users WHERE tenant_id = ta ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', ua::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  PERFORM _as_user();
  SELECT count(*) INTO vu FROM third_party_accounts;
  EXECUTE 'RESET ROLE';

  PERFORM _rec('T05', 'le compte de tiers d''une société reste invisible à l''autre',
    ia = 1 AND ib = 1 AND vu = 1 AND EXISTS (SELECT 1 FROM third_party_accounts WHERE tenant_id = ta AND name = 'Client A'),
    format('société A=%s, société B=%s, vus par A=%s (1 attendu)', ia, ib, vu));
END $$;

-- T06 — un salarié porte son compte 421 (le grand livre de la paie écrit le
--       matricule comme compte auxiliaire : sans ce compte, le FEC n'a pas de
--       libellé — mesuré « CompAuxLib manquant » sur M430080).
DO $$
DECLARE t uuid; e1 uuid; e2 uuid; n int; tp record; sans int;
BEGIN
  t := _mk_tenant('QA312G');
  PERFORM _as_user();
  INSERT INTO employees (tenant_id, name, employee_number, base_salary, hire_date, status)
  VALUES (t, 'Salarié matriculé', 'M312001', 2500, '2026-01-01', 'active') RETURNING id INTO e1;
  INSERT INTO employees (tenant_id, name, employee_number, base_salary, hire_date, status)
  VALUES (t, 'Salarié sans matricule', NULL, 2500, '2026-01-01', 'active') RETURNING id INTO e2;
  -- désactiver le salarié doit désactiver son compte
  UPDATE employees SET status = 'inactive' WHERE id = e1;
  EXECUTE 'RESET ROLE';

  SELECT count(*) INTO n FROM third_party_accounts WHERE tenant_id = t AND type = 'employee';
  SELECT * INTO tp FROM third_party_accounts WHERE tenant_id = t AND code = 'M312001';
  SELECT count(*) INTO sans FROM third_party_accounts WHERE tenant_id = t AND name = 'Salarié sans matricule';

  PERFORM _rec('T06', 'un salarié matriculé a son compte 421 (et un salarié sans matricule n''en a pas)',
    n = 1 AND tp.account_general_code = '421000' AND tp.name = 'Salarié matriculé'
      AND NOT tp.active AND sans = 0,
    format('%s compte(s) salarié ; M312001 collectif=%s actif=%s ; sans matricule=%s',
           n, tp.account_general_code, tp.active, sans));
END $$;

-- T07 — la balance âgée et son filtre « Clients » (ven-014) : toute ligne de
--       grand livre qui porte un compte auxiliaire de tiers trouve son TYPE et son
--       NOM. Sans la 312, `third_party_accounts` est vide : le type retombe sur
--       « other », le filtre « Clients » vide la balance et le nom affiché est le
--       code. Même cause que T01 — c'est la mesure de sa conséquence à l'écran.
DO $$
DECLARE t uuid; c uuid; v_code text; e uuid; typ text; nom text; n int;
BEGIN
  t := _mk_tenant('QA312I');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, email, active)
  VALUES (t, 'Dubois Industrie SAS', 'dubois@audit.test', true)
  RETURNING id, account_tiers INTO c, v_code;
  EXECUTE 'RESET ROLE';

  -- la facture de vente : 411 D 162,20 / 707 C 162,20, portée par le compte auxiliaire
  e := _entry(t, 'FAC-2026-312-I', DATE '2026-02-10',
    jsonb_build_array(
      jsonb_build_object('a', '411000', 'd', 162.20, 't', v_code),
      jsonb_build_object('a', '707000', 'c', 162.20)));

  SELECT count(*), min(tp.type), min(tp.name) INTO n, typ, nom
  FROM journal_lines l
  JOIN third_party_accounts tp
    ON tp.tenant_id = l.tenant_id AND tp.code = l.account_tiers
  WHERE l.tenant_id = t AND l.account_tiers = v_code AND tp.type = 'customer';

  PERFORM _rec('T07', 'une ligne de 411 trouve le type et le nom de son tiers (filtre « Clients »)',
    n = 1 AND typ = 'customer' AND nom = 'Dubois Industrie SAS',
    format('%s ligne(s) résolue(s) ; type=%s, nom=%s (filtre « Clients » vide sans ce résultat)', n, typ, nom));
END $$;

SELECT _audit_assert('312');



