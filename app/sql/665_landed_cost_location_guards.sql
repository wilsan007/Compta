-- ============================================================
-- 665_landed_cost_location_guards.sql — E.3 / E.5 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Ce que la CI a trouvé quand elle a enfin pu aller PLUS LOIN que la garde de
-- société (664). Le job DB s'arrêtait à `check_tenant_guard` : les contrôles
-- ISO-02, ISO-04 et BUD-04 qui le suivent n'avaient JAMAIS tourné sur cette
-- branche — ni sur aucune branche `plan6/*`, la liste blanche du déclencheur
-- les ayant tenues dehors (R3). Ils ont trouvé trois défauts dans les deux
-- tables que cette partie a créées : `landed_cost_receipts` (658) et
-- `stock_location_assignments` (659).
--
--   1. ISO-02 — `landed_cost_receipts.landed_cost_id` portait une clé étrangère
--      MONO-COLONNE vers `landed_costs(id)`, entre deux tables cloisonnées : une
--      ligne d'affectation pouvait désigner la dépense d'une AUTRE société. La
--      658 avait pourtant pris soin de composer la clé de la réception
--      (`receipt_id, tenant_id`) : c'est celle de la dépense qui a été oubliée.
--
--   2. ISO-04 — les deux tables avaient la RLS ACTIVÉE mais NON FORCÉE. Le
--      propriétaire d'une table échappe à ses propres politiques : une fonction
--      ou un script écrit sous ce rôle lirait les deux tables sans filtre.
--      `check_bt_grid` a compté +2 sur `rls_sans_force`, et son verdict est
--      explicite : « Corrigez la table fautive, ne relevez pas le plafond ».
--
--   3. BUD-04 — aucune des deux n'avait d'index de société : chaque lecture
--      filtrée par société balayait la table. Les deux tables sont neuves, donc
--      l'index se pose sans dette à reprendre.
--
-- Aucun des trois n'est visible par une suite de tests : ils ne s'attrapent pas
-- en exécutant un scénario, mais en confrontant la FORME du schéma à des règles.
-- C'est précisément ce que la R3 a rendu possible.
-- ============================================================

-- ── 1. ISO-02 — la clé étrangère de la dépense devient composite ────────────
-- Le nom vient de la 658 (FK écrite en ligne) ; la boucle retire en plus toute
-- clé mono-colonne qui viserait `landed_costs`, quel que soit son nom — le
-- correctif ne doit pas dépendre d'une nomenclature.
DO $$
DECLARE v_name text;
BEGIN
  FOR v_name IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relname = 'landed_cost_receipts'
      AND con.contype = 'f'
      AND con.confrelid = 'public.landed_costs'::regclass
      AND array_length(con.conkey, 1) = 1
  LOOP
    EXECUTE format('ALTER TABLE public.landed_cost_receipts DROP CONSTRAINT %I', v_name);
  END LOOP;
END $$;

ALTER TABLE public.landed_cost_receipts
  ADD CONSTRAINT landed_cost_receipts_landed_cost_fk
  FOREIGN KEY (tenant_id, landed_cost_id)
  REFERENCES public.landed_costs (tenant_id, id) ON DELETE CASCADE;

COMMENT ON CONSTRAINT landed_cost_receipts_landed_cost_fk ON public.landed_cost_receipts IS
  '665 (ISO-02) : la cible de la dépense est liée AVEC sa société — une affectation ne peut plus pointer la dépense d''une autre société.';

-- ── 2. ISO-04 — la RLS est forcée sur les deux tables neuves ────────────────
ALTER TABLE public.landed_cost_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.stock_location_assignments FORCE ROW LEVEL SECURITY;

-- ── 3. BUD-04 — l'index de société ─────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_landed_cost_receipts_tenant
  ON public.landed_cost_receipts USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_location_assignments_tenant
  ON public.stock_location_assignments USING btree (tenant_id);

