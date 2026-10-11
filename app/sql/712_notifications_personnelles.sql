-- ============================================================
-- 712 — F.6 / NOT-01 : LES NOTIFICATIONS SONT PERSONNELLES,
--       ET C'EST LA BASE QUI LE TIENT
-- Numéro pris le 2026-10-11T08:46:09.769Z par migration-numero.mjs
-- (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
--   CE QUI A ÉTÉ MESURÉ, sur base neuve (`pg_p5/fbase`, 336 migrations) :
--   · `notifications` porte un destinataire (`user_id`) et l'index
--     `idx_notifications_tenant_unread (tenant_id, user_id, read_at)` :
--     l'intention de borner au destinataire était là, dans la table ;
--   · mais les QUATRE politiques RLS ne filtraient que la SOCIÉTÉ —
--     `tenant_select_notifications :: (tenant_id = current_tenant_id())`.
--     Dans une société, chaque utilisateur lisait donc les 20 dernières
--     notifications de TOUS les autres, pouvait les marquer lues (UPDATE)
--     et les supprimer (DELETE) ;
--   · `mark_notification_read(p_notification_id)` ne vérifiait QUE la société :
--     un utilisateur marquait lue la notification d'un autre — du courrier
--     d'autrui ouvert sans trace ;
--   · `get_unread_notification_count()` et `mark_all_notifications_read()`,
--     appelés par l'en-tête SANS argument (`NotificationCenter.tsx`),
--     lisaient `p_user_id IS NULL` comme « TOUT LE MONDE » : le badge comptait
--     les notifications de la société entière, et « tout marquer comme lu »
--     marquait celles de tout le monde ;
--   · `create_notification` acceptait n'importe quel destinataire : un
--     utilisateur connecté pouvait écrire au nom d'un autre ;
--   · `notify_payslip_ready` (93) passait `NEW.employee_id` — un SALARIÉ — là
--     où la colonne attend un COMPTE, alors que `employees.auth_user_id`
--     existait déjà pour le dire.
--
--   LE CORRECTIF EST ENTIÈREMENT EN BASE, et c'est le point : le front n'est
--   PAS touché. `select('*')` rend maintenant ce que l'utilisateur a le droit
--   de voir, un appel sans argument veut dire « moi », et une notification ne
--   peut plus être marquée lue par quelqu'un d'autre.
--
--   DEUX RÈGLES ÉCRITES UNE FOIS :
--   · `user_id IS NULL` = DIFFUSION à la société (l'alerte « facture en
--     retard » concerne l'équipe de vente, pas une personne) — elle reste
--     visible de tous, et marquable par chacun ;
--   · `auth.uid() IS NULL` = appel SERVEUR (déclencheur, `SECURITY DEFINER`,
--     `service_role`) : il n'est pas borné, et c'est ce qui laisse les onze
--     déclencheurs du dépôt fonctionner sans être réécrits.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Un destinataire qui n'est pas un compte ne peut plus exister
--    Il est ramené à NULL (DIFFUSION), jamais rendu invisible :
--    cette migration ne cache aucune notification déjà écrite.
-- ------------------------------------------------------------
UPDATE notifications n
   SET user_id = NULL
 WHERE n.user_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = n.user_id);

-- ------------------------------------------------------------
-- 2) La RLS borne au DESTINATAIRE (et garde la société)
--    Quatre politiques, une par commande — comme avant, la grille
--    `check_bt_grid` ne bouge pas.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS tenant_select_notifications ON notifications;
CREATE POLICY tenant_select_notifications ON notifications FOR SELECT
  USING (tenant_id = current_tenant_id()
         AND (user_id IS NULL OR user_id = auth.uid()));

DROP POLICY IF EXISTS tenant_insert_notifications ON notifications;
CREATE POLICY tenant_insert_notifications ON notifications FOR INSERT
  WITH CHECK (tenant_id = current_tenant_id()
              AND (user_id IS NULL OR user_id = auth.uid()));

DROP POLICY IF EXISTS tenant_update_notifications ON notifications;
CREATE POLICY tenant_update_notifications ON notifications FOR UPDATE
  USING (tenant_id = current_tenant_id()
         AND (user_id IS NULL OR user_id = auth.uid()))
  WITH CHECK (tenant_id = current_tenant_id()
              AND (user_id IS NULL OR user_id = auth.uid()));

DROP POLICY IF EXISTS tenant_delete_notifications ON notifications;
CREATE POLICY tenant_delete_notifications ON notifications FOR DELETE
  USING (tenant_id = current_tenant_id()
         AND (user_id IS NULL OR user_id = auth.uid()));

-- ------------------------------------------------------------
-- 3) Marquer LU : le destinataire, ou la diffusion — pas « la société »
--    Avant : `WHERE id = ... AND tenant_id = ...` — appartenir à la société
--    suffisait à ouvrir le courrier d'un autre.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION mark_notification_read(p_notification_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  UPDATE notifications
     SET read_at = now()
   WHERE id = p_notification_id
     AND tenant_id = current_tenant_id()
     AND (auth.uid() IS NULL OR user_id IS NULL OR user_id = auth.uid());
END $$;

-- ------------------------------------------------------------
-- 4) LE COMPTEUR : un appel SANS argument veut dire « MOI »
--    C'est le défaut VIVANT : `NotificationCenter.tsx` appelle
--    `get_unread_notification_count()` sans argument, et le badge de
--    l'en-tête affichait le total de la société entière. `p_user_id` reste
--    accepté (appel serveur), mais NULL n'est PLUS « tout le monde » :
--    c'est l'utilisateur connecté.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_unread_notification_count(p_user_id uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := COALESCE(p_user_id, auth.uid());
  v_count integer;
BEGIN
  IF current_tenant_id() IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*) INTO v_count
    FROM notifications
   WHERE read_at IS NULL
     AND tenant_id = current_tenant_id()
     AND (v_uid IS NULL OR user_id IS NULL OR user_id = v_uid);

  RETURN v_count;
END $$;

-- ------------------------------------------------------------
-- 5) « TOUT MARQUER LU » : la même règle, une seule portée
--    Avant, l'appel sans argument (celui du front) marquait lues les
--    notifications de TOUTE la société.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION mark_all_notifications_read(p_user_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := COALESCE(p_user_id, auth.uid());
BEGIN
  UPDATE notifications
     SET read_at = now()
   WHERE read_at IS NULL
     AND tenant_id = current_tenant_id()
     AND (v_uid IS NULL OR user_id IS NULL OR user_id = v_uid);
END $$;

-- ------------------------------------------------------------
-- 6) `create_notification` : un utilisateur connecté notifie LUI-MÊME
--    Les déclencheurs du dépôt appellent cette fonction SANS jeton
--    (`auth.uid() IS NULL`) : ils gardent le droit de désigner un
--    destinataire (le compte du salarié, par exemple) ou de diffuser.
--    Un utilisateur connecté, lui, n'écrit pas dans la boîte d'un autre.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_notification(
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

  -- Un appelant connecté ne peut pas viser quelqu'un d'autre — ni diffuser
  -- à toute la société depuis son navigateur. Le marqueur `app.notification
  -- _serveur` est posé par les déclencheurs du dépôt (`notify_payslip_ready`
  -- ci-dessous) : il distingue « le serveur écrit pour quelqu'un » de « un
  -- utilisateur clic sur une RPC ». Un client ne peut pas le poser — il
  -- n'invente ni fonction ni GUC par PostgREST —, et il est transactionnel :
  -- il ne survit pas à l'acte qui l'a posé.
  IF auth.uid() IS NOT NULL
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

-- ------------------------------------------------------------
-- 7) Le bulletin de paie va au COMPTE du salarié, plus au salarié
--    `NEW.employee_id` désignait un employé ; la colonne, elle, attend un
--    compte — et `employees.auth_user_id` le porte depuis le socle.
--    Salarié sans compte : NULL = DIFFUSION à la société (visible dans
--    l'en-tête de ceux qui font la paie) plutôt qu'une boîte que personne
--    ne lit.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_payslip_ready() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid;
BEGIN
  IF NEW.status = 'draft' AND (OLD.status IS NULL OR OLD.status <> 'draft') THEN
    SELECT e.auth_user_id INTO v_uid FROM employees e WHERE e.id = NEW.employee_id;

    -- Marqueur serveur : ce déclencheur s'exécute PENDANT une requête
    -- utilisateur (le gestionnaire de paie) et écrit pour QUELQU'UN D'AUTRE
    -- (le salarié). Sans ce marqueur, la garde de `create_notification`
    -- refuserait la notification — mesure faite en écrivant la suite 712.
    PERFORM set_config('app.notification_serveur', 'on', true);

    PERFORM create_notification(
      'hr',
      'Bulletin de paie disponible',
      'Votre bulletin de paie de ' || to_char(NEW.period_start, 'MM/YYYY') || ' est disponible.',
      v_uid, 'info',
      '/pay-slips/' || NEW.id
    );
  END IF;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 8) Les droits : une table personnelle ne s'écrit que par ses fonctions
--    Mesuré avant : `anon` (le visiteur non connecté) avait SELECT, et
--    `authenticated` avait INSERT, UPDATE et DELETE en direct — les
--    politiques RLS étaient donc le SEUL obstacle, et elles ne voyaient
--    que la société. Fermé ici :
--      · `anon` ne lit ni n'écrit (la RLS le refusait déjà : deux murs
--        valent mieux qu'un sur une boîte nominative) ;
--      · `authenticated` n'écrit plus en direct : les cinq fonctions
--        `create_notification`, `mark_notification_read`,
--        `mark_all_notifications_read` (SECURITY DEFINER) sont les seules
--        plumes — doctrine 271 (« le stock s'écrit par ses fonctions »),
--        appliquée à la boîte de réception.
--    Vérifié avant d'y toucher : le seul écrivain de production est
--    `NotificationCenter.tsx`, et il ne fait que lire + appeler les RPC.
-- ------------------------------------------------------------
REVOKE ALL ON TABLE notifications FROM anon;
REVOKE INSERT, UPDATE, DELETE ON TABLE notifications FROM authenticated;

REVOKE ALL ON FUNCTION create_notification(text, text, text, uuid, text, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION get_unread_notification_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION mark_all_notifications_read(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION mark_notification_read(uuid) FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 9) La règle devient VIVANTE : un destinataire qui n'est pas un membre
--    de la société est ramené à la DIFFUSION.
--    La section 1 rattrape les lignes DÉJÀ écrites (l'ancien
--    `NEW.employee_id` de la 93) ; ce déclencheur empêche que ça
--    recommence, sans jamais faire échouer l'acte métier qui l'a
--    provoqué : une notification mal adressée ne doit pas annuler un
--    bulletin de paie — elle redevient une diffusion, donc VISIBLE,
--    plutôt qu'une ligne que personne ne lit.
--    Vérifié avant d'y toucher : tous les producteurs de `notifications`
--    passent un compte réel (`tu.auth_id` en 264 et 414, `employees.
--    auth_user_id` en 93/188) ou NULL. Les notificateurs de projet (85)
--    écrivent dans `project_notifications`, une autre table — intacts.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION notifications_normaliser_destinataire() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM tenant_users tu
     WHERE tu.auth_id = NEW.user_id
       AND tu.tenant_id = NEW.tenant_id
  ) THEN
    NEW.user_id := NULL;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notifications_normaliser_destinataire ON notifications;
CREATE TRIGGER trg_notifications_normaliser_destinataire
  BEFORE INSERT OR UPDATE OF user_id ON notifications
  FOR EACH ROW EXECUTE FUNCTION notifications_normaliser_destinataire();

REVOKE ALL ON FUNCTION notifications_normaliser_destinataire() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION create_notification(text, text, text, uuid, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION get_unread_notification_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_all_notifications_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_notification_read(uuid) TO authenticated;

