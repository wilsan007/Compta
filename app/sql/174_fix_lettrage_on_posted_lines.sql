-- ============================================================
-- 174_fix_lettrage_on_posted_lines.sql
--
-- Le lettrage ne pouvait s'appliquer à aucune écriture validée.
--
-- `prevent_posted_line_modification` refuse toute INSERT, UPDATE ou DELETE sur
-- une ligne dont l'écriture est `posted`. Or les quatre fonctions de lettrage
-- — `apply_lettrage`, `remove_lettrage`, `auto_lettrage_by_reference`,
-- `auto_letter_accounts` — procèdent par `UPDATE journal_lines SET
-- lettrage_code = …`. Elles échouaient donc systématiquement sur une écriture
-- validée, c'est-à-dire dans le seul cas qui compte : on lettre une facture
-- validée contre un règlement validé, jamais deux brouillons.
--
-- Mesuré avant correctif : `apply_lettrage` sur deux lignes d'une écriture
-- `posted` lève « Ligne d'écriture … validée (posted) — immuable ».
--
-- Correctif : l'immuabilité porte sur les valeurs comptables, pas sur les
-- annotations. Une ligne validée accepte désormais la modification des seules
-- colonnes de lettrage et de rapprochement ; montant, compte, date, libellé et
-- tout le reste restent gelés, et l'insertion comme la suppression restent
-- interdites.
--
-- Second défaut corrigé ici : `apply_lettrage` vérifiait l'unicité du compte de
-- tiers sur `left(compte, 3)`. 411001 et 411002 — deux clients différents — se
-- réduisent tous deux à « 411 ». On pouvait donc lettrer la facture d'un client
-- contre le règlement d'un autre, le contrôle d'équilibre étant satisfait par
-- la seule égalité des montants. La comparaison porte désormais sur le compte
-- complet.
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_posted_line_modification()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  v_entry_status text;
  v_entry_id uuid;
  -- Colonnes d'annotation : elles ne portent aucune valeur comptable et
  -- doivent rester modifiables après validation, sans quoi le lettrage et le
  -- rapprochement bancaire sont inapplicables.
  v_annotations text[] := ARRAY[
    'lettrage_code', 'lettrage_date', 'lettrage_partial', 'lettrage_group_id',
    'reconciled', 'amount_residual'
  ];
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_entry_id := OLD.journal_id;
  ELSE
    v_entry_id := NEW.journal_id;
  END IF;

  SELECT status INTO v_entry_status FROM journal_entries WHERE id = v_entry_id;

  IF v_entry_status = 'posted' THEN
    -- Seule exception : une mise à jour qui ne touche que des annotations.
    IF TG_OP = 'UPDATE'
       AND (to_jsonb(OLD) - v_annotations) = (to_jsonb(NEW) - v_annotations) THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Ligne d''écriture % validée (posted) — immuable. Utiliser l''extourne pour annuler.', v_entry_id;
  END IF;

  IF (TG_OP = 'DELETE') THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- Unicité du compte de tiers sur le compte complet
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_lettrage(p_line_ids uuid[], p_code text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_d numeric;
  v_c numeric;
  v_comptes int;
  v_code text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- LOT4-08 : Générer le code si non fourni
  IF p_code IS NULL OR p_code = '' THEN
    v_code := next_lettrage_code();
  ELSE
    v_code := p_code;
  END IF;

  -- LOT4-09 : Vérifier l'équilibre débit/crédit
  -- Le compte est comparé en entier : `left(compte, 3)` confondait 411001 et
  -- 411002, donc deux clients distincts.
  SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0),
         count(DISTINCT COALESCE(account_general, account_code))
  INTO v_d, v_c, v_comptes
  FROM journal_lines
  WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  IF v_comptes > 1 THEN
    RAISE EXCEPTION 'Lettrage sur % comptes de tiers différents', v_comptes;
  END IF;

  IF ABS(v_d - v_c) > 0.01 THEN
    RAISE EXCEPTION 'Lettrage déséquilibré : débit % ≠ crédit % (écart %)', v_d, v_c, ABS(v_d - v_c);
  END IF;

  UPDATE journal_lines
  SET lettrage_code = v_code, lettrage_date = CURRENT_DATE
  WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  RETURN jsonb_build_object(
    'code', v_code,
    'lines', array_length(p_line_ids, 1),
    'amount', v_d
  );
END;
$function$;
