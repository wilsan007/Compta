-- ═══════════════════════════════════════════════════════════════════════════
-- 389 — roles_closing : CLÔTURE et AFFECTATION sur les rôles (LOC1-08)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. LOC1-08, première tranche : l'**affectation du résultat** et les
-- **écarts de lettrage**. Ces fonctions ne portent plus `'120000'`, `'129000'`,
-- `'665000'`… ni les journaux `'OD'`/`'CL'` : elles demandent leurs **rôles**.
-- Cahier §5, tâche LOC1-08.
--
-- ÉCRITURES IDENTIQUES. Le pack PCG rend EXACTEMENT les comptes d'aujourd'hui
-- (`RESULTAT_BENEFICE→120000`, `RESULTAT_PERTE→129000`, `ESCOMPTES_ACCORDES→665000`,
-- `PERTES_CHANGE→666000`, `GAINS_CHANGE→766000`,
-- `PERTES_CREANCES_IRRECOUVRABLES→654000`, `JOURNAL_OD→OD`, `JOURNAL_CLOTURE→CL`).
-- La recette du cahier — « balance d'ouverture N+1 identique au centime » — est
-- donc tenue par construction.
--
-- UN RÔLE DE JOURNAL AJOUTÉ. Le journal de clôture `'CL'` n'avait pas de rôle
-- (comme `POS`/`OF` en `387`) : on le nomme `JOURNAL_CLOTURE`, conformément à la
-- règle de LOC1-04. Il sert à `close_fiscal_year` (`390`).
--
-- ⚠ CE QUI N'EST PAS DANS CETTE TRANCHE.
-- - `close_fiscal_year` → migration `390` (même lot, fichier séparé).
-- - `generate_depreciation_entry` : ses littéraux `280000`/`681000` ne
--   correspondent PAS aux rôles (`AMORTISSEMENTS` est par CATÉGORIE ; le pack
--   porte `681100`). Le remplacer **changerait les écritures** : à trancher.
--
-- Numéro pris le 2026-10-06T09:43:46.059Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Le rôle de journal de la clôture (catalogue + pack PCG)
-- ─────────────────────────────────────────────────────────────
INSERT INTO journal_role_catalog (role, journal_type, required_for) VALUES
  ('JOURNAL_CLOTURE', 'general', ARRAY['closing'])
ON CONFLICT (role) DO NOTHING;

INSERT INTO pack_journal_roles (pack_code, role, journal_code, journal_type) VALUES
  ('PCG', 'JOURNAL_CLOTURE', 'CL', 'general')
ON CONFLICT (pack_code, role) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 2. Affectation du résultat → journal OD, sur les rôles
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.allocate_result(p_fiscal_year_id uuid, p_allocation jsonb, p_date date DEFAULT NULL::date, p_description text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy fiscal_years%ROWTYPE;
  v_next fiscal_years%ROWTYPE;
  v_date date;
  v_profit boolean;
  v_total numeric(18,2);
  v_sum numeric(18,2);
  v_bad text;
  v_result_account text;
  v_entry_id uuid;
  v_journal text;
BEGIN
  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable ou accès interdit';
  END IF;
  IF v_fy.status NOT IN ('closed', 'locked') OR v_fy.closing_result IS NULL THEN
    RAISE EXCEPTION 'L''exercice % n''est pas clôturé : son résultat n''est pas encore déterminé', v_fy.code;
  END IF;
  IF v_fy.result_allocated_at IS NOT NULL THEN
    RAISE EXCEPTION 'Le résultat de l''exercice % est déjà affecté', v_fy.code;
  END IF;
  IF v_fy.closing_result = 0 THEN
    RAISE EXCEPTION 'Résultat nul : rien à affecter pour l''exercice %', v_fy.code;
  END IF;

  SELECT * INTO v_next FROM fiscal_years
  WHERE tenant_id = v_tid AND start_date = v_fy.end_date + 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L''exercice qui suit % est introuvable : l''affectation y est passée', v_fy.code;
  END IF;
  v_date := COALESCE(p_date, v_next.start_date);
  IF v_date NOT BETWEEN v_next.start_date AND v_next.end_date THEN
    RAISE EXCEPTION 'La date d''affectation doit appartenir à l''exercice % (du % au %)',
      v_next.code, v_next.start_date, v_next.end_date;
  END IF;

  v_profit := v_fy.closing_result > 0;
  v_total := abs(v_fy.closing_result);
  -- LOC1-08 : le compte de résultat vient du RÔLE
  v_result_account := CASE WHEN v_profit THEN resolve_account(v_tid, 'RESULTAT_BENEFICE')
                           ELSE resolve_account(v_tid, 'RESULTAT_PERTE') END;
  v_journal := resolve_journal(v_tid, 'JOURNAL_OD');

  IF jsonb_typeof(p_allocation) IS DISTINCT FROM 'array' OR jsonb_array_length(p_allocation) = 0 THEN
    RAISE EXCEPTION 'Répartition vide : indiquez au moins un compte et un montant';
  END IF;

  SELECT string_agg(COALESCE(x->>'account', '(vide)'), ', ') INTO v_bad
  FROM jsonb_array_elements(p_allocation) x
  WHERE COALESCE(x->>'account', '') !~ CASE WHEN v_profit THEN '^(106|108|110|457)' ELSE '^(106|108|110|119)' END
     OR COALESCE((x->>'amount')::numeric, 0) <= 0
     OR (x->>'amount')::numeric <> round((x->>'amount')::numeric, 2);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Ligne(s) d''affectation invalide(s) : % — %', v_bad,
      CASE WHEN v_profit
        THEN 'un bénéfice s''affecte en réserves (106), report à nouveau (110), dividendes (457) ou compte de l''exploitant (108), montant positif au centime'
        ELSE 'une perte s''affecte en report à nouveau débiteur (119), sur les réserves (106), le report créditeur (110) ou le compte de l''exploitant (108), montant positif au centime' END;
  END IF;

  SELECT sum((x->>'amount')::numeric) INTO v_sum FROM jsonb_array_elements(p_allocation) x;
  IF v_sum <> v_total THEN
    RAISE EXCEPTION 'La répartition (%) doit être égale au résultat de l''exercice % (%)', v_sum, v_fy.code, v_total;
  END IF;

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference)
  VALUES (v_tid, 'AFF-' || v_fy.code, v_date, v_journal, 'draft',
          COALESCE(NULLIF(p_description, ''), 'Affectation du résultat de l''exercice ' || v_fy.code),
          'AFFECTATION-' || v_fy.code)
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
  VALUES (v_tid, v_entry_id, v_result_account, v_result_account,
          CASE WHEN v_profit THEN v_total ELSE 0 END, CASE WHEN v_profit THEN 0 ELSE v_total END,
          'Résultat ' || v_fy.code, 0);

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
  SELECT v_tid, v_entry_id, x->>'account', x->>'account',
         CASE WHEN v_profit THEN 0 ELSE (x->>'amount')::numeric END,
         CASE WHEN v_profit THEN (x->>'amount')::numeric ELSE 0 END,
         'Affectation du résultat ' || v_fy.code, ord::int
  FROM jsonb_array_elements(p_allocation) WITH ORDINALITY AS a(x, ord);

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;

  UPDATE fiscal_years SET result_allocated_at = now(), result_allocation_entry_id = v_entry_id
  WHERE id = v_fy.id;

  RETURN jsonb_build_object('success', true, 'entry_id', v_entry_id, 'fiscal_year_id', v_fy.id,
                            'result', v_fy.closing_result, 'date', v_date);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 3. Écarts de lettrage → journal OD, sur les rôles
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_residual_entry(p_group_id uuid, p_residual_type text, p_amount numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_group lettrage_groups%ROWTYPE;
  v_compte text;
  v_tiers text;
  v_ref text;
  v_number text;
  v_je uuid;
  v_existe uuid;
  v_perte boolean;
  v_journal text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_group FROM lettrage_groups WHERE id = p_group_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Groupe de lettrage introuvable : %', p_group_id; END IF;

  -- LOC1-08 : le compte d'écart vient du RÔLE
  v_compte := CASE p_residual_type
    WHEN 'escompte' THEN resolve_account(v_tid, 'ESCOMPTES_ACCORDES')
    WHEN 'perte_change' THEN resolve_account(v_tid, 'PERTES_CHANGE')
    WHEN 'gain_change' THEN resolve_account(v_tid, 'GAINS_CHANGE')
    WHEN 'creance_irrecouvrable' THEN resolve_account(v_tid, 'PERTES_CREANCES_IRRECOUVRABLES')
  END;
  IF v_compte IS NULL THEN
    RAISE EXCEPTION 'Type d''écart inconnu : %', p_residual_type USING ERRCODE = 'check_violation';
  END IF;

  IF COALESCE(p_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Montant d''écart invalide : %', p_amount USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotence : un écart déjà comptabilisé ne se double pas
  v_ref := 'ECART:' || v_group.id;
  SELECT id INTO v_existe FROM journal_entries WHERE tenant_id = v_tid AND reference = v_ref LIMIT 1;
  IF v_existe IS NOT NULL THEN
    RAISE EXCEPTION 'L''écart du lettrage % est déjà comptabilisé (écriture %)', v_group.lettrage_code,
      (SELECT COALESCE(posting_number, number) FROM journal_entries WHERE id = v_existe)
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Contrepartie : le compte de tiers des lignes lettrées du groupe
  SELECT COALESCE(jl.account_general, jl.account_code) INTO v_tiers
  FROM journal_lines jl
  WHERE jl.tenant_id = v_tid AND jl.lettrage_group_id = v_group.id
  GROUP BY 1
  ORDER BY count(*) DESC, 1
  LIMIT 1;
  IF v_tiers IS NULL THEN
    RAISE EXCEPTION 'Écart du lettrage % : aucune ligne rattachée, contrepartie inconnue', v_group.lettrage_code
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_compte) THEN
    RAISE EXCEPTION 'Compte d''écart % absent du plan comptable de la société', v_compte
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_tiers) THEN
    RAISE EXCEPTION 'Compte de tiers % absent du plan comptable de la société', v_tiers
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_perte := p_residual_type <> 'gain_change';
  v_number := 'ECART-' || v_group.lettrage_code;
  v_journal := resolve_journal(v_tid, 'JOURNAL_OD');

  -- 1. en-tête en brouillard
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_tid, v_number, CURRENT_DATE, v_journal, 'draft',
          'Écart de règlement ' || p_residual_type || ' - ' || v_group.lettrage_code, v_ref, v_number)
  RETURNING id INTO v_je;

  -- 2. lignes équilibrées
  IF v_perte THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_compte, 'Écart de règlement ' || p_residual_type, p_amount, 0, v_group.lettrage_code),
           (v_tid, v_je, v_tiers,  'Écart de règlement ' || v_group.lettrage_code, 0, p_amount, v_group.lettrage_code);
  ELSE
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_tiers,  'Écart de règlement ' || v_group.lettrage_code, p_amount, 0, v_group.lettrage_code),
           (v_tid, v_je, v_compte, 'Écart de règlement ' || p_residual_type, 0, p_amount, v_group.lettrage_code);
  END IF;

  -- 3. validation
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  UPDATE lettrage_groups
  SET residual_amount = p_amount, residual_type = p_residual_type, status = 'closed'
  WHERE id = v_group.id AND tenant_id = v_tid;

  -- Traces d'écart de lettrage, quand l'écran en a créé
  UPDATE lettrage_differences
  SET difference_account = v_compte, generated_entry_id = v_je, status = 'posted'
  WHERE tenant_id = v_tid AND lettrage_code = v_group.lettrage_code;

  RETURN v_je;
END $function$;
