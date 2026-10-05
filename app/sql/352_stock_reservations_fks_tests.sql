-- ============================================================
-- 352_stock_reservations_fks_tests.sql — tâche 2.16, défaut révélé par la voie C
--
-- `stock_reservations` ne portait AUCUNE clé étrangère (mesuré le 04/10 sur
-- base neuve, 328 migrations : la clé primaire et deux CHECK). Une réservation
-- pouvait désigner un article ou un dépôt inexistant, ou ceux d'une autre
-- société ; supprimer l'article, le dépôt ou la société la laissait en place.
--
--   T01  une réservation sur un article INEXISTANT est refusée
--   T02  une réservation sur l'article d'une AUTRE société est refusée
--   T03  une réservation sur un dépôt INEXISTANT est refusée
--   T04  une réservation sur le dépôt d'une AUTRE société est refusée
--   T05  la réservation saine passe — avec son dépôt, et sans dépôt (NULL)
--   T06  un article ou un dépôt qui porte une réservation ne se supprime pas
--        (la réservation ne devient pas orpheline, et n'est pas effacée)
--   T07  supprimer une société emporte ses réservations (aucune ne reste)
--   T08  reprise — article introuvable : la réservation est retirée, sa ligne
--        entière et le motif sont au journal d'audit de la société
--   T09  reprise — dépôt introuvable : la réservation reste, détachée du dépôt ;
--        active, elle est annulée ; consommée, elle garde son statut ; tracé
--   T10  reprise — la réservation saine n'est pas touchée, celle d'une société
--        disparue part avec elle, et un second passage ne trouve plus rien
--   T11  reprise — le lien de chaîne ACTIF d'une réservation retirée ou annulée
--        est FERMÉ (rompu, motif), pas effacé — et la garde de suppression (453)
--        ne bloque donc pas la reprise
--
-- T08 → T11 retirent les clés DANS UNE SOUS-TRANSACTION ANNULÉE : c'est le seul
-- moyen de fabriquer des orphelins une fois les clés posées. Les mesures sont
-- prises avant l'annulation, les verdicts écrits après.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '352', false);
DELETE FROM _audit_results WHERE file = '352';

-- ── T01 → T06 : ce que la base refuse, ce qu'elle accepte ────
DO $$
DECLARE
  ta uuid := _mk_tenant('P2R16A', false);
  tb uuid := _mk_tenant('P2R16B', false);
  pa uuid; pb uuid; wa uuid; wb uuid;
  v_code text; v_msg text; n int; n2 int;
BEGIN
  INSERT INTO products (tenant_id, name, sku, type) VALUES (ta, 'Article A', 'R16-A', 'stock') RETURNING id INTO pa;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (tb, 'Article B', 'R16-B', 'stock') RETURNING id INTO pb;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (ta, 'W-R16A', 'Dépôt A') RETURNING id INTO wa;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (tb, 'W-R16B', 'Dépôt B') RETURNING id INTO wb;

  -- T01
  v_code := NULL; v_msg := 'insertion acceptée';
  BEGIN
    INSERT INTO stock_reservations (tenant_id, product_id, quantity, reference_type)
    VALUES (ta, gen_random_uuid(), 1, 'manual');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; v_msg := SQLERRM;
  END;
  PERFORM _rec('T01', 'une réservation sur un article inexistant est refusée',
    v_code = '23503', format('sqlstate=%s — %s', COALESCE(v_code, '(aucun)'), left(v_msg, 140)));

  -- T02
  v_code := NULL; v_msg := 'insertion acceptée';
  BEGIN
    INSERT INTO stock_reservations (tenant_id, product_id, quantity, reference_type)
    VALUES (ta, pb, 1, 'manual');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; v_msg := SQLERRM;
  END;
  PERFORM _rec('T02', 'une réservation sur l''article d''une autre société est refusée',
    v_code = '23503', format('sqlstate=%s — %s', COALESCE(v_code, '(aucun)'), left(v_msg, 140)));

  -- T03
  v_code := NULL; v_msg := 'insertion acceptée';
  BEGIN
    INSERT INTO stock_reservations (tenant_id, product_id, warehouse_id, quantity, reference_type)
    VALUES (ta, pa, gen_random_uuid(), 1, 'manual');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; v_msg := SQLERRM;
  END;
  PERFORM _rec('T03', 'une réservation sur un dépôt inexistant est refusée',
    v_code = '23503', format('sqlstate=%s — %s', COALESCE(v_code, '(aucun)'), left(v_msg, 140)));

  -- T04
  v_code := NULL; v_msg := 'insertion acceptée';
  BEGIN
    INSERT INTO stock_reservations (tenant_id, product_id, warehouse_id, quantity, reference_type)
    VALUES (ta, pa, wb, 1, 'manual');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; v_msg := SQLERRM;
  END;
  PERFORM _rec('T04', 'une réservation sur le dépôt d''une autre société est refusée',
    v_code = '23503', format('sqlstate=%s — %s', COALESCE(v_code, '(aucun)'), left(v_msg, 140)));

  -- T05 : le chemin sain ne doit pas être fermé par la clé
  v_code := NULL; v_msg := '';
  BEGIN
    INSERT INTO stock_reservations (tenant_id, product_id, warehouse_id, quantity, reference_type)
    VALUES (ta, pa, wa, 2, 'manual');
    INSERT INTO stock_reservations (tenant_id, product_id, warehouse_id, quantity, reference_type)
    VALUES (ta, pa, NULL, 3, 'manual');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; v_msg := SQLERRM;
  END;
  SELECT count(*) INTO n FROM stock_reservations WHERE tenant_id = ta AND product_id = pa;
  PERFORM _rec('T05', 'la réservation saine passe, avec son dépôt et sans dépôt',
    v_code IS NULL AND n = 2, format('réservations=%s (attendu 2) %s', n, left(v_msg, 140)));

  -- T06 : supprimer l'article ou le dépôt réservé
  v_code := NULL; v_msg := 'article supprimé';
  BEGIN
    DELETE FROM products WHERE id = pa;
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; v_msg := SQLERRM;
  END;
  DECLARE v_code2 text; v_msg2 text := 'dépôt supprimé';
  BEGIN
    BEGIN
      DELETE FROM warehouses WHERE id = wa;
    EXCEPTION WHEN OTHERS THEN v_code2 := SQLSTATE; v_msg2 := SQLERRM;
    END;
    SELECT count(*) INTO n FROM stock_reservations WHERE tenant_id = ta;
    SELECT count(*) INTO n2 FROM stock_reservations sr
    WHERE sr.tenant_id = ta
      AND (NOT EXISTS (SELECT 1 FROM products p WHERE p.tenant_id = sr.tenant_id AND p.id = sr.product_id)
        OR (sr.warehouse_id IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM warehouses w WHERE w.tenant_id = sr.tenant_id AND w.id = sr.warehouse_id)));
    PERFORM _rec('T06', 'un article ou un dépôt réservé ne se supprime pas : ni orpheline, ni effacée',
      v_code = '23503' AND v_code2 = '23503' AND n = 2 AND n2 = 0,
      format('article : %s / dépôt : %s / réservations=%s (attendu 2) orphelines=%s — %s',
             COALESCE(v_code, 'supprimé'), COALESCE(v_code2, 'supprimé'), n, n2, left(v_msg, 100)));
  END;
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 → T06 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T07 : la société part, ses réservations aussi ────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2R16C', false);
  p uuid; n int; v_msg text := '';
BEGIN
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article C', 'R16-C', 'stock') RETURNING id INTO p;
  INSERT INTO stock_reservations (tenant_id, product_id, quantity, reference_type) VALUES (t, p, 1, 'manual');
  BEGIN
    DELETE FROM tenants WHERE id = t;
  EXCEPTION WHEN OTHERS THEN v_msg := 'suppression refusée : ' || SQLERRM;
  END;
  SELECT count(*) INTO n FROM stock_reservations WHERE tenant_id = t;
  PERFORM _rec('T07', 'supprimer une société emporte ses réservations',
    n = 0 AND v_msg = '' AND NOT EXISTS (SELECT 1 FROM tenants WHERE id = t),
    format('réservations restantes=%s (attendu 0) %s', n, left(v_msg, 160)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'T07 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T08 → T11 : la reprise des orphelins ─────────────────────
DO $$
DECLARE
  ta uuid := _mk_tenant('P2R16D', false);
  tb uuid := _mk_tenant('P2R16E', false);
  t_absent uuid := gen_random_uuid();
  pa uuid; pb uuid; wa uuid;
  r_inexistant uuid; r_voisin uuid; r_depot_actif uuid; r_depot_conso uuid; r_saine uuid; r_sans_societe uuid;
  v_err text;
  n_retirees int; n_audit_del int; v_meta jsonb;
  s_actif text; s_conso text; w_actif uuid; w_conso uuid; n_audit_upd int;
  n_saine int; n_sans_soc int; n_premier int; n_second int; n_violent int;
  so uuid; n_liens int; n_rompus int; n_actifs int;
BEGIN
  INSERT INTO products (tenant_id, name, sku, type) VALUES (ta, 'Article D', 'R16-D', 'stock') RETURNING id INTO pa;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (tb, 'Article E', 'R16-E', 'stock') RETURNING id INTO pb;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (ta, 'W-R16D', 'Dépôt D') RETURNING id INTO wa;

  BEGIN
    ALTER TABLE stock_reservations DROP CONSTRAINT IF EXISTS stock_reservations_product_id_fkey;
    ALTER TABLE stock_reservations DROP CONSTRAINT IF EXISTS stock_reservations_warehouse_id_fkey;
    ALTER TABLE stock_reservations DROP CONSTRAINT IF EXISTS stock_reservations_tenant_id_fkey;

    INSERT INTO stock_reservations (tenant_id, product_id, quantity, reference_type, status)
      VALUES (ta, gen_random_uuid(), 4, 'manual', 'active') RETURNING id INTO r_inexistant;
    INSERT INTO stock_reservations (tenant_id, product_id, quantity, reference_type, status)
      VALUES (ta, pb, 5, 'manual', 'active') RETURNING id INTO r_voisin;
    INSERT INTO stock_reservations (tenant_id, product_id, warehouse_id, quantity, reference_type, status)
      VALUES (ta, pa, gen_random_uuid(), 6, 'manual', 'active') RETURNING id INTO r_depot_actif;
    INSERT INTO stock_reservations (tenant_id, product_id, warehouse_id, quantity, reference_type, status)
      VALUES (ta, pa, gen_random_uuid(), 7, 'manual', 'consumed') RETURNING id INTO r_depot_conso;
    INSERT INTO stock_reservations (tenant_id, product_id, warehouse_id, quantity, reference_type, status)
      VALUES (ta, pa, wa, 8, 'manual', 'active') RETURNING id INTO r_saine;
    INSERT INTO stock_reservations (tenant_id, product_id, quantity, reference_type, status)
      VALUES (t_absent, gen_random_uuid(), 9, 'manual', 'active') RETURNING id INTO r_sans_societe;

    -- Le lien commande → réservation, comme le maillon de la 401 le pose.
    -- Une commande par lien : un seul lien ACTIF par (amont, effet) (402).
    INSERT INTO sales_orders (tenant_id, number, status) VALUES (ta, 'R16-SO1', 'draft') RETURNING id INTO so;
    INSERT INTO document_links (tenant_id, amont_type, amont_id, aval_type, aval_id, link_type, effet)
    VALUES (ta, 'sales_orders', so, 'stock_reservations', r_voisin, 'created_from', 'sale.order.reserved');
    INSERT INTO sales_orders (tenant_id, number, status) VALUES (ta, 'R16-SO2', 'draft') RETURNING id INTO so;
    INSERT INTO document_links (tenant_id, amont_type, amont_id, aval_type, aval_id, link_type, effet)
    VALUES (ta, 'sales_orders', so, 'stock_reservations', r_depot_actif, 'created_from', 'sale.order.reserved');

    n_premier := stock_reservations_reprendre_orphelins();

    -- T11
    SELECT count(*), count(*) FILTER (WHERE etat = 'rompu' AND motif LIKE '352 %' AND ferme_le IS NOT NULL),
           count(*) FILTER (WHERE etat = 'actif')
      INTO n_liens, n_rompus, n_actifs
    FROM document_links
    WHERE tenant_id = ta AND aval_type = 'stock_reservations' AND aval_id IN (r_voisin, r_depot_actif);

    -- T08
    SELECT count(*) INTO n_retirees FROM stock_reservations WHERE id IN (r_inexistant, r_voisin);
    SELECT count(*) INTO n_audit_del FROM audit_log
    WHERE tenant_id = ta AND entity_type = 'stock_reservations' AND action = 'delete'
      AND entity_id IN (r_inexistant, r_voisin);
    SELECT metadata INTO v_meta FROM audit_log
    WHERE tenant_id = ta AND entity_type = 'stock_reservations' AND entity_id = r_voisin;

    -- T09
    SELECT status, warehouse_id INTO s_actif, w_actif FROM stock_reservations WHERE id = r_depot_actif;
    SELECT status, warehouse_id INTO s_conso, w_conso FROM stock_reservations WHERE id = r_depot_conso;
    SELECT count(*) INTO n_audit_upd FROM audit_log
    WHERE tenant_id = ta AND entity_type = 'stock_reservations' AND action = 'update'
      AND entity_id IN (r_depot_actif, r_depot_conso)
      AND metadata->'ligne'->>'warehouse_id' IS NOT NULL;

    -- T10
    SELECT count(*) INTO n_saine FROM stock_reservations
    WHERE id = r_saine AND status = 'active' AND warehouse_id = wa AND quantity = 8;
    SELECT count(*) INTO n_sans_soc FROM stock_reservations WHERE id = r_sans_societe;
    n_second := stock_reservations_reprendre_orphelins();
    SELECT count(*) INTO n_violent FROM stock_reservations sr
    WHERE NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id = sr.tenant_id)
       OR NOT EXISTS (SELECT 1 FROM products p WHERE p.tenant_id = sr.tenant_id AND p.id = sr.product_id)
       OR (sr.warehouse_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM warehouses w WHERE w.tenant_id = sr.tenant_id AND w.id = sr.warehouse_id));

    RAISE EXCEPTION 'ANNULATION_352';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'ANNULATION_352' THEN v_err := SQLERRM; END IF;
  END;

  PERFORM _rec('T08', 'reprise — article introuvable : réservation retirée, ligne entière et motif au journal d''audit',
    v_err IS NULL AND n_retirees = 0 AND n_audit_del = 2
      AND v_meta->'ligne'->>'product_id' = pb::text AND (v_meta->'ligne'->>'quantity')::numeric = 5
      AND COALESCE(v_meta->>'motif', '') <> '',
    COALESCE(v_err, format('encore en table=%s (attendu 0) tracées=%s (attendu 2) ligne gardée=%s',
                           n_retirees, n_audit_del, left(COALESCE(v_meta->'ligne', 'null'::jsonb)::text, 120))));

  PERFORM _rec('T09', 'reprise — dépôt introuvable : détachée du dépôt, l''active est annulée, la consommée le reste, tracé',
    v_err IS NULL AND s_actif = 'cancelled' AND w_actif IS NULL
      AND s_conso = 'consumed' AND w_conso IS NULL AND n_audit_upd = 2,
    COALESCE(v_err, format('active → %s (dépôt %s) ; consommée → %s (dépôt %s) ; tracées avec le dépôt d''origine=%s (attendu 2)',
                           s_actif, COALESCE(w_actif::text, 'NULL'), s_conso, COALESCE(w_conso::text, 'NULL'), n_audit_upd)));

  PERFORM _rec('T10', 'reprise — la saine est intacte, celle d''une société disparue part, le second passage rend 0',
    v_err IS NULL AND n_saine = 1 AND n_sans_soc = 0 AND n_premier = 5 AND n_second = 0 AND n_violent = 0,
    COALESCE(v_err, format('saine intacte=%s société disparue restante=%s premier passage=%s (attendu 5) second=%s (attendu 0) lignes qui violeraient encore les clés=%s',
                           n_saine, n_sans_soc, n_premier, n_second, n_violent)));

  PERFORM _rec('T11', 'reprise — le lien de chaîne actif de la réservation reprise est fermé (rompu, motif), pas effacé',
    v_err IS NULL AND n_liens = 2 AND n_rompus = 2 AND n_actifs = 0,
    COALESCE(v_err, format('liens=%s (attendu 2) rompus avec le motif 352=%s (attendu 2) encore actifs=%s (attendu 0)',
                           n_liens, n_rompus, n_actifs)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'T08 → T11 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('352');
