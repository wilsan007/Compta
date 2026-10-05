-- ═══════════════════════════════════════════════════════════════════════════
-- 493_chain_l16_devis_commande_tests.sql — L16 · devis → commande
-- ═══════════════════════════════════════════════════════════════════════════
-- Cette suite éprouve le maillon de la 493 en dix verdicts, sur les épreuves
-- du banc qui ont un sens ici :
--
--   T01  NOMINAL : le devis accepté produit UNE commande ; les lignes sont
--        copiées ; les PRIX sont gelés (aucun écart avec le devis) ; le total
--        est la somme des lignes acceptées ; le devis dit ce qu'il est devenu ;
--        le LIEN est posé (effet `sale.quote.to_order`) ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) et
--        n'ajoute ni commande ni lien ;
--   T03  REFUS EXPLICITES : devis non accepté, refusé, expiré, sans ligne —
--        quatre refus, quatre raisons ;
--   T04  LA FRISE RÉPOND (I-01) : `chain_document_arborescence` voit la
--        commande depuis le devis, et le devis depuis la commande ;
--   T05  ISOLATION (D8) : le voisin ne peut PAS convertir le devis d'autrui,
--        et ne voit aucun lien.
--
-- Ce que cette suite NE joue PAS, et le dit : D2 (concurrence), D3 (panne
-- partielle), D5 (réouverture) restent hors de portée d'une suite SQL d'un
-- seul processus ; D6 (retour arrière) est tenu par construction (tout ce
-- fichier est transactionnel), D7 (volume) n'a pas de sens sur une chaîne
-- commerciale de deux lignes.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '493', false);
DELETE FROM _audit_results WHERE file = '493';

-- ── T01 — LE NOMINAL : le devis accepté devient une commande, prix gelé ────
DO $$
DECLARE
  t uuid; c uuid; q uuid; o uuid; r jsonb; n int;
  v_total_ordre numeric; v_somme_lignes numeric; v_somme_vat numeric;
BEGIN
  t := _mk_tenant('T493A');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 493', 'C0493') RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date,
                      status, subtotal, vat_total, total)
    VALUES (t, 'D-493-1', c, 'Client 493', '2026-03-01', '2026-03-31', 'accepted', 1500, 275, 1775)
    RETURNING id INTO q;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price,
                           vat_rate, total, vat_total, line_order) VALUES
    (t, q, 'Prestation A', 1, 1000, 20, 1000, 200, 0),
    (t, q, 'Prestation B', 2,  250, 15,  500,  75, 1);

  PERFORM _as_user();
  r := convert_quote_to_order(q);
  o := (r->>'order_id')::uuid;

  PERFORM _rec('T01a', 'le devis accepté produit une commande (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND o IS NOT NULL, r::text);

  SELECT count(*) INTO n FROM sales_order_lines WHERE sales_order_id = o;
  PERFORM _rec('T01b', 'les DEUX lignes du devis sont copiées', n = 2, 'lignes = ' || n);

  -- LE PRIX EST GELÉ : aucun couple (quantité, prix) de la commande n'est
  -- étranger au devis, et aucun du devis ne manque à la commande.
  SELECT count(*) INTO n FROM (
    SELECT l.quantity, l.unit_price FROM quote_lines l WHERE l.quote_id = q
    EXCEPT
    SELECT s.quantity, s.unit_price FROM sales_order_lines s WHERE s.sales_order_id = o
  ) x;
  PERFORM _rec('T01c', 'aucun écart de prix ou de quantité avec le devis (gelé)', n = 0,
    'écarts = ' || n);

  SELECT sum(l.quantity * l.unit_price), sum(l.vat_total) INTO v_somme_lignes, v_somme_vat
    FROM quote_lines l WHERE l.quote_id = q;
  SELECT total INTO v_total_ordre FROM sales_orders WHERE id = o;
  PERFORM _rec('T01d', 'le total de la commande est la somme des lignes ACCEPTÉES',
    v_total_ordre = (v_somme_lignes + v_somme_vat),
    format('commande=%s attendu=%s', v_total_ordre, v_somme_lignes + v_somme_vat));

  SELECT count(*) INTO n FROM quotes
   WHERE id = q AND transformed_to_order_id = o AND transformation_status = 'transformed';
  PERFORM _rec('T01e', 'le devis dit ce qu''il est devenu (colonne + statut de transformation)',
    n = 1, 'devis mis à jour = ' || n);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'quotes' AND amont_id = q
     AND aval_type = 'sales_orders' AND aval_id = o
     AND effet = 'sale.quote.to_order' AND etat = 'actif';
  PERFORM _rec('T01f', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)',
    n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ, et n'ajoute rien ─────────
DO $$
DECLARE
  t uuid; c uuid; q uuid; o uuid; r jsonb; n int;
BEGIN
  t := _mk_tenant('T493B');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 493 B', 'C0493B') RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status)
    VALUES (t, 'D-493-2', c, 'Client 493 B', '2026-03-02', '2026-04-01', 'accepted') RETURNING id INTO q;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
    VALUES (t, q, 'Ligne', 1, 100, 20, 100, 20, 0);

  PERFORM _as_user();
  r := convert_quote_to_order(q);
  o := (r->>'order_id')::uuid;

  BEGIN
    PERFORM convert_quote_to_order(q);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (D1 tenu)', false, 'la 2e tentative a été ACCEPTÉE');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM sales_orders WHERE quote_id = q;
  PERFORM _rec('T02b', 'une SEULE commande pour ce devis après rejeu', n = 1, 'commandes = ' || n);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'quotes' AND amont_id = q AND aval_type = 'sales_orders';
  PERFORM _rec('T02c', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — LES REFUS EXPLICITES : quatre cas, quatre raisons ────────────────
-- Un refus MUET serait le défaut ; un refus qui DIT pourquoi est la correction.
DO $$
DECLARE
  t uuid; c uuid; q_draft uuid; q_rej uuid; q_vide uuid; libelle text;
BEGIN
  t := _mk_tenant('T493C');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 493 C', 'C0493C') RETURNING id INTO c;

  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status)
    VALUES (t, 'D-493-brouillon', c, 'Client 493 C', '2026-03-03', '2026-04-02', 'draft') RETURNING id INTO q_draft;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
    VALUES (t, q_draft, 'Ligne', 1, 10, 20, 10, 2, 0);

  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status)
    VALUES (t, 'D-493-refuse', c, 'Client 493 C', '2026-03-04', '2026-04-03', 'rejected') RETURNING id INTO q_rej;

  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status)
    VALUES (t, 'D-493-vide', c, 'Client 493 C', '2026-03-05', '2026-04-04', 'accepted') RETURNING id INTO q_vide;

  PERFORM _as_user();

  BEGIN
    PERFORM convert_quote_to_order(q_draft);
    PERFORM _rec('T03a', 'un devis NON ACCEPTÉ est refusé', false, 'accepté alors que brouillon');
  EXCEPTION WHEN check_violation THEN
    libelle := SQLERRM;
    PERFORM _rec('T03a', 'un devis NON ACCEPTÉ est refusé, avec sa raison', position('non accept' in libelle) > 0, libelle);
  END;

  BEGIN
    PERFORM convert_quote_to_order(q_rej);
    PERFORM _rec('T03b', 'un devis REFUSÉ est refusé', false, 'accepté alors que refusé');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un devis REFUSÉ est refusé, avec sa raison', true, SQLERRM);
  END;

  BEGIN
    PERFORM convert_quote_to_order(q_vide);
    PERFORM _rec('T03c', 'un devis SANS LIGNE est refusé', false, 'accepté alors que vide');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un devis SANS LIGNE est refusé, avec sa raison', true, SQLERRM);
  END;

  -- Et aucun des trois n'a laissé de commande derrière lui.
  PERFORM _rec('T03d', 'aucune commande créée par les trois refus',
    (SELECT count(*) FROM sales_orders WHERE quote_id IN (q_draft, q_rej, q_vide)) = 0,
    'commandes = ' || (SELECT count(*) FROM sales_orders WHERE quote_id IN (q_draft, q_rej, q_vide)));
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) : le maillon est VISIBLE des deux côtés ───
DO $$
DECLARE t uuid; c uuid; q uuid; o uuid; n int;
BEGIN
  t := _mk_tenant('T493D');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 493 D', 'C0493D') RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status)
    VALUES (t, 'D-493-frise', c, 'Client 493 D', '2026-03-06', '2026-04-05', 'accepted') RETURNING id INTO q;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
    VALUES (t, q, 'Ligne', 1, 500, 20, 500, 100, 0);

  PERFORM _as_user();
  o := ((convert_quote_to_order(q))->>'order_id')::uuid;

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'quotes', q, 'aval', 5, false)
   WHERE type = 'sales_orders' AND id = o;
  PERFORM _rec('T04a', 'depuis le DEVIS, la frise voit la COMMANDE', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'sales_orders', o, 'amont', 5, false)
   WHERE type = 'quotes' AND id = q;
  PERFORM _rec('T04b', 'depuis la COMMANDE, la frise voit le DEVIS', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne convertit pas, et ne voit rien ─────
DO $$
DECLARE
  ta uuid; tb uuid; ca uuid; qa uuid; oa uuid; n int;
BEGIN
  -- Société A fait son travail.
  ta := _mk_tenant('T493E1');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (ta, 'Client E1', 'CE1') RETURNING id INTO ca;
  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status)
    VALUES (ta, 'D-493-E1', ca, 'Client E1', '2026-03-07', '2026-04-06', 'accepted') RETURNING id INTO qa;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
    VALUES (ta, qa, 'Ligne', 1, 100, 20, 100, 20, 0);
  PERFORM _as_user();
  oa := ((convert_quote_to_order(qa))->>'order_id')::uuid;

  -- Société B : le décor change le tenant actif, et B tente de convertir le
  -- devis de A — c'est le scénario du voisin. On repasse par le rôle
  -- superutilisateur pour BÂTIR la société (« RESET ROLE », comme le décor 436) :
  -- `_as_user()` est local à la transaction et n'autorise pas l'écriture dans
  -- `auth.users`.
  RESET ROLE;
  tb := _mk_tenant('T493E2');
  PERFORM _as_user();
  BEGIN
    PERFORM convert_quote_to_order(qa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas convertir le devis d''autrui', false, 'converti par le voisin !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas convertir le devis d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'quotes' AND amont_id = qa AND aval_type = 'sales_orders';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  SELECT count(*) INTO n FROM sales_orders WHERE quote_id = qa;
  PERFORM _rec('T05c', 'le voisin ne voit AUCUNE commande de la société A (isolation)', n = 0, 'commandes visibles = ' || n);

  -- Et la commande existe TOUJOURS — il faut pour la voir sortir du rôle du
  -- voisin : c'est précisément ce que l'isolation garantit, et ce que le
  -- verdict précédent ne pouvait pas dire.
  RESET ROLE;
  SELECT count(*) INTO n FROM sales_orders WHERE quote_id = qa AND tenant_id = ta;
  PERFORM _rec('T05d', 'la commande de A existe toujours, une seule, et reste à A', n = 1, 'commandes de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('493');
