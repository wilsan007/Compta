-- ============================================================
-- 211_asset_deferred_tests.sql — R-01 (phase 1 du reste-à-faire du 22/09)
--
-- Amortissements, écarts de lettrage et charges/produits constatés d'avance :
-- trois fonctions cassaient depuis la 187 (en-tête inséré en `posted`, refusé
-- par le noyau strict) et imputaient des comptes fictifs (`6_____`, `280000`).
-- Scénarios : écriture en brouillard puis validation, comptes du plan,
-- équilibre, idempotence, refus explicites.
--
-- Amortissement linéaire : 12 000 sur 5 ans → dotation annuelle 2 400,
-- D 681200 / C 281000 ; prorata temporis en jours la première année.
-- Écart de règlement : D 665000 / C 411000 (escompte), D 411000 / C 766000 (gain).
-- CCA : D 486000 / C 606000 puis reprises mensuelles D 606000 / C 486000.
-- PCA : D 707000 / C 487000 puis reprises D 487000 / C 707000.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '211', false);
DELETE FROM _audit_results WHERE file = '211';

-- Immobilisation telle que l'écran la crée (FixedAssetsPage)
CREATE OR REPLACE FUNCTION _mk_asset(t uuid, p_name text, p_date date, p_value numeric, p_years int,
  p_dep_acc text DEFAULT NULL, p_exp_acc text DEFAULT NULL, p_status text DEFAULT 'active')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a uuid;
BEGIN
  INSERT INTO fixed_assets (tenant_id, name, code, category, purchase_date, purchase_value,
    useful_life_years, residual_value, status, depreciation_method,
    account_depreciation_code, account_expense_depreciation_code)
  VALUES (t, p_name, p_name, 'materiel', p_date, p_value, p_years, 0, p_status, 'straight_line',
    p_dep_acc, p_exp_acc)
  RETURNING id INTO a;
  RETURN a;
END $$;

-- Régularisation telle que l'écran la crée (RegularizationPage, type CCA/PCA)
CREATE OR REPLACE FUNCTION _mk_reg(t uuid, p_type text, p_account text, p_start date, p_end date, p_amount numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid;
BEGIN
  INSERT INTO regularization_entries (tenant_id, type, fiscal_year_id, account_code, description,
    start_date, end_date, amount, used_amount, remaining_amount, status)
  SELECT t, p_type, (SELECT id FROM fiscal_years WHERE tenant_id = t AND status = 'open' ORDER BY start_date LIMIT 1),
    p_account, p_type || ' ' || p_account, p_start, p_end, p_amount, 0, p_amount, 'pending'
  RETURNING id INTO r;
  RETURN r;
END $$;

-- Un exercice de plus, pour les reprises qui débordent sur l'année suivante
CREATE OR REPLACE FUNCTION _mk_year(t uuid, p_code text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE y uuid;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
  VALUES (t, p_code, (p_code || '-01-01')::date, (p_code || '-12-31')::date, 'open')
  RETURNING id INTO y;
  RETURN y;
END $$;
-- A01 — dotation annuelle : 12 000 sur 5 ans = 2 400, D 681200 / C 281000, validée
DO $$
DECLARE t uuid := _mk_tenant('A01'); a uuid; fy uuid; e uuid; r record;
BEGIN
  PERFORM _as_user();
  BEGIN
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
    a := _mk_asset(t, 'Camion', '2025-01-01', 12000, 5);
    e := generate_depreciation_entry(a, fy);
    SELECT je.status, je.posting_number IS NOT NULL AS numbered,
           COALESCE(sum(jl.debit), 0) AS d, COALESCE(sum(jl.credit), 0) AS c,
           COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '681200'), 0) AS d681,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '281000'), 0) AS c281,
           count(*) AS n
      INTO r FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.id = e GROUP BY je.status, je.posting_number;
    PERFORM _rec('A01', 'dotation 12 000/5 ans = 2 400 : D 681200 / C 281000, écriture validée et équilibrée',
      r.status = 'posted' AND r.numbered AND r.d = 2400 AND r.c = 2400 AND r.d681 = 2400 AND r.c281 = 2400 AND r.n = 2,
      format('statut=%s numérotée=%s D=%s C=%s D681200=%s C281000=%s lignes=%s', r.status, r.numbered, r.d, r.c, r.d681, r.c281, r.n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A01', 'dotation 12 000/5 ans = 2 400 : D 681200 / C 281000, écriture validée et équilibrée', false, SQLERRM);
  END;
END $$;

-- A02 — prorata temporis : acquise le 01/07/2026, la dotation 2026 vaut 184/365 de l'année
DO $$
DECLARE t uuid := _mk_tenant('A02'); a uuid; fy uuid; e uuid; attendu numeric; obtenu numeric;
BEGIN
  PERFORM _as_user();
  BEGIN
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
    a := _mk_asset(t, 'Presse', '2026-07-01', 12000, 5);
    e := generate_depreciation_entry(a, fy);
    attendu := round(round(12000::numeric / 5, 2) * 184 / 365, 2);
    SELECT COALESCE(sum(debit), 0) INTO obtenu FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('A02', 'prorata temporis en jours la première année (01/07 → 31/12)',
      obtenu = attendu, format('dotation=%s attendu=%s', obtenu, attendu));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A02', 'prorata temporis en jours la première année (01/07 → 31/12)', false, SQLERRM);
  END;
END $$;

-- A03 — les comptes portés par l'immobilisation sont ceux utilisés
DO $$
DECLARE t uuid := _mk_tenant('A03'); a uuid; fy uuid; e uuid; r record;
BEGIN
  PERFORM _as_user();
  BEGIN
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
    a := _mk_asset(t, 'Mobilier', '2025-01-01', 1000, 10, '281800', '681240');
    e := generate_depreciation_entry(a, fy);
    SELECT COALESCE(sum(debit) FILTER (WHERE account_code = '681240'), 0) AS d,
           COALESCE(sum(credit) FILTER (WHERE account_code = '281800'), 0) AS c
      INTO r FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('A03', 'comptes de l''immobilisation respectés (D 681240 / C 281800)',
      r.d = 100 AND r.c = 100, format('D681240=%s C281800=%s', r.d, r.c));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A03', 'comptes de l''immobilisation respectés (D 681240 / C 281800)', false, SQLERRM);
  END;
END $$;

-- A04 — aucun compte fictif : un compte absent du plan est refusé, avec son nom
DO $$
DECLARE t uuid := _mk_tenant('A04'); a uuid; fy uuid; refus boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
    a := _mk_asset(t, 'Machine', '2025-01-01', 1000, 5, '289999', '681200');
    BEGIN
      PERFORM generate_depreciation_entry(a, fy);
    EXCEPTION WHEN OTHERS THEN refus := SQLERRM LIKE '%289999%'; END;
    PERFORM _rec('A04', 'compte d''amortissement absent du plan : refus explicite (pas de compte fictif)',
      refus, 'refus=' || refus);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A04', 'compte d''amortissement absent du plan : refus explicite (pas de compte fictif)', false, SQLERRM);
  END;
END $$;

-- A05 — idempotence : un second appel ne crée pas de deuxième écriture
DO $$
DECLARE t uuid := _mk_tenant('A05'); a uuid; fy uuid; e1 uuid; e2 uuid; n int;
BEGIN
  PERFORM _as_user();
  BEGIN
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
    a := _mk_asset(t, 'Serveur', '2025-01-01', 12000, 5);
    e1 := generate_depreciation_entry(a, fy);
    e2 := generate_depreciation_entry(a, fy);
    SELECT count(*) INTO n FROM journal_entries je
      WHERE je.tenant_id = t AND je.reference = 'AMORT:' || a || ':' || '2026';
    PERFORM _rec('A05', 'dotation déjà comptabilisée : même écriture rendue, aucun doublon',
      e1 IS NOT NULL AND e1 = e2 AND n = 1, format('e1=%s e2=%s écritures=%s', e1, e2, n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A05', 'dotation déjà comptabilisée : même écriture rendue, aucun doublon', false, SQLERRM);
  END;
END $$;

-- A06 — historique de l'immobilisation et valeur nette mis à jour
DO $$
DECLARE t uuid := _mk_tenant('A06'); a uuid; fy uuid; d record; cv numeric; st text;
BEGIN
  PERFORM _as_user();
  BEGIN
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
    a := _mk_asset(t, 'Bateau', '2025-01-01', 12000, 5);
    PERFORM generate_depreciation_entry(a, fy);
    SELECT amount, cumulative_amount, net_book_value, fiscal_year_code, period, entry_number
      INTO d FROM asset_depreciations WHERE asset_id = a AND tenant_id = t;
    SELECT current_value, status INTO cv, st FROM fixed_assets WHERE id = a;
    PERFORM _rec('A06', 'dotation 2 400 enregistrée à l''historique ; valeur nette 9 600',
      d.amount = 2400 AND d.cumulative_amount = 2400 AND d.net_book_value = 9600
        AND d.fiscal_year_code = '2026' AND d.period = 12 AND d.entry_number IS NOT NULL AND cv = 9600,
      format('dotation=%s cumul=%s VNC=%s exercice=%s période=%s numéro=%s current_value=%s statut=%s',
        d.amount, d.cumulative_amount, d.net_book_value, d.fiscal_year_code, d.period, d.entry_number, cv, st));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A06', 'dotation 2 400 enregistrée à l''historique ; valeur nette 9 600', false, SQLERRM);
  END;
END $$;

-- A07 — immobilisation sortie : plus de dotation
DO $$
DECLARE t uuid := _mk_tenant('A07'); a uuid; fy uuid; refus boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
    a := _mk_asset(t, 'Vieux camion', '2025-01-01', 12000, 5, NULL, NULL, 'disposed');
    BEGIN
      PERFORM generate_depreciation_entry(a, fy);
    EXCEPTION WHEN OTHERS THEN refus := SQLERRM LIKE '%disposed%'; END;
    PERFORM _rec('A07', 'immobilisation sortie (disposed) : dotation refusée',
      refus, 'refus=' || refus);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A07', 'immobilisation sortie (disposed) : dotation refusée', false, SQLERRM);
  END;
END $$;

-- B01 — écart de règlement (escompte) : D 665000 / C 411000, validée, groupe clos
DO $$
DECLARE t uuid := _mk_tenant('B01'); e uuid; g uuid; res uuid; r record;
BEGIN
  PERFORM _as_user();
  BEGIN
    e := _entry(t, 'B01', DATE '2026-03-01',
      '[{"a":"411000","d":100,"t":"CLI1"},{"a":"707000","c":100}]');
    INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, total_debit, total_credit, status)
    VALUES (t, 'L-B01', DATE '2026-03-01', 100, 95, 'open') RETURNING id INTO g;
    UPDATE journal_lines SET lettrage_code = 'L-B01', lettrage_group_id = g
      WHERE journal_id = e AND account_code = '411000';

    res := generate_residual_entry(g, 'escompte', 5);
    SELECT je.status, COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '665000'), 0) AS d665,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '411000'), 0) AS c411,
           COALESCE(sum(jl.debit), 0) AS d, COALESCE(sum(jl.credit), 0) AS c
      INTO r FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.id = res GROUP BY je.status;
    PERFORM _rec('B01', 'escompte de 5 : D 665000 / C 411000, écriture validée et équilibrée, groupe clos',
      r.d665 = 5 AND r.c411 = 5 AND r.d = r.c AND r.status = 'posted'
        AND (SELECT status FROM lettrage_groups WHERE id = g) = 'closed',
      format('D665000=%s C411000=%s D=%s C=%s statut=%s', r.d665, r.c411, r.d, r.c, r.status));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('B01', 'escompte de 5 : D 665000 / C 411000, écriture validée et équilibrée, groupe clos', false, SQLERRM);
  END;
END $$;

-- B02 — gain de change : D 411000 / C 766000
DO $$
DECLARE t uuid := _mk_tenant('B02'); e uuid; g uuid; res uuid; r record;
BEGIN
  PERFORM _as_user();
  BEGIN
    e := _entry(t, 'B02', DATE '2026-03-01',
      '[{"a":"411000","d":100,"t":"CLI1"},{"a":"707000","c":100}]');
    INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, total_debit, total_credit, status)
    VALUES (t, 'L-B02', DATE '2026-03-01', 100, 102, 'open') RETURNING id INTO g;
    UPDATE journal_lines SET lettrage_code = 'L-B02', lettrage_group_id = g
      WHERE journal_id = e AND account_code = '411000';

    res := generate_residual_entry(g, 'gain_change', 2);
    SELECT je.status, COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '411000'), 0) AS d411,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '766000'), 0) AS c766
      INTO r FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.id = res GROUP BY je.status;
    PERFORM _rec('B02', 'gain de change de 2 : D 411000 / C 766000, écriture validée',
      r.d411 = 2 AND r.c766 = 2 AND r.status = 'posted', format('D411000=%s C766000=%s statut=%s', r.d411, r.c766, r.status));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('B02', 'gain de change de 2 : D 411000 / C 766000, écriture validée', false, SQLERRM);
  END;
END $$;

-- B03 — type d'écart inconnu refusé
DO $$
DECLARE t uuid := _mk_tenant('B03'); e uuid; g uuid; refus boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    e := _entry(t, 'B03', DATE '2026-03-01',
      '[{"a":"411000","d":100,"t":"CLI1"},{"a":"707000","c":100}]');
    INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, total_debit, total_credit, status)
    VALUES (t, 'L-B03', DATE '2026-03-01', 100, 95, 'open') RETURNING id INTO g;
    UPDATE journal_lines SET lettrage_code = 'L-B03', lettrage_group_id = g
      WHERE journal_id = e AND account_code = '411000';
    BEGIN
      PERFORM generate_residual_entry(g, 'fantaisie', 5);
    EXCEPTION WHEN OTHERS THEN refus := SQLERRM LIKE '%inconnu%'; END;
    PERFORM _rec('B03', 'type d''écart inconnu : refus explicite', refus, 'refus=' || refus);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('B03', 'type d''écart inconnu : refus explicite', false, SQLERRM);
  END;
END $$;

-- B04 — groupe sans ligne rattachée : la contrepartie est inconnue, refus
DO $$
DECLARE t uuid := _mk_tenant('B04'); g uuid; refus boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, total_debit, total_credit, status)
    VALUES (t, 'L-B04', DATE '2026-03-01', 100, 95, 'open') RETURNING id INTO g;
    BEGIN
      PERFORM generate_residual_entry(g, 'escompte', 5);
    EXCEPTION WHEN OTHERS THEN refus := SQLERRM LIKE '%contrepartie%'; END;
    PERFORM _rec('B04', 'groupe sans ligne lettrée : contrepartie inconnue, écriture refusée', refus, 'refus=' || refus);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('B04', 'groupe sans ligne lettrée : contrepartie inconnue, écriture refusée', false, SQLERRM);
  END;
END $$;

-- B05 — un écart déjà écrit n'est pas doublé
DO $$
DECLARE t uuid := _mk_tenant('B05'); e uuid; g uuid; n int; refus boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    e := _entry(t, 'B05', DATE '2026-03-01',
      '[{"a":"411000","d":100,"t":"CLI1"},{"a":"707000","c":100}]');
    INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, total_debit, total_credit, status)
    VALUES (t, 'L-B05', DATE '2026-03-01', 100, 95, 'open') RETURNING id INTO g;
    UPDATE journal_lines SET lettrage_code = 'L-B05', lettrage_group_id = g
      WHERE journal_id = e AND account_code = '411000';
    PERFORM generate_residual_entry(g, 'escompte', 5);
    BEGIN
      PERFORM generate_residual_entry(g, 'escompte', 5);
    EXCEPTION WHEN OTHERS THEN refus := SQLERRM LIKE '%déjà%'; END;
    SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND reference = 'ECART:' || g;
    PERFORM _rec('B05', 'écart déjà comptabilisé : second appel refusé, une seule écriture',
      refus AND n = 1, format('refus=%s écritures=%s', refus, n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('B05', 'écart déjà comptabilisé : second appel refusé, une seule écriture', false, SQLERRM);
  END;
END $$;

-- C01 — charge constatée d'avance : D 486000 / C 606000 puis 12 reprises D 606000 / C 486000
DO $$
DECLARE t uuid := _mk_tenant('C01'); reg uuid; r jsonb; ini record; rep record; reg2 record;
BEGIN
  PERFORM _as_user();
  BEGIN
    PERFORM _mk_year(t, '2027');
    reg := _mk_reg(t, 'CCA', '606000', DATE '2026-01-01', DATE '2026-12-31', 1200);
    r := post_deferred_charge(reg, 'cca', 1200, 12);

    SELECT je.status, je.date, COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '486000'), 0) AS d486,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '606000'), 0) AS c606,
           COALESCE(sum(jl.debit), 0) AS d, COALESCE(sum(jl.credit), 0) AS c
      INTO ini
      FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.id = (r->'entries'->0->>'entry_id')::uuid GROUP BY je.status, je.date;

    SELECT count(DISTINCT je.id) AS n,
           count(DISTINCT je.id) FILTER (WHERE je.status = 'posted') AS posted,
           COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '606000'), 0) AS d606,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '486000'), 0) AS c486,
           min(je.date) AS d_min, max(je.date) AS d_max
      INTO rep
      FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.tenant_id = t AND je.reference = 'DEFER:' || reg || ':1';

    SELECT status, remaining_amount, created_entry_id INTO reg2 FROM regularization_entries WHERE id = reg;
    PERFORM _rec('C01', 'CCA 1 200 en 12 mois : D 486000 / C 606000, 12 reprises de 100 validées, régularisation soldée',
      ini.status = 'posted' AND ini.d486 = 1200 AND ini.c606 = 1200 AND ini.d = ini.c AND ini.date = DATE '2026-01-01'
        AND rep.n = 12 AND rep.posted = 12 AND rep.d606 = 1200 AND rep.c486 = 1200
        AND rep.d_min = DATE '2026-02-01' AND rep.d_max = DATE '2027-01-01'
        AND reg2.remaining_amount = 0 AND reg2.created_entry_id IS NOT NULL,
      format('initiale %s D486=%s C606=%s du %s ; reprises %s validées %s ; 606=%s 486=%s %s→%s ; reste=%s',
        ini.status, ini.d486, ini.c606, ini.date, rep.n, rep.posted, rep.d606, rep.c486, rep.d_min, rep.d_max, reg2.remaining_amount));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('C01', 'CCA 1 200 en 12 mois : D 486000 / C 606000, 12 reprises de 100 validées, régularisation soldée', false, SQLERRM);
  END;
END $$;

-- C02 — produit constaté d'avance : D 707000 / C 487000 puis reprises D 487000 / C 707000
DO $$
DECLARE t uuid := _mk_tenant('C02'); reg uuid; r jsonb; ini record; rep record;
BEGIN
  PERFORM _as_user();
  BEGIN
    PERFORM _mk_year(t, '2027');
    reg := _mk_reg(t, 'PCA', '707000', DATE '2026-01-01', DATE '2026-12-31', 600);
    r := post_deferred_charge(reg, 'pca', 600, 12);
    SELECT je.status, COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '707000'), 0) AS d707,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '487000'), 0) AS c487
      INTO ini FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.id = (r->'entries'->0->>'entry_id')::uuid GROUP BY je.status;
    SELECT count(DISTINCT je.id) AS n, COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '487000'), 0) AS d487,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '707000'), 0) AS c707
      INTO rep FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.tenant_id = t AND je.reference = 'DEFER:' || reg || ':1';
    PERFORM _rec('C02', 'PCA 600 en 12 mois : D 707000 / C 487000, reprises D 487000 / C 707000',
      ini.status = 'posted' AND ini.d707 = 600 AND ini.c487 = 600
        AND rep.n = 12 AND rep.d487 = 600 AND rep.c707 = 600,
      format('initiale %s D707=%s C487=%s ; reprises=%s D487=%s C707=%s', ini.status, ini.d707, ini.c487, rep.n, rep.d487, rep.c707));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('C02', 'PCA 600 en 12 mois : D 707000 / C 487000, reprises D 487000 / C 707000', false, SQLERRM);
  END;
END $$;

-- C03 — compte de charge absent du plan refusé (le `6_____` de l'ancien code)
DO $$
DECLARE t uuid := _mk_tenant('C03'); reg uuid; refus boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    PERFORM _mk_year(t, '2027');
    reg := _mk_reg(t, 'CCA', '6_____', DATE '2026-01-01', DATE '2026-12-31', 1200);
    BEGIN
      PERFORM post_deferred_charge(reg, 'cca', 1200, 12);
    EXCEPTION WHEN OTHERS THEN refus := SQLERRM LIKE '%6_____%'; END;
    PERFORM _rec('C03', 'compte de charge absent du plan : report refusé, écriture annulée', refus, 'refus=' || refus);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('C03', 'compte de charge absent du plan : report refusé, écriture annulée', false, SQLERRM);
  END;
END $$;

-- C04 — une régularisation déjà reportée n'est pas doublée
DO $$
DECLARE t uuid := _mk_tenant('C04'); reg uuid; n int; refus boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    PERFORM _mk_year(t, '2027');
    reg := _mk_reg(t, 'CCA', '606000', DATE '2026-01-01', DATE '2026-12-31', 1200);
    PERFORM post_deferred_charge(reg, 'cca', 1200, 12);
    BEGIN
      PERFORM post_deferred_charge(reg, 'cca', 1200, 12);
    EXCEPTION WHEN OTHERS THEN refus := SQLERRM LIKE '%déjà%'; END;
    SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND reference = 'DEFER:' || reg || ':0';
    PERFORM _rec('C04', 'régularisation déjà reportée : second appel refusé, une seule écriture initiale',
      refus AND n = 1, format('refus=%s écritures initiales=%s', refus, n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('C04', 'régularisation déjà reportée : second appel refusé, une seule écriture initiale', false, SQLERRM);
  END;
END $$;

DROP FUNCTION _mk_asset(uuid, text, date, numeric, integer, text, text, text);
DROP FUNCTION _mk_reg(uuid, text, text, date, date, numeric);
DROP FUNCTION _mk_year(uuid, text);

SELECT _audit_assert('211');