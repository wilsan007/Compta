-- ═══════════════════════════════════════════════════════════════════════════
-- 496_chain_l16_cloture_projet_tests.sql — L16 · la clôture de projet
-- ═══════════════════════════════════════════════════════════════════════════
-- La suite éprouve le maillon de la 496 en dix verdicts :
--
--   T01  NOMINAL : le passage à 'completed' est TRACÉ (« applique »), le
--        contrat est DÉCLARÉ (aucune trace « tolere »/« refuse »), et
--        l'événement `projects.completed` est émis UNE fois, en PORTANT la
--        marge gelée ;
--   T02  IDEMPOTENCE (D1) : rouvrir puis reclore ne rejoue PAS l'effet — une
--        trace « ignore » le DIT, et ni la trace « applique » ni l'événement
--        ne sont dupliqués ;
--   T03  LE SILENCE HORS CLÔTURE : les autres transitions d'état (on_hold,
--        cancelled) ne produisent rien — le maillon ne parle que de la clôture ;
--   T04  LA CLÔTURE N'EST JAMAIS BLOQUÉE par le maillon qu'elle déclenche ;
--   T05  ISOLATION (D8) : le voisin ne voit ni trace ni événement.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '496', false);
DELETE FROM _audit_results WHERE file = '496';

-- ── T01 — LE NOMINAL : la clôture cesse d'être muette ──────────────────────
DO $$
DECLARE t uuid; p uuid; n int; v_res text; v_pay jsonb;
BEGIN
  t := _mk_tenant('T496A');
  INSERT INTO projects (tenant_id, name, status, budget, actual_cost, start_date)
    VALUES (t, 'Chantier Alpha', 'active', 10000, 6500, '2026-01-05') RETURNING id INTO p;

  PERFORM _as_user();
  UPDATE projects SET status = 'completed', end_date = '2026-03-31' WHERE id = p;

  SELECT count(*), max(resultat) INTO n, v_res FROM chain_traces
   WHERE tenant_id = t AND effet = 'project.closure.finalized' AND amont_id = p;
  PERFORM _rec('T01a', 'la clôture est TRACÉE (une trace, résultat « applique »)',
    n = 1 AND v_res = 'applique', 'traces = ' || n || ', resultat = ' || COALESCE(v_res, '-'));

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'project.closure.finalized' AND amont_id = p
     AND resultat IN ('tolere', 'refuse');
  PERFORM _rec('T01b', 'le contrat est DÉCLARÉ et ACTIF (aucune trace « tolere »/« refuse »)',
    n = 0, 'anomalies = ' || n);

  SELECT count(*) INTO n FROM domain_events
   WHERE tenant_id = t AND event_name = 'projects.completed' AND aggregate_id = p;
  PERFORM _rec('T01c', 'l''événement projects.completed est émis, et UNE seule fois',
    n = 1, 'evenements = ' || n);

  SELECT payload INTO v_pay FROM domain_events
   WHERE tenant_id = t AND event_name = 'projects.completed' AND aggregate_id = p
   ORDER BY created_at LIMIT 1;
  PERFORM _rec('T01d', 'l''événement PORTE la marge gelée (clé « marge » présente)',
    v_pay IS NOT NULL AND v_pay ? 'marge',
    'payload = ' || left(COALESCE(v_pay::text, 'vide'), 140));
END $$;

-- ── T02 — IDEMPOTENCE (D1) : rouvrir puis reclore ne rejoue RIEN ───────────
DO $$
DECLARE t uuid; p uuid; n int; n_applique_avant int; n_events_avant int;
BEGIN
  t := _mk_tenant('T496B');
  INSERT INTO projects (tenant_id, name, status, budget, actual_cost, start_date)
    VALUES (t, 'Chantier Beta', 'active', 5000, 3000, '2026-02-01') RETURNING id INTO p;

  PERFORM _as_user();
  UPDATE projects SET status = 'completed' WHERE id = p;

  SELECT count(*) INTO n_applique_avant FROM chain_traces
   WHERE tenant_id = t AND effet = 'project.closure.finalized' AND amont_id = p AND resultat = 'applique';
  SELECT count(*) INTO n_events_avant FROM domain_events
   WHERE tenant_id = t AND event_name = 'projects.completed' AND aggregate_id = p;

  -- Le projet est ROUVERT, puis reclos : le maillon ne doit pas rejouer.
  UPDATE projects SET status = 'active'   WHERE id = p;
  UPDATE projects SET status = 'completed' WHERE id = p;

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'project.closure.finalized' AND amont_id = p AND resultat = 'applique';
  PERFORM _rec('T02a', 'le rejeu ne produit PAS une 2e trace « applique » (D1 tenu)',
    n = n_applique_avant AND n_applique_avant = 1, 'applique = ' || n || ' (avant rejeu : ' || n_applique_avant || ')');

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'project.closure.finalized' AND amont_id = p AND resultat = 'ignore';
  PERFORM _rec('T02b', 'le rejeu est DIT (une trace « ignore »)', n = 1, 'ignore = ' || n);

  SELECT count(*) INTO n FROM domain_events
   WHERE tenant_id = t AND event_name = 'projects.completed' AND aggregate_id = p;
  PERFORM _rec('T02c', 'aucun 2e événement : l''annonce n''est pas dupliquée',
    n = n_events_avant AND n_events_avant = 1, 'evenements = ' || n || ' (avant rejeu : ' || n_events_avant || ')');
END $$;

-- ── T03 — LE SILENCE HORS CLÔTURE : le maillon ne parle que de la clôture ──
DO $$
DECLARE t uuid; p uuid; n_avant int; n int;
BEGIN
  t := _mk_tenant('T496C');
  INSERT INTO projects (tenant_id, name, status, budget, start_date)
    VALUES (t, 'Chantier Gamma', 'active', 1000, '2026-03-01') RETURNING id INTO p;
  PERFORM _as_user();

  SELECT count(*) INTO n_avant FROM chain_traces
   WHERE tenant_id = t AND effet = 'project.closure.finalized' AND amont_id = p;

  UPDATE projects SET status = 'on_hold'   WHERE id = p;   -- ni clôture…
  UPDATE projects SET status = 'cancelled' WHERE id = p;   -- …ni annulation

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'project.closure.finalized' AND amont_id = p;
  PERFORM _rec('T03a', 'on_hold puis cancelled ne produisent AUCUNE trace du maillon',
    n = n_avant AND n = 0, 'traces = ' || n);

  SELECT count(*) INTO n FROM domain_events
   WHERE tenant_id = t AND event_name = 'projects.completed' AND aggregate_id = p;
  PERFORM _rec('T03b', 'aucun événement projects.completed hors clôture', n = 0, 'evenements = ' || n);
END $$;

-- ── T04 — LA CLÔTURE N'EST JAMAIS BLOQUÉE par le maillon qu'elle déclenche ─
DO $$
DECLARE t uuid; p uuid; n int; ok boolean := true; msg text := 'UPDATE accepté';
BEGIN
  t := _mk_tenant('T496D');
  -- Un projet SANS donnée de coût : la marge peut être indisponible — la
  -- clôture doit passer quand même, et le dire (trace + payload).
  INSERT INTO projects (tenant_id, name, status, start_date)
    VALUES (t, 'Chantier Delta (sans coût)', 'active', '2026-04-01') RETURNING id INTO p;
  PERFORM _as_user();

  BEGIN
    UPDATE projects SET status = 'completed' WHERE id = p;
  EXCEPTION WHEN OTHERS THEN
    ok := false; msg := SQLERRM;
  END;
  PERFORM _rec('T04a', 'la clôture réussit même si la marge est indisponible', ok, msg);

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'project.closure.finalized' AND amont_id = p AND resultat = 'applique';
  PERFORM _rec('T04b', 'et elle est tracée (une trace « applique »)', n = 1, 'applique = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne voit ni trace ni événement ─────────
DO $$
DECLARE ta uuid; tb uuid; pa uuid; n int;
BEGIN
  ta := _mk_tenant('T496E1');
  INSERT INTO projects (tenant_id, name, status, start_date)
    VALUES (ta, 'Chantier E1', 'active', '2026-05-01') RETURNING id INTO pa;
  PERFORM _as_user();
  UPDATE projects SET status = 'completed' WHERE id = pa;

  -- Le décor bascule le tenant actif : il faut repasser par le rôle
  -- superutilisateur pour BÂTIR la société voisine (« RESET ROLE »).
  RESET ROLE;
  tb := _mk_tenant('T496E2');
  PERFORM _as_user();

  SELECT count(*) INTO n FROM chain_traces
   WHERE effet = 'project.closure.finalized' AND amont_id = pa;
  PERFORM _rec('T05a', 'le voisin ne voit AUCUNE trace de la société A', n = 0, 'traces visibles = ' || n);

  SELECT count(*) INTO n FROM domain_events
   WHERE event_name = 'projects.completed' AND aggregate_id = pa;
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN événement de la société A', n = 0, 'evenements visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = ta AND effet = 'project.closure.finalized' AND amont_id = pa AND resultat = 'applique';
  PERFORM _rec('T05c', 'la trace de A existe toujours, et reste à A', n = 1, 'traces de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('496');
