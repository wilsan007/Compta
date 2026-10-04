-- ============================================================
-- 97_pay01_withholding_tax_rate.sql
-- PAY-01 : Ajouter les colonnes pour le taux de prélèvement à la source
--
-- Le taux PAS (prélèvement à la source) était codé en dur à 10%.
-- Il doit venir de la DGFiP (taux personnalisé) ou du barème neutre.
-- ============================================================

-- Ajouter les colonnes sur employees si elles n'existent pas
ALTER TABLE employees ADD COLUMN IF NOT EXISTS withholding_tax_rate numeric;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS withholding_rate_source text
  CHECK (withholding_rate_source IN ('dgfip', 'neutral', 'manual'));

-- Commentaire pour documenter
COMMENT ON COLUMN employees.withholding_tax_rate IS
  'Taux de prélèvement à la source transmis par la DGFiP (en pourcentage, ex: 3.5 pour 3,5%)';
COMMENT ON COLUMN employees.withholding_rate_source IS
  'Source du taux PAS : dgfip (taux personnalisé), neutral (barème neutre), manual (saisie manuelle)';
