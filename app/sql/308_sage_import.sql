-- ============================================================
-- 308_sage_import.sql — W7 (M-19) : l'import d'écritures devient un acte unique
--
-- Trois défauts du plan correctif, tels que mesurés sur l'écran d'import
-- (`SageImportPage`) :
--
--   SAGE-01 🔴 Les écritures importées restent en **brouillon** et **rien ne les
--             valide** : la reprise d'une balance produit un brouillard, jamais
--             une comptabilité. Aucun contrôle `totalDebit = totalCredit` n'est
--             fait avant l'appel.
--   SAGE-02 🟠 `updateChartAccount(acc.id, { balance })` **remplace** le solde du
--             compte par le seul cumul importé : importer dans une société qui a
--             déjà des écritures **écrase** les soldes du plan comptable.
--   SAGE-03 🟠 Chaque écriture est tentée dans son propre `try/catch` : un import
--             partiel laisse une comptabilité déséquilibrée, sans transaction
--             englobante ni possibilité de reprise.
--
-- LE CORRECTIF : **une** fonction, donc **une** transaction.
--   `import_fec_entries(p_entries jsonb)` :
--     1. refuse un import vide et un import **déséquilibré** ;
--     2. refuse un import dont une **pièce existe déjà** (journal + numéro) ;
--     3. **crée les comptes manquants** du plan (type déduit de la classe) ;
--     4. insère les écritures et leurs lignes, puis les **valide** par le chemin
--        unique de la validation (`validate_journal_entries`, migration 273) ;
--     5. **cumule** les soldes des comptes, au lieu de les écraser ;
--     6. rend un verdict chiffré (`entries`, `lines`, `accounts_created`).
--   Une seule erreur, où qu'elle survienne, annule **tout** : la comptabilité ne
--   peut plus rester à moitié importée.
--
-- LIMITES, DITES. L'import ne défait pas une validation partielle : si le noyau
-- refuse une écriture (compte fermé, période close, séparation des tâches),
-- **rien** n'est écrit — l'écran doit corriger la source et relancer. Le
-- rattachement des tiers (`account_tiers`) et le lettrage sont repris tels quels
-- du fichier.
-- ============================================================

CREATE OR REPLACE FUNCTION public.import_fec_entries(p_entries jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_nb int;
  v_debit numeric;
  v_credit numeric;
  v_doublon text;
  v_e jsonb;
  v_l jsonb;
  v_eid uuid;
  v_ids uuid[] := '{}';
  v_comptes text[];
  v_crees int := 0;
  v_code text;
  v_libelle text;
  v_verdicts jsonb;
  v_ko text;
  v_lignes int := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;
  IF p_entries IS NULL OR jsonb_typeof(p_entries) <> 'array' THEN
    RAISE EXCEPTION 'Import vide ou mal formé : un tableau d''écritures est attendu' USING ERRCODE = '22023';
  END IF;

  v_nb := jsonb_array_length(p_entries);
  IF v_nb = 0 THEN
    RAISE EXCEPTION 'Import vide : aucune écriture à reprendre' USING ERRCODE = '22023';
  END IF;

  -- 1. Le contrôle d'équilibre, sur la totalité des lignes (SAGE-01)
  SELECT COALESCE(sum(COALESCE((l->>'debit')::numeric, 0)), 0),
         COALESCE(sum(COALESCE((l->>'credit')::numeric, 0)), 0)
  INTO v_debit, v_credit
  FROM jsonb_array_elements(p_entries) e,
       jsonb_array_elements(COALESCE(e->'lines', '[]'::jsonb)) l;

  IF round(v_debit, 2) <> round(v_credit, 2) THEN
    RAISE EXCEPTION 'Import déséquilibré : débit % ≠ crédit % — rien n''a été importé',
      round(v_debit, 2), round(v_credit, 2) USING ERRCODE = '23514';
  END IF;

  -- 2. Une pièce déjà présente (journal + numéro) ferait échouer la transaction
  --    au milieu : on refuse l'import entier, en la nommant.
  SELECT string_agg(format('%s#%s', e->>'journal_code', e->>'number'), ', ')
  INTO v_doublon
  FROM jsonb_array_elements(p_entries) e
  WHERE EXISTS (SELECT 1 FROM public.journal_entries je
                WHERE je.tenant_id = v_tid
                  AND je.journal_code = COALESCE(e->>'journal_code', 'OD')
                  AND je.number = e->>'number');
  IF v_doublon IS NOT NULL THEN
    RAISE EXCEPTION 'Import refusé : ces pièces existent déjà (%s)', v_doublon USING ERRCODE = '23505';
  END IF;

  -- 3. Les comptes manquants du plan sont créés (type déduit de la classe)
  SELECT array_agg(DISTINCT l->>'account_code')
  INTO v_comptes
  FROM jsonb_array_elements(p_entries) e,
       jsonb_array_elements(COALESCE(e->'lines', '[]'::jsonb)) l
  WHERE COALESCE(l->>'account_code', '') <> '';

  FOREACH v_code IN ARRAY COALESCE(v_comptes, '{}') LOOP
    IF NOT EXISTS (SELECT 1 FROM public.chart_accounts ca
                   WHERE ca.tenant_id = v_tid AND ca.code = v_code) THEN
      SELECT COALESCE(max(l->>'account_name'), '') INTO v_libelle
      FROM jsonb_array_elements(p_entries) e,
           jsonb_array_elements(COALESCE(e->'lines', '[]'::jsonb)) l
      WHERE l->>'account_code' = v_code;
      INSERT INTO public.chart_accounts (tenant_id, code, name, type, balance)
      VALUES (v_tid, v_code, COALESCE(NULLIF(v_libelle, ''), 'Compte importé ' || v_code),
              CASE left(v_code, 1)
                WHEN '1' THEN 'equity'
                WHEN '2' THEN 'asset'
                WHEN '3' THEN 'asset'
                WHEN '4' THEN CASE WHEN left(v_code, 2) = '41' THEN 'asset' ELSE 'liability' END
                WHEN '5' THEN 'asset'
                WHEN '6' THEN 'expense'
                WHEN '7' THEN 'income'
                ELSE 'asset' END,
              0);
      v_crees := v_crees + 1;
    END IF;
  END LOOP;

  -- 4. Les écritures et leurs lignes
  FOR v_e IN SELECT * FROM jsonb_array_elements(p_entries) LOOP
    INSERT INTO public.journal_entries (
      tenant_id, number, date, description, reference, status, journal_code, piece_number
    ) VALUES (
      v_tid,
      v_e->>'number',
      COALESCE(NULLIF(v_e->>'date', '')::date, CURRENT_DATE),
      COALESCE(v_e->>'description', 'Import ' || COALESCE(v_e->>'number', '')),
      NULLIF(v_e->>'piece_number', ''),
      'draft',
      COALESCE(v_e->>'journal_code', 'OD'),
      NULLIF(v_e->>'piece_number', '')
    ) RETURNING id INTO v_eid;
    v_ids := v_ids || v_eid;

    FOR v_l IN SELECT * FROM jsonb_array_elements(COALESCE(v_e->'lines', '[]'::jsonb)) LOOP
      INSERT INTO public.journal_lines (
        tenant_id, journal_id, account_code, account_general, account_tiers,
        debit, credit, description, line_order, lettrage_code
      ) VALUES (
        v_tid, v_eid,
        v_l->>'account_code', v_l->>'account_code', NULLIF(v_l->>'account_tiers', ''),
        COALESCE((v_l->>'debit')::numeric, 0), COALESCE((v_l->>'credit')::numeric, 0),
        NULLIF(v_l->>'description', ''), COALESCE((v_l->>'line_order')::int, 0),
        NULLIF(v_l->>'lettrage_code', '')
      );
      v_lignes := v_lignes + 1;
    END LOOP;
  END LOOP;

  -- 4bis. La validation par le chemin unique (numéro définitif, exercice,
  --       période, comptes, séparation des tâches) — 273
  v_verdicts := public.validate_journal_entries(v_ids);

  SELECT string_agg(format('%s : %s', x->>'number', x->>'error'), ' ; ')
  INTO v_ko
  FROM jsonb_array_elements(v_verdicts) x
  WHERE COALESCE((x->>'ok')::boolean, false) = false;
  IF v_ko IS NOT NULL THEN
    RAISE EXCEPTION 'Import refusé par le noyau comptable : % — rien n''a été importé', v_ko
      USING ERRCODE = '23514';
  END IF;

  -- 5. Les soldes des comptes **cumulent** l'import (SAGE-02)
  UPDATE public.chart_accounts ca
  SET balance = COALESCE(ca.balance, 0) + m.delta
  FROM (
    SELECT l->>'account_code' AS code,
           round(sum(COALESCE((l->>'debit')::numeric, 0) - COALESCE((l->>'credit')::numeric, 0)), 2) AS delta
    FROM jsonb_array_elements(p_entries) e,
         jsonb_array_elements(COALESCE(e->'lines', '[]'::jsonb)) l
    GROUP BY 1
  ) m
  WHERE ca.tenant_id = v_tid AND ca.code = m.code;

  RETURN jsonb_build_object(
    'entries', v_nb,
    'lines', v_lignes,
    'accounts_created', v_crees,
    'total_debit', round(v_debit, 2),
    'total_credit', round(v_credit, 2),
    'verdicts', v_verdicts
  );
END;
$$;

COMMENT ON FUNCTION public.import_fec_entries(jsonb) IS
  'Import d''écritures (FEC, balance) : une transaction, contrôle d''équilibre global, comptes créés au besoin, écritures validées par validate_journal_entries, soldes cumulés. 308 (W7).';

-- L'import est un acte d'écriture : l'écran y accède, pas le visiteur ni l'anonyme.
REVOKE EXECUTE ON FUNCTION public.import_fec_entries(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.import_fec_entries(jsonb) TO authenticated;

