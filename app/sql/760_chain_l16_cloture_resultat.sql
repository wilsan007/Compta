-- 760 — chain_l16_cloture_resultat
-- Numéro pris le 2026-10-11T08:34:15.517Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 760 — L16 · le chaînage interne de la COMPTABILITÉ : l'EXERCICE CLOS et son
--       ÉCRITURE D'AFFECTATION DU RÉSULTAT
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3) : « lettrage ↔ âge de la dette ↔ relance ↔ provision pour
-- dépréciation ↔ **écriture de clôture** ». Le lot `758` a fermé le lettrage ;
-- voici la clôture.
--
-- PREMIÈRE MIGRATION DE LA PLAGE `760 → 769` (nouvelle plage d'A3, inscrite au
-- registre le 06/10 après saturation de `750 → 759` — le registre fait foi, R2).
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `fiscal_years.result_allocation_entry_id` EXISTE (posée par `189`) et est
--     ÉCRIT par la clôture (`189`, ligne 672 : « le résultat est affecté ») — mais
--     **AUCUN lien de chaîne** (`document_links`) n'est posé : l'écriture
--     d'affectation d'un exercice est **invisible pour la frise** ;
--   * `fiscal_years` n'est PAS au registre `chain_document_types` : un lien vers un
--     exercice aurait été REFUSÉ (451). C'est le premier objet ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le type `fiscal_years` au registre, le contrat d'effet
-- `rev.fiscal_year.result_allocated`, et le maillon
-- `chain_l16_fiscal_year_result` — idempotent (rejeu REFUSÉ), réversible, tracé
-- (`link_documents`, type `generated_entry`).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : un exercice **ouvert** est refusé
-- (« non clos » — rien n'est encore affecté) ; un exercice dont le résultat n'est
-- **pas affecté** (`result_allocation_entry_id IS NULL`) aussi. Chaque refus dit sa
-- raison.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre accueille l'EXERCICE COMPTABLE ──────────────────────────
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('fiscal_years', 'fiscal_years', NULL, 'Exercice comptable')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'fiscal_years', 'result_allocated', 'rev.fiscal_year.result_allocated', true, NULL,
       false, false, true, false, true,
       'L16/760 : le résultat d''un exercice clos est affecté par une écriture, et le lien amont→aval est posé. Écrit par la clôture (189). Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'fiscal_years' AND evenement = 'result_allocated' AND effet = 'rev.fiscal_year.result_allocated'
);

-- ── 3. Le MAILLON : `chain_l16_fiscal_year_result` ─────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_fiscal_year_result(p_fy_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_y     fiscal_years%ROWTYPE;
  v_e     journal_entries%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. L'exercice, borné à la société.
  SELECT * INTO v_y FROM fiscal_years
   WHERE id = p_fy_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_y.status = 'open' THEN
    RAISE EXCEPTION 'Exercice % non clos : aucun résultat n''est encore affecté', v_y.code
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_y.result_allocation_entry_id IS NULL THEN
    RAISE EXCEPTION 'Exercice % : le résultat n''est pas affecté (aucune écriture)', v_y.code
      USING ERRCODE = 'check_violation';
  END IF;

  -- 3. L'écriture d'affectation, bornée à la société (celle que la clôture a posée).
  SELECT * INTO v_e FROM journal_entries
   WHERE id = v_y.result_allocation_entry_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Écriture d''affectation de l''exercice % introuvable (ou hors de votre société)', v_y.code
      USING ERRCODE = 'no_data_found';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_y.tenant_id
     AND l.amont_type = 'fiscal_years'    AND l.amont_id = p_fy_id
     AND l.aval_type  = 'journal_entries' AND l.aval_id  = v_y.result_allocation_entry_id
     AND l.effet = 'rev.fiscal_year.result_allocated' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'L''exercice % est déjà rattaché à son écriture d''affectation', v_y.code
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01). Aucune colonne n'est
  --    réécrite : `result_allocation_entry_id` est déjà posée par la clôture (189).
  PERFORM link_documents(
    v_y.tenant_id, 'fiscal_years', p_fy_id, 'journal_entries', v_y.result_allocation_entry_id,
    'rev.fiscal_year.result_allocated', 'generated_entry');

  RETURN jsonb_build_object(
    'success', true, 'fiscal_year_id', p_fy_id, 'entry_id', v_y.result_allocation_entry_id,
    'code', v_y.code, 'entry_number', v_e.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_fiscal_year_result(uuid) IS
  'L16/760 : chaîne comptable exercice clos → son écriture d''affectation du résultat. Idempotent (rejeu refusé), refuse un exercice ouvert ou au résultat non affecté, tracé (link_documents, effet rev.fiscal_year.result_allocated). Ne réécrit pas result_allocation_entry_id (posée par la clôture 189). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_fiscal_year_result(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_fiscal_year_result(uuid) TO authenticated;
