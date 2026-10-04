-- ============================================================
-- 233_nf525_chain.sql — H11 : le contrôle d'intégrité criait au loup à chaque appel
--
-- CONSTAT, mesuré le 24/09 sur base neuve. Trois événements écrits à la suite,
-- aucune suppression, aucune altération :
--     verify_nf525_chain() → total=3, liens rompus=0, sauts=3, chaîne invalide
--     détails : after_id = before_id = 4516, missing_count = -1 (trois fois)
-- La cause tient en une ligne : `v_last_id := v_rec.id` était exécutée AVANT le
-- contrôle de continuité, qui comparait donc la ligne à elle-même
-- (`id <> id + 1`, toujours vrai). Le journal fiscal NF-525 d'une société
-- saine se déclarait invalide à chaque vérification.
--
-- SECOND DÉFAUT, de conception celui-là : `chain_valid` exigeait zéro saut
-- d'identifiant. Or un saut arrive sans la moindre suppression — mesuré : une
-- transaction annulée consomme son numéro de séquence (log 4519, ROLLBACK sur
-- 4520, log 4521). Même l'arithmétique corrigée, la chaîne serait déclarée
-- invalide à la première transaction annulée de la journée.
--
-- CE QUI PROUVE UNE ALTÉRATION reste le chaînage : le `previous_hash` d'un
-- événement doit être le `current_hash` du précédent, et le contenu doit
-- redonner son propre hachage. Les sauts sont comptés, détaillés et expliqués —
-- un signal à instruire, pas un verdict.
--
-- LIMITE, dite ici faute de pouvoir la lever : supprimer le DERNIER maillon ne
-- casse aucun chaînage (il n'a pas de successeur). Seul un ancrage extérieur
-- (compteur scellé, horodatage tiers) le détecterait ; `gap_count` n'y suffit
-- pas puisqu'un ROLLBACK en produit aussi.
-- ============================================================

CREATE OR REPLACE FUNCTION public.verify_nf525_chain(p_from_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_total_count integer := 0;
  v_broken_count integer := 0;
  v_gap_count integer := 0;
  v_first_id bigint;
  v_last_id bigint := NULL;
  v_prev_id bigint := NULL;
  v_last_seen_hash text := NULL;
  v_hash_input text;
  v_expected_hash text;
  v_details jsonb := '[]'::jsonb;
  v_rec RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  FOR v_rec IN
    SELECT id, previous_hash, current_hash, event_type, entity_type, entity_id, event_date, tenant_id
    FROM nf525_event_log
    WHERE tenant_id = v_tid
      AND (p_from_date IS NULL OR event_date >= p_from_date)
      AND (p_to_date IS NULL OR event_date <= p_to_date)
    ORDER BY id ASC
  LOOP
    v_total_count := v_total_count + 1;
    IF v_total_count = 1 THEN
      v_first_id := v_rec.id;
    END IF;
    v_last_id := v_rec.id;

    -- LOT5-01 : Vérifier que previous_hash == current_hash de l'enregistrement précédent
    IF v_last_seen_hash IS NOT NULL
       AND v_rec.previous_hash IS DISTINCT FROM v_last_seen_hash THEN
      v_broken_count := v_broken_count + 1;
      v_details := v_details || jsonb_build_object(
        'error', 'CHAIN_FORK_OR_MISSING_LINK',
        'event_id', v_rec.id,
        'expected_prev', v_last_seen_hash,
        'actual_prev', v_rec.previous_hash
      )::jsonb;
    END IF;
    v_last_seen_hash := v_rec.current_hash;

    -- 233 : la continuité des identifiants se mesure contre la ligne PRÉCÉDENTE.
    -- Avant, v_last_id venait d'être écrasé par l'identifiant courant : la
    -- comparaison `v_rec.id <> v_last_id + 1` se lisait `id <> id + 1`, vraie
    -- pour TOUTE ligne. Une chaîne intacte de trois événements rendait donc
    -- « 3 sauts, chaîne invalide », avec after_id = before_id et
    -- missing_count = -1. Un contrôle qui crie au loup à chaque appel ne
    -- protège rien : plus personne ne distingue la vraie altération.
    IF v_prev_id IS NOT NULL AND v_rec.id <> v_prev_id + 1 THEN
      v_gap_count := v_gap_count + 1;
      v_details := v_details || jsonb_build_object(
        'error', 'ID_GAP_DETECTED',
        'after_id', v_prev_id,
        'before_id', v_rec.id,
        'missing_count', (v_rec.id - v_prev_id - 1),
        'note', 'Un saut d''identifiant signale une suppression OU une transaction annulée : la séquence consomme son numéro même en cas de ROLLBACK. À rapprocher des liens rompus, qui, eux, prouvent une altération.'
      )::jsonb;
    END IF;
    v_prev_id := v_rec.id;

    -- Recalculer le hash attendu pour vérifier l'intégrité du contenu
    v_hash_input := COALESCE(v_rec.previous_hash, 'GENESIS') || '|' ||
      v_rec.event_type || '|' ||
      v_rec.entity_type || '|' ||
      COALESCE(v_rec.entity_id::text, '') || '|' ||
      v_rec.tenant_id::text || '|' ||
      extract(epoch FROM v_rec.event_date)::text;

    v_expected_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

    IF v_expected_hash != v_rec.current_hash THEN
      v_broken_count := v_broken_count + 1;
      v_details := v_details || jsonb_build_object(
        'error', 'HASH_MISMATCH',
        'event_id', v_rec.id,
        'expected_hash', v_expected_hash,
        'actual_hash', v_rec.current_hash
      )::jsonb;
    END IF;
  END LOOP;

  -- 233 : `chain_valid` ne dépend plus des sauts d'identifiant. Mesuré : une
  -- transaction annulée consomme son numéro de séquence (4519 → 4521 sans
  -- aucune suppression), donc un saut arrive en exploitation normale. Ce qui
  -- prouve une altération, c'est le chaînage : le `previous_hash` d'un
  -- événement doit être le `current_hash` du précédent, et le contenu doit
  -- redonner son propre hachage. Les sauts restent comptés et détaillés — un
  -- signal à instruire, pas un verdict.
  RETURN jsonb_build_object(
    'total_events', v_total_count,
    'broken_links', v_broken_count,
    'gap_count', v_gap_count,
    'chain_valid', (v_broken_count = 0),
    'first_event_id', v_first_id,
    'last_event_id', v_last_id,
    'details', v_details,
    'verified_at', now()
  );
END;
$function$
