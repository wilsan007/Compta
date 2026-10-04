-- ═══════════════════════════════════════════════════════════════════════════
-- 455 — Partie 5 : INV-19 devient MESURABLE (« aucun document aval n'est
--       orphelin de son amont »)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- La 413 avait inscrit INV-19 « non mesurable », avec une raison exacte : sans
-- registre des types, rien ne permettait de résoudre `amont_type` en table.
-- Le registre existe (450) : la raison tombe, l'invariant se mesure.
--
-- Ce fichier :
--   1. passe INV-19 à `mesurable = true` (raison effacée) ;
--   2. réécrit `chain_invariant_mesurer` À L'IDENTIQUE (corps relevé sur une
--      base neuve à jour, par pg_get_functiondef) en ajoutant UNE
--      branche, `INV-19`, juste avant la branche finale qui lève une erreur.
--
-- ⚠️ Toute migration qui réécrit à nouveau `chain_invariant_mesurer` DOIT
-- partir du corps relevé sur une base neuve qui contient la 455 — sinon elle
-- efface la branche INV-19 en silence. La suite 450 (T12) le détecte.
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.chain_invariants
   SET mesurable = true,
       raison_non_mesurable = NULL
 WHERE code = 'INV-19' AND tenant_id IS NULL;

CREATE OR REPLACE FUNCTION public.chain_invariant_mesurer(p_tenant uuid, p_code text, OUT mesure_a numeric, OUT mesure_b numeric, OUT ecart numeric, OUT lignes_en_ecart integer, OUT detail jsonb)
 RETURNS record
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_a  numeric;
  v_b  numeric;
  v_n  integer := 0;
  v_n2 integer := 0;
  v_n3 integer := 0;
  v_t   record;          -- 455 : INV-19, un type du registre
  v_ids uuid[] := '{}';  -- 455 : INV-19, les liens orphelins (sans doublon)
  v_lot uuid[];          -- 455 : INV-19, le lot rendu par une requête dynamique
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'chain_invariant_mesurer : p_tenant est obligatoire';
  END IF;

  detail := '{}'::jsonb;

  -- ── INV-01 — le stock valorisé (couches restantes) vs le solde des comptes de
  --    stock (31x). La variation (603x) n'est passée qu'à la clôture : un écart
  --    en exercice courant est attendu, et le registre le dit.
  IF p_code = 'INV-01' THEN
    SELECT COALESCE(SUM(remaining_qty * unit_cost), 0) INTO v_a
      FROM stock_valuation_layers WHERE tenant_id = p_tenant;
    SELECT COALESCE(SUM(debit - credit), 0) INTO v_b
      FROM journal_lines
     WHERE tenant_id = p_tenant AND account_code LIKE '31%';

  -- ── INV-02 — la quantité par dépôt vs la somme des mouvements. `transfer` et
  --    `adjustment` n'ont aucun signe stocké (quantity >= 0 par contrainte) :
  --    ils sont exclus du calcul, et leur nombre est publié.
  ELSIF p_code = 'INV-02' THEN
    SELECT COALESCE(SUM(quantity), 0) INTO v_a
      FROM stock_quantities WHERE tenant_id = p_tenant;
    SELECT COALESCE(SUM(CASE WHEN type IN ('in', 'initial') THEN quantity
                             WHEN type = 'out'              THEN -quantity
                             ELSE 0 END), 0),
           COUNT(*) FILTER (WHERE type IN ('transfer', 'adjustment'))
      INTO v_b, v_n2
      FROM stock_movements WHERE tenant_id = p_tenant;
    detail := jsonb_build_object('mouvements_ambigus', v_n2);

  -- ── INV-03 — rien n'est réservé sans commande confirmée non livrée. Une
  --    réservation est une quantité, une commande un document : le contrôle est
  --    une **implication**, pas une égalité de montants.
  ELSIF p_code = 'INV-03' THEN
    SELECT COUNT(*) INTO v_n FROM stock_quantities
     WHERE tenant_id = p_tenant AND COALESCE(reserved_quantity, 0) > 0;
    SELECT COUNT(*) INTO v_n2 FROM sales_orders
     WHERE tenant_id = p_tenant AND status = 'confirmed'
       AND COALESCE(fully_delivered, false) = false;
    v_a := v_n::numeric;
    v_b := v_n2::numeric;
    lignes_en_ecart := CASE WHEN v_n > 0 AND v_n2 = 0 THEN v_n ELSE 0 END;
    detail := jsonb_build_object(
      'lignes_reservees', v_n, 'commandes_confirmees_non_livrees', v_n2);

  -- ── INV-04 — aucun pointage, temps projet ou frais un jour d'absence
  --    bloquante. Trois tables ; chaque violation est comptée.
  ELSIF p_code = 'INV-04' THEN
    WITH absences AS (
      SELECT a.employee_id, a.day,
        (SELECT COUNT(*) FROM timesheets x
          WHERE x.tenant_id = p_tenant AND x.employee_id = a.employee_id
            AND x.date = a.day) AS c_pointage,
        (SELECT COUNT(*) FROM project_time_entries y
          WHERE y.tenant_id = p_tenant AND y.employee_id = a.employee_id
            AND y.start_time::date = a.day) AS c_temps,
        (SELECT COUNT(*) FROM expense_report_lines l
           JOIN expense_reports r ON r.id = l.expense_report_id
          WHERE l.tenant_id = p_tenant AND r.employee_id = a.employee_id
            AND l.date = a.day) AS c_frais
        FROM employee_absence_days a
       WHERE a.tenant_id = p_tenant AND a.blocks_work
    )
    SELECT COALESCE(SUM(c_pointage), 0)::int, COALESCE(SUM(c_temps), 0)::int,
           COALESCE(SUM(c_frais), 0)::int
      INTO v_n, v_n2, v_n3 FROM absences;
    lignes_en_ecart := v_n + v_n2 + v_n3;
    detail := jsonb_build_object(
      'pointages', v_n, 'temps_projet', v_n2, 'frais', v_n3);

  -- ── INV-09 — le net à payer des bulletins vs le montant du virement. Les deux
  --    côtés portent `pay_run_id` : l'appariement est exact. Un lot sans ordre de
  --    virement n'est pas un écart (il n'est pas encore payé) : il est compté à
  --    part, et **seuls** les lots rapprochés entrent dans l'écart.
  ELSIF p_code = 'INV-09' THEN
    SELECT COALESCE(SUM(s.net), 0),
           COALESCE(SUM(CASE WHEN o.id IS NOT NULL THEN o.total_amount END), 0),
           COUNT(*) FILTER (WHERE o.id IS NULL),
           COUNT(*) FILTER (WHERE o.id IS NOT NULL
                              AND abs(s.net - o.total_amount) > 0.01)
      INTO v_a, v_b, v_n2, v_n
      FROM (SELECT pay_run_id, SUM(COALESCE(net_salary, 0)) AS net
              FROM pay_slips WHERE tenant_id = p_tenant GROUP BY pay_run_id) s
      LEFT JOIN sepa_payment_orders o
        ON o.pay_run_id = s.pay_run_id AND o.tenant_id = p_tenant;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('lots_sans_virement', v_n2, 'lots_en_ecart', v_n);

  -- ── INV-11 — le temps facturé ne dépasse pas le temps saisi. `invoice_lines.
  --    time_entry_id` rend le rattachement exact : aucune hypothèse.
  ELSIF p_code = 'INV-11' THEN
    SELECT COALESCE(SUM(p.duration_seconds), 0) INTO v_a
      FROM project_time_entries p
     WHERE p.tenant_id = p_tenant
       AND EXISTS (SELECT 1 FROM invoice_lines il
                    WHERE il.tenant_id = p_tenant AND il.time_entry_id = p.id);
    SELECT COALESCE(SUM(duration_seconds), 0) INTO v_b
      FROM project_time_entries
     WHERE tenant_id = p_tenant AND COALESCE(is_billable, false);
    -- les pointages facturés alors qu'ils ne sont pas facturables
    SELECT COUNT(*) INTO v_n
      FROM project_time_entries p
     WHERE p.tenant_id = p_tenant
       AND COALESCE(p.is_billable, false) = false
       AND EXISTS (SELECT 1 FROM invoice_lines il
                    WHERE il.tenant_id = p_tenant AND il.time_entry_id = p.id);
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('factures_non_facturables', v_n);

  -- ── INV-13 — l'amortissement cumulé vs le solde des comptes 28x.
  ELSIF p_code = 'INV-13' THEN
    SELECT COALESCE(SUM(amount), 0) INTO v_a
      FROM asset_depreciations WHERE tenant_id = p_tenant;
    SELECT COALESCE(SUM(credit - debit), 0) INTO v_b
      FROM journal_lines
     WHERE tenant_id = p_tenant AND account_code LIKE '28%';

  -- ── INV-14 — la TVA déclarée vs la TVA comptabilisée de la période. Le
  --    contrôle est **par déclaration** : chacune est confrontée à la TVA
  --    collectée comptabilisée entre ses dates (comptes 4457x).
  ELSIF p_code = 'INV-14' THEN
    WITH d AS (
      SELECT COALESCE(v.vat_collected, 0) AS declare,
             (SELECT COALESCE(SUM(jl.credit - jl.debit), 0)
                FROM journal_lines jl
                JOIN journal_entries je ON je.id = jl.journal_id
               WHERE jl.tenant_id = p_tenant
                 AND jl.account_code LIKE '4457%'
                 AND COALESCE(jl.line_date, je.date)::date
                     BETWEEN v.period_start AND v.period_end) AS comptabilise
        FROM vat_returns v
       WHERE v.tenant_id = p_tenant AND v.status <> 'draft'
    )
    SELECT COALESCE(SUM(declare), 0), COALESCE(SUM(comptabilise), 0),
           COUNT(*) FILTER (WHERE abs(declare - comptabilise) > 0.01),
           COUNT(*)
      INTO v_a, v_b, v_n, v_n2 FROM d;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object(
      'declarations_en_ecart', v_n, 'declarations_controlees', v_n2);

  -- ── INV-15 — la recette TTC de caisse vs le débit des écritures qui portent
  --    les tickets. La clé est celle que la 219 écrit :
  --    `journal_entries.reference = 'POS-' || pos_tickets.id`. Le préfixe
  --    'POS-AV-' (avoirs) est **exclu** : ce n'est pas une recette de ticket.
  ELSIF p_code = 'INV-15' THEN
    SELECT COALESCE(SUM(total), 0) INTO v_a
      FROM pos_tickets
     WHERE tenant_id = p_tenant AND COALESCE(is_voided, false) = false;
    SELECT COALESCE(SUM(jl.debit), 0) INTO v_b
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_id
     WHERE jl.tenant_id = p_tenant
       AND je.reference LIKE 'POS-%'
       AND je.reference NOT LIKE 'POS-AV-%';
    SELECT COUNT(*) INTO v_n
      FROM pos_tickets t
     WHERE t.tenant_id = p_tenant AND COALESCE(t.is_voided, false) = false
       AND NOT EXISTS (SELECT 1 FROM journal_entries je
                        WHERE je.tenant_id = p_tenant
                          AND je.reference = 'POS-' || t.id);
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('tickets_sans_ecriture', v_n);

  -- ── INV-16 — la chaîne de hachage NF-525 sans rupture. Le contrôle ne
  --    réinvente rien : il refait, en une requête, ce que `verify_nf525_chain`
  --    (233) vérifie ligne à ligne — chaque `previous_hash` doit valoir le
  --    `current_hash` de la ligne précédente, dans l'ordre des identifiants.
  --    Refait ici et non **appelé** : `verify_nf525_chain` lit
  --    `current_tenant_id()`, qui exige une session utilisateur ; le job
  --    nocturne n'en a pas.
  ELSIF p_code = 'INV-16' THEN
    WITH e AS (
      SELECT previous_hash,
             LAG(current_hash) OVER (ORDER BY id) AS attendu
        FROM nf525_event_log WHERE tenant_id = p_tenant
    )
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE attendu IS NOT NULL
                              AND previous_hash IS DISTINCT FROM attendu)
      INTO v_a, v_n FROM e;
    v_n := COALESCE(v_n, 0);
    v_b := v_n::numeric;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object(
      'evenements', COALESCE(v_a, 0)::int, 'ruptures', v_n);

  -- ── INV-17 — aucune écriture sur un exercice ou une période fermés.
  ELSIF p_code = 'INV-17' THEN
    SELECT COUNT(*) INTO v_n
      FROM journal_entries je
     WHERE je.tenant_id = p_tenant
       AND (EXISTS (SELECT 1 FROM fiscal_periods fp
                     WHERE fp.id = je.fiscal_period_id
                       AND fp.status IN ('closed', 'locked'))
         OR EXISTS (SELECT 1 FROM fiscal_years fy
                     WHERE fy.id = je.fiscal_year_id
                       AND (fy.status IN ('closed', 'locked')
                            OR fy.closed_at IS NOT NULL)));
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('ecritures_sur_periode_fermee', v_n);

  -- ── INV-18 — tout document validé a un numéro définitif, sans trou : par
  --    journal et par exercice, le dernier numéro servi doit égaler le nombre de
  --    numéros attribués.
  ELSIF p_code = 'INV-18' THEN
    WITH s AS (
      SELECT journal_code, fiscal_year_id, COALESCE(last_seq, 0) AS last_seq
        FROM journal_posting_sequences WHERE tenant_id = p_tenant),
    e AS (
      SELECT journal_code, fiscal_year_id, COUNT(*)::int AS n
        FROM journal_entries
       WHERE tenant_id = p_tenant AND posting_number IS NOT NULL
       GROUP BY journal_code, fiscal_year_id)
    SELECT COALESCE(SUM(s.last_seq), 0), COALESCE(SUM(COALESCE(e.n, 0)), 0),
           COUNT(*) FILTER (WHERE s.last_seq <> COALESCE(e.n, 0))
      INTO v_a, v_b, v_n
      FROM s LEFT JOIN e USING (journal_code, fiscal_year_id);
    lignes_en_ecart := COALESCE(v_n, 0);
    detail := jsonb_build_object('journaux_en_ecart', COALESCE(v_n, 0));

  -- ── INV-20 — toute ligne de paie variable a une source identifiée.
  ELSIF p_code = 'INV-20' THEN
    SELECT COUNT(*) INTO v_n
      FROM payroll_variable_elements
     WHERE tenant_id = p_tenant AND btrim(COALESCE(source, '')) = '';
    lignes_en_ecart := v_n;
    SELECT COALESCE(jsonb_object_agg(element_type, c), '{}'::jsonb) INTO detail
      FROM (SELECT COALESCE(element_type, '(nul)') AS element_type, COUNT(*) AS c
              FROM payroll_variable_elements
             WHERE tenant_id = p_tenant AND btrim(COALESCE(source, '')) = ''
             GROUP BY 1) s;

  -- ── INV-19 (455, Partie 5) — aucun lien ACTIF ne pointe vers un document,
  --    ou une ligne amont, qui n'existe plus dans la société. Le type se résout
  --    par le registre 450 ; un lien dont le type n'y est pas (base ancienne,
  --    contrainte NOT VALID) compte aussi comme orphelin. Chaque lien est
  --    compté UNE fois, même si l'amont et l'aval ont disparu tous les deux.
  ELSIF p_code = 'INV-19' THEN
    SELECT count(*) INTO v_n2
    FROM document_links WHERE tenant_id = p_tenant AND etat = 'actif';

    FOR v_t IN SELECT code, table_name, ligne_table FROM chain_document_types LOOP
      EXECUTE format(
        'SELECT array_agg(l.id) FROM document_links l
          WHERE l.tenant_id = $1 AND l.etat = ''actif'' AND l.amont_type = $2
            AND NOT EXISTS (SELECT 1 FROM public.%I d WHERE d.id = l.amont_id AND d.tenant_id = $1)',
        v_t.table_name) INTO v_lot USING p_tenant, v_t.code;
      v_ids := v_ids || COALESCE(v_lot, '{}');

      EXECUTE format(
        'SELECT array_agg(l.id) FROM document_links l
          WHERE l.tenant_id = $1 AND l.etat = ''actif'' AND l.aval_type = $2
            AND NOT EXISTS (SELECT 1 FROM public.%I d WHERE d.id = l.aval_id AND d.tenant_id = $1)',
        v_t.table_name) INTO v_lot USING p_tenant, v_t.code;
      v_ids := v_ids || COALESCE(v_lot, '{}');

      IF v_t.ligne_table IS NOT NULL THEN
        EXECUTE format(
          'SELECT array_agg(l.id) FROM document_links l
            WHERE l.tenant_id = $1 AND l.etat = ''actif'' AND l.amont_type = $2
              AND l.amont_ligne_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM public.%I d WHERE d.id = l.amont_ligne_id AND d.tenant_id = $1)',
          v_t.ligne_table) INTO v_lot USING p_tenant, v_t.code;
        v_ids := v_ids || COALESCE(v_lot, '{}');
      END IF;
    END LOOP;

    SELECT array_agg(l.id) INTO v_lot
    FROM document_links l
    WHERE l.tenant_id = p_tenant AND l.etat = 'actif'
      AND (NOT EXISTS (SELECT 1 FROM chain_document_types d WHERE d.code = l.amont_type)
        OR NOT EXISTS (SELECT 1 FROM chain_document_types d WHERE d.code = l.aval_type));
    v_ids := v_ids || COALESCE(v_lot, '{}');

    SELECT count(DISTINCT x) INTO v_n FROM unnest(v_ids) AS x;
    v_a := v_n2::numeric;
    v_b := (v_n2 - v_n)::numeric;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object(
      'liens_actifs', v_n2, 'liens_orphelins', v_n,
      'exemples', (SELECT to_jsonb(array_agg(e.x))
                     FROM (SELECT DISTINCT x FROM unnest(v_ids) AS x LIMIT 5) e));
  -- Un code inscrit `mesurable` sans branche de mesure est un mensonge : il
  -- produirait un relevé vide lu comme « tout va bien ». Il doit crier.
  ELSE
    RAISE EXCEPTION
      'chain_invariant_mesurer : % n''a aucune branche de mesure. Un invariant '
      'inscrit mesurable sans contrôle produit un relevé vide — corrigez le '
      'registre (mesurable = false, avec sa raison) ou écrivez la branche.',
      p_code;
  END IF;

  mesure_a := v_a;
  mesure_b := v_b;
  IF v_a IS NOT NULL AND v_b IS NOT NULL THEN
    ecart := abs(v_a - v_b);
  END IF;
  lignes_en_ecart := COALESCE(lignes_en_ecart, 0);
END
$function$;

REVOKE ALL ON FUNCTION public.chain_invariant_mesurer(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_invariant_mesurer(uuid, text) TO service_role;
