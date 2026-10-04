-- ============================================================
-- 252_chain_socle_tests.sql — L0 : ce que le socle des chaînages garantit
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md, lot L0 (§3, §4).
-- Le référentiel a mesuré, sur les 62 chaînages existants : idempotence 15 %,
-- trace 11 %, note moyenne 3,65/7. Ce fichier mesure les propriétés que le socle
-- doit apporter à TOUS, et les propriétés qu'il ne doit PAS laisser passer :
--
--   T01  les six tables sont là, RLS activée ET forcée, UNE politique par commande ;
--   T02  link_documents est idempotent et FUSIONNE le payload au rejeu ;
--   T03  une société absente ou un effet vide sont refusés, avec un message ;
--   T04  chain_deja_fait / chain_integrity_ok distinguent le lien posé du lien rompu ;
--   T05  la société voisine ne voit RIEN et ne peut RIEN écrire en direct ;
--   T06  chain_autorise : contrat standard lu par tous, ligne de société prioritaire,
--        effet éteint (`actif = false`) rendu faux, rien de déclaré = faux ;
--   T07  mode `observe` (défaut) : un effet non déclaré s'applique et se trace `tolere` ;
--   T08  mode `refuse` : l'effet non déclaré est bloqué, le message nomme document,
--        règle, module et date, et la trace dit `refuse` ;
--   T09  mode `avertit` : l'effet s'applique, un avertissement est émis, la trace dit `tolere` ;
--   T10  le gabarit est idempotent : un second passage rend false et trace `ignore` ;
--   T11  chain_apres mesure une durée réelle et refuse une trace sans début ;
--   T12  chain_trace refuse une société absente et une durée négative ;
--   T13  chain_regenerate refuse ce qui n'a jamais été appliqué, journalise
--        avant/après et émet chain.regenerated ;
--   T14  les événements vont dans une partition MENSUELLE (jamais dans le défaut),
--        et aucune partition n'est lisible en direct par `authenticated` ;
--   T15  chain_set_enforcement : société active seulement, mode inconnu refusé,
--        mode changé et relu, événement émis ;
--   T16  chain_ensure_partitions est idempotent, et REFUSE de rattacher une
--        partition dont les lignes sont déjà dans la partition par défaut.
--
-- Mesuré AVANT la 252 : aucune de ces tables n'existait (grep sur le dépôt :
-- zéro occurrence de document_links, chain_traces, link_documents, domain_events,
-- document_effects) — les seize scénarios sont donc les premiers à les décrire.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '252', false);
DELETE FROM _audit_results WHERE file = '252';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier
-- ─────────────────────────────────────────────────────────────

-- Un lien posé par le maillon type de ces scénarios (commande → livraison).
-- Partie 5 (450/451) : link_documents exige désormais que l'amont, l'aval et la
-- ligne amont EXISTENT. Les scénarios tirent leurs identifiants au hasard : cette
-- aide crée le vrai document (commande en brouillon, bon de livraison en attente,
-- ligne de commande) qui porte cet identifiant, s'il n'existe pas encore.
-- Société NULL ou identifiant NULL : rien n'est créé (le scénario teste justement
-- le refus de link_documents sur ces valeurs).
DROP FUNCTION IF EXISTS _p5_doc(uuid, text, uuid, uuid);
CREATE OR REPLACE FUNCTION _p5_doc(p_t uuid, p_type text, p_id uuid, p_ligne uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $p5$
BEGIN
  IF p_t IS NULL OR p_id IS NULL THEN
    RETURN;
  END IF;
  IF p_type = 'sales_orders' THEN
    INSERT INTO sales_orders (id, tenant_id, number, status)
    VALUES (p_id, p_t, 'P5-' || p_id::text, 'draft')
    ON CONFLICT (id) DO NOTHING;
    IF p_ligne IS NOT NULL THEN
      INSERT INTO sales_order_lines (id, tenant_id, sales_order_id, description, quantity, unit_price)
      VALUES (p_ligne, p_t, p_id, 'Ligne P5', 1, 0)
      ON CONFLICT (id) DO NOTHING;
    END IF;
  ELSIF p_type = 'delivery_notes' THEN
    INSERT INTO delivery_notes (id, tenant_id, number, status)
    VALUES (p_id, p_t, 'P5-' || p_id::text, 'pending')
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $p5$;

CREATE OR REPLACE FUNCTION _lien252(p_t uuid, p_amont uuid, p_aval uuid, p_effet text,
  p_payload jsonb DEFAULT '{}'::jsonb, p_ligne uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  PERFORM _p5_doc(p_t, 'sales_orders', p_amont, p_ligne);
  PERFORM _p5_doc(p_t, 'delivery_notes', p_aval);
  RETURN link_documents(p_t, 'sales_orders', p_amont, 'delivery_notes', p_aval, p_effet,
                        'delivered_by', p_payload, p_ligne, NULL);
END $$;

-- Une déclaration de contrat d'effet : société (p_t NULL = contrat standard),
-- document, événement, effet, et l'interrupteur `actif`.
CREATE OR REPLACE FUNCTION _contrat252(p_t uuid, p_doc text, p_evt text, p_effet text,
  p_actif boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  VALUES (p_t, p_doc, p_evt, p_effet, p_actif)
  ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               document_type, evenement, effet)
  DO UPDATE SET actif = EXCLUDED.actif
  RETURNING id INTO v;
  RETURN v;
END $$;

-- Les traces d'un maillon, telles que le tableau de bord des refus les lira.
CREATE OR REPLACE FUNCTION _traces252(p_t uuid, p_effet text)
RETURNS TABLE(resultat text, message text) LANGUAGE sql AS $$
  SELECT ct.resultat, ct.message FROM chain_traces ct
  WHERE ct.tenant_id = p_t AND ct.effet = p_effet ORDER BY ct.id
$$;

-- Le mode d'application, posé sans passer par la RPC (pour ne pas confondre
-- « le drapeau marche » avec « la RPC marche » — T15 mesure la RPC).
CREATE OR REPLACE FUNCTION _mode252(p_t uuid, p_mode text)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO chain_settings (tenant_id, enforcement) VALUES (p_t, p_mode)
  ON CONFLICT (tenant_id) DO UPDATE SET enforcement = EXCLUDED.enforcement, updated_at = now()
$$;

-- ═════════════════════════════════════════════════════════════
-- T01 — la structure : six tables, RLS activée et forcée, une politique par commande
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_socle int; v_doubles int; v_force int; v_index int;
BEGIN
  SELECT count(*) INTO v_socle
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('document_links', 'document_effects', 'domain_events',
                      'chain_traces', 'chain_regeneration_log', 'chain_settings')
    AND c.relkind IN ('r', 'p') AND c.relrowsecurity;

  SELECT count(*) INTO v_force
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('document_links', 'document_effects', 'domain_events',
                      'chain_traces', 'chain_regeneration_log', 'chain_settings')
    AND c.relforcerowsecurity;

  -- Deux politiques permissives sur la même (table, commande) sont OU-ées : la
  -- plus large gagne (ISO-03). Le socle ne doit pas réintroduire ce motif.
  SELECT count(*) INTO v_doubles FROM (
    SELECT p.polrelid, p.polcmd
    FROM pg_policy p
    WHERE p.polpermissive
      AND p.polrelid IN ('document_links'::regclass, 'document_effects'::regclass,
                         'domain_events'::regclass, 'chain_traces'::regclass,
                         'chain_regeneration_log'::regclass, 'chain_settings'::regclass)
    GROUP BY p.polrelid, p.polcmd HAVING count(*) > 1) d;

  -- Les index de société : toute table du socle se lit d'abord par sa société.
  SELECT count(*) INTO v_index FROM pg_index i
  WHERE i.indrelid IN ('document_links'::regclass, 'document_effects'::regclass,
                       'domain_events'::regclass, 'chain_traces'::regclass,
                       'chain_regeneration_log'::regclass, 'chain_settings'::regclass)
    AND pg_get_indexdef(i.indexrelid) LIKE '%tenant_id%';

  PERFORM _rec('T01', 'les six tables du socle : RLS activée ET forcée, une politique par commande, un index de société',
    v_socle = 6 AND v_force = 6 AND v_doubles = 0 AND v_index >= 6,
    format('RLS=%s/6, forcée=%s/6, couples (table, commande) doublés=%s, index de société=%s',
           v_socle, v_force, v_doubles, v_index));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — link_documents : idempotence structurelle, et le rejeu apporte son payload
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; v1 uuid; v2 uuid; n int; p jsonb;
BEGIN
  t := _mk_tenant('A252T02', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  v1 := _lien252(t, a, b, 'sale.delivery.stock_out', '{"qte": 10}'::jsonb);
  v2 := _lien252(t, a, b, 'sale.delivery.stock_out', '{"depot": "W1"}'::jsonb);

  SELECT count(*) INTO n FROM document_links WHERE tenant_id = t;
  SELECT dl.payload INTO p FROM document_links dl WHERE dl.id = v1;

  PERFORM _rec('T02', 'link_documents : le rejeu ne double rien et fusionne le payload (M-02)',
    n = 1 AND v1 = v2 AND p = '{"qte": 10, "depot": "W1"}'::jsonb,
    format('liens=%s (1 attendu), identifiants identiques=%s, payload=%s', n, v1 IS NOT DISTINCT FROM v2, p));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — refus explicites : société absente, effet vide, identifiant absent
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; v_ok int := 0; v_dits text[] := ARRAY[]::text[]; v_liens int;
BEGIN
  t := _mk_tenant('A252T03', false);

  BEGIN PERFORM _lien252(NULL, gen_random_uuid(), gen_random_uuid(), 'effet.test');
    v_dits := v_dits || 'société absente : acceptée'; EXCEPTION WHEN check_violation THEN
    v_ok := v_ok + 1; v_dits := v_dits || ('société absente : ' || left(SQLERRM, 60)); END;

  BEGIN PERFORM _lien252(t, gen_random_uuid(), gen_random_uuid(), '   ');
    v_dits := v_dits || 'effet vide : accepté'; EXCEPTION WHEN check_violation THEN
    v_ok := v_ok + 1; v_dits := v_dits || ('effet vide : ' || left(SQLERRM, 60)); END;

  BEGIN PERFORM _lien252(t, NULL, gen_random_uuid(), 'effet.test');
    v_dits := v_dits || 'amont absent : accepté'; EXCEPTION WHEN check_violation THEN
    v_ok := v_ok + 1; v_dits := v_dits || ('amont absent : ' || left(SQLERRM, 60)); END;

  SELECT count(*) INTO v_liens FROM document_links WHERE tenant_id = t;

  PERFORM _rec('T03', 'link_documents refuse la société absente, l''effet vide et l''identifiant manquant, en le disant',
    v_ok = 3 AND v_liens = 0,
    format('%s/3 refus explicites, %s lien(s) écrit(s) malgré le refus — %s', v_ok, v_liens, array_to_string(v_dits, ' | ')));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — chain_deja_fait / chain_integrity_ok : le lien posé, le lien rompu
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; c uuid; v_ligne uuid;
BEGIN
  t := _mk_tenant('A252T04', false);
  a := gen_random_uuid(); b := gen_random_uuid(); c := gen_random_uuid();
  v_ligne := gen_random_uuid();

  PERFORM _lien252(t, a, b, 'integrite.test', '{}'::jsonb, v_ligne);

  PERFORM _rec('T04', 'chain_deja_fait connaît la ligne, chain_integrity_ok distingue l''aval réel du voisin',
    chain_deja_fait(t, 'sales_orders', a, 'integrite.test', v_ligne)
    AND NOT chain_deja_fait(t, 'sales_orders', a, 'integrite.test', NULL)
    AND NOT chain_deja_fait(t, 'sales_orders', b, 'integrite.test', v_ligne)
    AND chain_integrity_ok(t, 'sales_orders', a, 'delivery_notes', b)
    AND NOT chain_integrity_ok(t, 'sales_orders', a, 'delivery_notes', c),
    format('ligne=oui, sans ligne=non, autre amont=non ; aval réel=oui, aval étranger=non (ligne %s)', v_ligne));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T05 — le cloisonnement : la société voisine ne voit rien, et n'écrit rien en direct
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  ta uuid; tb uuid; v_auth_ta uuid; a uuid; b uuid;
  vus int; v_vus_a int; refuse boolean := false; v_msg text;
BEGIN
  ta := _mk_tenant('A252T05a', false);
  a := gen_random_uuid(); b := gen_random_uuid();
  PERFORM _lien252(ta, a, b, 'iso.test');
  tb := _mk_tenant('A252T05b', false);        -- le contexte actif est désormais B

  SELECT tu.auth_id INTO v_auth_ta FROM tenant_users tu
   WHERE tu.tenant_id = ta AND tu.status = 'active' ORDER BY tu.auth_id LIMIT 1;

  PERFORM _as_user();                          -- comme PostgREST : rôle authenticated

  SELECT count(*) INTO vus FROM document_links;                     -- context = B
  PERFORM set_config('request.jwt.claim.sub', v_auth_ta::text, false);
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  SELECT count(*) INTO v_vus_a FROM document_links;                 -- context = A

  BEGIN
    INSERT INTO document_links (tenant_id, amont_type, amont_id, aval_type, aval_id, effet, link_type)
    VALUES (ta, 'x', gen_random_uuid(), 'y', gen_random_uuid(), 'iso.test', 'created_from');
    v_msg := 'écriture directe ACCEPTÉE';
  EXCEPTION WHEN insufficient_privilege THEN
    refuse := true; v_msg := left(SQLERRM, 80);
  END;

  PERFORM _rec('T05', 'la société B ne voit aucun lien de A, A retrouve le sien, et l''écriture directe est refusée par le privilège',
    vus = 0 AND v_vus_a = 1 AND refuse,
    format('B voit %s (0 attendu), A voit %s (1 attendu), écriture directe refusée=%s — %s',
           vus, v_vus_a, refuse, v_msg));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — le contrat d'effet : standard, priorité à la société, effet éteint
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; v_std boolean; v_tb boolean; v_off boolean; v_inconnu boolean;
BEGIN
  ta := _mk_tenant('A252T06a', false);
  tb := _mk_tenant('A252T06b', false);

  -- Contrat standard (tenant_id NULL) : lisible par toute société.
  PERFORM _contrat252(NULL, 'sales_orders', 'confirmee', 'contrat.standard', true);
  -- La société B éteint explicitement cet effet standard.
  PERFORM _contrat252(tb, 'sales_orders', 'confirmee', 'contrat.standard', false);

  v_std := chain_autorise(ta, 'sales_orders', 'confirmee', 'contrat.standard');
  v_tb  := chain_autorise(tb, 'sales_orders', 'confirmee', 'contrat.standard');
  v_off := chain_autorise(tb, 'sales_orders', 'confirmee', 'jamais.declare');
  v_inconnu := chain_autorise(ta, 'document.inconnu', 'peu.importe', 'contrat.standard');

  PERFORM _rec('T06', 'chain_autorise : standard lu par tous, la ligne de société l''emporte (même pour éteindre), rien de déclaré = faux',
    v_std AND NOT v_tb AND NOT v_off AND NOT v_inconnu,
    format('standard pour A=%s, éteint pour B=%s (false attendu), effet jamais déclaré=%s, document inconnu=%s',
           v_std, v_tb, v_off, v_inconnu));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T07 — mode `observe` (défaut) : l'effet non déclaré s'applique et se trace
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; v_continue boolean; v_trace record;
BEGIN
  t := _mk_tenant('A252T07', false);
  a := gen_random_uuid();

  v_continue := chain_avant(t, 'sales_orders', 'confirmee', 'effet.non.declare', 'sales_orders', a);
  SELECT * INTO v_trace FROM _traces252(t, 'effet.non.declare') LIMIT 1;

  PERFORM _rec('T07', 'mode observe (défaut) : un effet non déclaré s''applique et se trace `tolere`',
    v_continue AND chain_enforcement_mode(t) = 'observe' AND v_trace.resultat = 'tolere',
    format('continue=%s, mode=%s, trace=%s — %s', v_continue, chain_enforcement_mode(t),
           v_trace.resultat, left(COALESCE(v_trace.message, ''), 150)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — mode `refuse` : le message nomme document, règle, module et date
--
-- La trace du refus est écrite AVANT l'exception : elle ne survit donc pas au
-- rollback de l'opération refusée (limite transactionnelle de PostgreSQL, dite
-- dans l'en-tête de la 252). Ce scénario mesure les deux faits : le refus est
-- nominatif, et la trace ne survit pas quand l'appelant rattrape l'erreur.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; v_msg text; v_leve boolean := false; v_traces int;
BEGIN
  t := _mk_tenant('A252T08', false);
  a := gen_random_uuid();
  PERFORM _mode252(t, 'refuse');

  BEGIN
    PERFORM chain_avant(t, 'sales_orders', 'confirmee', 'effet.non.declare', 'sales_orders', a, NULL,
      'Commande C-2026-0007 du 24/09/2026 : l''écriture de vente est obligatoire (règle sale.ledger.entry) — module commercial.');
  EXCEPTION WHEN check_violation THEN
    v_leve := true; v_msg := SQLERRM;
  END;

  SELECT count(*) INTO v_traces FROM _traces252(t, 'effet.non.declare');

  PERFORM _rec('T08', 'mode refuse : l''effet non déclaré est bloqué avec un message qui nomme document, date, règle et module',
    v_leve
    AND v_msg LIKE '%Commande C-2026-0007 du 24/09/2026%'
    AND v_msg LIKE '%sale.ledger.entry%'
    AND v_msg LIKE '%module commercial%',
    format('levé=%s, trace survivante=%s (0 : elle est écrite avant l''exception, donc annulée par le rollback) — %s',
           v_leve, v_traces, left(COALESCE(v_msg, 'aucun message'), 160)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T09 — mode `avertit` : l'effet s'applique, l'avertissement est émis
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; v_continue boolean; v_trace record;
BEGIN
  t := _mk_tenant('A252T09', false);
  a := gen_random_uuid();
  PERFORM _mode252(t, 'avertit');

  v_continue := chain_avant(t, 'sales_orders', 'confirmee', 'effet.non.declare', 'sales_orders', a);
  SELECT * INTO v_trace FROM _traces252(t, 'effet.non.declare') LIMIT 1;

  PERFORM _rec('T09', 'mode avertit : l''effet non déclaré s''applique, la trace dit tolere et porte le mode',
    v_continue AND v_trace.resultat = 'tolere' AND v_trace.message LIKE '%mode avertit%',
    format('continue=%s, trace=%s, message dit le mode=%s — %s', v_continue, v_trace.resultat,
           v_trace.message LIKE '%mode avertit%', left(COALESCE(v_trace.message, ''), 150)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T10 — le gabarit est idempotent : le second passage rend false et trace `ignore`
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; v1 boolean; v2 boolean; v_trace record;
BEGIN
  t := _mk_tenant('A252T10', false);
  a := gen_random_uuid(); b := gen_random_uuid();
  PERFORM _contrat252(t, 'sales_orders', 'confirmee', 'gabarit.test', true);

  v1 := chain_avant(t, 'sales_orders', 'confirmee', 'gabarit.test', 'sales_orders', a);
  PERFORM _lien252(t, a, b, 'gabarit.test');                 -- l'effet est produit
  PERFORM chain_apres(t, 'gabarit.test', 'sales_orders', a, clock_timestamp(), 1, 'applique', NULL);

  v2 := chain_avant(t, 'sales_orders', 'confirmee', 'gabarit.test', 'sales_orders', a);
  SELECT * INTO v_trace FROM chain_traces ct
   WHERE ct.tenant_id = t AND ct.effet = 'gabarit.test' AND ct.resultat = 'ignore' ORDER BY ct.id LIMIT 1;

  PERFORM _rec('T10', 'le gabarit ne rejoue pas : premier passage vrai, second faux, trace `ignore`',
    v1 AND NOT v2 AND v_trace.resultat = 'ignore' AND chain_deja_fait(t, 'sales_orders', a, 'gabarit.test'),
    format('premier=%s, second=%s, trace ignore=%s', v1, v2, COALESCE(v_trace.resultat, 'absente')));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T11 — chain_apres : la durée est mesurée, une trace sans début est refusée
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; v_duree int; v_lignes int; v_res text; v_refus boolean := false;
BEGIN
  t := _mk_tenant('A252T11', false);
  a := gen_random_uuid();

  v_duree := chain_apres(t, 'mesure.test', 'sales_orders', a, clock_timestamp(), 3, 'applique', 'trois lignes');

  SELECT ct.lignes_ecrites, ct.resultat INTO v_lignes, v_res
  FROM chain_traces ct WHERE ct.tenant_id = t AND ct.effet = 'mesure.test' ORDER BY ct.id LIMIT 1;

  BEGIN PERFORM chain_apres(t, 'mesure.test', 'sales_orders', a, NULL);
  EXCEPTION WHEN check_violation THEN v_refus := true; END;

  PERFORM _rec('T11', 'chain_apres écrit la trace (durée, lignes, résultat) et refuse une trace sans instant de début',
    v_duree >= 0 AND v_lignes = 3 AND v_res = 'applique' AND v_refus,
    format('durée rendue=%s ms, lignes=%s, résultat=%s, trace sans début refusée=%s', v_duree, v_lignes, v_res, v_refus));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T12 — chain_trace : société absente, durée négative, résultat hors vocabulaire
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; v_ok int := 0; v_dits text := '';
BEGIN
  t := _mk_tenant('A252T12', false);
  a := gen_random_uuid();

  BEGIN PERFORM chain_trace(NULL, 'x.test', 'sales_orders', a, 0, 0, NULL, 'applique', NULL);
  EXCEPTION WHEN check_violation THEN v_ok := v_ok + 1; v_dits := v_dits || 'société : ' || left(SQLERRM, 40) || ' ; '; END;

  BEGIN PERFORM chain_trace(t, 'x.test', 'sales_orders', a, -1, 0, NULL, 'applique', NULL);
  EXCEPTION WHEN check_violation THEN v_ok := v_ok + 1; v_dits := v_dits || 'durée : ' || left(SQLERRM, 50) || ' ; '; END;

  BEGIN PERFORM chain_trace(t, 'x.test', 'sales_orders', a, 0, 0, NULL, 'hors.vocabulaire', NULL);
  EXCEPTION WHEN check_violation THEN v_ok := v_ok + 1; v_dits := v_dits || 'résultat : contrainte ; '; END;

  PERFORM _rec('T12', 'chain_trace refuse une société absente, une durée négative et un résultat hors vocabulaire',
    v_ok = 3, format('%s/3 refus — %s', v_ok, left(v_dits, 220)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T13 — chain_regenerate : rien à régénérer sans lien, sinon historique + événement
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  t uuid; a uuid; b uuid; v_log bigint; v_refus boolean := false; v_msg text;
  v_avant jsonb; v_apres jsonb; v_cause text; v_evt int;
BEGIN
  t := _mk_tenant('A252T13', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  BEGIN PERFORM chain_regenerate(t, 'jamais.applique', 'sales_orders', a, 'test');
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  PERFORM _lien252(t, a, b, 'regen.test', '{"prix": 10}'::jsonb);
  v_log := chain_regenerate(t, 'regen.test', 'sales_orders', a, 'prix de revient corrigé', '{"prix": 12}'::jsonb);

  SELECT crl.avant, crl.apres, crl.cause INTO v_avant, v_apres, v_cause
  FROM chain_regeneration_log crl WHERE crl.id = v_log;

  SELECT count(*) INTO v_evt FROM domain_events de
   WHERE de.tenant_id = t AND de.event_name = 'chain.regenerated';

  PERFORM _rec('T13', 'chain_regenerate refuse ce qui n''a jamais été appliqué, et journalise le changement avec son événement',
    v_refus AND v_msg LIKE '%aucun lien%' AND v_avant = '[{"prix": 10}]'::jsonb
    AND v_apres = '{"prix": 12}'::jsonb AND v_cause = 'prix de revient corrigé' AND v_evt = 1,
    format('refus=%s (%s), historique avant=%s après=%s cause=%s, événements chain.regenerated=%s',
           v_refus, left(COALESCE(v_msg, ''), 60), v_avant, v_apres, v_cause, v_evt));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T14 — les événements vont dans une partition mensuelle, et aucune partition
--       n'est lisible en direct (la politique du parent ne s'y applique pas)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  t uuid; a uuid; v_id bigint; v_part text; v_parts int; v_ouverts int; v_n int;
  v_marquees int; v_rattachees int; v_parent_marque boolean;
BEGIN
  t := _mk_tenant('A252T14', false);
  a := gen_random_uuid();

  v_id := emit_domain_event(t, 'commande.confirmee', 'sales_orders', a, '{"total": 1200}'::jsonb, NULL);

  SELECT c.relname INTO v_part
  FROM domain_events de JOIN pg_class c ON c.oid = de.tableoid
  WHERE de.tenant_id = t AND de.id = v_id;

  SELECT count(*) INTO v_parts FROM pg_inherits i WHERE i.inhparent = 'domain_events'::regclass;

  SELECT count(*) INTO v_ouverts FROM (
    SELECT c.oid FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_inherits i ON i.inhrelid = c.oid
    WHERE n.nspname = 'public' AND i.inhparent = 'domain_events'::regclass
      AND has_table_privilege('authenticated', c.oid, 'SELECT')) x;

  -- Les contrôles permanents (105 isolation, 238 cloison sans politique)
  -- énumèrent les cloisons et écartent les partitions (`relispartition`) :
  -- l'exclusion n'est une preuve que si PostgreSQL MARQUE bien chaque partition
  -- comme telle et si le parent ne l'est pas. Mesuré ici, pour que la règle
  -- des deux contrôles repose sur un fait et non sur une convention.
  SELECT count(*) FILTER (WHERE c.relispartition), count(*)
    INTO v_marquees, v_rattachees
  FROM pg_class c JOIN pg_inherits i ON i.inhrelid = c.oid
  WHERE i.inhparent IN ('domain_events'::regclass, 'chain_traces'::regclass);

  SELECT c.relispartition INTO v_parent_marque FROM pg_class c WHERE c.oid = 'domain_events'::regclass;

  PERFORM _as_user();                                    -- comme PostgREST
  SELECT count(*) INTO v_n FROM domain_events WHERE id = v_id;

  PERFORM _rec('T14', 'l''événement naît dans une partition mensuelle, le parent le rend à sa société, aucune partition n''est ouverte en direct',
    v_part <> 'domain_events_defaut' AND v_parts >= 5 AND v_ouverts = 0 AND v_n = 1
      AND v_marquees = v_rattachees AND NOT v_parent_marque,
    format('partition=%s, partitions rattachées=%s, partitions lisibles en direct par authenticated=%s (0 attendu), visible via le parent=%s, partitions marquées relispartition=%s/%s, parent marqué=%s',
           v_part, v_parts, v_ouverts, v_n, v_marquees, v_rattachees, v_parent_marque));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T15 — chain_set_enforcement : la société active seulement, avec droit
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  ta uuid; tb uuid; v_voisin boolean := false; v_mode_inconnu boolean := false;
  v_retour text; v_relu text; v_evt int;
BEGIN
  ta := _mk_tenant('A252T15a', false);
  tb := _mk_tenant('A252T15b', false);              -- la société active est B

  BEGIN PERFORM chain_set_enforcement(ta, 'refuse');
  EXCEPTION WHEN insufficient_privilege THEN v_voisin := true; END;

  BEGIN PERFORM chain_set_enforcement(tb, 'peut.etre');
  EXCEPTION WHEN invalid_parameter_value THEN v_mode_inconnu := true; END;

  v_retour := chain_set_enforcement(tb, 'refuse');
  v_relu := chain_enforcement_mode(tb);

  SELECT count(*) INTO v_evt FROM domain_events de
   WHERE de.tenant_id = tb AND de.event_name = 'chain.enforcement_changed';

  PERFORM _rec('T15', 'chain_set_enforcement refuse la société voisine et un mode inconnu, change le mode de la société active et l''événement est émis',
    v_voisin AND v_mode_inconnu AND v_retour = 'refuse' AND v_relu = 'refuse' AND v_evt = 1,
    format('refus du voisin=%s, refus du mode inconnu=%s, retour=%s, mode relu=%s, événements=%s',
           v_voisin, v_mode_inconnu, v_retour, v_relu, v_evt));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T16 — chain_ensure_partitions : idempotent, et refuse de recouvrir le défaut
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  t uuid; a uuid; v_deja int; v_refus boolean := false; v_msg text; v_cree int;
  v_mois timestamptz; v_nom text; v_ecart int;
BEGIN
  t := _mk_tenant('A252T16', false);
  a := gen_random_uuid();

  v_deja := chain_ensure_partitions(3);             -- la migration les a créées

  -- La fixture est le PREMIER mois sans partition : la suite reste rejouable
  -- (elle ne dépend pas de l'état laissé par l'exécution précédente).
  SELECT min(m.d) INTO v_mois
  FROM (SELECT date_trunc('month', now()) + make_interval(months => g) AS d
        FROM generate_series(0, 24) g) m
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relname = 'domain_events_' || to_char(m.d, 'YYYY_MM'));

  v_ecart := (date_part('year', v_mois) - date_part('year', date_trunc('month', now()))) * 12
             + (date_part('month', v_mois) - date_part('month', date_trunc('month', now())));
  v_nom := 'domain_events_' || to_char(v_mois, 'YYYY_MM');

  -- Une ligne dans la partition par défaut, pour ce mois resté sans partition.
  INSERT INTO domain_events (tenant_id, event_name, aggregate_type, aggregate_id, created_at)
  VALUES (t, 'partition.test', 'sales_orders', a, v_mois + interval '1 day');

  BEGIN
    PERFORM chain_ensure_partitions(v_ecart::int);
  EXCEPTION WHEN check_violation THEN
    v_refus := true; v_msg := SQLERRM;
  END;

  -- La ligne retirée, le même appel crée la partition : le refus portait bien
  -- sur les lignes restées dans le défaut, pas sur une fonction cassée.
  DELETE FROM domain_events de WHERE de.tenant_id = t AND de.event_name = 'partition.test';
  v_cree := chain_ensure_partitions(v_ecart::int);

  PERFORM _rec('T16', 'les partitions sont créées une fois, et le rattachement est refusé quand des lignes sont déjà dans la partition par défaut',
    v_deja = 0 AND v_refus AND v_msg LIKE '%' || v_nom || '%' AND v_cree = 2
      AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = v_nom),
    format('déjà créées=%s (0 attendu), refus=%s (%s), après nettoyage créées=%s dont %s',
           v_deja, v_refus, left(COALESCE(v_msg, ''), 90), v_cree, v_nom));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T17 — Le vocabulaire de trace admet `sans_effet` (migration 315)
--   La valeur qui manquait : « maillon EXÉCUTÉ, effet NON produit » — distincte
--   de `ignore`, qui dit qu'un rejeu n'a rien eu à faire. La tranche 4 (314) a
--   rencontré le cas le premier jour (une note de frais à 0 € n'écrit pas
--   d'écriture) et ses compagnons s'en tiraient en n'écrivant RIEN : honnête,
--   mais muet — le tableau de bord du lot L5 aurait compté ce maillon comme un
--   chaînage qui n'a jamais tourné.
--   Ce scénario mesure les trois choses qui comptent : la contrainte l'accepte
--   (table ET partitions), la trace se lit avec zéro ligne écrite, et elle reste
--   distinguable d'un `ignore`.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  t uuid := _mk_tenant('A252T17', false);
  v_relations int; v_avec int; v_sans int;
  v_ok boolean := false; v_refuse_ignore boolean := false;
  v_resultat text; v_lignes int;
BEGIN
  -- 1. Toutes les relations du socle portent la sixième valeur
  SELECT count(*) INTO v_relations
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relkind IN ('r', 'p')
    AND (c.relname = 'chain_traces'
         OR EXISTS (SELECT 1 FROM pg_inherits i
                    WHERE i.inhrelid = c.oid AND i.inhparent = 'chain_traces'::regclass));

  SELECT count(*) INTO v_avec FROM pg_constraint k
  WHERE k.conname = 'chain_traces_resultat_check'
    AND pg_get_constraintdef(k.oid) LIKE '%sans_effet%';
  v_sans := v_relations - v_avec;

  -- 2. Une trace `sans_effet` s'écrit et se relit, avec zéro ligne écrite
  PERFORM chain_apres(t, 'test.sans_effet', 'sales_orders', gen_random_uuid(),
                      clock_timestamp(), 0, 'sans_effet',
                      'Maillon exécuté, aucun effet produit (scénario du socle).', NULL, NULL);

  -- Le helper `_traces252` ne rend que (resultat, message) : le nombre de lignes
  -- se lit directement — le premier jet de ce scénario lisait une colonne qui
  -- n'existe pas dans son type, et l'erreur a fait SAUTER le verdict (16 verts au
  -- lieu de 17) : d'où le bloc d'exception ajouté en bas.
  SELECT count(*), max(ct.lignes_ecrites) INTO v_lignes, v_lignes
  FROM chain_traces ct
  WHERE ct.tenant_id = t AND ct.effet = 'test.sans_effet' AND ct.resultat = 'sans_effet';
  SELECT resultat INTO v_resultat FROM _traces252(t, 'test.sans_effet') LIMIT 1;
  v_ok := v_resultat = 'sans_effet' AND v_lignes = 0;

  -- 3. Une valeur INCONNUE reste refusée : la contrainte n'a pas été ouverte
  BEGIN
    PERFORM chain_apres(t, 'test.inconnu', 'sales_orders', gen_random_uuid(),
                        clock_timestamp(), 0, 'effet_impossible', NULL, NULL, NULL);
  EXCEPTION WHEN check_violation THEN
    v_refuse_ignore := true;
  END;

  PERFORM _rec('T17', 'le vocabulaire de trace admet `sans_effet` (maillon exécuté, aucun effet) sur la table ET ses partitions, se relit avec zéro ligne écrite, et refuse toujours une valeur inconnue',
    v_sans = 0 AND v_relations >= 2 AND v_ok AND v_refuse_ignore,
    format('relations=%s (toutes avec la valeur), sans la valeur=%s, trace relue=%s (%s ligne(s)), valeur inconnue refusée=%s',
           v_relations, v_sans, COALESCE(v_resultat, '—'), COALESCE(v_lignes, -1), v_refuse_ignore));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T17', 'le vocabulaire de trace admet `sans_effet` (maillon exécuté, aucun effet) sur la table ET ses partitions, se relit avec zéro ligne écrite, et refuse toujours une valeur inconnue',
    false, SQLERRM);
END $$;


-- ═════════════════════════════════════════════════════════════
-- Clôture
-- ═════════════════════════════════════════════════════════════
DROP FUNCTION _lien252(uuid, uuid, uuid, text, jsonb, uuid);
DROP FUNCTION _contrat252(uuid, text, text, text, boolean);
DROP FUNCTION _traces252(uuid, text);
DROP FUNCTION _mode252(uuid, text);

SELECT _audit_assert('252');

