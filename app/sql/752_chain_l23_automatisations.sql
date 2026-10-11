-- 752 — chain_l23_automatisations
-- Numéro pris le 2026-10-06T14:56:55.620Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 752 — L23-b · LES AUTOMATISATIONS branchées sur le journal d'événements unifié
-- ═══════════════════════════════════════════════════════════════════════════
-- Le lot **L23** (plan du 24/09, I-06) est « journal unique + automatisations +
-- webhooks branchés sur les MÊMES événements ». La tranche 1 (`415`) a livré le
-- JOURNAL et le pont webhooks (`chain_l23_enfiler`, déclencheur sur
-- `domain_events`). **L23-b = les automatisations** : une règle du client
-- (« quand CET événement arrive → exécuter CETTE action ») jouée par le même
-- journal.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve) : aucune table de
-- règles d'automatisation n'existe ; aucun moteur n'écoute `domain_events` pour
-- autre chose que les webhooks. Le plan donne l'exemple canonique
-- « devis accepté → créer la commande et notifier ».
--
-- CE QUE CE FICHIER POSE (la doctrine §3.2 — écrire une fois, utiliser partout) :
--   * `automation_actions` — le **catalogue FERMÉ** des actions qu'une règle
--     peut nommer. Une action non inscrite ne peut pas être référencée (clé
--     étrangère) ; on n'exécute jamais un nom de fonction venu d'une donnée.
--   * `automation_rules` — les règles de la société : `event_name` +
--     `action_code` + `params` + `active`.
--   * `automation_runs` — **l'idempotence STRUCTURELLE et la trace** : un index
--     unique `(tenant, règle, événement)`. Rejouer rend 0, jamais un `IF`
--     recopié (même doctrine que le pont de la `415`).
--   * `chain_l23_automatiser(event_id)` — LE MOTEUR : lit l'événement, et pour
--     chaque règle ACTIVE de **la société de l'événement** dont `event_name`
--     correspond, exécute l'action par un `CASE` fermé sur le catalogue.
--   * `zz_l23_automatiser` — déclencheur `AFTER INSERT` sur `domain_events` :
--     un événement émis par n'importe quel maillon déclenche les règles, sans
--     qu'aucun appelant ait à y penser.
--
-- LA PREMIÈRE ACTION (`chain.link`) est **pilotée par la charge utile** : elle
-- pose un lien amont→aval (`link_documents`) à partir de l'agrégat de
-- l'événement et des `params` de la règle. C'est le geste générique d'un
-- automatisme de chaînage ; les actions métier nommées (« créer la commande »,
-- « notifier ») s'inscrivent au même catalogue.
--
-- ⚠️ UNE ACTION QUI ÉCHOUE NE CASSE PAS L'ÉVÉNEMENT MÉTIER. Le moteur CONSOMME
-- l'erreur et la TRACE (`statut = 'failed'`, `detail = SQLERRM`) : une règle mal
-- configurée par le client est un défaut visible dans `automation_runs`, pas une
-- panne de la commande qui l'a déclenchée. (Le pont webhooks de la `415` fait le
-- contraire et c'est voulu : une livraison promise doit se voir ; une
-- automatisation est une commodité du client.)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le CATALOGUE FERMÉ des actions ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.automation_actions (
  code        text PRIMARY KEY,
  libelle     text NOT NULL,
  description text
);
ALTER TABLE public.automation_actions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS automation_actions_read ON public.automation_actions;
CREATE POLICY automation_actions_read ON public.automation_actions FOR SELECT USING (true);
GRANT SELECT ON public.automation_actions TO authenticated;

INSERT INTO public.automation_actions (code, libelle, description) VALUES
  ('chain.link', 'Chaîner deux documents',
   'Pose un lien amont→aval (`link_documents`) : l''amont est l''agrégat de l''événement (ou `params.amont_type`/`amont_id`), l''aval et l''effet viennent des `params`.')
ON CONFLICT (code) DO UPDATE SET libelle = EXCLUDED.libelle, description = EXCLUDED.description;

-- ── 2. Les RÈGLES d'automatisation (une par société) ───────────────────────
CREATE TABLE IF NOT EXISTS public.automation_rules (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL,
  code        text NOT NULL,
  event_name  text NOT NULL,
  action_code text NOT NULL,
  params      jsonb NOT NULL DEFAULT '{}'::jsonb,
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, code)
);
ALTER TABLE public.automation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automation_rules FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS automation_rules_tenant ON public.automation_rules;
CREATE POLICY automation_rules_tenant ON public.automation_rules
  FOR ALL USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

ALTER TABLE public.automation_rules DROP CONSTRAINT IF EXISTS automation_rules_tenant_id_fkey;
ALTER TABLE public.automation_rules ADD CONSTRAINT automation_rules_tenant_id_fkey
  FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.automation_rules DROP CONSTRAINT IF EXISTS automation_rules_action_code_fkey;
ALTER TABLE public.automation_rules ADD CONSTRAINT automation_rules_action_code_fkey
  FOREIGN KEY (action_code) REFERENCES public.automation_actions(code);

-- ── 3. L'EXÉCUTION : idempotence structurelle + trace ──────────────────────
CREATE TABLE IF NOT EXISTS public.automation_runs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL,
  rule_id    uuid NOT NULL,
  event_id   bigint NOT NULL,
  statut     text NOT NULL CHECK (statut IN ('executed', 'skipped', 'failed')),
  detail     text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, rule_id, event_id)
);
ALTER TABLE public.automation_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automation_runs FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS automation_runs_tenant ON public.automation_runs;
CREATE POLICY automation_runs_tenant ON public.automation_runs
  FOR ALL USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

ALTER TABLE public.automation_runs DROP CONSTRAINT IF EXISTS automation_runs_rule_fkey;
ALTER TABLE public.automation_runs ADD CONSTRAINT automation_runs_rule_fkey
  FOREIGN KEY (tenant_id, rule_id) REFERENCES public.automation_rules(tenant_id, id) ON DELETE CASCADE;

-- ── 4. LE MOTEUR : `chain_l23_automatiser` ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l23_automatiser(p_event_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_ev      domain_events%ROWTYPE;
  v_rule    automation_rules%ROWTYPE;
  v_n       integer := 0;
  v_amont_t text;
  v_amont   uuid;
  v_aval_t  text;
  v_aval    uuid;
  v_effet   text;
  v_link    text;
BEGIN
  SELECT * INTO v_ev FROM domain_events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Événement % introuvable', p_event_id USING ERRCODE = 'no_data_found';
  END IF;

  -- Garde de société : un appelant RATTACHÉ À UNE SOCIÉTÉ ne peut jouer que ses
  -- propres événements. Sans contexte (service, migration), on procède.
  IF current_tenant_id() IS NOT NULL AND v_ev.tenant_id IS DISTINCT FROM current_tenant_id() THEN
    RAISE EXCEPTION 'Événement hors de votre société' USING ERRCODE = 'check_violation';
  END IF;

  FOR v_rule IN
    SELECT * FROM automation_rules
     WHERE tenant_id = v_ev.tenant_id AND active AND event_name = v_ev.event_name
     ORDER BY created_at
  LOOP
    -- Idempotence STRUCTURELLE : on RÉSERVE la ligne. Un rejeu ne l'insère pas.
    INSERT INTO automation_runs (tenant_id, rule_id, event_id, statut)
    VALUES (v_ev.tenant_id, v_rule.id, p_event_id, 'skipped')
    ON CONFLICT (tenant_id, rule_id, event_id) DO NOTHING;
    IF NOT FOUND THEN
      CONTINUE;   -- déjà jouée : rejeu neutre
    END IF;

    BEGIN
      IF v_rule.action_code = 'chain.link' THEN
        v_amont_t := COALESCE(v_rule.params->>'amont_type', v_ev.aggregate_type);
        v_amont   := COALESCE(NULLIF(v_rule.params->>'amont_id', '')::uuid, v_ev.aggregate_id);
        v_aval_t  := v_rule.params->>'aval_type';
        v_aval    := NULLIF(v_rule.params->>'aval_id', '')::uuid;
        v_effet   := v_rule.params->>'effet';
        v_link    := COALESCE(v_rule.params->>'link_type', 'created_from');
        IF v_amont IS NULL OR v_aval IS NULL OR v_effet IS NULL OR v_aval_t IS NULL THEN
          UPDATE automation_runs SET statut = 'skipped', detail = 'paramètre manquant (amont, aval ou effet)'
           WHERE tenant_id = v_ev.tenant_id AND rule_id = v_rule.id AND event_id = p_event_id;
          CONTINUE;
        END IF;
        PERFORM link_documents(v_ev.tenant_id, v_amont_t, v_amont, v_aval_t, v_aval, v_effet, v_link);
        UPDATE automation_runs SET statut = 'executed', detail = format('lien %s → %s posé', v_amont_t, v_aval_t)
         WHERE tenant_id = v_ev.tenant_id AND rule_id = v_rule.id AND event_id = p_event_id;
        v_n := v_n + 1;
      ELSE
        UPDATE automation_runs SET statut = 'skipped', detail = 'action inconnue du moteur'
         WHERE tenant_id = v_ev.tenant_id AND rule_id = v_rule.id AND event_id = p_event_id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Une action qui échoue ne casse pas l'événement métier : elle est TRACÉE.
      UPDATE automation_runs SET statut = 'failed', detail = SQLERRM
       WHERE tenant_id = v_ev.tenant_id AND rule_id = v_rule.id AND event_id = p_event_id;
    END;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'event_id', p_event_id, 'rules_run', v_n);
END $fn$;

COMMENT ON FUNCTION public.chain_l23_automatiser(bigint) IS
  'L23-b/752 : moteur d''automatisations. Lit l''événement, joue chaque règle ACTIVE de sa société (event_name), trace dans automation_runs (idempotence structurelle (tenant, règle, événement)). Une action qui échoue est tracée, pas propagée.';

-- ── 5. Le DÉCLENCHEUR : tout événement joue les règles de sa société ────────
-- Le même point que le pont de la 415 : personne ne peut oublier d'appeler le
-- moteur, puisque l'événement ENTRANT dans le journal le réveille.
CREATE OR REPLACE FUNCTION public.zz_l23_automatiser()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  PERFORM public.chain_l23_automatiser(NEW.id);
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS zz_l23_automatiser ON public.domain_events;
CREATE TRIGGER zz_l23_automatiser
  AFTER INSERT ON public.domain_events
  FOR EACH ROW EXECUTE FUNCTION public.zz_l23_automatiser();

-- ── 6. Droits ──────────────────────────────────────────────────────────────
-- L'événement est lisible et l'action est bornée à la société (garde interne) :
-- le moteur peut être appelé par un utilisateur connecté ; le déclencheur, non.
REVOKE ALL ON FUNCTION public.chain_l23_automatiser(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l23_automatiser(bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.zz_l23_automatiser() FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS idx_automation_rules_event ON public.automation_rules (tenant_id, event_name) WHERE active;
CREATE INDEX IF NOT EXISTS idx_automation_runs_event ON public.automation_runs (tenant_id, event_id);
