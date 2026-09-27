-- ============================================================
-- 260_single_depreciation_engine_tests.sql — vague W5 (IMMO-01 → IMMO-05, RH-04)
--
-- MESURÉ AVANT la 260, sur base neuve (234 migrations, 0 erreur) :
--   * deux immobilisations identiques amortissaient PAREIL quelle que soit la
--     méthode choisie (`depreciation_method` n'était lue par aucun moteur) ;
--   * rien ne bornait la dotation à l'exercice : la date du jour décidait ;
--   * « units_of_production » était acceptée puis amortie LINÉAIREMENT, en
--     silence ;
--   * le lot du front sautait les échecs (`console.error`) et rendait une liste
--     partielle comme un succès ;
--   * le pointage écrivait ses heures supplémentaires avec un MONTANT NUL.
--
-- Chaque scénario est ROUGE sur la base sans la 260, et vert avec elle.
-- ============================================================

\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '260', false);
DELETE FROM _audit_results WHERE file = '260';

-- Exercice maîtrisé (statut choisi) : la 260 refuse une dotation d'exercice clos
CREATE OR REPLACE FUNCTION _mk_year260(t uuid, p_code text, p_status text DEFAULT 'open')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE fy uuid;
BEGIN
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = p_code;
  IF fy IS NULL THEN
    INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
    VALUES (t, p_code, (p_code || '-01-01')::date, (p_code || '-12-31')::date, p_status)
    RETURNING id INTO fy;
  END IF;
  RETURN fy;
END $$;

-- Immobilisation telle que l'écran la crée, méthode comprise
CREATE OR REPLACE FUNCTION _mk_asset260(t uuid, p_code text, p_value numeric, p_years int,
  p_method text, p_date date DEFAULT DATE '2025-01-01', p_dep_acc text DEFAULT NULL,
  p_exp_acc text DEFAULT NULL, p_status text DEFAULT 'active', p_residual numeric DEFAULT 0)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE fa uuid;
BEGIN
  INSERT INTO fixed_assets (tenant_id, name, code, category, purchase_date, purchase_value,
    residual_value, useful_life_years, depreciation_method, status, current_value,
    account_depreciation_code, account_expense_depreciation_code)
  VALUES (t, 'Immo ' || p_code, p_code, 'materiel', p_date, p_value, p_residual,
    p_years, p_method, p_status, p_value, p_dep_acc, p_exp_acc)
  RETURNING id INTO fa;
  RETURN fa;
END $$;
-- ── T01 — IMMO-04 : la méthode d'amortissement est LUE ──────────────────────
-- Deux immobilisations de 12 000 sur 5 ans, même date, seule la méthode change :
-- linéaire 2 400 ; dégressif (coefficient 2) 4 800. Avant la 260 : 2 400 pour
-- les deux — le choix de l'écran ne servait à rien.
DO $$
DECLARE
  t uuid := _mk_tenant('W5T01', false);
  fy uuid; a_lin uuid; a_deg uuid; m_lin numeric; m_deg numeric;
BEGIN
  PERFORM _as_user();
  fy := _mk_year260(t, '2026', 'open');
  a_lin := _mk_asset260(t, 'T01-LIN', 12000, 5, 'straight_line');
  a_deg := _mk_asset260(t, 'T01-DEG', 12000, 5, 'declining_balance');
  BEGIN
    PERFORM generate_depreciation_entry(a_lin, fy);
    PERFORM generate_depreciation_entry(a_deg, fy);
    SELECT amount INTO m_lin FROM asset_depreciations WHERE asset_id = a_lin AND tenant_id = t;
    SELECT amount INTO m_deg FROM asset_depreciations WHERE asset_id = a_deg AND tenant_id = t;
    PERFORM _rec('T01',
      'la méthode est LUE : linéaire 2 400, dégressif 4 800 sur la même immobilisation',
      m_lin = 2400 AND m_deg = 4800,
      format('linéaire=%s (2 400 attendu), dégressif=%s (4 800 attendu)', m_lin, m_deg));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T01',
      'la méthode est LUE : linéaire 2 400, dégressif 4 800 sur la même immobilisation',
      false, SQLERRM);
  END;
END $$;



-- ── T02 — IMMO-01/IMMO-03 : deux exercices, et le passé ne bouge plus ──────
-- Dégressif 12 000 / 5 ans : 2026 → 4 800 (cumul 4 800, VNC 7 200) ; 2027 →
-- 2 880 (cumul 7 680, VNC 4 320). La dotation de 2026 garde son montant et son
-- numéro d'écriture après celle de 2027 : le cumul vient de l'HISTORIQUE, il
-- ne se recalcule pas à partir de la date du jour.
DO $$
DECLARE
  t uuid := _mk_tenant('W5T02', false);
  fy26 uuid; fy27 uuid; a uuid;
  d26 record; d27 record; vnc numeric; n_ecritures int; numero26 text;
BEGIN
  PERFORM _as_user();
  fy26 := _mk_year260(t, '2026', 'open');
  fy27 := _mk_year260(t, '2027', 'open');
  a := _mk_asset260(t, 'T02-DEG', 12000, 5, 'declining_balance');
  BEGIN
    PERFORM generate_depreciation_entry(a, fy26);
    SELECT amount, cumulative_amount, net_book_value, entry_number INTO d26
      FROM asset_depreciations WHERE asset_id = a AND tenant_id = t AND fiscal_year_code = '2026';
    numero26 := d26.entry_number;

    PERFORM generate_depreciation_entry(a, fy27);
    SELECT amount, cumulative_amount, net_book_value INTO d27
      FROM asset_depreciations WHERE asset_id = a AND tenant_id = t AND fiscal_year_code = '2027';
    SELECT current_value INTO vnc FROM fixed_assets WHERE id = a;
    SELECT count(*) INTO n_ecritures FROM journal_entries
      WHERE tenant_id = t AND reference LIKE 'AMORT:' || a || ':%';
    SELECT entry_number INTO numero26 FROM asset_depreciations
      WHERE asset_id = a AND tenant_id = t AND fiscal_year_code = '2026';

    PERFORM _rec('T02',
      'deux exercices dégressifs : 4 800 puis 2 880 (cumul 7 680, VNC 4 320), la dotation du 1er exercice intacte',
      d26.amount = 4800 AND d26.cumulative_amount = 4800 AND d26.net_book_value = 7200
        AND d27.amount = 2880 AND d27.cumulative_amount = 7680 AND d27.net_book_value = 4320
        AND vnc = 4320 AND n_ecritures = 2,
      format('2026 : dotation=%s cumul=%s VNC=%s ; 2027 : dotation=%s cumul=%s VNC=%s ; VNC fiche=%s ; écritures=%s',
        d26.amount, d26.cumulative_amount, d26.net_book_value,
        d27.amount, d27.cumulative_amount, d27.net_book_value, vnc, n_ecritures));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02',
      'deux exercices dégressifs : 4 800 puis 2 880 (cumul 7 680, VNC 4 320), la dotation du 1er exercice intacte',
      false, SQLERRM);
  END;
END $$;

-- ── T03 — IMMO-03 : l'exercice clos est refusé PAR LE MOTEUR ────────────────
-- Le refus doit être celui du moteur (« ne se recalcule pas »), pas celui du
-- noyau comptable au moment de l'insertion : c'est ce qui permet au lot de
-- rendre un verdict par immobilisation. Rien n'est écrit, la valeur de clôture
-- ne bouge pas. Avant la 260, le moteur TENTAIT l'écriture (message du noyau :
-- « Exercice 2025 clos — écriture interdite »).
DO $$
DECLARE
  t uuid := _mk_tenant('W5T03', false);
  fy uuid; a uuid;
  refus_moteur boolean := false; msg text := '—';
  refus_lot boolean := false; msg_lot text := '—';
  vnc numeric; n_hist int; verdict jsonb;
BEGIN
  PERFORM _as_user();
  fy := _mk_year260(t, '2025', 'closed');
  a := _mk_asset260(t, 'T03-CLOS', 12000, 5, 'linear', DATE '2025-01-01');
  BEGIN
    BEGIN
      PERFORM generate_depreciation_entry(a, fy);
    EXCEPTION WHEN OTHERS THEN
      msg := SQLERRM;
      refus_moteur := SQLERRM LIKE '%ne se recalcule pas%';
    END;
    BEGIN
      verdict := generate_depreciation_entries(fy);
    EXCEPTION WHEN OTHERS THEN
      msg_lot := SQLERRM;
      refus_lot := SQLERRM LIKE '%exercice clos%';
    END;
    SELECT current_value INTO vnc FROM fixed_assets WHERE id = a;
    SELECT count(*) INTO n_hist FROM asset_depreciations WHERE asset_id = a AND tenant_id = t;
    PERFORM _rec('T03',
      'exercice clos : la dotation est refusée par le moteur (message nommé), rien n''est écrit, la valeur de clôture est intacte',
      refus_moteur AND refus_lot AND vnc = 12000 AND n_hist = 0 AND verdict IS NULL,
      format('refus moteur=%s (%s), refus du lot=%s (%s), VNC=%s (12 000 attendue), historique=%s ligne(s)',
        refus_moteur, left(msg, 90), refus_lot, left(msg_lot, 90), vnc, n_hist));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T03',
      'exercice clos : la dotation est refusée par le moteur (message nommé), rien n''est écrit, la valeur de clôture est intacte',
      false, SQLERRM);
  END;
END $$;

-- ── T04 — IMMO-04 : « units_of_production » est RETIRÉE, pas simulée ───────
-- Le plan offrait deux issues : l'implémenter ou la retirer de l'écran. La
-- fiche ne porte aucun compteur d'unités produites : elle est RETIRÉE, et le
-- moteur le DIT. Une méthode inconnue est refusée aussi — plus de linéaire
-- silencieux. Avant la 260 : les deux étaient amorties linéairement (2 400).
DO $$
DECLARE
  t uuid := _mk_tenant('W5T04', false);
  fy uuid; a_up uuid; a_zz uuid;
  refus_up boolean := false; refus_zz boolean := false;
  msg_up text := '—'; msg_zz text := '—'; n_hist int;
BEGIN
  PERFORM _as_user();
  fy := _mk_year260(t, '2026', 'open');
  a_up := _mk_asset260(t, 'T04-UP', 12000, 5, 'units_of_production');
  a_zz := _mk_asset260(t, 'T04-ZZ', 12000, 5, 'methode_imaginaire');
  BEGIN
    BEGIN
      PERFORM generate_depreciation_entry(a_up, fy);
    EXCEPTION WHEN OTHERS THEN
      msg_up := SQLERRM; refus_up := SQLERRM LIKE '%RETIRÉE%';
    END;
    BEGIN
      PERFORM generate_depreciation_entry(a_zz, fy);
    EXCEPTION WHEN OTHERS THEN
      msg_zz := SQLERRM; refus_zz := SQLERRM LIKE '%inconnue%';
    END;
    SELECT count(*) INTO n_hist FROM asset_depreciations
      WHERE tenant_id = t AND asset_id IN (a_up, a_zz);
    PERFORM _rec('T04',
      'units_of_production refusée (méthode RETIRÉE) et méthode inconnue refusée : aucune dotation silencieuse',
      refus_up AND refus_zz AND n_hist = 0,
      format('units_of_production : refus=%s (%s) ; méthode inconnue : refus=%s (%s) ; historique=%s ligne(s)',
        refus_up, left(msg_up, 80), refus_zz, left(msg_zz, 80), n_hist));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04',
      'units_of_production refusée (méthode RETIRÉE) et méthode inconnue refusée : aucune dotation silencieuse',
      false, SQLERRM);
  END;
END $$;

-- ── T05 — IMMO-05 : le lot dit les échecs, PAR IMMOBILISATION ──────────────
-- Quatre immobilisations : une qui passe, une sans objet (valeur nulle), une
-- dont le compte d'amortissement n'est pas au plan, une en méthode retirée.
-- Le lot ne peut plus rendre « 3 traitées » comme un succès : il nomme les
-- deux échecs et compte les réussites. Avant la 260, le lot n'existe pas côté
-- base (c'est le `try/catch` du front qui avalait les échecs).
DO $$
DECLARE
  t uuid := _mk_tenant('W5T05', false);
  fy uuid; a_ok uuid; a_zero uuid; a_cpt uuid; a_up uuid;
  verdict jsonb; echecs int; msgs text;
BEGIN
  PERFORM _as_user();
  fy := _mk_year260(t, '2026', 'open');
  a_ok   := _mk_asset260(t, 'T05-OK',   12000, 5, 'straight_line');
  a_zero := _mk_asset260(t, 'T05-ZERO',     0, 5, 'straight_line');
  a_cpt  := _mk_asset260(t, 'T05-CPT',  12000, 5, 'straight_line', DATE '2025-01-01', '289999', '681200');
  a_up   := _mk_asset260(t, 'T05-UP',   12000, 5, 'units_of_production');
  BEGIN
    verdict := generate_depreciation_entries(fy);
    echecs := jsonb_array_length(verdict -> 'echecs');
    SELECT string_agg(x ->> 'message', ' | ') INTO msgs
      FROM jsonb_array_elements(verdict -> 'echecs') x;
    PERFORM _rec('T05',
      'le lot rend un verdict par immobilisation : 4 examinées, 1 comptabilisée, 1 sans objet, 2 échecs NOMMÉS',
      (verdict ->> 'total')::int = 4
        AND (verdict ->> 'comptabilisees')::int = 1
        AND (verdict ->> 'sans_objet')::int = 1
        AND echecs = 2
        AND msgs LIKE '%289999%' AND msgs LIKE '%RETIRÉE%',
      format('total=%s comptabilisées=%s sans objet=%s échecs=%s | %s',
        verdict ->> 'total', verdict ->> 'comptabilisees', verdict ->> 'sans_objet', echecs, left(msgs, 140)));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T05',
      'le lot rend un verdict par immobilisation : 4 examinées, 1 comptabilisée, 1 sans objet, 2 échecs NOMMÉS',
      false, SQLERRM);
  END;
END $$;

-- ── T06 — NON-RÉGRESSION : le linéaire de 211/226 ne change pas ────────────
-- 12 000 sur 5 ans → 2 400, D 681200 / C 281000, écriture validée et numérotée.
-- Prorata temporis en jours l'année d'acquisition : acquisition le 01/07/2026 →
-- 2 400 × 184 / 365 = 1 209,86. (Vert avant comme après : ce scénario est là
-- pour que la vague ne casse pas ce qui marchait.)
DO $$
DECLARE
  t uuid := _mk_tenant('W5T06', false);
  fy uuid; a uuid; b uuid;
  r record; r2 record; st text;
BEGIN
  PERFORM _as_user();
  fy := _mk_year260(t, '2026', 'open');
  a := _mk_asset260(t, 'T06-LIN', 12000, 5, 'straight_line');
  b := _mk_asset260(t, 'T06-PRO', 12000, 5, 'linear', DATE '2026-07-01');
  BEGIN
    PERFORM generate_depreciation_entry(a, fy);
    PERFORM generate_depreciation_entry(b, fy);
    SELECT ad.amount, ad.net_book_value, je.status, je.posting_number IS NOT NULL AS numerote
      INTO r FROM asset_depreciations ad
      JOIN journal_entries je ON je.tenant_id = ad.tenant_id AND je.reference = 'AMORT:' || ad.asset_id || ':2026'
      WHERE ad.asset_id = a AND ad.tenant_id = t;
    SELECT ad.amount, ad.net_book_value INTO r2
      FROM asset_depreciations ad WHERE ad.asset_id = b AND ad.tenant_id = t;
    SELECT status INTO st FROM fixed_assets WHERE id = a;
    PERFORM _rec('T06',
      'linéaire non régressé : 2 400 sur l''année pleine, 1 209,86 avec prorata au 01/07, écriture validée et numérotée',
      r.amount = 2400 AND r.net_book_value = 9600 AND r.status = 'posted' AND r.numerote
        AND r2.amount = 1209.86 AND r2.net_book_value = 10790.14 AND st = 'active',
      format('année pleine : dotation=%s VNC=%s statut=%s numérotée=%s ; prorata : dotation=%s VNC=%s',
        r.amount, r.net_book_value, r.status, r.numerote, r2.amount, r2.net_book_value));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T06',
      'linéaire non régressé : 2 400 sur l''année pleine, 1 209,86 avec prorata au 01/07, écriture validée et numérotée',
      false, SQLERRM);
  END;
END $$;

-- ── T07 — IMMO-02 : le lot COMPTABILISE, et ne double pas ──────────────────
-- Deux immobilisations actives : deux écritures validées portant la référence
-- d'idempotence. Un second appel rend les MÊMES écritures (le moteur les
-- reconnaît) et n'en crée aucune de plus.
DO $$
DECLARE
  t uuid := _mk_tenant('W5T07', false);
  fy uuid; a uuid; b uuid; v1 jsonb; v2 jsonb; n int; validees int;
BEGIN
  PERFORM _as_user();
  fy := _mk_year260(t, '2026', 'open');
  a := _mk_asset260(t, 'T07-A', 12000, 5, 'straight_line');
  b := _mk_asset260(t, 'T07-B',  6000, 5, 'straight_line');
  BEGIN
    v1 := generate_depreciation_entries(fy);
    SELECT count(*), count(*) FILTER (WHERE status = 'posted') INTO n, validees
      FROM journal_entries WHERE tenant_id = t AND reference LIKE 'AMORT:%';
    v2 := generate_depreciation_entries(fy);
    SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND reference LIKE 'AMORT:%';
    PERFORM _rec('T07',
      'le lot comptabilise (2 écritures validées) et un second appel rend les mêmes, sans doublon',
      (v1 ->> 'comptabilisees')::int = 2 AND validees = 2 AND (v2 ->> 'comptabilisees')::int = 2 AND n = 2
        AND (v1 -> 'echecs') = '[]'::jsonb,
      format('1er appel=%s comptabilisées, 2 validées ; 2e appel=%s ; écritures=%s',
        v1 ->> 'comptabilisees', v2 ->> 'comptabilisees', n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T07',
      'le lot comptabilise (2 écritures validées) et un second appel rend les mêmes, sans doublon',
      false, SQLERRM);
  END;
END $$;

-- ── T08 — UN SEUL MOTEUR : le second a disparu du schéma ───────────────────
-- `calculate_depreciation` était la RPC historique que le front appelait : elle
-- n'existe plus, aucun écran ne peut plus produire un plan en marge du moteur.
DO $$
DECLARE
  rpc_hist text; moteur text; lot text; taux text;
BEGIN
  PERFORM _as_user();
  rpc_hist := to_regprocedure('public.calculate_depreciation(uuid,text)')::text;
  moteur   := to_regprocedure('public.generate_depreciation_entry(uuid,uuid)')::text;
  lot      := to_regprocedure('public.generate_depreciation_entries(uuid)')::text;
  taux     := to_regprocedure('public.payroll_overtime_amount(uuid,uuid,numeric)')::text;
  PERFORM _rec('T08',
    'un seul point d''entrée d''amortissement : calculate_depreciation supprimée, le moteur et son lot présents',
    rpc_hist IS NULL AND moteur IS NOT NULL AND lot IS NOT NULL AND taux IS NOT NULL,
    format('calculate_depreciation=%s ; generate_depreciation_entry=%s ; generate_depreciation_entries=%s ; payroll_overtime_amount=%s',
      COALESCE(rpc_hist, 'supprimée'), COALESCE(moteur, 'absente'), COALESCE(lot, 'absent'), COALESCE(taux, 'absent')));
END $$;

-- ── T09 — RH-04 : le pointage pose un MONTANT, pas des heures à zéro ───────
-- Salarié à 3 000 € sur 35 h : diviseur 151,6667 → 19,7802 l'heure ; majoration
-- par défaut 1,25 → 24,7253. Le pointage mesure 90 minutes au-delà de l'horaire
-- prévu (17 h → 18 h 30) : 1,50 h, soit 37,09 €. Avant la 260, la ligne portait
-- `unit_price = 0` et `amount = 0` — la paie comptait des heures qui ne
-- valaient rien.
DO $$
DECLARE
  t uuid := _mk_tenant('W5T09', false);
  e uuid; ts uuid; n int; q numeric; pu numeric; mt numeric; src text;
BEGIN
  PERFORM _as_user();
  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours,
                         default_start_time, default_end_time)
  VALUES (t, 'Amina W5T09', 'w5t09@audit.test', 'active', 3000, 35, '09:00', '17:00')
  RETURNING id INTO e;

  INSERT INTO timesheets (tenant_id, employee_id, date, scheduled_start, scheduled_end,
                          arrival_time, departure_time)
  VALUES (t, e, DATE '2026-01-15', '09:00', '17:00',
          TIMESTAMPTZ '2026-01-15 09:00', TIMESTAMPTZ '2026-01-15 18:30')
  RETURNING id INTO ts;

  UPDATE timesheets SET status = 'approved' WHERE id = ts AND tenant_id = t;

  SELECT count(*), max(quantity), max(unit_price), max(amount), max(source)
    INTO n, q, pu, mt, src
  FROM payroll_variable_elements
  WHERE tenant_id = t AND source_id = ts AND element_type = 'overtime';

  PERFORM _rec('T09',
    'heures supplémentaires : 1,50 h mesurée sur l''horaire prévu, taux horaire majoré et montant non nul (37,09 €)',
    n = 1 AND q = 1.5 AND pu BETWEEN 24.72 AND 24.73 AND mt BETWEEN 37.08 AND 37.10 AND COALESCE(src, '') = 'timesheet',
    format('lignes=%s quantité=%s taux=%s montant=%s source=%s', n, q, pu, mt, src));
END $$;

-- ── T10 — RH-04 : la majoration est un PARAMÈTRE, et une seule ligne ───────
-- La société porte MAJORATION_HEURES_SUP = 1,5 : 19,7802 × 1,5 = 29,6703, et
-- 1,50 h valent 44,51 €. Deux pointages = deux lignes (une par document
-- source) ; repasser le premier par « rejeté puis approuvé » met la ligne à
-- jour, elle ne se dédouble pas.
DO $$
DECLARE
  t uuid := _mk_tenant('W5T10', false);
  e uuid; ts1 uuid; ts2 uuid; n int; mt numeric; pu numeric; refus text := '—'; maj numeric;
BEGIN
  PERFORM _as_user();
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'MAJORATION_HEURES_SUP', 1.5, CURRENT_DATE - 1);

  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours,
                         default_start_time, default_end_time)
  VALUES (t, 'Bilal W5T10', 'w5t10@audit.test', 'active', 3000, 35, '09:00', '17:00')
  RETURNING id INTO e;

  INSERT INTO timesheets (tenant_id, employee_id, date, scheduled_start, scheduled_end,
                          arrival_time, departure_time)
  VALUES (t, e, DATE '2026-01-15', '09:00', '17:00',
          TIMESTAMPTZ '2026-01-15 09:00', TIMESTAMPTZ '2026-01-15 18:30')
  RETURNING id INTO ts1;
  BEGIN
    UPDATE timesheets SET status = 'approved' WHERE id = ts1 AND tenant_id = t;
  EXCEPTION WHEN OTHERS THEN refus := SQLERRM;
  END;

  INSERT INTO timesheets (tenant_id, employee_id, date, scheduled_start, scheduled_end,
                          arrival_time, departure_time)
  VALUES (t, e, DATE '2026-01-16', '09:00', '17:00',
          TIMESTAMPTZ '2026-01-16 09:00', TIMESTAMPTZ '2026-01-16 18:30')
  RETURNING id INTO ts2;
  UPDATE timesheets SET status = 'approved' WHERE id = ts2 AND tenant_id = t;

  -- Le premier pointage redevient approuvé : la ligne est reprise, pas doublée.
  UPDATE timesheets SET status = 'rejected' WHERE id = ts1 AND tenant_id = t;
  UPDATE timesheets SET status = 'approved' WHERE id = ts1 AND tenant_id = t;

  SELECT count(*), max(amount), max(unit_price) INTO n, mt, pu
  FROM payroll_variable_elements
  WHERE tenant_id = t AND element_type = 'overtime';

  -- La porte du front rend LA majoration de la société : les écrans de
  -- simulation n'ont plus de constante légale à eux.
  maj := payroll_overtime_majoration();

  PERFORM _rec('T10',
    'la majoration est un paramètre (1,5 → 44,51 €), le front la LIT, et un pointage ne produit qu''une ligne, même réapprouvé',
    refus = '—' AND n = 2 AND pu BETWEEN 29.66 AND 29.68 AND mt BETWEEN 44.50 AND 44.52 AND maj = 1.5,
    format('refus=%s ; lignes=%s (2 attendues) ; taux=%s ; montant=%s ; majoration lue par le front=%s (1,5 attendue)',
      refus, n, pu, mt, maj));
END $$;

SELECT _audit_assert('260');


