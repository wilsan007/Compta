-- ============================================================
-- 273_journal_entry_validation_tests.sql — vague X2 / C4 et C14 (journaux)
-- (audit fonctionnel exécuté du 28/09/2026, décisions D-A et D-C)
--
-- MESURÉ AVANT, par le chemin de l'écran (base neuve, 245 migrations) :
--   C4  une écriture saisie naît brouillon et AUCUN chemin d'interface ne la
--       valide : « Clôturer » ne touche que `status_detail` (le statut reste
--       `draft`, sans numéro définitif, hors FEC et hors états) ;
--       la clôture d'un journal × période passait sur des brouillons, et
--       échouait dès qu'une écriture du lot était validée (une écriture
--       validée refusait même son marqueur de clôture) ;
--   C4  `createSaisieEntry` écrivait l'en-tête PUIS les lignes (non atomique)
--       et envoyait `analytic_section`, colonne inexistante : la saisie par
--       journal échouait ;
--   C14 le formulaire des journaux envoyait `racines_autorisees`,
--       `compte_attente`, `numerotation`, `reconciliation_mode` : création
--       refusée (PGRST204). D-C : racines et compte d'attente ont un effet
--       (contrôlés ici), numérotation et rapprochement n'en ont aucun (retirés).
--
-- Ce que ce fichier prouve :
--   T01 `validate_journal_entries` valide un brouillon équilibré : statut
--       `posted`, numéro définitif, auteur de la validation, verdict par pièce
--   T02 dans le même appel, le brouillon déséquilibré est refusé et NOMMÉ ;
--       il reste brouillon — un brouillon faux est possible, pas validable
--   T03 un lecteur ne valide rien (verdict de refus, statut inchangé)
--   T04 clôturer un journal × période refuse tant qu'il reste un brouillon,
--       en le nommant ; clôturer une période fiscale aussi
--   T05 une écriture validée accepte son marqueur de clôture, et RIEN d'autre
--   T06 `post_journal_entry` garde l'en-tête de la saisie (pièce, référence,
--       modèle, devise, taux, état de saisie)
--   T07 journal à racines autorisées : un compte hors racines est refusé à la
--       saisie et à la validation ; le compte d'attente du journal passe
--   T08 un compte d'attente absent du plan est refusé sur la fiche journal
--   T09 séparation des tâches (232) : l'auteur ne valide pas sa propre
--       écriture par `validate_journal_entries`, un autre comptable si
--
-- T01–T08 sont ROUGES avant la 273 (T09 : non-régression).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '273', false);
DELETE FROM _audit_results WHERE file = '273';

-- Société + lecteur + comptable ; rend (société, admin, lecteur, comptable)
CREATE OR REPLACE FUNCTION _mk273(p_nom text, OUT t uuid, OUT adm uuid, OUT lec uuid, OUT cpt uuid)
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
  INSERT INTO fiscal_periods (tenant_id, fiscal_year_id, period_number, period_label, start_date, end_date, status)
  SELECT t, id, 9, 'Septembre 2026', '2026-09-01', '2026-09-30', 'open' FROM fiscal_years WHERE tenant_id = t;
END $$;

CREATE OR REPLACE FUNCTION _qui273(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, false);
  PERFORM _as_user();
END $$;

-- Saisie par l'écran : post_journal_entry, brouillon
CREATE OR REPLACE FUNCTION _saisie273(p_desc text, p_d numeric, p_c numeric, p_journal text DEFAULT 'OD',
  p_compte_d text DEFAULT '606100', p_compte_c text DEFAULT '512000') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  r := post_journal_entry(
    jsonb_build_object('number', '', 'date', '2026-09-15', 'description', p_desc, 'journal_code', p_journal, 'status', 'draft'),
    jsonb_build_array(
      jsonb_build_object('account_code', p_compte_d, 'debit', p_d, 'credit', 0, 'line_order', 0),
      jsonb_build_object('account_code', p_compte_c, 'debit', 0, 'credit', p_c, 'line_order', 1)));
  IF NOT coalesce((r->>'success')::boolean, false) THEN RAISE EXCEPTION 'saisie refusée : %', r->>'error'; END IF;
  RETURN (r->>'entry_id')::uuid;
END $$;

-- T01 / T02 / T03
DO $$
DECLARE s record; e_ok uuid; e_ko uuid; v jsonb := '[]'; st_ok text; st_ko text; pn text; vb uuid;
  err text; v_lec jsonb; st_lec text; e_lec uuid;
BEGIN
  s := _mk273('X2C4A');
  PERFORM _qui273(s.adm);
  e_ok := _saisie273('Loyer', 1000, 1000);
  e_ko := _saisie273('Déséquilibrée', 100, 90);
  e_lec := _saisie273('Pour le lecteur', 50, 50);
  BEGIN
    EXECUTE 'SELECT validate_journal_entries($1)' INTO v USING ARRAY[e_ok, e_ko];
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  SELECT status, posting_number, validated_by INTO st_ok, pn, vb FROM journal_entries WHERE id = e_ok;
  SELECT status INTO st_ko FROM journal_entries WHERE id = e_ko;
  PERFORM _rec('T01', 'valider un brouillon équilibré : posted, numéro définitif, validateur posé, verdict rendu',
    err IS NULL AND st_ok = 'posted' AND pn IS NOT NULL AND vb = s.adm
      AND EXISTS (SELECT 1 FROM jsonb_array_elements(v) x WHERE (x->>'id')::uuid = e_ok AND (x->>'ok')::boolean),
    format('err=%s statut=%s numéro=%s validateur=%s verdicts=%s', err, st_ok, pn, vb = s.adm, left(v::text, 200)));
  PERFORM _rec('T02', 'le brouillon déséquilibré est refusé, nommé, et reste brouillon (sans bloquer l''autre)',
    err IS NULL AND st_ko = 'draft'
      AND EXISTS (SELECT 1 FROM jsonb_array_elements(v) x WHERE (x->>'id')::uuid = e_ko AND NOT (x->>'ok')::boolean
                  AND x->>'error' ~* 'équilibr' AND x->>'number' IS NOT NULL),
    format('err=%s statut=%s verdicts=%s', err, st_ko, left(v::text, 300)));

  PERFORM _qui273(s.lec);
  err := NULL;
  BEGIN
    EXECUTE 'SELECT validate_journal_entries($1)' INTO v_lec USING ARRAY[e_lec];
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  SELECT status INTO st_lec FROM journal_entries WHERE id = e_lec;
  PERFORM _rec('T03', 'un lecteur ne valide rien (refus, statut inchangé)',
    st_lec = 'draft' AND (err ~* 'permission|refus' OR (v_lec IS NOT NULL AND NOT (v_lec->0->>'ok')::boolean)),
    format('err=%s statut=%s verdict=%s', err, st_lec, left(v_lec::text, 200)));
END $$;

-- T04 — la clôture refuse les brouillons, en les nommant
DO $$
DECLARE s record; e_post uuid; e_draft uuid; per uuid; num text; err_j text; err_p text; st_p text; n_draft int;
BEGIN
  s := _mk273('X2C4B');
  SELECT id INTO per FROM fiscal_periods WHERE tenant_id = s.t;
  PERFORM _qui273(s.adm);
  e_post := _saisie273('Validée', 10, 10);
  UPDATE journal_entries SET status = 'posted' WHERE id = e_post;   -- chemin du noyau, indépendant de la 273
  e_draft := _saisie273('Oubliée', 20, 20);
  SELECT number INTO num FROM journal_entries WHERE id = e_draft;
  -- clôture du journal × période par l'écran (closeJournalPeriod)
  BEGIN
    UPDATE journal_entries SET status_detail = 'closed'
    WHERE journal_code = 'OD' AND fiscal_period_id = per AND status_detail IS DISTINCT FROM 'closed';
  EXCEPTION WHEN OTHERS THEN err_j := SQLERRM;
  END;
  BEGIN
    UPDATE fiscal_periods SET status = 'closed' WHERE id = per;
  EXCEPTION WHEN OTHERS THEN err_p := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  SELECT status INTO st_p FROM fiscal_periods WHERE id = per;
  SELECT count(*) INTO n_draft FROM journal_entries WHERE id = e_draft AND status_detail = 'closed';
  PERFORM _rec('T04', 'clôture (journal × période, puis période) refusée tant qu''il reste un brouillon, nommé',
    err_j LIKE '%' || num || '%' AND err_p LIKE '%' || num || '%' AND st_p = 'open' AND n_draft = 0,
    format('journal : %s | période : %s | statut période=%s', err_j, err_p, st_p));

END $$;

-- T05 — une écriture validée accepte son marqueur de clôture, rien d'autre
DO $$
DECLARE s record; e_post uuid; per uuid; err_close text; det text; err_mod text;
BEGIN
  s := _mk273('X2C4B2');
  SELECT id INTO per FROM fiscal_periods WHERE tenant_id = s.t;
  PERFORM _qui273(s.adm);
  e_post := _saisie273('Validée', 10, 10);
  UPDATE journal_entries SET status = 'posted' WHERE id = e_post;
  BEGIN
    UPDATE journal_entries SET status_detail = 'closed'
    WHERE journal_code = 'OD' AND fiscal_period_id = per AND status_detail IS DISTINCT FROM 'closed';
  EXCEPTION WHEN OTHERS THEN err_close := SQLERRM;
  END;
  BEGIN
    UPDATE journal_entries SET description = 'réécrite' WHERE id = e_post;
    err_mod := 'ACCEPTÉE';
  EXCEPTION WHEN OTHERS THEN err_mod := 'refusée : ' || SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  SELECT status_detail INTO det FROM journal_entries WHERE id = e_post;
  PERFORM _rec('T05', 'une écriture validée accepte son marqueur de clôture, et rien d''autre',
    err_close IS NULL AND det = 'closed' AND err_mod LIKE 'refusée%',
    format('clôture : %s (état %s) | modification du libellé : %s', coalesce(err_close, 'OK'), det, left(err_mod, 120)));
END $$;

-- T06 — l'en-tête de la saisie
DO $$
DECLARE s record; r jsonb; e record; tpl uuid;
BEGIN
  s := _mk273('X2C4C');
  INSERT INTO entry_templates (tenant_id, name, journal_code) VALUES (s.t, 'Loyer', 'OD') RETURNING id INTO tpl;
  PERFORM _qui273(s.adm);
  r := post_journal_entry(
    jsonb_build_object('number', '', 'date', '2026-09-15', 'description', 'Achat en USD', 'journal_code', 'OD',
      'status', 'draft', 'piece_number', 'FAC-USD-12', 'reference', 'REF-9', 'invoice_ref', 'INV-9',
      'entry_template_id', tpl, 'currency_code', 'USD', 'functional_currency', 'EUR',
      'exchange_rate', 0.92, 'exchange_rate_date', '2026-09-15', 'status_detail', 'printed'),
    jsonb_build_array(
      jsonb_build_object('account_code', '606100', 'debit', 92, 'credit', 0),
      jsonb_build_object('account_code', '512000', 'debit', 0, 'credit', 92)));
  EXECUTE 'RESET ROLE';
  SELECT * INTO e FROM journal_entries WHERE id = (r->>'entry_id')::uuid;
  PERFORM _rec('T06', 'post_journal_entry garde pièce, référence, modèle, devise, taux et état de saisie',
    (r->>'success')::boolean AND e.piece_number = 'FAC-USD-12' AND e.reference = 'REF-9' AND e.invoice_ref = 'INV-9'
      AND e.entry_template_id = tpl AND e.currency_code = 'USD' AND e.functional_currency = 'EUR'
      AND e.exchange_rate = 0.92 AND e.exchange_rate_date = '2026-09-15' AND e.status_detail = 'printed',
    format('rpc=%s | pièce=%s réf=%s modèle=%s devise=%s/%s taux=%s état=%s', r, e.piece_number, e.reference,
      e.entry_template_id = tpl, e.currency_code, e.functional_currency, e.exchange_rate, e.status_detail));
END $$;

-- T07 / T08 — racines autorisées et compte d'attente du journal
DO $$
DECLARE s record; r_hors jsonb; r_ok jsonb; r_att jsonb; e_hors uuid; v jsonb; err_att text; n_att int;
  cols int;
BEGIN
  SELECT count(*) INTO cols FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'journals' AND column_name = 'racines_autorisees';
  IF cols = 0 THEN
    PERFORM _rec('T07', 'journal à racines autorisées : hors racines refusé, compte d''attente accepté', false, 'colonne racines_autorisees absente');
    PERFORM _rec('T08', 'un compte d''attente absent du plan est refusé sur la fiche journal', false, 'colonne racines_autorisees absente');
    RETURN;
  END IF;
  s := _mk273('X2C14J');
  PERFORM _qui273(s.adm);
  EXECUTE $q$INSERT INTO journals (tenant_id, code, name, type, racines_autorisees, account_attente)
           VALUES ($1, 'BQ2', 'Banque 2', 'bank', '512, 411, 401 ,627', '471000')$q$ USING s.t;
  r_hors := post_journal_entry(jsonb_build_object('date', '2026-09-15', 'journal_code', 'BQ2', 'description', 'hors racines'),
    jsonb_build_array(jsonb_build_object('account_code', '606100', 'debit', 10, 'credit', 0),
                      jsonb_build_object('account_code', '512000', 'debit', 0, 'credit', 10)));
  r_ok := post_journal_entry(jsonb_build_object('date', '2026-09-15', 'journal_code', 'BQ2', 'description', 'frais bancaires'),
    jsonb_build_array(jsonb_build_object('account_code', '627000', 'debit', 10, 'credit', 0),
                      jsonb_build_object('account_code', '512000', 'debit', 0, 'credit', 10)));
  r_att := post_journal_entry(jsonb_build_object('date', '2026-09-15', 'journal_code', 'BQ2', 'description', 'à identifier'),
    jsonb_build_array(jsonb_build_object('account_code', '471000', 'debit', 10, 'credit', 0),
                      jsonb_build_object('account_code', '512000', 'debit', 0, 'credit', 10)));
  -- une écriture hors racines arrivée par un autre chemin (insertion directe) ne se valide pas
  EXECUTE 'RESET ROLE';
  e_hors := _entry(s.t, 'BQ2-DIRECT', '2026-09-15', '[{"a":"606100","d":5},{"a":"512000","c":5}]', false, 'BQ2');
  PERFORM _qui273(s.adm);
  v := validate_journal_entries(ARRAY[e_hors]);
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T07', 'journal à racines : 606 refusé (saisie et validation), 627 et le compte d''attente 471 acceptés',
    NOT (r_hors->>'success')::boolean AND r_hors->>'error' ~ '606100'
      AND (r_ok->>'success')::boolean AND (r_att->>'success')::boolean
      AND NOT (v->0->>'ok')::boolean AND v->0->>'error' ~ '606100',
    format('606 : %s | 627 : %s | 471 : %s | validation directe : %s', r_hors->>'error', r_ok->>'success', r_att->>'success', v->0->>'error'));

  PERFORM _qui273(s.adm);
  BEGIN
    EXECUTE $q$INSERT INTO journals (tenant_id, code, name, type, account_attente) VALUES ($1, 'OD2', 'OD 2', 'general', '479999')$q$ USING s.t;
    err_att := 'ACCEPTÉ';
  EXCEPTION WHEN OTHERS THEN err_att := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T08', 'un compte d''attente absent du plan est refusé sur la fiche journal',
    err_att <> 'ACCEPTÉ' AND err_att ~ '479999', err_att);
END $$;

-- T09 — séparation des tâches
DO $$
DECLARE s record; e uuid; v_auteur jsonb; v_autre jsonb; st1 text; st2 text;
BEGIN
  s := _mk273('X2C4D');
  UPDATE company_settings SET enforce_segregation = true WHERE tenant_id = s.t;
  PERFORM _qui273(s.cpt);
  e := _saisie273('Saisie du comptable', 30, 30);
  v_auteur := validate_journal_entries(ARRAY[e]);
  EXECUTE 'RESET ROLE';
  SELECT status INTO st1 FROM journal_entries WHERE id = e;
  PERFORM _qui273(s.adm);
  v_autre := validate_journal_entries(ARRAY[e]);
  EXECUTE 'RESET ROLE';
  SELECT status INTO st2 FROM journal_entries WHERE id = e;
  PERFORM _rec('T09', 'séparation des tâches : l''auteur ne valide pas sa saisie, l''administrateur si',
    st1 = 'draft' AND v_auteur->0->>'error' ~* 'séparation' AND st2 = 'posted',
    format('auteur : %s (%s) | autre : %s (%s)', v_auteur->0->>'error', st1, v_autre->0->>'ok', st2));
EXCEPTION WHEN undefined_function THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T09', 'séparation des tâches : l''auteur ne valide pas sa saisie, l''administrateur si', false, SQLERRM);
END $$;

SELECT _audit_assert('273');
