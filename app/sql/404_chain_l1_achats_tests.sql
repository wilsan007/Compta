-- ============================================================
-- 314_chain_l1_achats_tests.sql — L1 (tranche 4) : ce que le traçage de la
--   chaîne ACHATS → COMPTABILITÉ et des NOTES DE FRAIS garantit
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md (lot L1) ;
-- inventaire §3 (la méthode) ; `INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md`
-- (les 32 fonctions mesurées, leur verdict, et ce qui est tracé ici).
--
--   T01  facture d'achat approuvée → UN lien purchase_invoices → journal_entries
--        (code « AC »), UN événement `purchase_invoices.approved`, et UNE SEULE
--        trace `applique` (le contrat est déclaré par la 314) ;
--   T02  le fait générateur est l'ÉTAT : une mise à jour qui ne change pas
--        `approval_status` ne crée ni second lien ni seconde trace, et le rejeu
--        explicite de `chain_avant` rend false en traçant `ignore` ;
--   T03  note de frais approuvée → DEUX liens (écriture « OD » ET élément de
--        paie), UN événement, UNE mesure — le gabarit multi-effets de la 310 ;
--   T04  une note de frais à 0 € : l'élément de paie est tracé, l'écriture ne
--        l'est PAS — le compagnon ne pose pas de lien vers un aval qui n'existe
--        pas (la limite du vocabulaire de trace est dite dans l'en-tête de la 314) ;
--   T05  mode `refuse` + contrat éteint : l'approbation est BLOQUÉE avant tout
--        effet (aucune écriture produite), avec un message nominatif ;
--   T06  la société voisine ne voit ni les liens ni les événements (RLS) ;
--   T07  l'ordre des déclencheurs est prouvé : les deux compagnons sont APRÈS et
--        trient après leur frère métier (doctrine de la 310) ;
--   T08  les deux compagnons ne sont pas des points d'entrée (aucun EXECUTE) ;
--   T09  les trois contrats sont en base avec leurs drapeaux mesurés
--        (`ecrit_comptable`/« AC », `ecrit_comptable`/« OD », `touche_paie`) ;
--   T10  le cloisonnement de l'écriture : l'aval lié appartient bien à la société
--        du document (aucun lien inter-société).
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé, puis rôle `authenticated` — un utilisateur réel, sous RLS.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '314', false);
DELETE FROM _audit_results WHERE file = '314';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Une facture d'achat prête à approuver (le fait générateur est l'approbation).
CREATE OR REPLACE FUNCTION _l314_achat(p_t uuid, p_num text, p_s uuid,
  p_ht numeric DEFAULT 1000, p_tva numeric DEFAULT 200)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pi uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date,
                                 status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
  VALUES (p_t, p_num, p_s, 'Fournisseur L314', '2026-04-10', '2026-05-10',
          'draft', p_ht, p_tva, p_ht + p_tva, 0, p_ht + p_tva, 'pending')
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price,
                                      vat_rate, vat_code, total, vat_amount, line_order)
  VALUES (p_t, pi, 'Achat L314', 1, p_ht, 20, 'FR20', p_ht, p_tva, 1);
  RETURN pi;
END $$;

-- Une note de frais soumise, prête à approuver.
CREATE OR REPLACE FUNCTION _l314_note(p_t uuid, p_e uuid, p_num text,
  p_total numeric DEFAULT 120, p_tva numeric DEFAULT 20)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE er uuid;
BEGIN
  INSERT INTO expense_reports (tenant_id, employee_id, number, period, total_amount, total_vat,
                               status, submitted_at)
  VALUES (p_t, p_e, p_num, '2026-04', p_total, p_tva, 'submitted', '2026-05-12T10:00:00Z')
  RETURNING id INTO er;
  RETURN er;
END $$;

-- Les liens d'un document, avec leur effet et l'aval.
CREATE OR REPLACE FUNCTION _l314_liens(p_t uuid, p_amont_type text, p_amont_id uuid)
RETURNS TABLE(effet text, aval_type text, aval_id uuid, link_type text, payload jsonb)
LANGUAGE sql AS $$
  SELECT dl.effet, dl.aval_type, dl.aval_id, dl.link_type, dl.payload
  FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = p_amont_type AND dl.amont_id = p_amont_id
  ORDER BY dl.effet
$$;

CREATE OR REPLACE FUNCTION _l314_evt(p_t uuid, p_nom text, p_agregat uuid)
RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM domain_events de
  WHERE de.tenant_id = p_t AND de.event_name = p_nom AND de.aggregate_id = p_agregat
$$;

CREATE OR REPLACE FUNCTION _l314_traces(p_t uuid, p_effet text)
RETURNS TABLE(resultat text, duree_ms integer, lignes_ecrites integer)
LANGUAGE sql AS $$
  SELECT ct.resultat, ct.duree_ms, ct.lignes_ecrites FROM chain_traces ct
  WHERE ct.tenant_id = p_t AND ct.effet = p_effet ORDER BY ct.id
$$;

-- ═════════════════════════════════════════════════════════════
-- T01 — Facture d'achat approuvée : le lien, l'événement, la trace
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L4A'); s uuid; pi uuid; v record; n_liens int; n_evt int;
        n_tolere int; n_applique int; v_aval_societe boolean;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur L4', 'F4001') RETURNING id INTO s;
  pi := _l314_achat(t, 'FA-L4-1', s);
  PERFORM _as_user();
  BEGIN
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;

    SELECT * INTO v FROM _l314_liens(t, 'purchase_invoices', pi) LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l314_liens(t, 'purchase_invoices', pi);
    n_evt := _l314_evt(t, 'purchase_invoices.approved', pi);
    SELECT count(*) FILTER (WHERE resultat = 'tolere'),
           count(*) FILTER (WHERE resultat = 'applique')
      INTO n_tolere, n_applique FROM _l314_traces(t, 'purchase.invoice.generated_entry');

    -- L'aval appartient à la même société que le document (T10 le mesure aussi).
    SELECT (je.tenant_id = t) INTO v_aval_societe
    FROM journal_entries je WHERE je.id = v.aval_id;

    PERFORM _rec('T01', 'facture d''achat approuvée → un lien purchase_invoices → journal_entries (code « AC »), un événement, et UNE SEULE trace `applique`',
      n_liens = 1 AND v.aval_type = 'journal_entries' AND v.link_type = 'generated_entry'
        AND v.payload->>'journal_code' = 'AC' AND v_aval_societe
        AND n_evt = 1 AND n_tolere = 0 AND n_applique = 1,
      format('liens=%s aval=%s type=%s payload=%s événements=%s tolere=%s applique=%s',
             n_liens, v.aval_type, v.link_type, v.payload, n_evt, n_tolere, n_applique));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T01', 'facture d''achat approuvée → un lien purchase_invoices → journal_entries (code « AC »), un événement, et UNE SEULE trace `applique`', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — Le fait générateur est l'état, et le rejeu explicite rend false
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L4B'); s uuid; pi uuid; n_liens int; n_traces int;
        v_deja boolean; n_ignore int;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur L4B', 'F4002') RETURNING id INTO s;
  pi := _l314_achat(t, 'FA-L4-2', s);
  PERFORM _as_user();
  BEGIN
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
    -- Une mise à jour qui ne change PAS l'état : le fait générateur ne se rejoue pas.
    UPDATE purchase_invoices SET supplier_name = 'Fournisseur renommé' WHERE id = pi;

    SELECT count(*) INTO n_liens FROM _l314_liens(t, 'purchase_invoices', pi);
    SELECT count(*) INTO n_traces FROM chain_traces
    WHERE tenant_id = t AND effet = 'purchase.invoice.generated_entry';

    -- Le rejeu EXPLICITE de l'entrée du maillon (appelée par le propriétaire,
    -- puisque le socle n'est pas une API) rend false et trace `ignore`.
    EXECUTE 'RESET ROLE';
    v_deja := chain_avant(t, 'purchase_invoices', 'approved', 'purchase.invoice.generated_entry',
                          'purchase_invoices', pi);
    SELECT count(*) INTO n_ignore FROM chain_traces
    WHERE tenant_id = t AND effet = 'purchase.invoice.generated_entry' AND resultat = 'ignore';

    PERFORM _rec('T02', 'l''état est le fait générateur (une mise à jour sans changement n''ajoute ni lien ni trace) et le rejeu explicite rend false en traçant `ignore`',
      n_liens = 1 AND n_traces = 1 AND NOT v_deja AND n_ignore = 1,
      format('liens=%s traces=%s rejeu=%s traces ignore=%s', n_liens, n_traces, v_deja, n_ignore));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'l''état est le fait générateur (une mise à jour sans changement n''ajoute ni lien ni trace) et le rejeu explicite rend false en traçant `ignore`', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- T03 — Note de frais approuvée : DEUX liens, UN événement, UNE mesure
--   Le gabarit multi-effets de la 310 : deux avals (l'écriture « OD » et
--   l'élément de paie), deux liens, un seul fait métier.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L4C'); e uuid; er uuid; n_liens int; n_evt int;
        v_ecriture record; v_element record; v_trace record;
BEGIN
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Employé L4C', 'l4c@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-L4C', '2026-04-01', '2026-04-30', '2026-04-30', 'draft', 0, 0, 0, 1);
  er := _l314_note(t, e, 'NDF-L4-1', 120, 20);

  PERFORM _as_user();
  BEGIN
    UPDATE expense_reports SET status = 'approved' WHERE id = er;

    SELECT * INTO v_ecriture FROM _l314_liens(t, 'expense_reports', er)
     WHERE effet = 'expense.report.generated_entry';
    SELECT * INTO v_element FROM _l314_liens(t, 'expense_reports', er)
     WHERE effet = 'expense.report.payroll_element';
    SELECT count(*) INTO n_liens FROM _l314_liens(t, 'expense_reports', er);
    n_evt := _l314_evt(t, 'expense_reports.approved', er);
    SELECT * INTO v_trace FROM _l314_traces(t, 'expense.report.integration') LIMIT 1;

    PERFORM _rec('T03', 'note de frais approuvée → DEUX liens (écriture « OD » ET élément de paie), un événement, une mesure qui compte les deux',
      n_liens = 2
        AND v_ecriture.aval_type = 'journal_entries' AND v_ecriture.payload->>'journal_code' = 'OD'
        AND v_element.aval_type = 'payroll_variable_elements'
        AND v_element.payload->>'total' IS NOT NULL
        AND (v_element.payload->>'total')::numeric = 120
        AND n_evt = 1 AND v_trace.resultat = 'applique' AND v_trace.lignes_ecrites = 2,
      format('liens=%s (écriture=%s, élément=%s) événements=%s trace=%s/%s lignes',
             n_liens, v_ecriture.aval_type, v_element.aval_type, n_evt,
             v_trace.resultat, v_trace.lignes_ecrites));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T03', 'note de frais approuvée → DEUX liens (écriture « OD » ET élément de paie), un événement, une mesure qui compte les deux', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — Une note à 0 € n'a pas d'écriture, et le compagnon n'invente pas de lien
--   Le maillon n'écrit l'écriture que si le total est positif ; il porte en
--   revanche toujours l'élément de paie (avec 0). Le compagnon doit donc tracer
--   UN lien, pas deux — la limite du vocabulaire (`exécuté, aucun effet`) est
--   dite dans l'en-tête de la 314 : l'absence n'est pas tracée, et rien n'est
--   inventé.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L4D'); e uuid; er uuid; n_liens int; n_ecriture int; n_ecritures_od int;
BEGIN
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Employé L4D', 'l4d@audit.test', 'active', 3000) RETURNING id INTO e;
  er := _l314_note(t, e, 'NDF-L4-2', 0, 0);

  PERFORM _as_user();
  BEGIN
    UPDATE expense_reports SET status = 'approved' WHERE id = er;

    SELECT count(*) INTO n_liens FROM _l314_liens(t, 'expense_reports', er);
    SELECT count(*) INTO n_ecriture FROM _l314_liens(t, 'expense_reports', er)
     WHERE effet = 'expense.report.generated_entry';
    SELECT count(*) INTO n_ecritures_od FROM journal_entries
     WHERE tenant_id = t AND reference = 'EXPENSE-' || (SELECT number FROM expense_reports WHERE id = er);

    PERFORM _rec('T04', 'note de frais à 0 € : aucun lien vers une écriture qui n''existe pas (le maillon ne l''écrit pas), l''élément de paie reste tracé',
      n_liens = 1 AND n_ecriture = 0 AND n_ecritures_od = 0,
      format('liens=%s (dont écriture=%s), écritures OD produites=%s', n_liens, n_ecriture, n_ecritures_od));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04', 'note de frais à 0 € : aucun lien vers une écriture qui n''existe pas (le maillon ne l''écrit pas), l''élément de paie reste tracé', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- T05 — Mode `refuse` + contrat éteint : bloqué AVANT tout effet
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L4E'); s uuid; pi uuid;
        v_refuse boolean := false; v_msg text := 'ACCEPTÉ';
        n_ecritures int; v_statut text;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur L4E', 'F4005') RETURNING id INTO s;
  pi := _l314_achat(t, 'FA-L4-E', s);

  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  VALUES (t, 'purchase_invoices', 'approved', 'purchase.invoice.generated_entry', false)
  ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               document_type, evenement, effet)
  DO UPDATE SET actif = false;
  INSERT INTO chain_settings (tenant_id, enforcement) VALUES (t, 'refuse')
  ON CONFLICT (tenant_id) DO UPDATE SET enforcement = 'refuse';

  PERFORM _as_user();
  BEGIN
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
  EXCEPTION WHEN check_violation THEN
    v_refuse := true; v_msg := SQLERRM;
  END;

  SELECT count(*) INTO n_ecritures FROM journal_entries WHERE tenant_id = t;
  SELECT approval_status INTO v_statut FROM purchase_invoices WHERE id = pi;

  PERFORM _rec('T05', 'mode refuse + contrat éteint : l''approbation est BLOQUÉE avant tout effet (aucune écriture, statut inchangé), avec un message nominatif',
    v_refuse AND v_msg LIKE '%purchase.invoice.generated_entry%' AND n_ecritures = 0
      AND v_statut IS DISTINCT FROM 'approved',
    format('refusé=%s, écritures produites=%s (0), statut=%s — %s',
           v_refuse, n_ecritures, v_statut, left(v_msg, 120)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — La société voisine ne voit ni les liens ni l'événement (RLS)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid := _mk_tenant('L4F1'); s uuid; pi uuid; v_auth_ta uuid;
        tb uuid := _mk_tenant('L4F2', false); v_auth_tb uuid;
        n_liens_ta int; n_evt_ta int; n_liens_tb int; n_evt_tb int;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (ta, 'Fournisseur L4F', 'F4006') RETURNING id INTO s;
  pi := _l314_achat(ta, 'FA-L4-F', s);
  -- Les identités des deux sociétés se lisent AVANT de passer en `authenticated`
  -- (sous le contexte de B, le RLS cache les lignes de A).
  SELECT tu.auth_id INTO v_auth_ta FROM tenant_users tu
  WHERE tu.tenant_id = ta AND tu.status = 'active' ORDER BY tu.auth_id LIMIT 1;
  SELECT tu.auth_id INTO v_auth_tb FROM tenant_users tu
  WHERE tu.tenant_id = tb AND tu.status = 'active' ORDER BY tu.auth_id LIMIT 1;
  s := NULL;  -- (le fournisseur n'est utilisé que pour la facture)

  PERFORM _as_user();
  -- Contexte de A : on approuve, puis on compte ce que A voit.
  PERFORM set_config('request.jwt.claim.sub', v_auth_ta::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_auth_ta, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
  SELECT count(*) INTO n_liens_ta FROM _l314_liens(ta, 'purchase_invoices', pi);
  n_evt_ta := _l314_evt(ta, 'purchase_invoices.approved', pi);

  -- Contexte de B : les mêmes lectures doivent rendre zéro.
  PERFORM set_config('request.jwt.claim.sub', v_auth_tb::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_auth_tb, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', tb::text, false);
  SELECT count(*) INTO n_liens_tb FROM document_links
  WHERE amont_type = 'purchase_invoices' AND amont_id = pi;
  SELECT count(*) INTO n_evt_tb FROM domain_events
  WHERE event_name = 'purchase_invoices.approved' AND aggregate_id = pi;

  PERFORM _rec('T06', 'la société voisine ne voit ni le lien ni l''événement de la facture d''achat tracée',
    n_liens_ta = 1 AND n_evt_ta = 1 AND n_liens_tb = 0 AND n_evt_tb = 0,
    format('chez A : liens=%s événements=%s | chez B : liens=%s événements=%s',
           n_liens_ta, n_evt_ta, n_liens_tb, n_evt_tb));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T07 — L'ordre des déclencheurs est prouvé (doctrine de la 310, T10)
--   Un compagnon n'est utile que s'il s'exécute APRÈS le maillon métier : même
--   table, même événement, nom qui trie après lui.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_compagnons int; n_apres int; n_freres_avant int; n_freres_apres int;
BEGIN
  SELECT count(*) INTO n_compagnons FROM pg_trigger t
  WHERE NOT t.tgisinternal
    AND t.tgname IN ('zz_l1_purchase_invoice_entry', 'zz_l1_expense_report_integration');

  SELECT count(*) INTO n_apres FROM pg_trigger t
  WHERE NOT t.tgisinternal
    AND t.tgname IN ('zz_l1_purchase_invoice_entry', 'zz_l1_expense_report_integration')
    AND (t.tgtype & 2) = 0;      -- 0 = AFTER

  SELECT count(*) INTO n_freres_avant
  FROM pg_trigger c
  JOIN pg_trigger s ON s.tgrelid = c.tgrelid AND s.tgtype = c.tgtype
                   AND NOT s.tgisinternal AND s.tgname < c.tgname
  WHERE NOT c.tgisinternal
    AND c.tgname IN ('zz_l1_purchase_invoice_entry', 'zz_l1_expense_report_integration');

  SELECT count(*) INTO n_freres_apres
  FROM pg_trigger c
  JOIN pg_trigger s ON s.tgrelid = c.tgrelid AND s.tgtype = c.tgtype
                   AND NOT s.tgisinternal AND s.tgname > c.tgname
  WHERE NOT c.tgisinternal
    AND c.tgname IN ('zz_l1_purchase_invoice_entry', 'zz_l1_expense_report_integration');

  PERFORM _rec('T07', 'les deux compagnons sont des déclencheurs APRÈS, chacun trie après un frère métier de même événement, et aucun frère ne trie après eux',
    n_compagnons = 2 AND n_apres = 2 AND n_freres_avant >= 2 AND n_freres_apres = 0,
    format('compagnons=%s (après=%s), frères qui trient avant=%s, frères qui trient après=%s (0 attendu)',
           n_compagnons, n_apres, n_freres_avant, n_freres_apres));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — Les compagnons ne sont pas des points d'entrée (aucun EXECUTE)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_total int; n_exposes int;
BEGIN
  SELECT count(*) INTO n_total FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.proname IN ('chain_l1_purchase_invoice_entry', 'chain_l1_expense_report_integration');

  SELECT count(*) INTO n_exposes FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.proname IN ('chain_l1_purchase_invoice_entry', 'chain_l1_expense_report_integration')
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

  PERFORM _rec('T08', 'les deux compagnons sont révoqués : aucun EXECUTE pour un utilisateur connecté — le socle n''est pas une API',
    n_total = 2 AND n_exposes = 0,
    format('compagnons=%s (2 attendus), exposés à `authenticated`=%s (0 attendu)', n_total, n_exposes));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T09 — Les trois contrats sont en base, avec les drapeaux MESURÉS
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_ok int;
BEGIN
  SELECT count(*) INTO n_ok FROM document_effects e
  WHERE e.tenant_id IS NULL AND e.actif AND (
    (e.effet = 'purchase.invoice.generated_entry'
      AND e.document_type = 'purchase_invoices' AND e.evenement = 'approved'
      AND e.ecrit_comptable AND e.journal_code = 'AC'
      AND NOT e.touche_stock AND NOT e.touche_paie)
    OR
    (e.effet = 'expense.report.generated_entry'
      AND e.document_type = 'expense_reports' AND e.evenement = 'approved'
      AND e.ecrit_comptable AND e.journal_code = 'OD' AND NOT e.touche_paie)
    OR
    (e.effet = 'expense.report.payroll_element'
      AND e.document_type = 'expense_reports' AND e.evenement = 'approved'
      AND NOT e.ecrit_comptable AND e.touche_paie));

  PERFORM _rec('T09', 'les trois contrats sont déclarés et actifs, avec leurs drapeaux mesurés (AC comptable, OD comptable, élément de paie)',
    n_ok = 3, format('contrats conformes=%s (3 attendus)', n_ok));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T10 — Le cloisonnement du lien : l'aval appartient à la société du document
--   Le lien est écrit par un compagnon `SECURITY DEFINER` : il ne doit jamais
--   désigner une pièce d'une autre société (la leçon d'ISO-02, en données).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_liens int; n_croises int;
BEGIN
  SELECT count(*) INTO n_liens FROM document_links dl
  WHERE dl.effet IN ('purchase.invoice.generated_entry', 'expense.report.generated_entry',
                     'expense.report.payroll_element');

  SELECT count(*) INTO n_croises FROM document_links dl
  WHERE dl.effet IN ('purchase.invoice.generated_entry', 'expense.report.generated_entry',
                     'expense.report.payroll_element')
    AND (
      (dl.aval_type = 'journal_entries' AND NOT EXISTS (
         SELECT 1 FROM journal_entries j WHERE j.id = dl.aval_id AND j.tenant_id = dl.tenant_id))
      OR
      (dl.aval_type = 'payroll_variable_elements' AND NOT EXISTS (
         SELECT 1 FROM payroll_variable_elements p WHERE p.id = dl.aval_id AND p.tenant_id = dl.tenant_id))
    );

  PERFORM _rec('T10', 'aucun lien posé par les compagnons ne désigne un aval d''une autre société',
    n_liens >= 3 AND n_croises = 0,
    format('liens mesurés=%s (3 au moins), liens inter-société=%s (0 attendu)', n_liens, n_croises));
END $$;

-- ─────────────────────────────────────────────────────────────
-- Le registre des échecs attendus reste VIDE : aucun scénario de ce fichier n'a
-- le droit d'échouer (doctrine AUD-A02).
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('314');

