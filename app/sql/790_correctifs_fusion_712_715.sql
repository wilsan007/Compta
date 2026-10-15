-- 790 — correctifs_fusion_712_715
-- Numéro pris le 2026-10-13T18:29:52.320Z par migration-numero.mjs (ligne « plan6 intégration (correctifs de fusion) », branche integration/plan6-b).
-- ═══════════════════════════════════════════════════════════════════════════
-- 790 — Correctifs de la fusion plan6 F (13/10/2026, session d'intégration)
-- ═══════════════════════════════════════════════════════════════════════════
-- ROUGES AVANT, mesurés sur base neuve le 13/10/2026 (batterie : 22 échecs) :
--
--   1. ~14 suites refusées par le garde de la 712 (NOTIFICATION_DESTINATAIRE_
--      REFUSE) : 180 E18, 192 A05/G04, 222 G12*, 223 R09*, 244, 257 T02/T03,
--      401, 406, 432, 434, 435, 436, 470, 354… — un DÉCLENCHEUR du dépôt
--      notifie (diffusion ou destinataire tiers) pendant une action utilisateur
--      (jwt actif) : le marqueur `app.notification_serveur` n'est posé que par
--      les déclencheurs ÉCRITS PAR la 712. Les déclencheurs antérieurs (caisse,
--      banque, chaînes, règlements) ne le posent pas.
--
--   2. `check_anon_grants` + suite 228 T06 : zz_715_check_subscription_member()
--      est appelable par anon/PUBLIC (aucun REVOKE dans la 715).
--
-- CORRECTIONS :
--
--   1. `create_notification` : le garde n'exige le marqueur serveur QUE hors
--      déclencheur. `pg_trigger_depth() > 0` = c'est un déclencheur du dépôt
--      qui écrit : le serveur décide — le client ne peut pas fabriquer un
--      déclencheur à sa convenance (il n'invente ni fonction ni GUC par
--      PostgREST). L'appel RPC direct reste GARDIEN : un client connecté ne
--      notifie que lui-même, ni diffusion ni tiers. La 712 le voulait en
--      « marqueur serveur » ; le marqueur est conservé (les déclencheurs 712
--      continuent de fonctionner), le déclencheur devient la preuve.
--
--   2. REVOKE sur zz_715_check_subscription_member : fonction INTERNE de
--      déclencheur. Le privilège s'exerce à la CRÉATION du déclencheur, pas à
--      l'exécution — la suite 715 re-jouée (21/21) et 450 T11 le prouvent.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_notification(
  p_category text,
  p_title text,
  p_message text,
  p_user_id uuid DEFAULT NULL,
  p_severity text DEFAULT 'info',
  p_link text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_id uuid;
  v_tenant uuid := current_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Un appelant connecté ne peut pas viser quelqu'un d'autre — ni diffuser à
  -- toute la société depuis son navigateur. Deux preuves de « le serveur écrit
  -- pour quelqu'un » sont acceptées : le marqueur `app.notification_serveur`
  -- (posé par les déclencheurs de la 712 — conservé) OU le simple fait d'ÊTRE
  -- dans un déclencheur (`pg_trigger_depth() > 0` : le code déclenchant est le
  -- code du dépôt, pas celui du client — PostgREST n'expose aucun déclencheur
  -- comme point d'entrée). Sans les deux, un client ne notifie que lui-même.
  IF auth.uid() IS NOT NULL
     AND pg_trigger_depth() = 0
     AND COALESCE(current_setting('app.notification_serveur', true), 'off') <> 'on'
     AND (p_user_id IS NULL OR p_user_id <> auth.uid()) THEN
    RAISE EXCEPTION 'NOTIFICATION_DESTINATAIRE_REFUSE: un utilisateur connecté ne notifie que lui-même (destinataire demandé : %)',
      COALESCE(p_user_id::text, 'diffusion à la société')
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO notifications (tenant_id, user_id, category, severity, title, message, link, metadata)
  VALUES (v_tenant, p_user_id, p_category, p_severity, p_title, p_message, p_link, p_metadata)
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

-- Fonction INTERNE de déclencheur (715) : ni PUBLIC, ni anon, ni authenticated.
REVOKE ALL ON FUNCTION public.zz_715_check_subscription_member() FROM PUBLIC, anon, authenticated;

