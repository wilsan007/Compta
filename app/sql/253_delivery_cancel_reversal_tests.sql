-- ============================================================
-- 253_delivery_cancel_reversal_tests.sql — le pendant S-12 côté vente
--
-- La 230 avait fermé la moitié du chemin : expédier sort le stock une fois,
-- réexpédier un BL annulé est refusé explicitement — mais **annuler un BL
-- expédié ne remettait rien** (ni stock, ni couche, ni écriture). Le commentaire
-- de la 230 le disait lui-même : « Hors périmètre, inscrit au registre ».
-- C'est le pendant exact de ce que la 251 fait pour la réception.
--
-- Mesuré AVANT la 253 (base neuve, 252 migrations) : T02, T03 et T05 rouges
-- (stock jamais rendu, aucune contrepassation possible ni attendue), T01 et T04
-- verts — ce sont les non-régressions de la 230 (une seule sortie à
-- l'expédition, réexpédition refusée).
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '253', false);
DELETE FROM _audit_results WHERE file = '253';

-- Société, dépôt, client, article à 5 avec 1 000 en stock (couche et CUMP posés
-- par le mouvement d'entrée), et un bon de livraison.
CREATE OR REPLACE FUNCTION _mk_vente253(p_nom text, OUT t uuid, OUT wh uuid, OUT c uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  PERFORM _ledger_fixture(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 5) RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (t, p, wh, 'in', 'in', 1000, 5, 'APPRO-' || p_nom, CURRENT_DATE, CURRENT_DATE);
END $$;

CREATE OR REPLACE FUNCTION _mk_bl253(p_t uuid, p_c uuid, p_p uuid, p_num text, p_qte numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE bl uuid;
BEGIN
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (p_t, p_num, p_c, CURRENT_DATE, 'pending') RETURNING id INTO bl;
  INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity)
    VALUES (p_t, bl, p_p, 'Article livré', p_qte);
  RETURN bl;
END $$;

-- L'état du stock : article, dépôt, couches (quantité et valeur).
CREATE OR REPLACE FUNCTION _stock253(p_t uuid, p_p uuid, p_wh uuid,
  OUT article numeric, OUT depot numeric, OUT couches numeric, OUT valeur numeric)
LANGUAGE plpgsql AS $$
BEGIN
  SELECT stock_quantity INTO article FROM products WHERE id = p_p AND tenant_id = p_t;
  SELECT quantity INTO depot FROM stock_quantities
    WHERE tenant_id = p_t AND product_id = p_p AND warehouse_id = p_wh;
  SELECT COALESCE(sum(remaining_qty), 0), COALESCE(sum(remaining_qty * unit_cost), 0)
    INTO couches, valeur
    FROM stock_valuation_layers WHERE tenant_id = p_t AND product_id = p_p;
END $$;

-- L'écriture de stock d'une référence : nombre, débit et crédit du compte 31x.
CREATE OR REPLACE FUNCTION _ecr253(p_t uuid, p_ref text,
  OUT nb int, OUT d31 numeric, OUT c31 numeric, OUT statut text)
LANGUAGE plpgsql AS $$
BEGIN
  SELECT count(DISTINCT je.id), COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0), max(je.status)
    INTO nb, d31, c31, statut
  FROM journal_entries je
  LEFT JOIN journal_lines jl ON jl.journal_id = je.id AND jl.account_code LIKE '31%'
  WHERE je.tenant_id = p_t AND je.reference = p_ref;
END $$;


-- ═════════════════════════════════════════════════════════════
-- T01 — non-régression 230 : expédier sort le stock une seule fois
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; bl uuid; s record; n int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_vente253('DV253T01')) x;
  bl := _mk_bl253(v.t, v.c, v.p, 'T01', 10);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  PERFORM set_config('role', 'postgres', true);
  SELECT * INTO s FROM (SELECT * FROM _stock253(v.t, v.p, v.wh)) x;
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;
  PERFORM _rec('T01', 'expédier un BL de 10 : une sortie, article et dépôt à 990 (230 non régressée)',
    n = 1 AND s.article = 990 AND s.depot = 990,
    format('sorties=%s (1 attendue), article=%s dépôt=%s (990/990 attendus)', n, s.article, s.depot));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — annuler un BL EXPÉDIÉ remet le stock, la couche et l'écriture
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; bl uuid; s record; eo record; ea record; n int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_vente253('DV253T02')) x;
  bl := _mk_bl253(v.t, v.c, v.p, 'T02', 10);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
  PERFORM set_config('role', 'postgres', true);

  SELECT * INTO s FROM (SELECT * FROM _stock253(v.t, v.p, v.wh)) x;
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = v.t AND reference_type = 'delivery_note_cancel' AND reference_id = bl;
  SELECT * INTO eo FROM (SELECT * FROM _ecr253(v.t, 'BL-T02')) x;
  SELECT * INTO ea FROM (SELECT * FROM _ecr253(v.t, 'BL-ANN-T02')) x;

  PERFORM _rec('T02', 'annuler un BL expédié rend le stock (1 000) et contrepasse sa sortie',
    s.article = 1000 AND s.depot = 1000 AND s.couches = 1000 AND n = 1
      AND eo.c31 = 50 AND eo.statut = 'posted'
      AND ea.d31 = 50 AND ea.c31 = 0 AND ea.statut = 'posted',
    format('article=%s dépôt=%s couches=%s (1000/1000/1000 attendus), contrepassations=%s (1 attendue) | sortie C31=%s, contrepartie D31=%s',
           s.article, s.depot, s.couches, n, eo.c31, ea.d31));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — annuler deux fois ne remet pas le stock deux fois
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; bl uuid; s record; n int; s2 text; s3 text; err text := '—';
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_vente253('DV253T03')) x;
  bl := _mk_bl253(v.t, v.c, v.p, 'T03', 10);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;

  -- (a) une seconde annulation sur un BL déjà annulé
  BEGIN
    UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
    s2 := 'aucune erreur';
  EXCEPTION WHEN others THEN s2 := SQLSTATE;
  END;

  -- (b) état hostile fabriqué : le statut remis à « expédié » en neutralisant
  --     les deux déclencheurs (comme une base d'avant la 253), puis une seconde
  --     annulation — la garde explicite doit refuser.
  PERFORM set_config('role', 'postgres', true);
  ALTER TABLE delivery_notes DISABLE TRIGGER create_stock_out_on_delivery;
  BEGIN
    ALTER TABLE delivery_notes DISABLE TRIGGER trg_delivery_cancel_reverse;
  EXCEPTION WHEN undefined_object THEN NULL;   -- la garde naît avec la 253
  END;
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  BEGIN
    ALTER TABLE delivery_notes ENABLE TRIGGER trg_delivery_cancel_reverse;
  EXCEPTION WHEN undefined_object THEN NULL;
  END;
  ALTER TABLE delivery_notes ENABLE TRIGGER create_stock_out_on_delivery;
  BEGIN
    UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
  EXCEPTION WHEN others THEN s3 := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT * INTO s FROM (SELECT * FROM _stock253(v.t, v.p, v.wh)) x;
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = v.t AND reference_type = 'delivery_note_cancel' AND reference_id = bl;
  PERFORM _rec('T03', 'annuler deux fois ne remet pas le stock deux fois',
    s2 = 'aucune erreur' AND s3 = '23505' AND s.article = 1000 AND s.depot = 1000 AND n = 1,
    format('2ᵉ annulation=%s, contrepassation forcée SQLSTATE=%s (23505 attendu), article=%s dépôt=%s, contrepassations=%s | %s',
           s2, COALESCE(s3, 'aucune erreur'), s.article, s.depot, n, left(err, 60)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — non-régression 230 : un BL annulé ne se réexpédie pas
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; bl uuid; s record; n int; refuse boolean := false; err text := '—';
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_vente253('DV253T04')) x;
  bl := _mk_bl253(v.t, v.c, v.p, 'T04', 10);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
  BEGIN
    UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  EXCEPTION WHEN others THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT * INTO s FROM (SELECT * FROM _stock253(v.t, v.p, v.wh)) x;
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;
  PERFORM _rec('T04', 'réexpédier un BL annulé reste refusé, et ne ressort pas le stock',
    refuse AND n = 1 AND s.article = 1000 AND err LIKE '%déjà expédié%',
    format('refus=%s sorties d''origine=%s (1 attendue) article=%s (1000 attendu) | %s',
           refuse, n, s.article, left(err, 70)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — annuler un BL LIVRÉ remet aussi le stock
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; bl uuid; s record; n int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_vente253('DV253T05')) x;
  bl := _mk_bl253(v.t, v.c, v.p, 'T05', 10);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  UPDATE delivery_notes SET status = 'delivered' WHERE id = bl;
  UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
  PERFORM set_config('role', 'postgres', true);

  SELECT * INTO s FROM (SELECT * FROM _stock253(v.t, v.p, v.wh)) x;
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = v.t AND reference_type = 'delivery_note_cancel' AND reference_id = bl;
  PERFORM _rec('T05', 'annuler un BL livré rend aussi le stock',
    s.article = 1000 AND s.depot = 1000 AND s.couches = 1000 AND n = 1,
    format('article=%s dépôt=%s couches=%s (1000/1000/1000 attendus), contrepassations=%s (1 attendue)',
           s.article, s.depot, s.couches, n));
END $$;

DROP FUNCTION _ecr253(uuid, text);
DROP FUNCTION _stock253(uuid, uuid, uuid);
DROP FUNCTION _mk_bl253(uuid, uuid, uuid, text, numeric);
DROP FUNCTION _mk_vente253(text);

SELECT _audit_assert('253');

