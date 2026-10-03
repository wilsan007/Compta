-- ═══════════════════════════════════════════════════════════════════════
-- 422 — L20, tranche 1 : LE RETOUR EN ARRIÈRE, QUI N'EXISTAIT PAS
-- ═══════════════════════════════════════════════════════════════════════
--
-- M-04 (§ Plan, phase F) : « tout effet paramétrique se RÉGÉNÈRE ; on ne
-- corrige jamais une ligne à la main », et la régénération se fait
-- « avec HISTORIQUE et POSSIBILITÉ DE REVENIR À LA VERSION PRÉCÉDENTE ».
--
-- MESURÉ AVANT, sur la base du jour — et la mesure est plus grote que
-- l'absence de la fonction :
--
--   * `chain_regeneration_log` existe depuis la 252 (le socle a anticipé
--     L20) : 9 colonnes, dont `avant` et `apres`. Elle a 2 lignes — les
--     siennes, celles de sa propre suite T13.
--   * `chain_regenerate(...)` existe aussi, et il ne fait QUE journaliser :
--     il photographie les payloads des liens, écrit une ligne, émet
--     `chain.regenerated`, rend l'id. **Il ne régénère rien** — c'est
--     assumé et figé par la suite 252 T13, qui passe `apres` en argument
--     et n'exige aucune preuve. On ne touche pas à ce contrat : il
--     appartient au socle, et la 422 n'est pas son lot.
--   * **`ZÉRO` fonction de retour arrière** : ni rollback, ni revert,
--     ni annulation. Le `avant` que la 252 écrit depuis trois semaines est
--     donc une donnée que PERSONNE ne peutattaquer.
--
-- LE DÉFAUT, FORMULÉ : on peut régénérer, l'historique s'écrit, et on ne
-- peut pas revenir en arrière — alors que c'est la moitié de la phrase du
-- plan, et la moitié qui protège : sans retour, une régénération est un
-- aller simple, donc une décision irréversible déguisée en édition.
--
-- LES HUIT SCÉNARIOS.
--   T01  le retour arrière existe et RESTAURE l'état précédent ;
--   T02  sans société, refus (le cloisonnement ne s'ouvre pas) ;
--   T03  un id inconnu, ou d'une AUTRE société, est refusé nommé ;
--   T04  CONFLIT — si l'état vivant n'est plus celui qu'on croyait, le
--        retour REFUSE et ne détruit rien ;
--   T05  il se journalise lui-même et émet son événement ;
--   T06  un DEUXIÈME retour est refusé : aucun double effet ;
--   T07  un lien ROMPU n'est pas ressuscité par un retour arrière ;
--   T08  l'historique se relit : avant, après, et l'état vivant restauré.
--
-- ⚠️ LE CONFLIT EST LE CŒUR, ET IL EST CONÇU, PAS AJOUTÉ.
-- `chain_regenerate` prend `apres` DE L'APPELLANT : la 252 T13 passe
-- `{"prix": 12}` pendant que le lien vit porte encore `{"prix": 10}`.
-- `apres` est donc une DÉCLARATION, pas un constat — on ne peut pas s'y
-- fier pour détecter que l'état a bougé depuis. Le rollback exige alors
-- que l'appelant DÉCLARE l'état vivant attendu (`p_attendu`) et refuse si
-- le réel ne colle pas : c'est de la concurrence optimiste, et c'est la
-- seule honnête quand le journal ne sait pas dire la vérité. Refuser ici
-- est le comportement correct — l'alternative écraserait un travail plus
-- récent sous couvert d'un retour arrière.
-- ═══════════════════════════════════════════════════════════════════════

SELECT set_config('audit.file', '422', false);

-- ⚠️ CE DÉCOR EST AUTONOME, ET C'EST DÉLIBÉRÉ.
-- La 450 pose deux clés étrangères composites : un lien de chaîne doit
-- s'appuyer sur de VRAIES pièces, sinon `link_documents` refuse (23503).
-- On insère donc les deux documents nous-mêmes, plutôt que d'appeler le
-- `_p5_doc` de la suite 252 — une preuve qui dépend du décor d'une autre
-- preuve cesse d'en être une le jour où cette autre suite change.
CREATE OR REPLACE FUNCTION _doc422(p_t uuid, p_type text, p_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_t IS NULL OR p_id IS NULL THEN RETURN; END IF;
  IF p_type = 'sales_orders' THEN
    INSERT INTO sales_orders (id, tenant_id, number, status)
    VALUES (p_id, p_t, 'L20-' || p_id::text, 'draft')
    ON CONFLICT (id) DO NOTHING;
  ELSIF p_type = 'delivery_notes' THEN
    INSERT INTO delivery_notes (id, tenant_id, number, status)
    VALUES (p_id, p_t, 'L20-' || p_id::text, 'pending')
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION _lien422(p_t uuid, p_amont uuid, p_aval uuid,
                                   p_effet text, p_payload jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  PERFORM _doc422(p_t, 'sales_orders', p_amont);
  PERFORM _doc422(p_t, 'delivery_notes', p_aval);
  RETURN link_documents(p_t, 'sales_orders', p_amont, 'delivery_notes', p_aval,
                        p_effet, 'delivered_by', p_payload, NULL, NULL);
END $$;

-- L'état VIVANT des liens d'un effet : c'est le « avant » que la 252
-- photographie, et c'est donc la forme que `p_attendu` doit reprendre.
CREATE OR REPLACE FUNCTION _l420_vivant(p_t uuid, p_amont_type text,
                                        p_amont_id uuid, p_effet text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT COALESCE(jsonb_agg(dl.payload ORDER BY dl.created_at, dl.id), '[]'::jsonb)
    FROM document_links dl
   WHERE dl.tenant_id = p_t
     AND dl.amont_type = p_amont_type
     AND dl.amont_id = p_amont_id
     AND dl.effet = p_effet;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- T01 — le retour arrière existe, et restaure l'état précédent
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; lk uuid; v_log bigint; v_rb bigint;
        v_vivant jsonb;
BEGIN
  t := _mk_tenant('L20T01', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  lk := _lien422(t, a, b, 'prix.achat', '{"cout": 10}'::jsonb);
  v_log := chain_regenerate(t, 'prix.achat', 'sales_orders', a,
                            'prix de revient corrigé', '{"cout": 12}'::jsonb);

  -- la régénération est faite « à la main » : le lien porte le nouveau prix
  UPDATE document_links SET payload = '{"cout": 12}'::jsonb WHERE id = lk;
  v_vivant := _l420_vivant(t, 'sales_orders', a, 'prix.achat');

  -- RETOUR : on déclare l'état vivant attendu, et on revient au prix d'avant
  v_rb := chain_regeneration_rollback(t, v_log, v_vivant);

  PERFORM _rec('T01', 'le retour arrière existe et restaure l''état précédent — l''historique n''est plus une impasse',
    v_rb IS NOT NULL
    AND (SELECT dl.payload FROM document_links dl WHERE dl.id = lk) = '{"cout": 10}'::jsonb,
    format('id retour=%s, lien revenu à %s (on attendait {"cout": 10})',
           v_rb, (SELECT dl.payload FROM document_links dl WHERE dl.id = lk)));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T02 — sans société, refus : le cloisonnement ne s'ouvre pas
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_refus boolean := false; v_msg text;
BEGIN
  BEGIN PERFORM chain_regeneration_rollback(NULL, 1, '[]'::jsonb);
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  PERFORM _rec('T02', 'sans société, le retour arrière est REFUSÉ — une absence de cloisonnement n''est pas un retour',
    v_refus AND v_msg LIKE '%société%',
    format('refus=%s (%s)', v_refus, left(COALESCE(v_msg,''), 70)));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T03 — un id inconnu, ou d'une AUTRE société, est refusé NOMMÉ
--      (deux sociétés, deux journaux : celui de l'une ne commande rien
--       sur celui de l'autre)
--
-- ⚠️ L'ORDRE EST VOLONTAIRE. `_mk_tenant` POSE le contexte de session :
-- c'est le contexte, et non le paramètre, qui fait foi (garde 1b). On
-- teste donc l'id inconnu PENDANT que le contexte est celui de t1, et on
-- ne crée t2 qu'ensuite — à ce moment le contexte bascule, et le refus
-- devient une preuve plutôt qu'un accident de mise en scène.
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE t1 uuid; t2 uuid; a1 uuid; a2 uuid; b1 uuid; b2 uuid;
        v_log1 bigint; v_lien1 uuid;
        v_refus boolean := false; v_msg text;
        v_refus2 boolean := false; v_msg2 text;
BEGIN
  t1 := _mk_tenant('L20T03A', false);
  a1 := gen_random_uuid(); b1 := gen_random_uuid();

  v_lien1 := _lien422(t1, a1, b1, 'prix.achat', '{"cout": 10}'::jsonb);
  v_log1  := chain_regenerate(t1, 'prix.achat', 'sales_orders', a1,
                              'prix corrigé', '{"cout": 12}'::jsonb);
  UPDATE document_links SET payload = '{"cout": 12}'::jsonb WHERE id = v_lien1;

  -- un id qui n'existe pas — contexte = t1, paramètre = t1
  BEGIN PERFORM chain_regeneration_rollback(t1, -1, '[]'::jsonb);
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  -- on bascule le contexte sur t2 : maintenant, demander le journal de t1
  -- est exactement ce que ferait un utilisateur de t2 pour toucher t1.
  t2 := _mk_tenant('L20T03B', false);
  BEGIN PERFORM chain_regeneration_rollback(t2, v_log1, '[]'::jsonb);
  EXCEPTION WHEN check_violation THEN v_refus2 := true; v_msg2 := SQLERRM; END;

  PERFORM _rec('T03', 'un id inconnu, ou d''une autre société, est REFUSÉ nommé — le journal d''une société ne commande rien sur celle d''autre',
    v_refus AND v_msg ILIKE '%inconnue%'
    AND v_refus2 AND v_msg2 ILIKE '%société%'
    AND (SELECT dl.payload FROM document_links dl WHERE dl.id = v_lien1) = '{"cout": 12}'::jsonb,
    format('inconnu=%s (%s) | autre société=%s (%s) | lien A intact=%s',
           v_refus, left(COALESCE(v_msg,''), 34), v_refus2, left(COALESCE(v_msg2,''), 34),
           (SELECT dl.payload FROM document_links dl WHERE dl.id = v_lien1)));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T04 — CONFLIT : si l'état vivant n'est plus celui qu'on croyait,
--      le retour REFUSE et ne détruit RIEN.
--      C'est le scénario qui vaut le lot : c'est lui qui empêche un
--      retour « bien intentionné » d'écraser le travail de quelqu'un.
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; lk uuid; v_log bigint;
        v_refus boolean := false; v_msg text;
BEGIN
  t := _mk_tenant('L20T04', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  lk := _lien422(t, a, b, 'prix.achat', '{"cout": 10}'::jsonb);
  v_log := chain_regenerate(t, 'prix.achat', 'sales_orders', a,
                            'prix corrigé', '{"cout": 12}'::jsonb);

  -- le lien a été régénéré (12), puis quelqu'un d'AUTRE a encore bougé (15)
  UPDATE document_links SET payload = '{"cout": 15}'::jsonb WHERE id = lk;

  -- le retour arrière part sur la conviction que c'est 12 : c'est FAUX
  BEGIN PERFORM chain_regeneration_rollback(t, v_log, '[{"cout": 12}]'::jsonb);
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  PERFORM _rec('T04', 'CONFLIT — un retour arrière qui ne correspond plus à l''état vivant est REFUSÉ, et rien n''est détruit',
    v_refus AND v_msg ILIKE '%conflit%'
    AND (SELECT dl.payload FROM document_links dl WHERE dl.id = lk) = '{"cout": 15}'::jsonb,
    format('refus=%s (%s) — lien laissé à %s (le travail le plus récent survit)',
           v_refus, left(COALESCE(v_msg,''), 60),
           (SELECT dl.payload FROM document_links dl WHERE dl.id = lk)));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T05 — le retour se JOURNALISE et émet son propre événement
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; lk uuid; v_log bigint; v_rb bigint;
        v_cause text; v_evt int; v_lignes int;
BEGIN
  t := _mk_tenant('L20T05', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  lk := _lien422(t, a, b, 'prix.achat', '{"cout": 10}'::jsonb);
  v_log := chain_regenerate(t, 'prix.achat', 'sales_orders', a,
                            'prix corrigé', '{"cout": 12}'::jsonb);
  UPDATE document_links SET payload = '{"cout": 12}'::jsonb WHERE id = lk;
  v_rb := chain_regeneration_rollback(t, v_log, '[{"cout": 12}]'::jsonb);

  SELECT cause INTO v_cause FROM chain_regeneration_log WHERE id = v_rb;
  SELECT count(*) INTO v_evt FROM domain_events de
   WHERE de.tenant_id = t AND de.event_name = 'chain.regeneration_reverted';
  -- le journal porte les DEUX temps : la régénération ET son retour
  SELECT count(*) INTO v_lignes FROM chain_regeneration_log crl
   WHERE crl.tenant_id = t AND crl.amont_id = a;

  PERFORM _rec('T05', 'le retour arrière se journalise LUI-MÊME et émet son événement — un retour qui ne se voit pas est un retour qu''on rejoue',
    v_rb IS NOT NULL AND v_cause LIKE '%retour%'
    AND v_evt = 1 AND v_lignes = 2,
    format('cause=%s, événements chain.regeneration_reverted=%s, lignes au journal=%s (on attend 2)',
           left(COALESCE(v_cause,''), 34), v_evt, v_lignes));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T06 — un DEUXIÈME retour est REFUSÉ : aucun double effet
--      (sans ce garde, un retour rejoué réécrit l'historique deux fois
--       et un rejeu de script deviendrait une seconde régénération)
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; lk uuid; v_log bigint;
        v_refus boolean := false; v_msg text;
BEGIN
  t := _mk_tenant('L20T06', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  lk := _lien422(t, a, b, 'prix.achat', '{"cout": 10}'::jsonb);
  v_log := chain_regenerate(t, 'prix.achat', 'sales_orders', a,
                            'prix corrigé', '{"cout": 12}'::jsonb);
  UPDATE document_links SET payload = '{"cout": 12}'::jsonb WHERE id = lk;
  PERFORM chain_regeneration_rollback(t, v_log, '[{"cout": 12}]'::jsonb);

  -- on rejoue : le lien est DÉJÀ revenu à 10. Le régénérer serait
  -- acceptable, le REVENIR une seconde fois ne l'est pas.
  BEGIN PERFORM chain_regeneration_rollback(t, v_log, '[{"cout": 10}]'::jsonb);
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  PERFORM _rec('T06', 'un SECOND retour arrière est REFUSÉ — l''état visé est déjà celui qui est en place',
    v_refus AND v_msg ILIKE '%déjà%'
    AND (SELECT dl.payload FROM document_links dl WHERE dl.id = lk) = '{"cout": 10}'::jsonb,
    format('refus=%s (%s) — lien à %s',
           v_refus, left(COALESCE(v_msg,''), 55),
           (SELECT dl.payload FROM document_links dl WHERE dl.id = lk)));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T07 — un lien ROMPU n'est pas ressuscité par un retour arrière.
--      Le cycle du lien (312) dit qu'un lien rompu est rompu : un retour
--      arrière ne « répare » pas une chaîne, il en remet une à son état
--      antérieur. Le confondre serait inventer une quatrième transition.
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; lk uuid; v_log bigint; v_rb bigint;
        v_etat text;
BEGIN
  t := _mk_tenant('L20T07', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  lk := _lien422(t, a, b, 'prix.achat', '{"cout": 10}'::jsonb);
  v_log := chain_regenerate(t, 'prix.achat', 'sales_orders', a,
                            'prix corrigé', '{"cout": 12}'::jsonb);
  UPDATE document_links SET payload = '{"cout": 12}'::jsonb WHERE id = lk;
  -- Le maillon casse la chaîne : le lien passe « rompu ». ⚠️ le CHECK de la
  -- 453 exige, pour tout lien non actif, une date de fermeture ET un motif :
  --  on ne fabrique pas un état de transition partiel.
  UPDATE document_links
     SET etat = 'rompu', ferme_le = now(), motif = 'effet retiré'
   WHERE id = lk;

  -- le retour s'exécute (les payloads reviennent) mais NE ressuscite pas
  v_rb := chain_regeneration_rollback(t, v_log, '[{"cout": 12}]'::jsonb);

  SELECT etat INTO v_etat FROM document_links WHERE id = lk;

  PERFORM _rec('T07', 'un lien ROMPU n''est pas ressuscité par un retour arrière — revenir en arrière n''est pas réparer',
    v_rb IS NOT NULL AND v_etat = 'rompu'
    AND (SELECT dl.payload FROM document_links dl WHERE dl.id = lk) = '{"cout": 10}'::jsonb,
    format('retour=%s, état du lien=%s (il doit rester rompu), payload=%s',
           v_rb, v_etat, (SELECT dl.payload FROM document_links dl WHERE dl.id = lk)));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T08 — l'historique se RELIT : avant, après, et l'état vivant.
--      C'est la promesse de « historique » : on peut relire ce qui s'est
--      passé, et pas seulement le laisser exister dans une table.
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; a uuid; b uuid; lk uuid; v_log bigint; v_rb bigint;
        v_avant jsonb; v_apres jsonb; v_cause text; v_vivant jsonb;
BEGIN
  t := _mk_tenant('L20T08', false);
  a := gen_random_uuid(); b := gen_random_uuid();

  lk := _lien422(t, a, b, 'prix.achat', '{"cout": 10}'::jsonb);
  v_log := chain_regenerate(t, 'prix.achat', 'sales_orders', a,
                            'prix corrigé', '{"cout": 12}'::jsonb);
  UPDATE document_links SET payload = '{"cout": 12}'::jsonb WHERE id = lk;
  v_rb := chain_regeneration_rollback(t, v_log, '[{"cout": 12}]'::jsonb);

  SELECT avant, apres INTO v_avant, v_apres FROM chain_regeneration_log WHERE id = v_log;
  SELECT cause INTO v_cause FROM chain_regeneration_log WHERE id = v_rb;
  v_vivant := _l420_vivant(t, 'sales_orders', a, 'prix.achat');

  PERFORM _rec('T08', 'l''historique se relit : AVANT, APRÈS, la cause du retour, et l''état vivant restauré',
    v_avant = '[{"cout": 10}]'::jsonb
    AND v_apres = '{"cout": 12}'::jsonb
    AND v_cause LIKE '%retour%'
    AND v_vivant = '[{"cout": 10}]'::jsonb,
    format('avant=%s après(déclaré)=%s cause retour=%s, état vivant relu=%s',
           v_avant, v_apres, left(COALESCE(v_cause,''), 26), v_vivant));
END $$;

DROP FUNCTION _lien422(uuid, uuid, uuid, text, jsonb);
DROP FUNCTION _doc422(uuid, text, uuid);
DROP FUNCTION _l420_vivant(uuid, text, uuid, text);
SELECT _audit_assert('422');