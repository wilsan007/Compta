-- ═══════════════════════════════════════════════════════════════════════════
-- 768_chain_l18_imputation_analytique_tests.sql — L18, tranche 2 (fin) :
--       L'IMPUTATION ANALYTIQUE du stock — la section circule jusqu'au livre
-- ═══════════════════════════════════════════════════════════════════════════
-- La 418 (tranche 1) imputait le COÛT d'un chantier (projects.actual_cost) ;
-- la 767 reliait le projet à son OF. Il manque la pièce du plan L18 dite
-- « avec imputation analytique » et retenue comme LIMITE par la tranche 1
-- (§5.2 : « elle supposerait stock_movements.analytic_section_id, que la 304
-- n'a posé que sur les lignes de facture et d'achat ») : le stock ne portait
-- aucune section — la balance analytique ne pouvait égaler la balance
-- générale en dehors des ventes et des achats (limite W7 reprise par la 304).
--
-- ROUGE D'ABORD : T01 (porteur) tombe sur les colonnes absentes ; T02
-- s'arrête net sur `column "analytic_section_id" of relation
-- "stock_movements" does not exist` — le défaut EST l'absence.
--
-- Les huit verdicts : T01 le porteur (2 colonnes + 2 clés composites) ·
-- T02 le cloisonnement du mouvement (clé nommée) · T03 le cloisonnement de
-- l'OF · T04a le nettoyage du porteur à la suppression (SET NULL) · T04b
-- l'écriture postée PROTÈGE sa section (inaltérabilité W2, conflit nommé) ·
-- T05 la circulation sur la SORTIE de chantier (écriture STK, ligne de
-- charge 6xx) · T06 l'OF DE CHANTIER (mouvements + écriture JE-OF portent
-- la section de l'OF) · T07 le cas ordinaire muet.
-- ═══════════════════════════════════════════════════════════════════════════
SELECT set_config('audit.file', '768', false);

\ir ci/audit_helpers.sql
DELETE FROM _audit_results WHERE file = '768';

-- ─────────────────────────────────────────────────────────────
-- Décor : société + dépôt + articles + nomenclature + projet.
-- (Le harnais analytique de la 304, repris à l'identique.)
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS _sec768(uuid, text);
CREATE OR REPLACE FUNCTION _sec768(p_t uuid, p_code text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; pl uuid;
BEGIN
  SELECT id INTO pl FROM analytic_plans WHERE tenant_id = p_t LIMIT 1;
  IF pl IS NULL THEN
    INSERT INTO analytic_plans (tenant_id, code, name) VALUES (p_t, 'AX-' || p_code, 'Plan ' || p_code)
      RETURNING id INTO pl;
  END IF;
  INSERT INTO analytic_sections (tenant_id, plan_id, code, name, axis, level)
    VALUES (p_t, pl, p_code, 'Section ' || p_code, 1, 1)
    ON CONFLICT DO NOTHING;
  SELECT id INTO v FROM analytic_sections WHERE tenant_id = p_t AND code = p_code LIMIT 1;
  RETURN v;
END $$;

DROP FUNCTION IF EXISTS _mk768(text);
CREATE OR REPLACE FUNCTION _mk768(p_nom text,
  OUT t uuid, OUT wh uuid, OUT p uuid, OUT comp uuid, OUT proj uuid)
LANGUAGE plpgsql AS $$
DECLARE b uuid;
BEGIN
  t := _mk_tenant('L18A' || p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name)
    VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'PF ' || p_nom, 'PF768-' || p_nom, 'stock', 30) RETURNING id INTO p;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'MP ' || p_nom, 'MP768-' || p_nom, 'stock', 5) RETURNING id INTO comp;
  INSERT INTO boms (tenant_id, code, name, product_id)
    VALUES (t, 'BOM-' || p_nom, 'Nomenclature ' || p_nom, p) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity)
    VALUES (t, b, comp, 2);
  -- Stock initial du composant (sans section : le cas ordinaire).
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id,
    movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, comp, wh, 'in', 'in', 100, 5, 'INIT', CURRENT_DATE, CURRENT_DATE);
  INSERT INTO projects (tenant_id, name) VALUES (t, 'Chantier ' || p_nom) RETURNING id INTO proj;
END $$;

-- ════════════════════════════════════════════════════════════
-- T01 — LE PORTEUR : deux colonnes, deux clés composites ISO-02
--      (mouvement et OF portent une section analytique).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE n_col int; n_fk int;
BEGIN
  SELECT count(*) INTO n_col FROM information_schema.columns
   WHERE table_schema = 'public'
     AND ((table_name = 'stock_movements' AND column_name = 'analytic_section_id')
       OR (table_name = 'manufacturing_orders' AND column_name = 'analytic_section_id'));
  SELECT count(*) INTO n_fk FROM pg_constraint
   WHERE contype = 'f'
     AND (conname = 'stock_movements_analytic_section_fk'
       OR conname = 'manufacturing_orders_analytic_section_fk');
  PERFORM _rec('T01', 'le porteur analytique existe : 2 colonnes + 2 clés composites ISO-02',
    n_col = 2 AND n_fk = 2,
    format('colonnes=%s clés=%s (2 / 2 attendus)', n_col, n_fk));
END $$;

-- ════════════════════════════════════════════════════════════
-- T02 — CLOISONNEMENT : une section d'une AUTRE société est
--      refusée par la clé composite nommée (23503).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; sec_b uuid; msg text := ''; tb uuid;
BEGIN
  x := _mk768('T02');
  tb := _mk_tenant('L18AT02B');
  sec_b := _sec768(tb, 'T02B');
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id,
      movement_type, type, quantity, unit_cost, reference, reference_type,
      reference_id, movement_date, date, analytic_section_id)
    VALUES (x.t, x.comp, x.wh, 'out', 'out', 1, 5, 'S-768', 'project',
            x.proj, CURRENT_DATE, CURRENT_DATE, sec_b);
  EXCEPTION WHEN foreign_key_violation THEN
    msg := SQLERRM;
  END;
  PERFORM _rec('T02', 'une section d''une AUTRE société est REFUSÉE — clé composite nommée (23503)',
    msg LIKE '%stock_movements_analytic_section_fk%',
    CASE WHEN msg <> '' THEN 'refus : ' || left(msg, 96)
         ELSE 'mouvement accepté avec une section étrangère' END);
END $$;

-- ════════════════════════════════════════════════════════════
-- T03 — CLOISONNEMENT de l'OF : même refus, clé nommée.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; sec_b uuid; msg text := ''; tb uuid; b uuid;
BEGIN
  x := _mk768('T03');
  tb := _mk_tenant('L18AT03B');
  sec_b := _sec768(tb, 'T03B');
  SELECT id INTO b FROM boms WHERE tenant_id = x.t AND code = 'BOM-T03';
  BEGIN
    INSERT INTO manufacturing_orders (tenant_id, number, product_id, bom_id,
      quantity, warehouse_id, status, analytic_section_id)
    VALUES (x.t, 'OF-768-T03', x.p, b, 5, x.wh, 'planned', sec_b);
  EXCEPTION WHEN foreign_key_violation THEN
    msg := SQLERRM;
  END;
  PERFORM _rec('T03', 'une section étrangère sur l''OF est REFUSÉE — clé composite nommée',
    msg LIKE '%manufacturing_orders_analytic_section_fk%',
    CASE WHEN msg <> '' THEN 'refus : ' || left(msg, 96)
         ELSE 'OF accepté avec une section étrangère' END);
END $$;

-- ════════════════════════════════════════════════════════════
-- T04a — LE PORTEUR EST NETTOYÉ (ON DELETE SET NULL) : sur un
--      mouvement SANS écriture (production — le déclencheur STK
--      les saute), la suppression de la section vide le porteur.
-- T04b — et l'ÉCRITURE POSTÉE PROTÈGE sa section : la même
--      suppression sur une section portée par une écriture STK
--      postée est REFUSÉE par l'inaltérabilité (W2/250) — le
--      conflit 250 ↔ clé analytique est nommé, pas tu.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; sec uuid; mv uuid; sec_after uuid; msg text := '';
BEGIN
  x := _mk768('T04');
  sec := _sec768(x.t, 'T04');
  -- a) mouvement sans écriture (reference_type = 'production' → le STK saute)
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id,
    movement_type, type, quantity, unit_cost, reference, reference_type,
    reference_id, movement_date, date, analytic_section_id)
  VALUES (x.t, x.comp, x.wh, 'in', 'in', 1, 5, 'OF-T04', 'production',
          NULL, CURRENT_DATE, CURRENT_DATE, sec)
  RETURNING id INTO mv;
  DELETE FROM analytic_sections WHERE id = sec AND tenant_id = x.t;
  SELECT analytic_section_id INTO sec_after FROM stock_movements WHERE id = mv;
  PERFORM _rec('T04a', 'supprimer la section NETTOIE le porteur (ON DELETE SET NULL)',
    sec_after IS NULL,
    format('section après suppression=%s (NULL attendu)', COALESCE(sec_after::text, 'NULL')));

  -- b) même section… non : nouvelle section, mouvement AVEC écriture postée
  sec := _sec768(x.t, 'T04b');
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id,
    movement_type, type, quantity, unit_cost, reference, reference_type,
    reference_id, movement_date, date, analytic_section_id)
  VALUES (x.t, x.comp, x.wh, 'out', 'out', 1, 5, 'S-768', 'project',
          x.proj, CURRENT_DATE, CURRENT_DATE, sec)
  RETURNING id INTO mv;
  BEGIN
    DELETE FROM analytic_sections WHERE id = sec AND tenant_id = x.t;
  EXCEPTION WHEN OTHERS THEN
    msg := SQLERRM;
  END;
  SELECT analytic_section_id INTO sec_after FROM stock_movements WHERE id = mv;
  PERFORM _rec('T04b', 'l''écriture STK postée PROTÈGE sa section : la suppression est REFUSÉE (inaltérabilité W2)',
    msg LIKE '%immuable%' AND sec_after = sec,
    format('refus=%s | porteur intact=%s', left(msg, 60), sec_after = sec));
END $$;

-- ════════════════════════════════════════════════════════════
-- T05 — LA CIRCULATION : la section d'une SORTIE de chantier
--      monte jusqu'à la ligne de charge (6xx) de l'écriture STK.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; sec uuid; mv uuid; entry_id uuid; sec_l uuid; debit_l numeric;
BEGIN
  x := _mk768('T05');
  sec := _sec768(x.t, 'T05');
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id,
    movement_type, type, quantity, unit_cost, reference, reference_type,
    reference_id, movement_date, date, analytic_section_id)
  VALUES (x.t, x.comp, x.wh, 'out', 'out', 4, 5, 'CHANTIER-768', 'project',
          x.proj, CURRENT_DATE, CURRENT_DATE, sec)
  RETURNING id INTO mv;
  SELECT id INTO entry_id FROM journal_entries
   WHERE tenant_id = x.t AND piece_number = 'STK-' || mv::text LIMIT 1;
  SELECT jl.analytic_section_id, jl.debit INTO sec_l, debit_l
    FROM journal_lines jl
   WHERE jl.tenant_id = x.t AND jl.journal_id = entry_id
     AND jl.account_code LIKE '6%'
   LIMIT 1;
  PERFORM _rec('T05', 'la section du mouvement de chantier circule jusqu''à la ligne de charge (6xx) de l''écriture STK',
    entry_id IS NOT NULL AND sec_l = sec AND debit_l = 20,
    format('écriture=%s section portée=%s débit=%s (20 attendu)',
           COALESCE(entry_id::text, '(aucune)'), COALESCE(sec_l::text, '(aucune)'), debit_l));
END $$;

-- ════════════════════════════════════════════════════════════
-- T06 — L'OF DE CHANTIER : la clôture (le VRAI chemin, qui écrit
--      reference = numéro d'OF) porte la section sur les sorties
--      de composants ET sur la ligne 601000 de l'écriture JE-OF ;
--      et le coût matière atteint le projet (actual_cost = 50).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; sec uuid; mo_id uuid; bom_id uuid;
        n_mv int; n_sec int; entry_id uuid; sec_l uuid; cout numeric;
BEGIN
  x := _mk768('T06');
  sec := _sec768(x.t, 'T06');
  SELECT id INTO bom_id FROM boms WHERE tenant_id = x.t AND code = 'BOM-T06';
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, bom_id,
    quantity, warehouse_id, status, project_id, analytic_section_id)
  VALUES (x.t, 'OF-768-T06', x.p, bom_id, 5, x.wh, 'planned', x.proj, sec)
  RETURNING id INTO mo_id;
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = mo_id;
  UPDATE manufacturing_orders SET status = 'completed'   WHERE id = mo_id;

  SELECT count(*), count(*) FILTER (WHERE sm.analytic_section_id = sec)
    INTO n_mv, n_sec
    FROM stock_movements sm
   WHERE sm.tenant_id = x.t
     AND sm.reference_type = 'production'
     AND sm.reference = 'OF-768-T06'
     AND sm.movement_type = 'out';
  SELECT id INTO entry_id FROM journal_entries
   WHERE tenant_id = x.t AND reference = 'JE-OF-OF-768-T06' LIMIT 1;
  SELECT analytic_section_id INTO sec_l FROM journal_lines
   WHERE tenant_id = x.t AND journal_id = entry_id AND account_code = '601000'
   LIMIT 1;
  SELECT actual_cost INTO cout FROM projects WHERE id = x.proj;

  PERFORM _rec('T06', 'l''OF DE CHANTIER porte sa section : sorties de composants ET ligne 601000 — et le coût matière atteint le projet (50)',
    n_mv >= 1 AND n_sec = n_mv AND entry_id IS NOT NULL AND sec_l = sec AND cout = 50,
    format('sorties=%s portant la section=%s | JE-OF=%s section 601000=%s | actual_cost=%s',
           n_mv, n_sec, COALESCE(entry_id::text, '(aucune)'),
           COALESCE(sec_l::text, '(aucune)'), cout));
END $$;

-- ════════════════════════════════════════════════════════════
-- T07 — LE CAS ORDINAIRE EST MUET : un OF sans section produit
--      mouvements et écriture SANS section — personne n'en invente.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; mo_id uuid; bom_id uuid;
        n_mv int; n_null int; entry_id uuid; sec_l uuid;
BEGIN
  x := _mk768('T07');
  SELECT id INTO bom_id FROM boms WHERE tenant_id = x.t AND code = 'BOM-T07';
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, bom_id,
    quantity, warehouse_id, status, project_id)
  VALUES (x.t, 'OF-768-T07', x.p, bom_id, 5, x.wh, 'planned', x.proj)
  RETURNING id INTO mo_id;
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = mo_id;
  UPDATE manufacturing_orders SET status = 'completed'   WHERE id = mo_id;

  SELECT count(*), count(*) FILTER (WHERE sm.analytic_section_id IS NULL)
    INTO n_mv, n_null
    FROM stock_movements sm
   WHERE sm.tenant_id = x.t
     AND sm.reference_type = 'production'
     AND sm.reference = 'OF-768-T07'
     AND sm.movement_type = 'out';
  SELECT id INTO entry_id FROM journal_entries
   WHERE tenant_id = x.t AND reference = 'JE-OF-OF-768-T07' LIMIT 1;
  SELECT analytic_section_id INTO sec_l FROM journal_lines
   WHERE tenant_id = x.t AND journal_id = entry_id AND account_code = '601000'
   LIMIT 1;

  PERFORM _rec('T07', 'un OF SANS section produit mouvements et écriture SANS section (muet)',
    n_mv >= 1 AND n_null = n_mv AND entry_id IS NOT NULL AND sec_l IS NULL,
    format('sorties=%s sans section=%s | JE-OF=%s section 601000=%s (NULL attendu)',
           n_mv, n_null, COALESCE(entry_id::text, '(aucune)'),
           COALESCE(sec_l::text, '(aucune)')));
END $$;

DROP FUNCTION _sec768(uuid, text);
DROP FUNCTION _mk768(text);

SELECT _audit_assert('768');