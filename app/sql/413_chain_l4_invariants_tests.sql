-- ============================================================
-- 413_chain_l4_invariants_tests.sql — L4 : ce que l'INDICE DE
--   COHÉRENCE garantit quand il affiche un score au client
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §E.3
-- (I-03). Le référentiel nomme 20 invariants transversaux et dit « quatre
-- sont tenus et prouvés (INV-15 à INV-18), le reste rompu, partiel ou
-- inexistant », pour un score « de l'ordre de 4 à 6 sur 20 ». Ce chiffre
-- n'était mesuré nulle part. La 413 le mesure — et cette suite vérifie que
-- la mesure dit vrai.
--
-- Le lot L4 a une doctrine, et c'est elle qu'on teste :
--
--   T01  le registre est EXHAUSTIF et HONNÊTE — 20 invariants standard,
--        13 mesurables, 7 non mesurables, et chacun des 7 porte une
--        raison non vide (la contrainte `chain_invariants_raison_check`
--        l'impose) : un invariant absent du registre serait un invariant
--        oublié, un invariant enregistré non mesurable est un invariant
--        NOMMÉ ;
--   T02  l'indice est le score SUR CE QUI EST MESURÉ — 13 au dénominateur,
--        jamais 20, et les 7 non mesurables sortent en `non_mesure` avec
--        leur raison dans le détail. « 13/20 » serait un mensonge ;
--   T03  un écart RÉEL est détecté, nommé et chiffré : une ligne de paie
--        variable sans source fait basculer INV-20 en `rompu`, avec le
--        nombre de lignes et leur répartition par `element_type` ;
--   T04  l'historique se garde : deux relevés ne s'écrasent pas, et le
--        second lit l'état courant — un invariant rompu puis réparé passe
--        de `rompu` à `tenu` sans que le relevé précédent disparaisse ;
--   T05  la ligne de société l'emporte sur le standard (même mécanisme que
--        `document_effects`, 252) : elle peut DÉACTIVER un invariant, et
--        ce choix ne touche que sa société ;
--   T06  le garde-fou : un invariant inscrit `mesurable` SANS branche de
--        mesure fait crier au lieu de produire un relevé vide lu comme
--        « tenu » — et la contrainte refuse un non mesurable sans raison ;
--   T07  structure : les deux tables sont RLS activée ET forcée, ne portent
--        qu'une politique de LECTURE, `audit_chains` est SECURITY DEFINER
--        et n'est PAS exécutable par le client (vingt requêtes
--        d'agrégation sur commande seraient un levier de déni de service) ;
--   T08  isolation : la société voisine ne voit ni le relevé ni le registre
--        de l'autre, mais voit bien les invariants standard — le registre
--        livré avec le produit n'est pas un secret (contrôle positif).
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé par `_mk_tenant`, puis rôle `authenticated` pour les lectures — un
-- utilisateur réel, sous RLS. La MESURE, elle, se fait par `audit_chains`,
-- donc sous `service_role` : c'est le rôle qui l'exploite en production (le
-- job nocturne), et c'est aussi le seul à qui la fonction soit donnée.
--
-- ⚠️ `set_config('role', …)` ne prend effet qu'EN TRANSACTION : appelé en
-- autocommit il est annulé à la fin de l'instruction et la session reste
-- `postgres` (superutilisateur, donc RLS ignorée) — les lectures passeraient
-- alors au travers des politiques et ne prouveraient rien. Tout le changement
-- de rôle de ce fichier passe donc par `PERFORM` À L'INTÉRIEUR d'un bloc `DO`.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '413', false);
DELETE FROM _audit_results WHERE file = '413';
-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Un élément de paie variable SANS source : la violation d'INV-20 la plus
-- simple à produire — un montant que personne ne peut expliquer.
CREATE OR REPLACE FUNCTION _l413_element_sans_source(p_t uuid, p_employe uuid, p_cle text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO payroll_variable_elements
    (id, tenant_id, employee_id, period, element_type, description, amount, source)
  VALUES
    (md5(p_t::text || p_cle)::uuid, p_t, p_employe, '2026-03', 'prime',
     'Prime sans source', 500, NULL)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v;
  RETURN COALESCE(v, md5(p_t::text || p_cle)::uuid);
END $$;

-- Le dernier relevé d'un invariant pour une société — ce que lit le client.
CREATE OR REPLACE FUNCTION _l413_releve(p_t uuid, p_code text)
RETURNS TABLE(verdict text, lignes_en_ecart integer, detail jsonb, mesure_le timestamptz)
LANGUAGE sql AS $$
  SELECT r.verdict, r.lignes_en_ecart, r.detail, r.mesure_le
    FROM chain_invariant_results r
   WHERE r.tenant_id = p_t AND r.code = p_code
   ORDER BY r.mesure_le DESC, r.id DESC
   LIMIT 1
$$;

-- Rétablit le contexte d'une société comme PostgREST le ferait à chaque
-- requête : GUC + JWT. Indispensable pour lire « comme un voisin » dans la
-- MÊME session — `current_tenant_id()` valide l'appartenance dans
-- `tenant_users`, donc sans cela le contexte retombe à NULL et la RLS
-- laisserait tout passer ou rien.
CREATE OR REPLACE FUNCTION _mk_tenant_contexte(p_t uuid)
RETURNS void LANGUAGE plpgsql AS $$
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

-- ═════════════════════════════════════════════════════════════
-- T01 — Le registre est exhaustif et honnête
--   20 invariants standard, tous distincts, 13 mesurables et 7 non
--   mesurables — et chacun des 7 porte une raison NON VIDE. Un invariant
--   absent du registre serait un invariant oublié ; enregistré non
--   mesurable, c'est un invariant NOMMÉ, et c'est ce qui rend l'indice
--   vérifiable plutôt que décoratif.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_total int; n_mes int; n_non int; n_sans_raison int; n_doublon int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*), count(*) FILTER (WHERE mesurable),
         count(*) FILTER (WHERE NOT mesurable),
         count(*) FILTER (WHERE NOT mesurable
                            AND btrim(COALESCE(raison_non_mesurable, '')) = '')
    INTO n_total, n_mes, n_non, n_sans_raison
    FROM chain_invariants
   WHERE tenant_id IS NULL AND actif;

  SELECT count(*) INTO n_doublon FROM (
    SELECT code FROM chain_invariants WHERE tenant_id IS NULL
     GROUP BY code HAVING count(*) > 1) d;

  PERFORM _rec('T01', 'le registre est exhaustif et honnête : 20 invariants standard, tous distincts, 13 mesurables et 7 non mesurables — chacun des 7 porte une raison non vide',
    n_total = 20 AND n_mes = 13 AND n_non = 7 AND n_sans_raison = 0 AND n_doublon = 0,
    format('inscrits=%s (20 attendus) mesurables=%s (13) non mesurables=%s (7) sans raison=%s doublons=%s',
           n_total, n_mes, n_non, n_sans_raison, n_doublon));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'le registre est exhaustif et honnête : 20 invariants standard, tous distincts, 13 mesurables et 7 non mesurables — chacun des 7 porte une raison non vide', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — L'indice est le score SUR CE QUI EST MESURÉ, jamais sur 20
--   Une société neuve tient ses 13 invariants mesurés : l'indice vaut
--   1.0000 et le relevé publie à côté « 7 non mesurables ». Afficher
--   « 13/20 » quand sept ne sont pas mesurables serait un mensonge : le
--   dénominateur est 13, et les 7 lignes non mesurées portent leur raison.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; res jsonb; n_non_mesure int; n_lignes int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('L4A');

    -- La mesure ne se fait que par la voie grantée : `service_role`.
    PERFORM set_config('role', 'service_role', true);
    res := public.audit_chains(t);

    SELECT count(*) INTO n_lignes FROM chain_invariant_results WHERE tenant_id = t;
    SELECT count(*) INTO n_non_mesure
      FROM chain_invariant_results
     WHERE tenant_id = t AND verdict = 'non_mesure'
       AND btrim(COALESCE(detail->>'raison', '')) <> '';

    PERFORM _rec('T02', 'l''indice est le score SUR CE QUI EST MESURÉ : société neuve = 13/13 tenus, indice 1.0000, et les 7 non mesurables sont publiés à côté avec leur raison (jamais « 13/20 »)',
      (res->>'inscrits')::int = 20
        AND (res->>'mesures')::int = 13
        AND (res->>'tenus')::int = 13
        AND (res->>'rompus')::int = 0
        AND (res->>'non_mesurables')::int = 7
        AND (res->>'indice')::numeric = 1.0000
        AND n_lignes = 20 AND n_non_mesure = 7,
      format('inscrits=%s mesures=%s tenus=%s rompus=%s non_mesurables=%s indice=%s | lignes écrites=%s non_mesure AVEC raison=%s/7',
             res->>'inscrits', res->>'mesures', res->>'tenus', res->>'rompus',
             res->>'non_mesurables', res->>'indice', n_lignes, n_non_mesure));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'l''indice est le score SUR CE QUI EST MESURÉ : société neuve = 13/13 tenus, indice 1.0000, et les 7 non mesurables sont publiés à côté avec leur raison (jamais « 13/20 »)', false, SQLERRM);
  END;
END $$;
-- ═════════════════════════════════════════════════════════════
-- T03 — Un écart RÉEL est détecté, compté et nommé
--   Une prime sans source identifiée : INV-20 (sens `existence`) bascule en
--   `rompu`, l'écart est COMPTÉ, et le détail répartit les violations par
--   `element_type` — un montant que personne ne peut expliquer. Contrôle
--   négatif indispensable : le même invariant était `tenu` au relevé
--   précédent, sur la même société, et l'indice baisse d'autant.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; res jsonb; employe uuid; v record; n_rompus int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('L4B');
    INSERT INTO employees (tenant_id, name, email, status, salary, hire_date)
    VALUES (t, 'Salarie L4B', 'l4b@audit.test', 'active', 3000, '2025-01-01')
    RETURNING id INTO employe;

    PERFORM set_config('role', 'service_role', true);
    res := public.audit_chains(t);                    -- état de départ
    SELECT * INTO v FROM _l413_releve(t, 'INV-20');
    IF v.verdict <> 'tenu' THEN
      RAISE EXCEPTION 'précondition : INV-20 doit être tenu avant la faute (état mesuré : %)', v.verdict;
    END IF;

    PERFORM _l413_element_sans_source(t, employe, 'L4B-1');
    res := public.audit_chains(t);                    -- après la faute

    SELECT * INTO v FROM _l413_releve(t, 'INV-20');
    SELECT count(*) INTO n_rompus FROM chain_invariant_results
     WHERE tenant_id = t AND verdict = 'rompu';

    PERFORM _rec('T03', 'un écart RÉEL est détecté, compté et nommé : une prime sans source fait passer INV-20 de `tenu` à `rompu`, lignes_en_ecart = 1, le détail la répartit par element_type, et l''indice baisse d''autant',
      v.verdict = 'rompu' AND v.lignes_en_ecart = 1
        AND (v.detail->>'prime')::int = 1
        AND n_rompus = 1
        AND (res->>'rompus')::int = 1
        AND (res->>'tenus')::int = 12
        AND (res->>'mesures')::int = 13
        AND (res->>'indice')::numeric < 1.0000,
      format('INV-20 : %s, %s ligne(s) en écart, détail=%s | rompus=%s tenus=%s indice=%s (mesures=%s)',
             v.verdict, v.lignes_en_ecart, v.detail, res->>'rompus', res->>'tenus',
             res->>'indice', res->>'mesures'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T03', 'un écart RÉEL est détecté, compté et nommé : une prime sans source fait passer INV-20 de `tenu` à `rompu`, lignes_en_ecart = 1, le détail la répartit par element_type, et l''indice baisse d''autant', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — L'historique se garde, et le second relevé lit l'état courant
--   Deux `audit_chains` n'écrasent rien : le relevé d'hier reste lisible,
--   et le nouveau lit l'état du moment. Une société dont on RÉPARE l'écart
--   repasse de `rompu` à `tenu` — l'historique garde la trace du passage,
--   c'est ce qui rendra possible l'alerte de dégradation (tranche 2).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; res jsonb; employe uuid; v_avant record; v_apos record;
        n_releves int; n_rompus_histo int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('L4C');
    INSERT INTO employees (tenant_id, name, email, status, salary, hire_date)
    VALUES (t, 'Salarie L4C', 'l4c@audit.test', 'active', 3000, '2025-01-01')
    RETURNING id INTO employe;

    PERFORM set_config('role', 'service_role', true);
    PERFORM _l413_element_sans_source(t, employe, 'L4C-1');
    PERFORM public.audit_chains(t);                    -- relevé n°1 : rompu

    -- On répare : la source est identifiée.
    UPDATE payroll_variable_elements SET source = 'feuille_heures'
     WHERE tenant_id = t AND source IS NULL;
    PERFORM public.audit_chains(t);                    -- relevé n°2 : tenu

    SELECT count(*) INTO n_releves FROM chain_invariant_results
     WHERE tenant_id = t AND code = 'INV-20';
    SELECT count(*) INTO n_rompus_histo FROM chain_invariant_results
     WHERE tenant_id = t AND code = 'INV-20' AND verdict = 'rompu';

    -- Le PREMIER relevé (l'antériorité se lit par mesure_le) et le dernier.
    SELECT r.verdict, r.lignes_en_ecart INTO v_avant
      FROM chain_invariant_results r
     WHERE r.tenant_id = t AND r.code = 'INV-20'
     ORDER BY r.mesure_le, r.id LIMIT 1;
    SELECT * INTO v_apos FROM _l413_releve(t, 'INV-20');

    PERFORM _rec('T04', 'l''historique se garde et se lit dans l''ordre : deux relevés n''écrasent rien, le premier reste `rompu`, le second lit l''état réparé (`tenu`) — l''indice remonte à 1.0000',
      n_releves = 2 AND n_rompus_histo = 1
        AND v_avant.verdict = 'rompu'
        AND v_apos.verdict = 'tenu'
        AND v_apos.lignes_en_ecart = 0,
      format('relevés INV-20=%s (2 attendus) dont rompus=%s | premier=%s (%s lignes) dernier=%s (%s lignes)',
             n_releves, n_rompus_histo, v_avant.verdict,
             v_avant.lignes_en_ecart, v_apos.verdict, v_apos.lignes_en_ecart));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04', 'l''historique se garde et se lit dans l''ordre : deux relevés n''écrasent rien, le premier reste `rompu`, le second lit l''état réparé (`tenu`) — l''indice remonte à 1.0000', false, SQLERRM);
  END;
END $$;
-- ═════════════════════════════════════════════════════════════
-- T05 — La ligne de société l'emporte sur le standard (252)
--   Une société écrit sa PROPRE ligne pour un code : elle remplace celle
--   livrée avec le produit et peut la DÉACTIVER. Le contrôle n'est pas
--   seulement « ma ligne existe » : c'est « le relevé de cette société ne
--   contient plus l'invariant, et celui de la voisine, si ». Le même
--   mécanisme que `document_effects` / `uq_document_effects_contrat`.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; res_a jsonb; employe uuid;
        n_inv20_a int; n_inv20_b int; n_lignes_a int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    ta := _mk_tenant('L4D');
    tb := _mk_tenant('L4E');
    INSERT INTO employees (tenant_id, name, email, status, salary, hire_date)
    VALUES (ta, 'Salarie L4D', 'l4d@audit.test', 'active', 3000, '2025-01-01')
    RETURNING id INTO employe;

    -- La société A désactive INV-20 : elle ne veut pas de ce contrôle.
    INSERT INTO chain_invariants
      (tenant_id, code, libelle, modules, source_a, source_b, sens,
       tolerance, mesurable, actif, note)
    VALUES
      (ta, 'INV-20', 'Paie variable — contrôle désactivé par la société',
       ARRAY['paie'], 'payroll_variable_elements', 'source', 'existence',
       0, true, false, 'Choix de la société : pas de contrôle sur les primes.');

    -- Même faute dans les DEUX sociétés : A l'a désactivé, B l'a subi.
    PERFORM _l413_element_sans_source(ta, employe, 'L4D-1');
    PERFORM set_config('role', 'service_role', true);
    res_a := public.audit_chains(ta);
    PERFORM public.audit_chains(tb);

    SELECT count(*) INTO n_inv20_a FROM chain_invariant_results
     WHERE tenant_id = ta AND code = 'INV-20';
    SELECT count(*) INTO n_lignes_a FROM chain_invariant_results WHERE tenant_id = ta;
    -- La voisine n'a RIEN de la ligne de A dans son registre (RLS) : on
    -- recompte donc depuis `service_role`, qui voit les lignes de toutes.
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) INTO n_inv20_b FROM chain_invariant_results
     WHERE tenant_id = tb AND code = 'INV-20';

    -- A : l'invariant désactivé n'est plus mesuré (19 lignes, pas 20) et la
    -- faute n'est donc PAS comptée — indice 1.0000 malgré la prime orpheline.
    -- B : il reste mesuré et tenu (société neuve sans faute).
    PERFORM _rec('T05', 'la ligne de société l''emporte sur le standard : A désactive INV-20 et son relevé ne le contient plus (19 lignes, indice 1.0000 malgré la faute), tandis que la voisine B le mesure toujours',
      n_inv20_a = 0 AND n_lignes_a = 19
        AND (res_a->>'inscrits')::int = 19
        AND (res_a->>'mesures')::int = 12
        AND (res_a->>'rompus')::int = 0
        AND (res_a->>'indice')::numeric = 1.0000
        AND n_inv20_b = 1,
      format('A : INV-20 dans le relevé=%s (0 attendu) lignes=%s (19) mesures=%s rompus=%s indice=%s | B : INV-20=%s (1 attendu)',
             n_inv20_a, n_lignes_a, res_a->>'mesures', res_a->>'rompus',
             res_a->>'indice', n_inv20_b));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T05', 'la ligne de société l''emporte sur le standard : A désactive INV-20 et son relevé ne le contient plus (19 lignes, indice 1.0000 malgré la faute), tandis que la voisine B le mesure toujours', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — Le garde-fou : pas de relevé vide lu comme « tenu »
--   Un invariant inscrit `mesurable` SANS branche de mesure produirait un
--   relevé vide que le lecteur lirait « tout va bien ». La fonction crie.
--   Et la contrainte refuse, en base, un invariant non mesurable SANS raison
--   — c'est le filet en dessous du garde-fou.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; v_cri text; v_contrainte text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('L4F');

    -- Un invariant que le registre déclare mesurable, sans branche écrite.
    INSERT INTO chain_invariants
      (tenant_id, code, libelle, source_a, source_b, sens, mesurable)
    VALUES
      (t, 'INV-99', 'Invariant inscrit mesurable sans branche de mesure',
       'table_a', 'table_b', 'egalite', true);

    BEGIN
      PERFORM set_config('role', 'service_role', true);
      PERFORM public.audit_chains(t);
      v_cri := NULL;                       -- n'arrive pas ici si ça crie
    EXCEPTION WHEN OTHERS THEN
      v_cri := SQLERRM;
    END;
    PERFORM set_config('role', 'postgres', true);

    -- Le filet en base : `mesurable = false` SANS raison est refusé.
    BEGIN
      INSERT INTO chain_invariants
        (tenant_id, code, libelle, source_a, source_b, sens, mesurable)
      VALUES
        (t, 'INV-98', 'Non mesurable sans raison', 'a', 'b', 'egalite', false);
      v_contrainte := NULL;
    EXCEPTION WHEN OTHERS THEN
      v_contrainte := SQLERRM;
    END;

    PERFORM _rec('T06', 'le garde-fou : un invariant inscrit mesurable SANS branche de mesure fait crier (le relevé vide ne doit jamais passer pour un invariant tenu), et la contrainte refuse en base un non mesurable sans raison',
      v_cri IS NOT NULL AND v_cri LIKE '%INV-99%'
        AND v_contrainte IS NOT NULL
        AND v_contrainte LIKE '%chain_invariants_raison_check%',
      format('mesure sans branche → %s | contrainte → %s',
             COALESCE(left(v_cri, 110), 'AUCUNE (silencieux !)'),
             COALESCE(left(v_contrainte, 110), 'AUCUNE (accepté !) ')));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T06', 'le garde-fou : un invariant inscrit mesurable SANS branche de mesure fait crier (le relevé vide ne doit jamais passer pour un invariant tenu), et la contrainte refuse en base un non mesurable sans raison', false, SQLERRM);
  END;
END $$;
-- ═════════════════════════════════════════════════════════════
-- T07 — Structure : deux tables RLS forcée, et une fonction hors de
--   portée du client
--   Le relevé s'écrit par `audit_chains` (SECURITY DEFINER), jamais par le
--   navigateur : vingt requêtes d'agrégation sur commande seraient un
--   levier de déni de service. Le client LIT le relevé. Les deux tables ne
--   portent donc qu'une politique de SELECT — et l'absence de politique
--   d'écriture est vérifiée ici, pas supposée.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_rls int; n_force int; n_pol_lecture int; n_pol_ecriture int;
        n_index_societe int; n_audit_definer int; n_audit_client int;
        n_mesurer_client int; n_service int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) FILTER (WHERE c.relrowsecurity),
         count(*) FILTER (WHERE c.relforcerowsecurity),
         count(*) FILTER (WHERE EXISTS (
             SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid AND p.polcmd = 'r')),
         count(*) FILTER (WHERE EXISTS (
             SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid AND p.polcmd <> 'r'))
    INTO n_rls, n_force, n_pol_lecture, n_pol_ecriture
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
   WHERE c.relname IN ('chain_invariants', 'chain_invariant_results');

  -- L'index mené par `tenant_id` que la porte G1 exige de toute table
  -- cloisonnée : l'index unique porte une expression, il ne suffit pas.
  SELECT count(*) INTO n_index_societe
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
   WHERE c.relname IN ('chain_invariants', 'chain_invariant_results')
     AND EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a
                   ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                 WHERE i.indrelid = c.oid AND a.attname = 'tenant_id' AND i.indisvalid);

  SELECT count(*) FILTER (WHERE prosecdef) INTO n_audit_definer
    FROM pg_proc WHERE proname = 'audit_chains' AND pronamespace = 'public'::regnamespace;

  -- Le client ne peut ni mesurer ni déclencher le relevé ; seul
  -- `service_role` peut lancer le relevé.
  SELECT count(*) INTO n_audit_client FROM pg_proc
   WHERE proname = 'audit_chains' AND pronamespace = 'public'::regnamespace
     AND has_function_privilege('authenticated', oid, 'EXECUTE');
  SELECT count(*) INTO n_mesurer_client FROM pg_proc
   WHERE proname = 'chain_invariant_mesurer' AND pronamespace = 'public'::regnamespace
     AND has_function_privilege('authenticated', oid, 'EXECUTE');
  SELECT count(*) INTO n_service FROM pg_proc
   WHERE proname = 'audit_chains' AND pronamespace = 'public'::regnamespace
     AND has_function_privilege('service_role', oid, 'EXECUTE');

  PERFORM _rec('T07', 'structure : les deux tables sont RLS activée ET forcée, ne portent QU''une politique de lecture, ont leur index mené par `tenant_id`, et `audit_chains` (SECURITY DEFINER) reste hors de portée du client — `service_role` seul peut lancer le relevé',
    n_rls = 2 AND n_force = 2 AND n_pol_lecture = 2 AND n_pol_ecriture = 0
      AND n_index_societe = 2 AND n_audit_definer = 1
      AND n_audit_client = 0 AND n_mesurer_client = 0 AND n_service = 1,
    format('RLS=%s/2 forcée=%s/2 politiques lecture=%s/2 écriture=%s (0 attendue) index société=%s/2 | audit_chains : SECURITY DEFINER=%s/1 par authenticated=%s (0 attendu) service_role=%s/1 | mesurer par le client=%s (0 attendu)',
           n_rls, n_force, n_pol_lecture, n_pol_ecriture, n_index_societe,
           n_audit_definer, n_audit_client, n_service, n_mesurer_client));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'structure : les deux tables sont RLS activée ET forcée, ne portent QU''une politique de lecture, ont leur index mené par `tenant_id`, et `audit_chains` (SECURITY DEFINER) reste hors de portée du client — `service_role` seul peut lancer le relevé', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — Isolation : la société voisine ne voit ni le relevé ni le registre
--   Les lectures se font SANS clause de société — c'est la RLS seule qui
--   doit cacher les lignes de l'autre. Contrôle positif indispensable : la
--   société propriétaire voit tout son relevé, et les DEUX voient les 20
--   invariants standard, qui sont le produit livré et non un secret.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid;
        n_std int; n_rel_a int; n_rel_b int; n_reg_a int;
        n_reg_voisin int; n_rel_voisin int;
BEGIN
  -- Deux sociétés, deux utilisateurs — chacun est membre de la sienne. C'est
  -- le cloisonnement réel : le contexte RLS est validé par l'appartenance
  -- dans `tenant_users` (cf. `current_tenant_id`), pas par un simple GUC.
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('L4G');
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.audit_chains(ta);
  PERFORM set_config('role', 'postgres', true);
  -- Une ligne de registre propre à A : sans elle, le contrôle n'aurait rien
  -- à cacher.
  INSERT INTO chain_invariants
    (tenant_id, code, libelle, source_a, source_b, sens, mesurable, actif)
  VALUES (ta, 'INV-20', 'Choix de A', 'a', 'b', 'existence', true, false);

  tb := _mk_tenant('L4H');
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.audit_chains(tb);

  -- ── Le propriétaire de A, contexte = A ──────────────────────────
  -- `_mk_tenant('L4H')` a laissé le JWT de B : on réinstalle celui de A,
  -- c'est-à-dire exactement ce que PostgREST refait à chaque requête.
  PERFORM set_config('role', 'postgres', true);
  PERFORM _mk_tenant_contexte(ta);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO n_std FROM chain_invariants WHERE tenant_id IS NULL;
  SELECT count(*) INTO n_rel_a FROM chain_invariant_results WHERE tenant_id = ta;
  SELECT count(*) INTO n_reg_a FROM chain_invariants WHERE tenant_id = ta;
  -- Il ne voit que SON relevé : aucune ligne de celui de la voisine.
  SELECT count(*) INTO n_rel_b FROM chain_invariant_results WHERE tenant_id = tb;

  -- ── Le propriétaire de B, contexte = B ──────────────────────────
  -- On réinstalle le contexte et le rôle : c'est ce que PostgREST fait à
  -- chaque requête, et c'est la seule façon de lire « comme un voisin ».
  PERFORM set_config('role', 'postgres', true);
  PERFORM _mk_tenant_contexte(tb);
  PERFORM set_config('role', 'authenticated', true);
  -- Le voisin ne voit ni le relevé de A, ni sa ligne de registre : la RLS
  -- les cache même sans clause de société.
  SELECT count(*) INTO n_rel_voisin FROM chain_invariant_results WHERE tenant_id = ta;
  SELECT count(*) INTO n_reg_voisin FROM chain_invariants WHERE tenant_id = ta;
  -- … et il voit bien le sien (contrôle positif) : le contrôle est Targeted,
  -- il n'est pas simplement aveugle.
  SELECT count(*) INTO n_rel_b FROM chain_invariant_results WHERE tenant_id = tb;

  PERFORM _rec('T08', 'isolation : sous le rôle `authenticated`, le propriétaire voit ses 20 lignes de relevé et sa ligne de registre ; la voisine, elle, ne voit NI le relevé NI le registre de A — tandis que le standard des 20 invariants reste visible de tous, car il est le produit livré et non un secret',
    n_std = 20 AND n_rel_a = 20 AND n_reg_a = 1
      AND n_rel_b = 20 AND n_rel_voisin = 0 AND n_reg_voisin = 0,
    format('standard visible de tous=%s/20 | A : relevé=%s/20, registre propre=%s/1 | B : son propre relevé=%s/20 (contrôle positif), et sous son contexte le relevé de A=%s (0 attendu), le registre de A=%s (0 attendu)',
           n_std, n_rel_a, n_reg_a, n_rel_b, n_rel_voisin, n_reg_voisin));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'isolation : sous le rôle `authenticated`, le propriétaire voit ses 20 lignes de relevé et sa ligne de registre ; la voisine, elle, ne voit NI le relevé NI le registre de A — tandis que le standard des 20 invariants reste visible de tous, car il est le produit livré et non un secret', false, SQLERRM);
END $$;

SELECT _audit_assert('413');