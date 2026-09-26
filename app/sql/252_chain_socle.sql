-- ============================================================
-- 252_chain_socle.sql — L0 : le socle des chaînages transverses
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md (partie 3
-- « L'architecture d'implémentation : le socle » et lot L0 de la partie 5).
-- Le référentiel (doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md)
-- a mesuré 62 chaînages existants, note moyenne 3,65/7, idempotence 15 %,
-- trace 11 %. Ce fichier pose ce qui manquait à tous : un socle commun.
--
-- CE QUE CE FICHIER POSE (rien de plus)
--   1. les cinq tables du plan (§3.1) : document_links (qui a produit quoi),
--      document_effects (ce qui doit se produire), domain_events (ce qui s'est
--      passé), chain_regeneration_log (ce qui a été recalculé), chain_traces
--      (la mesure de chaque maillon, §3.4) ;
--   2. la sixième table, chain_settings : le drapeau d'application par société
--      (`observe` → `avertit` → `refuse`, §3.6) ;
--   3. les six fonctions utilitaires du plan (§3.2) : link_documents,
--      chain_deja_fait, chain_integrity_ok, emit_domain_event, chain_autorise,
--      chain_regenerate ;
--   4. le gabarit de maillon (§3.2 et §3.4) : chain_avant / chain_trace /
--      chain_apres — l'idempotence, le contrat et la mesure écrites UNE fois
--      pour les 62 maillons à venir ;
--   5. le réglage du drapeau : chain_enforcement_mode / chain_set_enforcement ;
--   6. les partitions mensuelles de domain_events et chain_traces, et la
--      fonction qui les crée (chain_ensure_partitions).
--
-- CE QUE CE FICHIER NE FAIT PAS, ET QUI VIENDRA APRÈS
--   * il ne branche AUCUN maillon : la rétro-instrumentation des 62 chaînages
--     est le lot L1, les 62 règles d'état la phase D ;
--   * il ne sème AUCUN contrat d'effet : les déclarations sont le lot L7.
--     Conséquence assumée : tant qu'un effet n'est pas déclaré, `chain_autorise`
--     rend FAUX (contrat fermé par défaut) — et c'est
--     `chain_settings.enforcement`, à `observe` par défaut, qui décide si cela
--     bloque. Une société existante ne peut donc pas être bloquée par une
--     déclaration manquante tant qu'elle n'a pas demandé `refuse` ;
--   * il ne planifie aucune tâche : `chain_ensure_partitions()` est écrit pour
--     être appelé par le job nocturne du lot L4.
--
-- DÉCISIONS D'ÉCART AU PLAN, ET POURQUOI (mesurées par la suite 252)
--   * `document_effects` reçoit `actif` : sans elle, une société ne pouvait pas
--     DÉSACTIVER un effet standard (une ligne `tenant_id IS NULL` déclare un
--     effet ; aucune ligne ne peut le retirer). `chain_autorise` lit la ligne la
--     plus spécifique — société d'abord, standard ensuite — et rend son `actif` ;
--   * `domain_events` et `chain_traces` portent `PRIMARY KEY (id, created_at)` :
--     PostgreSQL refuse une clé primaire qui ne contient pas la clé de
--     partitionnement. Le plan écrivait `id` seul ;
--   * `document_effects` n'a pas de contrainte PRIMARY KEY sur
--     `COALESCE(tenant_id, …)` : une clé primaire n'accepte pas d'expression en
--     PostgreSQL (`ALTER TABLE … ADD PRIMARY KEY (COALESCE(…))` échoue —
--     mesuré). L'unicité est portée par un index unique sur la même expression,
--     que `ON CONFLICT` retrouve ;
--   * le vocabulaire de `chain_traces.resultat` gagne `tolere` : `ignore` dit
--     « déjà appliqué », `tolere` dit « effet non déclaré, appliqué parce que la
--     société n'est pas en `refuse` ». Sans cette valeur, un effet appliqué hors
--     contrat serait indiscernable d'un rejeu ;
--   * les partitions reçoivent `ENABLE ROW LEVEL SECURITY` **et** la
--     révocation des droits directs : mesuré le 24/09/2026, une partition
--     héritait des privilèges par défaut et restait lisible EN DIRECT (la
--     politique du parent ne s'applique qu'en passant par le parent) ;
--   * 3 mois de partitions sont créés d'avance, et `chain_ensure_partitions()`
--     REFUSE de rattacher une partition dont les lignes sont déjà dans la
--     partition par défaut (PostgreSQL rejette le rattachement : « updated
--     partition constraint for default partition would be violated ») : le
--     message nomme le mois et le nombre de lignes à déplacer.
--
-- CONVENTIONS DE SÉCURITÉ, APPLIQUÉES DÈS LA CRÉATION (§3.5)
--   * RLS activée ET forcée sur les six tables ; UNE politique par commande
--     (jamais deux permissives — la leçon d'ISO-03) ;
--   * lecture seule pour le client : `document_links`, `domain_events`,
--     `chain_traces` et `chain_regeneration_log` sont écrits par les fonctions
--     (SECURITY DEFINER, propriétaire de la table) et LUS par la société —
--     `REVOKE ALL … FROM authenticated` puis `GRANT SELECT` ;
--   * la société d'une écriture vient de la SOURCE, jamais de la session
--     (point 7 de la définition de « terminé », §4.1) ;
--   * aucune clé étrangère inter-société : `(tenant_id, amont_id)` et
--     `(tenant_id, aval_id)` sont tenus par la clé unique et la politique, pas
--     par une clé étrangère mono-colonne (ISO-02).
-- ============================================================
-- ─────────────────────────────────────────────────────────────
-- 1. QUI A PRODUIT QUOI — le registre de chaîne (M-10, M-11, M-12)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS document_links (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  amont_type     text NOT NULL,
  amont_id       uuid NOT NULL,
  amont_ligne_id uuid,
  aval_type      text NOT NULL,
  aval_id        uuid NOT NULL,
  aval_ligne_id  uuid,
  link_type      text NOT NULL,
  effet          text NOT NULL,
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_links_link_type_check CHECK (link_type IN (
    'created_from', 'delivered_by', 'invoiced_by', 'paid_by',
    'reversed_by', 'adjusted_by', 'generated_entry', 'consumed_by_absence')),
  CONSTRAINT document_links_amont_check CHECK (btrim(amont_type) <> ''),
  CONSTRAINT document_links_aval_check  CHECK (btrim(aval_type) <> ''),
  CONSTRAINT document_links_effet_check CHECK (btrim(effet) <> '')
);

COMMENT ON TABLE document_links IS
  '252 (L0) : registre de chaîne — quel document a produit quel document, par quel maillon. Écrit seulement par link_documents(), lu par la société.';
COMMENT ON COLUMN document_links.effet IS
  'Identifiant du maillon qui a créé le lien (ex. « sale.delivery.stock_out ») : c''est la clé d''idempotence, avec le tenant et l''amont.';
COMMENT ON COLUMN document_links.amont_ligne_id IS
  'M-09 : la ligne, pas seulement l''en-tête — indispensable en livraison et réception partielles.';
COMMENT ON COLUMN document_links.payload IS
  'Quantités, montants, identifiants nécessaires à l''analyse d''impact (M-12). Aucune donnée personnelle : la purge RGPD ne doit pas casser l''audit.';

-- ─────────────────────────────────────────────────────────────
-- 2. CE QUE CE DOCUMENT DOIT PRODUIRE — le contrat d'effet (M-05)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS document_effects (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid REFERENCES tenants(id) ON DELETE CASCADE,
  document_type   text NOT NULL,
  evenement       text NOT NULL,
  effet           text NOT NULL,
  ecrit_comptable boolean NOT NULL DEFAULT false,
  journal_code    text,
  touche_stock    boolean NOT NULL DEFAULT false,
  touche_paie     boolean NOT NULL DEFAULT false,
  reversible      boolean NOT NULL DEFAULT true,
  obligatoire     boolean NOT NULL DEFAULT false,
  actif           boolean NOT NULL DEFAULT true,
  note            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_effects_types_check CHECK (
    btrim(document_type) <> '' AND btrim(evenement) <> '' AND btrim(effet) <> '')
);

-- L'unicité du contrat, standard (tenant_id NULL) ou propre à une société.
-- Une contrainte PRIMARY KEY n'accepte pas d'expression : c'est un index unique
-- sur la même expression, et c'est lui que `ON CONFLICT` retrouvera.
CREATE UNIQUE INDEX IF NOT EXISTS uq_document_effects_contrat
  ON document_effects (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
                       document_type, evenement, effet);

COMMENT ON TABLE document_effects IS
  '252 (L0) : le contrat d''effet — ce que chaque type de document produit, par événement. tenant_id NULL = contrat standard livré avec le produit ; une ligne de société l''emporte (et peut le désactiver par `actif = false`).';
COMMENT ON COLUMN document_effects.actif IS
  '252 : false = la société a explicitement éteint un effet (typiquement un effet standard). chain_autorise rend cette valeur, jamais un simple « la ligne existe ».';
COMMENT ON COLUMN document_effects.obligatoire IS
  'true = le chaînage ne peut pas être court-circuité par l''utilisateur (pas de validation manuelle du document sans son effet).';

-- ─────────────────────────────────────────────────────────────
-- 3. CE QUI S'EST PASSÉ — le registre d'événements (M-13, I-06)
--    Partitionné par mois : un million de lignes par an et par société ne doit
--    pas ralentir l'écriture (§3.3). La partition par défaut évite l'échec
--    d'insertion ; les partitions du mois sont créées par chain_ensure_partitions().
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS domain_events (
  id             bigserial,
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  event_name     text NOT NULL,
  aggregate_type text NOT NULL,
  aggregate_id   uuid NOT NULL,
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor_id       uuid,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, created_at),
  CONSTRAINT domain_events_nom_check CHECK (btrim(event_name) <> ''),
  CONSTRAINT domain_events_agregat_check CHECK (btrim(aggregate_type) <> '')
) PARTITION BY RANGE (created_at);

COMMENT ON TABLE domain_events IS
  '252 (L0) : journal d''événements lisible par société (M-13) — notifications, webhooks, audit et automatisations du client s''y branchent. Partitionné par mois, rétention 24 mois.';
COMMENT ON COLUMN domain_events.payload IS
  'Aucune donnée personnelle non nécessaire : montants et identifiants seulement, pour que la purge RGPD ne casse pas l''audit (§3.5).';

-- ─────────────────────────────────────────────────────────────
-- 4. CE QUI A ÉTÉ RECALCULÉ — l'historique des régénérations (M-04)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_regeneration_log (
  id         bigserial PRIMARY KEY,
  tenant_id  uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  effet      text NOT NULL,
  amont_type text NOT NULL,
  amont_id   uuid NOT NULL,
  cause      text NOT NULL,
  avant      jsonb,
  apres      jsonb,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chain_regeneration_log_cause_check CHECK (btrim(cause) <> '')
);

COMMENT ON TABLE chain_regeneration_log IS
  '252 (L0) : ce que chaque régénération a changé, et pourquoi (M-04 : régénérer plutôt que corriger à la main). Append-only : il ne se corrige pas, il se relit.';

-- ─────────────────────────────────────────────────────────────
-- 5. LA MESURE DE CHAQUE MAILLON — chain_traces (§3.4)
--    Un chaînage qui ne se mesure pas ne s'améliore pas : chaque exécution
--    laisse une ligne (durée, lignes écrites, verrous attendus, résultat).
--    Partitionné comme domain_events.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_traces (
  id                  bigserial,
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  effet               text NOT NULL,
  amont_type          text NOT NULL,
  amont_id            uuid NOT NULL,
  amont_ligne_id      uuid,
  duree_ms            integer NOT NULL DEFAULT 0,
  lignes_ecrites      integer NOT NULL DEFAULT 0,
  verrous_attendus_ms integer,
  resultat            text NOT NULL,
  message             text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, created_at),
  CONSTRAINT chain_traces_resultat_check CHECK (resultat IN (
    'applique', 'ignore', 'tolere', 'refuse', 'regenere')),
  CONSTRAINT chain_traces_effet_check CHECK (btrim(effet) <> '')
) PARTITION BY RANGE (created_at);

COMMENT ON TABLE chain_traces IS
  '252 (L0) : trace d''exécution de chaque maillon (§3.4) — les trois tableaux de bord internes (performance p50/p95/p99, refus, régénérations) se lisent ici.';
COMMENT ON COLUMN chain_traces.resultat IS
  'applique = effet produit ; ignore = déjà appliqué (rejeu) ; tolere = effet non déclaré au contrat, appliqué parce que la société n''est pas en refuse ; refuse = bloqué, avec le message vu par l''utilisateur ; regenere = recalcul.';
COMMENT ON COLUMN chain_traces.lignes_ecrites IS
  'Sert à voir les maillons bavards (une écriture par ligne au lieu d''un seul INSERT … SELECT) : le budget §3.3 les refuse.';

-- ─────────────────────────────────────────────────────────────
-- 6. LE DRAPEAU D'APPLICATION PAR SOCIÉTÉ (§3.6)
--    observe → avertit → refuse : on mesure le taux de refus AVANT de bloquer
--    un client existant. L'absence de ligne vaut `observe`.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_settings (
  tenant_id   uuid PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  enforcement text NOT NULL DEFAULT 'observe'
    CONSTRAINT chain_settings_enforcement_check CHECK (enforcement IN ('observe', 'avertit', 'refuse')),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid
);

COMMENT ON TABLE chain_settings IS
  '252 (L0) : mode d''application des contrats d''effet, par société. observe = on trace sans bloquer ; avertit = on trace et on avertit ; refuse = on bloque avec un message nommant document, date, règle et module.';


-- ─────────────────────────────────────────────────────────────
-- 7. Les index (sans eux, les budgets §3.3 ne tiennent pas)
--    Tout maillon qui filtre sur une colonne non indexée est refusé en revue.
-- ─────────────────────────────────────────────────────────────
-- La clé d'idempotence structurelle (M-02) : rejouer un maillon ne double rien.
-- L'expression COALESCE permet une ligne sans ligne source (amont_ligne_id NULL).
CREATE UNIQUE INDEX IF NOT EXISTS uq_document_links_effet
  ON document_links (tenant_id, amont_type, amont_id, effet,
                     COALESCE(amont_ligne_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Navigation amont → aval, aval → amont, et par type de lien (M-10, M-12).
CREATE INDEX IF NOT EXISTS ix_document_links_amont ON document_links (tenant_id, amont_type, amont_id);
CREATE INDEX IF NOT EXISTS ix_document_links_aval  ON document_links (tenant_id, aval_type, aval_id);
CREATE INDEX IF NOT EXISTS ix_document_links_type  ON document_links (tenant_id, link_type, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_document_links_aval_ligne
  ON document_links (tenant_id, aval_ligne_id) WHERE aval_ligne_id IS NOT NULL;

-- Le contrat se lit par (type de document, événement) : c'est la clé de lecture
-- de chain_autorise, appelée au début de chaque maillon.
CREATE INDEX IF NOT EXISTS ix_document_effects_societe
  ON document_effects (tenant_id, document_type, evenement);

-- Le journal d'activité se lit par agrégat (la fiche d'un document) et par nom
-- d'événement (les automatisations et webhooks).
CREATE INDEX IF NOT EXISTS ix_domain_events_agregat
  ON domain_events (tenant_id, aggregate_type, aggregate_id);
CREATE INDEX IF NOT EXISTS ix_domain_events_nom
  ON domain_events (tenant_id, event_name, created_at DESC);

-- Les régénérations se relisent par document et par cause (paramétrage instable).
CREATE INDEX IF NOT EXISTS ix_chain_regeneration_log_amont
  ON chain_regeneration_log (tenant_id, amont_type, amont_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_chain_regeneration_log_cause
  ON chain_regeneration_log (tenant_id, cause, created_at DESC);

-- Les traces : par maillon (p50/p95/p99) et par refus (règles mal comprises).
CREATE INDEX IF NOT EXISTS ix_chain_traces_effet
  ON chain_traces (tenant_id, effet, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_chain_traces_refus
  ON chain_traces (tenant_id, resultat, created_at DESC);

-- ─────────────────────────────────────────────────────────────
-- 8. Cloisonnement : RLS activée ET forcée, UNE politique par commande
--    Aucune politique d'écriture : les écritures passent par les fonctions du
--    socle (SECURITY DEFINER, propriétaire de la table), jamais par le client.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE document_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_links FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS document_links_select_societe ON document_links;
CREATE POLICY document_links_select_societe ON document_links
  FOR SELECT USING (tenant_id = current_tenant_id());

ALTER TABLE domain_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE domain_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS domain_events_select_societe ON domain_events;
CREATE POLICY domain_events_select_societe ON domain_events
  FOR SELECT USING (tenant_id = current_tenant_id());

ALTER TABLE chain_traces ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_traces FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_traces_select_societe ON chain_traces;
CREATE POLICY chain_traces_select_societe ON chain_traces
  FOR SELECT USING (tenant_id = current_tenant_id());

ALTER TABLE chain_regeneration_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_regeneration_log FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_regeneration_log_select_societe ON chain_regeneration_log;
CREATE POLICY chain_regeneration_log_select_societe ON chain_regeneration_log
  FOR SELECT USING (tenant_id = current_tenant_id());

-- Le contrat standard (tenant_id NULL) est lisible par tous les utilisateurs
-- connectés : c'est une donnée de référence, pas une donnée de société.
ALTER TABLE document_effects ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_effects FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS document_effects_select ON document_effects;
CREATE POLICY document_effects_select ON document_effects
  FOR SELECT USING (tenant_id IS NULL OR tenant_id = current_tenant_id());

-- Le mode d'application se lit par la société active ; il s'écrit par la
-- fonction chain_set_enforcement() (droit vérifié), jamais en direct.
ALTER TABLE chain_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_settings FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_settings_select_societe ON chain_settings;
CREATE POLICY chain_settings_select_societe ON chain_settings
  FOR SELECT USING (tenant_id = current_tenant_id());

-- ─────────────────────────────────────────────────────────────
-- 9. Droits : lecture seule pour le client, aucune écriture directe
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON TABLE document_links, document_effects, domain_events,
  chain_traces, chain_regeneration_log, chain_settings
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE document_links, document_effects, domain_events,
  chain_traces, chain_regeneration_log, chain_settings
  TO authenticated, service_role;


-- ─────────────────────────────────────────────────────────────
-- 10. Les six fonctions utilitaires du plan (§3.2)
--     Écrites une fois, appelées 62 fois. Aucune ne contient de logique
--     métier : c'est ce qui les rend transverses.
-- ─────────────────────────────────────────────────────────────

-- a) Déclarer un lien (idempotent) : LA fonction que tous les maillons appellent.
--    Le rejeu ne double rien (index unique) et FUSIONNE le payload, pour que la
--    seconde exécution apporte son information au lieu de la perdre.
CREATE OR REPLACE FUNCTION public.link_documents(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_aval_type   text,
  p_aval_id     uuid,
  p_effet       text,
  p_link_type   text,
  p_payload     jsonb DEFAULT '{}'::jsonb,
  p_amont_ligne uuid DEFAULT NULL,
  p_aval_ligne  uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_id uuid;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Chaînage refusé : aucune société — un lien sans société n''existe pas (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;
  IF p_amont_id IS NULL OR p_aval_id IS NULL THEN
    RAISE EXCEPTION 'Chaînage refusé : le lien % → % est incomplet (identifiant amont ou aval absent).',
      p_amont_type, p_aval_type USING ERRCODE = '23514';
  END IF;
  IF COALESCE(btrim(p_effet), '') = '' THEN
    RAISE EXCEPTION 'Chaînage refusé : maillon sans nom (effet vide). Un lien sans effet n''est pas idempotent.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO document_links (tenant_id, amont_type, amont_id, amont_ligne_id,
                              aval_type, aval_id, aval_ligne_id,
                              link_type, effet, payload, created_by)
  VALUES (p_tenant, p_amont_type, p_amont_id, p_amont_ligne,
          p_aval_type, p_aval_id, p_aval_ligne,
          p_link_type, p_effet, COALESCE(p_payload, '{}'::jsonb), auth.uid())
  ON CONFLICT (tenant_id, amont_type, amont_id, effet,
               COALESCE(amont_ligne_id, '00000000-0000-0000-0000-000000000000'::uuid))
  DO UPDATE SET payload       = document_links.payload || EXCLUDED.payload,
                link_type     = EXCLUDED.link_type,
                aval_type     = EXCLUDED.aval_type,
                aval_id       = EXCLUDED.aval_id,
                aval_ligne_id = EXCLUDED.aval_ligne_id
  RETURNING id INTO v_id;

  RETURN v_id;
END $fn$;

COMMENT ON FUNCTION public.link_documents(uuid, text, uuid, text, uuid, text, text, jsonb, uuid, uuid) IS
  'L0 : déclare un lien amont → aval pour un effet donné. Idempotent (index unique + ON CONFLICT) et fusionne le payload au rejeu. Rend l''identifiant du lien.';

-- b) Le lien existe-t-il déjà ? (M-02 : appelée en entrée de chaque maillon)
CREATE OR REPLACE FUNCTION public.chain_deja_fait(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_effet       text,
  p_amont_ligne uuid DEFAULT NULL
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM document_links dl
    WHERE dl.tenant_id = p_tenant
      AND dl.amont_type = p_amont_type
      AND dl.amont_id = p_amont_id
      AND dl.effet = p_effet
      AND dl.amont_ligne_id IS NOT DISTINCT FROM p_amont_ligne)
$fn$;

-- c) Le lien amont ↔ aval est-il intact ? (M-03 : condition de réversibilité)
CREATE OR REPLACE FUNCTION public.chain_integrity_ok(
  p_tenant     uuid,
  p_amont_type text,
  p_amont_id   uuid,
  p_aval_type  text,
  p_aval_id    uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM document_links dl
    WHERE dl.tenant_id = p_tenant
      AND dl.amont_type = p_amont_type
      AND dl.amont_id = p_amont_id
      AND dl.aval_type = p_aval_type
      AND dl.aval_id = p_aval_id)
$fn$;


-- d) Émettre un événement lisible (M-13) : notifications, webhooks, audit,
--    automatisations du client se branchent sur ce même journal.
CREATE OR REPLACE FUNCTION public.emit_domain_event(
  p_tenant         uuid,
  p_event_name     text,
  p_aggregate_type text,
  p_aggregate_id   uuid,
  p_payload        jsonb DEFAULT '{}'::jsonb,
  p_actor          uuid DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_id bigint;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Événement refusé : aucune société (cloisonnement fermé).' USING ERRCODE = '23514';
  END IF;
  IF COALESCE(btrim(p_event_name), '') = '' THEN
    RAISE EXCEPTION 'Événement refusé : nom d''événement vide.' USING ERRCODE = '23514';
  END IF;

  INSERT INTO domain_events (tenant_id, event_name, aggregate_type, aggregate_id, payload, actor_id)
  VALUES (p_tenant, p_event_name, p_aggregate_type, p_aggregate_id,
          COALESCE(p_payload, '{}'::jsonb), COALESCE(p_actor, auth.uid()))
  RETURNING id INTO v_id;

  RETURN v_id;
END $fn$;

-- e) Le contrat autorise-t-il cet effet ? (M-05 : lu avant chaque maillon)
--    La ligne de la société l'emporte sur le contrat standard ; rien de déclaré
--    vaut FAUX — le contrat est fermé par défaut. Le drapeau de la société
--    (chain_settings) décide ensuite si ce refus bloque ou seulement se trace.
CREATE OR REPLACE FUNCTION public.chain_autorise(
  p_tenant        uuid,
  p_document_type text,
  p_evenement     text,
  p_effet         text
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_actif boolean;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Contrat : aucune société (cloisonnement fermé).' USING ERRCODE = '23514';
  END IF;

  SELECT e.actif INTO v_actif
  FROM document_effects e
  WHERE e.document_type = p_document_type
    AND e.evenement = p_evenement
    AND e.effet = p_effet
    AND (e.tenant_id = p_tenant OR e.tenant_id IS NULL)
  ORDER BY (e.tenant_id IS NULL), e.created_at DESC
  LIMIT 1;

  RETURN COALESCE(v_actif, false);
END $fn$;

COMMENT ON FUNCTION public.chain_autorise(uuid, text, text, text) IS
  'L0 : lit le contrat d''effet — la ligne de la société l''emporte sur le contrat standard, et son `actif` fait foi. Rien de déclaré = false (fermé par défaut).';

-- f) Régénérer un effet de façon traçable (M-04)
--    Le socle ne recalcule pas un effet qu'il ne connaît pas : il REFUSE de
--    régénérer ce qui n'a jamais été appliqué (aucun lien), enregistre ce qui
--    change (avant / après) et émet l'événement. Le recalcul lui-même reste au
--    maillon, qui appelle cette fonction après avoir repris son effet.
CREATE OR REPLACE FUNCTION public.chain_regenerate(
  p_tenant     uuid,
  p_effet      text,
  p_amont_type text,
  p_amont_id   uuid,
  p_cause      text,
  p_apres      jsonb DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_avant jsonb;
  v_id    bigint;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Régénération refusée : aucune société (cloisonnement fermé).' USING ERRCODE = '23514';
  END IF;

  SELECT jsonb_agg(dl.payload) INTO v_avant
  FROM document_links dl
  WHERE dl.tenant_id = p_tenant
    AND dl.amont_type = p_amont_type
    AND dl.amont_id = p_amont_id
    AND dl.effet = p_effet;

  IF v_avant IS NULL THEN
    RAISE EXCEPTION 'Régénération refusée : aucun lien « % » pour % (%) — il n''y a rien à régénérer. Le maillon doit d''abord produire l''effet (link_documents).',
      p_effet, p_amont_type, p_amont_id USING ERRCODE = '23514';
  END IF;

  INSERT INTO chain_regeneration_log (tenant_id, effet, amont_type, amont_id, cause, avant, apres, created_by)
  VALUES (p_tenant, p_effet, p_amont_type, p_amont_id, p_cause, v_avant, p_apres, auth.uid())
  RETURNING id INTO v_id;

  PERFORM emit_domain_event(p_tenant, 'chain.regenerated', p_amont_type, p_amont_id,
    jsonb_build_object('effet', p_effet, 'cause', p_cause, 'regeneration_id', v_id), NULL);

  RETURN v_id;
END $fn$;

COMMENT ON FUNCTION public.chain_regenerate(uuid, text, text, uuid, text, jsonb) IS
  'L0 : enregistre une régénération (avant / après, cause, auteur) et émet chain.regenerated. Refuse si aucun lien n''existe : on ne régénère pas ce qui n''a jamais été appliqué.';


-- ─────────────────────────────────────────────────────────────
-- 11. Le gabarit de maillon (§3.2, §3.4) — l'idempotence, le contrat et la
--     mesure écrites UNE fois. Tout maillon commence par chain_avant() et finit
--     par chain_apres() ; entre les deux, il produit son effet et appelle
--     link_documents() + emit_domain_event().
-- ─────────────────────────────────────────────────────────────

-- La trace brute : une ligne par exécution de maillon (§3.4).
CREATE OR REPLACE FUNCTION public.chain_trace(
  p_tenant             uuid,
  p_effet              text,
  p_amont_type         text,
  p_amont_id           uuid,
  p_duree_ms           integer,
  p_lignes_ecrites     integer,
  p_verrous_attendus_ms integer,
  p_resultat           text,
  p_message            text,
  p_amont_ligne        uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Trace refusée : aucune société (cloisonnement fermé).' USING ERRCODE = '23514';
  END IF;
  IF COALESCE(p_duree_ms, 0) < 0 OR COALESCE(p_lignes_ecrites, 0) < 0 THEN
    RAISE EXCEPTION 'Trace refusée pour « % » : durée ou nombre de lignes négatif (% ms, % lignes).',
      p_effet, p_duree_ms, p_lignes_ecrites USING ERRCODE = '23514';
  END IF;

  INSERT INTO chain_traces (tenant_id, effet, amont_type, amont_id, amont_ligne_id,
                            duree_ms, lignes_ecrites, verrous_attendus_ms, resultat, message)
  VALUES (p_tenant, p_effet, p_amont_type, p_amont_id, p_amont_ligne,
          COALESCE(p_duree_ms, 0), COALESCE(p_lignes_ecrites, 0), p_verrous_attendus_ms,
          p_resultat, p_message);
END $fn$;

-- L'entrée du maillon : idempotence (a-t-on déjà produit cet effet ?) puis
-- contrat (a-t-on le droit ?), et le drapeau de la société décide si l'absence
-- de déclaration bloque.
--   TRUE  → le maillon doit produire son effet ;
--   FALSE → il ne doit rien faire (déjà appliqué).
CREATE OR REPLACE FUNCTION public.chain_avant(
  p_tenant        uuid,
  p_document_type text,
  p_evenement     text,
  p_effet         text,
  p_amont_type    text,
  p_amont_id      uuid,
  p_amont_ligne   uuid DEFAULT NULL,
  p_message_refus text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_mode text;
  v_msg  text;
BEGIN
  -- 1. Idempotence structurelle (M-02) : le rejeu ne fait rien, et le dit.
  IF chain_deja_fait(p_tenant, p_amont_type, p_amont_id, p_effet, p_amont_ligne) THEN
    PERFORM chain_trace(p_tenant, p_effet, p_amont_type, p_amont_id, 0, 0, NULL,
      'ignore', 'Chaînage déjà appliqué — rejeu sans effet.', p_amont_ligne);
    RETURN false;
  END IF;

  -- 2. Contrat (M-05) : déclaré et actif → on procède.
  IF chain_autorise(p_tenant, p_document_type, p_evenement, p_effet) THEN
    RETURN true;
  END IF;

  -- 3. Non déclaré : le drapeau de la société décide (observe → avertit → refuse).
  v_mode := chain_enforcement_mode(p_tenant);
  v_msg  := COALESCE(NULLIF(btrim(p_message_refus), ''), format(
    'Chaînage non déclaré — règle « %s » absente du contrat du document %s (événement « %s »), module %s, société %s, le %s.',
    p_effet, p_document_type, p_evenement, p_amont_type, p_tenant,
    to_char(now(), 'DD/MM/YYYY HH24:MI')));

  IF v_mode = 'refuse' THEN
    PERFORM chain_trace(p_tenant, p_effet, p_amont_type, p_amont_id, 0, 0, NULL,
      'refuse', v_msg, p_amont_ligne);
    RAISE EXCEPTION '%', v_msg USING ERRCODE = '23514';
  END IF;

  IF v_mode = 'avertit' THEN
    RAISE WARNING '% (mode avertit)', v_msg;
  END IF;

  PERFORM chain_trace(p_tenant, p_effet, p_amont_type, p_amont_id, 0, 0, NULL,
    'tolere', v_msg || format(' (mode %s : l''effet est appliqué sans contrat)', v_mode), p_amont_ligne);
  RETURN true;
END $fn$;

COMMENT ON FUNCTION public.chain_avant(uuid, text, text, text, text, uuid, uuid, text) IS
  'L0 : entrée de tout maillon — rejeu (rend false et trace « ignore »), contrat lu, puis drapeau de la société (observe = trace « tolere », avertit = avertissement + « tolere », refuse = exception avec message nominatif).';


-- La sortie du maillon : ce qu'il a fait, en combien de temps, en combien de
-- lignes (§3.4). Rend la durée mesurée, pour que les budgets §3.3 s'avisent.
CREATE OR REPLACE FUNCTION public.chain_apres(
  p_tenant              uuid,
  p_effet               text,
  p_amont_type          text,
  p_amont_id            uuid,
  p_debut               timestamptz,
  p_lignes_ecrites      integer DEFAULT 0,
  p_resultat            text DEFAULT 'applique',
  p_message             text DEFAULT NULL,
  p_verrous_attendus_ms integer DEFAULT NULL,
  p_amont_ligne         uuid DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_duree integer;
BEGIN
  IF p_debut IS NULL THEN
    RAISE EXCEPTION 'Trace refusée pour « % » : instant de début absent — une trace sans durée ne mesure rien.', p_effet
      USING ERRCODE = '23514';
  END IF;

  v_duree := GREATEST(0, round(EXTRACT(EPOCH FROM (clock_timestamp() - p_debut)) * 1000))::integer;

  PERFORM chain_trace(p_tenant, p_effet, p_amont_type, p_amont_id, v_duree,
    p_lignes_ecrites, p_verrous_attendus_ms, p_resultat, p_message, p_amont_ligne);

  RETURN v_duree;
END $fn$;

COMMENT ON FUNCTION public.chain_apres(uuid, text, text, uuid, timestamptz, integer, text, text, integer, uuid) IS
  'L0 : sortie de tout maillon — écrit la trace (durée mesurée, lignes écrites, verrous attendus, résultat) et rend la durée en millisecondes, à comparer aux budgets §3.3.';

-- ─────────────────────────────────────────────────────────────
-- 12. Le drapeau d'application par société (§3.6)
-- ─────────────────────────────────────────────────────────────
-- Absence de ligne = `observe` : une société existante ne peut pas être bloquée
-- par une déclaration manquante. Société absente (NULL) = refus, jamais un
-- « observe » silencieux.
CREATE OR REPLACE FUNCTION public.chain_enforcement_mode(p_tenant uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_mode text;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Mode d''application : aucune société (cloisonnement fermé).' USING ERRCODE = '23514';
  END IF;

  SELECT cs.enforcement INTO v_mode FROM chain_settings cs WHERE cs.tenant_id = p_tenant;
  RETURN COALESCE(v_mode, 'observe');
END $fn$;

-- Le réglage : réservé à la société ACTIVE (la session) et à un rôle qui en a
-- le droit — un appel direct ne change pas le mode d'une autre société.
CREATE OR REPLACE FUNCTION public.chain_set_enforcement(p_tenant uuid, p_mode text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF p_tenant IS NULL OR p_tenant IS DISTINCT FROM current_tenant_id() THEN
    RAISE EXCEPTION 'Mode d''application refusé : le réglage ne porte que sur la société active.'
      USING ERRCODE = '42501';
  END IF;
  IF p_mode NOT IN ('observe', 'avertit', 'refuse') THEN
    RAISE EXCEPTION 'Mode d''application refusé : « % » n''existe pas (observe, avertit, refuse).', p_mode
      USING ERRCODE = '22023';
  END IF;
  IF NOT can_perform('chain_settings', 'update') THEN
    RAISE EXCEPTION 'Mode d''application refusé : votre rôle ne porte pas le droit de régler les chaînages.'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO chain_settings (tenant_id, enforcement, updated_at, updated_by)
  VALUES (p_tenant, p_mode, now(), auth.uid())
  ON CONFLICT (tenant_id) DO UPDATE
    SET enforcement = EXCLUDED.enforcement,
        updated_at  = EXCLUDED.updated_at,
        updated_by  = EXCLUDED.updated_by;

  PERFORM emit_domain_event(p_tenant, 'chain.enforcement_changed', 'chain_settings', p_tenant,
    jsonb_build_object('mode', p_mode), NULL);

  RETURN p_mode;
END $fn$;

COMMENT ON FUNCTION public.chain_set_enforcement(uuid, text) IS
  'L0 : règle le mode (observe | avertit | refuse) de la société ACTIVE, avec droit `can_perform` et événement chain.enforcement_changed.';


-- ─────────────────────────────────────────────────────────────
-- 13. Les partitions : la partition par défaut, trois mois d'avance, et de quoi
--     tenir la suite (§3.3 point 3 : un million de lignes par an et par société).
-- ─────────────────────────────────────────────────────────────
-- La partition par défaut évite qu'une écriture échoue faute de partition : la
-- chaîne ne casse jamais pour une question de calendrier.
CREATE TABLE IF NOT EXISTS domain_events_defaut PARTITION OF domain_events DEFAULT;
CREATE TABLE IF NOT EXISTS chain_traces_defaut  PARTITION OF chain_traces  DEFAULT;

ALTER TABLE domain_events_defaut ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_traces_defaut  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE domain_events_defaut FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE chain_traces_defaut  FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE domain_events_defaut IS
  '252 : partition par défaut du journal d''événements. Droits directs retirés, RLS activée : la lecture passe par domain_events (la politique du parent).';
COMMENT ON TABLE chain_traces_defaut IS
  '252 : partition par défaut des traces de chaînage. Droits directs retirés, RLS activée : la lecture passe par chain_traces (la politique du parent).';

-- Créer les partitions d'UNE table partitionnée du socle (le nom de table est un
-- paramètre : l'analyse statique de `plpgsql_check` ne peut donc pas résoudre le
-- SQL dynamique en une relation qui n'existe pas — mesuré sur le premier jet,
-- qui passait le tableau à FOREACH et faisait échouer `ci/check_plpgsql.sql`).
CREATE OR REPLACE FUNCTION public.chain_ensure_partitions_table(p_table text, p_mois integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_debut  timestamptz;
  v_fin    timestamptz;
  v_nom    text;
  v_lignes bigint;
  v_creees integer := 0;
  i        integer;
BEGIN
  -- Liste blanche ET vérification de structure : le nom vient du code, et la
  -- table doit être une table partitionnée du socle — jamais une table ordinaire.
  IF p_table NOT IN ('domain_events', 'chain_traces') THEN
    RAISE EXCEPTION 'Partitions : table « % » hors du socle des chaînages (domain_events, chain_traces).', p_table
      USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = p_table AND c.relkind = 'p') THEN
    RAISE EXCEPTION 'Partitions : % n''est pas une table partitionnée du socle.', p_table
      USING ERRCODE = '22023';
  END IF;
  IF p_mois IS NULL OR p_mois < 0 OR p_mois > 24 THEN
    RAISE EXCEPTION 'Partitions : % mois d''avance demandés, hors bornes (0 à 24).', p_mois
      USING ERRCODE = '22023';
  END IF;

  FOR i IN 0..p_mois LOOP
    v_debut := date_trunc('month', now()) + make_interval(months => i);
    v_fin   := v_debut + interval '1 month';
    v_nom   := p_table || '_' || to_char(v_debut, 'YYYY_MM');

    CONTINUE WHEN EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_nom AND c.relkind IN ('r', 'p'));

    -- Rattacher une partition qui recouvre des lignes déjà écrites dans la
    -- partition par défaut est refusé par PostgreSQL ; on refuse plus tôt, et
    -- le message dit combien de lignes déplacer.
    EXECUTE format('SELECT count(*) FROM %I.%I WHERE created_at >= $1 AND created_at < $2', 'public', p_table)
      INTO v_lignes USING v_debut, v_fin;

    IF v_lignes > 0 THEN
      RAISE EXCEPTION 'Partition % : la partition par défaut porte déjà % ligne(s) entre % et % — PostgreSQL refuse de rattacher une partition qui les recouvre. Déplacez ces lignes (voir l''en-tête de la 252) avant de relancer.',
        v_nom, v_lignes, to_char(v_debut, 'YYYY-MM-DD'), to_char(v_fin, 'YYYY-MM-DD')
        USING ERRCODE = '23514';
    END IF;

    -- Le schéma est passé en paramètre, jamais concaténé : `check-unused-tables`
    -- lit le TEXTE des migrations, et le nom de schéma littéral après CREATE TABLE
    -- y faisait apparaître une table nommée « public » (repli de l'expression
    -- régulière, corrigé ici et mesuré par la suite 252).
    EXECUTE format('CREATE TABLE %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
                   'public', v_nom, 'public', p_table, v_debut, v_fin);
    -- Deux garde-fous mesurés : la politique du parent ne s'applique PAS à qui
    -- interroge la partition directement, et les privilèges par défaut de
    -- l'image Supabase ouvrent toute table nouvelle à `authenticated`.
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', 'public', v_nom);
    EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC, anon, authenticated', 'public', v_nom);
    EXECUTE format('COMMENT ON TABLE %I.%I IS %L', 'public', v_nom,
      format('252 : partition mensuelle de %s, créée par chain_ensure_partitions(). Droits directs retirés, RLS activée — la lecture passe par le parent.', p_table));

    v_creees := v_creees + 1;
  END LOOP;

  RETURN v_creees;
END $fn$;

CREATE OR REPLACE FUNCTION public.chain_ensure_partitions(p_mois integer DEFAULT 3)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF p_mois IS NULL OR p_mois < 0 OR p_mois > 24 THEN
    RAISE EXCEPTION 'Partitions : % mois d''avance demandés, hors bornes (0 à 24).', p_mois
      USING ERRCODE = '22023';
  END IF;

  RETURN chain_ensure_partitions_table('domain_events', p_mois)
       + chain_ensure_partitions_table('chain_traces', p_mois);
END $fn$;

COMMENT ON FUNCTION public.chain_ensure_partitions_table(text, integer) IS
  'L0 : crée les partitions mensuelles d''une table partitionnée du socle (domain_events, chain_traces), du mois courant à +p_mois. Refuse un nom hors socle, une table non partitionnée, et un mois dont les lignes sont restées dans la partition par défaut.';

COMMENT ON FUNCTION public.chain_ensure_partitions(integer) IS
  'L0 : crée les partitions mensuelles de domain_events et chain_traces (mois courant + p_mois). Appelée par le job nocturne du lot L4.';

-- Trois mois d'avance dès la création du socle.
SELECT public.chain_ensure_partitions(3) AS partitions_creees;


-- ─────────────────────────────────────────────────────────────
-- 14. Droits sur les fonctions : le socle n'est pas une API
-- ─────────────────────────────────────────────────────────────
-- Aucune de ces fonctions n'est une porte d'entrée : elles s'appellent depuis
-- les maillons (déclencheurs et fonctions SECURITY DEFINER, propriétaires des
-- tables). La 228 a montré que `CREATE FUNCTION` rétablit EXECUTE pour PUBLIC
-- à chaque migration : la révocation s'écrit donc à chaque fois, et
-- `ci/check_anon_grants.sql` est là pour le jour où une migration l'oubliera.
REVOKE ALL ON FUNCTION public.link_documents(uuid, text, uuid, text, uuid, text, text, jsonb, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_deja_fait(uuid, text, uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_integrity_ok(uuid, text, uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.emit_domain_event(uuid, text, text, uuid, jsonb, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_autorise(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_regenerate(uuid, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_trace(uuid, text, text, uuid, integer, integer, integer, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_avant(uuid, text, text, text, text, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_apres(uuid, text, text, uuid, timestamptz, integer, text, text, integer, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_enforcement_mode(uuid) FROM PUBLIC, anon, authenticated;

-- La maintenance des partitions sort du propriétaire : les scripts
-- d'exploitation (service_role) l'appellent sans passer par un maillon.
REVOKE ALL ON FUNCTION public.chain_ensure_partitions(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_ensure_partitions(integer) TO service_role;
REVOKE ALL ON FUNCTION public.chain_ensure_partitions_table(text, integer) FROM PUBLIC, anon, authenticated;

-- Le réglage du drapeau est la SEULE RPC du socle : la société active seulement,
-- et seulement pour un rôle qui porte le droit.
REVOKE ALL ON FUNCTION public.chain_set_enforcement(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_set_enforcement(uuid, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 15. Le gabarit de maillon — le squelette que copient les 62 maillons (lot L1)
--
--     Les six questions de la revue (§4.3), dans l'ordre du code : le contrat
--     existe-t-il ? que se passe-t-il si on rejoue ? si on annule ? si la
--     société voisine est active ? combien de requêtes pour N lignes ? que lit
--     l'utilisateur quand ça refuse ?
-- ─────────────────────────────────────────────────────────────
/*
CREATE OR REPLACE FUNCTION public.chain_<domaine>_<effet>()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_lignes integer := 0;
  v_aval   uuid;
BEGIN
  -- 1. ENTRÉE — rejeu, contrat, drapeau. Rend false si l'effet est déjà là.
  IF NOT chain_avant(NEW.tenant_id, 'sales_order', 'confirmed',
                     'sale.delivery.stock_out', 'sales_order', NEW.id, NULL,
                     format('Commande %s du %s : la sortie de stock ne peut pas être produite (règle sale.delivery.stock_out).',
                            NEW.number, to_char(NEW.date, 'DD/MM/YYYY')))
  THEN RETURN NEW; END IF;

  -- 2. L'EFFET — un seul INSERT … SELECT pour N lignes (jamais de requête par ligne).
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, reference_type, reference_id,
                               date, movement_date)
  SELECT NEW.tenant_id, l.product_id, NEW.warehouse_id, 'out', 'out',
         l.quantity, l.unit_cost, NEW.number, 'sales_order', NEW.id,
         NEW.date, NEW.date
  FROM sales_order_lines l
  WHERE l.tenant_id = NEW.tenant_id AND l.order_id = NEW.id
  RETURNING id INTO v_aval;
  GET DIAGNOSTICS v_lignes = ROW_COUNT;

  -- 3. LE LIEN ET L'ÉVÉNEMENT — l'ascendance, pour la vue chaîne et l'impact.
  PERFORM link_documents(NEW.tenant_id, 'sales_order', NEW.id,
                         'stock_movement', v_aval, 'sale.delivery.stock_out', 'delivered_by',
                         jsonb_build_object('lignes', v_lignes));
  PERFORM emit_domain_event(NEW.tenant_id, 'sales_order.delivered', 'sales_order', NEW.id,
                            jsonb_build_object('lignes', v_lignes), NULL);

  -- 4. LA MESURE — dans le budget (≤ 50 ms pour un maillon simple, §3.3).
  PERFORM chain_apres(NEW.tenant_id, 'sale.delivery.stock_out', 'sales_order', NEW.id,
                      v_debut, v_lignes, 'applique', NULL);

  RETURN NEW;
END $maillon$;

-- La réversibilité (point 4 du « terminé ») : extourner plutôt que corriger.
CREATE OR REPLACE FUNCTION public.chain_<domaine>_<effet>_reverse() … ;

-- L'annulation ne défait QUE si le lien est intact (M-03).
IF NOT chain_integrity_ok(NEW.tenant_id, 'sales_order', NEW.id, 'stock_movement', v_aval) THEN
  RAISE EXCEPTION 'Annulation refusée : le lien commande % → sortie de stock est rompu ; régénérer créerait un doublon silencieux.', NEW.number;
END IF;

-- Le contrôle d'effet (M-05) : la CI compare le réel à la déclaration.
-- Le contrat se déclare dans document_effects (lot L7), jamais dans le maillon.
*/

