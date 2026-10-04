-- ============================================================
-- 271_viewer_writes_and_approval_tests.sql — vague X1 : droits
-- (audit fonctionnel exécuté du 28/09/2026 : C3, M8, M9, M12, H10)
--
-- MESURÉ AVANT, sur base neuve (238 migrations + 270) :
--   C3  un lecteur remettait `document_number_sequences` à 2 : toute
--       validation de facture échouait ensuite (doublon) — la facturation
--       d'une société bloquée par son lecteur ;
--   M8  un lecteur modifiait 16 des 41 tables testées (exercices, journaux,
--       dépôts, nomenclatures, OF, réceptions, caisse, imports de relevé,
--       couches de valorisation…), créait des écritures par
--       `post_journal_entry` et relançait le calcul des bulletins ;
--   M9  l'auteur d'une facture d'achat l'approuvait lui-même, même avec
--       `enforce_segregation`, et `approved_by` n'était jamais écrit ;
--   M12 `analytic_distribution_lines` gardait une politique héritée
--       (`tenant_id IS NULL OR … app.tenant_id`) ; `project_docs` cloisonnait
--       sur « la première société de la table » (`LIMIT 1`).
--
-- Ce que ce fichier prouve :
--   T01 un lecteur ne modifie pas `document_number_sequences`          (C3)
--   T02 les tables alimentées par déclencheur ne sont plus écrites par
--       `authenticated` (numérotation, stock, couches, séquences)      (C3)
--   T03 la validation d'une facture numérote toujours (non-régression)
--   T04 un lecteur n'écrit dans AUCUNE des tables du périmètre X1, et
--       chaque refus vient des droits — pas d'une autre erreur        (M8)
--   T05 l'admin écrit toujours dans ces tables (non-régression)
--   T06 un lecteur ne crée pas d'écriture par `post_journal_entry`     (M8)
--   T07 un lecteur ne relance pas le calcul d'un bulletin             (H10)
--   T08 l'approbation d'un achat écrit `approved_by` et son auteur    (M9)
--   T09 avec séparation des tâches, l'auteur n'approuve pas son achat ;
--       un autre comptable le peut                                     (M9)
--   T10 plus aucune politique héritée sur analytic_distribution_lines
--       ni project_docs ; project_docs reste lisible par sa société   (M12)
--
-- Tous sauf T03, T05 sont ROUGES avant la 271.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '271', false);
DELETE FROM _audit_results WHERE file = '271';

-- Société + un lecteur + un comptable ; rend (société, admin, lecteur, comptable)
CREATE OR REPLACE FUNCTION _mk271(p_nom text, OUT t uuid, OUT adm uuid, OUT lec uuid, OUT cpt uuid)
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom);
  SELECT auth_id INTO adm FROM tenant_users WHERE tenant_id = t AND role = 'admin' LIMIT 1;
  INSERT INTO auth.users (id, email) VALUES (uuid_generate_v4(), lower(p_nom) || '-lec@audit.test') RETURNING id INTO lec;
  INSERT INTO auth.users (id, email) VALUES (uuid_generate_v4(), lower(p_nom) || '-cpt@audit.test') RETURNING id INTO cpt;
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status) VALUES
    (t, lec, lower(p_nom) || '-lec@audit.test', 'Lecteur', 'viewer', 'active'),
    (t, cpt, lower(p_nom) || '-cpt@audit.test', 'Comptable', 'accountant', 'active');
END $$;

-- Pose le jeton d'un utilisateur puis passe sous `authenticated`
CREATE OR REPLACE FUNCTION _qui271(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, false);
  PERFORM _as_user();
END $$;

-- Tente une écriture et l'annule toujours ; rend 'ÉCRIT', 'REFUS' (droits/RLS)
-- ou 'AUTRE: <erreur>' — un refus pour une autre raison ne prouve rien.
-- Une RPC qui rend `{"success": false, "error": "Permission refusée…"}` (post_journal_entry
-- intercepte ses exceptions) refuse aussi ; une modification qui n'atteint AUCUNE
-- ligne (la RLS l'a filtrée) n'a rien écrit.
CREATE OR REPLACE FUNCTION _essai271(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_res text; v_n int;
BEGIN
  BEGIN
    IF p_sql ~* '^\s*select' THEN
      EXECUTE p_sql INTO v_res;
      IF v_res ~ '"success": false' AND v_res ~* 'permission' THEN RETURN 'REFUS'; END IF;
    ELSE
      EXECUTE p_sql;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n = 0 THEN RETURN 'REFUS'; END IF;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0271', MESSAGE = 'écrit';
  EXCEPTION
    WHEN SQLSTATE 'P0271' THEN RETURN 'ÉCRIT';
    WHEN insufficient_privilege THEN RETURN 'REFUS';
    WHEN OTHERS THEN
      IF SQLERRM ~* 'row-level security|permission|Permission refusée|droit' THEN RETURN 'REFUS'; END IF;
      RETURN 'AUTRE: ' || left(SQLERRM, 90);
  END;
END $$;

-- Le jeu d'écritures du périmètre X1 (M8), paramétré par la société
CREATE OR REPLACE FUNCTION _jeu271(t uuid, p uuid, wh uuid, term uuid) RETURNS TABLE (nom text, requete text)
LANGUAGE sql AS $$
  VALUES
    ('fiscal_periods', format($q$INSERT INTO fiscal_periods (tenant_id, period_number, start_date, end_date, period_label) VALUES (%L, 99, '2026-12-01', '2026-12-31', 'P271')$q$, t)),
    ('journals', format($q$INSERT INTO journals (tenant_id, code, name, type) VALUES (%L, 'X271', 'Journal 271', 'general')$q$, t)),
    ('warehouses', format($q$INSERT INTO warehouses (tenant_id, code, name) VALUES (%L, 'W271B', 'Dépôt 271')$q$, t)),
    ('boms', format($q$INSERT INTO boms (tenant_id, code, name, product_id) VALUES (%L, 'B271', 'Nomenclature', %L)$q$, t, p)),
    ('bom_lines', format($q$INSERT INTO bom_lines (tenant_id, product_id, quantity) VALUES (%L, %L, 1)$q$, t, p)),
    ('manufacturing_orders', format($q$INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity) VALUES (%L, 'OF271', %L, 1)$q$, t, p)),
    ('goods_receipts', format($q$INSERT INTO goods_receipts (tenant_id, number) VALUES (%L, 'REC271')$q$, t)),
    ('goods_receipt_lines', format($q$INSERT INTO goods_receipt_lines (tenant_id, description) VALUES (%L, 'Ligne 271')$q$, t)),
    ('pos_terminals', format($q$INSERT INTO pos_terminals (tenant_id, name) VALUES (%L, 'Caisse 271B')$q$, t)),
    ('pos_sessions', format($q$INSERT INTO pos_sessions (tenant_id, terminal_id, user_email) VALUES (%L, %L, 'x@audit.test')$q$, t, term)),
    ('bank_statement_imports', format($q$INSERT INTO bank_statement_imports (tenant_id, format, filename) VALUES (%L, 'mt940', 'r.sta')$q$, t)),
    ('document_number_sequences', format($q$INSERT INTO document_number_sequences (tenant_id, prefix) VALUES (%L, 'ZZ')$q$, t)),
    ('stock_quantities', format($q$INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity) VALUES (%L, %L, %L, 5)$q$, t, p, wh)),
    ('journals (modification)', format($q$UPDATE journals SET name = name || '.' WHERE tenant_id = %L AND code = 'OD'$q$, t))
$$;

-- T01 — un lecteur et la numérotation (C3)
DO $$
DECLARE r record; v text;
BEGIN
  SELECT * INTO r FROM _mk271('X1C3');
  INSERT INTO document_number_sequences (tenant_id, prefix, next_number)
    VALUES (r.t, 'FAC', 7);
  PERFORM _qui271(r.lec);
  v := _essai271(format($q$UPDATE document_number_sequences SET next_number = 2 WHERE tenant_id = %L AND prefix = 'FAC'$q$, r.t));
  EXECUTE 'RESET ROLE';
  -- une modification sans effet (0 ligne visible) est aussi un refus
  IF v = 'ÉCRIT' AND (SELECT next_number FROM document_number_sequences WHERE tenant_id = r.t AND prefix = 'FAC') = 7 THEN
    v := 'ÉCRIT (annulé par le test)';
  END IF;
  PERFORM _rec('T01', 'un lecteur ne remet pas la numérotation des factures à zéro', v = 'REFUS', v);
END $$;

-- T02 — tables alimentées par déclencheur : aucune écriture directe
DO $$
DECLARE liste text;
BEGIN
  SELECT string_agg(x, ', ') INTO liste FROM unnest(ARRAY['document_number_sequences', 'stock_quantities',
    'stock_valuation_layers', 'journal_posting_sequences']) x
  WHERE has_table_privilege('authenticated', 'public.' || x, 'INSERT')
     OR has_table_privilege('authenticated', 'public.' || x, 'UPDATE')
     OR has_table_privilege('authenticated', 'public.' || x, 'DELETE');
  PERFORM _rec('T02', 'numérotation, stock, couches et séquences : écrits par leurs seules fonctions',
    liste IS NULL, coalesce('encore écrivables par authenticated : ' || liste, 'aucune'));
END $$;

-- T03 — la validation de facture numérote toujours
DO $$
DECLARE r record; c uuid; inv uuid; num text; err text := '—';
BEGIN
  SELECT * INTO r FROM _mk271('X1C3b');
  INSERT INTO customers (tenant_id, name) VALUES (r.t, 'Client 271') RETURNING id INTO c;
  PERFORM _qui271(r.adm);
  BEGIN
    INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
    VALUES (r.t, c, 'Client 271', '2026-09-10', '2026-10-10', 'draft') RETURNING id INTO inv;
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, line_order)
    VALUES (r.t, inv, 'Prestation', 1, 100, 20, 0);
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT number INTO num FROM invoices WHERE id = inv;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'l''admin valide une facture : elle reçoit son numéro définitif',
    num ~ '^FAC-2026-', format('numéro=%s ; erreur=%s', num, err));
END $$;

-- T04 / T05 — le périmètre M8, par le lecteur puis par l'admin
DO $$
DECLARE
  r record; p uuid; wh uuid; term uuid; j record; v text;
  ecrits text := ''; autres text := ''; refus int := 0;
  adm_ko text := '';
BEGIN
  SELECT * INTO r FROM _mk271('X1M8');
  INSERT INTO products (tenant_id, name, sku, type) VALUES (r.t, 'Article 271', 'A271', 'stock') RETURNING id INTO p;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (r.t, 'W271', 'Dépôt') RETURNING id INTO wh;
  INSERT INTO pos_terminals (tenant_id, name) VALUES (r.t, 'Caisse 271') RETURNING id INTO term;

  PERFORM _qui271(r.lec);
  FOR j IN SELECT * FROM _jeu271(r.t, p, wh, term) LOOP
    v := _essai271(j.requete);
    IF v = 'ÉCRIT' THEN
      ecrits := ecrits || j.nom || ', ';
    ELSIF v = 'REFUS' THEN refus := refus + 1;
    ELSE autres := autres || j.nom || ' (' || v || '), ';
    END IF;
  END LOOP;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T04', 'un lecteur n''écrit dans aucune table du périmètre X1 (et chaque refus vient des droits)',
    ecrits = '' AND autres = '',
    format('refusées=%s ; écrites : %s ; autres erreurs : %s', refus, nullif(ecrits, ''), nullif(autres, '')));

  -- l'admin : tout ce qui n'est pas réservé aux fonctions passe
  PERFORM _qui271(r.adm);
  FOR j IN SELECT * FROM _jeu271(r.t, p, wh, term)
           WHERE nom NOT IN ('document_number_sequences', 'stock_quantities') LOOP
    v := _essai271(j.requete);
    IF v <> 'ÉCRIT' THEN adm_ko := adm_ko || j.nom || ' (' || v || '), '; END IF;
  END LOOP;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T05', 'l''admin écrit toujours dans ces tables', adm_ko = '', coalesce(nullif(adm_ko, ''), 'toutes écrites'));
END $$;

-- T06 — post_journal_entry par un lecteur
DO $$
DECLARE r record; v text;
BEGIN
  SELECT * INTO r FROM _mk271('X1PJE');
  PERFORM _qui271(r.lec);
  v := _essai271($q$SELECT post_journal_entry(
         '{"date":"2026-09-16","description":"par un lecteur","status":"draft"}'::jsonb,
         '[{"account_code":"601000","debit":10,"credit":0},{"account_code":"401000","debit":0,"credit":10}]'::jsonb)$q$);
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T06', 'un lecteur ne crée pas d''écriture par post_journal_entry', v = 'REFUS', v);
END $$;

-- T07 — calculate_payslip par un lecteur (H10)
DO $$
DECLARE r record; e uuid; v text;
BEGIN
  SELECT * INTO r FROM _mk271('X1PAY');
  INSERT INTO employees (tenant_id, employee_number, first_name, last_name, hire_date, status, base_salary)
  VALUES (r.t, 'X1-01', 'Awa', 'Test', '2025-01-01', 'active', 2500) RETURNING id INTO e;
  PERFORM _qui271(r.lec);
  v := _essai271(format($q$SELECT calculate_payslip(%L::uuid, '2026-09')$q$, e));
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T07', 'un lecteur ne relance pas le calcul d''un bulletin', v = 'REFUS', v);
END $$;

-- Facture d'achat saisie par p_auteur (une ligne) ; rend son id
CREATE OR REPLACE FUNCTION _achat271(p_t uuid, p_auteur uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE s uuid; pi uuid;
BEGIN
  EXECUTE 'RESET ROLE';
  INSERT INTO suppliers (tenant_id, name) VALUES (p_t, 'Fournisseur 271') RETURNING id INTO s;
  PERFORM _qui271(p_auteur);
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status, approval_status)
  VALUES (p_t, 'F-' || left(uuid_generate_v4()::text, 8), s, 'Fournisseur 271', '2026-09-12', '2026-10-12', 'draft', 'pending')
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, vat_rate, total, vat_amount, line_order)
  VALUES (p_t, pi, 'Achat', 1, 300, 20, 300, 60, 0);
  EXECUTE 'RESET ROLE';
  RETURN pi;
END $$;

-- T08 — l'approbation est tracée
DO $$
DECLARE r record; pi uuid; cb uuid; ab uuid; err text := '—';
BEGIN
  SELECT * INTO r FROM _mk271('X1M9a');
  pi := _achat271(r.t, r.cpt);
  PERFORM _qui271(r.adm);
  BEGIN
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  EXECUTE 'SELECT created_by, approved_by FROM purchase_invoices WHERE id = $1' INTO cb, ab USING pi;
  PERFORM _rec('T08', 'l''approbation d''un achat enregistre son auteur et son approbateur',
    cb = r.cpt AND ab = r.adm, format('auteur=%s (attendu comptable) ; approbateur=%s (attendu admin) ; erreur=%s',
      cb = r.cpt, ab = r.adm, err));
EXCEPTION WHEN undefined_column THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T08', 'l''approbation d''un achat enregistre son auteur et son approbateur', false,
    'purchase_invoices.created_by n''existe pas');
END $$;

-- T09 — séparation des tâches sur l'approbation
DO $$
DECLARE r record; pi uuid; v_auteur text; v_autre text; st text;
BEGIN
  SELECT * INTO r FROM _mk271('X1M9b');
  UPDATE company_settings SET enforce_segregation = true WHERE tenant_id = r.t;
  pi := _achat271(r.t, r.cpt);
  PERFORM _qui271(r.cpt);
  v_auteur := _essai271(format($q$UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = %L$q$, pi));
  PERFORM _qui271(r.adm);
  BEGIN
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
    v_autre := 'approuvée';
  EXCEPTION WHEN OTHERS THEN v_autre := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  SELECT approval_status INTO st FROM purchase_invoices WHERE id = pi;
  PERFORM _rec('T09', 'séparation des tâches : l''auteur n''approuve pas son achat, un autre le peut',
    v_auteur LIKE 'AUTRE: Séparation%' AND st = 'approved',
    format('par l''auteur → %s ; par un autre → %s ; statut=%s', v_auteur, v_autre, st));
END $$;

-- T10 — politiques héritées (M12)
DO $$
DECLARE r record; heritees text; n_lu int; n_insere int := 0; err text := '—';
BEGIN
  SELECT string_agg(tablename || '.' || policyname, ', ') INTO heritees
  FROM pg_policies
  WHERE tablename IN ('analytic_distribution_lines', 'project_docs')
    AND (coalesce(qual, '') || coalesce(with_check, '')) !~ 'current_tenant_id\(\)';

  SELECT * INTO r FROM _mk271('X1M12');
  PERFORM _qui271(r.adm);
  BEGIN
    INSERT INTO project_docs (tenant_id, title) VALUES (r.t, 'Doc 271');
    GET DIAGNOSTICS n_insere = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT count(*) INTO n_lu FROM project_docs WHERE title = 'Doc 271';
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T10', 'plus de politique héritée (analytique, documents de projet) ; la société écrit et lit ses documents',
    heritees IS NULL AND n_insere = 1 AND n_lu = 1,
    format('héritées=%s ; inséré=%s ; relu=%s ; erreur=%s', coalesce(heritees, 'aucune'), n_insere, n_lu, err));
END $$;

RESET ROLE;
SELECT _audit_assert('271');
