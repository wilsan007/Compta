-- ============================================================
-- 161_employee_gender_bdes.sql
--
-- G16 (doc/audit/SUIVI-CAHIER-CORRECTIF.md, bloc G) — arbitrage du 18/09 :
-- ajouter la colonne.
--
-- `calculateBdesIndicators` (src/lib/queries/socialDeclarations.ts:498) demandait
-- `employees.gender`, qui n'existait dans aucune migration. PostgREST refusait la
-- requête entière (42703) : l'écran BDES était en erreur, pas seulement amputé de
-- ses deux indicateurs d'égalité.
--
-- RGPD : la donnée n'est collectée que parce qu'une obligation légale l'impose —
-- index d'égalité professionnelle et BDES (art. L.2312-18 du code du travail),
-- et rubrique S21.G00.30.005 de la DSN. Colonne facultative (NULL = non
-- renseigné, valeur par défaut), limitée aux deux modalités que ces déclarations
-- admettent, et exclue de tout autre usage. Aucune valeur n'est déduite.
-- ============================================================

ALTER TABLE employees ADD COLUMN IF NOT EXISTS gender text;

DO $$ BEGIN
  ALTER TABLE employees ADD CONSTRAINT employees_gender_check
    CHECK (gender IS NULL OR gender IN ('F', 'M'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN employees.gender IS
  'Sexe déclaré, au sens des déclarations sociales uniquement (DSN S21.G00.30.005, '
  'index égalité professionnelle, BDES). ''F'' ou ''M'', NULL si non renseigné. '
  'Donnée collectée au titre d''une obligation légale — ne pas employer ailleurs.';
