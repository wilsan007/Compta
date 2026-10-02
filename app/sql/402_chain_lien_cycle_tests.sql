-- ============================================================
-- 312_chain_lien_cycle_tests.sql — le CYCLE DE VIE DU LIEN : ce qu'il garantit
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md (M-02, M-03) et
-- VAGUE-L1-2026-09-29.md §6.2 : « la clé du socle n'a pas de notion de tour » —
-- trouvaille née d'un ROUGE de la suite 230 (T04) : une commande annulée puis
-- reconfirmée ne réservait plus rien.
--
--   C01  structure : les cinq colonnes du cycle, les trois gardes, et l'index
--        d'idempotence devenu PARTIEL (`WHERE etat = 'actif'`) ;
--   C02  le rejeu d'un effet ACTIF ne double rien et FUSIONNE le payload
--        (non-régression de la 252 T02) ;
--   C03  la fermeture ciblée : le lien passe `rompu`, il est daté, motivé,
--        signé, journalisé — et il n'est plus « déjà fait » ni « intact » ;
--   C04  le tour suivant : après fermeture, un NOUVEAU lien naît au tour 2 et
--        l'ancien n'est PAS réécrit (« un lien remplacé, pas réécrit ») ;
--   C05  `chain_avant` redevient VRAI après fermeture — c'est le prérequis qui
--        manquait pour le poser sur les maillons qui se reproduisent ;
--   C06  les refus nominatifs : motif absent, état inconnu, aucun lien actif —
--        et rien n'est écrit quand c'est refusé ;
--   C07  la fermeture GLOBALE d'un document : tous les effets en un acte, un
--        événement par lien, et le second appel RAPPORTE 0 sans lever ;
--   C08  le cloisonnement : fermer chez A ne ferme rien chez B ;
--   C09  les lectures `chain_lien_actif` / `chain_lien_tour` avant, pendant et
--        après le cycle ;
--   C10  les gardes structurelles mordent : un lien fermé sans motif est refusé
--        par la base, et deux liens ACTIFS sur la même clé sont impossibles ;
--   C11  l'événement de fermeture nomme le lien, l'effet, le tour et le motif ;
--   C12  le ROUGE DE LA 230, joué sur le vrai flux : commande annulée puis
--        reconfirmée, avec le geste que le maillon d'annulation posera — la
--        réservation est reproduite ET l'historique garde les deux tours.
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé, puis rôle `authenticated` — un utilisateur réel, sous RLS.
-- Le socle n'est PAS une API (`REVOKE … FROM authenticated`, 252 §14) : les
-- fonctions `chain_*` s'appellent ici comme les maillons les appellent — en tant
-- que propriétaire. Les scénarios qui ont besoin du rôle applicatif basculent
-- avec `_as_user()`, et reviennent avec `set_config('role','none',true)`.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '312', false);
DELETE FROM _audit_results WHERE file = '312';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Poser un lien de test, avec sa ligne amont si besoin.
-- `DROP` avant `CREATE` : le dépôt le fait partout (`audit_helpers.sql`) — une
-- signature qui change ne se remplace pas, elle se recrée.
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

DROP FUNCTION IF EXISTS _l312_lien(uuid, uuid, uuid, text, uuid, jsonb);
CREATE OR REPLACE FUNCTION _l312_lien(p_t uuid, p_amont uuid, p_aval uuid, p_effet text,
  p_ligne uuid DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  PERFORM _p5_doc(p_t, 'sales_orders', p_amont, p_ligne);
  PERFORM _p5_doc(p_t, 'delivery_notes', p_aval);
  RETURN link_documents(p_t, 'sales_orders', p_amont, 'delivery_notes', p_aval, p_effet,
                        'delivered_by', p_payload, p_ligne, NULL);
END $$;

-- Le cycle complet d'un couple, tel que le tableau de bord le lira : état, tour,
-- motif, aval — pour TOUS les tours, dans l'ordre.
DROP FUNCTION IF EXISTS _l312_cycle(uuid, uuid, text);
CREATE OR REPLACE FUNCTION _l312_cycle(p_t uuid, p_amont uuid, p_effet text)
RETURNS TABLE(tour integer, etat text, motif text, aval_id uuid, ferme_le timestamptz, ferme_par uuid)
LANGUAGE sql AS $$
  SELECT dl.tour, dl.etat, dl.motif, dl.aval_id, dl.ferme_le, dl.ferme_par
  FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = 'sales_orders'
    AND dl.amont_id = p_amont AND dl.effet = p_effet
  ORDER BY dl.tour
$$;

DROP FUNCTION IF EXISTS _l312_evenements(uuid, text, uuid);
CREATE OR REPLACE FUNCTION _l312_evenements(p_t uuid, p_nom text, p_agregat uuid)
RETURNS TABLE(payload jsonb) LANGUAGE sql AS $$
  SELECT de.payload FROM domain_events de
  WHERE de.tenant_id = p_t AND de.event_name = p_nom AND de.aggregate_id = p_agregat
  ORDER BY de.id
$$;

-- ═════════════════════════════════════════════════════════════
-- C01 — la structure du cycle : colonnes, gardes, index partiel
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_colonnes int; v_gardes int; v_partiel boolean; v_predicat boolean; v_histo int;
BEGIN
  SELECT count(*) INTO v_colonnes
  FROM pg_attribute a
  WHERE a.attrelid = 'public.document_links'::regclass AND NOT a.attisdropped
    AND a.attname IN ('etat', 'tour', 'ferme_le', 'ferme_par', 'motif');

  SELECT count(*) INTO v_gardes FROM pg_constraint
  WHERE conrelid = 'public.document_links'::regclass
    AND conname IN ('document_links_etat_check', 'document_links_tour_check',
                    'document_links_fermeture_check');

  SELECT (i.indpred IS NOT NULL),
         (pg_get_indexdef(i.indexrelid) ILIKE '%etat%actif%')
    INTO v_partiel, v_predicat
  FROM pg_index i WHERE i.indexrelid = 'public.uq_document_links_effet'::regclass;

  SELECT count(*) INTO v_histo FROM pg_indexes
  WHERE schemaname = 'public' AND indexname = 'ix_document_links_cycle';

  PERFORM _rec('C01', 'le cycle a ses colonnes, ses trois gardes et un index d''idempotence PARTIEL sur les seuls liens actifs',
    v_colonnes = 5 AND v_gardes = 3 AND v_partiel AND v_predicat AND v_histo = 1,
    format('colonnes=%s/5, gardes=%s/3, index partiel=%s, prédicat etat=actif=%s, index d''historique=%s',
           v_colonnes, v_gardes, v_partiel, v_predicat, v_histo));
END $$;

-- ═════════════════════════════════════════════════════════════
-- C02 — le rejeu d'un effet ACTIF : rien de plus, payload fusionné
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; n int; v jsonb; v_tour int; v_etat text;
BEGIN
  t := _mk_tenant('A312C02', false);
  a := gen_random_uuid(); b := gen_random_uuid();
  PERFORM _l312_lien(t, a, b, 'cycle.rejeu', NULL, '{"qte": 10}'::jsonb);
  PERFORM _l312_lien(t, a, b, 'cycle.rejeu', NULL, '{"depot": "W1"}'::jsonb);

  SELECT count(*), max(tour), max(etat) INTO n, v_tour, v_etat
  FROM document_links
  WHERE tenant_id = t AND amont_type = 'sales_orders' AND amont_id = a AND effet = 'cycle.rejeu';
  -- Le payload, tel qu'il est fusionné (aucun agrégat jsonb n'existe).
  SELECT payload INTO v FROM document_links
  WHERE tenant_id = t AND amont_type = 'sales_orders' AND amont_id = a AND effet = 'cycle.rejeu'
  ORDER BY tour LIMIT 1;

  PERFORM _rec('C02', 'le rejeu d''un effet ACTIF ne double rien, fusionne le payload et reste au tour 1',
    n = 1 AND v = '{"qte": 10, "depot": "W1"}'::jsonb AND v_tour = 1 AND v_etat = 'actif',
    format('lignes=%s, payload=%s, tour=%s, état=%s', n, v, v_tour, v_etat));
END $$;


-- ═════════════════════════════════════════════════════════════
-- C03 — la fermeture ciblée : datée, motivée, journalisée, et plus « intacte »
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; n int; v_etat text; v_motif text; v_ferme timestamptz;
        v_par uuid; v_deja boolean; v_intact boolean; n_evt int;
BEGIN
  t := _mk_tenant('A312C03', false);
  a := gen_random_uuid(); b := gen_random_uuid();
  PERFORM _l312_lien(t, a, b, 'cycle.rompu');

  n := chain_lien_rompre(t, 'sales_orders', a, 'cycle.rompu',
        'Commande C-312-0001 du 30/09/2026 annulée : l''effet tracé est retiré (règle cycle.rompu).');

  SELECT etat, motif, ferme_le, ferme_par INTO v_etat, v_motif, v_ferme, v_par
  FROM _l312_cycle(t, a, 'cycle.rompu') LIMIT 1;

  v_deja   := chain_deja_fait(t, 'sales_orders', a, 'cycle.rompu');
  v_intact := chain_integrity_ok(t, 'sales_orders', a, 'delivery_notes', b);

  SELECT count(*) INTO n_evt FROM _l312_evenements(t, 'chain.link_broken', a);

  PERFORM _rec('C03', 'fermer un lien le date, le motive, le signe, le journalise — et il n''est plus « déjà fait » ni « intact » (M-03)',
    n = 1 AND v_etat = 'rompu' AND v_motif LIKE '%annulée%' AND v_ferme IS NOT NULL
      AND NOT v_deja AND NOT v_intact AND n_evt = 1,
    format('fermés=%s, état=%s, motif=%s, fermé=%s, signé=%s, déjà_fait=%s, intact=%s, événements=%s',
           n, v_etat, left(COALESCE(v_motif, ''), 60), v_ferme IS NOT NULL, v_par IS NOT NULL,
           v_deja, v_intact, n_evt));
END $$;


-- ═════════════════════════════════════════════════════════════
-- C04 — le tour suivant : un lien REMPLACÉ, jamais réécrit
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; c uuid; n int; n_actifs int; v_ancien_aval uuid;
        v_nouvel_aval uuid; v_ancien_etat text; v_tour_max int;
BEGIN
  t := _mk_tenant('A312C04', false);
  a := gen_random_uuid(); b := gen_random_uuid(); c := gen_random_uuid();
  PERFORM _l312_lien(t, a, b, 'cycle.tour');
  PERFORM chain_lien_remplacer(t, 'sales_orders', a, 'cycle.tour',
    'Commande reconfirmée : la réservation est reproduite.');
  PERFORM _l312_lien(t, a, c, 'cycle.tour');

  SELECT count(*), count(*) FILTER (WHERE etat = 'actif'), max(tour)
    INTO n, n_actifs, v_tour_max FROM _l312_cycle(t, a, 'cycle.tour');

  SELECT aval_id, etat INTO v_ancien_aval, v_ancien_etat
  FROM _l312_cycle(t, a, 'cycle.tour') ORDER BY tour LIMIT 1;
  SELECT aval_id INTO v_nouvel_aval FROM _l312_cycle(t, a, 'cycle.tour') ORDER BY tour DESC LIMIT 1;

  PERFORM _rec('C04', 'après fermeture, le nouveau lien naît au TOUR 2 et l''ancien garde son aval et son état — « un lien remplacé, pas réécrit »',
    n = 2 AND n_actifs = 1 AND v_tour_max = 2 AND v_ancien_aval = b AND v_ancien_etat = 'remplace'
      AND v_nouvel_aval = c,
    format('lignes=%s (2 attendues), actifs=%s (1), tour max=%s (2), aval du tour 1 inchangé=%s, état du tour 1=%s, aval du tour 2 juste=%s',
           n, n_actifs, v_tour_max, v_ancien_aval = b, v_ancien_etat, v_nouvel_aval = c));
END $$;

-- ═════════════════════════════════════════════════════════════
-- C05 — `chain_avant` redevient VRAI après fermeture
--   C'est LE prérequis qui manquait (trouvaille §6.2 de la VAGUE-L1) : sans
--   lui, poser `chain_avant` sur un maillon qui se reproduit après annulation
--   faisait disparaître l'effet en silence (réservé = 0 au lieu de 10).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; v_avant boolean; v_apres boolean; n_ignore int;
BEGIN
  t := _mk_tenant('A312C05', false);
  a := gen_random_uuid(); b := gen_random_uuid();
  PERFORM _l312_lien(t, a, b, 'cycle.avant');

  -- Le maillon rejoué voit son effet déjà posé : il ne fait rien (et le trace).
  v_avant := chain_avant(t, 'sales_orders', 'confirmee', 'cycle.avant', 'sales_orders', a);

  -- Le maillon d'annulation ferme le lien, puis le maillon reprend.
  PERFORM chain_lien_remplacer(t, 'sales_orders', a, 'cycle.avant', 'Reprise après annulation.');
  v_apres := chain_avant(t, 'sales_orders', 'confirmee', 'cycle.avant', 'sales_orders', a);

  SELECT count(*) INTO n_ignore FROM chain_traces
  WHERE tenant_id = t AND effet = 'cycle.avant' AND resultat = 'ignore';

  PERFORM _rec('C05', 'chain_avant rend false tant que le lien est actif, et VRAI dès qu''il est fermé — l''effet peut être reproduit',
    NOT v_avant AND v_apres AND n_ignore = 1,
    format('avant fermeture=%s (false attendu), après fermeture=%s (true attendu), traces « ignore »=%s (1)', v_avant, v_apres, n_ignore));
END $$;


-- ═════════════════════════════════════════════════════════════
-- C06 — les refus nominatifs, et rien d'écrit quand c'est refusé
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; v_ok int := 0; v_dits text[] := ARRAY[]::text[];
        v_msg text; n_avant int; n_apres int;
BEGIN
  t := _mk_tenant('A312C06', false);
  a := gen_random_uuid(); b := gen_random_uuid();
  PERFORM _l312_lien(t, a, b, 'cycle.refus');
  SELECT count(*) INTO n_avant FROM _l312_cycle(t, a, 'cycle.refus');

  -- 1. Motif absent : la base refuse une fermeture muette.
  BEGIN
    PERFORM chain_lien_rompre(t, 'sales_orders', a, 'cycle.refus', '   ');
    v_dits := v_dits || 'motif vide : accepté';
  EXCEPTION WHEN check_violation THEN
    v_ok := v_ok + 1; v_dits := v_dits || ('motif vide : ' || left(SQLERRM, 50));
  END;

  -- 2. État inconnu : ce n'est pas un état de fermeture.
  BEGIN
    PERFORM chain_lien_fermer(t, 'sales_orders', a, 'cycle.refus', NULL, 'efface', 'motif');
    v_dits := v_dits || 'état inconnu : accepté';
  EXCEPTION WHEN invalid_parameter_value THEN
    v_ok := v_ok + 1; v_dits := v_dits || ('état inconnu : ' || left(SQLERRM, 50));
  END;

  -- 3. Aucun lien actif : le ciblé REFUSE, et le message nomme l'effet et le document.
  BEGIN
    PERFORM chain_lien_rompre(t, 'sales_orders', a, 'cycle.jamais.produit', 'Annulation.');
    v_dits := v_dits || 'sans lien : accepté';
  EXCEPTION WHEN check_violation THEN
    v_msg := SQLERRM;
    IF v_msg LIKE '%cycle.jamais.produit%' AND v_msg LIKE '%sales_orders%' THEN
      v_ok := v_ok + 1; v_dits := array_append(v_dits, 'sans lien : nominatif');
    END IF;
  END;

  SELECT count(*) INTO n_apres FROM _l312_cycle(t, a, 'cycle.refus');

  PERFORM _rec('C06', 'trois refus nominatifs (motif absent, état inconnu, aucun lien actif) et aucun lien fermé par erreur',
    v_ok = 3 AND n_apres = n_avant,
    format('%s/3 refus conformes, liens avant=%s après=%s — %s', v_ok, n_avant, n_apres, array_to_string(v_dits, ' | ')));
END $$;

-- ═════════════════════════════════════════════════════════════
-- C07 — la fermeture GLOBALE : tous les effets d'un document en un acte
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; n1 int; n2 int; n_actifs int; n_rompus int; n_evt int;
BEGIN
  t := _mk_tenant('A312C07', false);
  a := gen_random_uuid();
  PERFORM _l312_lien(t, a, gen_random_uuid(), 'cycle.global.ecriture');
  PERFORM _l312_lien(t, a, gen_random_uuid(), 'cycle.global.stock');

  n1 := chain_liens_fermer(t, 'sales_orders', a, 'rompu',
        'Commande annulée : les effets tracés sont retirés.');

  SELECT count(*) FILTER (WHERE etat = 'actif'), count(*) FILTER (WHERE etat = 'rompu')
    INTO n_actifs, n_rompus FROM document_links
  WHERE tenant_id = t AND amont_type = 'sales_orders' AND amont_id = a;

  SELECT count(*) INTO n_evt FROM domain_events
  WHERE tenant_id = t AND event_name = 'chain.link_broken' AND aggregate_id = a;

  -- Le second appel RAPPORTE 0 : un document sans effet actif se ferme « pour
  -- rien », et c'est légitime — contrairement au fermé ciblé, qui refuse.
  n2 := chain_liens_fermer(t, 'sales_orders', a, 'rompu', 'Deuxième annulation (rejeu).');

  PERFORM _rec('C07', 'la fermeture globale ferme les deux effets du document en un acte, journalise un événement par lien, et le rejeu rapporte 0 sans lever',
    n1 = 2 AND n_actifs = 0 AND n_rompus = 2 AND n_evt = 2 AND n2 = 0,
    format('premier appel=%s (2), actifs=%s, rompus=%s, événements=%s, second appel=%s (0)', n1, n_actifs, n_rompus, n_evt, n2));
END $$;


-- ═════════════════════════════════════════════════════════════
-- C08 — le cloisonnement : fermer chez A ne ferme rien chez B
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; a uuid; b uuid; n int; vus_b int; v_etat_b text;
BEGIN
  ta := _mk_tenant('A312C08a', false);
  a := gen_random_uuid();
  PERFORM _l312_lien(ta, a, gen_random_uuid(), 'cycle.iso');
  tb := _mk_tenant('A312C08b', false);          -- le contexte actif est désormais B
  b := gen_random_uuid();
  PERFORM _l312_lien(tb, b, gen_random_uuid(), 'cycle.iso');

  -- Fermer tous les liens de la société A : la clause de société porte sur
  -- l'ÉCRITURE (le lien de B doit rester actif), pas seulement sur la lecture.
  n := chain_liens_fermer(ta, 'sales_orders', a, 'rompu', 'Annulation chez A seulement.');

  SELECT count(*) INTO vus_b FROM document_links
   WHERE tenant_id = tb AND amont_id = b AND etat = 'actif';
  SELECT etat INTO v_etat_b FROM document_links WHERE tenant_id = tb AND amont_id = b;

  PERFORM _rec('C08', 'fermer les liens de la société A laisse ceux de B actifs (la clause de société est dans l''écriture)',
    n = 1 AND vus_b = 1 AND v_etat_b = 'actif',
    format('fermés chez A=%s (1), lien de B encore actif=%s, état de B=%s', n, vus_b, v_etat_b));
END $$;

-- ═════════════════════════════════════════════════════════════
-- C09 — les deux lectures du cycle
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; v_av uuid; l0 uuid; t0 int; l1 uuid; t1 int; l2 uuid; t2 int;
BEGIN
  t := _mk_tenant('A312C09', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  -- Avant tout : aucun lien actif, aucun tour.
  l0 := chain_lien_actif(t, 'sales_orders', a, 'cycle.lecture');
  t0 := chain_lien_tour(t, 'sales_orders', a, 'cycle.lecture');

  v_av := _l312_lien(t, a, b, 'cycle.lecture');
  l1 := chain_lien_actif(t, 'sales_orders', a, 'cycle.lecture');
  t1 := chain_lien_tour(t, 'sales_orders', a, 'cycle.lecture');

  PERFORM chain_lien_rompre(t, 'sales_orders', a, 'cycle.lecture', 'Annulation.');
  l2 := chain_lien_actif(t, 'sales_orders', a, 'cycle.lecture');
  t2 := chain_lien_tour(t, 'sales_orders', a, 'cycle.lecture');

  PERFORM _rec('C09', 'chain_lien_actif rend le lien vivant (NULL après fermeture) et chain_lien_tour le plus haut tour atteint',
    l0 IS NULL AND t0 = 0 AND l1 = v_av AND t1 = 1 AND l2 IS NULL AND t2 = 1,
    format('avant : actif=%s tour=%s | pendant : actif juste=%s tour=%s | après : actif=%s tour=%s',
           l0, t0, l1 = v_av, t1, l2, t2));
END $$;


-- ═════════════════════════════════════════════════════════════
-- C10 — les gardes structurelles mordent (la base, pas la revue)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; v_id uuid; v_ok int := 0; v_dits text[] := ARRAY[]::text[];
        v_active int;
BEGIN
  t := _mk_tenant('A312C10', false);
  a := gen_random_uuid(); b := gen_random_uuid();
  v_id := _l312_lien(t, a, b, 'cycle.garde');

  -- 1. Un lien ACTIF qui devient fermé SANS motif : refusé par la contrainte.
  BEGIN
    UPDATE document_links SET etat = 'rompu', ferme_le = now() WHERE id = v_id;
    v_dits := array_append(v_dits, 'fermé sans motif : accepté');
  EXCEPTION WHEN check_violation THEN
    v_ok := v_ok + 1; v_dits := array_append(v_dits, 'fermé sans motif : refusé');
  END;

  -- 2. Un lien fermé SANS motif dès l'insertion : refusé aussi.
  BEGIN
    INSERT INTO document_links (tenant_id, amont_type, amont_id, aval_type, aval_id,
                                link_type, effet, etat, ferme_le)
    VALUES (t, 'sales_orders', gen_random_uuid(), 'delivery_notes', gen_random_uuid(),
            'delivered_by', 'cycle.garde', 'rompu', now());
    v_dits := array_append(v_dits, 'insertion fermée sans motif : acceptée');
  EXCEPTION WHEN check_violation THEN
    v_ok := v_ok + 1; v_dits := array_append(v_dits, 'insertion muette : refusée');
  END;

  -- 3. DEUX liens ACTIFS sur la même clé : impossibles (index partiel).
  BEGIN
    INSERT INTO document_links (tenant_id, amont_type, amont_id, aval_type, aval_id,
                                link_type, effet, tour)
    VALUES (t, 'sales_orders', a, 'delivery_notes', gen_random_uuid(), 'delivered_by', 'cycle.garde', 2);
    v_dits := array_append(v_dits, 'second lien actif : accepté');
  EXCEPTION WHEN unique_violation THEN
    v_ok := v_ok + 1; v_dits := array_append(v_dits, 'second actif : refusé');
  END;

  SELECT count(*) INTO v_active FROM document_links
   WHERE tenant_id = t AND effet = 'cycle.garde' AND etat = 'actif';

  PERFORM _rec('C10', 'la base refuse une fermeture sans motif (par mise à jour ET par insertion) et interdit deux liens actifs sur la même clé',
    v_ok = 3 AND v_active = 1,
    format('%s/3 gardes ont mordu, liens actifs=%s (1) — %s', v_ok, v_active, array_to_string(v_dits, ' | ')));
END $$;

-- ═════════════════════════════════════════════════════════════
-- C11 — l'événement de fermeture dit quoi, qui, quel tour, pourquoi
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; v_id uuid; p jsonb;
BEGIN
  t := _mk_tenant('A312C11', false);
  a := gen_random_uuid(); b := gen_random_uuid();
  v_id := _l312_lien(t, a, b, 'cycle.evenement');

  PERFORM chain_lien_remplacer(t, 'sales_orders', a, 'cycle.evenement',
    'Commande reconfirmée le 30/09/2026.');

  SELECT payload INTO p FROM _l312_evenements(t, 'chain.link_superseded', a) LIMIT 1;

  PERFORM _rec('C11', 'l''événement de fermeture porte l''effet, le lien, le tour, l''état et le motif — la vue chaîne n''a rien à deviner',
    p -> 'effet' = to_jsonb('cycle.evenement'::text) AND p -> 'lien_id' = to_jsonb(v_id)
      AND p -> 'tour' = '1'::jsonb AND p -> 'etat' = to_jsonb('remplace'::text)
      AND (p ->> 'motif') LIKE '%reconfirmée%',
    format('payload=%s', p));
END $$;


-- ═════════════════════════════════════════════════════════════
-- C12 — LE ROUGE DE LA 230, joué sur le vrai flux
--
--   La trouvaille du lot L1 est née ici : la première version de la 311 appelait
--   `chain_avant` sur le maillon des réservations, et la suite 230 (T04) a rougi
--   — commande ANNULÉE puis RECONFIRMÉE : `réservé = 0` au lieu de 10, parce que
--   la clé du socle ne distinguait pas le rejeu de la reproduction légitime.
--
--   Ce scénario JOUE le geste que le maillon d'annulation posera au lot L3
--   (`chain_liens_fermer` au moment de l'annulation) et mesure, sur le flux
--   réel : l'effet est REPRODUIT par le métier, l'historique garde les DEUX
--   tours, et `chain_avant` — qui l'aurait empêché — rend vrai.
-- ═════════════════════════════════════════════════════════════

-- Deux articles en stock, un client : le gabarit de la 311, réduit au stock.
DROP FUNCTION IF EXISTS _l312_vente(text);
CREATE OR REPLACE FUNCTION _l312_vente(p_nom text, OUT t uuid, OUT wh uuid, OUT c uuid,
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

-- Commande à DEUX lignes, NON confirmée : chaque scénario choisit son moment.
DROP FUNCTION IF EXISTS _l312_cmd(uuid, uuid, uuid, uuid, text);
CREATE OR REPLACE FUNCTION _l312_cmd(p_t uuid, p_c uuid, p1 uuid, p2 uuid, p_num text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE so uuid;
BEGIN
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
  VALUES (p_t, 'CV-' || p_num, p_c, CURRENT_DATE, 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
  VALUES (p_t, so, p1, 'Ligne 1', 3, 20), (p_t, so, p2, 'Ligne 2', 4, 20);
  RETURN so;
END $$;


DO $$
DECLARE v record; so uuid; ligne1 uuid; v_deja_avant boolean; v_avant_faux boolean;
        v_deja_apres boolean; v_avant_vrai boolean; n_fermes int;
        n_liens int; n_actifs int; n_rompus int; n_tours int;
        n_res_actives int; n_ok int;
BEGIN
  v := _l312_vente('L3A');
  so := _l312_cmd(v.t, v.c, v.p1, v.p2, 'L3A');

  -- 1. La commande est confirmée par l'utilisateur : le maillon métier réserve
  --    les deux lignes et tisse les liens du tour 1.
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;

  SELECT id INTO ligne1 FROM sales_order_lines WHERE sales_order_id = so AND product_id = v.p1;

  -- 2. Retour au propriétaire : le socle n'est pas une API.
  PERFORM set_config('role', 'none', true);

  v_deja_avant := chain_deja_fait(v.t, 'sales_orders', so, 'sale.order.reserved', ligne1);
  v_avant_faux := chain_avant(v.t, 'sales_orders', 'confirmed', 'sale.order.reserved',
                              'sales_orders', so, ligne1);

  -- 3. LE GESTE DU LOT L3 : l'annulation ferme les liens tracés du document.
  n_fermes := chain_liens_fermer(v.t, 'sales_orders', so, 'rompu',
    'Commande CV-L3A annulée : les effets tracés sont retirés.');

  v_deja_apres := chain_deja_fait(v.t, 'sales_orders', so, 'sale.order.reserved', ligne1);
  v_avant_vrai := chain_avant(v.t, 'sales_orders', 'confirmed', 'sale.order.reserved',
                              'sales_orders', so, ligne1);

  -- 4. Le métier annule puis reconfirme — c'est exactement ce que la 230 (T04)
  --    fait rougir sans le cycle de vie.
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'cancelled' WHERE id = so;
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;

  -- 5. Les lectures, comme l'écran les fera (RLS de la société).
  SELECT count(*), count(*) FILTER (WHERE etat = 'actif'), count(*) FILTER (WHERE etat = 'rompu'),
         count(DISTINCT tour)
    INTO n_liens, n_actifs, n_rompus, n_tours
  FROM document_links
  WHERE tenant_id = v.t AND amont_type = 'sales_orders' AND amont_id = so
    AND effet = 'sale.order.reserved';

  SELECT count(*) INTO n_res_actives FROM stock_reservations
  WHERE tenant_id = v.t AND reference_id = so AND status = 'active';

  SELECT count(*) INTO n_ok
  FROM document_links l
  JOIN sales_order_lines sl ON sl.id = l.amont_ligne_id
  JOIN stock_reservations sr ON sr.id = l.aval_id
  WHERE l.tenant_id = v.t AND l.amont_id = so AND l.effet = 'sale.order.reserved'
    AND l.etat = 'actif' AND sr.product_id = sl.product_id AND sr.status = 'active';

  PERFORM _rec('C12',
    'commande annulée puis reconfirmée : la réservation est REPRODUITE (2 actives), l''historique garde les deux tours (2 rompus + 2 actifs) et chain_avant rend vrai après fermeture',
    v_deja_avant AND NOT v_avant_faux AND n_fermes = 2
      AND NOT v_deja_apres AND v_avant_vrai
      AND n_liens = 4 AND n_actifs = 2 AND n_rompus = 2 AND n_tours = 2
      AND n_res_actives = 2 AND n_ok = 2,
    format('avant fermeture : déjà_fait=%s chain_avant=%s | fermés=%s | après : déjà_fait=%s chain_avant=%s | liens=%s (actifs=%s, rompus=%s, tours=%s) réservations actives=%s correspondances=%s',
           v_deja_avant, v_avant_faux, n_fermes, v_deja_apres, v_avant_vrai,
           n_liens, n_actifs, n_rompus, n_tours, n_res_actives, n_ok));
END $$;

-- ─────────────────────────────────────────────────────────────
-- Le registre des échecs attendus reste VIDE : aucun scénario de ce fichier
-- n'a le droit d'échouer (doctrine AUD-A02).
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('312');

