-- ============================================================
-- 322_chain_l1_caisse_rpc_tests.sql — L3 : la caisse, TRACÉE PAR SON CHEMIN
--   D'APPEL — ce que les wrappers garantissent
--
-- Source : inventaire de la tranche 4 §2, lignes 3 et 14 (`pos_refund_ticket`,
-- `create_pos_ticket` — « Maillon / RPC, à tracer — lot L3 »). Un compagnon ne
-- peut pas s'y accrocher : la chaîne vit DANS l'appel.
--
--   T01  encaissement : DEUX liens (stock_out vers le mouvement, payment vers
--        le paiement) et DEUX traces `applique` — le maillon est PILOTÉ ;
--   T02  les AVALS sont exacts : le lien stock_out désigne une sortie `out` du
--        ticket et son payload porte les N identifiants (agrégation par
--        produit — doctrine 316, lien documentaire) ; le lien payment désigne
--        un `pos_payments` du ticket ;
--   T03  le CAS ORDINAIRE ne se trace pas : un ticket de services ne sort
--        rien — aucun lien, aucune trace stock_out (`sans_effet` est réservé
--        à l'anomalie, retenue de la 316) ; le paiement, lui, est tracé ;
--   T04  l'AVOIR : le ticket est lié à son avoir (`adjusted_by`) et à ses
--        rentrées (`pos.ticket.stock_in`), et — doctrine 320 — le lien de sa
--        sortie d'origine est ROMPU, motivé ; le lien du PAIEMENT reste actif
--        (limite de la 255 : le décaissement n'est pas écrit par l'avoir) ;
--   T05  l'ANNULATION (session ouverte) rend le stock : le lien stock_out est
--        ROMPU, la fermeture n'écrit AUCUNE trace (doctrine 312) et le
--        paiement reste actif ;
--   T06  mode `refuse` + effet éteint : l'appel LÈVE et RIEN ne persiste —
--        ni ticket, ni ligne, ni paiement, ni mouvement, ni lien, ni
--        événement. La transaction de l'appel RPC est le mur ;
--   T07  STRUCTURE : les trois corps `_inner` ne sont PAS exécutables par
--        `authenticated` (seuls les wrappers sont exposés — leçon R-17), les
--        trois wrappers sont SECURITY DEFINER et gardent la garde de société,
--        et les quatre contrats sont déclarés et ACTIFS ;
--   T08  CLOISONNEMENT : la société voisine ne voit ni les liens, ni les
--        traces, ni les événements de la caisse de A.
--
-- Ce que cette suite NE mesure PAS : les cinq maillons RPC restants (paie
-- versée, relevé manuel) — la tranche suivante — ni le banc D1→D8.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '412', false);
DELETE FROM _audit_results WHERE file = '322';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Une caisse : dépôt, client, article de stock, article de service, terminal,
-- session ouverte (fond 100). Les comptes du POS et des avoirs sont posés.
DROP FUNCTION IF EXISTS _l322_caisse(text);
CREATE OR REPLACE FUNCTION _l322_caisse(p_nom text,
  OUT t uuid, OUT wh uuid, OUT cli uuid, OUT prod uuid, OUT serv uuid, OUT term uuid, OUT sess uuid)
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom, false);
  PERFORM ensure_standard_journals(t);
  PERFORM _ledger_fixture(t, ARRAY['530000','511200','531000','707000','445710','445711','658000','758000','411000']);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Magasin') RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO cli;
  INSERT INTO products (tenant_id, name, sku, type, sale_price, cost_price, vat_rate)
    VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 10, 5, 20) RETURNING id INTO prod;
  INSERT INTO products (tenant_id, name, sku, type, sale_price, cost_price, vat_rate)
    VALUES (t, 'Service ' || p_nom, 'SRV-' || p_nom, 'service', 30, 0, 20) RETURNING id INTO serv;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, quantity, unit_cost, reference)
    VALUES (t, prod, wh, 'initial', 10, 5, 'Stock initial');
  INSERT INTO pos_terminals (tenant_id, name, warehouse_id) VALUES (t, 'Caisse ' || p_nom, wh) RETURNING id INTO term;
  INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status)
    VALUES (t, term, 'caisse@audit.test', 100, 'open') RETURNING id INTO sess;
END $$;

-- Un ticket par l'appel RPC — le chemin que l'écran prend.
DROP FUNCTION IF EXISTS _l322_ticket(uuid, uuid, numeric, uuid);
CREATE OR REPLACE FUNCTION _l322_ticket(p_sess uuid, p_prod uuid, p_qty numeric, p_cli uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE k public.pos_tickets;
BEGIN
  k := create_pos_ticket(
    jsonb_build_object('session_id', p_sess, 'number', 'T', 'payment_method', 'cash', 'customer_id', p_cli),
    jsonb_build_array(jsonb_build_object('product_id', p_prod, 'description', 'Article', 'quantity', p_qty,
                                         'unit_price', (SELECT sale_price FROM products WHERE id = p_prod),
                                         'vat_rate', 20)));
  RETURN k.id;
END $$;

-- Les liens d'un document, avec l'état et le tour (le même outillage que la 320).
DROP FUNCTION IF EXISTS _l322_liens(uuid, text, uuid);
CREATE OR REPLACE FUNCTION _l322_liens(p_t uuid, p_amont_type text, p_amont_id uuid)
RETURNS TABLE(effet text, aval_type text, aval_id uuid, link_type text, payload jsonb,
              etat text, tour integer, motif text)
LANGUAGE sql AS $$
  SELECT dl.effet, dl.aval_type, dl.aval_id, dl.link_type, dl.payload, dl.etat, dl.tour, dl.motif
  FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = p_amont_type AND dl.amont_id = p_amont_id
  ORDER BY dl.effet, dl.tour
$$;

-- ═════════════════════════════════════════════════════════════
-- T01 / T02 — Encaissement : deux liens, deux traces, des avals exacts
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; k uuid; n_liens int; n_stock int; n_pay int; n_applique int; n_evt int;
        v_stock record; v_pay record; p_stock jsonb; ok_aval boolean;
BEGIN
  v := _l322_caisse('R322A');
  PERFORM _as_user();
  k := _l322_ticket(v.sess, v.prod, 3);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO n_liens FROM _l322_liens(v.t, 'pos_tickets', k);
  SELECT count(*) INTO n_applique FROM chain_traces
   WHERE tenant_id = v.t AND amont_id = k AND resultat = 'applique';
  SELECT count(*) INTO n_evt FROM domain_events
   WHERE tenant_id = v.t AND aggregate_id = k AND event_name = 'pos_tickets.created';

  PERFORM _rec('T01',
    'encaissement : DEUX liens (stock_out, payment) et DEUX traces `applique`, un événement pos_tickets.created — le maillon est PILOTÉ, pas seulement exécuté',
    n_liens = 2 AND n_applique = 2 AND n_evt = 1,
    format('liens=%s (2 attendus) traces applique=%s (2 attendues) événements=%s', n_liens, n_applique, n_evt));

  -- T02 : les AVALS sont exacts, et le payload porte ce que le lien ne peut pas.
  SELECT * INTO v_stock FROM _l322_liens(v.t, 'pos_tickets', k)
   WHERE effet = 'pos.ticket.stock_out';
  SELECT * INTO v_pay FROM _l322_liens(v.t, 'pos_tickets', k)
   WHERE effet = 'pos.ticket.payment';
  p_stock := v_stock.payload;
  SELECT count(*) INTO n_stock FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'pos_ticket' AND reference_id = k
     AND id = v_stock.aval_id AND movement_type = 'out';
  SELECT count(*) INTO n_pay FROM pos_payments
   WHERE tenant_id = v.t AND ticket_id = k AND id = v_pay.aval_id;
  ok_aval := (p_stock -> 'mouvements') = to_jsonb(n_stock)
             AND jsonb_array_length(COALESCE(p_stock -> 'ids', '[]'::jsonb)) >= 1;

  PERFORM _rec('T02',
    'les avals sont EXACTS : le lien stock_out désigne une sortie `out` du ticket (payload : identifiants et décompte — l''agrégation par produit est dite, pas cachée), le lien payment désigne un pos_payments du ticket (`paid_by`)',
    v_stock.link_type = 'delivered_by' AND v_pay.link_type = 'paid_by'
      AND n_stock = 1 AND n_pay = 1 AND ok_aval,
    format('stock_out → %s (mouvements out de ce ticket=%s, payload=%s) | payment → %s (paiements=%s)',
           v_stock.aval_type, n_stock, p_stock, v_pay.aval_type, n_pay));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — Le cas ordinaire ne se trace pas : un ticket de services
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; k uuid; n_liens int; n_traces int; n_pay int;
BEGIN
  v := _l322_caisse('R322B');
  PERFORM _as_user();
  k := _l322_ticket(v.sess, v.serv, 1);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO n_liens FROM _l322_liens(v.t, 'pos_tickets', k)
   WHERE effet = 'pos.ticket.stock_out';
  SELECT count(*) INTO n_traces FROM chain_traces
   WHERE tenant_id = v.t AND amont_id = k AND effet = 'pos.ticket.stock_out';
  SELECT count(*) INTO n_pay FROM _l322_liens(v.t, 'pos_tickets', k)
   WHERE effet = 'pos.ticket.payment';

  PERFORM _rec('T03',
    'un ticket de SERVICES ne sort rien : aucun lien ni trace stock_out (le cas ordinaire ne se trace pas — retenue de la 316, `sans_effet` est réservé à l''anomalie) ; le paiement, lui, est tracé',
    n_liens = 0 AND n_traces = 0 AND n_pay = 1,
    format('liens stock_out=%s traces stock_out=%s liens payment=%s', n_liens, n_traces, n_pay));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — L'avoir de caisse : l'aval propre, la rentrée, ET la fermeture (320)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; k uuid; av uuid; l_av record; l_in record; l_out record; l_pay record;
        n_applique int; n_evt int; n_rentrees int; ok_ids boolean;
BEGIN
  v := _l322_caisse('R322C');
  PERFORM _as_user();
  k := _l322_ticket(v.sess, v.prod, 3, v.cli);
  -- La session se clôt : l'avoir est la seule voie (250), et le client est
  -- nominatif (255) — le décor du ticket vendu et comptabilisé.
  UPDATE pos_sessions SET status = 'closed', closing_amount = 136, closed_at = now() WHERE id = v.sess;
  av := pos_refund_ticket(k, 'Retour client');
  PERFORM set_config('role', 'none', true);

  SELECT * INTO l_av FROM _l322_liens(v.t, 'pos_tickets', k) WHERE effet = 'pos.ticket.refunded';
  SELECT * INTO l_in FROM _l322_liens(v.t, 'pos_tickets', k) WHERE effet = 'pos.ticket.stock_in';
  SELECT * INTO l_out FROM _l322_liens(v.t, 'pos_tickets', k) WHERE effet = 'pos.ticket.stock_out';
  SELECT * INTO l_pay FROM _l322_liens(v.t, 'pos_tickets', k) WHERE effet = 'pos.ticket.payment';

  SELECT count(*) INTO n_applique FROM chain_traces
   WHERE tenant_id = v.t AND amont_id = k AND effet IN ('pos.ticket.refunded', 'pos.ticket.stock_in')
     AND resultat = 'applique';
  SELECT count(*) INTO n_evt FROM domain_events
   WHERE tenant_id = v.t AND aggregate_id = k AND event_name = 'pos_tickets.refunded';
  SELECT count(*) INTO n_rentrees FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'pos_refund' AND reference_id = av
     AND id = l_in.aval_id AND movement_type = 'in';
  ok_ids := (l_in.payload -> 'mouvements') IS NOT NULL;

  PERFORM _rec('T04',
    'l''avoir : le ticket est LIÉ à sa pièce (`adjusted_by`, l''écriture de l''avoir restant tracée par le compagnon de la 310) et à ses rentrées de stock ; le lien de la sortie d''origine est ROMPU, motivé ; le lien du PAIEMENT reste ACTIF (limite de la 255 : le décaissement n''est pas écrit par l''avoir)',
    l_av.aval_type = 'credit_notes' AND l_av.aval_id = av AND l_av.link_type = 'adjusted_by'
      AND l_in.aval_type = 'stock_movements' AND n_rentrees = 1
      AND l_out.etat = 'rompu' AND l_out.motif LIKE '%rendu%'
      AND l_pay.etat = 'actif'
      AND n_applique = 2 AND n_evt = 1,
    format('avoir → %s %s (type %s) | rentrées=%s (aval %s) | stock_out : %s « %s » | payment : %s | traces applique=%s événements=%s',
           l_av.aval_type, left(l_av.aval_id::text, 8), l_av.link_type, n_rentrees, l_in.aval_type,
           l_out.etat, left(COALESCE(l_out.motif, '—'), 40), l_pay.etat, n_applique, n_evt));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — L'annulation (session ouverte) : la fermeture, sans aucune trace
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; k uuid; l_out record; l_pay record; n_traces int; n_rentrees int; n_evt int;
BEGIN
  v := _l322_caisse('R322D');
  PERFORM _as_user();
  k := _l322_ticket(v.sess, v.prod, 2);
  PERFORM void_pos_ticket(k, 'Erreur de saisie');
  PERFORM set_config('role', 'none', true);

  SELECT * INTO l_out FROM _l322_liens(v.t, 'pos_tickets', k) WHERE effet = 'pos.ticket.stock_out';
  SELECT * INTO l_pay FROM _l322_liens(v.t, 'pos_tickets', k) WHERE effet = 'pos.ticket.payment';
  SELECT count(*) INTO n_traces FROM chain_traces
   WHERE tenant_id = v.t AND amont_id = k AND resultat = 'applique';
  SELECT count(*) INTO n_rentrees FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'pos_ticket_void' AND reference_id = k;
  SELECT count(*) INTO n_evt FROM domain_events
   WHERE tenant_id = v.t AND event_name = 'chain.link_broken' AND aggregate_id = k;

  PERFORM _rec('T05',
    'l''annulation d''un ticket sur session OUVERTE rend le stock : le lien stock_out est ROMPU (motif nominatif), la fermeture n''écrit AUCUNE trace (doctrine 312 : son journal est l''événement chain.link_broken, écrit), et le paiement reste ACTIF',
    l_out.etat = 'rompu' AND l_out.motif LIKE '%annulé%' AND l_pay.etat = 'actif'
      AND n_traces = 2 AND n_rentrees = 1 AND n_evt = 1,
    format('stock_out : %s « %s » | payment : %s | traces applique (création seule)=%s rentres miroir=%s événements de fermeture=%s',
           l_out.etat, left(COALESCE(l_out.motif, '—'), 40), l_pay.etat, n_traces, n_rentrees, n_evt));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — Mode refuse + effet éteint : l'appel lève, et RIEN ne persiste
--   L'entrée est posée dans le chemin d'appel APRÈS le corps (intact) — et
--   c'est la TRANSACTION de l'appel qui rend le refus équivalent : l'exception
--   annule tout ce que le corps vient d'écrire. La limite de la 252 §5 reste
--   vraie : la trace `refuse` elle-même ne survit pas au rollback.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; k uuid := NULL; refuse boolean := false; msg text := '—';
        n_tk int; n_mv int; n_pay int; n_lignes int; n_liens int; n_evt int;
BEGIN
  v := _l322_caisse('R322E');
  -- L'effet est ÉTEINT pour cette société, et elle demande le mode `refuse`.
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  VALUES (v.t, 'pos_tickets', 'created', 'pos.ticket.stock_out', false);
  PERFORM chain_set_enforcement(v.t, 'refuse');

  PERFORM _as_user();
  BEGIN
    k := _l322_ticket(v.sess, v.prod, 3);
  EXCEPTION WHEN OTHERS THEN
    refuse := true; msg := SQLERRM;
  END;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO n_tk FROM pos_tickets WHERE tenant_id = v.t;
  SELECT count(*) INTO n_mv FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'pos_ticket';
  SELECT count(*) INTO n_pay FROM pos_payments WHERE tenant_id = v.t;
  SELECT count(*) INTO n_lignes FROM pos_ticket_lines WHERE tenant_id = v.t;
  SELECT count(*) INTO n_liens FROM document_links WHERE tenant_id = v.t AND amont_type = 'pos_tickets';
  SELECT count(*) INTO n_evt FROM domain_events WHERE tenant_id = v.t AND event_name = 'pos_tickets.created';

  PERFORM _rec('T06',
    'mode refuse + effet éteint : l''appel LÈVE (message nominatif) et RIEN ne persiste — ni ticket, ni ligne, ni paiement, ni mouvement, ni lien, ni événement. La transaction de l''appel RPC est le mur, et le corps intact n''y échappe pas',
    refuse AND n_tk = 0 AND n_mv = 0 AND n_pay = 0 AND n_lignes = 0 AND n_liens = 0 AND n_evt = 0
      AND k IS NULL,
    format('refus=%s (k=%s) tickets=%s lignes=%s paiements=%s mouvements=%s liens=%s événements=%s | %s',
           refuse, k, n_tk, n_lignes, n_pay, n_mv, n_liens, n_evt, left(msg, 60)));
END $$;
-- ═════════════════════════════════════════════════════════════
-- T07 — La STRUCTURE : trois corps `_inner` DERRIÈRE trois wrappers
--   Une PROPRIÉTÉ, pas un compte (leçon R-17) : ce qui doit tenir demain,
--   c'est qu'un `authenticated` ne puisse appeler QUE le wrapper — le corps
--   renommé ne porte plus de droits, et c'est lui qui tisse la chaîne. Les
--   deux moitiés ne peuvent être séparées : sans le wrapper, pas de maillon ;
--   sans les droits, pas de wrapper utilisable.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_inner int; n_wrappers_sd int; n_wrappers_exec int; n_inner_exec int;
        n_contrats int; n_contrats_actifs int; detail_contrats text;
BEGIN
  -- a) les trois corps renommés existent et ne sont exposés à PERSONNE.
  SELECT count(*) INTO n_inner
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public' AND p.proname IN ('create_pos_ticket_inner',
                                                 'pos_refund_ticket_inner',
                                                 'void_pos_ticket_inner');

  -- `PUBLIC` n'est pas un rôle de catalogue : le test du pseudo-rôle se fait
  -- par `aclexplode`, qui lit le TRUE de `proacl` — c'est ce droit par défaut
  -- qu'un `REVOKE … FROM PUBLIC` efface, et qu'il faut donc vérifier à part.
  SELECT count(*) INTO n_inner_exec
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public' AND p.proname IN ('create_pos_ticket_inner',
                                                 'pos_refund_ticket_inner',
                                                 'void_pos_ticket_inner')
     AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          OR has_function_privilege('anon', p.oid, 'EXECUTE')
          OR EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner)))
                      WHERE grantee = 0 AND privilege_type = 'EXECUTE'));

  -- b) les trois wrappers sont SECURITY DEFINER…
  SELECT count(*) INTO n_wrappers_sd
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public' AND p.prosecdef
     AND p.proname IN ('create_pos_ticket', 'pos_refund_ticket', 'void_pos_ticket');

  -- …et le SEUL chemin ouvert à `authenticated`.
  SELECT count(*) INTO n_wrappers_exec
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public'
     AND p.proname IN ('create_pos_ticket', 'pos_refund_ticket', 'void_pos_ticket')
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

  -- c) les quatre contrats sont DÉCLARÉS et ACTIFS (la porte G2 de la 313).
  SELECT count(*) FILTER (WHERE actif), count(*)
    INTO n_contrats_actifs, n_contrats
    FROM document_effects
   WHERE tenant_id IS NULL AND document_type = 'pos_tickets'
     AND effet IN ('pos.ticket.stock_out', 'pos.ticket.payment',
                   'pos.ticket.refunded', 'pos.ticket.stock_in');

  SELECT string_agg(effet || '=' || actif::text, ', ' ORDER BY effet)
    INTO detail_contrats
    FROM document_effects
   WHERE tenant_id IS NULL AND document_type = 'pos_tickets'
     AND effet IN ('pos.ticket.stock_out', 'pos.ticket.payment',
                   'pos.ticket.refunded', 'pos.ticket.stock_in');

PERFORM _rec('T07',
    'STRUCTURE : les trois corps `_inner` existent et ne sont exécutables par PERSONNE (authenticated, anon, PUBLIC) ; les trois wrappers sont SECURITY DEFINER et restent le seul chemin de `authenticated` ; les quatre contrats d''effet sont déclarés et actifs',
    n_inner = 3 AND n_inner_exec = 0
      AND n_wrappers_sd = 3 AND n_wrappers_exec = 3
      AND n_contrats = 4 AND n_contrats_actifs = 4,
    format('corps _inner=%s (exposés à un rôle public : %s) | wrappers SECURITY DEFINER=%s, exécutables par authenticated=%s | contrats=%s dont actifs=%s (%s)',
           n_inner, n_inner_exec, n_wrappers_sd, n_wrappers_exec,
           n_contrats, n_contrats_actifs, detail_contrats));
END $$;
-- ═════════════════════════════════════════════════════════════
-- T08 — Le CLOISONNEMENT : la caisse de A n'existe pas pour B
--   Le contrôle POSITIF est ce qui distingue ce scénario d'un « rien à voir » :
--   B voit ses propres liens (2) — sans quoi « 0 lien de A vu par B » ne
--   prouverait strictement rien.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE va record; vb record; ka uuid; kb uuid; ua uuid; ub uuid;
        n_liens_a int; n_tr_a int; n_ev_a int;
        n_liens_voisin int; n_tr_voisin int; n_ev_voisin int; n_liens_b int;
BEGIN
  va := _l322_caisse('R322F');
  vb := _l322_caisse('R322G');

  SELECT auth_id INTO ua FROM tenant_users WHERE tenant_id = va.t AND status = 'active' LIMIT 1;
  SELECT auth_id INTO ub FROM tenant_users WHERE tenant_id = vb.t AND status = 'active' LIMIT 1;
  IF ua IS NULL OR ub IS NULL THEN
    RAISE EXCEPTION 'Contexte de société non établi — le scénario ne prouverait rien';
  END IF;

  -- A encaisse : le contexte doit être celui de A, sinon le wrapper SECURITY
  -- DEFINER ne verrait pas la session et le scénario mesurerait… rien (leçon
  -- de la 320 : « A rompus=0 », un contexte resté sur B — un faux vert muet).
  PERFORM set_config('request.jwt.claim.sub', ua::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', va.t::text, false);
  PERFORM _as_user();
  ka := _l322_ticket(va.sess, va.prod, 2);

  SELECT count(*) INTO n_liens_a FROM _l322_liens(va.t, 'pos_tickets', ka);
  SELECT count(*) INTO n_tr_a   FROM chain_traces WHERE tenant_id = va.t AND amont_id = ka;
  SELECT count(*) INTO n_ev_a   FROM domain_events WHERE tenant_id = va.t AND aggregate_id = ka;

  -- B encaisse le sien, puis se connecte : elle voit SON ticket, pas celui de A.
  PERFORM set_config('request.jwt.claim.sub', ub::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', vb.t::text, false);
  PERFORM _as_user();
  kb := _l322_ticket(vb.sess, vb.prod, 1);

  -- Le contrôle POSITIF : B a bien ses deux liens.
  SELECT count(*) INTO n_liens_b FROM _l322_liens(vb.t, 'pos_tickets', kb);

  SELECT count(*) INTO n_liens_voisin FROM document_links WHERE amont_id = ka;
  SELECT count(*) INTO n_tr_voisin   FROM chain_traces  WHERE tenant_id = va.t AND amont_id = ka;
  SELECT count(*) INTO n_ev_voisin   FROM domain_events WHERE tenant_id = va.t AND aggregate_id = ka;
  PERFORM set_config('role', 'none', true);

  PERFORM _rec('T08',
    'le CLOISONNEMENT de la caisse : A encaisse 2 liens et ses traces, B encaisse les SIENS (contrôle positif) et ne voit ni les liens, ni les traces, ni les événements du ticket de A',
    n_liens_a = 2 AND n_tr_a >= 2 AND n_ev_a = 1
      AND n_liens_b = 2
      AND n_liens_voisin = 0 AND n_tr_voisin = 0 AND n_ev_voisin = 0,
    format('A : liens=%s traces=%s événements=%s | B : ses propres liens=%s (contrôle positif) | vus par B depuis A : liens=%s traces=%s événements=%s',
           n_liens_a, n_tr_a, n_ev_a, n_liens_b,
           n_liens_voisin, n_tr_voisin, n_ev_voisin));
END $$;

-- Cette suite doit RÉPONDRE à la CI. Elle enregistrait ses verdicts sous la
-- clé `322` — qui n'est le fichier d'aucune suite — et n'appelait jamais
-- `_audit_assert` : un scénario rouge y était donc indifférente, sans jamais
-- faire échouer quoi que ce soit. C'est exactement la façon dont la CI affiche
-- du vert sur du vide. Elle répond maintenant sous SON fichier, `412`.
SELECT _audit_assert('412');