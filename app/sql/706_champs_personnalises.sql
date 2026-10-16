-- 706 — champs_personnalises
-- Numéro pris le 2026-10-11T05:45:50.010Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.5 / PRJ-04 (partie F du plan du 05/10) : LES CHAMPS PERSONNALISÉS
--
-- Le constat. Les tables d'un premier jet (`custom_field_definitions`,
-- `custom_field_values`) ont été SUPPRIMÉES le 18/09 par la `164` (« nommées
-- NULLE PART »). F.5 les rétablit — parce qu'une société a toujours un champ que
-- le produit n'a pas prévu (un numéro d'affaire, une date de visite, une
-- classification interne) et qu'aujourd'hui elle n'a nulle part où le mettre.
--
-- Le modèle, et ce qui le rend tenable :
--   * une DÉFINITION décrit un champ pour un couple (module, entité) :
--     `(module='projects', entity='project', field_key='affaire_ref')`. Son
--     `field_type` est CONTRAINT (text/number/date/boolean/select), sa clé est
--     un identifiant technique (regex), et un `select` doit porter ses options ;
--   * une VALEUR porte le champ pour UN enregistrement (`record_id` = l'id de la
--     ligne visée). Elle est rattachée à sa définition par une clé COMPOSITE
--     `(tenant_id, definition_id)` : supprimer une définition emporte ses valeurs,
--     et une valeur ne peut pas viser la définition d'une autre société (ISO-02) ;
--   * un DÉCLENCHEUR tient la cohérence que les clés ne peuvent pas tenir : le
--     TYPE de la valeur suit la définition (`number` → un nombre, `boolean` →
--     vrai/faux, `select` → une des options), et un champ DÉSACTIVÉ n'accueille
--     plus de valeur. Refus NOMMÉS (`CUSTOM_FIELD_TYPE`, `CUSTOM_FIELD_OPTION`,
--     `CUSTOM_FIELD_INACTIVE`).
--
-- RLS FORCÉE, index de société, QUATRE politiques par table (une par commande —
-- la grille BT s'applique sans faire monter `moins_de_4_commandes`).
--
-- Premier module branché : les PROJETS (l'écran Paramètres → Champs personnalisés
-- gère les définitions et saisit les valeurs pour un projet). Le modèle est
-- générique : brancher un autre module = une définition de plus, pas un schéma.
-- ============================================================

CREATE TABLE IF NOT EXISTS custom_field_definitions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  module      text NOT NULL,
  entity      text NOT NULL,
  field_key   text NOT NULL CHECK (field_key ~ '^[a-z][a-z0-9_]*$'),
  label       text NOT NULL,
  field_type  text NOT NULL CHECK (field_type IN ('text', 'number', 'date', 'boolean', 'select')),
  options     jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_required boolean NOT NULL DEFAULT false,
  position    int NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, module, entity, field_key),
  UNIQUE (tenant_id, id),
  CHECK (field_type <> 'select' OR jsonb_array_length(options) > 0)
);

CREATE INDEX IF NOT EXISTS idx_custom_field_definitions_tenant
  ON custom_field_definitions(tenant_id);

CREATE TABLE IF NOT EXISTS custom_field_values (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  definition_id uuid NOT NULL,
  record_id     uuid NOT NULL,
  value         jsonb NOT NULL,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, definition_id, record_id),
  FOREIGN KEY (tenant_id, definition_id)
    REFERENCES custom_field_definitions (tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_custom_field_values_tenant ON custom_field_values(tenant_id);
CREATE INDEX IF NOT EXISTS idx_custom_field_values_record ON custom_field_values(record_id);


-- ============================================================
-- Le déclencheur : le TYPE de la valeur suit la DÉFINITION
-- ============================================================
CREATE OR REPLACE FUNCTION validate_custom_field_value()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_type     text;
  v_active   boolean;
  v_options  jsonb;
BEGIN
  SELECT field_type, is_active, options
    INTO v_type, v_active, v_options
    FROM custom_field_definitions
   WHERE id = NEW.definition_id AND tenant_id = NEW.tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CUSTOM_FIELD_UNKNOWN : définition de champ introuvable pour cette société';
  END IF;
  IF NOT v_active THEN
    RAISE EXCEPTION 'CUSTOM_FIELD_INACTIVE : ce champ est désactivé';
  END IF;

  IF v_type = 'number' AND jsonb_typeof(NEW.value) <> 'number' THEN
    RAISE EXCEPTION 'CUSTOM_FIELD_TYPE : un champ numérique attend un nombre';
  END IF;
  IF v_type = 'boolean' AND jsonb_typeof(NEW.value) <> 'boolean' THEN
    RAISE EXCEPTION 'CUSTOM_FIELD_TYPE : un champ vrai/faux attend un booléen';
  END IF;
  IF v_type IN ('text', 'date', 'select') AND jsonb_typeof(NEW.value) <> 'string' THEN
    RAISE EXCEPTION 'CUSTOM_FIELD_TYPE : ce champ attend du texte';
  END IF;
  IF v_type = 'select' AND NOT (v_options ? (NEW.value #>> '{}')) THEN
    RAISE EXCEPTION 'CUSTOM_FIELD_OPTION : valeur hors des options du champ';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_validate_custom_field_value ON custom_field_values;
CREATE TRIGGER trg_validate_custom_field_value
  BEFORE INSERT OR UPDATE ON custom_field_values
  FOR EACH ROW EXECUTE FUNCTION validate_custom_field_value();

-- Une fonction de DÉCLENCHEUR n'est pas une fonction de service : personne ne
-- l'appelle directement (PostgREST n'expose pas les fonctions `RETURNS trigger`).
-- Sans ce retrait, elle resterait exécutable par `PUBLIC` — donc par un visiteur
-- non connecté —, ce que `ci/check_anon_grants.sql` refuse.
REVOKE ALL ON FUNCTION validate_custom_field_value() FROM PUBLIC, anon;

-- ============================================================
-- RLS : forcée, quatre politiques par table
-- ============================================================
ALTER TABLE custom_field_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_field_definitions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS custom_field_definitions_select ON custom_field_definitions;
CREATE POLICY custom_field_definitions_select ON custom_field_definitions
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS custom_field_definitions_insert ON custom_field_definitions;
CREATE POLICY custom_field_definitions_insert ON custom_field_definitions
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS custom_field_definitions_update ON custom_field_definitions;
CREATE POLICY custom_field_definitions_update ON custom_field_definitions
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS custom_field_definitions_delete ON custom_field_definitions;
CREATE POLICY custom_field_definitions_delete ON custom_field_definitions
  FOR DELETE USING (tenant_id = current_tenant_id());

ALTER TABLE custom_field_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_field_values FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS custom_field_values_select ON custom_field_values;
CREATE POLICY custom_field_values_select ON custom_field_values
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS custom_field_values_insert ON custom_field_values;
CREATE POLICY custom_field_values_insert ON custom_field_values
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS custom_field_values_update ON custom_field_values;
CREATE POLICY custom_field_values_update ON custom_field_values
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS custom_field_values_delete ON custom_field_values;
CREATE POLICY custom_field_values_delete ON custom_field_values
  FOR DELETE USING (tenant_id = current_tenant_id());

-- Le visiteur n'écrit rien (les défauts du schéma donnent `ALL` à `anon` sur
-- toute table neuve — on le retire ici).
REVOKE ALL ON custom_field_definitions, custom_field_values FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON custom_field_definitions, custom_field_values TO authenticated;
GRANT ALL ON custom_field_definitions, custom_field_values TO service_role;

