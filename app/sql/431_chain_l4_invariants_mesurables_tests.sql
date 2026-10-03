-- ============================================================
-- 431_chain_l4_invariants_mesurables_tests.sql — les six raisons
--   de non-mesure sont des PREUVES datées
--
-- HARMONISATION DU 03/10/2026. Cette suite portait sept scénarios ; six
-- éprouvaient le registre `chain_document_types` propre à la 431 et son
-- enveloppe de mesure, retirés au profit du registre de la 450 (voir
-- l'en-tête de la migration). INV-19 — orphelin compté, société saine
-- tenue, branche présente — est éprouvé par la suite 450 (T12 à T14) et
-- par la 413 (14 mesurés, 6 nommés). Il reste ici le scénario que rien
-- d'autre ne couvre : T05.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '431', false);
DELETE FROM _audit_results WHERE file = '431';

-- ═══════════════════════════════════════════════════════════════
-- T05 — Les six raisons sont des PREUVES, pas des affirmations
--   Le plan autorise le repli (« la raison de chaque exclusion »).
--   La 431 rend cette raison opposable : chacune commence par
--   « Mesuré le » — elle cite la mesure qui la fonde. Une raison
--   qui commence autrement est une affirmation, et une affirmation
--   se recopie sans se vérifier.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE v_sans_preuve text; v_nb int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT string_agg(code, ', ' ORDER BY code) INTO v_sans_preuve
    FROM chain_invariants
   WHERE tenant_id IS NULL AND NOT mesurable
     AND raison_non_mesurable NOT LIKE 'Mesuré le %';
  SELECT count(*) INTO v_nb FROM chain_invariants
   WHERE tenant_id IS NULL AND NOT mesurable;

  PERFORM _rec('T05', 'les six invariants non mesurables portent chacun une raison qui COMMENCE par « Mesuré le » : la raison est datée, fondée sur une mesure réelle, opposable — c''est le repli que le plan autorise, tenu au standard de preuve du dépôt',
    v_sans_preuve IS NULL AND v_nb = 6,
    format('non mesurables=%s (6 attendus) | sans preuve datée : %s',
           v_nb, COALESCE(v_sans_preuve, '(aucun — les six portent leur mesure)')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'les six invariants non mesurables portent chacun une raison qui COMMENCE par « Mesuré le » : la raison est datée, fondée sur une mesure réelle, opposable — c''est le repli que le plan autorise, tenu au standard de preuve du dépôt', false, SQLERRM);
END $$;

SELECT _audit_assert('431');
