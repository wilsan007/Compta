-- ============================================================
-- check_chain_performance.sql — G6 : le banc des chaînages
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md, porte **G6**
-- (§4.2) : « un banc qui exécute 1 000 chaînages sur une base neuve et **échoue
-- si un p95 dépasse le budget §3.3** » — le défaut qu'elle rend impossible : les
-- chaînages « qui marchent en démo » et bloquent en production.
--
-- CE QU'IL MESURE, ET CE QU'IL NE MESURE PAS. Il exécute **1 000 fois** le
-- chemin que TOUS les maillons partagent — `chain_avant` (idempotence + contrat),
-- `link_documents` (le lien, M-02), `emit_domain_event` (le journal, M-13),
-- `chain_apres` (la mesure, §3.4) — sur 1 000 documents DISTINCTS, et il compare
-- le p95 d'une itération complète au budget du plan : **≤ 50 ms** (§3.3, « un
-- maillon simple : une écriture, un lien »).
-- Il ne mesure donc PAS le coût métier de chaque maillon (l'écriture de son
-- effet) : ce coût-là est mesuré là où il vit — chaque suite d'acceptation trace
-- `duree_ms` dans `chain_traces` (T11 de la 310, T11 de la 311), et le tableau de
-- bord du lot L5 en publie le p50/p95/p99. Ce banc-ci mesure **la part commune**,
-- celle que les 62 maillons paient 62 fois.
--
-- CE QU'IL DÉTECTE VRAIMENT, ET CE QU'IL NE DÉTECTE PAS (mesuré le 30/09/2026).
--   1. le budget absolu : p95 ≤ 50 ms — un maillon lent sera désactivé par ses
--      utilisateurs, dit le plan ;
--   2. la perte de l'index d'ARBITRAGE : `uq_document_links_effet` est l'index
--      que `link_documents` retrouve dans son `ON CONFLICT`. L'ayant retiré pour
--      l'éprouver, le banc **échoue immédiatement** (« no unique or exclusion
--      constraint matching the ON CONFLICT specification ») : c'est la détection
--      la plus forte du fichier, et elle ne dépend d'aucun seuil ;
--   3. la **linéarité** (ci-dessous) attrape une dérive qui s'aggrave avec le
--      nombre de liens — mais **mesuré : elle ne voit PAS la perte de
--      `ix_document_links_cycle`** à N = 1 000 (p95 0,199 ms sans lui, contre
--      1,002 ms avec : le bruit du poste pèse plus que l'index). C'est écrit ici
--      pour que le vert de ce banc ne laisse pas croire qu'il protège de tout :
--      l'échelle qui décide du coût réel (1 M de liens par an, §3.3) est le banc
--      du lot **L4**, sur copie de production.
--
-- LE BANC NE LAISSE RIEN. Tout se joue dans une transaction **annulée** à la fin
-- (ROLLBACK) : la CI exécute ce contrôle avant les suites, et la base doit rester
-- celle des migrations. Il s'auto-teste : si 1 000 tours n'ont pas produit 1 000
-- liens — ou si le p95 mesuré est nul, c'est-à-dire non mesuré — il échoue, parce
-- qu'un vert ne doit jamais dire « rien n'a été regardé ».
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- 1. Le décor : une société de banc, un contrat déclaré pour l'effet mesuré
--    (sans contrat, chaque tour tracerait `tolere` : le banc mesurerait le mode
--    dégradé, pas la production après L7).
-- ─────────────────────────────────────────────────────────────
INSERT INTO tenants (id, name, plan, status, currency, created_at)
VALUES ('00000000-0000-0000-0000-0000000003a2'::uuid, 'A312PERF', 'pro', 'active', 'EUR', now());

INSERT INTO document_effects (tenant_id, document_type, evenement, effet, ecrit_comptable, touche_stock)
VALUES (NULL, 'zz_doc', 'zz_confirme', 'perf.maillon.declare', false, false);

-- La boucle de mesure : 1 000 tours, chacun sur un document distinct (donc un
-- INSERT réel dans les trois tables du socle, jamais un rejeu). Chaque appel est
-- chronométré séparément : c'est le p95 PAR MAILLON que le plan publie (§3.4).
CREATE TEMP TABLE g6_tours (
  tour integer, d_avant numeric, d_lien numeric, d_evenement numeric, d_apres numeric, d_total numeric);

DO $$
DECLARE
  v_tenant uuid := '00000000-0000-0000-0000-0000000003a2'::uuid;
  v_lien   uuid;
  v_amont  uuid;
  v_ok     boolean;
  v_i      integer;
  v_n      integer := 1000;
  v_t      timestamptz;
  v_t0     timestamptz;
  v_t1     timestamptz;
  v_t2     timestamptz;
  v_t3     timestamptz;
  v_ms     numeric;
BEGIN
  FOR v_i IN 1..v_n LOOP
    v_amont := gen_random_uuid();          -- un document DISTINCT par tour
    v_t0 := clock_timestamp();

    -- (a) l'entrée du maillon : idempotence + contrat
    v_ok := chain_avant(v_tenant, 'zz_doc', 'zz_confirme', 'perf.maillon.declare',
                        'zz_doc', v_amont);
    IF NOT v_ok THEN
      RAISE EXCEPTION 'Le banc n''a pas produit son effet au tour % : chain_avant a rendu faux — le décor est faux.', v_i;
    END IF;
    v_t1 := clock_timestamp();

    -- (b) le lien (c'est lui qui écrit dans document_links et fait vivre l'index)
    v_lien := link_documents(v_tenant, 'zz_doc', v_amont, 'zz_aval', v_amont,
                             'perf.maillon.declare', 'created_from',
                             jsonb_build_object('tour', v_i));
    v_t2 := clock_timestamp();

    -- (c) l'événement du journal, puis (d) la trace du maillon (§3.4)
    PERFORM emit_domain_event(v_tenant, 'zz_doc.confirme', 'zz_doc', v_amont,
                              jsonb_build_object('tour', v_i), NULL);
    v_t3 := clock_timestamp();

    PERFORM chain_apres(v_tenant, 'perf.maillon.declare', 'zz_doc', v_amont,
                        v_t0, 1, 'applique', NULL);
    v_t := clock_timestamp();

    INSERT INTO g6_tours (tour, d_avant, d_lien, d_evenement, d_apres, d_total)
    VALUES (v_i,
            round(EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000, 3)::numeric,
            round(EXTRACT(EPOCH FROM (v_t2 - v_t1)) * 1000, 3)::numeric,
            round(EXTRACT(EPOCH FROM (v_t3 - v_t2)) * 1000, 3)::numeric,
            round(EXTRACT(EPOCH FROM (v_t - v_t3)) * 1000, 3)::numeric,
            round(EXTRACT(EPOCH FROM (v_t - v_t0)) * 1000, 3)::numeric);
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 2. Le verdict : budget absolu (§3.3), linéarité, et « le banc a bien tourné »
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g6_verdict AS
SELECT count(*) AS tours,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY d_avant)     AS p50_avant,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY d_avant)     AS p95_avant,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY d_lien)      AS p50_lien,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY d_lien)      AS p95_lien,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY d_evenement) AS p50_evenement,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY d_evenement) AS p95_evenement,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY d_apres)     AS p50_apres,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY d_apres)     AS p95_apres,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY d_total)     AS p50_total,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY d_total)     AS p95_total,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY d_total) FILTER (WHERE tour <= 100)  AS p95_100,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY d_total) FILTER (WHERE tour > 900)   AS p95_1000
FROM g6_tours;

DO $$
DECLARE
  v record;
  v_n        int := 1000;
  v_liens    int;
  v_traces   int;
  v_evenements int;
  v_budget   numeric := 50;      -- §3.3 : un maillon simple (une écriture, un lien)
  v_facteur  numeric := 5;       -- tolérance de linéarité (index perdu => bien plus)
  -- Plancher de 5 ms : à l'échelle de la milliseconde, un RAPPORT est du bruit —
  -- mesuré : p95 de 0,28 ms pour les 100 premiers tours, 0,49 ms pour les 100
  -- derniers (rapport 1,8, mais il change de sens d'une exécution à l'autre). Un
  -- plancher à 2 ms faisait rougir le banc sur une simple oscillation du poste ;
  -- à 5 ms, il ne se déclenche que sur une dérive réelle.
  v_plancher numeric := 5;
  v_seuil    numeric;
  v_msg      text;
BEGIN
  SELECT * INTO v FROM g6_verdict;

  -- L'auto-test du banc : 1 000 tours, 1 000 liens, 1 000 traces, 1 000 événements.
  -- Sans cette moitié, un `chain_avant` qui rendrait faux (rejeu) mesurerait du vide.
  SELECT count(*) INTO v_liens      FROM document_links
   WHERE tenant_id = '00000000-0000-0000-0000-0000000003a2'::uuid;
  SELECT count(*) INTO v_traces     FROM chain_traces
   WHERE tenant_id = '00000000-0000-0000-0000-0000000003a2'::uuid;
  SELECT count(*) INTO v_evenements FROM domain_events
   WHERE tenant_id = '00000000-0000-0000-0000-0000000003a2'::uuid;

  IF v.tours <> v_n THEN
    v_msg := format('banc incomplet : %s tours mesurés pour %s demandés', v.tours, v_n);
    RAISE EXCEPTION '%', 'check_chain_performance : ' || v_msg;
  END IF;
  IF v_liens <> v_n OR v_traces <> v_n OR v_evenements <> v_n THEN
    v_msg := format('le banc n''a pas écrit ce qu''il croit : %s lien(s), %s trace(s), %s événement(s) pour %s tours',
                    v_liens, v_traces, v_evenements, v_n);
    RAISE EXCEPTION '%', 'check_chain_performance / AUTO-TEST : ' || v_msg;
  END IF;
  IF COALESCE(v.p95_total, 0) = 0 THEN
    RAISE EXCEPTION '%', 'check_chain_performance / AUTO-TEST : p95 mesuré nul — le banc n''a rien mesuré.';
  END IF;

  -- `format()` de PostgreSQL ne connaît que `%s`, `%I`, `%L` — pas de `%.3f` :
  -- les nombres sont donc arrondis ici, puis insérés tels quels. `percentile_cont`
  -- rend un `double precision`, et `round(double, int)` n'existe pas : on caste.
  v_msg := format('Banc des chaînages (%s tours) : p95 total %s ms — chain_avant %s, link_documents %s, emit_domain_event %s, chain_apres %s',
                  v.tours, round(v.p95_total::numeric, 3), round(v.p95_avant::numeric, 3),
                  round(v.p95_lien::numeric, 3), round(v.p95_evenement::numeric, 3),
                  round(v.p95_apres::numeric, 3));
  RAISE NOTICE '%', v_msg;
  v_msg := format('Banc des chaînages : p50 total %s ms ; p95 des 100 premiers %s ms, p95 des 100 derniers %s ms (budget %s ms, linéarité x%s au-delà de %s ms)',
                  round(v.p50_total::numeric, 3), round(v.p95_100::numeric, 3),
                  round(v.p95_1000::numeric, 3), round(v_budget, 0), round(v_facteur, 0),
                  round(v_plancher, 0));
  RAISE NOTICE '%', v_msg;

  IF v.p95_total > v_budget THEN
    v_msg := format('p95 = %s ms pour un budget de %s ms (§3.3, maillon simple) — le chaînage est trop lent',
                    round(v.p95_total::numeric, 3), round(v_budget, 0));
    RAISE EXCEPTION '%', 'check_chain_performance : ' || v_msg;
  END IF;

  v_seuil := GREATEST(v_facteur * v.p95_100, v_plancher);
  IF v.p95_1000 > v_seuil THEN
    v_msg := format('les 100 derniers tours coûtent %s ms (p95) contre %s ms pour les 100 premiers : le coût MONTE avec le nombre de liens — un index du socle a probablement disparu (uq_document_links_effet, ix_document_links_cycle)',
                    round(v.p95_1000::numeric, 3), round(v.p95_100::numeric, 3));
    RAISE EXCEPTION '%', 'check_chain_performance : ' || v_msg;
  END IF;

  RAISE NOTICE 'check_chain_performance : OK — % chaînages dans le budget, coût stable de 1 à % liens.', v_n, v_n;
END $$;

-- Le banc ne laisse rien derrière lui : la CI tourne sur la base des migrations.
ROLLBACK;
