-- ============================================================
-- 316_chain_l1_candidats_tests.sql — L1 (tranche 5) : ce que le traçage des
--   CINQ CANDIDATS DIRECTS garantit
--
-- Source : doc/audit/INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md §2 (les cinq
-- fonctions qui remplissent les deux conditions de la doctrine compagnon).
--
--   T01  écart de change GAIN au règlement → un lien customer_payments →
--        journal_entries, un événement, une trace `applique` ;
--   T02  règlement SANS écart (devise de tenue) → aucun lien : le cas ordinaire
--        ne se trace pas (ni `sans_effet`, qui est réservé à l'anomalie) ;
--   T03  l'anomalie, elle, se trace : un règlement qui PORTE un écart sans
--        écriture d'écart → trace `sans_effet` (valeur de la 315), zéro ligne ;
--   T04  rappels de paie : le lot passe en `processing` avec un rappel en attente
--        → un lien pay_runs → payroll_variable_elements, décompte au payload,
--        un événement ; un lot SANS rappel → aucun lien ;
--   T05  acomptes de paie : même forme, même événement, avec le marqueur propre
--        au maillon (`deducted`) ;
--   T06  facturation des temps : un temps facturable produit une ligne de
--        facture → un lien project_time_entries → invoice_lines ;
--   T07  un temps NON facturable ne trace rien (le cas ordinaire) ;
--   T08  structure : cinq contrats actifs, cinq compagnons APRÈS (chacun triant
--        après son frère métier), cinq fonctions révoquées ;
--   T09  la société voisine ne voit ni les liens ni les événements (RLS) ;
--   T10  aucun lien de la tranche ne désigne un aval d'une autre société.
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé, puis rôle `authenticated` — un utilisateur réel, sous RLS.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '406', false);
DELETE FROM _audit_results WHERE file = '316';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Une facture en DEVISE, validée (le décor de la suite 309, repris tel quel :
-- c'est lui qui fait courir le maillon d'écart de change).
CREATE OR REPLACE FUNCTION _l316_vente(p_t uuid, p_c uuid, p_taux numeric, p_montant numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date,
                        status, subtotal, vat_total, total, amount_paid, amount_due,
                        currency_code, exchange_rate, amount_total_currency)
  VALUES (p_t, 'FAC-' || left(uuid_generate_v4()::text, 8), p_c, 'Client US', '2026-03-10',
          '2026-04-10', 'draft', p_montant, 0, p_montant, 0, p_montant,
          CASE WHEN p_taux = 1 THEN 'EUR' ELSE 'USD' END, p_taux, p_montant)
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price,
                             vat_rate, vat_code, total, vat_amount, line_order)
  VALUES (p_t, inv, 'Prestation', 1, p_montant, 0, 'FR0', p_montant, 0, 1);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  RETURN inv;
END $$;

-- Un règlement (le maillon d'écart de change se déclenche à l'INSERT).
CREATE OR REPLACE FUNCTION _l316_reglement(p_t uuid, p_c uuid, p_inv uuid, p_devise text,
  p_taux_piece numeric, p_taux_paiement numeric, p_montant_devise numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p uuid;
BEGIN
  INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date,
                                 amount, method, status, currency_code, exchange_rate, amount_currency)
  VALUES (p_t, 'REG-' || left(uuid_generate_v4()::text, 8), p_c, p_inv, '2026-04-05',
          round(p_montant_devise * p_taux_paiement, 2), 'transfer', 'recorded', p_devise,
          p_taux_paiement, p_montant_devise)
  RETURNING id INTO p;
  RETURN p;
END $$;

-- Un lot de paie, avec un rappel et/ou un acompte en attente pour sa période.
CREATE OR REPLACE FUNCTION _l316_lot(p_t uuid, p_num text, p_employee uuid, p_periode date)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid;
BEGIN
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (p_t, p_num, p_periode, (p_periode + interval '1 month - 1 day')::date,
          (p_periode + interval '1 month - 1 day')::date, 'draft', 0, 0, 0, 1)
  RETURNING id INTO r;
  RETURN r;
END $$;

-- Les liens d'un document, leur effet et l'aval.
CREATE OR REPLACE FUNCTION _l316_liens(p_t uuid, p_amont_type text, p_amont_id uuid)
RETURNS TABLE(effet text, aval_type text, aval_id uuid, link_type text, payload jsonb)
LANGUAGE sql AS $$
  SELECT dl.effet, dl.aval_type, dl.aval_id, dl.link_type, dl.payload
  FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = p_amont_type AND dl.amont_id = p_amont_id
  ORDER BY dl.effet
$$;

CREATE OR REPLACE FUNCTION _l316_evt(p_t uuid, p_nom text, p_agregat uuid)
RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM domain_events de
  WHERE de.tenant_id = p_t AND de.event_name = p_nom AND de.aggregate_id = p_agregat
$$;

CREATE OR REPLACE FUNCTION _l316_traces(p_t uuid, p_effet text)
RETURNS TABLE(resultat text, duree_ms integer, lignes_ecrites integer, message text)
LANGUAGE sql AS $$
  SELECT ct.resultat, ct.duree_ms, ct.lignes_ecrites, ct.message FROM chain_traces ct
  WHERE ct.tenant_id = p_t AND ct.effet = p_effet ORDER BY ct.id
$$;

-- ═════════════════════════════════════════════════════════════
-- T01 — Gain de change au règlement : le lien, l'événement, la trace
--   Facture 1 000 USD comptabilisée à 0,90 (900 EUR), encaissée à 0,95 (950 EUR)
--   → 50 EUR de gain : le maillon écrit l'écriture, le compagnon la LIE.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5A'); c uuid; inv uuid; pay uuid; v record;
        n_liens int; n_evt int; n_tolere int; n_applique int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_collectif) VALUES (t, 'Client US', '411000') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _l316_vente(t, c, 0.90, 1000);
    pay := _l316_reglement(t, c, inv, 'USD', 0.90, 0.95, 1000);

    SELECT * INTO v FROM _l316_liens(t, 'customer_payments', pay)
     WHERE effet = 'sale.payment.exchange_gain_loss' LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'customer_payments', pay)
     WHERE effet = 'sale.payment.exchange_gain_loss';
    n_evt := _l316_evt(t, 'customer_payments.exchange_gain_loss_posted', pay);
    SELECT count(*) FILTER (WHERE resultat = 'tolere'), count(*) FILTER (WHERE resultat = 'applique')
      INTO n_tolere, n_applique FROM _l316_traces(t, 'sale.payment.exchange_gain_loss');

    PERFORM _rec('T01', 'gain de change au règlement → un lien customer_payments → journal_entries (adjusted_by), un événement, UNE SEULE trace `applique`',
      n_liens = 1 AND v.aval_type = 'journal_entries' AND v.link_type = 'adjusted_by'
        AND (v.payload->>'ecart')::numeric = 50
        AND n_evt = 1 AND n_tolere = 0 AND n_applique = 1,
      format('liens=%s aval=%s type=%s payload=%s événements=%s tolere=%s applique=%s',
             n_liens, v.aval_type, v.link_type, v.payload, n_evt, n_tolere, n_applique));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T01', 'gain de change au règlement → un lien customer_payments → journal_entries (adjusted_by), un événement, UNE SEULE trace `applique`', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — Règlement SANS écart : le cas ordinaire ne se trace pas
--   Devise de tenue (EUR) : le maillon n'écrit aucune écriture d'écart. Un
--   `sans_effet` y serait un bruit — la valeur est réservée à l'anomalie (T03).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5B'); c uuid; inv uuid; pay uuid; n_liens int; n_traces int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_collectif) VALUES (t, 'Client EU', '411000') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _l316_vente(t, c, 1, 1000);          -- devise de tenue : pas d'écart possible
    pay := _l316_reglement(t, c, inv, 'EUR', 1, 1, 1000);

    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'customer_payments', pay)
     WHERE effet = 'sale.payment.exchange_gain_loss';
    SELECT count(*) INTO n_traces FROM _l316_traces(t, 'sale.payment.exchange_gain_loss');

    PERFORM _rec('T02', 'règlement en devise de tenue : aucun lien et AUCUNE trace — le cas ordinaire ne se trace pas (`sans_effet` est réservé à l''anomalie)',
      n_liens = 0 AND n_traces = 0,
      format('liens=%s (0 attendu), traces=%s (0 attendue)', n_liens, n_traces));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'règlement en devise de tenue : aucun lien et AUCUNE trace — le cas ordinaire ne se trace pas (`sans_effet` est réservé à l''anomalie)', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — L'anomalie, elle, SE TRACE : `sans_effet` (valeur de la 315)
--   Un règlement qui PORTE un écart (marqueur mesuré, non nul) sans qu'aucune
--   écriture d'écart existe : c'est exactement le cas que le vocabulaire ne
--   savait pas dire avant la 315. On l'obtient en posant le marqueur sans passer
--   par le maillon (l'écriture est absente, le marqueur est là).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5C'); c uuid; inv uuid; pay uuid; v record; n_liens int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_collectif) VALUES (t, 'Client Anomalie', '411000') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _l316_vente(t, c, 1, 1000);
    -- Le marqueur est posé À LA MAIN, sans écriture d'écart : le maillon ne
    -- réagira pas (il saute quand l'écart est déjà non nul), le compagnon si.
    INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date,
                                   amount, method, status, currency_code, exchange_rate,
                                   amount_currency, exchange_gain_loss)
    VALUES (t, 'REG-ANOMALIE', c, inv, '2026-04-05', 1000, 'transfer', 'recorded', 'EUR', 1, 1000, 12)
    RETURNING id INTO pay;

    SELECT * INTO v FROM _l316_traces(t, 'sale.payment.exchange_gain_loss') LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'customer_payments', pay)
     WHERE effet = 'sale.payment.exchange_gain_loss';

    PERFORM _rec('T03', 'écart de change marqué sans écriture d''écart : le compagnon trace `sans_effet` (zéro ligne) et NE POSE AUCUN lien — l''anomalie est visible au lieu d''être muette',
      n_liens = 0 AND v.resultat = 'sans_effet' AND v.lignes_ecrites = 0 AND v.message LIKE '%aucune écriture%',
      format('liens=%s (0 attendu), trace=%s (%s ligne(s)) — %s',
             n_liens, v.resultat, v.lignes_ecrites, left(COALESCE(v.message, ''), 90)));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T03', 'écart de change marqué sans écriture d''écart : le compagnon trace `sans_effet` (zéro ligne) et NE POSE AUCUN lien — l''anomalie est visible au lieu d''être muette', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — Rappels de paie : N rappels intégrés en UN passage
--   Le lot passe en `processing` ; le maillon métier
--   (`integrate_pay_recalls_on_payrun`) pose un élément de paie par rappel
--   `pending` de la période ; le compagnon LIE le lot à ses éléments, avec le
--   décompte au payload (`lien_par_ligne = false`) — un rappel n'est pas une
--   ligne du lot. Un second passage ne double pas le lien.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5D'); e1 uuid; e2 uuid; r1 uuid; r2 uuid; run uuid;
        v record; n_liens int; n_evt int; n_elem int; n_app int; n_apres_rejeu int;
BEGIN
  BEGIN
    INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
    VALUES (t, 'Salarié A', 'Sal', 'A', 'sal-a@audit.test', CURRENT_DATE, 'active') RETURNING id INTO e1;
    INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
    VALUES (t, 'Salarié B', 'Sal', 'B', 'sal-b@audit.test', CURRENT_DATE, 'active') RETURNING id INTO e2;
    INSERT INTO pay_recalls (tenant_id, employee_id, reference_period, recall_amount, status)
    VALUES (t, e1, '2026-03', 300, 'pending') RETURNING id INTO r1;
    INSERT INTO pay_recalls (tenant_id, employee_id, reference_period, recall_amount, status)
    VALUES (t, e2, '2026-03', 120, 'pending') RETURNING id INTO r2;
    run := _l316_lot(t, 'PAIE-2026-03', e1, '2026-03-01');

    PERFORM _as_user();
    UPDATE pay_runs SET status = 'processing' WHERE id = run;

    SELECT * INTO v FROM _l316_liens(t, 'pay_runs', run)
     WHERE effet = 'payroll.pay_recall.integrated' LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'pay_runs', run)
     WHERE effet = 'payroll.pay_recall.integrated';
    n_evt := _l316_evt(t, 'pay_runs.pay_recalls_integrated', run);
    SELECT count(*) INTO n_elem FROM payroll_variable_elements
     WHERE tenant_id = t AND pay_run_id = run AND element_type = 'pay_recall';
    SELECT count(*) FILTER (WHERE resultat = 'applique') INTO n_app
      FROM _l316_traces(t, 'payroll.pay_recall.integrated');

    -- Rejeu : une seconde fois `processing` ne doit pas poser un second lien.
    UPDATE pay_runs SET status = 'draft' WHERE id = run;
    UPDATE pay_runs SET status = 'processing' WHERE id = run;
    SELECT count(*) INTO n_apres_rejeu FROM _l316_liens(t, 'pay_runs', run)
     WHERE effet = 'payroll.pay_recall.integrated';

    PERFORM _rec('T04', 'rappels de paie : le lot passe en `processing` → UN lien pay_runs → payroll_variable_elements (payload `elements` = 2, `lien_par_ligne` = false, identifiants des rappels), un événement, une trace `applique` — le rejeu ne double pas le lien',
      n_elem = 2 AND n_liens = 1 AND n_apres_rejeu = 1
        AND v.aval_type = 'payroll_variable_elements' AND v.link_type = 'generated_entry'
        AND (v.payload->>'elements')::int = 2 AND (v.payload->>'lien_par_ligne')::boolean = false
        AND jsonb_array_length(v.payload->'recall_ids') = 2
        AND (v.payload->>'periode') = '2026-03'
        AND n_evt = 1 AND n_app = 1,
      format('éléments=%s liens=%s après rejeu=%s aval=%s payload=%s événements=%s traces applique=%s',
             n_elem, n_liens, n_apres_rejeu, v.aval_type, v.payload, n_evt, n_app));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04', 'rappels de paie : le lot passe en `processing` → UN lien pay_runs → payroll_variable_elements (payload `elements` = 2, `lien_par_ligne` = false, identifiants des rappels), un événement, une trace `applique` — le rejeu ne double pas le lien', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — Acomptes de paie : même forme, marqueur propre
--   Le maillon (`integrate_salary_advances_on_payrun`) retient les acomptes
--   `pending` du mois ; le compagnon lie le lot à ses éléments, et le payload
--   porte les identifiants des ACOMPTES (`advance_ids`) — jamais ceux des rappels.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5E'); e1 uuid; a1 uuid; a2 uuid; run uuid; v record;
        n_liens int; n_evt int; n_elem int; n_app int;
BEGIN
  BEGIN
    INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
    VALUES (t, 'Salarié C', 'Sal', 'C', 'sal-c@audit.test', CURRENT_DATE, 'active') RETURNING id INTO e1;
    INSERT INTO salary_advances (tenant_id, employee_id, amount, advance_date, status, deduction_month)
    VALUES (t, e1, 200, '2026-03-02', 'pending', '2026-03-01'::date) RETURNING id INTO a1;
    INSERT INTO salary_advances (tenant_id, employee_id, amount, advance_date, status, deduction_month)
    VALUES (t, e1, 150, '2026-03-05', 'pending', '2026-03-01'::date) RETURNING id INTO a2;
    run := _l316_lot(t, 'PAIE-2026-03', e1, '2026-03-01');

    PERFORM _as_user();
    UPDATE pay_runs SET status = 'processing' WHERE id = run;

    SELECT * INTO v FROM _l316_liens(t, 'pay_runs', run)
     WHERE effet = 'payroll.salary_advance.integrated' LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'pay_runs', run)
     WHERE effet = 'payroll.salary_advance.integrated';
    n_evt := _l316_evt(t, 'pay_runs.salary_advances_deducted', run);
    SELECT count(*) INTO n_elem FROM payroll_variable_elements
     WHERE tenant_id = t AND pay_run_id = run AND element_type = 'advance_deduction';
    SELECT count(*) FILTER (WHERE resultat = 'applique') INTO n_app
      FROM _l316_traces(t, 'payroll.salary_advance.integrated');

    PERFORM _rec('T05', 'acomptes de paie : UN lien pay_runs → payroll_variable_elements portant `advance_ids` (2 acomptes) et jamais `recall_ids`, un événement propre (`pay_runs.salary_advances_deducted`), une trace `applique`',
      n_elem = 2 AND n_liens = 1
        AND v.aval_type = 'payroll_variable_elements' AND v.link_type = 'generated_entry'
        AND (v.payload->>'elements')::int = 2
        AND jsonb_array_length(v.payload->'advance_ids') = 2
        AND (v.payload ? 'recall_ids') = false
        AND n_evt = 1 AND n_app = 1,
      format('éléments=%s liens=%s payload=%s événements=%s traces applique=%s',
             n_elem, n_liens, v.payload, n_evt, n_app));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T05', 'acomptes de paie : UN lien pay_runs → payroll_variable_elements portant `advance_ids` (2 acomptes) et jamais `recall_ids`, un événement propre (`pay_runs.salary_advances_deducted`), une trace `applique`', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — Temps facturable : le lien va de la feuille à la LIGNE de facture
--   Décor repris de la suite 231 (projet `allow_billable`, saisie directe : le
--   `end_time` est là dès l'INSERT). Le maillon de la 301 crée la ligne dans le
--   brouillon du projet ; le compagnon pose le lien, avec l'heure et le taux.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5F'); c uuid; pr uuid; tk uuid; emp uuid; mgr uuid; te uuid;
        v record; n_liens int; n_lignes int; n_evt int; n_app int; v_tot numeric;
BEGIN
  BEGIN
    UPDATE company_settings SET currency = 'EUR' WHERE tenant_id = t;
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client F') RETURNING id INTO c;
    INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
      VALUES (t, 'Salarié F', 'Sal', 'F', 'sal-f@audit.test', CURRENT_DATE, 'active') RETURNING id INTO emp;
    INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
      VALUES (t, 'Chef F', 'Chef', 'F', 'chef-f@audit.test', CURRENT_DATE, 'active') RETURNING id INTO mgr;
    INSERT INTO projects (tenant_id, name, customer_id, status, allow_billable, allow_timesheets, manager_id)
      VALUES (t, 'Chantier F', c, 'active', true, true, mgr) RETURNING id INTO pr;
    INSERT INTO project_tasks (tenant_id, project_id, title, status)
      VALUES (t, pr, 'Tâche F', 'todo') RETURNING id INTO tk;

    PERFORM _as_user();
    INSERT INTO project_time_entries (tenant_id, project_id, task_id, employee_id,
      start_time, end_time, duration_seconds, is_billable, hourly_rate)
    VALUES (t, pr, tk, emp, now() - interval '3 hours', now(), 10800, true, 80)
    RETURNING id INTO te;

    SELECT * INTO v FROM _l316_liens(t, 'project_time_entries', te)
     WHERE effet = 'project.time.billed' LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'project_time_entries', te)
     WHERE effet = 'project.time.billed';
    SELECT count(*), COALESCE(sum(il.total), 0) INTO n_lignes, v_tot
      FROM invoice_lines il WHERE il.tenant_id = t AND il.time_entry_id = te;
    n_evt := _l316_evt(t, 'project_time_entries.billed', te);
    SELECT count(*) FILTER (WHERE resultat = 'applique') INTO n_app
      FROM _l316_traces(t, 'project.time.billed');

    PERFORM _rec('T06', 'temps facturable : 3 h à 80 → UNE ligne de facture (240) et UN lien project_time_entries → invoice_lines (`invoiced_by`), l''heure et le taux au payload, un événement, une trace `applique`',
      n_lignes = 1 AND v_tot = 240 AND n_liens = 1
        AND v.aval_type = 'invoice_lines' AND v.link_type = 'invoiced_by'
        AND (v.payload->>'heures')::numeric = 3 AND (v.payload->>'taux')::numeric = 80
        AND (v.payload->>'facturable')::boolean = true
        AND n_evt = 1 AND n_app = 1,
      format('lignes=%s total=%s liens=%s aval=%s payload=%s événements=%s traces applique=%s',
             n_lignes, v_tot, n_liens, v.aval_type, v.payload, n_evt, n_app));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T06', 'temps facturable : 3 h à 80 → UNE ligne de facture (240) et UN lien project_time_entries → invoice_lines (`invoiced_by`), l''heure et le taux au payload, un événement, une trace `applique`', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T07 — Temps NON facturable : le cas ordinaire reste muet
--   Aucune ligne de facture n'est créée par le métier, donc rien à lier — et on
--   ne trace rien : `sans_effet` dirait qu'un effet manque là où aucun n'est
--   attendu (la distinction que la 315 a rendue possible est donc *utilisée*,
--   pas seulement disponible).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5G'); c uuid; pr uuid; tk uuid; emp uuid; mgr uuid; te uuid;
        n_liens int; n_traces int; n_lignes int;
BEGIN
  BEGIN
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client G') RETURNING id INTO c;
    INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
      VALUES (t, 'Salarié G', 'Sal', 'G', 'sal-g@audit.test', CURRENT_DATE, 'active') RETURNING id INTO emp;
    INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
      VALUES (t, 'Chef G', 'Chef', 'G', 'chef-g@audit.test', CURRENT_DATE, 'active') RETURNING id INTO mgr;
    INSERT INTO projects (tenant_id, name, customer_id, status, allow_billable, allow_timesheets, manager_id)
      VALUES (t, 'Chantier G', c, 'active', true, true, mgr) RETURNING id INTO pr;
    INSERT INTO project_tasks (tenant_id, project_id, title, status)
      VALUES (t, pr, 'Tâche G', 'todo') RETURNING id INTO tk;

    PERFORM _as_user();
    INSERT INTO project_time_entries (tenant_id, project_id, task_id, employee_id,
      start_time, end_time, duration_seconds, is_billable, hourly_rate)
    VALUES (t, pr, tk, emp, now() - interval '2 hours', now(), 7200, false, 80)
    RETURNING id INTO te;

    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'project_time_entries', te)
     WHERE effet = 'project.time.billed';
    SELECT count(*) INTO n_traces FROM _l316_traces(t, 'project.time.billed');
    SELECT count(*) INTO n_lignes FROM invoice_lines
     WHERE tenant_id = t AND time_entry_id = te;

    PERFORM _rec('T07', 'temps non facturable : aucune ligne de facture, donc AUCUN lien et AUCUNE trace — le cas ordinaire ne crie pas (`sans_effet` est réservé au manque)',
      n_lignes = 0 AND n_liens = 0 AND n_traces = 0,
      format('lignes=%s liens=%s traces=%s (0 partout attendu)', n_lignes, n_liens, n_traces));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T07', 'temps non facturable : aucune ligne de facture, donc AUCUN lien et AUCUNE trace — le cas ordinaire ne crie pas (`sans_effet` est réservé au manque)', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — Ligne de relevé appariée : le lien va jusqu'à la LIGNE du grand livre
--   Décor mesuré : le maillon de la 222 (`statement_line_ledger_match`) apparie
--   une ligne de relevé à une ligne du grand livre NON rapprochée du compte
--   bancaire, montant égal, date à ±15/+5 jours, écriture comptabilisée. Le
--   compagnon RE-LIT les marqueurs posés par le maillon (jamais `NEW`, dont la
--   copie ne les porte pas — défaut mesuré au premier passage de la 316) et lie
--   l'opération à la ligne du grand livre.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5H'); ba uuid; ent uuid; bt uuid; v record;
        n_liens int; n_evt int; n_app int; v_matched boolean; v_bilan uuid; v_rec boolean;
BEGIN
  BEGIN
    INSERT INTO bank_accounts (tenant_id, name, type, account_code)
    VALUES (t, 'Compte courant', 'chequing', '512000') RETURNING id INTO ba;
    -- Écriture comptabilisée du 10/03 : paiement de 500 par le compte bancaire
    -- (le compte 512000 est crédité ; le maillon apparie une opération `debit` du
    -- relevé au CRÉDIT du grand livre — sens mesuré de `statement_line_ledger_match`).
    ent := _entry(t, 'PAI-500', '2026-03-10',
      '[{"a":"401000","d":500,"c":0},{"a":"512000","d":0,"c":500}]'::jsonb, true);

    PERFORM _as_user();
    INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description,
                                   reference, type, amount, source, kind)
    VALUES (t, ba, ba, '2026-03-11', 'Prélèvement fournisseur', 'REL-001', 'debit', 500, 'import', 'statement')
    RETURNING id INTO bt;

    SELECT matched, reconciled_entry_id INTO v_matched, v_bilan
      FROM bank_transactions WHERE id = bt;
    SELECT jl.reconciled INTO v_rec FROM journal_lines jl
      WHERE jl.tenant_id = t AND jl.account_code = '512000' AND jl.journal_id = ent LIMIT 1;

    SELECT * INTO v FROM _l316_liens(t, 'bank_transactions', bt)
     WHERE effet = 'treasury.statement_line.matched' LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'bank_transactions', bt)
     WHERE effet = 'treasury.statement_line.matched';
    n_evt := _l316_evt(t, 'bank_transactions.matched', bt);
    SELECT count(*) FILTER (WHERE resultat = 'applique') INTO n_app
      FROM _l316_traces(t, 'treasury.statement_line.matched');

    PERFORM _rec('T08', 'ligne de relevé appariée : le métier rapproche (matched, écriture, ligne marquée) et le compagnon pose UN lien bank_transactions → journal_lines (`created_from`), un événement, une trace `applique`',
      n_liens = 1 AND v.aval_type = 'journal_lines' AND v.link_type = 'created_from'
        AND COALESCE(v_matched, false) AND v_bilan = ent AND COALESCE(v_rec, false)
        AND (v.payload->>'reference') = 'REL-001' AND (v.payload->>'montant')::numeric = 500
        AND (v.payload->>'compte') = '512000'
        AND n_evt = 1 AND n_app = 1,
      format('liens=%s aval=%s payload=%s rapproché=%s écriture=%s ligne marquée=%s événements=%s traces applique=%s',
             n_liens, v.aval_type, v.payload, v_matched, v_bilan = ent, v_rec, n_evt, n_app));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T08', 'ligne de relevé appariée : le métier rapproche (matched, écriture, ligne marquée) et le compagnon pose UN lien bank_transactions → journal_lines (`created_from`), un événement, une trace `applique`', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T09 — Ligne de relevé SANS contrepartie comptable : le cas ordinaire
--   Aucune ligne du grand livre ne correspond (montant différent) : le maillon
--   n'apparie pas, le compagnon ne lie pas — et il ne trace pas non plus, sinon
--   chaque import d'un relevé de cent lignes produirait cent `sans_effet`.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('C5I'); ba uuid; ent uuid; bt uuid; n_liens int; n_traces int;
        v_matched boolean;
BEGIN
  BEGIN
    INSERT INTO bank_accounts (tenant_id, name, type, account_code)
    VALUES (t, 'Compte courant', 'chequing', '512000') RETURNING id INTO ba;
    -- Le grand livre porte 500 ; le relevé annonce 999 : rien ne doit s'apparier.
    ent := _entry(t, 'PAI-500', '2026-03-10',
      '[{"a":"401000","d":500,"c":0},{"a":"512000","d":0,"c":500}]'::jsonb, true);

    PERFORM _as_user();
    INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description,
                                   reference, type, amount, source, kind)
    VALUES (t, ba, ba, '2026-03-11', 'Prélèvement fournisseur', 'REL-002', 'debit', 999, 'import', 'statement')
    RETURNING id INTO bt;

    SELECT matched INTO v_matched FROM bank_transactions
     WHERE tenant_id = t AND reference = 'REL-002';
    SELECT count(*) INTO n_liens FROM _l316_liens(t, 'bank_transactions', bt);
    SELECT count(*) INTO n_traces FROM _l316_traces(t, 'treasury.statement_line.matched');

    PERFORM _rec('T09', 'ligne de relevé sans contrepartie : le métier n''apparie pas (montant différent), le compagnon ne lie pas et NE TRACE PAS — un import muet ne produit pas cent `sans_effet`',
      COALESCE(v_matched, true) = false AND n_liens = 0 AND n_traces = 0,
      format('rapproché=%s liens=%s traces=%s (faux/0/0 attendu)', v_matched, n_liens, n_traces));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T09', 'ligne de relevé sans contrepartie : le métier n''apparie pas (montant différent), le compagnon ne lie pas et NE TRACE PAS — un import muet ne produit pas cent `sans_effet`', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T10 — Structure : cinq contrats, cinq compagnons, et le dernier mot
--   Ce qui se mesure ici ne dépend d'aucune donnée : les cinq effets sont
--   déclarés au registre, les cinq fonctions existent, sont SECURITY DEFINER,
--   ne sont PAS exécutables par `authenticated`, et chaque déclencheur
--   compagnon s'exécute APRÈS son maillon métier — PostgreSQL exécute les
--   déclencheurs dans l'ordre ASCII de leur nom, donc aucun déclencheur qui
--   n'est pas un compagnon L1 ne trie après un `zz_l1_*`. C'est la condition
--   pour que le compagnon voie ce que le maillon métier vient d'écrire.
--   ⚠️ L'ordre ENTRE deux compagnons L1 d'une même table est libre et n'est pas
--   contraint ici : `pay_runs` porte `zz_l1_pay_recall_integration` ET
--   `zz_l1_salary_advance_integration`, et sur cette table le second trie après
--   le premier — chacun ne lit que son propre type d'élément de paie, donc la
--   contrainte qui compte est bien « après le métier », pas « le dernier des
--   derniers » (mesuré : c'est le premier jet de ce scénario qui l'avait
--   écrit trop fort, et la suite l'a signalé).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_effets text[] := ARRAY['sale.payment.exchange_gain_loss', 'project.time.billed',
                           'payroll.pay_recall.integrated', 'payroll.salary_advance.integrated',
                           'treasury.statement_line.matched'];
  v_fonctions text[] := ARRAY['chain_l1_payment_exchange_gain_loss', 'chain_l1_time_entry_billed',
                              'chain_l1_pay_recall_integration', 'chain_l1_salary_advance_integration',
                              'chain_l1_statement_line_matched'];
  v_triggers text[] := ARRAY['zz_l1_payment_exchange_gain_loss', 'zz_l1_time_entry_billed',
                             'zz_l1_pay_recall_integration', 'zz_l1_salary_advance_integration',
                             'zz_l1_statement_line_matched'];
  n_contrats int; n_comp int; n_definer int; n_exposes int; n_apres_metier int; n_metier_apres int;
BEGIN
  SELECT count(*) INTO n_contrats FROM document_effects
   WHERE tenant_id IS NULL AND actif AND effet = ANY (v_effets);

  SELECT count(*) FILTER (WHERE true), count(*) FILTER (WHERE p.prosecdef)
    INTO n_comp, n_definer
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace AND ns.nspname = 'public'
  WHERE p.proname = ANY (v_fonctions);

  SELECT count(*) INTO n_exposes
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace AND ns.nspname = 'public'
  WHERE p.proname = ANY (v_fonctions) AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

  -- Chacun de mes cinq déclencheurs trie après tous les déclencheurs MÉTIER de sa
  -- table (ceux qui ne sont pas des compagnons L1).
  SELECT count(*) INTO n_apres_metier
  FROM pg_trigger t
  WHERE NOT t.tgisinternal AND t.tgname = ANY (v_triggers)
    AND NOT EXISTS (
      SELECT 1 FROM pg_trigger t2
      WHERE t2.tgrelid = t.tgrelid AND NOT t2.tgisinternal
        AND t2.tgname > t.tgname
        AND t2.tgname NOT LIKE 'zz_l1\_%'
    );

  -- Contre-épreuve : aucun déclencheur métier ne trie après l'un des miens.
  SELECT count(*) INTO n_metier_apres
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
  WHERE NOT t.tgisinternal
    AND c.relname IN ('customer_payments', 'project_time_entries', 'pay_runs', 'bank_transactions')
    AND t.tgname NOT LIKE 'zz_l1\_%'
    AND t.tgname > (SELECT min(x.tgname) FROM pg_trigger x
                    WHERE x.tgrelid = t.tgrelid AND NOT x.tgisinternal AND x.tgname = ANY (v_triggers));

  PERFORM _rec('T10', 'structure : 5 contrats actifs, 5 compagnons SECURITY DEFINER non exposés à `authenticated`, et chacun s''exécute APRÈS son maillon métier — aucun déclencheur métier ne trie après un compagnon `zz_l1_*`',
    n_contrats = 5 AND n_comp = 5 AND n_definer = 5 AND n_exposes = 0
      AND n_apres_metier = 5 AND n_metier_apres = 0,
    format('contrats=%s/5 compagnons=%s/5 SECURITY DEFINER=%s exposés=%s après-le-métier=%s/5 métier-après-moi=%s',
           n_contrats, n_comp, n_definer, n_exposes, n_apres_metier, n_metier_apres));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T11 — Isolation : la société voisine ne voit ni liens, ni événements, ni traces
--   Les trois lectures se font SANS clause de société — c'est la RLS seule qui
--   doit cacher les lignes de l'autre société. Contrôle positif : la société
--   propriétaire, elle, voit bien son lien, son événement et sa trace.
--   ⚠️ La voisine est un utilisateur RÉELLEMENT connecté à elle (`_mk_tenant` crée
--   son utilisateur, pose son JWT et son contexte). Poser `app.active_tenant_id`
--   seul ne suffit pas et le test mesurerait autre chose : `current_tenant_id()`
--   n'accepte un GUC que si le JWT appartient à `tenant_users` pour cette société
--   — sans appartenance, la société est « absente » et l'écriture échoue en
--   violation de RLS (défaut du premier jet de ce scénario, signalé par la suite).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; ca uuid; inv uuid; pay uuid;
        n_liens_a int; n_ev_a int; n_tr_a int;
        n_ev_voisin int; n_tr_voisin int; n_liens_voisin int;
BEGIN
  BEGIN
    ta := _mk_tenant('C5J');
    INSERT INTO customers (tenant_id, name, account_collectif)
    VALUES (ta, 'Client J', '411000') RETURNING id INTO ca;

    PERFORM _as_user();
    inv := _l316_vente(ta, ca, 0.90, 1000);
    pay := _l316_reglement(ta, ca, inv, 'USD', 0.90, 0.95, 1000);

    SELECT count(*) INTO n_liens_a FROM _l316_liens(ta, 'customer_payments', pay)
     WHERE effet = 'sale.payment.exchange_gain_loss';
    n_ev_a := _l316_evt(ta, 'customer_payments.exchange_gain_loss_posted', pay);
    SELECT count(*) INTO n_tr_a FROM _l316_traces(ta, 'sale.payment.exchange_gain_loss');

    -- La société voisine se connecte (utilisateur, JWT et contexte à elle).
    PERFORM set_config('role', 'postgres', true);
    tb := _mk_tenant('C5K');
    PERFORM _as_user();

    -- Lectures SANS filtre de société : la RLS doit suffire.
    SELECT count(*) INTO n_liens_voisin FROM document_links WHERE amont_id = pay;
    SELECT count(*) INTO n_ev_voisin FROM domain_events WHERE aggregate_id = pay;
    SELECT count(*) INTO n_tr_voisin FROM chain_traces WHERE tenant_id = ta;

    PERFORM _rec('T11', 'isolation : la société voisine ne voit ni le lien, ni l''événement, ni la trace du règlement — et la société propriétaire les voit tous les trois (contrôle positif)',
      n_liens_a = 1 AND n_ev_a = 1 AND n_tr_a = 1
        AND n_liens_voisin = 0 AND n_ev_voisin = 0 AND n_tr_voisin = 0,
      format('propriétaire : liens=%s événements=%s traces=%s | voisine : liens=%s événements=%s traces=%s',
             n_liens_a, n_ev_a, n_tr_a, n_liens_voisin, n_ev_voisin, n_tr_voisin));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T11', 'isolation : la société voisine ne voit ni le lien, ni l''événement, ni la trace du règlement — et la société propriétaire les voit tous les trois (contrôle positif)', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T12 — Cohérence des avals : jamais d'aval hors société, jamais de type étranger
--   Lecture en superutilisateur (l'invariant porte sur TOUTES les sociétés, la
--   RLS le masquerait). Deux mesures : aucun lien des cinq effets ne désigne un
--   aval qui appartient à une autre société, et les types d'aval employés sont
--   ceux que la tranche déclare — un aval non résolu serait un lien mort.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_effets text[] := ARRAY['sale.payment.exchange_gain_loss', 'project.time.billed',
                           'payroll.pay_recall.integrated', 'payroll.salary_advance.integrated',
                           'treasury.statement_line.matched'];
  n_liens int; n_hors_societe int; n_types_etrangers int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) INTO n_liens FROM document_links dl WHERE dl.effet = ANY (v_effets);

  SELECT count(*) INTO n_hors_societe FROM document_links dl
   WHERE dl.effet = ANY (v_effets)
     AND NOT (
          (dl.aval_type = 'journal_entries'
             AND EXISTS (SELECT 1 FROM journal_entries a WHERE a.id = dl.aval_id AND a.tenant_id = dl.tenant_id))
       OR (dl.aval_type = 'invoice_lines'
             AND EXISTS (SELECT 1 FROM invoice_lines a WHERE a.id = dl.aval_id AND a.tenant_id = dl.tenant_id))
       OR (dl.aval_type = 'payroll_variable_elements'
             AND EXISTS (SELECT 1 FROM payroll_variable_elements a WHERE a.id = dl.aval_id AND a.tenant_id = dl.tenant_id))
       OR (dl.aval_type = 'journal_lines'
             AND EXISTS (SELECT 1 FROM journal_lines a WHERE a.id = dl.aval_id AND a.tenant_id = dl.tenant_id))
     );

  SELECT count(*) INTO n_types_etrangers FROM document_links dl
   WHERE dl.effet = ANY (v_effets)
     AND dl.aval_type NOT IN ('journal_entries', 'invoice_lines',
                              'payroll_variable_elements', 'journal_lines');

  PERFORM _rec('T12', 'cohérence : les cinq effets ont laissé des liens dont AUCUN ne désigne un aval d''une autre société ni un type d''aval étranger — un aval non résolu serait un lien mort',
    n_liens >= 5 AND n_hors_societe = 0 AND n_types_etrangers = 0,
    format('liens des cinq effets=%s (5 au moins attendus sur une base neuve), avals hors société=%s, types étrangers=%s',
           n_liens, n_hors_societe, n_types_etrangers));
END $$;

SELECT _audit_assert('406');
