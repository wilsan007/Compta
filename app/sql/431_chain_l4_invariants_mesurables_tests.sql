-- ============================================================
-- 431_chain_l4_invariants_mesurables_tests.sql — L4, tranche 3 :
--   ce que la mesure d'INV-19 et les six preuves garantissent
--
-- La 431 ajoute le QUATORZIÈME invariant mesurable (INV-19, par le
-- registre `chain_document_types`) et transforme les six raisons
-- restantes en preuves mesurées. La suite prouve sept choses :
--
--   T01  le relevé mesure bien 14 invariants, et le `detail`
--        d'INV-19 publie ses quatre clés — un détail sans ses clés
--        est un détail que la page « Cohérence » ne peut pas lire ;
--   T02  un orphelin RÉEL (type enregistré, document disparu) est
--        compté : c'est la fonction première de l'invariant ;
--   T03  ⚠️ le garde anti-faux-vert : un lien de type NON ENREGISTRÉ
--        fait rompre l'invariant. Le jour où l'inventaire oublie
--        d'inscrire un type, le relevé ne dit pas « tenu » — il
--        dit « je n'ai pas pu regarder, et je le crie » ;
--   T04  la délégation aux treize branches de la 413 est INTACTE :
--        mêmes mesures, et la garde « mesurable sans branche LÈVE »
--        tient toujours à travers le nouveau wrapper ;
--   T05  les six raisons non mesurables sont des PREUVES mesurées :
--        chacune commence par « Mesuré le » — une raison invérifiable
--        se recopie, une preuve se contrôle ;
--   T06  structure et droits : `chain_document_types` est RLS
--        activée ET forcée, porte UNE politique de lecture, son
--        index est mené par tenant_id, et le client NE PEUT PAS
--        écrire — inscrire un type depuis le navigateur ferait
--        verdir INV-19 à volonté ;
--   T07  isolation : l'entrée de registre propre à une société n'est
--        pas lue par la voisine ; l'entrée standard l'est par tous.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '431', false);
DELETE FROM _audit_results WHERE file = '431';

-- Rétablit le contexte d'une société comme PostgREST le fait à chaque
-- requête. Redéfini ici (les suites sont jouées INDÉPENDAMMENT), à
-- l'identique de la 414 : `CREATE OR REPLACE` garde la définition
-- unique si deux suites tournent dans la même base.
CREATE OR REPLACE FUNCTION _mk_tenant_contexte(p_t uuid)
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

-- Outillage de test, jamais exposé au client. `SECURITY DEFINER` +
-- `set_config(..., false)` : sans ce REVOKE, PostgreSQL accorde `EXECUTE` à
-- `PUBLIC` et le client choisit sa société (mesuré le 02/10, cf. le
-- développement dans 414_chain_l4_alerte_degradation_tests.sql).
REVOKE ALL ON FUNCTION _mk_tenant_contexte(uuid) FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- T01 — Le relevé mesure QUATORZE, et le détail d'INV-19 se lit
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; r jsonb; d jsonb; v_mesures int; v_non_mes int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('INV19-T01');
  PERFORM set_config('role', 'service_role', true);
  r := public.audit_chains(ta);
  v_mesures := (r->>'mesures')::int;
  v_non_mes := (r->>'non_mesurables')::int;
  PERFORM set_config('role', 'postgres', true);

  SELECT detail INTO d FROM chain_invariant_results
   WHERE tenant_id = ta AND code = 'INV-19'
   ORDER BY mesure_le DESC LIMIT 1;

  PERFORM _rec('T01', 'le relevé mesure QUATORZE invariants (INV-19 est passé du rang de nommé à celui de mesuré), les six autres restent nommés avec leur preuve, et le détail d''INV-19 publie ses quatre clés — un détail sans ses clés est un détail que l''écran ne peut pas lire',
    v_mesures = 14 AND v_non_mes = 6
      AND d ? 'liens_examines' AND d ? 'orphelins_reels'
      AND d ? 'types_non_resolus' AND d ? 'types_hors_registre',
    format('mesures=%s (14 attendues) | non_mesurables=%s (6 attendus) | clés du détail INV-19 : %s',
           v_mesures, v_non_mes, COALESCE(d::text, '(aucun relevé INV-19)')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'le relevé mesure QUATORZE invariants (INV-19 est passé du rang de nommé à celui de mesuré), les six autres restent nommés avec leur preuve, et le détail d''INV-19 publie ses quatre clés — un détail sans ses clés est un détail que l''écran ne peut pas lire', false, SQLERRM);
END $$;
-- ═══════════════════════════════════════════════════════════════
-- T02 — Un orphelin RÉEL est compté
--   Le type est enregistré (`pay_runs`, `journal_entries`), les
--   documents n'existent pas : chacun des deux côtés est compté,
--   et l'invariant est ROMPU. Une société saine reste « tenue » :
--   c'est le contrôle négatif qui donne sa valeur au positif.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; v_rompu int; v_sain int; d jsonb;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('INV19-T02a');
  tb := _mk_tenant('INV19-T02b');
  INSERT INTO document_links
    (tenant_id, amont_type, amont_id, aval_type, aval_id, link_type, effet)
  VALUES
    (ta, 'pay_runs', gen_random_uuid(), 'journal_entries',
     gen_random_uuid(), 'generated_entry', 'INV19.test.orphelin');
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.audit_chains(ta);
  PERFORM public.audit_chains(tb);
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) FILTER (WHERE verdict = 'rompu') INTO v_rompu
    FROM chain_invariant_results WHERE tenant_id = ta AND code = 'INV-19';
  SELECT count(*) FILTER (WHERE verdict = 'tenu') INTO v_sain
    FROM chain_invariant_results WHERE tenant_id = tb AND code = 'INV-19';
  SELECT detail INTO d FROM chain_invariant_results
   WHERE tenant_id = ta AND code = 'INV-19' ORDER BY mesure_le DESC LIMIT 1;

  PERFORM _rec('T02', 'un orphelin RÉEL est compté : deux types enregistrés, deux documents disparus — l''invariant est ROMPU et le détail nomme les deux orphelins, tandis qu''une société saine reste tenue',
    v_rompu >= 1 AND v_sain >= 1
      AND (d->>'orphelins_reels')::int = 2
      AND (d->>'types_non_resolus')::int = 0,
    format('rompu=%s (>=1 attendu) | saine tenue=%s (>=1 attendu) | orphelins_reels=%s (2 attendus) | types_non_resolus=%s (0 attendu)',
           v_rompu, v_sain, d->>'orphelins_reels', d->>'types_non_resolus'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'un orphelin RÉEL est compté : deux types enregistrés, deux documents disparus — l''invariant est ROMPU et le détail nomme les deux orphelins, tandis qu''une société saine reste tenue', false, SQLERRM);
END $$;

-- ═══════════════════════════════════════════════════════════════
-- T03 — Le garde anti-faux-vert : type hors registre ⇒ rompu
--   Un lien de type `ghost_documents` — aucun type de ce nom au
--   registre — NE PEUT PAS être déclaré tenu : personne n'a pu
--   regarder son amont. L'invariant doit être ROMPU, le type doit
--   être NOMMÉ dans le détail. C'est la leçon de la 413 retournée
--   en garde-fou : « un relevé vide ne passe jamais pour un
--   invariant tenu ».
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; v_rompu int; d jsonb; v_types text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('INV19-T03');
  INSERT INTO document_links
    (tenant_id, amont_type, amont_id, aval_type, aval_id, link_type, effet)
  VALUES
    (ta, 'ghost_documents', gen_random_uuid(), 'journal_entries',
     gen_random_uuid(), 'generated_entry', 'INV19.test.hors_registre');
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.audit_chains(ta);
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) FILTER (WHERE verdict = 'rompu') INTO v_rompu
    FROM chain_invariant_results WHERE tenant_id = ta AND code = 'INV-19';
  SELECT detail INTO d FROM chain_invariant_results
   WHERE tenant_id = ta AND code = 'INV-19' ORDER BY mesure_le DESC LIMIT 1;
  v_types := d->>'types_hors_registre';

  PERFORM _rec('T03', 'le garde anti-faux-vert : un lien de type NON ENREGISTRÉ fait rompre l''invariant et le type est NOMMÉ dans le détail — le relevé ne dit jamais « tenu » sur ce qu''il n''a pas pu regarder',
    v_rompu >= 1
      AND (d->>'types_non_resolus')::int >= 1
      AND v_types LIKE '%ghost_documents%',
    format('rompu=%s (>=1 attendu) | types_non_resolus=%s (>=1 attendu) | types_hors_registre=%s (doit nommer ghost_documents)',
           v_rompu, d->>'types_non_resolus', COALESCE(v_types, '(vide)')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'le garde anti-faux-vert : un lien de type NON ENREGISTRÉ fait rompre l''invariant et le type est NOMMÉ dans le détail — le relevé ne dit jamais « tenu » sur ce qu''il n''a pas pu regarder', false, SQLERRM);
END $$;
-- ═══════════════════════════════════════════════════════════════
-- T04 — La délégation aux treize branches de la 413 est intacte
--   Deux contrôles dans un seul scénario :
--   1. la mesure d'un code de la 413 (INV-01) passe par le nouveau
--      wrapper et rend EXACTEMENT ce que la base rend ;
--   2. la garde de la 413 tient : un invariant inscrit `mesurable`
--      sans branche de mesure LÈVE — à travers le wrapper. On
--      inscrit `INV-99` (inactif : il ne pollue ni le relevé ni
--      l'indice) et on mesure : l'exception doit partir.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; m RECORD; b RECORD; v_leve text := NULL;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('INV19-T04');
  SELECT * INTO m FROM public.chain_invariant_mesurer(ta, 'INV-01');
  SELECT * INTO b FROM public.chain_invariant_mesurer_base(ta, 'INV-01');

  INSERT INTO chain_invariants
    (tenant_id, code, libelle, modules, source_a, source_b, sens,
     tolerance, mesurable, raison_non_mesurable, actif)
  VALUES
    (ta, 'INV-99', 'Sonde de la 431 : mesurable sans branche',
     ARRAY['sonde'], 'a', 'b', 'egalite', 0.01, true, NULL, false);

  BEGIN
    PERFORM public.chain_invariant_mesurer(ta, 'INV-99');
  EXCEPTION WHEN OTHERS THEN
    v_leve := SQLERRM;
  END;

  PERFORM _rec('T04', 'la délégation est intacte : INV-01 rend par le wrapper exactement ce que la base de la 413 rend (mêmes mesures, même écart), et la garde « mesurable sans branche LÈVE » tient toujours — la sonde INV-99 est refusée',
    m.mesure_a = b.mesure_a AND m.mesure_b = b.mesure_b
      AND COALESCE(m.ecart, 0) = COALESCE(b.ecart, 0)
      AND v_leve IS NOT NULL AND v_leve LIKE '%INV-99%',
    format('INV-01 wrapper a=%s b=%s écart=%s | base a=%s b=%s écart=%s | INV-99 levée : %s',
           m.mesure_a, m.mesure_b, m.ecart, b.mesure_a, b.mesure_b, b.ecart,
           COALESCE(v_leve, '(AUCUNE exception — la garde a été contournée !)')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'la délégation est intacte : INV-01 rend par le wrapper exactement ce que la base de la 413 rend (mêmes mesures, même écart), et la garde « mesurable sans branche LÈVE » tient toujours — la sonde INV-99 est refusée', false, SQLERRM);
END $$;
-- ═══════════════════════════════════════════════════════════════
-- T05 — Les six raisons sont des PREUVES, pas des affirmations
--   Le plan autorise le repli (« la raison de chaque exclusion »).
--   La 431 rend cette raison opposable : chacune commence par
--   « Mesuré le » — elle cite la mesure qui la fonde. Une raison
--   qui commence autrement est une affirmation, et une affirmation
--   se recopie sans se vérifier.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE v_sans_preuve text; v_nb int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT string_agg(code, ', ' ORDER BY code) INTO v_sans_preuve
    FROM chain_invariants
   WHERE tenant_id IS NULL AND NOT mesurable
     AND raison_non_mesurable NOT LIKE 'Mesuré le %';
  SELECT count(*) INTO v_nb FROM chain_invariants
   WHERE tenant_id IS NULL AND NOT mesurable;

  PERFORM _rec('T05', 'les six invariants non mesurables portent chacun une raison qui COMMENCE par « Mesuré le » : la raison est datée, fondée sur une mesure réelle, opposable — c''est le repli que le plan autorise, tenu au standard de preuve du dépôt',
    v_sans_preuve IS NULL AND v_nb = 6,
    format('non mesurables=%s (6 attendus) | sans preuve datée : %s',
           v_nb, COALESCE(v_sans_preuve, '(aucun — les six portent leur mesure)')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'les six invariants non mesurables portent chacun une raison qui COMMENCE par « Mesuré le » : la raison est datée, fondée sur une mesure réelle, opposable — c''est le repli que le plan autorise, tenu au standard de preuve du dépôt', false, SQLERRM);
END $$;
-- ═══════════════════════════════════════════════════════════════
-- T06 — Structure et droits du registre
--   `chain_document_types` est la seule table de la 416. Le réflexe
--   du dépôt (§3.5) s'applique : RLS activée ET forcée, UNE seule
--   politique (lecture), index mené par tenant_id. Et le point qui
--   lui est propre : le client NE PEUT PAS écrire — inscrire un type
--   arbitraire depuis le navigateur ferait verdir INV-19 à volonté.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; v_rls text; v_force boolean; v_pol int; v_idx int;
        v_refus text := NULL;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('INV19-T06');
  SELECT c.relrowsecurity::text, c.relforcerowsecurity INTO v_rls, v_force
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'chain_document_types';
  SELECT count(*) INTO v_pol FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'chain_document_types';
  SELECT count(*) INTO v_idx FROM pg_indexes
   WHERE schemaname = 'public' AND tablename = 'chain_document_types'
     AND indexdef LIKE '%(tenant_id,%';

  -- Le client écrit ? Il ne doit pas pouvoir.
  PERFORM _mk_tenant_contexte(ta);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    INSERT INTO chain_document_types (tenant_id, type, table_name)
    VALUES (ta, 'sonde_ecran', 'sales_orders');
  EXCEPTION WHEN OTHERS THEN
    v_refus := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  PERFORM _rec('T06', 'structure : `chain_document_types` est RLS activée ET forcée, porte UNE seule politique de lecture, son index est mené par tenant_id, et le client NE PEUT PAS écrire — une inscription depuis le navigateur ferait verdir INV-19 à volonté, le refus est donc une garantie, pas un manque',
    v_rls = 'true' AND v_force AND v_pol = 1 AND v_idx >= 1
      AND v_refus IS NOT NULL,
    format('rls=%s forcé=%s politiques=%s (1 attendue) index_tenant=%s (>=1 attendu) | écriture client refusée : %s',
           v_rls, v_force, v_pol, v_idx,
           COALESCE(v_refus, '(AUCUN refus — le client peut écrire !)')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'structure : `chain_document_types` est RLS activée ET forcée, porte UNE seule politique de lecture, son index est mené par tenant_id, et le client NE PEUT PAS écrire — une inscription depuis le navigateur ferait verdir INV-19 à volonté, le refus est donc une garantie, pas un manque', false, SQLERRM);
END $$;
-- ═══════════════════════════════════════════════════════════════
-- T07 — Isolation du registre
--   L'entrée standard (tenant_id NULL) se lit de partout — c'est
--   le produit livré. L'entrée propre à une société ne se lit QUE
--   chez elle. La voisine ne la voit pas, SANS clause de société :
--   c'est la RLS seule qui cloisonne.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; n_std int; n_propre_a int; n_propre_b int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('INV19-T07a');
  tb := _mk_tenant('INV19-T07b');
  INSERT INTO chain_document_types (tenant_id, type, table_name, cote)
  VALUES (ta, 'sales_orders_locale', 'sales_orders', 'les_deux');

  -- La propriétaire : l'entrée standard ET la sienne.
  PERFORM _mk_tenant_contexte(ta);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) FILTER (WHERE tenant_id IS NULL) INTO n_std
    FROM chain_document_types;
  SELECT count(*) FILTER (WHERE type = 'sales_orders_locale') INTO n_propre_a
    FROM chain_document_types;

  -- La voisine : l'entrée standard OUI, celle de l'autre NON.
  PERFORM set_config('role', 'postgres', true);
  PERFORM _mk_tenant_contexte(tb);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) FILTER (WHERE tenant_id IS NULL) INTO n_std
    FROM chain_document_types;
  SELECT count(*) FILTER (WHERE type = 'sales_orders_locale') INTO n_propre_b
    FROM chain_document_types;
  PERFORM set_config('role', 'postgres', true);

  PERFORM _rec('T07', 'isolation : l''entrée standard (tenant_id NULL) se lit chez les deux sociétés — c''est le produit livré —, l''entrée propre à une société ne se lit QUE chez elle, et la RLS le fait SANS clause de société dans la requête',
    n_std >= 2 AND n_propre_a = 1 AND n_propre_b = 0,
    format('standard vues par A puis B : %s puis %s (>=2 attendus) | entrée de A vue par A=%s (1 attendu) | vue par B=%s (0 attendu)',
           n_std, n_std, n_propre_a, n_propre_b));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'isolation : l''entrée standard (tenant_id NULL) se lit chez les deux sociétés — c''est le produit livré —, l''entrée propre à une société ne se lit QUE chez elle, et la RLS le fait SANS clause de société dans la requête', false, SQLERRM);
END $$;

SELECT _audit_assert('431');

