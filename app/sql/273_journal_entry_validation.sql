-- ============================================================
-- 273_journal_entry_validation.sql — vague X2 / C4, et C14 pour les journaux
-- (audit fonctionnel exécuté du 28/09/2026 ; décisions D-A et D-C du plan)
--
-- LES DÉFAUTS, mesurés par le chemin de l'écran (base neuve, 245 migrations) :
--   C4  une écriture saisie naît brouillon et aucun chemin d'interface ne la
--       valide. « Clôturer » ne pose que `status_detail = 'closed'` : le statut
--       reste `draft`, sans numéro définitif, hors FEC, hors balance, hors bilan.
--       La clôture d'un journal × période passait sur des brouillons ; celle
--       d'une période fiscale aussi. Et dès qu'une écriture du lot était
--       validée, la clôture échouait : une écriture validée refusait même son
--       marqueur de clôture (`prevent_posted_entry_modification`).
--   C4  `createSaisieEntry` insérait l'en-tête PUIS les lignes (non atomique) ;
--       `post_journal_entry`, le chemin atomique, perdait la pièce, la
--       référence, le modèle, la devise, le taux et l'état de saisie.
--   C14 la fiche journal envoyait quatre colonnes absentes : création refusée.
--       La base porte déjà `account_attente` et `numbering_mode`, lues par
--       PERSONNE.
--
-- LES CORRECTIFS (D-A : brouillon puis « Valider » ; D-C : une donnée n'existe
-- que si une règle la lit)
--   1. `validate_journal_entries(uuid[])` : valide chaque écriture dans sa
--      propre sous-transaction et rend un verdict PAR écriture
--      (`{id, number, ok, posting_number | error}`). Elle ne réécrit aucune
--      règle : le passage à `posted` déclenche le noyau déjà prouvé (équilibre,
--      exercice et période ouverts, comptes ouverts, droit
--      `journal_entry.post`, séparation des tâches de la 232, numéro définitif,
--      `validated_by` / `validated_at`, événement NF-525). SECURITY INVOKER :
--      la RLS et les déclencheurs voient l'utilisateur réel.
--   2. Journaux : `racines_autorisees` (liste de préfixes « 512, 411 ») est
--      AJOUTÉE et CONTRÔLÉE — à la saisie (`post_journal_entry`) et à la
--      validation (la 1) ; le compte d'attente (`account_attente`, colonne
--      existante) passe toujours et doit exister au plan. `numbering_mode`
--      n'est lue par aucune règle : la numérotation est celle de la base
--      (brouillon, puis numéro définitif continu à la validation) — l'écran
--      cesse de l'offrir.
--   3. `post_journal_entry` garde l'en-tête de la saisie. Son corps est celui
--      de sa dernière version (271) : seules l'insertion de l'en-tête et la
--      garde des racines changent.
--   4. Clôtures : un journal × période ou une période fiscale ne se clôture
--      pas tant qu'il reste un brouillon — le refus NOMME les pièces. Une
--      écriture validée accepte son marqueur de clôture (`status_detail`), et
--      rien d'autre : le fond reste immuable.
--
-- Suite : `273_journal_entry_validation_tests.sql` (9 scénarios, rouges avant).
-- ============================================================

-- ── 2. Journaux : racines autorisées et compte d'attente ─────────────────────
ALTER TABLE public.journals ADD COLUMN IF NOT EXISTS racines_autorisees text;

COMMENT ON COLUMN public.journals.racines_autorisees IS
  'X2/C14 (273) : préfixes de comptes admis dans ce journal, séparés par des virgules '
  '(« 512, 411, 401 »). Vide = tous. Le compte d''attente et le compte de contrepartie '
  'du journal passent toujours. Contrôlé par post_journal_entry et validate_journal_entries.';
COMMENT ON COLUMN public.journals.account_attente IS
  'X2/C14 (273) : compte d''attente du journal (47x). Admis même hors racines ; doit exister au plan.';
COMMENT ON COLUMN public.journals.numbering_mode IS
  'Non lue (273) : la numérotation est celle de la base — numéro provisoire au brouillon, '
  'numéro définitif continu par journal et par exercice à la validation (187/217).';

-- Normalise la liste et vérifie le compte d'attente
CREATE OR REPLACE FUNCTION public.journal_settings_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_prefix text;
BEGIN
  IF NEW.racines_autorisees IS NOT NULL THEN
    SELECT string_agg(p, ', ' ORDER BY ord)
      INTO NEW.racines_autorisees
    FROM (
      SELECT btrim(x) AS p, ord
      FROM unnest(string_to_array(NEW.racines_autorisees, ',')) WITH ORDINALITY AS u(x, ord)
      WHERE btrim(x) <> ''
    ) s;
    FOR v_prefix IN SELECT btrim(x) FROM unnest(string_to_array(coalesce(NEW.racines_autorisees, ''), ',')) x
                    WHERE btrim(x) <> '' LOOP
      IF v_prefix !~ '^[0-9]{1,8}$' THEN
        RAISE EXCEPTION 'Racine de compte « % » invalide : des chiffres seulement (ex. 512, 411)', v_prefix
          USING ERRCODE = 'check_violation';
      END IF;
    END LOOP;
  END IF;

  NEW.account_attente := NULLIF(btrim(NEW.account_attente), '');
  IF NEW.account_attente IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.account_attente IS DISTINCT FROM OLD.account_attente)
     AND NOT EXISTS (SELECT 1 FROM chart_accounts
                     WHERE tenant_id = NEW.tenant_id AND code = NEW.account_attente) THEN
    RAISE EXCEPTION 'Compte d''attente % absent du plan comptable de la société', NEW.account_attente
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION public.journal_settings_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tg_journal_settings_guard ON public.journals;
CREATE TRIGGER tg_journal_settings_guard
  BEFORE INSERT OR UPDATE OF racines_autorisees, account_attente ON public.journals
  FOR EACH ROW EXECUTE FUNCTION public.journal_settings_guard();

-- Premier compte d'une écriture qui sort des racines de son journal (NULL : conforme)
CREATE OR REPLACE FUNCTION public.journal_entry_root_violation(p_entry_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT min(coalesce(l.account_general, l.account_code))
  FROM journal_entries e
  JOIN journals j ON j.tenant_id = e.tenant_id AND j.code = e.journal_code
  JOIN journal_lines l ON l.journal_id = e.id
  WHERE e.id = p_entry_id
    AND nullif(btrim(j.racines_autorisees), '') IS NOT NULL
    AND coalesce(l.account_general, l.account_code) IS DISTINCT FROM j.account_attente
    AND coalesce(l.account_general, l.account_code) IS DISTINCT FROM j.account_counterpart
    AND NOT EXISTS (
      SELECT 1 FROM unnest(string_to_array(j.racines_autorisees, ',')) r
      WHERE btrim(r) <> '' AND coalesce(l.account_general, l.account_code) LIKE btrim(r) || '%')
$$;
REVOKE EXECUTE ON FUNCTION public.journal_entry_root_violation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.journal_entry_root_violation(uuid) TO authenticated, service_role;

-- ── 3a. Le modèle de saisie d'une écriture est un modèle de saisie ──────────
-- La 83 avait rattaché `journal_entries.entry_template_id` à `recurring_entries`
-- (clé devinée ; la 237 l'a rendue composite). Les deux écrans qui la posent
-- (saisie par journal, saisie par pièce) envoient l'identifiant d'un
-- `entry_templates` : toute saisie faite depuis un modèle était refusée. Aucune
-- fonction n'y écrit un identifiant d'abonnement (vérifié le 28/09).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'entry_templates_tenant_id_id_key') THEN
    ALTER TABLE public.entry_templates ADD CONSTRAINT entry_templates_tenant_id_id_key UNIQUE (tenant_id, id);
  END IF;
END $$;
ALTER TABLE public.journal_entries DROP CONSTRAINT IF EXISTS journal_entries_entry_template_id_fkey;
UPDATE public.journal_entries e SET entry_template_id = NULL
WHERE entry_template_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM entry_templates t WHERE t.tenant_id = e.tenant_id AND t.id = e.entry_template_id)
  AND status <> 'posted';
DO $$ BEGIN
  -- une écriture validée est immuable : si l'une d'elles porte un ancien
  -- identifiant d'abonnement, la clé n'est posée que pour les lignes à venir
  IF EXISTS (SELECT 1 FROM journal_entries e WHERE entry_template_id IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM entry_templates t WHERE t.tenant_id = e.tenant_id AND t.id = e.entry_template_id)) THEN
    ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_entry_template_id_fkey
      FOREIGN KEY (tenant_id, entry_template_id) REFERENCES public.entry_templates (tenant_id, id)
      ON DELETE SET NULL (entry_template_id) NOT VALID;
  ELSE
    ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_entry_template_id_fkey
      FOREIGN KEY (tenant_id, entry_template_id) REFERENCES public.entry_templates (tenant_id, id)
      ON DELETE SET NULL (entry_template_id);
  END IF;
END $$;

-- ── 3. post_journal_entry : l'en-tête de la saisie, et les racines ───────────
-- Corps de la 271, par remplacement d'ancres exactes : la migration échoue si
-- une ancre a changé, plutôt que de réécrire la fonction de mémoire.
DO $mig$
DECLARE
  v_def text := pg_get_functiondef('public.post_journal_entry(jsonb, jsonb)'::regprocedure);
  v_new text;
  a_insert constant text := $a$  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref, piece_number
  ) VALUES (
    v_tid,
    v_number,
    (p_entry ->> 'date')::date,
    v_journal_code,
    'draft',  -- AUD-C10 : toujours en brouillard ; validation après les lignes
    p_entry ->> 'description',
    p_entry ->> 'invoice_ref',
    v_number
  )
  RETURNING id INTO v_entry_id;$a$;
  r_insert constant text := $a$  -- X2/C4 (273) : l'en-tête de la saisie est gardé (pièce, référence, modèle,
  -- devise, taux, état de saisie) ; le reste est posé par le noyau.
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref, piece_number, reference, entry_template_id,
    currency_code, functional_currency, exchange_rate, exchange_rate_date, status_detail
  ) VALUES (
    v_tid,
    v_number,
    (p_entry ->> 'date')::date,
    v_journal_code,
    'draft',  -- AUD-C10 : toujours en brouillard ; validation après les lignes
    p_entry ->> 'description',
    p_entry ->> 'invoice_ref',
    COALESCE(NULLIF(btrim(p_entry ->> 'piece_number'), ''), v_number),
    NULLIF(p_entry ->> 'reference', ''),
    NULLIF(p_entry ->> 'entry_template_id', '')::uuid,
    COALESCE(NULLIF(p_entry ->> 'currency_code', ''), 'EUR'),
    COALESCE(NULLIF(p_entry ->> 'functional_currency', ''), NULLIF(p_entry ->> 'currency_code', ''), 'EUR'),
    COALESCE(NULLIF(p_entry ->> 'exchange_rate', '')::numeric, 1),
    NULLIF(p_entry ->> 'exchange_rate_date', '')::date,
    COALESCE(NULLIF(p_entry ->> 'status_detail', ''), 'open')
  )
  RETURNING id INTO v_entry_id;$a$;
  a_empty constant text := $a$  IF jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Écriture vide: aucune ligne fournie';
  END IF;$a$;
  r_empty constant text := $a$  IF jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Écriture vide: aucune ligne fournie';
  END IF;

  -- X2/C14 (273) : un journal à racines autorisées refuse un compte hors racines
  -- (le compte d'attente et la contrepartie du journal passent toujours)
  v_hors_racines := journal_entry_root_violation(v_entry_id);
  IF v_hors_racines IS NOT NULL THEN
    RAISE EXCEPTION 'Compte % hors des racines autorisées du journal %', v_hors_racines, v_journal_code
      USING ERRCODE = 'check_violation';
  END IF;$a$;
  a_decl constant text := $a$  v_journal_code text;
BEGIN$a$;
  r_decl constant text := $a$  v_journal_code text;
  v_hors_racines text;
BEGIN$a$;
BEGIN
  IF position('v_hors_racines' IN v_def) > 0 THEN
    RETURN;   -- déjà appliquée (rejeu de la migration)
  END IF;
  IF position(a_insert IN v_def) = 0 OR position(a_empty IN v_def) = 0 OR position(a_decl IN v_def) = 0 THEN
    RAISE EXCEPTION '273 : post_journal_entry a changé depuis la 271 — ancre introuvable, migration à reprendre';
  END IF;
  v_new := replace(replace(replace(v_def, a_insert, r_insert), a_empty, r_empty), a_decl, r_decl);
  EXECUTE v_new;
END $mig$;

-- ── 1. validate_journal_entries ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_journal_entries(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_out jsonb := '[]'::jsonb;
  v_id uuid;
  v_e record;
  v_hors text;
  v_pn text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN v_out;
  END IF;
  IF cardinality(p_ids) > 500 THEN
    RAISE EXCEPTION 'Au plus 500 écritures par validation (% demandées)', cardinality(p_ids);
  END IF;

  FOREACH v_id IN ARRAY p_ids LOOP
    SELECT id, number, status INTO v_e
    FROM journal_entries WHERE id = v_id AND tenant_id = v_tid;

    IF NOT FOUND THEN
      v_out := v_out || jsonb_build_object('id', v_id, 'ok', false, 'error', 'Écriture introuvable pour cette société');
      CONTINUE;
    END IF;
    IF v_e.status = 'posted' THEN
      v_out := v_out || jsonb_build_object('id', v_id, 'number', v_e.number, 'ok', false, 'error', 'Écriture déjà validée');
      CONTINUE;
    END IF;

    BEGIN
      IF NOT has_permission('journal_entry.post') THEN
        RAISE EXCEPTION 'Permission refusée : validation d''écriture (journal_entry.post)';
      END IF;
      v_hors := journal_entry_root_violation(v_id);
      IF v_hors IS NOT NULL THEN
        RAISE EXCEPTION 'Compte % hors des racines autorisées du journal', v_hors;
      END IF;
      -- le noyau fait le reste : équilibre, exercice, période, comptes,
      -- séparation des tâches, numéro définitif, validateur, NF-525
      UPDATE journal_entries SET status = 'posted'
      WHERE id = v_id AND tenant_id = v_tid
      RETURNING posting_number INTO v_pn;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Permission refusée : écriture non modifiable par cet utilisateur';
      END IF;
      v_out := v_out || jsonb_build_object('id', v_id, 'number', v_e.number, 'ok', true, 'posting_number', v_pn);
    EXCEPTION WHEN OTHERS THEN
      v_out := v_out || jsonb_build_object('id', v_id, 'number', v_e.number, 'ok', false, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN v_out;
END $$;

COMMENT ON FUNCTION public.validate_journal_entries(uuid[]) IS
  'X2/C4 (273, décision D-A) : valide des écritures brouillon, chacune dans sa sous-transaction ; '
  'rend un verdict par écriture {id, number, ok, posting_number | error}. Les règles sont celles '
  'du noyau (équilibre, période, droit journal_entry.post, séparation des tâches, numéro définitif).';
REVOKE EXECUTE ON FUNCTION public.validate_journal_entries(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.validate_journal_entries(uuid[]) TO authenticated, service_role;

-- ── 4. Clôtures ─────────────────────────────────────────────────────────────
-- 4a. Une écriture validée accepte son marqueur de clôture, rien d'autre.
CREATE OR REPLACE FUNCTION public.prevent_posted_entry_modification()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Une écriture validée (posted) ne peut être ni modifiée ni supprimée
  -- L'annulation passe par generateExtourne (création d'une écriture inverse)
  IF (TG_OP = 'DELETE') THEN
    IF OLD.status = 'posted' THEN
      RAISE EXCEPTION 'Écriture % est validée (posted) — immuable. Utiliser l''extourne pour annuler.', OLD.id;
    END IF;
    RETURN OLD;
  END IF;
  -- TG_OP = 'UPDATE'
  IF OLD.status = 'posted' THEN
    -- X2/C4 (273) : l'état de saisie (ouverte / imprimée / clôturée) n'est pas
    -- le contenu comptable ; la clôture d'un journal × période le pose sur des
    -- écritures validées. Toute autre différence reste refusée.
    IF (to_jsonb(NEW) - 'status_detail' - 'updated_at') = (to_jsonb(OLD) - 'status_detail' - 'updated_at') THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Écriture % est validée (posted) — immuable. Utiliser l''extourne pour annuler.', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- 4b. Un brouillon ne se clôture pas : la clôture d'un journal × période le nomme.
CREATE OR REPLACE FUNCTION public.journal_entry_close_requires_posted()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.status_detail = 'closed' AND OLD.status_detail IS DISTINCT FROM 'closed'
     AND NEW.status IS DISTINCT FROM 'posted' THEN
    RAISE EXCEPTION 'Clôture refusée : l''écriture % (%) est en brouillon — validez-la ou supprimez-la avant de clôturer',
      NEW.number, to_char(NEW.date, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION public.journal_entry_close_requires_posted() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tg_journal_entry_close_requires_posted ON public.journal_entries;
CREATE TRIGGER tg_journal_entry_close_requires_posted
  BEFORE UPDATE OF status_detail ON public.journal_entries
  FOR EACH ROW EXECUTE FUNCTION public.journal_entry_close_requires_posted();

-- 4c. Une période fiscale ne se clôture pas sur des brouillons (nommés, 10 au plus).
CREATE OR REPLACE FUNCTION public.fiscal_period_close_requires_posted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_n int;
  v_list text;
BEGIN
  IF NEW.status IN ('closed', 'locked') AND OLD.status IS DISTINCT FROM NEW.status
     AND OLD.status NOT IN ('closed', 'locked') THEN
    SELECT count(*), string_agg(number, ', ' ORDER BY date, number) FILTER (WHERE rn <= 10)
      INTO v_n, v_list
    FROM (
      SELECT number, date, row_number() OVER (ORDER BY date, number) rn
      FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND status = 'draft'
        AND date BETWEEN NEW.start_date AND NEW.end_date
    ) d;
    IF v_n > 0 THEN
      RAISE EXCEPTION 'Clôture de la période % refusée : % écriture(s) en brouillon (%) — à valider ou supprimer',
        NEW.period_label, v_n, v_list || CASE WHEN v_n > 10 THEN '…' ELSE '' END
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fiscal_period_close_requires_posted() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tg_fiscal_period_close_requires_posted ON public.fiscal_periods;
CREATE TRIGGER tg_fiscal_period_close_requires_posted
  BEFORE UPDATE OF status ON public.fiscal_periods
  FOR EACH ROW EXECUTE FUNCTION public.fiscal_period_close_requires_posted();
