-- ============================================================
-- 305_drop_legacy_fec.sql — W7 (M-11) : une seule implémentation du FEC
--
-- FEC-01 🟡 : `fec_export` existait en base en **deux** surcharges, toutes deux
-- héritées :
--   • `fec_export(date, date, integer, integer)` — 9 colonnes sur les 18 de
--     l'arrêté, `je.number` (numéro provisoire) au lieu de `posting_number`,
--     aucune colonne de devise ;
--   • `fec_export(uuid, date, date, integer, integer)` — la même, avec un
--     `p_tenant_id` fourni par l'appelant (sa révocation datait de la 227).
--
-- Aucune n'est appelée : ni par le front (qui bâtit son FEC avec `getFECData` et
-- `fecValidator`, 18 colonnes, trié par `posting_seq`), ni par une autre fonction
-- SQL. Deux implémentations d'un même état légal, dont une fausse, c'est une de
-- trop : elles partent.
--
-- La suite `305_single_fec_implementation_tests.sql` tient la fermeture (T01
-- rouge avant, vert après) et vérifie que les colonnes lues par l'export de
-- l'écran sont toujours là (T02).
-- ============================================================

DROP FUNCTION IF EXISTS public.fec_export(date, date, integer, integer);
DROP FUNCTION IF EXISTS public.fec_export(uuid, date, date, integer, integer);
