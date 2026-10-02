-- ============================================================
-- 313_chain_effects_contract_tests.sql — L7 : ce que les contrats d'effet garantissent
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md, doctrine **M-05**
-- (« chaque type de document déclare son effet, y compris aucun ») et lot **L7**
-- (« contrats d'effet déclarés, 0 % → 100 % »). La porte **G2**
-- (`ci/check_effects_contract.sql`) tient la règle ; ce fichier mesure l'effet des
-- **14 contrats** que la migration 313 déclare.
--
--   D01  les 14 couples (document, événement, effet) sont déclarés, actifs, et
--        lisibles par une société (contrat standard, `tenant_id IS NULL`) ;
--   D02  `chain_autorise` rend VRAI pour les 14, pour une société neuve — c'est
--        ce que « 0 → 100 % » veut dire, mesuré ;
--   D03  l'exécution réelle ne trace plus `tolere` : une facture validée écrit
--        UNE trace `applique` (avant la 313 : `tolere` + `applique`, mesuré) ;
--   D04  la ligne de société l'emporte : une société qui éteint un effet obtient
--        `chain_autorise` faux, la voisine garde le contrat standard actif ;
--   D05  en mode `refuse`, un effet éteint BLOQUE l'opération métier avant tout
--        effet — aucune ligne d'écriture n'est produite — et un effet déclaré
--        passe (le refus ne frappe que ce qui n'est pas autorisé) ;
--   D06  **le réel confronté à la déclaration** (le cœur de M-05) : pour chaque
--        contrat, les drapeaux `ecrit_comptable` / `touche_stock` sont comparés
--        aux tables que le maillon écrit vraiment (relevé sur `pg_proc`) ;
--   D07  aucun effet appelé n'est sans contrat, aucun contrat n'est un fantôme :
--        l'extraction qui alimente la porte G2 est rejouée ici, et confrontée
--        aux 14 déclarations ;
--   D08  la migration est rejouable : rejouer ses `INSERT` ne duplique rien et
--        réaligne les drapeaux (14 clés, 14 lignes) ;
--   D09  le contrat standard est en LECTURE seule pour la société (aucune
--        politique d'écriture) : une société ne peut pas réécrire le contrat de
--        toutes les autres — elle éteint le sien ;
--   D10  les drapeaux sont déclaratifs, et c'est dit : mesuré, `actif` est le
--        seul lu par un code ; `ecrit_comptable`, `touche_stock`, `touche_paie`,
--        `journal_code`, `reversible` et `obligatoire` ne sont lus par personne.
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé, puis rôle `authenticated` — un utilisateur réel, sous RLS. Les fonctions
-- du socle (`chain_autorise`) s'appellent, elles, en tant que propriétaire : le
-- socle n'est pas une API (252 §14).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '313', false);
DELETE FROM _audit_results WHERE file = '313';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- LES QUATORZE CONTRATS ATTENDUS — la même liste que la migration 313. Elle est
-- écrite ici en dur : une suite qui lirait la table pour savoir quoi vérifier ne
-- vérifierait rien.
CREATE OR REPLACE FUNCTION _l313_attendus()
RETURNS TABLE(document_type text, evenement text, effet text)
LANGUAGE sql AS $$
  VALUES ('invoices', 'validated', 'sale.invoice.generated_entry'),
         ('credit_notes', 'validated', 'sale.credit_note.generated_entry'),
         ('supplier_payments', 'recorded', 'purchase.payment.generated_entry'),
         ('customer_payments', 'recorded', 'sale.payment.generated_entry'),
         ('bank_accounts', 'created', 'treasury.bank_account.journal'),
         ('bank_accounts', 'created', 'treasury.bank_account.account'),
         ('sales_orders', 'confirmed', 'sale.order.reserved'),
         ('delivery_notes', 'shipped', 'sale.delivery.stock_out'),
         ('st_shipments', 'shipped', 'subcontracting.shipment.stock_out'),
         ('st_receipts', 'received', 'subcontracting.receipt.stock_in'),
         ('pos_sessions', 'closed', 'pos.session.closure'),
         ('bank_transactions', 'reconciled', 'treasury.bank_transaction.reconciled'),
         ('manufacturing_orders', 'completed', 'production.order.generated_entry'),
         ('manufacturing_orders', 'completed', 'production.order.stock_in')
$$;

-- Une facture prête à valider (le même gabarit que la suite 310).
CREATE OR REPLACE FUNCTION _l313_facture(p_t uuid, p_num text, p_cust uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE i uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date,
                        status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (p_t, p_num, p_cust, 'Client L7', '2026-03-01', '2026-03-31',
          'draft', 100, 20, 120, 0, 120)
  RETURNING id INTO i;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price,
                             vat_rate, total, vat_code, vat_amount)
  VALUES (p_t, i, 'Prestation L7', 1, 100, 20, 100, 'FR20', 20);
  RETURN i;
END $$;

-- Les tables qu'un effet FAIT écrire, relevées sur le code compilé (pas sur la
-- déclaration) : c'est la moitié « réel » de la confrontation de M-05.
CREATE OR REPLACE FUNCTION _l313_tables_ecrites(p_effet text)
RETURNS text LANGUAGE sql AS $$
  SELECT COALESCE(string_agg(DISTINCT m[2], ', '), '')
  FROM pg_proc p
  CROSS JOIN LATERAL regexp_matches(p.prosrc,
    '(INSERT INTO|UPDATE|DELETE FROM) (?:public\.)?([a-z_]+)', 'g') m
  WHERE p.proname NOT LIKE '\_%'
    AND p.prosrc LIKE '%' || p_effet || '%'
$$;

-- ═════════════════════════════════════════════════════════════
-- D01 — les 14 couples sont déclarés, actifs, et lisibles par une société
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L7A', false);
        n_attendus int; n_declares int; n_actifs int; n_inactifs int;
BEGIN
  SELECT count(*) INTO n_attendus FROM _l313_attendus();

  SELECT count(*) INTO n_declares
  FROM _l313_attendus() a
  JOIN document_effects e
    ON e.tenant_id IS NULL AND e.document_type = a.document_type
   AND e.evenement = a.evenement AND e.effet = a.effet;

  SELECT count(*) INTO n_actifs
  FROM _l313_attendus() a
  JOIN document_effects e
    ON e.tenant_id IS NULL AND e.document_type = a.document_type
   AND e.evenement = a.evenement AND e.effet = a.effet AND e.actif;

  -- Lisibles PAR UNE SOCIÉTÉ : la politique de `document_effects` autorise les
  -- lignes `tenant_id IS NULL` (donnée de référence), et c'est la lecture que
  -- l'écran fera.
  PERFORM _as_user();
  SELECT count(*) INTO n_inactifs
  FROM _l313_attendus() a
  JOIN document_effects e
    ON e.tenant_id IS NULL AND e.document_type = a.document_type
   AND e.evenement = a.evenement AND e.effet = a.effet;

  PERFORM _rec('D01', 'les 14 contrats d''effet standard sont déclarés, actifs, et lisibles par une société',
    n_attendus = 14 AND n_declares = 14 AND n_actifs = 14 AND n_inactifs = 14,
    format('attendus=%s, déclarés=%s, actifs=%s, visibles sous RLS=%s', n_attendus, n_declares, n_actifs, n_inactifs));
END $$;

-- ═════════════════════════════════════════════════════════════
-- D02 — `chain_autorise` rend VRAI pour les 14 (« 0 → 100 % », mesuré)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L7B', false);
        n_autorises int; n_total int; v_refuses text;
BEGIN
  SELECT count(*) INTO n_total FROM _l313_attendus();

  SELECT count(*) INTO n_autorises
  FROM _l313_attendus() a
  WHERE chain_autorise(t, a.document_type, a.evenement, a.effet);

  SELECT string_agg(a.effet, ', ' ORDER BY a.effet) INTO v_refuses
  FROM _l313_attendus() a
  WHERE NOT chain_autorise(t, a.document_type, a.evenement, a.effet);

  PERFORM _rec('D02', 'chain_autorise rend vrai pour les 14 contrats déclarés, pour une société neuve sans ligne de société',
    n_autorises = 14 AND n_total = 14,
    format('autorisés=%s/%s%s', n_autorises, n_total,
           CASE WHEN v_refuses IS NULL THEN '' ELSE ' — refusés : ' || v_refuses END));
END $$;

-- ═════════════════════════════════════════════════════════════
-- D03 — l'exécution réelle ne trace plus `tolere`
--   Le défaut mesuré avant la 313 : 1 132 traces `tolere` pour 1 117 `applique`
--   sur la base de test. Ici, une facture validée : UNE trace, `applique`.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L7C'); c uuid; inv uuid; n_tolere int; n_applique int; n_ignore int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client L7', 'L7001') RETURNING id INTO c;
  inv := _l313_facture(t, 'F-L7-1', c);
  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT count(*) FILTER (WHERE resultat = 'tolere'),
           count(*) FILTER (WHERE resultat = 'applique'),
           count(*) FILTER (WHERE resultat = 'ignore')
      INTO n_tolere, n_applique, n_ignore
    FROM chain_traces WHERE tenant_id = t AND effet = 'sale.invoice.generated_entry';

    PERFORM _rec('D03', 'facture validée : UNE SEULE trace `applique` — le contrat étant déclaré, plus aucune trace « sans contrat » (avant la 313 : tolere + applique)',
      n_applique = 1 AND n_tolere = 0 AND n_ignore = 0,
      format('tolere=%s (0 attendu), applique=%s (1), ignore=%s', n_tolere, n_applique, n_ignore));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('D03', 'facture validée : UNE SEULE trace `applique` — le contrat étant déclaré, plus aucune trace « sans contrat » (avant la 313 : tolere + applique)', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- D04 — la ligne de société l'emporte, et le contrat standard ne bouge pas
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid := _mk_tenant('L7D1', false); tb uuid := _mk_tenant('L7D2', false);
        v_a boolean; v_b boolean; v_std boolean; n_vus_b int; n_vus_a int; v_auth_ta uuid;
        n_total int;
BEGIN
  -- A éteint l'effet POUR ELLE. La ligne est écrite par le propriétaire : la
  -- société n'a aucun droit d'écriture sur `document_effects` (mesuré par D09).
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  VALUES (ta, 'invoices', 'validated', 'sale.invoice.generated_entry', false)
  ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               document_type, evenement, effet)
  DO UPDATE SET actif = false;

  v_a := chain_autorise(ta, 'invoices', 'validated', 'sale.invoice.generated_entry');
  v_b := chain_autorise(tb, 'invoices', 'validated', 'sale.invoice.generated_entry');

  SELECT e.actif INTO v_std FROM document_effects e
  WHERE e.tenant_id IS NULL AND e.document_type = 'invoices'
    AND e.evenement = 'validated' AND e.effet = 'sale.invoice.generated_entry';

  -- Ce que le PROPRIÉTAIRE voit : le contrat standard ET la ligne de A.
  SELECT count(*) INTO n_total FROM document_effects
  WHERE document_type = 'invoices' AND evenement = 'validated'
    AND effet = 'sale.invoice.generated_entry';

  -- L'identité de A se lit AVANT de passer en `authenticated` : sous le contexte
  -- de B, le RLS de `tenant_users` cache les lignes de A — le scénario comparerait
  -- alors avec NULL sans le dire (leçon apprise en écrivant ce scénario).
  SELECT tu.auth_id INTO v_auth_ta FROM tenant_users tu
  WHERE tu.tenant_id = ta AND tu.status = 'active' ORDER BY tu.auth_id LIMIT 1;

  -- Lecture sous RLS : le contexte est celui de B (le dernier créé), puis celui
  -- de A. B ne doit PAS voir la ligne de A.
  PERFORM _as_user();
  SELECT count(*) INTO n_vus_b FROM document_effects
  WHERE document_type = 'invoices' AND evenement = 'validated'
    AND effet = 'sale.invoice.generated_entry';

  -- `current_tenant_id()` exige que `auth.uid()` soit membre ACTIF de la société :
  -- les deux réglages sont donc nécessaires (le `sub` seul ne suffit pas, il faut
  -- aussi les revendications que `auth.uid()` lit).
  PERFORM set_config('request.jwt.claim.sub', v_auth_ta::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_auth_ta, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  SELECT count(*) INTO n_vus_a FROM document_effects
  WHERE document_type = 'invoices' AND evenement = 'validated'
    AND effet = 'sale.invoice.generated_entry';

  PERFORM _rec('D04', 'une société qui éteint un effet obtient `chain_autorise` faux pour elle, vrai pour la voisine ; le contrat standard reste actif et B ne voit pas la ligne de A',
    NOT v_a AND v_b AND v_std AND n_vus_b = 1 AND n_vus_a = 2,
    format('A autorisé=%s (faux), B autorisé=%s (vrai), standard actif=%s, lignes (propriétaire, publiées et non assertées)=%s, vues par B=%s (1), par A=%s (2)',
           v_a, v_b, v_std, n_total, n_vus_b, n_vus_a));
END $$;

-- ═════════════════════════════════════════════════════════════
-- D05 — mode `refuse` + effet éteint : bloqué AVANT tout effet
--   Et la contre-épreuve : contrat rallumé, la même opération passe — le refus
--   ne frappe que ce qui n'est pas autorisé.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L7E'); c uuid; inv uuid; inv2 uuid;
        v_refuse boolean := false; v_msg text := 'ACCEPTÉ'; v_second boolean := false;
        n_entries int; v_statut text;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client L7E', 'L7002') RETURNING id INTO c;
  inv := _l313_facture(t, 'F-L7-E1', c);
  inv2 := _l313_facture(t, 'F-L7-E2', c);

  -- L'effet est ÉTEINT pour cette société, et elle demande le mode `refuse`.
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  VALUES (t, 'invoices', 'validated', 'sale.invoice.generated_entry', false)
  ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               document_type, evenement, effet)
  DO UPDATE SET actif = false;
  INSERT INTO chain_settings (tenant_id, enforcement) VALUES (t, 'refuse')
  ON CONFLICT (tenant_id) DO UPDATE SET enforcement = 'refuse';

  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  EXCEPTION WHEN check_violation THEN
    v_refuse := true; v_msg := SQLERRM;
  END;

  -- Le refus est AVANT effet : aucune écriture, et le document n'est pas validé.
  SELECT count(*) INTO n_entries FROM journal_entries WHERE tenant_id = t;
  SELECT validation_status INTO v_statut FROM invoices WHERE id = inv;

  -- Contrat RALLUMÉ : la même opération passe.
  EXECUTE 'RESET ROLE';
  UPDATE document_effects SET actif = true
  WHERE tenant_id = t AND document_type = 'invoices' AND evenement = 'validated'
    AND effet = 'sale.invoice.generated_entry';
  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv2;
    v_second := true;
  EXCEPTION WHEN OTHERS THEN
    v_second := false; v_msg := v_msg || ' | second : ' || SQLERRM;
  END;

  PERFORM _rec('D05', 'mode refuse + effet éteint : l''opération est BLOQUÉE avant tout effet (aucune écriture, document non validé), avec un message nominatif ; contrat rallumé, la même opération passe',
    v_refuse AND v_msg LIKE '%sale.invoice.generated_entry%' AND n_entries = 0
      AND v_statut IS DISTINCT FROM 'validated' AND v_second,
    format('refusé=%s, écritures produites=%s (0), statut=%s, second passé=%s — %s',
           v_refuse, n_entries, v_statut, v_second, left(v_msg, 120)));
END $$;


-- ═════════════════════════════════════════════════════════════
-- D06 — LE RÉEL CONFRONTÉ À LA DÉCLARATION (effet comptable, exécuté)
--
--   Le cœur de M-05 : « un test exécute le document et compare le réel à la
--   déclaration ». Une facture est validée pour de vrai : la déclaration dit
--   `ecrit_comptable = true` et `touche_stock = false` — on compte les écritures
--   ET les mouvements de stock produits.
--
--   ⚠️ Ce que ce scénario ne fait pas, et qui est dit : la confrontation est faite
--   **par exécution** pour UN effet comptable et UN effet de stock (D07) ; les
--   douze autres demandent leurs douze décors métier (avoir, deux règlements,
--   compte bancaire, expédition et réception de sous-traitance, clôture de caisse,
--   rapprochement, deux effets d'OF). Une confrontation par *lecture du code*
--   avait été écrite d'abord : elle a été **retirée** parce qu'elle produisait de
--   faux verdicts (le déclencheur frère d'un effet peut écrire plus que l'effet,
--   et `pos_sessions` a un maillon BEFORE là où son compagnon est AFTER) —
--   mesuré, pas supposé. La confrontation par exécution des douze autres est du
--   lot **L3**.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L7F'); c uuid; inv uuid;
        n_ecritures int; n_lignes int; n_mouvements int; v_cpt boolean; v_stk boolean;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client L7F', 'L7003') RETURNING id INTO c;
  inv := _l313_facture(t, 'F-L7-D6', c);

  SELECT ec.ecrit_comptable, ec.touche_stock INTO v_cpt, v_stk
  FROM document_effects ec
  WHERE ec.tenant_id IS NULL AND ec.document_type = 'invoices'
    AND ec.evenement = 'validated' AND ec.effet = 'sale.invoice.generated_entry';

  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;

    SELECT count(*) INTO n_ecritures FROM journal_entries WHERE tenant_id = t;
    SELECT count(*) INTO n_lignes
      FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
      WHERE je.tenant_id = t;
    SELECT count(*) INTO n_mouvements FROM stock_movements WHERE tenant_id = t;

    PERFORM _rec('D06', 'facture validée, confrontée à sa déclaration : `ecrit_comptable` vrai et l''écriture existe (en-tête ET lignes), `touche_stock` faux et AUCUN mouvement n''est écrit',
      v_cpt AND v_stk = false AND n_ecritures = 1 AND n_lignes >= 1 AND n_mouvements = 0,
      format('déclaré : comptable=%s / stock=%s | réel : %s écriture(s), %s ligne(s), %s mouvement(s) de stock',
             v_cpt, v_stk, n_ecritures, n_lignes, n_mouvements));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('D06', 'facture validée, confrontée à sa déclaration : `ecrit_comptable` vrai et l''écriture existe (en-tête ET lignes), `touche_stock` faux et AUCUN mouvement n''est écrit', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- D07 — LA MÊME CONFRONTATION, sur un effet de STOCK (exécuté)
--   Une commande confirmée : la déclaration dit `touche_stock = true` et
--   `ecrit_comptable = false` — on compte les réservations ET les écritures.
-- ═════════════════════════════════════════════════════════════

-- Un décor de vente réduit (le gabarit de la 312) : deux articles en stock.
DROP FUNCTION IF EXISTS _l313_vente(text);
CREATE OR REPLACE FUNCTION _l313_vente(p_nom text, OUT t uuid, OUT wh uuid, OUT c uuid,
                                       OUT p1 uuid, OUT p2 uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article 1 ' || p_nom, 'A1-' || p_nom, 'stock', 5) RETURNING id INTO p1;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article 2 ' || p_nom, 'A2-' || p_nom, 'stock', 5) RETURNING id INTO p2;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, movement_date, date)
  VALUES (t, p1, wh, 'in', 'in', 100, 5, 'APPRO1-' || p_nom, CURRENT_DATE, CURRENT_DATE),
         (t, p2, wh, 'in', 'in', 100, 5, 'APPRO2-' || p_nom, CURRENT_DATE, CURRENT_DATE);
END $$;

DO $$
DECLARE v record; so uuid; v_cpt boolean; v_stk boolean;
        n_reservations int; n_ecritures int; n_ecritures_avant int;
BEGIN
  v := _l313_vente('L7G');
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
  VALUES (v.t, 'CV-L7G', v.c, CURRENT_DATE, 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
  VALUES (v.t, so, v.p1, 'Ligne 1', 3, 20), (v.t, so, v.p2, 'Ligne 2', 4, 20);

  SELECT ec.ecrit_comptable, ec.touche_stock INTO v_cpt, v_stk
  FROM document_effects ec
  WHERE ec.tenant_id IS NULL AND ec.document_type = 'sales_orders'
    AND ec.evenement = 'confirmed' AND ec.effet = 'sale.order.reserved';

  PERFORM _as_user();
  BEGIN
    -- La déclaration porte sur L'EFFET, pas sur la société : le décor (entrée de
    -- stock) a déjà pu écrire des pièces. On compare donc un AVANT et un APRÈS,
    -- jamais un total — c'est ainsi qu'on isole ce que l'effet ajoute.
    SELECT count(*) INTO n_ecritures_avant FROM journal_entries WHERE tenant_id = v.t;

    UPDATE sales_orders SET status = 'confirmed' WHERE id = so;

    SELECT count(*) INTO n_reservations FROM stock_reservations
    WHERE tenant_id = v.t AND reference_id = so;
    SELECT count(*) INTO n_ecritures FROM journal_entries WHERE tenant_id = v.t;

    PERFORM _rec('D07', 'commande confirmée, confrontée à sa déclaration : `touche_stock` vrai et les réservations existent, `ecrit_comptable` faux et l''effet N''AJOUTE aucune écriture',
      v_cpt = false AND v_stk AND n_reservations >= 2 AND n_ecritures = n_ecritures_avant,
      format('déclaré : comptable=%s / stock=%s | réel : %s réservation(s), écritures avant=%s après=%s (aucune ajoutée)',
             v_cpt, v_stk, n_reservations, n_ecritures_avant, n_ecritures));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('D07', 'commande confirmée, confrontée à sa déclaration : `touche_stock` vrai et les réservations existent, `ecrit_comptable` faux et l''effet N''AJOUTE aucune écriture', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- D08 — aucun effet appelé sans contrat, aucun contrat fantôme
--   L'extraction qui alimente la porte G2 (`chain_avant` → couples,
--   `link_documents` → effets) est rejouée ici, et confrontée aux déclarations :
--   c'est la même mesure, vue du côté de la MIGRATION (elle doit couvrir le code).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_couples_sans int; v_effets_sans int; v_fantomes int; n_couples int; n_effets int;
        v_sans text;
BEGIN
  WITH f AS (
    SELECT p.proname, p.prosrc FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    WHERE p.proname NOT LIKE '\_%'
      AND p.proname NOT IN ('link_documents', 'emit_domain_event', 'chain_avant', 'chain_apres',
        'chain_trace', 'chain_deja_fait', 'chain_integrity_ok', 'chain_autorise', 'chain_regenerate',
        'chain_enforcement_mode', 'chain_set_enforcement', 'chain_ensure_partitions',
        'chain_ensure_partitions_table', 'chain_lien_actif', 'chain_lien_tour', 'chain_lien_fermer',
        'chain_lien_remplacer', 'chain_lien_rompre', 'chain_liens_fermer')
      AND p.prosrc ~ 'chain_avant|link_documents'
  ),
  couples AS (
    SELECT DISTINCT m[1] || ' / ' || m[2] || ' / ' || m[3] AS cle
    FROM f CROSS JOIN LATERAL regexp_matches(f.prosrc,
      'chain_avant\s*\(\s*[^,]+,\s*''([^'']+)''\s*,\s*''([^'']+)''\s*,\s*''([^'']+)''', 'g') m
  ),
  effets AS (
    SELECT DISTINCT m[1] AS cle
    FROM f CROSS JOIN LATERAL regexp_matches(f.prosrc,
      'link_documents\s*\(\s*[^,]+,\s*''[^'']*''\s*,\s*[^,]+,\s*''[^'']*''\s*,\s*[^,]+,\s*''([^'']+)''', 'g') m
  )
  SELECT (SELECT count(*) FROM couples),
         (SELECT count(*) FROM effets),
         (SELECT count(*) FROM couples c WHERE NOT EXISTS (
            SELECT 1 FROM document_effects e WHERE e.tenant_id IS NULL
              AND e.document_type || ' / ' || e.evenement || ' / ' || e.effet = c.cle)),
         (SELECT count(*) FROM effets x WHERE NOT EXISTS (
            SELECT 1 FROM document_effects e WHERE e.tenant_id IS NULL AND e.effet = x.cle))
    INTO n_couples, n_effets, v_couples_sans, v_effets_sans;

  -- Contrat fantôme PARMI LES 14 : un contrat déclaré que le code ne nomme nulle
  -- part (ni le maillon, ni son compagnon) serait une déclaration en l'air.
  SELECT count(*) INTO v_fantomes FROM _l313_attendus() a
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    WHERE p.proname NOT LIKE '\_%'
      AND p.prosrc LIKE '%' || a.effet || '%'
      AND p.prosrc ~ 'chain_avant|link_documents');

  SELECT string_agg(c.cle, ', ') INTO v_sans
  FROM (SELECT DISTINCT m[1] || ' / ' || m[2] || ' / ' || m[3] AS cle
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
        CROSS JOIN LATERAL regexp_matches(p.prosrc,
          'chain_avant\s*\(\s*[^,]+,\s*''([^'']+)''\s*,\s*''([^'']+)''\s*,\s*''([^'']+)''', 'g') m
        WHERE p.proname NOT LIKE '\_%'
          AND p.proname NOT IN ('chain_avant', 'chain_lien_fermer')
          AND p.prosrc ~ 'chain_avant') c
  WHERE NOT EXISTS (SELECT 1 FROM document_effects e WHERE e.tenant_id IS NULL
                      AND e.document_type || ' / ' || e.evenement || ' / ' || e.effet = c.cle);

  PERFORM _rec('D08', 'les couples et les effets appelés par le code sont TOUS déclarés, et aucun des 14 contrats n''est fantôme',
    n_couples >= 11 AND n_effets >= 14 AND v_couples_sans = 0 AND v_effets_sans = 0 AND v_fantomes = 0,
    format('couples lus=%s (0 sans contrat), effets lus=%s (0 sans contrat), contrats fantômes=%s%s',
           n_couples, n_effets, v_fantomes,
           CASE WHEN v_sans IS NULL THEN '' ELSE ' — sans contrat : ' || v_sans END));
END $$;

-- ═════════════════════════════════════════════════════════════
-- D09 — la migration est rejouable sans rien dupliquer
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_avant int; n_apres int; n_actifs_avant int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE e.actif) INTO n_avant, n_actifs_avant
  FROM document_effects e
  WHERE e.tenant_id IS NULL
    AND EXISTS (SELECT 1 FROM _l313_attendus() a
                WHERE a.document_type = e.document_type AND a.evenement = e.evenement
                  AND a.effet = e.effet);

  -- Le geste exact de la 313, rejoué : il doit RÉALIGNER, pas dupliquer.
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  SELECT NULL, a.document_type, a.evenement, a.effet, true FROM _l313_attendus() a
  ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               document_type, evenement, effet)
  DO UPDATE SET actif = EXCLUDED.actif;

  SELECT count(*), count(*) FILTER (WHERE e.actif) INTO n_apres, n_actifs_avant
  FROM document_effects e
  WHERE e.tenant_id IS NULL
    AND EXISTS (SELECT 1 FROM _l313_attendus() a
                WHERE a.document_type = e.document_type AND a.evenement = e.evenement
                  AND a.effet = e.effet);

  PERFORM _rec('D09', 'rejouer les déclarations de la 313 ne duplique rien : 14 clés, 14 lignes, toutes actives',
    n_avant = 14 AND n_apres = 14 AND n_actifs_avant = 14,
    format('avant : %s ligne(s) ; après rejeu : %s ligne(s), %s active(s)', n_avant, n_apres, n_actifs_avant));
END $$;


-- ═════════════════════════════════════════════════════════════
-- D10 — le contrat est en LECTURE seule pour la société
--   Elle l'éteint par une ligne de société (écrite par le propriétaire, D04) ;
--   elle n'écrit pas dans la table. C'est la même règle que le registre de
--   chaîne (252, T05), et elle vaut pour les six tables du socle.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L7I', false); v_refuse boolean := false; v_msg text;
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO document_effects (tenant_id, document_type, evenement, effet)
    VALUES (t, 'zz_document', 'zz_evenement', 'zz.effet');
    v_msg := 'insertion ACCEPTÉE';
  EXCEPTION WHEN insufficient_privilege THEN
    v_refuse := true; v_msg := 'insufficient_privilege';
  WHEN OTHERS THEN
    v_refuse := true; v_msg := SQLSTATE || ' — ' || left(SQLERRM, 60);
  END;

  PERFORM _rec('D10', 'la société ne peut pas écrire dans le contrat d''effet (lecture seule) : elle l''éteint par une ligne de société, écrite par le propriétaire',
    v_refuse, format('écriture directe refusée=%s — %s', v_refuse, v_msg));
END $$;

-- ═════════════════════════════════════════════════════════════
-- D11 — les drapeaux sont DÉCLARATIFS, et c'est dit
--   Mesuré le 30/09/2026 : `actif` est le seul drapeau de `document_effects` lu
--   par un code (`chain_autorise`). Les six autres — `ecrit_comptable`,
--   `journal_code`, `touche_stock`, `touche_paie`, `reversible`, `obligatoire` —
--   n'ont AUCUN lecteur : ils déclarent ce que la porte G2 confronte au réel, et
--   ce que les écrans du lot L5 publieront. Un drapeau sans lecteur ne protège
--   rien : ce scénario l'empêche de devenir un mensonge silencieux — le jour où
--   l'un d'eux sera lu, le compte changera et il faudra le dire.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_actif int; v_autres int; v_noms text;
BEGIN
  SELECT count(*) INTO v_actif FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.proname NOT LIKE '\_%' AND p.prosrc ~ 'document_effects' AND p.prosrc ~ '\.actif';

  SELECT count(*), string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_autres, v_noms
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.proname NOT LIKE '\_%' AND p.prosrc ~ 'document_effects'
    AND p.prosrc ~ '\.(ecrit_comptable|touche_stock|touche_paie|obligatoire|reversible|journal_code)';

  PERFORM _rec('D11', '`actif` est le seul drapeau du contrat lu par un code (`chain_autorise`) ; les six autres sont déclaratifs et n''ont aucun lecteur — mesuré, et publié',
    v_actif >= 1 AND v_autres = 0,
    format('fonctions lisant document_effects.actif=%s ; lisant un autre drapeau=%s%s',
           v_actif, v_autres, CASE WHEN v_noms IS NULL THEN '' ELSE ' — ' || v_noms END));
END $$;

-- ─────────────────────────────────────────────────────────────
-- Le registre des échecs attendus reste VIDE : aucun scénario de ce fichier n'a
-- le droit d'échouer (doctrine AUD-A02). Les verdicts attendus qui ont CHANGÉ le
-- 30/09 (T01, T11, T12 de la suite 310) sont documentés dans leur fichier, pas
-- blanchis ici.
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('313');

