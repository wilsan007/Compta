-- ============================================================
-- 258_payment_reminders_idempotent.sql — une relance part une fois, et elle
--                                        se sait envoyée (EF-01, EF-02)
--
-- MESURÉ (audit du 23/09) sur `cron-payment-reminders`, qui tourne **tous les
-- jours à 9 h** :
--
--   EF-01  `.single()` sur une recherche d'antériorité qui ne trouve rien
--          renvoie `PGRST116` ; `if (error) throw error` interrompt **tout le
--          cron** dès la première facture en retard. Aucune relance n'est
--          jamais partie, et le cron échouait chaque jour.
--   EF-02  Même en franchissant ce point, l'enregistrement de la relance
--          échouait sur trois colonnes inexistantes (corrigées par la 257) —
--          sans lire l'erreur. Le lendemain, le test « a-t-on déjà relancé ? »
--          ne trouvait toujours rien : **le client recevait la même relance
--          tous les jours**, niveaux « MISE EN DEMEURE » et « poursuites »
--          compris.
--
-- Deux défauts de structure s'ajoutaient, mesurés sur la table :
--   * `reminder_level` était borné à 3 ; le niveau 4 (≥ 60 jours) ne pouvait
--     pas être enregistré — corrigé par la 257 ;
--   * `status` refusait `pending` et `failed` — corrigé par la 257 aussi.
--     Sans ces deux énumérations élargies, **la relance ne pouvait pas être
--     tracée**, quel que soit le code.
--
-- CE QUE CE FICHIER POSE
--   1. **la reprise des doublons déjà envoyés** : plusieurs relances du même
--      niveau pour la même facture sont ramenées à une — la première est
--      conservée, les suivantes passent à `cancelled` avec la raison en notes.
--      Aucune ligne n'est supprimée : l'historique de ce qui a été envoyé à
--      tort reste lisible ;
--   2. **l'unicité** (société, facture, niveau) parmi les relances non
--      annulées : un doublon devient impossible, pas seulement improbable ;
--   3. `claim_collection_reminder()` — **la prise de la relance avant l'envoi**.
--      Un envoi déjà parti (ou en cours) rend `NULL` : le cron ne renvoie rien.
--      Un envoi en échec, lui, peut être repris (l'échec ne prive pas le
--      client de sa relance) ;
--   4. `finalize_collection_reminder()` — **un seul chemin** pour dire
--      « envoyée » ou « en échec », avec l'heure réelle et l'erreur du
--      prestataire, depuis l'état `pending` uniquement.
--
-- Les deux RPC sont réservées au `service_role` (le cron) : un écran n'a pas à
-- se déclarer « relance envoyée ».
-- ============================================================

-- ── 1. Reprise : plusieurs relances du même niveau → une ───────────────────
DO $$
DECLARE v_n int;
BEGIN
  WITH classees AS (
    SELECT id,
           row_number() OVER (
             PARTITION BY tenant_id, invoice_id, reminder_level
             ORDER BY (status = 'sent') DESC, created_at NULLS LAST, id
           ) AS rang
    FROM public.collection_reminders
    WHERE invoice_id IS NOT NULL AND status <> 'cancelled'
  )
  UPDATE public.collection_reminders c
     SET status = 'cancelled',
         notes = COALESCE(NULLIF(c.notes, '') || ' | ', '')
                 || '258 (W6) : doublon de relance du même niveau — ramenée à une seule,'
                 || ' la relance conservée est celle dont l''envoi a été prouvé.'
    FROM classees r
   WHERE c.id = r.id AND r.rang > 1;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN
    RAISE NOTICE '258 : % relance(s) en double ramenée(s) à une — statut cancelled, la ligne est conservée', v_n;
  END IF;
END $$;

-- ── 2. L'unicité qui rend le doublon impossible ────────────────────────────
-- Partielle : une relance annulée ne compte pas, sinon la reprise ci-dessus
-- bloquerait l'index.
DROP INDEX IF EXISTS public.collection_reminders_idempotence_key;
CREATE UNIQUE INDEX collection_reminders_idempotence_key
  ON public.collection_reminders (tenant_id, invoice_id, reminder_level)
  WHERE status <> 'cancelled';

COMMENT ON INDEX public.collection_reminders_idempotence_key IS
  '258 (W6) : une relance par (société, facture, niveau) parmi les non annulées. Sans elle, la relance repartait chaque jour (EF-02).';

-- ── 3. La prise de la relance, avant l'envoi ───────────────────────────────
-- Rend l'identifiant de la relance POSÉE, ou NULL si un envoi de ce niveau a
-- déjà été prouvé (ou est en cours). Un échec antérieur peut être repris.
CREATE OR REPLACE FUNCTION public.claim_collection_reminder(
  p_tenant_id      uuid,
  p_invoice_id     uuid,
  p_customer_id    uuid,
  p_reminder_level integer,
  p_amount         numeric,
  p_days_overdue   integer,
  p_number         text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.collection_reminders (
    tenant_id, number, invoice_id, customer_id, reminder_level, reminder_date,
    amount, status, days_overdue, email_sent
  ) VALUES (
    p_tenant_id, p_number, p_invoice_id, p_customer_id, p_reminder_level, CURRENT_DATE,
    p_amount, 'pending', p_days_overdue, false
  )
  ON CONFLICT (tenant_id, invoice_id, reminder_level) WHERE status <> 'cancelled'
  DO UPDATE SET
    status        = 'pending',
    sent_at       = NULL,
    email_sent    = false,
    last_error    = NULL,
    amount        = EXCLUDED.amount,
    days_overdue  = EXCLUDED.days_overdue,
    number        = EXCLUDED.number,
    reminder_date = EXCLUDED.reminder_date
  WHERE public.collection_reminders.status = 'failed'
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

COMMENT ON FUNCTION public.claim_collection_reminder(uuid, uuid, uuid, integer, numeric, integer, text) IS
  '258 (W6) : prend la relance d''un niveau avant de l''envoyer. NULL si un envoi de ce niveau est déjà prouvé — le cron ne relance plus tous les jours.';

-- ── 4. Le seul chemin qui dit « envoyée » ou « en échec » ──────────────────
CREATE OR REPLACE FUNCTION public.finalize_collection_reminder(
  p_tenant_id   uuid,
  p_reminder_id uuid,
  p_sent        boolean,
  p_error       text DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_status text;
BEGIN
  UPDATE public.collection_reminders
     SET status     = CASE WHEN p_sent THEN 'sent' ELSE 'failed' END,
         sent_at    = CASE WHEN p_sent THEN now() ELSE NULL END,
         email_sent = p_sent,
         last_error = CASE WHEN p_sent THEN NULL ELSE COALESCE(p_error, 'envoi refusé par le prestataire') END
   WHERE id = p_reminder_id
     AND tenant_id = p_tenant_id
     AND status = 'pending'
  RETURNING status INTO v_status;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'relance % : introuvable, déjà traitée, ou hors de la société %', p_reminder_id, p_tenant_id
      USING ERRCODE = 'P0002';
  END IF;

  RETURN v_status;
END $$;

COMMENT ON FUNCTION public.finalize_collection_reminder(uuid, uuid, boolean, text) IS
  '258 (W6) : clôt une relance prise (`pending`) en `sent` (avec l''heure réelle) ou `failed` (avec l''erreur du prestataire). Un écran ne peut pas se déclarer « relance envoyée ».';

-- ── 5. Droits — la prise et la clôture appartiennent au cron ───────────────
REVOKE ALL ON FUNCTION public.claim_collection_reminder(uuid, uuid, uuid, integer, numeric, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finalize_collection_reminder(uuid, uuid, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_collection_reminder(uuid, uuid, uuid, integer, numeric, integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.finalize_collection_reminder(uuid, uuid, boolean, text) TO service_role;
