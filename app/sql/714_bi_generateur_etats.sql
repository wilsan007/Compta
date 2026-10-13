-- ============================================================
-- 714 : BI-01 — Générateur d'états : contraintes et rôle
-- ============================================================
--
-- Le constat (mesuré sur base neuve) :
--   `custom_report_templates` n'a AUCUN CHECK sur `report_type`, `category`,
--   `page_orientation`, `page_size` — n'importe quoi passe. Les quatre
--   politiques RLS ne filtrent que la société (pas de `can_perform`), et la
--   `FOR INSERT` n'a même pas de `WITH CHECK` (PERM‑01).
--   `reporting_plans` a des CHECK (report_type, format, schedule) mais les
--   politiques d'écriture n'ont pas de `can_perform` non plus.
--
-- Ce lot :
--   1) CHECK sur `custom_report_templates` : report_type, category,
--      page_orientation, page_size, name (non vide ≤ 200).
--   2) `can_perform` sur les 3 commandes d'écriture des DEUX tables.
--   3) Reprise : valeurs existantes hors CHECK → valeur par défaut.
--
-- Limites : le VRAI moteur de rendu (Gotenberg ou autre) est F.3/D-4 —
-- ce lot rend la DONNÉE vraie, il ne rend pas les états. La suite mesure
-- les contraintes, pas le rendu.
-- ============================================================

BEGIN;

-- ============================================================
-- 1) Reprise des données sales AVANT les CHECK
-- ============================================================

-- custom_report_templates : report_type hors liste
UPDATE custom_report_templates
   SET report_type = 'trial_balance'
 WHERE report_type NOT IN (
   'trial_balance', 'general_ledger', 'balance_sheet',
   'profit_loss', 'aged_balance', 'journals'
 );

-- category hors liste
UPDATE custom_report_templates
   SET category = 'accounting'
 WHERE category NOT IN (
   'accounting', 'hr', 'stock', 'commercial', 'treasury', 'fiscal'
 );

-- page_orientation hors liste
UPDATE custom_report_templates
   SET page_orientation = 'portrait'
 WHERE page_orientation IS NOT NULL
   AND page_orientation NOT IN ('portrait', 'landscape');

-- page_size hors liste
UPDATE custom_report_templates
   SET page_size = 'A4'
 WHERE page_size IS NOT NULL
   AND page_size NOT IN ('A4', 'A3', 'Letter');

-- name vide ou trop long
UPDATE custom_report_templates
   SET name = 'Sans nom'
 WHERE name IS NULL OR length(trim(name)) = 0;

UPDATE custom_report_templates
   SET name = left(name, 200)
 WHERE length(name) > 200;

-- ============================================================
-- 2) CHECK sur custom_report_templates
-- ============================================================

ALTER TABLE custom_report_templates
  ADD CONSTRAINT crt_report_type_check
    CHECK (report_type IN (
      'trial_balance', 'general_ledger', 'balance_sheet',
      'profit_loss', 'aged_balance', 'journals'
    ));

ALTER TABLE custom_report_templates
  ADD CONSTRAINT crt_category_check
    CHECK (category IN (
      'accounting', 'hr', 'stock', 'commercial', 'treasury', 'fiscal'
    ));

ALTER TABLE custom_report_templates
  ADD CONSTRAINT crt_page_orientation_check
    CHECK (page_orientation IS NULL
           OR page_orientation IN ('portrait', 'landscape'));

ALTER TABLE custom_report_templates
  ADD CONSTRAINT crt_page_size_check
    CHECK (page_size IS NULL
           OR page_size IN ('A4', 'A3', 'Letter'));

ALTER TABLE custom_report_templates
  ADD CONSTRAINT crt_name_check
    CHECK (length(btrim(name)) > 0 AND length(name) <= 200);

-- ============================================================
-- 3) Politiques RLS avec can_perform (PERM-01)
--    custom_report_templates : réglage de société (D-6)
-- ============================================================

DROP POLICY IF EXISTS tenant_insert_custom_reports ON custom_report_templates;
CREATE POLICY tenant_insert_custom_reports ON custom_report_templates FOR INSERT
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('custom_report_templates', 'insert'));

DROP POLICY IF EXISTS tenant_update_custom_reports ON custom_report_templates;
CREATE POLICY tenant_update_custom_reports ON custom_report_templates FOR UPDATE
  USING (tenant_id = current_tenant_id()
         AND can_perform('custom_report_templates', 'update'))
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('custom_report_templates', 'update'));

DROP POLICY IF EXISTS tenant_delete_custom_reports ON custom_report_templates;
CREATE POLICY tenant_delete_custom_reports ON custom_report_templates FOR DELETE
  USING (tenant_id = current_tenant_id()
         AND can_perform('custom_report_templates', 'delete'));

-- ============================================================
-- 4) Politiques RLS avec can_perform — reporting_plans
-- ============================================================

DROP POLICY IF EXISTS tenant_insert_reporting_plans ON reporting_plans;
CREATE POLICY tenant_insert_reporting_plans ON reporting_plans FOR INSERT
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('reporting_plans', 'insert'));

DROP POLICY IF EXISTS tenant_update_reporting_plans ON reporting_plans;
CREATE POLICY tenant_update_reporting_plans ON reporting_plans FOR UPDATE
  USING (tenant_id = current_tenant_id()
         AND can_perform('reporting_plans', 'update'))
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('reporting_plans', 'update'));

DROP POLICY IF EXISTS tenant_delete_reporting_plans ON reporting_plans;
CREATE POLICY tenant_delete_reporting_plans ON reporting_plans FOR DELETE
  USING (tenant_id = current_tenant_id()
         AND can_perform('reporting_plans', 'delete'));

COMMIT;