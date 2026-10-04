-- ============================================================
-- 317_invoice_direct_stock_and_line_accounts_tests.sql — lot B (écrans Ventes)
--
-- Recette /qa du 29/09/2026. Cinq défauts et deux décisions (D-QA-1, D-QA-2) :
--
--   B2 (ven-008)  Une facture directe sans choix d'article créditait tout le HT
--                 en 707000 : mesuré 707000 C 280,00 pour « 3 × livre +
--                 1 × service » (une prestation dont la fiche porte 706000).
--   D-QA-1        Une facture directe d'un article stocké, sans BL, ne sortait
--                 pas le stock (mesuré : stock 50 → 50).
--   B4 (ven-012)  L'avoir d'un article rendu était ventilé au prorata de la
--                 facture (706 55,56 / 707 44,44) ; son écriture ne portait pas
--                 `invoice_ref`.
--   B6 (ven-006)  Une facture née d'un BL n'avait pas de nom de client ; une
--                 facture née d'un devis du 10/09 était datée du 29/09.
--   B7 (ven-007) / D-QA-2 : une facture datée avant la dernière validée était
--                 numérotée sans avertissement.
--
-- Mesuré sur la base de recette à la 316, AVANT la 317 (11 scénarios, 3 verts /
-- 8 rouges ; les trois verts sont les non-régressions voulues) :
--   T01 ❌ ligne libre à 706000 : tout part en 707000 (706000=0, 707000=250)
--   T02 ❌ prestation sans compte sur la fiche : tout part en 707000
--   T03 ✅ article stocké sans compte : 707000 (non-régression)
--   T04 ✅ le compte de l'article prime sur celui de la ligne (non-régression)
--   T05a ❌ facture directe d'un article stocké : 0 sortie, stock 50 → 50
--   T05b ❌ (même cause) la garde anti-double n'existait pas
--   T06a ✅ avoir d'un article : 707000 — vert avant, car la ligne portait
--        l'article ; le rouge ven-012 venait de la ligne SANS article, saisie à
--        la main (couvert côté écran : lignes de la facture reprises)
--   T06b ❌ l'écriture de l'avoir ne portait pas invoice_ref
--   T07a ❌ facture sans nom de client (customer_name vide)
--   T07b ❌ devis du 10/09 facturé au 30/09 (date du jour)
--   T08  ❌ facture antérieure validée sans avertissement (statut validated)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '317', false);
DELETE FROM _audit_results WHERE file = '317';

-- Société de recette : dépôt, client, un article stocké (50 en stock) et une
-- prestation — ni l'un ni l'autre ne porte de compte de vente sur sa fiche.
CREATE OR REPLACE FUNCTION _mk_vente317(p_nom text,
  OUT t uuid, OUT c uuid, OUT wh uuid, OUT p_stock uuid, OUT p_service uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 5) RETURNING id INTO p_stock;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Prestation ' || p_nom, 'S-' || p_nom, 'service', 0) RETURNING id INTO p_service;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, p_stock, wh, 'in', 'in', 50, 5, 'APPRO', CURRENT_DATE, CURRENT_DATE);
END $$;

-- Lignes : [{"produit": uuid|null, "description": text, "qte": n, "pu": n,
--            "tva": n, "compte": text|null, "dnl": uuid|null}]
CREATE OR REPLACE FUNCTION _mk_fac317(p_t uuid, p_c uuid, p_date date, p_lignes jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid; l jsonb; i int := 0;
BEGIN
  INSERT INTO invoices (tenant_id, customer_id, date, due_date, status)
  VALUES (p_t, p_c, p_date, p_date + 30, 'draft') RETURNING id INTO inv;
  FOR l IN SELECT * FROM jsonb_array_elements(p_lignes) LOOP
    INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description, quantity, unit_price,
                               vat_rate, account_code, line_order, delivery_note_line_id)
    VALUES (p_t, inv, NULLIF(l->>'produit', '')::uuid, l->>'description', (l->>'qte')::numeric,
            (l->>'pu')::numeric, COALESCE((l->>'tva')::numeric, 0), NULLIF(l->>'compte', ''), i,
            NULLIF(l->>'dnl', '')::uuid);
    i := i + 1;
  END LOOP;
  RETURN inv;
END $$;

-- Somme au crédit d'un compte dans l'écriture de la pièce
CREATE OR REPLACE FUNCTION _credit317(p_entry uuid, p_compte text)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT COALESCE(sum(jl.credit), 0) FROM journal_lines jl
  WHERE jl.journal_id = p_entry AND jl.account_code = p_compte
$$;


-- T01/T02/T03/T04 (B2, ven-008) : l'ordre des comptes de vente
DO $$
DECLARE v record; i1 uuid; i2 uuid; i3 uuid; i4 uuid; e uuid; pa uuid;
BEGIN
  v := _mk_vente317('T01');

  -- T01 : ligne libre, aucun article, compte de vente choisi sur la ligne
  i1 := _mk_fac317(v.t, v.c, '2026-03-01',
    jsonb_build_array(jsonb_build_object('description', 'Honoraires', 'qte', 1, 'pu', 250, 'tva', 0, 'compte', '706000')));
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = i1;
  SELECT transferred_entry_id INTO e FROM invoices WHERE id = i1;
  PERFORM _rec('T01', 'ligne libre à 706000 : la prestation est créditée en 706000, pas en 707000',
    _credit317(e, '706000') = 250 AND _credit317(e, '707000') = 0,
    format('706000=%s (250 attendu) 707000=%s (0 attendu)', _credit317(e, '706000'), _credit317(e, '707000')));

  -- T02 : article de type service, sans compte sur sa fiche → 706000 par défaut
  i2 := _mk_fac317(v.t, v.c, '2026-03-02',
    jsonb_build_array(jsonb_build_object('produit', v.p_service, 'description', 'Prestation', 'qte', 1, 'pu', 200, 'tva', 0)));
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = i2;
  SELECT transferred_entry_id INTO e FROM invoices WHERE id = i2;
  PERFORM _rec('T02', 'article de type service sans compte : crédité en 706000',
    _credit317(e, '706000') = 200 AND _credit317(e, '707000') = 0,
    format('706000=%s (200 attendu) 707000=%s (0 attendu)', _credit317(e, '706000'), _credit317(e, '707000')));

  -- T03 : article stocké sans compte → 707000 (et sortie de stock, T05)
  i3 := _mk_fac317(v.t, v.c, '2026-03-03',
    jsonb_build_array(jsonb_build_object('produit', v.p_stock, 'description', 'Livre', 'qte', 3, 'pu', 10, 'tva', 0)));
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = i3;
  SELECT transferred_entry_id INTO e FROM invoices WHERE id = i3;
  PERFORM _rec('T03', 'article stocké sans compte : crédité en 707000',
    _credit317(e, '707000') = 30 AND _credit317(e, '706000') = 0,
    format('707000=%s (30 attendu) 706000=%s (0 attendu)', _credit317(e, '707000'), _credit317(e, '706000')));

  -- T04 : le compte de l'article prime sur le compte de la ligne (non-régression)
  UPDATE products SET sale_account_code = '701000' WHERE id = v.p_stock;
  i4 := _mk_fac317(v.t, v.c, '2026-03-04',
    jsonb_build_array(jsonb_build_object('produit', v.p_stock, 'description', 'Article au compte', 'qte', 1, 'pu', 90, 'tva', 0, 'compte', '706000')));
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = i4;
  SELECT transferred_entry_id INTO e FROM invoices WHERE id = i4;
  PERFORM _rec('T04', 'le compte de l''article prime sur le compte de la ligne',
    _credit317(e, '701000') = 90 AND _credit317(e, '706000') = 0,
    format('701000=%s (90 attendu) 706000=%s (0 attendu)', _credit317(e, '701000'), _credit317(e, '706000')));
END $$;

-- T05 : D-QA-1 — la facture directe d'un article stocké sort le stock, une
--       fois ; la garde anti-double épargne une ligne née d'un BL.
DO $$
DECLARE v record; inv uuid; inv2 uuid; dn uuid; dnl uuid; n int; q numeric; stock numeric; n2 int;
BEGIN
  v := _mk_vente317('T05');

  inv := _mk_fac317(v.t, v.c, '2026-03-05',
    jsonb_build_array(jsonb_build_object('produit', v.p_stock, 'description', 'Livre', 'qte', 3, 'pu', 10, 'tva', 0)));
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  SELECT count(*), COALESCE(sum(quantity), 0) INTO n, q
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'invoice' AND reference_id = inv;
  SELECT stock_quantity INTO stock FROM products WHERE id = v.p_stock;
  PERFORM _rec('T05a', 'facture directe d''un article stocké : 1 sortie de 3, stock 50 → 47',
    n = 1 AND q = 3 AND stock = 47,
    format('sorties=%s (1 attendue) quantité=%s (3 attendue) stock=%s (47 attendu)', n, q, stock));

  -- Une ligne née d'un BL : la sortie du bon existe déjà, la facture ne ressort rien
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
  VALUES (v.t, 'BL-DQA1-T05', v.c, '2026-03-06', 'pending') RETURNING id INTO dn;
  INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity)
  VALUES (v.t, dn, v.p_stock, 'Livre du bon', 2) RETURNING id INTO dnl;

  inv2 := _mk_fac317(v.t, v.c, '2026-03-06',
    jsonb_build_array(jsonb_build_object('produit', v.p_stock, 'description', 'Livre du bon', 'qte', 2, 'pu', 10, 'tva', 0, 'dnl', dnl)));
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv2;
  SELECT count(*) INTO n2 FROM stock_movements
  WHERE tenant_id = v.t AND reference_type = 'invoice' AND reference_id = inv2;
  SELECT stock_quantity INTO stock FROM products WHERE id = v.p_stock;
  PERFORM _rec('T05b', 'ligne née d''un BL : aucune double sortie (garde D-QA-1)',
    n2 = 0 AND stock = 47,
    format('sorties facture=%s (0 attendue) stock=%s (47 attendu, inchangé)', n2, stock));
END $$;

-- T06 (B4, ven-012) : l'avoir d'un article rendu suit le compte de l'article
--      (707000), pas le prorata de la facture ; son écriture est lettrable.
DO $$
DECLARE v record; inv uuid; cn uuid; e uuid; d707 numeric; d706 numeric; c411 numeric; ref text;
BEGIN
  v := _mk_vente317('T06');
  -- Facture : 200 en 707000 (article) + 250 en 706000 (prestation)
  inv := _mk_fac317(v.t, v.c, '2026-03-07', jsonb_build_array(
    jsonb_build_object('produit', v.p_stock, 'description', 'Livre', 'qte', 2, 'pu', 100, 'tva', 0),
    jsonb_build_object('produit', v.p_service, 'description', 'Prestation', 'qte', 1, 'pu', 250, 'tva', 0)));
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;

  -- Avoir de 1 × article rendu : la ligne porte l'article, aucune prestation
  INSERT INTO credit_notes (tenant_id, customer_id, invoice_id, date, subtotal, vat_total, total)
  VALUES (v.t, v.c, inv, '2026-04-01', 100, 0, 100) RETURNING id INTO cn;
  INSERT INTO credit_note_lines (tenant_id, credit_note_id, product_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
  VALUES (v.t, cn, v.p_stock, 'Retour 1 pièce', 1, 100, 0, 100, 0, 0);
  UPDATE credit_notes SET status = 'validated' WHERE id = cn;

  SELECT transferred_entry_id INTO e FROM credit_notes WHERE id = cn;
  d707 := COALESCE((SELECT sum(jl.debit) FROM journal_lines jl WHERE jl.journal_id = e AND jl.account_code = '707000'), 0);
  d706 := COALESCE((SELECT sum(jl.debit) FROM journal_lines jl WHERE jl.journal_id = e AND jl.account_code = '706000'), 0);
  c411 := COALESCE((SELECT sum(jl.credit) FROM journal_lines jl WHERE jl.journal_id = e AND jl.account_code = '411000'), 0);
  SELECT je.invoice_ref INTO ref FROM journal_entries je WHERE je.id = e;

  PERFORM _rec('T06a', 'avoir d''un article rendu : 707000 D 100, aucune ligne 706000',
    d707 = 100 AND d706 = 0 AND c411 = 100,
    format('707000=%s (100 attendu) 706000=%s (0 attendu) 411000=%s (100 attendu)', d707, d706, c411));
  PERFORM _rec('T06b', 'l''écriture de l''avoir porte la référence de la facture d''origine',
    ref = (SELECT number FROM invoices WHERE id = inv),
    format('invoice_ref=%s (attendu %s)', COALESCE(ref, 'vide'), (SELECT number FROM invoices WHERE id = inv)));
END $$;


-- T07 (B6, ven-006) : le nom du client suit la facture ; une facture née d'un
--      devis garde la date du devis (et non celle du jour).
DO $$
DECLARE v record; inv uuid; q uuid; inv2 uuid; nom text; d date; res jsonb;
BEGIN
  v := _mk_vente317('T07');

  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
  VALUES (v.t, v.c, NULL, CURRENT_DATE, CURRENT_DATE + 30, 'draft') RETURNING id INTO inv;
  SELECT customer_name INTO nom FROM invoices WHERE id = inv;
  PERFORM _rec('T07a', 'facture sans nom de client : le nom est recopié du client',
    nom = (SELECT name FROM customers WHERE id = v.c),
    format('customer_name=%s (attendu %s)', COALESCE(nom, 'vide'), (SELECT name FROM customers WHERE id = v.c)));

  -- Devis daté du 10/09 : la facture qui en naît porte cette date, pas celle du jour
  INSERT INTO quotes (tenant_id, customer_id, customer_name, date, expiry_date, status)
  VALUES (v.t, v.c, 'Client T07', '2026-09-10', '2026-10-10', 'accepted') RETURNING id INTO q;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, line_order)
  VALUES (v.t, q, 'Prestation', 1, 100, 0, 0);
  res := convert_quote_to_invoice(q);
  SELECT id, date INTO inv2, d FROM invoices WHERE id = (res->>'invoice_id')::uuid;
  PERFORM _rec('T07b', 'facture née d''un devis du 10/09 : datée du 10/09, pas du jour',
    d = DATE '2026-09-10',
    format('date=%s (2026-09-10 attendue)', d));
END $$;

-- T08 (B7, ven-007 / D-QA-2) : la validation refuse une facture datée avant la
--      dernière facture validée de la société.
DO $$
DECLARE v record; a uuid; b uuid; refuse boolean := false; msg text := '—';
BEGIN
  v := _mk_vente317('T08');
  a := _mk_fac317(v.t, v.c, '2026-09-29',
    jsonb_build_array(jsonb_build_object('description', 'Première', 'qte', 1, 'pu', 100, 'tva', 0)));
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = a;

  b := _mk_fac317(v.t, v.c, '2026-09-12',
    jsonb_build_array(jsonb_build_object('description', 'Antérieure', 'qte', 1, 'pu', 100, 'tva', 0)));
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = b;
  EXCEPTION WHEN others THEN
    refuse := true; msg := SQLERRM;
  END;

  PERFORM _rec('T08', 'valider une facture antérieure à la dernière validée est refusé, avec un message nommé',
    refuse AND msg LIKE '%chronologie%' AND (SELECT validation_status FROM invoices WHERE id = b) = 'draft',
    format('refus=%s statut=%s | message=%s', refuse, (SELECT validation_status FROM invoices WHERE id = b), left(msg, 90)));
END $$;

-- T09 (D-QA-1) : une sortie impossible refuse la validation, avec un message
--      qui nomme la facture et l'article (pas un code brut).
DO $$
DECLARE v record; p0 uuid; inv uuid; refuse boolean := false; msg text := '—'; st text;
BEGIN
  v := _mk_vente317('T09');
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (v.t, 'Article sans stock', 'A-ZERO-T09', 'stock', 5) RETURNING id INTO p0;

  inv := _mk_fac317(v.t, v.c, '2026-03-09',
    jsonb_build_array(jsonb_build_object('produit', p0, 'description', 'Article sans stock', 'qte', 1, 'pu', 10, 'tva', 0)));
  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  EXCEPTION WHEN others THEN
    refuse := true; msg := SQLERRM;
  END;
  SELECT validation_status INTO st FROM invoices WHERE id = inv;
  PERFORM _rec('T09', 'article sans stock : la validation est refusée avec un message nommé',
    refuse AND st = 'draft' AND msg LIKE '%sortie de stock impossible%' AND msg LIKE '%Article sans stock%',
    format('refus=%s statut=%s | message=%s', refuse, st, left(msg, 110)));
END $$;

DROP FUNCTION _credit317(uuid, text);
DROP FUNCTION _mk_fac317(uuid, uuid, date, jsonb);
DROP FUNCTION _mk_vente317(text);
SELECT _audit_assert('317');

