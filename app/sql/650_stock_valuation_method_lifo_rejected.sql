-- ============================================================
-- 650_stock_valuation_method_lifo_rejected.sql — STK-03 (partie E)
--
-- DÉCISION, et pourquoi celle-là — c'est une question de NORMES, pas de goût.
--   · IAS 2 (IFRS) : le LIFO (DEPS, « dernier entré, premier sorti ») est INTERDIT.
--   · PCG français (règlement ANC 2014-03, art. 213-1) : le CUMP et le PEPS
--     (FIFO) sont admis ; le LIFO est interdit depuis le 1er janvier 2005
--     (règlement CRC 2004-06).
--   · SYSCOHADA révisé : CUMP et PEPS admis, LIFO interdit.
-- Les leaders du marché s'alignent :
--   · Odoo : FIFO, AVCO (coût moyen), prix standard — PAS de LIFO ;
--   · Sage Gestion Commerciale FR : CUMP par défaut, PEPS — pas de LIFO ;
--   · SAP : FIFO / coût moyen ; le LIFO n'est pas la voie IFRS.
--
-- Conséquence : `stock_valuation_method` ne doit PAS offrir 'lifo'. La 111
-- l'autorisait (`CHECK (… IN ('cump','fifo','lifo'))`). Ce fichier resserre le
-- réglage aux deux méthodes conformes :
--   · 'cump' — défaut, moteur de la 254 (les couches portent le CUMP) ;
--   · 'fifo' — PEPS, admis par les normes ; son moteur de couches reste aligné
--     sur le CUMP, limite DITE et MESURÉE par la suite 254 (T05).
--
-- Mesuré AVANT : `stock_valuation_method` acceptait 'lifo' — une méthode que la
-- comptabilité n'a jamais su produire et que les normes interdisent.
-- Après : 'lifo' est refusé par le CHECK.
-- ============================================================

-- 1. Normaliser les lignes existantes : aucune ne doit porter une valeur interdite.
UPDATE company_settings
SET stock_valuation_method = 'cump'
WHERE stock_valuation_method IS NULL
   OR stock_valuation_method NOT IN ('cump', 'fifo');

-- 2. Retirer l'ancienne contrainte (nommée dynamiquement — son nom dépend de la 111).
DO $$
DECLARE c text;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'company_settings'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%stock_valuation_method%'
  LOOP
    EXECUTE format('ALTER TABLE company_settings DROP CONSTRAINT %I', c);
  END LOOP;
END $$;

-- 3. Un seul jeu de valeurs admises : les méthodes conformes.
ALTER TABLE company_settings
  ADD CONSTRAINT company_settings_stock_valuation_method_check
  CHECK (stock_valuation_method IN ('cump', 'fifo'));

COMMENT ON COLUMN company_settings.stock_valuation_method IS
  'STK-03 (650) : méthode de valorisation. Valeurs admises : cump (défaut, moteur de la 254) et fifo (PEPS). LIFO (DEPS) interdit — IAS 2, PCG art. 213-1 (CRC 2004-06), SYSCOHADA ; non implémenté par Odoo.';
