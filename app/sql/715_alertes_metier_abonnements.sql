-- ============================================================
-- 715 : NOT-02 — les alertes métier, déclarées et évaluées
--       (règles d'alerte + abonnements)
-- ============================================================
--
-- Le constat (mesuré sur base neuve) :
--   `stock_alerts` existe mais est propre au stock ; AUCUNE table ne
--   porte une règle d'alerte métier (facture en retard, tâche de
--   projet en retard, stock bas) ni un ABONNEMENT — qui veut être
--   prévenu, et de quoi. NOT‑01 (712) a rendu la boîte personnelle
--   vraie ; il manquait le moteur qui l'ALIMENTE.
--
-- Ce lot :
--   1) `business_alert_rules` — une règle par (société, type), à
--      seuil contraint, activable ;
--   2) `alert_subscriptions` — un membre s'abonne à une règle ;
--      le destinataire d'une alerte n'est plus deviné ;
--   3) `evaluate_business_alert_rules()` — le moteur : il évalue
--      chaque règle active, et notifie (abonnés, ou diffusion si
--      aucun abonné). Idempotence : une règle déclenchée le même
--      jour ne renvoie pas deux fois (marqueur dans `metadata`).
--
-- Limites dites : (a) trois types seulement (facture en retard,
-- tâche en retard, stock bas) — la liste est ouverte et contrainte ;
-- (b) l'e‑mail est NOT‑03 (Resend 👤 en attente) : le canal
-- `email` est ACCEPTÉ par la contrainte mais n'est PAS livré par le
-- moteur — c'est écrit, pas tu ;
-- (c) le moteur est appelé par un écran (RPC) ou un cron — pas de
-- déclencheur : une alerte n'est pas une conséquence d'une ligne,
-- c'est un constat d'état.
-- ============================================================

BEGIN;

-- ============================================================
-- 1) Les règles d'alerte
-- ============================================================
CREATE TABLE IF NOT EXISTS business_alert_rules (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text NOT NULL,
  -- Le type CHOISIT ce que le moteur mesure. La liste est contrainte
  -- et fermée : une règle que le moteur ne sait pas évaluer n'existe
  -- pas (un réglage qui ne fait rien est un leurre).
  alert_type  text NOT NULL
    CONSTRAINT bar_alert_type_check CHECK (alert_type IN (
      'invoice_overdue',   -- factures échues et non payées
      'project_task_overdue', -- tâches de projet en retard
      'stock_below_threshold'  -- articles sous le seuil
    )),
  -- Le seuil. Contraint par TYPE : le moteur ne lit que la clé
  -- correspondante, et une clé d'un autre type est refusée.
  conditions  jsonb NOT NULL DEFAULT '{}'::jsonb
    CONSTRAINT bar_conditions_is_object CHECK (
      jsonb_typeof(conditions) = 'object'),
  severity    text NOT NULL DEFAULT 'warning'
    CONSTRAINT bar_severity_check CHECK (
      severity IN ('info', 'warning', 'critical')),
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bar_name_check CHECK (length(btrim(name)) > 0 AND length(name) <= 200),
  -- Une règle ne porte que les seuils de SON type.
  CONSTRAINT bar_conditions_per_type CHECK (
    (alert_type = 'invoice_overdue'
       AND conditions ? 'min_amount'
       AND jsonb_typeof(conditions->'min_amount') = 'number')
 OR (alert_type = 'project_task_overdue'
       AND conditions ? 'min_count'
       AND jsonb_typeof(conditions->'min_count') = 'number')
 OR (alert_type = 'stock_below_threshold'
       AND conditions ? 'threshold'
       AND jsonb_typeof(conditions->'threshold') = 'number')
  )
);

CREATE INDEX IF NOT EXISTS idx_bar_tenant ON business_alert_rules(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bar_active ON business_alert_rules(tenant_id) WHERE active;
-- La clé que la table des abonnements reference (ISO‑02) : sans elle,
-- PostgreSQL refuse la clé étrangère composite.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_bar_tenant_id
  ON business_alert_rules(tenant_id, id);

ALTER TABLE business_alert_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_alert_rules FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_select_business_alert_rules ON business_alert_rules;
CREATE POLICY tenant_select_business_alert_rules ON business_alert_rules FOR SELECT
  USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS tenant_insert_business_alert_rules ON business_alert_rules;
CREATE POLICY tenant_insert_business_alert_rules ON business_alert_rules FOR INSERT
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('business_alert_rules', 'insert'));

DROP POLICY IF EXISTS tenant_update_business_alert_rules ON business_alert_rules;
CREATE POLICY tenant_update_business_alert_rules ON business_alert_rules FOR UPDATE
  USING (tenant_id = current_tenant_id()
         AND can_perform('business_alert_rules', 'update'))
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('business_alert_rules', 'update'));

DROP POLICY IF EXISTS tenant_delete_business_alert_rules ON business_alert_rules;
CREATE POLICY tenant_delete_business_alert_rules ON business_alert_rules FOR DELETE
  USING (tenant_id = current_tenant_id()
         AND can_perform('business_alert_rules', 'delete'));

REVOKE ALL ON business_alert_rules FROM anon, public;
GRANT SELECT ON business_alert_rules TO authenticated;

DROP TRIGGER IF EXISTS trg_bar_updated_at ON business_alert_rules;
CREATE TRIGGER trg_bar_updated_at BEFORE UPDATE ON business_alert_rules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 2) Les abonnements — QUI veut être prévenu, et de QUOI
-- ============================================================
CREATE TABLE IF NOT EXISTS alert_subscriptions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  -- Clé COMPOSITE vers la règle (ISO‑02) : une abonnement ne peut
  -- pas pointer une règle d'une autre société, ni vers rien.
  rule_id     uuid NOT NULL,
  -- Le compte. Comme `notifications.user_id` (712) : c'est
  -- `auth.users.id`, et le déclencheur ci‑dessous vérifie que ce
  -- compte est bien MEMBRE de la société — jamais d'abonnement
  -- pour un invisible.
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Le canal. `in_app` est livré par le moteur ; `email` est
  -- ACCEPTÉ mais non livré (NOT‑03, Resend 👤) — voir les limites.
  channel     text NOT NULL DEFAULT 'in_app'
    CONSTRAINT as_channel_check CHECK (channel IN ('in_app', 'email')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  -- Un membre ne s'abonne qu'UNE fois à une règle.
  CONSTRAINT as_unique_rule_user UNIQUE (tenant_id, rule_id, user_id)
);

ALTER TABLE alert_subscriptions
  ADD CONSTRAINT as_rule_fk
  FOREIGN KEY (tenant_id, rule_id)
  REFERENCES business_alert_rules(tenant_id, id)
  ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_as_tenant_rule ON alert_subscriptions(tenant_id, rule_id);
CREATE INDEX IF NOT EXISTS idx_as_user ON alert_subscriptions(tenant_id, user_id);

ALTER TABLE alert_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_subscriptions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_select_alert_subscriptions ON alert_subscriptions;
CREATE POLICY tenant_select_alert_subscriptions ON alert_subscriptions FOR SELECT
  USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS tenant_insert_alert_subscriptions ON alert_subscriptions;
CREATE POLICY tenant_insert_alert_subscriptions ON alert_subscriptions FOR INSERT
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('alert_subscriptions', 'insert'));

DROP POLICY IF EXISTS tenant_update_alert_subscriptions ON alert_subscriptions;
CREATE POLICY tenant_update_alert_subscriptions ON alert_subscriptions FOR UPDATE
  USING (tenant_id = current_tenant_id()
         AND can_perform('alert_subscriptions', 'update'))
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('alert_subscriptions', 'update'));

DROP POLICY IF EXISTS tenant_delete_alert_subscriptions ON alert_subscriptions;
CREATE POLICY tenant_delete_alert_subscriptions ON alert_subscriptions FOR DELETE
  USING (tenant_id = current_tenant_id()
         AND can_perform('alert_subscriptions', 'delete'));

REVOKE ALL ON alert_subscriptions FROM anon, public;
GRANT SELECT ON alert_subscriptions TO authenticated;

-- Le destinataire doit être MEMBRE de la société (le même garde‑fou
-- que 712 sur `notifications`) : un abonnement pour un compte d'une
-- autre société ne recevrait jamais l'alerte — c'est un leurre.
CREATE OR REPLACE FUNCTION zz_715_check_subscription_member()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM tenant_users
     WHERE tenant_id = NEW.tenant_id AND auth_id = NEW.user_id
  ) THEN
    RAISE EXCEPTION 'ABONNEMENT_REFUSE: le compte % n''est pas membre de cette société',
      NEW.user_id
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_715_subscription_member ON alert_subscriptions;
CREATE TRIGGER trg_715_subscription_member
  BEFORE INSERT OR UPDATE ON alert_subscriptions
  FOR EACH ROW EXECUTE FUNCTION zz_715_check_subscription_member();


-- ============================================================
-- 3) Le moteur — il CONSTATE l'état, il ne devine rien
-- ============================================================
-- Chaque type sait ce qu'il mesure :
--   invoice_overdue       → somme des `amount_due` des factures échues
--   project_task_overdue  → nombre de tâches échues non finies
--   stock_below_threshold → nombre d'articles à ≤ le seuil de la règle
-- Le verdict est écrit dans `metadata` (mesuré + seuil) : l'alerte
-- dit d'où elle vient, elle n'est pas une alarme muette.
CREATE OR REPLACE FUNCTION evaluate_business_alert_rules(
  p_tenant_id uuid DEFAULT NULL
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  r              record;
  v_tenant       uuid := COALESCE(p_tenant_id, current_tenant_id());
  v_measure      numeric;
  v_fired        integer := 0;
  v_title        text;
  v_message      text;
  v_already      integer;
  v_sub          record;
  v_delivered    integer;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Le moteur écrit pour les ABONNÉS : c'est un acte serveur, le
  -- même que les déclencheurs de la 712. Le marqueur est
  -- transactionnel — il ne survit pas à cet appel.
  PERFORM set_config('app.notification_serveur', 'on', true);

  FOR r IN
    SELECT * FROM business_alert_rules
     WHERE tenant_id = v_tenant AND active
     ORDER BY created_at
  LOOP
    -- Ce que la règle mesure
    CASE r.alert_type
      WHEN 'invoice_overdue' THEN
        SELECT COALESCE(SUM(i.amount_due), 0) INTO v_measure
          FROM invoices i
         WHERE i.tenant_id = v_tenant
           AND i.due_date < current_date
           AND i.status IN ('sent', 'viewed', 'overdue')
           AND i.amount_due > 0;
        IF v_measure < (r.conditions->>'min_amount')::numeric THEN
          CONTINUE;
        END IF;
        v_title := format('Factures échues : %s €', round(v_measure, 2));
        v_message := format(
          'Le total des factures échues et non payées atteint %s € (seuil : %s €).',
          round(v_measure, 2), r.conditions->>'min_amount');

      WHEN 'project_task_overdue' THEN
        SELECT COUNT(*) INTO v_measure
          FROM project_tasks pt
          JOIN projects p ON p.id = pt.project_id
         WHERE p.tenant_id = v_tenant
           AND pt.due_date < current_date
           AND COALESCE(pt.status, '') NOT IN ('done', 'completed', 'cancelled');
        IF v_measure < (r.conditions->>'min_count')::numeric THEN
          CONTINUE;
        END IF;
        v_title := format('Tâches de projet en retard : %s', v_measure);
        v_message := format(
          '%s tâche(s) de projet sont en retard (seuil : %s).',
          v_measure, r.conditions->>'min_count');

      WHEN 'stock_below_threshold' THEN
        SELECT COUNT(*) INTO v_measure
          FROM products pr
         WHERE pr.tenant_id = v_tenant
           AND pr.stock_quantity <= (r.conditions->>'threshold')::numeric;
        IF v_measure < 1 THEN
          CONTINUE;
        END IF;
        v_title := format('Articles sous le seuil de stock : %s', v_measure);
        v_message := format(
          '%s article(s) sont à ou sous le seuil de %s.',
          v_measure, r.conditions->>'threshold');

      ELSE
        -- Type contraint par le CHECK : jamais atteint. Gardé pour
        -- qu'une règle ajoutée sans moteur ne notifie PAS en silence.
        CONTINUE;
    END CASE;

    -- Idempotence : la même règle ne notifie pas deux fois le même
    -- jour. Le marqueur est dans `metadata` — pas de table de plus.
    SELECT COUNT(*) INTO v_already
      FROM notifications n
     WHERE n.tenant_id = v_tenant
       AND n.metadata->>'alert_rule_id' = r.id::text
       AND n.created_at >= date_trunc('day', now());
    IF v_already > 0 THEN
      CONTINUE;
    END IF;

    -- Destinataires : les abonnés (canal in_app) ; s'il n'y en a
    -- aucun, la règle ALERTÉE devient une DIFFUSION — jamais un
    -- silence. `email` n'est pas livré (NOT‑03) : ignoré, écrit.
    v_delivered := 0;
    FOR v_sub IN
      SELECT user_id FROM alert_subscriptions
       WHERE tenant_id = v_tenant AND rule_id = r.id AND channel = 'in_app'
    LOOP
      PERFORM create_notification(
        'alert', v_title, v_message, v_sub.user_id, r.severity,
        NULL,
        jsonb_build_object(
          'alert_rule_id', r.id,
          'alert_type', r.alert_type,
          'measure', v_measure,
          'conditions', r.conditions));
      v_delivered := v_delivered + 1;
    END LOOP;

    IF v_delivered = 0 THEN
      PERFORM create_notification(
        'alert', v_title, v_message, NULL, r.severity,
        NULL,
        jsonb_build_object(
          'alert_rule_id', r.id,
          'alert_type', r.alert_type,
          'measure', v_measure,
          'conditions', r.conditions));
    END IF;

    v_fired := v_fired + 1;
  END LOOP;

  RETURN v_fired;
END $$;

REVOKE ALL ON FUNCTION evaluate_business_alert_rules(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION evaluate_business_alert_rules(uuid) TO authenticated;

COMMIT;

