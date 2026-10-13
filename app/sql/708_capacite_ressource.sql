-- 708 — capacite_ressource
-- Numéro pris le 2026-10-11T06:11:58.809Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.5 / PRJ-02 (partie F du plan du 05/10) : LA CAPACITÉ PAR RESSOURCE
--
-- Le constat. Les tables d'un premier jet (`resource_capacities`) ont été
-- SUPPRIMÉES le 18/09 par la `164` (« nommées NULLE PART »). F.5 les rétablit :
-- planifier un projet suppose de savoir QUI a COMBIEN d'heures disponibles sur
-- QUELLE période — et le produit ne le disait nulle part.
--
-- Le modèle : une ligne = « ce salarié a N heures par semaine, de telle date à
-- telle date ». Ce qui le rend tenable :
--   * la capacité est rattachée au salarié par une clé COMPOSITE
--     `(tenant_id, employee_id)` : supprimer un salarié emporte ses capacités, et
--     une capacité ne peut pas viser le salarié d'une autre société (ISO-02) ;
--   * les bornes sont CONTRAINTES (`period_end >= period_start`, 0 ≤ heures
--     hebdomadaires ≤ 168 — une semaine n'a pas 200 heures) ;
--   * un DÉCLENCHEUR interdit le CHEVAUCHEMENT : deux capacités du même salarié
--     ne peuvent pas couvrir la même journée. C'est la règle que ni une clé ni un
--     CHECK ne peuvent tenir (`EXCLUDE USING gist` demanderait `btree_gist`, que
--     le socle n'a pas — le déclencheur fait le travail, et le dit).
--
-- RLS FORCÉE, index de société, QUATRE politiques par table (une par commande).
-- ============================================================

CREATE TABLE IF NOT EXISTS resource_capacities (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id  uuid NOT NULL,
  period_start date NOT NULL,
  period_end   date NOT NULL,
  weekly_hours numeric(5,2) NOT NULL
    CHECK (weekly_hours >= 0 AND weekly_hours <= 168),
  note         text,
  created_by   uuid,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end >= period_start),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, employee_id) REFERENCES employees (tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_resource_capacities_tenant   ON resource_capacities(tenant_id);
CREATE INDEX IF NOT EXISTS idx_resource_capacities_employee ON resource_capacities(employee_id);

-- ============================================================
-- Le déclencheur : deux capacités du même salarié ne se chevauchent pas
-- ============================================================
CREATE OR REPLACE FUNCTION check_resource_capacity_overlap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Une période à l'ENVERS n'est pas du ressort de ce contrôle : `daterange`
  -- lève « range lower bound must be less than or equal to range upper bound »
  -- avant tout chevauchement. C'est le CHECK `period_end >= period_start` de la
  -- table qui la refuse — on le laisse faire, plutôt que d'inventer un message.
  IF NEW.period_end < NEW.period_start THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM resource_capacities
     WHERE tenant_id = NEW.tenant_id
       AND employee_id = NEW.employee_id
       AND id <> NEW.id
       AND daterange(period_start, period_end, '[]')
        && daterange(NEW.period_start, NEW.period_end, '[]')
  ) THEN
    RAISE EXCEPTION 'CAPACITY_OVERLAP : une capacité couvre déjà cette période pour ce salarié';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_check_resource_capacity_overlap ON resource_capacities;
CREATE TRIGGER trg_check_resource_capacity_overlap
  BEFORE INSERT OR UPDATE OF employee_id, period_start, period_end ON resource_capacities
  FOR EACH ROW EXECUTE FUNCTION check_resource_capacity_overlap();

REVOKE ALL ON FUNCTION check_resource_capacity_overlap() FROM PUBLIC, anon;


-- ============================================================
-- RLS : forcée, quatre politiques (une par commande)
-- ============================================================
ALTER TABLE resource_capacities ENABLE ROW LEVEL SECURITY;
ALTER TABLE resource_capacities FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS resource_capacities_select ON resource_capacities;
CREATE POLICY resource_capacities_select ON resource_capacities
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS resource_capacities_insert ON resource_capacities;
CREATE POLICY resource_capacities_insert ON resource_capacities
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS resource_capacities_update ON resource_capacities;
CREATE POLICY resource_capacities_update ON resource_capacities
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS resource_capacities_delete ON resource_capacities;
CREATE POLICY resource_capacities_delete ON resource_capacities
  FOR DELETE USING (tenant_id = current_tenant_id());

-- Le visiteur n'écrit rien (défauts du schéma : `ALL` à `anon` sur toute table neuve).
REVOKE ALL ON resource_capacities FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON resource_capacities TO authenticated;
GRANT ALL ON resource_capacities TO service_role;

