-- ============================================================
-- 414_chain_l4_alerte_degradation_tests.sql — L4 (tranche 2) : ce
--   que l'ALERTE DE DÉGRADATION garantit
--
-- La 413 (L4, tranche 1) mesure et publie l'indice de cohérence. Le plan
-- charge L4 d'un quatrième objet, resté entier : « une alerte en cas de
-- dégradation ». Sans elle, la 413 produit un historique que personne ne
-- regarde. La 414 compare le relevé du jour au relevé précédent et prévient.
--
--   T01  le PREMIER passage n'alerte pas : une société neuve, et un
--        invariant qui n'a jamais été mesuré, n'ont rien à dégrader. Alerter
--        ici enverrait une notification à chaque société la première nuit —
--        c'est le bruit qui fait qu'une alerte s'éteint ;
--   T02  une PERTE est détectée et notifiée : un invariant `tenu` qui devient
--        `rompu` écrit une ligne, motive `perte`, et prévient les rôles
--        admin/owner/manager — pas les autres ;
--   T03  le rejeu est SANS EFFET : relancer le job dix fois n'écrit pas dix
--        lignes. C'est le garde-fou anti-spam, et il est en base (index
--        unique), pas seulement dans la fonction ;
--   T04  une RÉPARATION n'alerte pas : `rompu` → `tenu` est une amélioration,
--        pas une degradation — et le motif `amelioration` est écrit quand
--        même, pour qu'un lecteur ne se demande pas ce qui s'est passé ;
--   T05  un écart DÉJÀ rompu et stationnaire ne se répète pas (`deja_rompu`),
--        mais un écart qui s'AGRAVIE, si (`agravement`) : on ne répète pas
--        la même alerte, on ne se tait pas non plus quand le défaut grandit ;
--   T06  structure et droits : RLS forcée, politique de lecture seule, la
--        fonction de passage NON exposée au client (relève + notification
--        depuis le navigateur serait un levier de déni de service), et la
--        COMPARAISON, elle, lisible ;
--   T07  isolation : le journal des alertes est cloisonné par société —
--        chaque propriétaire voit LA SIENNE, la voisine ne voit pas celle
--        de l'autre, et la RLS le fait SANS clause de société. Les DEUX
--        sociétés sont peuplées et le total écrit est contrôlé hors RLS :
--        sans ce témoin, « la voisine ne voit rien » se distinguerait pas
--        de « la voisine n'a rien » — un test qui passe sur une table
--        vide ne prouve rien (cf. le développement du scénario).
--
-- Même outillage que la 413 : contexte posé par `_mk_tenant`, mesure par
-- `service_role` (le rôle qui l'exploite), lectures sous `authenticated`.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '414', false);
DELETE FROM _audit_results WHERE file = '414';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier
-- ─────────────────────────────────────────────────────────────

-- Une prime de paie variable SANS source : la violation d'INV-20 la plus
-- simple à produire — un montant que personne ne peut expliquer. C'est le
-- défaut que les scénarios cassent puis réparent.
CREATE OR REPLACE FUNCTION _l414_faute(p_t uuid, p_employe uuid, p_cle text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO payroll_variable_elements
    (id, tenant_id, employee_id, period, element_type, description, amount, source)
  VALUES
    (md5(p_t::text || p_cle)::uuid, p_t, p_employe, '2026-03', 'prime',
     'Prime sans source', 500, NULL)
  ON CONFLICT DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION _l414_employe(p_t uuid, p_nom text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  -- `employees_email_format_check` refuse un espace : le nom est normalisé
  -- (mesuré : `new row … violates check constraint employees_email_format_check`).
  INSERT INTO employees (tenant_id, name, email, status, salary, hire_date)
  VALUES (p_t, p_nom, lower(regexp_replace(p_nom, '[^a-zA-Z0-9]+', '.', 'g'))
                     || '@audit.test', 'active', 3000, '2025-01-01')
  RETURNING id INTO v;
  RETURN v;
END $$;

-- Les alertes d'une société, dans l'ordre.
CREATE OR REPLACE FUNCTION _l414_alertes(p_t uuid)
RETURNS TABLE(code text, motif text, verdict_avant text, verdict_apres text,
              lignes_avant integer, lignes_apres integer, delta numeric)
LANGUAGE sql AS $$
  SELECT a.code, a.motif, a.verdict_avant, a.verdict_apres,
         a.lignes_avant, a.lignes_apres, a.delta
    FROM chain_invariant_alertes a
   WHERE a.tenant_id = p_t
   ORDER BY a.mesure_le, a.id
$$;

-- Rétablit le contexte d'une société comme PostgREST le fait à chaque
-- requête : GUC + JWT. Les suites sont jouées INDÉPENDAMMENT les unes des
-- autres (la CI lance `-f sql/414_...` seul), on ne peut donc pas compter sur
-- l''helper de la 413 : celui-ci est redéfini ici, à l''identique.
-- `CREATE OR REPLACE` : si les deux suites tournent dans la même base, la
-- définition reste unique.
-- `SECURITY DEFINER` : la fonction lit `tenant_users`, que le rôle
-- `authenticated` ne peut pas consulter directement (mesuré : `permission
-- denied for table users`). C'est un outillage de test, jamais exposé.
--
-- ⚠️ ELLE N'ÉTAIT PAS EXPOSÉE AU CLIENT, ET C'ÉTAIT UNE FAUTE (mesuré le
--   02/10). PostgreSQL accorde `EXECUTE` à `PUBLIC` sur toute fonction
--   créée : mesuré, `has_function_privilege('authenticated',
--   '_mk_tenant_contexte(uuid)', 'EXECUTE') = true`, et `anon` aussi.
--   `SECURITY DEFINER` + `set_config(..., false)` = le client pouvait
--   CHOISIR sa société : le contexte de session bascule alors pour la
--   session entière (le `false` de `set_config` la rend permanente), et la
--   RLS s'applique sur ce contexte frauduleux.
--   MESURÉ : le rôle `authenticated` de la société SEPT appelle
--   `_mk_tenant_contexte(<SIX>)` et `current_setting('app.active_tenant_id')`
--   vaut ensuite SIX — il lit les alertes de SIX. Élévation de privilèges
--   entre sociétés, sur un helper de test.
--   Le `REVOKE` ci-dessous est la fermeture : elle suit la définition, donc
--   elle s'applique quel que soit le fichier de suite qui l'ait écrite
--   (413, 414, 431 la redéfinissent toutes les trois à l'identique).
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

-- Outillage de test : seul `postgres` (et `service_role`, qui n'en a pas
-- besoin) l'exécute. Le `GRANT` au propriétaire n'est pas nécessaire :
-- `postgres` est superutilisateur, il garde le droit.
REVOKE ALL ON FUNCTION _mk_tenant_contexte(uuid) FROM PUBLIC, anon, authenticated;
-- ═════════════════════════════════════════════════════════════
-- T01 — Le premier passage n'alerte pas
--   Une société neuve n'a qu'un relevé par invariant : il n'y a rien à
--   comparer. Alerter ici enverrait une notification à chaque société la
--   première nuit où elle est relevée — et une alerte qui fire sur du rien est
--   une alerte à laquelle on ne croit plus.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; n1 int; v record;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('AL1');

    PERFORM set_config('role', 'service_role', true);
    n1 := public.chain_alertes_lancer(t);
    PERFORM set_config('role', 'postgres', true);

    SELECT * INTO v FROM public.chain_degradation_detectee(t, 'INV-01');

    PERFORM _rec('T01', 'le PREMIER passage n''alerte pas : une société neuve n''a qu''un relevé par invariant, il n''y a rien à comparer — le motif `premier_releve` est rendu et ZÉRO notification part',
      n1 = 0
        AND (SELECT count(*) FROM chain_invariant_alertes WHERE tenant_id = t) = 0
        AND (SELECT count(*) FROM notifications WHERE tenant_id = t) = 0
        AND v.degrade = false AND v.motif = 'premier_releve',
      format('passage rendu=%s (0 attendu) | lignes d''alerte=%s notifications=%s | INV-01 : degrade=%s motif=%s',
             n1,
             (SELECT count(*) FROM chain_invariant_alertes WHERE tenant_id = t),
             (SELECT count(*) FROM notifications WHERE tenant_id = t),
             v.degrade, v.motif));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T01', 'le PREMIER passage n''alerte pas : une société neuve n''a qu''un relevé par invariant, il n''y a rien à comparer — le motif `premier_releve` est rendu et ZÉRO notification part', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — Une PERTE est détectée, écrite et notifiée
--   L'invariant passe de `tenu` à `rompu` : c'est une perte de garantie, la
--   seule qui soit par définition une dégradation. La ligne porte les DEUX
--   verdicts et le delta, et la notification part vers les rôles
--   admin/owner/manager — ceux qui peuvent corriger.
--
--   Contrôle négatif indispensable : le même invariant était `tenu` au relevé
--   précédent, sur la même société (c'est le premier passage qui l'a établi).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; employe uuid; n1 int; v record; v_notif record; n_admin int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('AL2');
    employe := _l414_employe(t, 'Salarie AL2');

    -- Premier relevé : tout tient.
    PERFORM set_config('role', 'service_role', true);
    PERFORM public.chain_alertes_lancer(t);

    -- La faute arrive : une prime sans source identifiée.
    PERFORM set_config('role', 'postgres', true);
    PERFORM _l414_faute(t, employe, 'AL2-1');

    PERFORM set_config('role', 'service_role', true);
    n1 := public.chain_alertes_lancer(t);
    PERFORM set_config('role', 'postgres', true);

    SELECT * INTO v FROM _l414_alertes(t) WHERE code = 'INV-20';
    SELECT * INTO v_notif FROM notifications
     WHERE tenant_id = t AND category = 'chain_coherence' LIMIT 1;
    SELECT count(*) INTO n_admin FROM tenant_users
     WHERE tenant_id = t AND status = 'active';

    PERFORM _rec('T02', 'une PERTE est détectée, écrite et notifiée : un invariant `tenu` qui devient `rompu` motive `perte`, porte les deux verdicts et le delta, et déclenche une notification `warning` pour les rôles admin/owner/manager',
      n1 = 1
        AND v.code = 'INV-20' AND v.motif = 'perte'
        AND v.verdict_avant = 'tenu' AND v.verdict_apres = 'rompu'
        AND v.lignes_avant = 0 AND v.lignes_apres = 1 AND v.delta = 1
        AND v_notif.category = 'chain_coherence'
        AND v_notif.severity = 'warning'
        AND v_notif.title LIKE '%INV-20%'
        AND (SELECT count(*) FROM notifications
              WHERE tenant_id = t AND category = 'chain_coherence') = n_admin,
      format('passage rendu=%s (1 attendu) | alerte : %s %s→%s, %s→%s lignes (delta %s) | notification %s / %s / %s | destinataires=%s (membres actifs=%s)',
             n1, v.code, v.verdict_avant, v.verdict_apres,
             v.lignes_avant, v.lignes_apres, v.delta,
             v_notif.severity, v_notif.category, left(COALESCE(v_notif.title, ''), 46),
             (SELECT count(*) FROM notifications
               WHERE tenant_id = t AND category = 'chain_coherence'), n_admin));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'une PERTE est détectée, écrite et notifiée : un invariant `tenu` qui devient `rompu` motive `perte`, porte les deux verdicts et le delta, et déclenche une notification `warning` pour les rôles admin/owner/manager', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- T03 — Le rejeu est SANS EFFET (le garde-fou anti-spam)
--   Le job nocturne peut être rejoué : un cron qui rate, un redéploiement, un
--   administrateur qui relance à la main. Relancer cinq fois ne doit PAS écrire
--   cinq lignes ni envoyer cinq notifications. C'est l'index unique
--   `(société, code, relevé)` qui l'interdit — posé EN BASE, pas seulement
--   dans la fonction : une fonction sans contrainte ne tient pas une garantie.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; employe uuid; n_premier int; n_rejeu int; n_lignes int;
        n_notif int; n_contrainte int; v_err text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('AL3');
    employe := _l414_employe(t, 'Salarie AL3');
    PERFORM set_config('role', 'service_role', true);
    PERFORM public.chain_alertes_lancer(t);
    PERFORM set_config('role', 'postgres', true);
    PERFORM _l414_faute(t, employe, 'AL3-1');

    -- Le passage qui détecte.
    PERFORM set_config('role', 'service_role', true);
    n_premier := public.chain_alertes_lancer(t);
    -- Quatre rejeux : un job qui tourne en boucle.
    n_rejeu := 0;
    FOR i IN 1..4 LOOP
      n_rejeu := n_rejeu + public.chain_alertes_lancer(t);
    END LOOP;
    PERFORM set_config('role', 'postgres', true);

    SELECT count(*) INTO n_lignes FROM chain_invariant_alertes
     WHERE tenant_id = t AND code = 'INV-20';
    SELECT count(*) INTO n_notif FROM notifications
     WHERE tenant_id = t AND category = 'chain_coherence';

    -- La contrainte est-elle bien en base ? Sur `releve_id` — c'est la clé
    -- qui corrige le défaut mesuré : deux passages dans la même transaction
    -- partagent le même `mesure_le`, et une clé horodatée absorbait
    -- silencieusement le second (motif `agravement` rendu, 0 alerte écrite).
    -- L'identifiant distingue deux relevés de la même seconde.
    SELECT count(*) INTO n_contrainte FROM pg_constraint
     WHERE conrelid = 'chain_invariant_alertes'::regclass
       AND contype = 'u'
       AND pg_get_constraintdef(oid) LIKE '%tenant_id, code, releve_id%';

    -- Et elle refuse vraiment une écriture directe du même triplet.
    BEGIN
      INSERT INTO chain_invariant_alertes
        (tenant_id, code, mesure_le, verdict_avant, verdict_apres, motif,
         releve_id, releve_avant_id)
      SELECT tenant_id, code, mesure_le, verdict_avant, verdict_apres, 'perte',
             releve_id, releve_avant_id
        FROM chain_invariant_alertes WHERE tenant_id = t AND code = 'INV-20'
        LIMIT 1;
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;
    END;

    PERFORM _rec('T03', 'le rejeu est SANS EFFET : cinq passages ne produisent qu''UNE alerte et UNE notification — l''unicité (société, code, relevé) est posée EN BASE et refuse l''écriture directe du même triplet, pas seulement dans la fonction',
      n_premier = 1 AND n_rejeu = 0 AND n_lignes = 1 AND n_notif = 1
        AND n_contrainte = 1 AND v_err IS NOT NULL
        AND v_err LIKE '%chain_invariant_alertes_releve_uniq%',
      format('1er passage=%s, 4 rejeux=%s (0 attendu) | lignes=%s notifications=%s | contrainte unique présente=%s | doublon refusé : %s',
             n_premier, n_rejeu, n_lignes, n_notif, n_contrainte,
             COALESCE(left(v_err, 70), 'ACCEPTÉ (échec !) ')));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T03', 'le rejeu est SANS EFFET : cinq passages ne produisent qu''UNE alerte et UNE notification — l''unicité (société, code, relevé) est posée EN BASE et refuse l''écriture directe du même triplet, pas seulement dans la fonction', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- T04 — Une RÉPARATION n'alerte pas, mais elle est nommée
--   `rompu` → `tenu` est une amélioration : alerter dessus serait du bruit.
--   Mais le cas n'est pas MUET : le motif rendu est `amelioration`, donc un
--   lecteur du journal voit ce qui s'est passé au lieu de se demander
--   pourquoi l'indice est remonté.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; employe uuid; v record; n_apres int; n_notif int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('AL4');
    employe := _l414_employe(t, 'Salarie AL4');
    PERFORM set_config('role', 'service_role', true);
    PERFORM public.chain_alertes_lancer(t);
    PERFORM set_config('role', 'postgres', true);
    PERFORM _l414_faute(t, employe, 'AL4-1');
    PERFORM set_config('role', 'service_role', true);
    PERFORM public.chain_alertes_lancer(t);       -- la perte est alertée

    -- On répare : la source est identifiée.
    PERFORM set_config('role', 'postgres', true);
    UPDATE payroll_variable_elements SET source = 'feuille_heures'
     WHERE tenant_id = t AND source IS NULL;

    PERFORM set_config('role', 'service_role', true);
    n_apres := public.chain_alertes_lancer(t);
    PERFORM set_config('role', 'postgres', true);

    SELECT * INTO v FROM public.chain_degradation_detectee(t, 'INV-20');
    SELECT count(*) INTO n_notif FROM notifications
     WHERE tenant_id = t AND category = 'chain_coherence';

    PERFORM _rec('T04', 'une RÉPARATION n''alerte pas mais elle est NOMMÉE : `rompu` → `tenu` rend le motif `amelioration`, zéro nouvelle alerte et toujours UNE seule notification — le journal dit ce qui s''est passé',
      n_apres = 0
        AND v.degrade = false AND v.motif = 'amelioration'
        AND v.verdict_avant = 'rompu' AND v.verdict_apres = 'tenu'
        AND (SELECT count(*) FROM chain_invariant_alertes WHERE tenant_id = t) = 1
        AND n_notif = 1,
      format('passage après réparation rendu=%s (0 attendu) | INV-20 : %s → %s, motif=%s | lignes d''alerte=%s (1 : la perte d''avant) notifications=%s',
             n_apres, v.verdict_avant, v.verdict_apres, v.motif,
             (SELECT count(*) FROM chain_invariant_alertes WHERE tenant_id = t), n_notif));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04', 'une RÉPARATION n''alerte pas mais elle est NOMMÉE : `rompu` → `tenu` rend le motif `amelioration`, zéro nouvelle alerte et toujours UNE seule notification — le journal dit ce qui s''est passé', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- T05 — Un écart DÉJÀ rompu ne se répète pas, mais s'il s'aggrave, si
--   C'est la ligne de flottaison entre le silence et le bruit. Un défaut
--   stationnaire ne doit pas réveiller l'utilisateur chaque nuit — mais un
--   défaut qui GRANDIT doit se signaler, sinon l'alerte se tait au pire
--   moment. Deux motifs distincts, donc deux comportements distincts :
--   `deja_rompu` (aucune ligne, aucune notification) et `agravement`
--   (une ligne, une notification).
--
--   Le montage : deux fautes → rupture (alerte), puis une troisième
--   (l'écart grandit) doit déclencher `agravement` ; un passage suivant sans
--   changement ne doit rien produire.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; employe uuid; v_stable record; v_aggr record;
        n_stable int; n_aggr int; n_lignes int; n_notif int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    t := _mk_tenant('AL5');
    employe := _l414_employe(t, 'Salarie AL5');
    PERFORM set_config('role', 'service_role', true);
    PERFORM public.chain_alertes_lancer(t);

    -- Deux fautes : l'invariant passe de tenu à rompu, 2 lignes en écart.
    PERFORM set_config('role', 'postgres', true);
    PERFORM _l414_faute(t, employe, 'AL5-1');
    PERFORM _l414_faute(t, employe, 'AL5-2');
    PERFORM set_config('role', 'service_role', true);
    PERFORM public.chain_alertes_lancer(t);        -- perte : 2 lignes en écart

    -- Passage suivant SANS changement : `deja_rompu`, aucune nouvelle alerte.
    n_stable := public.chain_alertes_lancer(t);
    PERFORM set_config('role', 'postgres', true);
    SELECT * INTO v_stable FROM public.chain_degradation_detectee(t, 'INV-20');

    -- L'écart grandit : une troisième faute → `agravement`.
    PERFORM _l414_faute(t, employe, 'AL5-3');
    PERFORM set_config('role', 'service_role', true);
    n_aggr := public.chain_alertes_lancer(t);
    PERFORM set_config('role', 'postgres', true);
    SELECT * INTO v_aggr FROM public.chain_degradation_detectee(t, 'INV-20');

    SELECT count(*) INTO n_lignes FROM chain_invariant_alertes
     WHERE tenant_id = t AND code = 'INV-20';
    SELECT count(*) INTO n_notif FROM notifications
     WHERE tenant_id = t AND category = 'chain_coherence';

    PERFORM _rec('T05', 'la ligne de flottaison entre le bruit et le silence : un écart DÉJÀ rompu et inchangé ne se répète pas (`deja_rompu`, 0 alerte), mais s''il s''AGRAVIE il est signalé (`agravement`, 1 alerte et 1 notification)',
      n_stable = 0 AND v_stable.degrade = false AND v_stable.motif = 'deja_rompu'
        AND v_stable.lignes_avant = 2 AND v_stable.lignes_apres = 2
        AND n_aggr = 1 AND v_aggr.degrade = true AND v_aggr.motif = 'agravement'
        AND v_aggr.lignes_avant = 2 AND v_aggr.lignes_apres = 3
        AND n_lignes = 2 AND n_notif = 2,
      format('passage stable rendu=%s motif=%s (%s→%s lignes) | passage après aggravation rendu=%s motif=%s (%s→%s lignes) | lignes d''alerte=%s notifications=%s',
             n_stable, v_stable.motif, v_stable.lignes_avant, v_stable.lignes_apres,
             n_aggr, v_aggr.motif, v_aggr.lignes_avant, v_aggr.lignes_apres,
             n_lignes, n_notif));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T05', 'la ligne de flottaison entre le bruit et le silence : un écart DÉJÀ rompu et inchangé ne se répète pas (`deja_rompu`, 0 alerte), mais s''il s''AGRAVIE il est signalé (`agravement`, 1 alerte et 1 notification)', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- T06 — Structure et droits
--   Le journal se LIT (page « Cohérence ») et ne s'écrit que par la fonction.
--   `chain_alertes_lancer` n'est PAS donnée au client : déclencher un relevé
--   ET une notification depuis le navigateur serait un levier de déni de
--   service et une source de spam. La COMPARAISON, elle, reste lisible — c'est
--   une lecture du relevé, elle prend les droits de `authenticated`.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_rls int; n_force int; n_pol_lecture int; n_pol_ecriture int;
        n_index_societe int; n_lancer_client int; n_toutes_client int;
        n_compare_client int; n_compare_service int; n_definer int;
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
   WHERE c.relname = 'chain_invariant_alertes';

  SELECT count(*) INTO n_index_societe
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
   WHERE c.relname = 'chain_invariant_alertes'
     AND EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a
                   ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                 WHERE i.indrelid = c.oid AND a.attname = 'tenant_id' AND i.indisvalid);

  SELECT count(*) INTO n_lancer_client FROM pg_proc
   WHERE proname = 'chain_alertes_lancer' AND pronamespace = 'public'::regnamespace
     AND has_function_privilege('authenticated', oid, 'EXECUTE');
  SELECT count(*) INTO n_toutes_client FROM pg_proc
   WHERE proname = 'chain_alertes_toutes_societes' AND pronamespace = 'public'::regnamespace
     AND has_function_privilege('authenticated', oid, 'EXECUTE');
  SELECT count(*) INTO n_compare_client FROM pg_proc
   WHERE proname = 'chain_degradation_detectee' AND pronamespace = 'public'::regnamespace
     AND has_function_privilege('authenticated', oid, 'EXECUTE');
  SELECT count(*) INTO n_compare_service FROM pg_proc
   WHERE proname = 'chain_degradation_detectee' AND pronamespace = 'public'::regnamespace
     AND has_function_privilege('service_role', oid, 'EXECUTE');
  SELECT count(*) FILTER (WHERE prosecdef) INTO n_definer FROM pg_proc
   WHERE proname = 'chain_alertes_lancer' AND pronamespace = 'public'::regnamespace;

  PERFORM _rec('T06', 'structure : `chain_invariant_alertes` est RLS activée ET forcée, ne porte QU''une politique de lecture, a son index mené par `tenant_id`, et le passage (relevé + notification) reste hors de portée du client — seule la COMPARAISON est lisible',
    n_rls = 1 AND n_force = 1 AND n_pol_lecture = 1 AND n_pol_ecriture = 0
      AND n_index_societe = 1 AND n_definer = 1
      AND n_lancer_client = 0 AND n_toutes_client = 0
      AND n_compare_client = 1 AND n_compare_service = 1,
    format('RLS=%s forcée=%s politiques lecture=%s écriture=%s (0 attendue) index société=%s | lancer par authenticated=%s (0 attendu), toutes=%s (0 attendu) | comparer par authenticated=%s service_role=%s',
           n_rls, n_force, n_pol_lecture, n_pol_ecriture, n_index_societe,
           n_lancer_client, n_toutes_client, n_compare_client, n_compare_service));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'structure : `chain_invariant_alertes` est RLS activée ET forcée, ne porte QU''une politique de lecture, a son index mené par `tenant_id`, et le passage (relevé + notification) reste hors de portée du client — seule la COMPARAISON est lisible', false, SQLERRM);
END $$;


-- ═════════════════════════════════════════════════════════════
-- T07 — Isolation
--   Les lectures se font SANS clause de société : c'est la RLS seule qui doit
--   cacher les lignes de l'autre. Contrôle positif : la propriétaire voit la
--   sienne (1 alerte), et la voisine ne voit ni celle de l'autre ni — c'est le
--   contrôle négatif qui compte — la sienne par un chemin de travers.
--
-- ⚠️ L'ORDRE DES FAUTES EST LE SCÉNARIO, ET IL AVAIT ÉTÉ INVERSÉ (mesuré).
--   La version précédente créait la faute **avant** le premier passage. La
--   faute est alors déjà là au moment du relevé : le passage 1 constate
--   `rompu`, le passage 2 constate `rompu` → `rompu`, et la 414 applique le
--   motif `deja_rompu` — qui, **à juste titre**, n'écrit aucune alerte (cf.
--   T05). Le scénario voyait donc `0` et non `1`.
--   Ce n'était pas un défaut d'isolation : c'était un relevé qui ne pouvait
--   rien prouver, parce que la dégradation n'était jamais SURVENUE. La
--   RLS n'a pas été touchée — mesuré sur la base neuve : la politique est
--   bien `tenant_id = current_tenant_id()`, seule politique, et les
--   4 `perte` écrites par T02→T05 sont réelles.
--   L'ordre correct est celui de T02 : relevé sain, PUIS faute, PUIS passage.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; employe_a uuid; employe_b uuid;
        n_a int; n_b int; n_voisin int; n_croise int; n_ecrit int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  -- Le nom est suffixé par l'horodatage : la comparaison porte sur
  -- l'HISTORIQUE des relevés, et une société homonyme laissée par un run
  -- précédent commencerait avec un relevé déjà `rompu` — le scénario verrait
  -- `deja_rompu` au lieu de `perte`, et le contrôle ne prouverait plus rien
  -- (mesuré : c'est exactement ce que donnait un nom fixe).
  ta := _mk_tenant('AL6-' || to_char(clock_timestamp(), 'HH24MISS'));
  employe_a := _l414_employe(ta, 'Salarie AL6');
  -- 1) Relevé SAIN : rien ne manque, INV-20 est `tenu`. C'est ce `tenu`
  --    qui rend la perte plus tard RÉELLE et non déclarative.
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.chain_alertes_lancer(ta);
  -- 2) La faute arrive.
  PERFORM set_config('role', 'postgres', true);
  PERFORM _l414_faute(ta, employe_a, 'AL6-1');
  -- 3) Passage 2 : `tenu` → `rompu`, motif `perte`, UNE alerte écrite.
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.chain_alertes_lancer(ta);

  -- La voisine : même construction, elle a donc ELLE AUSSI une alerte.
  -- ⚠️ Une voisine sans aucune alerte ne prouverait rien : voir « le
  --    contrôle négatif » ci-dessous. Les deux côtés doivent être peuplés,
  --    sinon « la voisine ne voit rien » se distingue pas de « la voisine
  --    n'a rien ».
  PERFORM set_config('role', 'postgres', true);
  tb := _mk_tenant('AL7-' || to_char(clock_timestamp(), 'HH24MISS'));
  employe_b := _l414_employe(tb, 'Salarie AL7');
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.chain_alertes_lancer(tb);        -- relevé sain
  PERFORM set_config('role', 'postgres', true);
  PERFORM _l414_faute(tb, employe_b, 'AL7-1');
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.chain_alertes_lancer(tb);        -- perte, 1 alerte

  --combien d'alertes EXISTENT réellement, hors RLS. C'est le témoin qui
  -- distingue « la RLS cache » de « la ligne n'a jamais été écrite ».
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n_ecrit FROM chain_invariant_alertes
   WHERE tenant_id IN (ta, tb);

  -- La propriétaire : son journal (1 attendu), celui de la voisine (0).
  PERFORM _mk_tenant_contexte(ta);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO n_a FROM chain_invariant_alertes WHERE tenant_id = ta;
  SELECT count(*) INTO n_voisin FROM chain_invariant_alertes WHERE tenant_id = tb;

  -- La voisine, contexte = B : elle voit LA SIENNE (1 attendu — contrôle
  -- positif), et PAS celle de A (0 attendu).
  PERFORM set_config('role', 'postgres', true);
  PERFORM _mk_tenant_contexte(tb);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO n_b FROM chain_invariant_alertes WHERE tenant_id = tb;
  SELECT count(*) INTO n_croise FROM chain_invariant_alertes WHERE tenant_id = ta;

  -- `n_ecrit = 2` est le garde anti-faux-vert : sans lui, les quatre autres
  -- contrôles peuvent être satisfaits par une table VIDE (RLS trop stricte,
  -- alertes jamais écrites, faute mal posée). On exige que les deux alertes
  -- existent réellement, puis que chacune ne soit visible que de sa société.
  PERFORM _rec('T07', 'isolation : le journal des alertes est cloisonné par société — chaque propriétaire voit LA SIENNE, la voisine ne voit pas celle de l''autre, et la RLS le fait SANS clause de société',
    n_ecrit = 2 AND n_a = 1 AND n_voisin = 0 AND n_b = 1 AND n_croise = 0,
    format('écrit hors RLS : AL6+AL7=%s (2 attendu : sans ce témoin, les autres contrôles passeraient sur une table vide) | AL6 voit la sienne=%s (1 attendu) | AL7 vues par AL6=%s (0 attendu) | AL7 voit la sienne=%s (1 attendu) | AL6 vues par AL7=%s (0 attendu)',
           n_ecrit, n_a, n_voisin, n_b, n_croise));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'isolation : le journal des alertes est cloisonné par société — chaque propriétaire voit LA SIENNE, la voisine ne voit pas celle de l''autre, et la RLS le fait SANS clause de société', false, SQLERRM);
END $$;

SELECT _audit_assert('414');
