-- 759 — chain_l16_bulletin_ecriture
-- Numéro pris le 2026-10-11T07:03:42.947Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 759 — L16 · le chaînage interne de la RH/PAIE (le « maillon faible » du
--       référentiel) : le BULLETIN et son ÉCRITURE COMPTABLE
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3) le dit au module RH/Paie — « contrat ↔ salarié ↔ absence ↔
-- temps ↔ variable ↔ **bulletin** ↔ cumuls ↔ **écriture** ↔ virement ↔ DSN ».
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `pay_slips.journal_entry_id` et `pay_slips.journal_posted` EXISTENT et sont
--     ÉCRITS par la comptabilisation de la paie (`191_payroll_to_ledger`, ligne 207)
--     — mais **AUCUN lien de chaîne** (`document_links`) n'est posé : l'écriture
--     d'un bulletin est **invisible pour la frise** ;
--   * `pay_slips` n'est PAS au registre `chain_document_types` : un lien vers un
--     bulletin aurait été REFUSÉ (451). C'est le premier objet ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le type `pay_slips` au registre, le contrat d'effet
-- `payroll.slip.posted`, et le maillon `chain_l16_payslip_entry` — idempotent
-- (rejeu REFUSÉ), réversible, tracé (`link_documents`, type `generated_entry`,
-- lisible par la Vue Chaîne).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : un bulletin non **comptabilisé**
-- (`journal_entry_id IS NULL`) est refusé — on ne trace pas une écriture qui
-- n'existe pas ; un bulletin annulé aussi. Chaque refus dit sa raison.
--
-- ⚠️ PLAGE A3 SATURÉE : `759` est le **dernier** numéro de la plage
-- `750 → 759`. A3 doit **demander une extension** à l'intégration avant le prochain
-- maillon — le registre fait foi (R2).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre accueille le BULLETIN DE PAIE ───────────────────────────
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('pay_slips', 'pay_slips', NULL, 'Bulletin de paie')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'pay_slips', 'posted', 'payroll.slip.posted', true, NULL,
       false, true, true, false, true,
       'L16/759 : le bulletin de paie est rattaché à son écriture comptable, et le lien amont→aval est posé. Écrit par la comptabilisation de la paie (191). Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'pay_slips' AND evenement = 'posted' AND effet = 'payroll.slip.posted'
);

-- ── 3. Le MAILLON : `chain_l16_payslip_entry` ──────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_payslip_entry(p_slip_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_s     pay_slips%ROWTYPE;
  v_e     journal_entries%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. Le bulletin, borné à la société.
  SELECT * INTO v_s FROM pay_slips
   WHERE id = p_slip_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulletin de paie introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_s.status = 'cancelled' THEN
    RAISE EXCEPTION 'Bulletin % annulé : aucune écriture ne s''y rattache', v_s.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_s.journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Bulletin % non comptabilisé : il n''a pas encore d''écriture', v_s.number
      USING ERRCODE = 'check_violation';
  END IF;

  -- 3. L'écriture, bornée à la société (celle que la comptabilisation de la paie a posée).
  SELECT * INTO v_e FROM journal_entries
   WHERE id = v_s.journal_entry_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Écriture du bulletin % introuvable (ou hors de votre société)', v_s.number
      USING ERRCODE = 'no_data_found';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_s.tenant_id
     AND l.amont_type = 'pay_slips'       AND l.amont_id = p_slip_id
     AND l.aval_type  = 'journal_entries' AND l.aval_id  = v_s.journal_entry_id
     AND l.effet = 'payroll.slip.posted' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'Le bulletin % est déjà rattaché à son écriture', v_s.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01). Aucune colonne n'est
  --    réécrite : `journal_entry_id` est déjà posée par la comptabilisation (191).
  PERFORM link_documents(
    v_s.tenant_id, 'pay_slips', p_slip_id, 'journal_entries', v_s.journal_entry_id,
    'payroll.slip.posted', 'generated_entry');

  RETURN jsonb_build_object(
    'success', true, 'slip_id', p_slip_id, 'entry_id', v_s.journal_entry_id,
    'slip_number', v_s.number, 'entry_number', v_e.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_payslip_entry(uuid) IS
  'L16/759 : chaîne paie bulletin → son écriture comptable. Idempotent (rejeu refusé), refuse un bulletin annulé ou non comptabilisé, tracé (link_documents, effet payroll.slip.posted). Ne réécrit pas journal_entry_id (posée par la comptabilisation 191). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_payslip_entry(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_payslip_entry(uuid) TO authenticated;
