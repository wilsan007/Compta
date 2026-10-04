-- ============================================================
-- 267_nf525_closure.sql — W10 : la clôture NF-525 aboutit, et elle se constate
--
-- MESURÉ AVANT (base neuve, 235 migrations, 0 erreur) :
--
--   * `close_nf525_period('2026-09')` échouait TOUJOURS :
--       ERROR: NF525: Le journal d'événements est inaltérable. Modification interdite.
--       CONTEXT: PL/pgSQL function prevent_nf525_modification() line 3 at RAISE
--     Le corps faisait `UPDATE nf525_event_log SET closed = true` en comptant sur
--     `SECURITY DEFINER` pour « contourner » le déclencheur — ce qu'un
--     déclencheur ne fait pas : il s'exécute quelle que soit la sécurité de la
--     fonction, et celui-ci lève sans condition (`nf525_no_update`,
--     `BEFORE UPDATE FOR EACH ROW`).
--
--   * le drapeau `closed` ainsi écrit n'était **lu par personne** : vérifié sur
--     les 235 migrations, aucun lecteur de `nf525_event_log.closed`.
--
--   * **rien** n'insérait dans `nf525_period_closures` — la table que
--     `get_nf525_attestation` interroge (`SELECT … FROM nf525_period_closures
--     WHERE tenant_id = … AND period = …`, puis `RAISE EXCEPTION 'Période non
--     clôturée'`). L'attestation ne pouvait donc pas aboutir, même après une
--     clôture réussie.
--
-- CE QUE LA MIGRATION POSE (append-only, comme l'exige NF-525) :
--
--   1. la clôture n'ÉCRIT PLUS dans le journal — elle AJOUTE l'événement
--      `period_close` (le journal d'événements est inaltérable : c'est sa
--      définition, pas une contrainte à contourner) et inscrit la clôture là où
--      elle se lit, `nf525_period_closures` : période, nombre d'événements,
--      empreinte de clôture, auteur, date ;
--
--   2. une période sans événement n'est pas clôturable — clôturer le vide ne
--      prouve rien (le message le dit) ;
--
--   3. une période déjà clôturée est refusée explicitement (l'unicité
--      `(tenant_id, period)` de la 91 le garantit déjà ; l'erreur devient lisible
--      pour l'écran, qui l'affiche telle quelle) ;
--
--   4. le format est celui que les déclencheurs écrivent : `YYYY-MM`
--      (`to_char(now(), 'YYYY-MM')`, `to_char(NEW.date, 'YYYY-MM')`) — vérifié
--      avant d'écrire, pour refuser une date au lieu de clôturer une période vide.
--
-- LIMITE DITE : cette migration n'interdit pas d'AJOUTER un événement à une
-- période déjà clôturée. Un tel refus rétroactif changerait le sort d'une vente
-- ou d'une facture saisie après coup : c'est une décision de gestion, pas un
-- correctif — elle n'est pas prise ici. L'attestation, elle, re-vérifie la chaîne
-- et recompte les événements au moment où elle est demandée
-- (`verify_nf525_chain`), donc une clôture suivie d'écritures est visible.
-- ============================================================

CREATE OR REPLACE FUNCTION public.close_nf525_period(p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_uid uuid := auth.uid();
  v_count integer;
  v_last_hash text;
  v_closing_hash text;
  v_hash_input text;
  v_closed_at timestamptz := now();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Le format est celui que les déclencheurs du journal écrivent : AAAA-MM.
  -- Une date ('2026-09-30') désignerait une période qui n'existe pas.
  IF p_period IS NULL OR p_period !~ '^[0-9]{4}-[0-9]{2}$' THEN
    RAISE EXCEPTION 'Période NF525 invalide : % (format attendu AAAA-MM)', COALESCE(p_period, 'NULL');
  END IF;

  IF EXISTS (SELECT 1 FROM nf525_period_closures WHERE tenant_id = v_tid AND period = p_period) THEN
    RAISE EXCEPTION 'Période déjà clôturée : %', p_period;
  END IF;

  SELECT count(*), COALESCE(max(current_hash), 'EMPTY')
  INTO v_count, v_last_hash
  FROM nf525_event_log
  WHERE tenant_id = v_tid AND period = p_period;

  IF v_count = 0 THEN
    RAISE EXCEPTION 'Aucun événement pour la période % : il n''y a rien à clôturer', p_period;
  END IF;

  v_hash_input := 'CLOSE|' || p_period || '|' || v_tid::text || '|' || v_last_hash || '|' || v_count;
  v_closing_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

  -- La clôture se CONSTATE : une ligne, une empreinte, un auteur, une date.
  INSERT INTO nf525_period_closures (tenant_id, period, event_count, closing_hash, closed_by, closed_at)
  VALUES (v_tid, p_period, v_count, v_closing_hash, v_uid, v_closed_at);

  -- Et elle s'ajoute au journal (jamais l'inverse) : l'événement de clôture fait
  -- partie de la chaîne, il ne la réécrit pas.
  PERFORM log_nf525_event(
    'period_close',
    'nf525_period',
    NULL,
    jsonb_build_object('period', p_period, 'event_count', v_count, 'closing_hash', v_closing_hash),
    NULL,
    p_period
  );

  RETURN jsonb_build_object(
    'period', p_period,
    'event_count', v_count,
    'closing_hash', v_closing_hash,
    'closed_at', v_closed_at
  );
END;
$function$;
