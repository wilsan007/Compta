-- ============================================================
-- 437_chain_l4_fuites_fermees_tests.sql — les TROIS fuites
--   entre sociétés fermées en L4, et leur non-régression
--
-- Le 02/10, en validant la 414 (tâche 3.9), trois défauts d'isolation ont été
-- trouvés et corrigés — mais les corrections n'étaient prouvées que par des
-- MESURES MANUELLES. Cette suite les rend opposables : si quelqu'un rouvre une
-- fuite, la CI rougit.
--
--   T01  `_mk_tenant_contexte` n'est PLUS exécutable par le client. C'était un
--        helper de TEST, `SECURITY DEFINER`, et PostgreSQL accorde `EXECUTE` à
--        `PUBLIC` par défaut — donc `authenticated` ET `anon` pouvaient
--        l'appeler et choisir leur société (`set_config(..., false)` rend le
--        contexte permanent pour la session). Mesuré avant : `true` pour les
--        deux rôles, et le contexte basculait bel et bien.
--   T02  `chain_degradation_detectee` refuse une société qui n'est pas celle du
--        contexte. Elle est `SECURITY DEFINER` et son `p_tenant` est libre : la
--        RLS du lecteur ne pouvait pas s'y opposer. Mesuré avant : SEPT
--        obtenait le relevé de SIX (`releve_id = 3015`).
--   T03  `chain_invariant_alertes.releve_id` est une clé COMPOSITE
--        `(tenant_id, releve_id)`. En mono-colonne, une alerte de SEPT pouvait
--        viser le relevé de SIX : mesuré, l'insertion était ACCEPTÉE. Le
--        scénario tente l'insertion et exige le REFUS.
--
-- ⚠️ T01/T02 sont des contrôles de DROITS et de REFUS : ils passent quand la
--    fuite est fermée, et rougissent seuls quand elle revient. Un test qui
--    mesurerait « le client voit 0 lien » passerait aussi sur une base vide —
--    c'est pourquoi T03 exige un rejet, pas un compte.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '437', false);
DELETE FROM _audit_results WHERE file = '437';

-- ─────────────────────────────────────────────────────────────
-- Outillage : poser le contexte d'une société comme PostgREST le
-- fait, SANS passer par le helper compromised (c'est justement lui
-- que T01 met à l'épreuve : s'en servir ici rendrait le test
-- circulaire).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _l437_contexte(p_t uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE a uuid;
BEGIN
  SELECT tu.auth_id INTO a FROM tenant_users tu
   WHERE tu.tenant_id = p_t AND tu.status = 'active' LIMIT 1;
  IF a IS NULL THEN
    RAISE EXCEPTION 'aucun utilisateur actif pour la société %', p_t;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', p_t::text, false);
END $$;

-- ⚠️ CET OUTILLAGE A COMMIS LA MÊME FAUTE QUE CELUI QU'IL REMPLACE (mesuré le
--   02/10, en écrivant la 437). `_l437_contexte` est `SECURITY DEFINER` et
--   prend une société libre : c'est exactement ce que la porte
--   `check_tenant_guard` refuse, et elle l'a signalé à la première exécution
--   (« `_l437_contexte(p_t uuid)` agit au nom d'une société sans vérifier que
--   l'appelant en est membre »). Sans ce REVOKE, PostgreSQL accorde `EXECUTE`
--   à `PUBLIC` et le client pourrait choisir sa société — la fuite que
--   `_mk_tenant_contexte` portait.
--   On ne l'inscrit donc PAS au registre : ce serait cacheter un défaut réel
--   dans le test censé prouver qu'on l'a fermé.
REVOKE ALL ON FUNCTION _l437_contexte(uuid) FROM PUBLIC, anon, authenticated;

-- Deux sociétés : chacune a son identité et ses liens.
CREATE OR REPLACE FUNCTION _l437_societes()
RETURNS uuid[] LANGUAGE plpgsql AS $$
DECLARE ta uuid; tb uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('L437-A-' || to_char(clock_timestamp(), 'HH24MISS'));
  tb := _mk_tenant('L437-B-' || to_char(clock_timestamp(), 'HH24MISS'));
  RETURN ARRAY[ta, tb];
END $$;
-- ═════════════════════════════════════════════════════════════
-- T01 — Le helper de test n'est PLUS atteignable par le client
--   Un helper `SECURITY DEFINER` qui pose `app.active_tenant_id` avec
--   `set_config(..., false)` donne au client le CHOIX de sa société. C'est ce
--   qui a été mesuré : `authenticated` et `anon` pouvaient l'appeler, et le
--   contexte de session basculait pour la session entière.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_auth int; n_anon int; v_erreur text; v_Existe int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  -- Le droit, d'abord : c'est le contrôle qui ne peut pas mentir, car il ne
  -- dépend d'aucune donnée.
  SELECT count(*) INTO n_auth
    FROM pg_proc p
   WHERE p.proname = '_mk_tenant_contexte'
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
  SELECT count(*) INTO n_anon
    FROM pg_proc p
   WHERE p.proname = '_mk_tenant_contexte'
     AND has_function_privilege('anon', p.oid, 'EXECUTE');

  -- ⚠️ LE FAUX VERT QUE CE TEST A ÉVITÉ (mesuré le 02/10, en écrivant la 437).
  --   La CI joue les suites dans l'ordre ; selon ce qui a tourné avant, la
  --   fonction `_mk_tenant_contexte` peut être ABSENTE de la base. Le compte
  --   des droits rendait alors 0, et le scénario passait — alors qu'il ne
  --   prouvait rien : le refus venait de « function does not exist », pas
  --   d'un retrait de droit.
  --   On exige donc que la fonction EXISTE. Sans elle, il n'y a pas de fuite à
  --   prouver fermée, et le test doit le dire.
  SELECT count(*) INTO v_Existe FROM pg_proc WHERE proname = '_mk_tenant_contexte';
  IF v_Existe = 0 THEN
    PERFORM _rec('T01', 'le helper de test qui pose le contexte n''est plus exécutable par le client : ni `authenticated`, ni `anon` — et l''appel est refusé',
      false, 'la fonction `_mk_tenant_contexte` n''existe pas dans cette base : aucun droit à vérifier, ce scénario ne peut rien prouver (il passerait sur une absence, pas sur une fermeture)');
    RETURN;
  END IF;

  -- Et l'EXÉCUTION, qui est la preuve qu'un droit pourrait se cacher :
  -- on tente l'appel, on attend le refus.
  BEGIN
    PERFORM set_config('role', 'postgres', true);
    SET LOCAL ROLE authenticated;
    -- On passe une société quelconque : si la fonction s'exécutait, elle
    -- lèverait « aucun utilisateur actif » — mais le test ne cherche PAS ce
    -- message : il cherche le REFUS DE DROIT, que `has_function_privilege`
    -- ne peut pas toujours anticiper (une règle de GRANT plus large).
    BEGIN
      PERFORM _mk_tenant_contexte(gen_random_uuid());
    EXCEPTION WHEN insufficient_privilege THEN
      v_erreur := SQLERRM;
    END;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_erreur := SQLERRM;
    RESET ROLE;
  END;

  PERFORM _rec('T01', 'le helper de test qui pose le contexte n''est plus exécutable par le client : ni `authenticated`, ni `anon` — et l''appel est refusé',
    n_auth = 0 AND n_anon = 0 AND v_erreur IS NOT NULL AND v_erreur LIKE '%permission denied%',
    format('EXECUTE pour authenticated=%s (0 attendu) | pour anon=%s (0 attendu) | appel réel : %s',
           n_auth, n_anon, COALESCE(v_erreur, 'AUCUN REFUS — le helper est encore appelable')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'le helper de test qui pose le contexte n''est plus exécutable par le client : ni `authenticated`, ni `anon` — et l''appel est refusé', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — `chain_degradation_detectee` refuse la société d'autrui
--   Elle est `SECURITY DEFINER` et exposed à `authenticated` (c'est une
--   COMPARAISON, une lecture : elle doit rester lisible). Son `p_tenant` est
--   donc libre — sauf contrôle. Avant : SEPT obtenait le relevé de SIX.
--   On exige ici DEUX choses : le refus pour la société d'autrui, ET le
--   fonctionnement normal pour la sienne (sinon on pourrait « fermer » la
--   fonction en la cassant).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_soc uuid[];
        v_refus text; v_sien jsonb;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  v_soc := _l437_societes();

  -- Un relevé réel pour chaque société, sinon le refus ne prouverait rien.
  PERFORM set_config('role', 'service_role', true);
  PERFORM audit_chains(v_soc[1]);
  PERFORM audit_chains(v_soc[2]);
  PERFORM set_config('role', 'postgres', true);

  -- Chez soi : la comparaison répond, sans lever.
  PERFORM _l437_contexte(v_soc[1]);
  SET LOCAL ROLE authenticated;
  BEGIN
    SELECT to_jsonb(d) INTO v_sien
      FROM public.chain_degradation_detectee(v_soc[1], 'INV-01') d;
    v_refus := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_refus := 'appel légitime refusé : ' || SQLERRM;
  END;

  -- Chez l'autre : la fonction doit LEVER, pas rendre un verdict.
  BEGIN
    PERFORM public.chain_degradation_detectee(v_soc[2], 'INV-01');
    v_refus := COALESCE(v_refus, 'AUCUN REFUS : le relevé de la société voisine a été rendu');
  EXCEPTION WHEN others THEN
    IF v_refus IS NULL THEN v_refus := SQLERRM; END IF;
  END;
  RESET ROLE;

  PERFORM _rec('T02', 'la comparaison refuse la société d''autrui mais répond pour la sienne : c''est une garde, pas une fonction cassée',
    (v_sien IS NOT NULL) AND (v_refus IS NOT NULL) AND (v_refus LIKE '%refus%'),
    format('appel sur SA société : %s | appel sur la société AUTRE : %s',
           COALESCE(v_sien->>'motif', 'AUCUNE LIGNE RENDUE'),
           COALESCE(v_refus, '(aucun)')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'la comparaison refuse la société d''autrui mais répond pour la sienne : c''est une garde, pas une fonction cassée', false, SQLERRM);
END $$;
-- ═════════════════════════════════════════════════════════════
-- T03 — Le lien d'une alerte ne peut pas traverser une société
--   `releve_id` était une clé étrangère MONO-colonne vers
--   `chain_invariant_results(id)` : une alerte de SEPT pouvait viser le relevé
--   de SIX, et l'insertion était ACCEPTÉE (mesuré, porte ISO-02). La clé est
--   devenue composite `(tenant_id, releve_id)`.
--   Le scénario exige le REFUS de l'insertion croisée. Exiger un COMPTE de
--   liens croisés passerait aussi sur une base vide — c'est le rejet qui prouve.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_soc uuid[]; v_releve bigint; v_refus text; v_ok int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  v_soc := _l437_societes();

  -- Un relevé réel chez B, pour avoir un `id` à viser depuis A.
  PERFORM set_config('role', 'service_role', true);
  PERFORM audit_chains(v_soc[2]);
  PERFORM set_config('role', 'postgres', true);
  SELECT id INTO v_releve FROM chain_invariant_results
   WHERE tenant_id = v_soc[2] LIMIT 1;

  IF v_releve IS NULL THEN
    PERFORM _rec('T03', 'une alerte ne peut pas viser le relevé d''une autre société (clé composite)', false,
                 'aucun relevé produit pour la société voisine : le scénario ne peut rien prouver');
    RETURN;
  END IF;

  -- On tente l'insertion croisée : A (v_soc[1]) visant le relevé de B.
  BEGIN
    INSERT INTO chain_invariant_alertes
      (tenant_id, code, mesure_le, verdict_avant, verdict_apres,
       lignes_avant, lignes_apres, delta, motif, releve_id)
    VALUES
      (v_soc[1], 'INV-01', now(), 'tenu', 'rompu', 0, 1, 1, 'perte', v_releve);
    v_refus := NULL;      -- acceptée : la clé est redevenue mono-colonne
  EXCEPTION WHEN foreign_key_violation THEN
    v_refus := SQLERRM;
  END;

  -- Temoin : la clé composite existe-t-elle bien ?
  SELECT count(*) INTO v_ok FROM pg_constraint c
    JOIN pg_class ch ON ch.oid = c.conrelid
   WHERE ch.relname = 'chain_invariant_alertes'
     AND c.contype = 'f'
     AND pg_get_constraintdef(c.oid) LIKE '%(tenant_id, releve_id)%';

  PERFORM _rec('T03', 'une alerte ne peut pas viser le relevé d''une autre société : la clé est COMPOSITE (tenant_id, releve_id) et l''insertion croisée est refusée',
    (v_refus IS NOT NULL) AND (v_ok = 1),
    format('insertion croisée (A visant le relevé de B) : %s | contrainte composite présente=%s (1 attendue)',
           COALESCE(v_refus, 'ACCEPTEE - la clé a ete rouverte !'), v_ok));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'une alerte ne peut pas viser le relevé d''une autre société : la clé est COMPOSITE (tenant_id, releve_id) et l''insertion croisée est refusée', false, SQLERRM);
END $$;

SELECT _audit_assert('437');