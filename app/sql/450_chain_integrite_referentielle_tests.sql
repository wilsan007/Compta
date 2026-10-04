-- ============================================================
-- 450_chain_integrite_referentielle_tests.sql — Partie 5 : l'intégrité
--   référentielle des chaînages (migrations 450 → 455)
--
--   T01  le REGISTRE est complet : 27 types, chaque table (et table de
--        lignes) existe, et CHAQUE type écrit en dur dans un appel à
--        link_documents par un maillon est inscrit ;
--   T02  un type INCONNU est refusé (23503) ;
--   T03  un amont INEXISTANT est refusé, et un amont d'une AUTRE société aussi ;
--   T04  une ligne amont inexistante est refusée ; une ligne réelle passe ;
--   T05  non-régression : confirmer une commande pose toujours son lien ;
--   T06  D1 — un compte bancaire SANS opération se supprime (règle 244) et ses
--        deux liens sont FERMÉS (rompu) — plus d'orphelin actif ;
--   T07  D2 — supprimer un règlement client relié : REFUSÉ ;
--   T08  D3 — commande confirmée : suppression REFUSÉE (document ET ligne) ;
--        après ANNULATION (qui ferme les liens) : suppression ACCEPTÉE ;
--   T09  D4 — réservation : suppression REFUSÉE ; release_stock_reservation
--        rend la quantité réservée, ferme le lien (rompu, motif) ; ensuite la
--        suppression passe ;
--   T10  un lecteur (viewer) ne libère pas une réservation (42501) ;
--   T11  STRUCTURE : chaque table du registre (et de lignes) porte sa garde ;
--        les fonctions internes ne sont pas exposées ;
--   T12  INV-19 est MESURABLE : un orphelin fabriqué le rend « rompu »,
--        chain_fermer_orphelins le ferme (1 puis 0), INV-19 redevient « tenu » ;
--   T13  la suppression d'une SOCIÉTÉ entière passe (cascade) ;
--   T14  D5 — le journal et le compte comptable créés pour une banque : REFUSÉS.
--
-- Vu ROUGE sur le code d'avant (base neuve, migrations ≤ 413, mesuré le
-- 02/10/2026) : T01→T04, T06→T12 et T14 rouges ; T05 et T13 verts — ce sont
-- des NON-RÉGRESSIONS (le maillon de la commande, la cascade d'une société) qui
-- doivent rester vraies avant comme après.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '450', false);
DELETE FROM _audit_results WHERE file = '450';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier
-- ─────────────────────────────────────────────────────────────

-- Une commande client CONFIRMÉE, avec stock disponible : son maillon pose un
-- lien sales_orders → stock_reservations PAR LIGNE (reserve_stock_on_sales_order_confirm).
DROP FUNCTION IF EXISTS _p5_commande(uuid, text, numeric);
CREATE OR REPLACE FUNCTION _p5_commande(p_t uuid, p_nom text, p_qte numeric DEFAULT 3)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c uuid; p uuid; wh uuid; so uuid;
BEGIN
  INSERT INTO customers (name, tenant_id) VALUES ('Client ' || p_nom, p_t) RETURNING id INTO c;
  INSERT INTO warehouses (code, name, tenant_id) VALUES ('W-' || p_nom, 'Dépôt ' || p_nom, p_t) RETURNING id INTO wh;
  INSERT INTO products (name, sku, type, sale_price, purchase_price, vat_rate, tenant_id)
    VALUES ('Article ' || p_nom, 'SKU-' || p_nom, 'stock', 20, 5, 20, p_t) RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, reference, date, movement_date)
    VALUES (p_t, p, wh, 'in', 'in', 100, 5, 'APPRO-' || p_nom, CURRENT_DATE, CURRENT_DATE);
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
    VALUES (p_t, 'CV-' || p_nom, c, CURRENT_DATE, 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
    VALUES (p_t, so, p, 'Ligne ' || p_nom, p_qte, 20);
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;
  RETURN so;
END $$;

-- Tente une suppression et rend : 'supprimé', 'refusé (chaîne)' ou 'refusé : <message>'.
DROP FUNCTION IF EXISTS _p5_supprimer(text, uuid);
CREATE OR REPLACE FUNCTION _p5_supprimer(p_table text, p_id uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  EXECUTE format('DELETE FROM %I WHERE id = $1', p_table) USING p_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN CASE WHEN n = 1 THEN 'supprimé' ELSE 'aucune ligne' END;
EXCEPTION
  WHEN foreign_key_violation THEN
    RETURN CASE WHEN SQLERRM = 'CHAIN_DELETE_REFUSED' THEN 'refusé (chaîne)' ELSE 'refusé : ' || SQLERRM END;
  WHEN OTHERS THEN
    RETURN 'refusé : ' || SQLERRM;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T01 — le registre est complet
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_types int; n_tables_absentes int; v_non_inscrits text;
BEGIN
  SELECT count(*) INTO n_types FROM chain_document_types;
  SELECT count(*) INTO n_tables_absentes
  FROM chain_document_types t
  CROSS JOIN LATERAL (VALUES (t.table_name), (t.ligne_table)) x(tbl)
  WHERE x.tbl IS NOT NULL AND to_regclass('public.' || x.tbl) IS NULL;

  -- Les types écrits EN DUR dans les appels link_documents(société, 'amont', id, 'aval', …)
  SELECT string_agg(DISTINCT ty, ', ') INTO v_non_inscrits
  FROM (
    SELECT unnest(ARRAY[m[1], m[2]]) AS ty
    FROM pg_proc p,
         regexp_matches(p.prosrc,
           'link_documents\(\s*[^,()]+,\s*''([a-z_]+)''\s*,\s*[^,()]+,\s*''([a-z_]+)''', 'g') AS m
    WHERE p.pronamespace = 'public'::regnamespace AND p.proname <> 'link_documents'
  ) x
  WHERE NOT EXISTS (SELECT 1 FROM chain_document_types d WHERE d.code = x.ty);

  PERFORM _rec('T01',
    'le registre est complet : 27 types, toutes les tables existent, et chaque type écrit en dur dans un maillon est inscrit',
    n_types = 27 AND n_tables_absentes = 0 AND v_non_inscrits IS NULL,
    format('types=%s (27) tables absentes=%s types de maillon non inscrits=%s',
           n_types, n_tables_absentes, COALESCE(v_non_inscrits, 'aucun')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'le registre est complet', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — un type inconnu est refusé
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T02'); so uuid; v_code text := '(aucun refus)';
BEGIN
  PERFORM set_config('role', 'none', true);
  INSERT INTO sales_orders (tenant_id, number, status) VALUES (t, 'T02', 'draft') RETURNING id INTO so;
  BEGIN
    PERFORM link_documents(t, 'commande', so, 'sales_orders', so, 'p5.test', 'created_from');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  PERFORM _rec('T02', 'un lien de type inconnu (« commande ») est refusé avec 23503',
    v_code = '23503', format('SQLSTATE=%s', v_code));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — amont inexistant, et amont d'une autre société
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid := _mk_tenant('P5T03A'); tb uuid := _mk_tenant('P5T03B');
        soa uuid; sob uuid; c1 text := '(aucun refus)'; c2 text := '(aucun refus)';
BEGIN
  PERFORM set_config('role', 'none', true);
  INSERT INTO sales_orders (tenant_id, number, status) VALUES (ta, 'T03A', 'draft') RETURNING id INTO soa;
  INSERT INTO sales_orders (tenant_id, number, status) VALUES (tb, 'T03B', 'draft') RETURNING id INTO sob;
  BEGIN
    PERFORM link_documents(ta, 'sales_orders', gen_random_uuid(), 'sales_orders', soa, 'p5.test', 'created_from');
  EXCEPTION WHEN OTHERS THEN c1 := SQLSTATE; END;
  BEGIN
    PERFORM link_documents(tb, 'sales_orders', soa, 'sales_orders', sob, 'p5.test', 'created_from');
  EXCEPTION WHEN OTHERS THEN c2 := SQLSTATE; END;
  PERFORM _rec('T03', 'un amont inexistant, et un amont appartenant à une autre société, sont refusés (23503)',
    c1 = '23503' AND c2 = '23503', format('inexistant=%s autre société=%s', c1, c2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — ligne amont inexistante refusée, ligne réelle acceptée
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T04'); so uuid; ligne uuid; c1 text := '(aucun refus)'; v_lien uuid;
BEGIN
  PERFORM set_config('role', 'none', true);
  INSERT INTO sales_orders (tenant_id, number, status) VALUES (t, 'T04', 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, description, quantity, unit_price)
    VALUES (t, so, 'Ligne T04', 1, 10) RETURNING id INTO ligne;
  BEGIN
    PERFORM link_documents(t, 'sales_orders', so, 'sales_orders', so, 'p5.ligne', 'created_from',
                           '{}'::jsonb, gen_random_uuid(), NULL);
  EXCEPTION WHEN OTHERS THEN c1 := SQLSTATE; END;
  v_lien := link_documents(t, 'sales_orders', so, 'sales_orders', so, 'p5.ligne', 'created_from',
                           '{}'::jsonb, ligne, NULL);
  PERFORM _rec('T04', 'une ligne amont inexistante est refusée (23503) ; une ligne réelle donne un lien',
    c1 = '23503' AND v_lien IS NOT NULL, format('ligne inventée=%s ligne réelle → lien=%s', c1, v_lien IS NOT NULL));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — non-régression : le maillon de la commande pose toujours son lien
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T05'); so uuid; n int;
BEGIN
  PERFORM _as_user();
  so := _p5_commande(t, 'T05');
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'sales_orders' AND amont_id = so
     AND aval_type = 'stock_reservations' AND etat = 'actif';
  PERFORM _rec('T05', 'confirmer une commande pose toujours son lien commande → réservation (non-régression du maillon)',
    n = 1, format('liens actifs=%s (1 attendu)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'T05 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — D1 : le compte bancaire SANS opération se supprime (règle 244),
--       et ses deux liens sont FERMÉS — plus aucun orphelin actif
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T06'); b uuid; v text; n_actifs int; n_rompus int;
BEGIN
  PERFORM _as_user();
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque T06', 'chequing') RETURNING id INTO b;
  v := _p5_supprimer('bank_accounts', b);
  PERFORM set_config('role', 'none', true);
  SELECT count(*) FILTER (WHERE etat = 'actif'), count(*) FILTER (WHERE etat = 'rompu')
    INTO n_actifs, n_rompus
  FROM document_links WHERE tenant_id = t AND amont_type = 'bank_accounts' AND amont_id = b;
  PERFORM _rec('T06', 'D1 — un compte bancaire SANS opération se supprime (244) et ses 2 liens sont fermés (rompu) : aucun lien actif vers rien',
    v = 'supprimé' AND n_actifs = 0 AND n_rompus = 2,
    format('suppression=%s liens actifs=%s liens rompus=%s (2)', v, n_actifs, n_rompus));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'T06 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T07 — D2 : le règlement client relié ne se supprime pas
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T07'); c uuid; inv uuid; cp uuid; v text;
BEGIN
  PERFORM _as_user();
  INSERT INTO customers (name, tenant_id) VALUES ('Client T07', t) RETURNING id INTO c;
  INSERT INTO invoices (number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, tenant_id)
    VALUES ('T07', c, 'Client T07', '2026-03-01', '2026-03-31', 'draft', 100, 20, 120, t) RETURNING id INTO inv;
  INSERT INTO invoice_lines (invoice_id, description, quantity, unit_price, vat_rate, total, vat_total, tenant_id)
    VALUES (inv, 'Prestation', 1, 100, 20, 100, 20, t);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date, amount, method)
    VALUES (t, 'RG-T07', c, inv, '2026-03-05', 120, 'transfer') RETURNING id INTO cp;
  v := _p5_supprimer('customer_payments', cp);
  PERFORM set_config('role', 'none', true);
  PERFORM _rec('T07', 'D2 — un règlement client comptabilisé ne se supprime pas (sinon la facture resterait « payée » sans règlement)',
    v = 'refusé (chaîne)' AND EXISTS (SELECT 1 FROM customer_payments WHERE id = cp),
    format('suppression=%s', v));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'T07 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — D3 : commande confirmée, puis annulée
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T08'); so uuid; ligne uuid; v1 text; v2 text; v3 text; n_actifs int;
BEGIN
  PERFORM _as_user();
  so := _p5_commande(t, 'T08');
  SELECT id INTO ligne FROM sales_order_lines WHERE sales_order_id = so LIMIT 1;
  v1 := _p5_supprimer('sales_orders', so);
  v2 := _p5_supprimer('sales_order_lines', ligne);
  UPDATE sales_orders SET status = 'cancelled' WHERE id = so;   -- le chemin d'annulation (410) ferme les liens
  v3 := _p5_supprimer('sales_orders', so);
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO n_actifs FROM document_links WHERE tenant_id = t AND amont_id = so AND etat = 'actif';
  PERFORM _rec('T08', 'D3 — commande confirmée : ni elle ni sa ligne ne se suppriment ; ANNULÉE (liens fermés), elle se supprime',
    v1 = 'refusé (chaîne)' AND v2 = 'refusé (chaîne)' AND v3 = 'supprimé' AND n_actifs = 0,
    format('commande=%s ligne=%s après annulation=%s liens actifs restants=%s', v1, v2, v3, n_actifs));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'T08 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T09 — D4 : la réservation se LIBÈRE, elle ne se supprime pas
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T09'); so uuid; r uuid; v1 text; v2 text;
        q_avant numeric; q_apres numeric; v_statut text; v_etat text; v_motif text;
BEGIN
  PERFORM _as_user();
  so := _p5_commande(t, 'T09', 3);
  SELECT aval_id INTO r FROM document_links
   WHERE tenant_id = t AND amont_id = so AND aval_type = 'stock_reservations' AND etat = 'actif';
  SELECT COALESCE(sum(reserved_quantity), 0) INTO q_avant FROM stock_quantities WHERE tenant_id = t;
  v1 := _p5_supprimer('stock_reservations', r);
  PERFORM release_stock_reservation(r);
  SELECT COALESCE(sum(reserved_quantity), 0) INTO q_apres FROM stock_quantities WHERE tenant_id = t;
  SELECT status INTO v_statut FROM stock_reservations WHERE id = r;
  v2 := _p5_supprimer('stock_reservations', r);
  PERFORM set_config('role', 'none', true);
  SELECT etat, motif INTO v_etat, v_motif FROM document_links
   WHERE tenant_id = t AND aval_id = r ORDER BY tour DESC LIMIT 1;
  PERFORM _rec('T09', 'D4 — une réservation reliée ne se supprime pas ; release_stock_reservation rend la quantité, ferme le lien (rompu), puis la suppression passe',
    v1 = 'refusé (chaîne)' AND q_avant = 3 AND q_apres = 0 AND v_statut = 'released'
      AND v_etat = 'rompu' AND v_motif ILIKE '%libérée à la main%' AND v2 = 'supprimé',
    format('suppression avant=%s réservé %s → %s statut=%s lien=%s suppression après=%s',
           v1, q_avant, q_apres, v_statut, v_etat, v2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T09', 'T09 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T10 — un lecteur ne libère pas une réservation
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T10'); so uuid; r uuid; v uuid := gen_random_uuid(); v_code text := '(accepté)';
BEGIN
  PERFORM _as_user();
  so := _p5_commande(t, 'T10');
  PERFORM set_config('role', 'none', true);
  SELECT aval_id INTO r FROM document_links WHERE tenant_id = t AND amont_id = so AND aval_type = 'stock_reservations';
  INSERT INTO auth.users (id, email) VALUES (v, 'lecteur-' || v || '@p5.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
    VALUES (t, v, 'lecteur-' || v || '@p5.test', 'Lecteur', 'viewer', 'active');
  PERFORM set_config('request.jwt.claim.sub', v::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, false);
  PERFORM _as_user();
  BEGIN PERFORM release_stock_reservation(r); EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  PERFORM set_config('role', 'none', true);
  PERFORM _rec('T10', 'un lecteur (viewer) ne libère pas une réservation (42501), et elle reste active',
    v_code = '42501' AND (SELECT status FROM stock_reservations WHERE id = r) = 'active',
    format('SQLSTATE=%s', v_code));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T10', 'T10 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T11 — structure : la garde est partout, l'interne n'est pas exposé
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_sans_garde text; v_expose text;
BEGIN
  SELECT string_agg(x.tbl, ', ') INTO v_sans_garde
  FROM chain_document_types t
  CROSS JOIN LATERAL (VALUES (t.table_name, 'zz_garde_p5_suppression'),
                             (t.ligne_table, 'zz_garde_p5_suppression_ligne')) x(tbl, trig)
  WHERE x.tbl IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM pg_trigger g
                     WHERE g.tgrelid = to_regclass('public.' || x.tbl)
                       AND g.tgname = x.trig AND g.tgenabled <> 'D');

  SELECT string_agg(f, ', ') INTO v_expose
  FROM unnest(ARRAY['chain_document_existe(uuid,text,uuid,boolean)', 'chain_fermer_orphelins(uuid)',
                    'link_documents(uuid,text,uuid,text,uuid,text,text,jsonb,uuid,uuid)']) f
  WHERE has_function_privilege('authenticated', f, 'EXECUTE') OR has_function_privilege('anon', f, 'EXECUTE');

  PERFORM _rec('T11', 'structure : les 32 tables (27 documents + 5 tables de lignes) portent leur garde ; les fonctions internes ne sont ni à authenticated ni à anon ; release_stock_reservation est à authenticated, pas à anon',
    v_sans_garde IS NULL AND v_expose IS NULL
      AND has_function_privilege('authenticated', 'release_stock_reservation(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'release_stock_reservation(uuid)', 'EXECUTE')
      AND (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'zz_garde_p5_suppression%') = 32,
    format('sans garde=%s exposées=%s gardes posées=%s (32)', COALESCE(v_sans_garde, 'aucune'),
           COALESCE(v_expose, 'aucune'), (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'zz_garde_p5_suppression%')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T11', 'T11 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T12 — INV-19 est mesurable, et la reprise ferme l'orphelin
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T12'); so uuid; v1 text; v2 text; n1 int; n2 int; v_mesurable boolean;
BEGIN
  PERFORM set_config('role', 'none', true);
  SELECT mesurable INTO v_mesurable FROM chain_invariants WHERE code = 'INV-19' AND tenant_id IS NULL;
  INSERT INTO sales_orders (tenant_id, number, status) VALUES (t, 'T12', 'draft') RETURNING id INTO so;
  -- Un orphelin FABRIQUÉ : insertion directe (le propriétaire contourne link_documents),
  -- l'aval désigne une commande qui n'existe pas.
  INSERT INTO document_links (tenant_id, amont_type, amont_id, aval_type, aval_id, effet, link_type)
  VALUES (t, 'sales_orders', so, 'sales_orders', gen_random_uuid(), 'p5.orphelin', 'created_from');

  PERFORM audit_chains(t);
  SELECT verdict INTO v1 FROM chain_invariant_results WHERE tenant_id = t AND code = 'INV-19' ORDER BY mesure_le DESC, id DESC LIMIT 1;
  n1 := chain_fermer_orphelins(t);
  n2 := chain_fermer_orphelins(t);
  PERFORM audit_chains(t);
  SELECT verdict INTO v2 FROM chain_invariant_results WHERE tenant_id = t AND code = 'INV-19' ORDER BY mesure_le DESC, id DESC LIMIT 1;

  PERFORM _rec('T12', 'INV-19 est mesurable : un lien orphelin le rend « rompu » ; chain_fermer_orphelins le ferme (1, puis 0 au rejeu) ; INV-19 redevient « tenu »',
    v_mesurable AND v1 = 'rompu' AND n1 = 1 AND n2 = 0 AND v2 = 'tenu',
    format('mesurable=%s verdict avant=%s fermés=%s puis %s verdict après=%s', v_mesurable, v1, n1, n2, v2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T12', 'INV-19 est mesurable', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T13 — la suppression d'une société entière passe (cascade)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T13'); b uuid; v text := 'supprimée'; n_liens int; n_banques int;
BEGIN
  PERFORM _as_user();
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque T13', 'chequing') RETURNING id INTO b;
  PERFORM set_config('role', 'none', true);
  BEGIN
    DELETE FROM tenants WHERE id = t;
  EXCEPTION WHEN OTHERS THEN v := 'refusée : ' || SQLERRM; END;
  SELECT count(*) INTO n_liens FROM document_links WHERE tenant_id = t;
  SELECT count(*) INTO n_banques FROM bank_accounts WHERE tenant_id = t;
  PERFORM _rec('T13', 'supprimer une SOCIÉTÉ entière passe : la garde laisse la cascade, liens et documents partent ensemble',
    v = 'supprimée' AND n_liens = 0 AND n_banques = 0,
    format('société=%s liens restants=%s comptes restants=%s', v, n_liens, n_banques));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T13', 'T13 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T14 — D5 : le journal et le compte comptable d'une banque (côté aval)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('P5T14'); b uuid; ja uuid; ca uuid; v1 text; v2 text;
BEGIN
  PERFORM _as_user();
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque T14', 'chequing') RETURNING id INTO b;
  SELECT aval_id INTO ja FROM document_links WHERE tenant_id = t AND amont_id = b AND aval_type = 'journals';
  SELECT aval_id INTO ca FROM document_links WHERE tenant_id = t AND amont_id = b AND aval_type = 'chart_accounts';
  v1 := _p5_supprimer('journals', ja);
  v2 := _p5_supprimer('chart_accounts', ca);
  PERFORM set_config('role', 'none', true);
  PERFORM _rec('T14', 'D5 — le journal et le compte comptable créés pour une banque (aval d''un lien actif) ne se suppriment pas',
    v1 = 'refusé (chaîne)' AND v2 = 'refusé (chaîne)', format('journal=%s compte=%s', v1, v2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T14', 'T14 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('450');
