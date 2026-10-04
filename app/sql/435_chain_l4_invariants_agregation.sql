-- ══════════════════════════════════════════════════════════════
-- 435 — LES INVARIANTS RESTANTS, MESURÉS PAR AGRÉGATION
--
-- Le reproche fait à ces invariants était « la donnée n'est pas stockée ».
-- C'est souvent vrai — et souvent SANS IMPORTANCE : quand les deux côtés de
-- l'égalité se répondent, il suffit de CALCULER le côté manquant au lieu de
-- le dupliquer dans une colonne que personne ne tient à jour.
--
-- Aucune table métier n'est touchée ici. C'est délibéré : les colonnes
-- manquantes vivaient dans des tables partagées avec d'autres chantiers, et
-- ajouter une colonne pour y stocker un calcul que la base sait déjà faire,
-- c'est créer une seconde vérité à désynchroniser.
-- ══════════════════════════════════════════════════════════════

  -- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chain_invariant_mesurer(
  p_tenant uuid,
  p_code   text,
  OUT mesure_a        numeric,
  OUT mesure_b        numeric,
  OUT ecart           numeric,
  OUT lignes_en_ecart integer,
  OUT detail          jsonb
) RETURNS RECORD
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_a  numeric;
  v_b  numeric;
  v_n  integer := 0;
  v_n2 integer := 0;
  v_n3 integer := 0;
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

  -- Un code inscrit `mesurable` sans branche de mesure est un mensonge : il
  -- produirait un relevé vide lu comme « tout va bien ». Il doit crier.
  ELSIF p_code = 'INV-05' THEN
    SELECT COALESCE(SUM(c.engage), 0),
           COALESCE(SUM(c.reste), 0),
           COUNT(*) FILTER (WHERE abs(COALESCE(c.engage,0) - COALESCE(c.reste,0)) > 0.01),
           COUNT(*)
      INTO v_a, v_b, v_n, v_n2
      FROM (
        SELECT bc.amount AS engage,
               COALESCE(cmd.total, 0) - COALESCE(f.facture, 0) AS reste
          FROM budget_commitments bc
          JOIN (
            SELECT pol.purchase_order_id,
                   SUM(COALESCE(pol.line_total, 0)) AS total
              FROM purchase_order_lines pol
             WHERE pol.tenant_id = p_tenant
             GROUP BY pol.purchase_order_id
          ) cmd ON cmd.purchase_order_id = bc.source_id
          LEFT JOIN LATERAL (
            SELECT SUM(COALESCE(pi.total, 0)) AS facture
              FROM purchase_invoices pi
             WHERE pi.purchase_order_id = cmd.purchase_order_id
               AND pi.tenant_id = p_tenant
               AND COALESCE(pi.status,'') NOT IN ('draft','cancelled')
          ) f ON true
         WHERE bc.tenant_id = p_tenant
           AND bc.source_type = 'purchase_order'
           AND COALESCE(bc.status,'') NOT IN ('cancelled','released')
      ) c;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('engagements', v_n2, 'engagements_en_ecart', v_n);

  -- ── INV-06 — Le réalisé budgétaire égale les mouvements ──────────
  -- `budgets` porte le BUDGET (period_1 … period_12). Le RÉALISÉ se lit dans
  -- les lignes d'écriture des mêmes comptes. On exclut brouillons, à-nouveaux
  -- et clôture : les compter reviendrait à comparer un budget d'exploitation
  -- à des écritures qui ne le portent pas encore.
  ELSIF p_code = 'INV-06' THEN
    WITH b AS (
      SELECT account_code,
             (COALESCE(period_1,0)+COALESCE(period_2,0)+COALESCE(period_3,0)
             +COALESCE(period_4,0)+COALESCE(period_5,0)+COALESCE(period_6,0)
             +COALESCE(period_7,0)+COALESCE(period_8,0)+COALESCE(period_9,0)
             +COALESCE(period_10,0)+COALESCE(period_11,0)+COALESCE(period_12,0)) AS budget
        FROM budgets
       WHERE tenant_id = p_tenant
    ), r AS (
      SELECT jl.account_code,
             SUM(COALESCE(jl.debit,0) - COALESCE(jl.credit,0)) AS realise
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_id
       WHERE jl.tenant_id = p_tenant
         AND COALESCE(je.status,'') NOT IN ('draft','opening','closing')
         AND COALESCE(je.journal_code,'') NOT IN ('AN','CL')
       GROUP BY jl.account_code
    )
    SELECT COALESCE(SUM(r.realise), 0), COALESCE(SUM(b.budget), 0),
           COUNT(*) FILTER (WHERE abs(COALESCE(r.realise,0) - COALESCE(b.budget,0)) > 0.01),
           COUNT(*)
      INTO v_a, v_b, v_n, v_n2
      FROM b LEFT JOIN r ON r.account_code = b.account_code;

    lignes_en_ecart := v_n;
    detail := jsonb_build_object('comptes_budgetes', v_n2, 'comptes_en_ecart', v_n);

  ELSIF p_code = 'INV-08' THEN
    SELECT COALESCE(SUM(m.mouvements), 0),
           COALESCE(SUM(m.encours), 0),
           CASE WHEN abs(COALESCE(SUM(m.mouvements),0) - COALESCE(SUM(m.encours),0)) > 0.01
                THEN 1 ELSE 0 END,
           COUNT(*)
      INTO v_a, v_b, v_n, v_n2
      FROM (
        SELECT ba.id,
               COALESCE(SUM(CASE WHEN bt.type = 'credit' THEN bt.amount
                                 WHEN bt.type = 'debit'  THEN -bt.amount END), 0) AS mouvements,
               COALESCE(ba.balance, 0) AS encours
          FROM bank_accounts ba
          LEFT JOIN bank_transactions bt
            ON bt.bank_account_id = ba.id
           AND bt.tenant_id = ba.tenant_id
           AND COALESCE(bt.type,'') <> 'draft'
         WHERE ba.tenant_id = p_tenant
         GROUP BY ba.id, ba.balance
      ) m;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('comptes_banque', v_n2, 'ecart_global', v_n);

  -- ── INV-19 — Aucun document aval n'est orphelin de son amont ──────
  -- `amont_type` est un texte libre : c'est précisément ce qui rend l'orphelin
  -- mesurable. Pour chaque lien, on vérifie que l'amont existe dans la table
  -- que ce type désigne — une intégrité référentielle SANS clé étrangère.
  -- Moins solide qu'une FK, mais elle est VÉRIFIÉE, là où rien ne l'était.
  --
  -- ⚠️ La liste des types autorisés est ÉCRITE ICI, pas déduite de la donnée.
  -- Construire un nom de table depuis un `amont_type` venu des liens serait
  -- une injection : un lien forgé pourrait faire lire une autre table. Un type
  -- hors de cette liste n'est pas « interpreté » — il est compté comme
  -- orphelin, ce qui est la seule conduite honnête quand le type est inconnu.
  -- ⚠️ L'ordre des OUT compte : le relevé attend `mesure_a` puis `mesure_b`.
  -- Ici `mesure_b` est le nombre d'ORPHELINS — c'est lui qui doit alimenter
  -- `lignes_en_ecart`, parce que c'est ce compteur que le verdict « existence »
  -- regarde. Prendre `v_n` (le total des liens) donnait 22 lignes en écart sur
  -- une société dont aucun lien n'est orphelin : l'invariant criait au DOUBLE,
  -- sana : c'est le mot juste, « sain » serait une contrepartie ironique.
  ELSIF p_code = 'INV-19' THEN
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE dl.amont_id IS NULL
                               OR (dl.amont_type = 'bank_transactions'
                                   AND NOT EXISTS (SELECT 1 FROM bank_transactions x
                                                    WHERE x.id = dl.amont_id AND x.tenant_id = dl.tenant_id))
                               OR (dl.amont_type = 'bank_accounts'
                                   AND NOT EXISTS (SELECT 1 FROM bank_accounts x
                                                    WHERE x.id = dl.amont_id AND x.tenant_id = dl.tenant_id))
                               OR (dl.amont_type = 'pay_runs'
                                   AND NOT EXISTS (SELECT 1 FROM pay_runs x
                                                    WHERE x.id = dl.amont_id AND x.tenant_id = dl.tenant_id))
                               OR (dl.amont_type = 'pos_tickets'
                                   AND NOT EXISTS (SELECT 1 FROM pos_tickets x
                                                    WHERE x.id = dl.amont_id AND x.tenant_id = dl.tenant_id))
                               OR dl.amont_type NOT IN ('bank_transactions','bank_accounts',
                                                        'pay_runs','pos_tickets')),
           COUNT(*)
      INTO v_a, v_b, v_n, v_n2
      FROM document_links dl
     WHERE dl.tenant_id = p_tenant;

    -- c'est le compteur d'orphelins qui décide, pas l'écart
    lignes_en_ecart := v_b;
    detail := jsonb_build_object('liens', v_n2, 'liens_orphelins', v_n);
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
$fn$;

-- 2. LE REGISTRE — quatre invariants deviennent mesurables
--
-- On ne les déclare mesurables qu'APRÈS avoir écrit leur branche : un
-- `mesurable = true` sans contrôle produirait un relevé VIDE, lu comme « tout
-- va bien ». La 413 fait déjà crier ce cas ; on ne le contourne pas.
-- ══════════════════════════════════════════════════════════════
UPDATE chain_invariants
   SET mesurable = true,
       raison_non_mesurable = NULL,
       note = '435 : mesuré par agrégation — le côté manquant se CALCULE, il ne se stocke pas.'
 WHERE code IN ('INV-05','INV-06','INV-08','INV-19')
   AND tenant_id IS NULL;

-- INV-12 reste NON mesurable, et sa raison est désormais VÉRIFIÉE plutôt
-- que supposée : `v_project_profitability` n'agrège que des HEURES
-- (`project_tasks.effort_spent_h`). L'invariant veut « facturé − temps −
-- achats − stock − frais » : il manque les trois derniers termes. Recalculer
-- « facturé − temps » et le comparer au coût publié ne mesurerait pas
-- l'invariant — cela mesurerait un invariant plus faible sous le même nom.
-- Réduire la définition pour la rendre mesurable serait exactement le défaut
-- que ce registre prétend punished.
UPDATE chain_invariants
   SET note = '435 : toujours non mesurable, et pour une raison vérifiée.'
 WHERE code = 'INV-12' AND tenant_id IS NULL;

COMMENT ON FUNCTION public.chain_invariant_mesurer(uuid, text) IS
  '413 (L4) + 435 : mesure UN invariant transversal pour une société. Les branches INV-05, INV-06, INV-08 et INV-19 ont été ajoutées par la 435 — elles CALCULENT le côté manquant (reste à facturer, réalisé, solde de relevé, amont existant) au lieu d''exiger qu''il soit stocké dans une colonne que personne ne tiendrait à jour. Lève une exception si le code est inscrit mesurable mais n''a aucune branche — un relevé vide ne doit jamais passer pour un invariant tenu.';
  -- Le « reste à facturer » n'est stocké nulle part : il se CALCULE. Pour
  -- chaque commande engagée, le total de ses lignes moins ce qui a déjà été
  -- facturé dessus.