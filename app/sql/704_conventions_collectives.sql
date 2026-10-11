-- 704 — conventions_collectives
-- Numéro pris le 2026-10-06T09:43:15.007Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.7 / PAY-08 (partie F du plan du 05/10) : LES CONVENTIONS COLLECTIVES
--
-- Le constat. `collective_agreements` et `collective_classifications` ont été
-- créées par la 123 (PAY-08) — avec leurs deux colonnes de rattachement sur
-- `employees` (`collective_agreement_id`, `classification_id`), rendues
-- COMPOSITES par la 237 — puis n'ont JAMAIS été lues par un écran ni une
-- fonction : ce sont deux « coquilles » (ORPH-02). Deux défauts mesurés le
-- 05/10 :
--   * leur RLS est ACTIVÉE mais NON FORCÉE (`relforcerowsecurity = false`) —
--     le défaut ISO-04 que `ci/check_bt_grid.sql` compte ;
--   * rien ne VALIDE le rattachement : `employees.collective_agreement_id`
--     s'écrit par un simple UPDATE, sans vérifier que la convention appartient
--     à la société ni que la classification appartient bien à cette convention
--     (les clés composites garantissent la SOCIÉTÉ, pas la COHÉRENCE interne).
--
-- Ce que cette migration pose :
--   1. RLS FORCÉE sur les deux tables (elles portent `tenant_id` : la règle
--      `sans_rls`/`rls_sans_force` de la grille BT s'applique) ;
--   2. `set_employee_collective_agreement(...)` : le seul chemin d'affectation,
--      qui vérifie — avant d'écrire — que l'appelant est administrateur de la
--      société, que le salarié et la convention en relèvent, et que la
--      classification appartient À CETTE convention.
--
-- La lecture, elle, reste directe (PostgREST + RLS) : c'est ce que consomme
-- l'écran Paramètres → Conventions collectives, livré avec cette migration.
--
-- Pas de changement de schéma hors RLS : les colonnes existent depuis la 123.
-- ============================================================

ALTER TABLE collective_agreements     FORCE ROW LEVEL SECURITY;
ALTER TABLE collective_classifications FORCE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION set_employee_collective_agreement(
  p_employee_id       uuid,
  p_agreement_id      uuid,
  p_classification_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Aucune société active';
  END IF;
  IF NOT _is_admin_of_current_tenant() THEN
    RAISE EXCEPTION 'PAY_FORBIDDEN : seul un administrateur affecte une convention';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id AND tenant_id = v_tenant) THEN
    RAISE EXCEPTION 'EMPLOYEE_NOT_FOUND : salarié inconnu dans votre société';
  END IF;
  IF p_agreement_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM collective_agreements WHERE id = p_agreement_id AND tenant_id = v_tenant) THEN
    RAISE EXCEPTION 'AGREEMENT_NOT_FOUND : convention inconnue dans votre société';
  END IF;
  IF p_classification_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM collective_classifications
        WHERE id = p_classification_id AND tenant_id = v_tenant AND agreement_id = p_agreement_id) THEN
    RAISE EXCEPTION 'CLASSIFICATION_MISMATCH : cette classification n''appartient pas à la convention';
  END IF;

  UPDATE employees
     SET collective_agreement_id = p_agreement_id,
         classification_id       = p_classification_id
   WHERE id = p_employee_id AND tenant_id = v_tenant;

  RETURN jsonb_build_object('success', true);
END $$;

REVOKE ALL ON FUNCTION set_employee_collective_agreement(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_employee_collective_agreement(uuid, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION set_employee_collective_agreement(uuid, uuid, uuid) IS
  'F.7/PAY-08 (704) : affecte (ou retire, p_agreement_id NULL) la convention '
  'collective et la classification d''un salarié. Vérifie que l''appelant est '
  'administrateur de la société, que le salarié et la convention en relèvent, et '
  'que la classification appartient à CETTE convention.';

