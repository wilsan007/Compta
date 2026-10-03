-- ============================================================
-- 340_timesheet_overtime_from_hours_tests.sql — tâche 2.2 (C3, rh-008)
--
-- Le défaut : une feuille de temps saisie à l'écran ne porte que des HEURES
-- (`hours`), jamais d'heure d'arrivée ni de départ. Or `overtime_minutes`
-- n'était calculé qu'à partir de `departure_time` : 12 h approuvées donnaient
-- `overtime_minutes = 0`, donc aucun élément de paie « heures sup ».
--
--   T01  12 h saisies, horaire prévu 7 h (35 h / 5) → 300 minutes
--   T02  à l'approbation : UN élément `overtime`, 5 h, au taux majoré de la
--        société (2 500 / 151,6667 × 1,25 = 20,6044 → 103,02 €)
--   T03  7 h saisies → 0 minute, aucun élément `overtime`
--   T04  non-régression : un pointage AVEC heures d'arrivée et de départ garde
--        la mesure sur l'horaire prévu (09:00–18:30 pour 17:00 → 90 min)
--   T05  l'horaire du salarié compte : 39 h / 5 = 7,8 h ; 9 h → 72 minutes
--   T06  l'approbation est signée par la base : `approved_by = auth.uid()`,
--        `approved_at` posé — l'écran n'a rien à envoyer
--   T07  un pointage d'ABSENCE ne fabrique pas d'heures sup
--   T08  corriger les heures (7 → 10) recalcule : 180 minutes
--   T09  une valeur FOURNIE (« 9 h dont 60 min ») est respectée, approbation comprise
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '340', false);
DELETE FROM _audit_results WHERE file = '340';

CREATE OR REPLACE FUNCTION _l340_employe(p_t uuid, p_nom text, p_hebdo numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours,
                         default_start_time, default_end_time)
  VALUES (p_t, p_nom, lower(replace(p_nom, ' ', '')) || '@audit.test', 'active', 2500, p_hebdo, '09:00', '17:00')
  RETURNING id INTO e;
  RETURN e;
END $$;

-- ── T01 + T02 ────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C3T01', false);
  e uuid; ts uuid; m int; n int; q numeric; pu numeric; mt numeric;
BEGIN
  PERFORM _as_user();
  e := _l340_employe(t, 'Salarie C3T01', 35);
  INSERT INTO timesheets (tenant_id, employee_id, date, hours)
  VALUES (t, e, DATE '2026-02-10', 12) RETURNING id INTO ts;
  SELECT overtime_minutes INTO m FROM timesheets WHERE id = ts;
  PERFORM _rec('T01', '12 h saisies sans heure de départ, horaire prévu 7 h : 300 minutes d''heures supplémentaires',
    m = 300, format('overtime_minutes=%s (300 attendues)', m));

  UPDATE timesheets SET status = 'approved' WHERE id = ts AND tenant_id = t;
  SELECT count(*), max(quantity), max(unit_price), max(amount) INTO n, q, pu, mt
  FROM payroll_variable_elements
  WHERE tenant_id = t AND source_id = ts AND element_type = 'overtime';
  PERFORM _rec('T02', 'à l''approbation : UN élément de paie « heures sup », 5 h au taux majoré (≈ 20,60 → 103,02 €)',
    n = 1 AND q = 5 AND pu BETWEEN 20.60 AND 20.61 AND mt BETWEEN 103.01 AND 103.03,
    format('lignes=%s quantité=%s taux=%s montant=%s', n, q, pu, mt));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01/T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T03 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C3T03', false);
  e uuid; ts uuid; m int; n int;
BEGIN
  PERFORM _as_user();
  e := _l340_employe(t, 'Salarie C3T03', 35);
  INSERT INTO timesheets (tenant_id, employee_id, date, hours)
  VALUES (t, e, DATE '2026-02-10', 7) RETURNING id INTO ts;
  UPDATE timesheets SET status = 'approved' WHERE id = ts AND tenant_id = t;
  SELECT overtime_minutes INTO m FROM timesheets WHERE id = ts;
  SELECT count(*) INTO n FROM payroll_variable_elements
  WHERE tenant_id = t AND source_id = ts AND element_type = 'overtime';
  PERFORM _rec('T03', '7 h saisies pour 7 h prévues : aucune heure supplémentaire, aucun élément de paie',
    COALESCE(m, 0) = 0 AND n = 0, format('overtime_minutes=%s éléments=%s', m, n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T04 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C3T04', false);
  e uuid; ts uuid; m int;
BEGIN
  PERFORM _as_user();
  e := _l340_employe(t, 'Salarie C3T04', 35);
  INSERT INTO timesheets (tenant_id, employee_id, date, scheduled_start, scheduled_end,
                          arrival_time, departure_time)
  VALUES (t, e, DATE '2026-02-10', '09:00', '17:00',
          TIMESTAMPTZ '2026-02-10 09:00', TIMESTAMPTZ '2026-02-10 18:30')
  RETURNING id INTO ts;
  SELECT overtime_minutes INTO m FROM timesheets WHERE id = ts;
  PERFORM _rec('T04', 'non-régression : un pointage avec arrivée et départ reste mesuré sur l''horaire prévu (90 min)',
    m = 90, format('overtime_minutes=%s (90 attendues)', m));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T05 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C3T05', false);
  e uuid; ts uuid; m int;
BEGIN
  PERFORM _as_user();
  e := _l340_employe(t, 'Salarie C3T05', 39);
  INSERT INTO timesheets (tenant_id, employee_id, date, hours)
  VALUES (t, e, DATE '2026-02-10', 9) RETURNING id INTO ts;
  SELECT overtime_minutes INTO m FROM timesheets WHERE id = ts;
  PERFORM _rec('T05', 'l''horaire du salarié compte : 39 h par semaine = 7,8 h par jour ; 9 h saisies → 72 minutes',
    m = 72, format('overtime_minutes=%s (72 attendues)', m));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'T05 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T06 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C3T06', false);
  e uuid; ts uuid; par uuid; le timestamptz;
BEGIN
  PERFORM _as_user();
  e := _l340_employe(t, 'Salarie C3T06', 35);
  INSERT INTO timesheets (tenant_id, employee_id, date, hours)
  VALUES (t, e, DATE '2026-02-10', 7) RETURNING id INTO ts;
  UPDATE timesheets SET status = 'approved' WHERE id = ts AND tenant_id = t;
  SELECT approved_by, approved_at INTO par, le FROM timesheets WHERE id = ts;
  PERFORM _rec('T06', 'l''approbation est signée par la base : approved_by = l''utilisateur connecté, approved_at posé',
    par IS NOT NULL AND par = auth.uid() AND le IS NOT NULL,
    format('approved_by=%s (attendu %s) approved_at=%s', par, auth.uid(), le));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'T06 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T07 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C3T07', false);
  e uuid; ts uuid; m int;
BEGIN
  PERFORM _as_user();
  e := _l340_employe(t, 'Salarie C3T07', 35);
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, absence_type)
  VALUES (t, e, DATE '2026-02-10', 12, 'unjustified') RETURNING id INTO ts;
  SELECT overtime_minutes INTO m FROM timesheets WHERE id = ts;
  PERFORM _rec('T07', 'un pointage d''absence ne fabrique pas d''heures supplémentaires',
    COALESCE(m, 0) = 0, format('overtime_minutes=%s (0 attendue)', m));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'T07 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T08 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C3T08', false);
  e uuid; ts uuid; m int;
BEGIN
  PERFORM _as_user();
  e := _l340_employe(t, 'Salarie C3T08', 35);
  INSERT INTO timesheets (tenant_id, employee_id, date, hours)
  VALUES (t, e, DATE '2026-02-10', 7) RETURNING id INTO ts;
  UPDATE timesheets SET hours = 10 WHERE id = ts AND tenant_id = t;
  SELECT overtime_minutes INTO m FROM timesheets WHERE id = ts;
  PERFORM _rec('T08', 'corriger les heures d''une feuille recalcule les heures supplémentaires (7 h → 10 h : 180 minutes)',
    m = 180, format('overtime_minutes=%s (180 attendues)', m));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'T08 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T09 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C3T09', false);
  e uuid; ts uuid; m1 int; m2 int;
BEGIN
  PERFORM _as_user();
  e := _l340_employe(t, 'Salarie C3T09', 35);
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, overtime_minutes)
  VALUES (t, e, DATE '2026-02-10', 9, 60) RETURNING id INTO ts;
  SELECT overtime_minutes INTO m1 FROM timesheets WHERE id = ts;
  UPDATE timesheets SET status = 'approved' WHERE id = ts AND tenant_id = t;
  SELECT overtime_minutes INTO m2 FROM timesheets WHERE id = ts;
  PERFORM _rec('T09', 'une valeur fournie est respectée : « 9 h dont 60 min sup » reste 60, à la saisie comme à l''approbation',
    m1 = 60 AND m2 = 60, format('à la saisie=%s, après approbation=%s (60 attendues)', m1, m2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T09', 'T09 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

DROP FUNCTION _l340_employe(uuid, text, numeric);
SELECT _audit_assert('340');
