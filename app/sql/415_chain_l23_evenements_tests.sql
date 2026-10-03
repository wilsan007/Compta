-- ==========================================================
-- 415_chain_l23_evenements_tests.sql — L23 (tranche 1) : LE JOURNAL
--   D'ÉVÉNEMENTS UNIFIÉ — ce que vaut la promesse « vos webhooks sont
--   branchés sur les mêmes événements » quand on l'examine
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5 Phase F,
-- lot **L23** (« journal unique + automatisations + webhooks branchés sur les
-- MÊMES événements »), et §E.5 (la règle d'urbanisme appliquée aux
-- événements). La méthode appliquée est celle de la partie 4 : les 12 points
-- de « terminé » (§4.1), les tests T-1 → T-4, les six questions de revue (§4.3).
--
-- ⚠️ MESURÉ AVANT LA 415, SUR BASE NEUVE (272 migrations, 0 erreur) —
--   c'est ce qui rend ce fichier rouge, et non une opinion :
--
--   * `domain_events` est écrit par **25** événements du socle
--     (`emit_domain_event`), et **AUCUN** ne produisait jamais de livraison :
--     il n'existait aucun pont entre le journal et la file
--     (`webhook_delivery_queue`), que l'Edge Function `outgoing-webhooks`
--     consomme pourtant par `claim_webhook_batch()`. Mesuré : **0 fonction**
--     insère dans `webhook_delivery_queue` depuis `domain_events`.
--
--   * les **deux** seules sources d'événements historiques
--     (`notify_webhook_invoice_created`, `notify_webhook_invoice_paid`)
--     écrivent dans **`webhook_delivery_logs`** avec `endpoint_id = NULL` —
--     une table que **personne ne lit pour livrer** : un client abonné à
--     `invoice.created` recevait une promesse au journal, et l'envoi ne
--     partait jamais.
--
--   * DEUX VOCABULAIRES DISJOINTS. Le catalogue `webhook_event_catalog`
--     annonce **15** événements ; le socle en produit **25**, et
--     l'intersection est de **2** (`invoice.created`, `invoice.paid`, les
--     deux seuls qui sont précisément ceux que la file ne voyait pas).
--     **13 des 15** événements annoncés n'ont **aucun producteur** — dont
--     `manufacturing_order.completed`, dont le nom réellement produit est
--     `manufacturing_orders.completed` (le singulier n'existe nulle part).
--
-- Ce que la 415 corrige : un pont UNIQUE (`domain_events` → file), les deux
-- déclencheurs historiques redirigés vers ce même pont, un catalogue qui ne
-- promet que ce qui est produit, et un refus à l'abonnement d'un événement
-- qui n'existe pas.
--
--   T01  **T-1, l'effet attendu est produit, chiffré** — le chemin RÉEL
--        (une fonction du produit → `emit_domain_event` → `domain_events` →
--        file) produit **une** livraison, avec l'URL, le secret et un
--        payload qui porte la source.
--   T02  **T-2, le rejeu ne double pas** (D1) — le pont est borné par une
--        clé unique structurelle, et un rejeu de l'action métier ne rejoue
--        pas l'événement.
--   T03  **point 4 de §4.1** — la NON-réversibilité du pont est DÉCLARÉE,
--        avec son motif : on ne laisse pas un maillon sans inverse et sans
--        le dire.
--   T04  **T-4 / D-8, l'isolation tient** — le `tenant_id` de la livraison
--        vient de l'ÉVÉNEMENT, jamais de la session.
--   T05  **§E.5, l'urbanisme appliqué aux événements** — le catalogue ne
--        promet rien qui ne soit produit, ET tout ce qui est produit est
--        catalogué. Porte **auto-entretenue** : elle relit les corps des
--        fonctions en base.
--   T06  **point 6 de §4.1, refus explicite** — s'abonner à un événement
--        hors catalogue est REFUSÉ, et le message nomme l'événement, la
--        règle et le module.
--   T07  **point 8 de §4.1, performance mesurée** — p95 du pont sur 200
--        enfilages, confronté au budget §3.3 (≤ 50 ms).
--   T08  **structure / G1** — la file est RLS activée ET **forcée** (mesuré
--        avant : `relforcerowsecurity = f`) et ne porte qu'une politique.
--
-- Les scénarios s'exécutent en superutilisateur avec le contexte de société
-- posé par `_mk_tenant` : le pont est un `SECURITY DEFINER`, et c'est sa
-- **propre** isolation (T04) qui est prouvée, non celle de la session.
-- ==========================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '415', false);
DELETE FROM _audit_results WHERE file = '415';
-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Un point de livraison réel, abonné à une liste d'événements. L'URL est
-- publique et passe `is_allowed_webhook_url` : on veut mesurer le pont,
-- pas la garde SSRF.
CREATE OR REPLACE FUNCTION _l415_endpoint(p_t uuid, p_events jsonb,
                                           p_url text DEFAULT 'https://exemple.test/hook')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
  INSERT INTO webhook_endpoints (tenant_id, name, url, secret, active, active_events)
  VALUES (p_t, 'Point ' || left(md5(random()::text), 6), p_url, 's3cr3t', true, p_events)
  RETURNING id INTO e;
  RETURN e;
END $$;

-- Les **producteurs réels**, lus dans les corps des fonctions en base. Le
-- motif est volontairement LARGE : tout littéral « mot_mot » d'une fonction
-- qui appelle `emit_domain_event` ou `chain_l23_enfiler`. C'est ce qui rend
-- T05 auto-entretenu — un événement produit demain sans ligne de catalogue
-- fait rouge ce test sans qu'on ait à le prévoir.
CREATE OR REPLACE FUNCTION _l415_producteurs()
RETURNS TABLE (evt text)
LANGUAGE sql STABLE AS $$
  -- 03/10/2026 (harmonisation) : un littéral passé à `has_permission('…')` est
  -- un DROIT (« payroll.pay »), pas un événement. La 430 en porte un dans une
  -- fonction qui émet : le motif large le prenait pour un producteur. On retire
  -- ces appels du texte lu — et eux seuls : tout autre littéral reste compté.
  SELECT DISTINCT (regexp_matches(
           regexp_replace(p.prosrc, 'has_permission\(''[^'']+''\)', '', 'g'),
           '''([a-z_]+\.[a-z_]+)''', 'g'))[1]
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname <> 'emit_domain_event'
    AND (p.prosrc ~ 'emit_domain_event\(' OR p.prosrc ~ 'chain_l23_enfiler\(')
$$;

-- Les livraisons enfilées POUR UN ÉVÉNEMENT, tous points confondus.
CREATE OR REPLACE FUNCTION _l415_livraisons(p_t uuid, p_evt text)
RETURNS TABLE (nb integer, url text, secret text, source text)
LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer, min(q.url), min(q.secret), min(q.payload ->> 'source_event_id')
  FROM webhook_delivery_queue q
  WHERE q.tenant_id = p_t AND q.event = p_evt
$$;
-- ═════════════════════════════════════════════════════════════
-- T01 — Le chemin RÉEL produit la livraison, chiffrée
--   On n'appelle pas le pont : on appelle une fonction du produit
--   (`chain_set_enforcement`, qui émet `chain.enforcement_changed`) et on
--   vérifie qu'une facture d'abonnement a bien été enfilée, avec l'URL du
--   point, son secret, et un payload qui remonte jusqu'à l'événement.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; n int; u text; s text; src text; evt int;
BEGIN
  t := _mk_tenant('L23T01');
  PERFORM _l415_endpoint(t, '["chain.enforcement_changed"]'::jsonb);

  PERFORM chain_set_enforcement(t, 'avertit');
  SELECT count(*) INTO evt FROM domain_events
   WHERE tenant_id = t AND event_name = 'chain.enforcement_changed';

  SELECT nb, url, secret, source INTO n, u, s, src
    FROM _l415_livraisons(t, 'chain.enforcement_changed');

  PERFORM _rec('T01', 'un événement du socle atteint la file de livraison, une fois, avec son point et son secret',
    evt = 1 AND n = 1 AND u = 'https://exemple.test/hook' AND s = 's3cr3t' AND src IS NOT NULL,
    format('événements=%s livraisons=%s url=%s secret=%s source=%s', evt, n, coalesce(u, 'NULL'),
           coalesce(s, 'NULL'), coalesce(src, 'NULL')));
END $$;-- ═════════════════════════════════════════════════════════════
-- T02 — Le rejeu ne double pas (D1, point 3 de §4.1)
--   L'idempotence du pont est STRUCTURELLE : `chain_l23_enfiler` est
--   bornée par une clé unique `(tenant, événement, point)`. On le prouve en
--   appelant le pont DEUX fois sur le MÊME événement : le second appel rend
--   `0` et la file ne bouge pas. Un `IF NOT EXISTS` recopié ne prouverait
--   rien ; une clé unique, si.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; eid bigint; n1 int; ajout int; n2 int;
BEGIN
  t := _mk_tenant('L23T02');
  PERFORM _l415_endpoint(t, '["chain.enforcement_changed"]'::jsonb);
  PERFORM chain_set_enforcement(t, 'avertit');

  SELECT id INTO eid FROM domain_events
   WHERE tenant_id = t AND event_name = 'chain.enforcement_changed'
   ORDER BY id DESC LIMIT 1;
  SELECT nb INTO n1 FROM _l415_livraisons(t, 'chain.enforcement_changed');

  -- rejeu EXPLICITE du pont sur le même événement. Appel gardé : si le pont
  -- n'existe pas encore, le test REND un verdict rouge au lieu d'interrompre
  -- le fichier — les huit verdicts restent lisibles.
  BEGIN
    ajout := chain_l23_enfiler(eid);
  EXCEPTION WHEN undefined_function OR undefined_object THEN
    ajout := -1;
  END;

  SELECT nb INTO n2 FROM _l415_livraisons(t, 'chain.enforcement_changed');

  PERFORM _rec('T02', 'un même événement ne donne qu''une livraison par point : le rejeu du pont rend 0',
    n1 = 1 AND ajout = 0 AND n2 = 1,
    format('après la 1re propagation=%s | rejeu du pont a ajouté=%s | total=%s (1 attendu)', n1, ajout, n2));
END $$;-- ═════════════════════════════════════════════════════════════
-- T03 — La non-réversibilité du pont est DÉCLARÉE (point 4 de §4.1)
--   Le pont n'a pas d'effet inverse : une livraison enfilée ne se
--   « défile » pas. C'est permis — mais cela doit être DIT : un maillon
--   sans inverse et sans motif viole le standard des 12 points.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE motif text; revers boolean; trouve boolean := false;
BEGIN
  SELECT de.note, de.reversible INTO motif, revers
  FROM document_effects de
  WHERE de.effet = 'event.webhook.enqueued' AND de.tenant_id IS NULL
  LIMIT 1;
  trouve := motif IS NOT NULL;

  PERFORM _rec('T03', 'la non-réversibilité du pont est déclarée avec son motif',
    trouve AND NOT COALESCE(revers, true) AND length(motif) > 20,
    format('contrat trouvé=%s réversible=%s motif=%s', trouve, coalesce(revers::text, 'NULL'),
           left(coalesce(motif, '—'), 90)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — L'isolation tient : le tenant vient de l'ÉVÉNEMENT (T-4, D-8)
--   Point 7 de §4.1. On pose le contexte sur B et on émet pour A : c'est
--   le cas le plus défavorable, car le GUC de session et l'événement
--   disent des choses différentes. La ligne doit porter A ; B reste vide.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; n_a int; n_b int; ctx uuid;
BEGIN
  ta := _mk_tenant('L23T04A');
  tb := _mk_tenant('L23T04B');
  PERFORM _l415_endpoint(ta, '["chain.enforcement_changed"]'::jsonb, 'https://a.exemple.test/hook');
  PERFORM _l415_endpoint(tb, '["chain.enforcement_changed"]'::jsonb, 'https://b.exemple.test/hook');

  -- le contexte de session est celui de B (le dernier _mk_tenant) — on le
  -- prouve au lieu de l'affirmer, sinon le test ne mesurerait rien :
  ctx := current_tenant_id();

  -- l'événement est émis POUR A, par l'API même que le produit emploie
  PERFORM emit_domain_event(ta, 'chain.enforcement_changed', 'chain_settings', ta,
                            jsonb_build_object('mode', 'avertit', 'par', 'T04'), NULL);

  SELECT x.nb INTO n_a FROM _l415_livraisons(ta, 'chain.enforcement_changed') x;
  SELECT x.nb INTO n_b FROM _l415_livraisons(tb, 'chain.enforcement_changed') x;

  PERFORM _rec('T04', 'l''événement de A n''enfile rien pour B, même contexte de session posé sur B',
    ctx = tb AND n_a = 1 AND n_b = 0,
    format('contexte=%s | livraisons A=%s (1 attendue) livraisons B=%s (0 attendue)',
           CASE WHEN ctx = tb THEN 'B' WHEN ctx = ta THEN 'A' ELSE coalesce(ctx::text,'NULL') END, n_a, n_b));
END $$;-- ═════════════════════════════════════════════════════════════
-- T05 — Le catalogue ne promet que ce qui est produit (§E.5)
--   Deux directions, parce qu'une seule laisse passer un mensonge :
--     * un événement ACTIF du catalogue SANS producteur = une promesse
--       morte (mesuré : 13 sur 15 avant la 415) ;
--     * un producteur SANS ligne de catalogue = un effet invisible du
--       client (mesuré : 26 sur 26 avant la 415).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE promis_sans_produit text; produit_hors_catalogue text; n_promis int; n_produit int;
BEGIN
  SELECT string_agg(c.event_name, ', ' ORDER BY c.event_name), count(*)
    INTO promis_sans_produit, n_promis
  FROM webhook_event_catalog c
  WHERE COALESCE(c.is_active, true)
    AND NOT EXISTS (SELECT 1 FROM _l415_producteurs() p WHERE p.evt = c.event_name);

  SELECT string_agg(p.evt, ', ' ORDER BY p.evt), count(*)
    INTO produit_hors_catalogue, n_produit
  FROM _l415_producteurs() p
  WHERE NOT EXISTS (SELECT 1 FROM webhook_event_catalog c WHERE c.event_name = p.evt);

  PERFORM _rec('T05', 'le catalogue promet exactement ce qui est produit — ni promesse morte, ni effet invisible',
    n_promis = 0 AND n_produit = 0,
    format('promesses sans producteur=%s [%s] | producteurs sans catalogue=%s [%s]',
           n_promis, left(coalesce(promis_sans_produit, '—'), 110),
           n_produit, left(coalesce(produit_hors_catalogue, '—'), 110)));
END $$;-- ═════════════════════════════════════════════════════════════
-- T06 — Le refus est explicite (point 6 de §4.1)
--   S'abonner à un événement qui n'existe pas est une faute de
--   configuration INVISIBLE : le client croirait attendre une facture et
--   ne recevrait rien, pour toujours. La base refuse, en nommant
--   l'événement, la règle et le module.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; refuse boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('L23T06');
  BEGIN
    INSERT INTO webhook_endpoints (tenant_id, name, url, secret, active, active_events)
    VALUES (t, 'Fantaisiste', 'https://f.exemple.test/hook', 's', true, '["facture.magique"]'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    refuse := true; err := SQLERRM;
  END;
  SELECT count(*) INTO n FROM webhook_endpoints WHERE tenant_id = t;

  PERFORM _rec('T06', 'un abonnement à un événement inexistant est refusé, en nommant l''événement et la règle',
    refuse AND n = 0
      AND err LIKE '%facture.magique%' AND err LIKE '%catalogue%' AND err LIKE '%webhook%',
    format('refusé=%s points=%s message=%s', refuse, n, left(err, 140)));
END $$;-- ═════════════════════════════════════════════════════════════
-- T07 — Le surcoût du pont est mesuré (point 8 de §4.1, budget §3.3)
--   200 enfilages, p95 rapporté au budget d'un maillon simple (≤ 50 ms).
--   Le chiffre est DANS le verdict : un « ça va vite » sans nombre ne
--   prouve rien, et un budget qui se négocie au fil de l'eau n'est pas un
--   budget. L'événement bridge inclus — c'est lui qu'on ajoute.
--   L'abonnement est `*` : c'est le chemin le plus coûteux du pont, et il
--   est vérifié ici pour de bon.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; i int; p95 double precision; budget double precision := 50;
        t0 timestamptz; deltas double precision[] := '{}';
BEGIN
  t := _mk_tenant('L23T07');
  PERFORM _l415_endpoint(t, '["*"]'::jsonb, 'https://banc.exemple.test/hook');
  PERFORM set_config('role', 'postgres', true);

  FOR i IN 1..200 LOOP
    t0 := clock_timestamp();
    PERFORM emit_domain_event(t, 'chain.enforcement_changed', 'chain_settings', t,
                              jsonb_build_object('i', i), NULL);
    deltas := deltas || (EXTRACT(epoch FROM (clock_timestamp() - t0)) * 1000.0);
  END LOOP;

  SELECT percentile_disc(0.95) WITHIN GROUP (ORDER BY x) INTO p95
  FROM unnest(deltas) AS x;

  PERFORM _rec('T07', 'le pont tient le budget de §3.3 pour un maillon simple',
    p95 IS NOT NULL AND p95 <= budget,
    format('p95=%s ms pour un budget de %s ms sur 200 enfilages (abonnement « * »)', round(p95::numeric, 3), budget));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — Structure : la file est RLS activée ET forcée, une seule politique
--   Le socle ne l'avait pas fait — mesuré, `relforcerowsecurity = f` sur
--   `webhook_delivery_queue`. §3.5 l'exige pour toute table du système, et
--   c'est la seule des trois tables de la chaîne des webhooks dans ce cas
--   (points de livraison et journal sont déjà forcés).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE rls boolean; force boolean; pol int;
BEGIN
  SELECT c.relrowsecurity, c.relforcerowsecurity INTO rls, force
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'webhook_delivery_queue';
  SELECT count(*) INTO pol FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'webhook_delivery_queue';

  PERFORM _rec('T08', 'la file de livraison est cloisonnée en base (RLS activée ET forcée), une politique',
    rls AND force AND pol = 1,
    format('RLS=%s forcée=%s politiques=%s', coalesce(rls::text, 'NULL'),
           coalesce(force::text, 'NULL'), pol));
END $$;

DROP FUNCTION _l415_endpoint(uuid, jsonb, text);
DROP FUNCTION _l415_producteurs();
DROP FUNCTION _l415_livraisons(uuid, text);
SELECT _audit_assert('415');