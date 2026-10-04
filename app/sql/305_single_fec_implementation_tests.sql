-- ============================================================
-- 305_single_fec_implementation_tests.sql — W7 (M-11) : un seul FEC
--
--   FEC-01 🟡 Une **seconde** implémentation du FEC vivait en base :
--             `fec_export`, en deux surcharges, qui ne produit que **9 colonnes
--             sur les 18** de l'arrêté et écrit `je.number` (numéro provisoire)
--             au lieu de `posting_number`. Elle n'est appelée par personne —
--             l'écran bâtit son FEC avec `getFECData` + son validateur (18
--             colonnes, tri par `posting_seq`).
--
-- Ce fichier tient la fermeture : plus aucune fonction SQL ne produit de FEC, et
-- les colonnes que l'export de l'écran lit sont toujours là.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '305', false);
DELETE FROM _audit_results WHERE file = '305';

-- T01 — les deux surcharges de la seconde implémentation ont disparu
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_proc p
  JOIN pg_namespace ns ON ns.oid = p.pronamespace AND ns.nspname = 'public'
  WHERE p.proname = 'fec_export';
  PERFORM _rec('T01', 'plus aucune fonction publique ne produit un FEC à 9 colonnes',
    n = 0, format('%s fonction(s) fec_export restante(s) (0 attendue)', n));
END $$;

-- T02 — l'export de l'écran garde ce qu'il lit : le numéro définitif et l'ordre
-- de comptabilisation, sur l'écriture comme sur la ligne.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM information_schema.columns
  WHERE table_schema = 'public'
    AND ((table_name = 'journal_entries' AND column_name IN ('posting_seq', 'posting_number', 'piece_number'))
      OR (table_name = 'journal_lines' AND column_name IN ('account_general', 'account_tiers', 'echeance_date', 'reference')));
  PERFORM _rec('T02', 'les colonnes de l''arrêté que l''écran lit sont toujours présentes (7 attendues)',
    n = 7, format('%s colonne(s) présente(s) (7 attendues)', n));
END $$;

SELECT _audit_assert('305');
