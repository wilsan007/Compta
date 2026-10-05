-- ============================================================
-- 353_analytic_credit_note_grill_draft.sql — tâche 2.13 (G1, pil-008) : les restes
--
-- La 304 a fait circuler la section analytique de la ligne de FACTURE vers la
-- ligne d'écriture, la 350 a rendu les grilles de ventilation réelles (compte
-- et sections sous clés étrangères). Trois choses manquaient, prouvées par
-- `353_analytic_credit_note_grill_draft_tests.sql` (6 rouges avant ce fichier) :
--
--   1. L'AVOIR. `credit_note_lines` n'avait pas de porteur : un avoir sans
--      facture d'origine ne pouvait être imputé nulle part.
--   2. LA GRILLE. `distribution_grills` n'était lue par AUCUN chemin
--      d'écriture (seule `distribute_by_grill`, une lecture que rien n'appelle) :
--      une grille posée sur 707000 ne ventilait jamais rien.
--   3. LE BROUILLON. Une facture en brouillon ne se modifiait pas : il fallait
--      la supprimer et la ressaisir.
--
-- LES RÈGLES, ÉCRITES.
--   • Ordre de priorité sur une ligne d'écriture de classe 6 ou 7 : la
--     ventilation saisie sur la ligne, puis la section de la ligne du DOCUMENT
--     (avoir, facture, facture d'achat), puis la GRILLE du compte. Ce que
--     l'utilisateur a choisi prime toujours sur ce qui est automatique (T05).
--   • Une grille ne s'applique que si elle est ENTIÈREMENT valide : active,
--     somme des parts = 100 % (± 0,01), sections actives, imputables (pas de
--     section « total ») et toutes du même plan. Sinon elle est ignorée : une
--     grille fausse ne bloque JAMAIS une écriture comptable (T04).
--   • La grille du journal de l'écriture prime sur la grille sans journal.
--     Entre deux grilles actives du même compte et du même journal, la PLUS
--     ANCIENNE s'applique (mesuré en rejouant le scénario d'écran AN04 deux fois) :
--     rien n'interdit encore d'en créer deux.
--   • Les parts d'une grille sont écrites dans `analytic_distribution_lines`
--     (la dernière part absorbe l'arrondi : le total fait le montant de la
--     ligne) ; la ligne d'écriture porte la section dominante et sa part.
--   • Un brouillon né d'un autre document (temps passé, bon de livraison,
--     commande) ne se modifie pas par ce chemin : ses lignes sont rattachées.
--
-- LES LIMITES, DITES.
--   • La balance analytique de l'écran lit encore UNE section par ligne
--     d'écriture : le présent fichier écrit les parts, la lecture est corrigée
--     côté écran dans le même commit (`getAnalyticBalance`).
--   • Les avoirs d'ACHAT n'ont pas de lignes (`purchase_credit_notes` est un
--     en-tête seul) : rien à imputer par ligne.
--   • La paie, le stock, la caisse et la production ne portent toujours pas de
--     section sur leurs documents ; la grille du compte, elle, s'applique à
--     TOUTE ligne d'écriture de classe 6 ou 7, d'où qu'elle vienne.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Le porteur sur la ligne d'avoir (clé composite, doctrine 237)
-- ------------------------------------------------------------
ALTER TABLE public.credit_note_lines ADD COLUMN IF NOT EXISTS analytic_section_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'credit_note_lines_analytic_section_fkey') THEN
    ALTER TABLE public.credit_note_lines
      ADD CONSTRAINT credit_note_lines_analytic_section_fkey
      FOREIGN KEY (tenant_id, analytic_section_id)
      REFERENCES public.analytic_sections (tenant_id, id) ON DELETE SET NULL (analytic_section_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_credit_note_lines_tenant_section
  ON public.credit_note_lines (tenant_id, analytic_section_id);

COMMENT ON COLUMN public.credit_note_lines.analytic_section_id IS
  '2.13 (353) : section analytique de la ligne d''avoir — reprise sur la ligne d''écriture de l''avoir';

-- ------------------------------------------------------------
-- 1 bis. L'avoir en cours de validation se fait connaître
-- ------------------------------------------------------------
-- `credit_note_guard` (BEFORE) attribue le numéro définitif ET écrit l'écriture
-- dans le même geste : quand les lignes d'écriture naissent, la table porte
-- encore le numéro PROVISOIRE de l'avoir — le numéro de pièce de l'écriture ne
-- retrouve rien (mesuré : T01 rouge avec le seul rapprochement par numéro).
-- L'avoir se signale donc par un contexte de transaction, ouvert AVANT la garde
-- (le nom du déclencheur le place en tête) et refermé APRÈS la mise à jour.
CREATE OR REPLACE FUNCTION public.credit_note_analytic_context()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_WHEN = 'BEFORE' THEN
    IF OLD.status = 'draft' AND NEW.status IN ('validated', 'applied') THEN
      PERFORM set_config('app.credit_note_validating', NEW.id::text, true);
    END IF;
    RETURN NEW;
  END IF;
  PERFORM set_config('app.credit_note_validating', '', true);
  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.credit_note_analytic_context() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS a0_credit_note_analytic_context ON public.credit_notes;
CREATE TRIGGER a0_credit_note_analytic_context
  BEFORE UPDATE OF status ON public.credit_notes
  FOR EACH ROW EXECUTE FUNCTION public.credit_note_analytic_context();

DROP TRIGGER IF EXISTS zz_credit_note_analytic_context_end ON public.credit_notes;
CREATE TRIGGER zz_credit_note_analytic_context_end
  AFTER UPDATE OF status ON public.credit_notes
  FOR EACH ROW EXECUTE FUNCTION public.credit_note_analytic_context();

-- ------------------------------------------------------------
-- 2. La grille d'un compte, si elle est entièrement valide
-- ------------------------------------------------------------
-- Rend la ventilation `{plan: {section: pourcentage}}` de la grille applicable à
-- (société, compte, journal), ou NULL. Interne : non exposée.
CREATE OR REPLACE FUNCTION public.analytic_grill_distribution(p_tenant uuid, p_account text, p_journal text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  g record;
  v_dist jsonb;
BEGIN
  IF p_tenant IS NULL OR p_account IS NULL THEN
    RETURN NULL;
  END IF;

  FOR g IN
    SELECT dg.id
    FROM distribution_grills dg
    WHERE dg.tenant_id = p_tenant
      AND dg.account_code = p_account
      AND dg.active IS NOT FALSE
      AND (NULLIF(dg.journal_code, '') IS NULL OR dg.journal_code = p_journal)
    ORDER BY (NULLIF(dg.journal_code, '') IS NOT NULL) DESC, dg.created_at, dg.id
  LOOP
    SELECT CASE
             WHEN count(*) > 0
              AND abs(sum(l.percentage) - 100) <= 0.01
              AND bool_and(l.percentage > 0)
              AND bool_and(s.id IS NOT NULL AND s.active IS NOT FALSE AND s.section_type IS DISTINCT FROM 'total')
              AND count(DISTINCT COALESCE(s.plan_id::text, 'sans-plan')) = 1
             THEN jsonb_build_object(
                    COALESCE(min(s.plan_id::text), 'sans-plan'),
                    jsonb_object_agg(s.id::text, l.percentage))
           END
    INTO v_dist
    FROM distribution_grill_lines l
    LEFT JOIN analytic_sections s ON s.tenant_id = l.tenant_id AND s.code = l.section_code
    WHERE l.tenant_id = p_tenant AND l.grill_id = g.id;

    IF v_dist IS NOT NULL THEN
      RETURN v_dist;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.analytic_grill_distribution(uuid, text, text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 3. La propagation : ventilation saisie → document (avoir, facture, achat) → grille
-- ------------------------------------------------------------
-- Corps de la 304, repris à l'identique pour ses deux premières étapes ; ajoutés :
-- la ligne d'AVOIR (étape 2, en tête : l'avoir se reconnaît à son numéro de pièce)
-- et la GRILLE du compte (étape 3).
CREATE OR REPLACE FUNCTION public.propagate_analytic_section()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_plan text;
  v_section text;
  v_pct numeric;
  v_base numeric;
  v_ref text;
  v_inv_ref text;
  v_piece text;
  v_journal text;
  v_sec uuid;
  v_compte text := COALESCE(NEW.account_code, NEW.account_general);
  v_grille jsonb;
  v_avoir uuid := NULLIF(current_setting('app.credit_note_validating', true), '')::uuid;
BEGIN
  -- ── 1. La ventilation multi-axes donne la section et le montant ──────────
  IF NEW.analytic_distribution IS NOT NULL
     AND jsonb_typeof(NEW.analytic_distribution) = 'object'
     AND NEW.analytic_distribution <> '{}'::jsonb THEN

    -- La section **dominante** (plus fort pourcentage) donne la section plate, et
    -- le montant analytique suit le pourcentage appliqué à l'assiette de la ligne.
    SELECT p.key, s.key, (s.value)::numeric
    INTO v_plan, v_section, v_pct
    FROM jsonb_each(NEW.analytic_distribution) p,
         LATERAL jsonb_each(CASE WHEN jsonb_typeof(p.value) = 'object' THEN p.value ELSE '{}'::jsonb END) s
    WHERE (s.value)::text ~ '^-?[0-9]+(\.[0-9]+)?$'
    ORDER BY (s.value)::numeric DESC, s.key
    LIMIT 1;

    IF v_section IS NOT NULL THEN
      IF NEW.analytic_section_id IS NULL THEN
        NEW.analytic_section_id := v_section::uuid;
      END IF;
      IF NEW.analytic_amount IS NULL OR NEW.analytic_amount = 0 THEN
        v_base := COALESCE(NULLIF(NEW.debit, 0), NEW.credit, 0);
        NEW.analytic_amount := round(v_base * v_pct / 100.0, 2);
      END IF;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.analytic_section_id IS NOT NULL OR v_compte IS NULL OR v_compte !~ '^[67]' THEN
    RETURN NEW;
  END IF;

  -- ── 2. La section de la ligne de **document** d'origine ─────────────────
  -- ANA-02 : les écritures engendrées (ventes, achats) naissent d'un document
  -- qui sait à quoi la dépense ou le produit se rattache. La ligne d'écriture
  -- porte le compte ; la ligne de document porte la section : on les apparie par
  -- le numéro du document et par le compte.
  SELECT e.invoice_ref, e.reference, e.piece_number, e.journal_code
  INTO v_inv_ref, v_ref, v_piece, v_journal
  FROM journal_entries e
  WHERE e.id = NEW.journal_id AND e.tenant_id = NEW.tenant_id;

  -- Avoirs de vente (353) : l'avoir en cours de validation (contexte), sinon celui
  -- dont l'écriture porte le numéro en numéro de pièce. Même résolution de compte
  -- que `credit_note_guard`.
  IF v_avoir IS NOT NULL OR v_piece IS NOT NULL THEN
    SELECT cl.analytic_section_id INTO v_sec
    FROM credit_notes cn
    JOIN credit_note_lines cl ON cl.credit_note_id = cn.id AND cl.tenant_id = cn.tenant_id
    LEFT JOIN products p ON p.id = cl.product_id AND p.tenant_id = cn.tenant_id
    LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = cn.tenant_id
    WHERE cn.tenant_id = NEW.tenant_id
      AND (cn.id = v_avoir OR (v_avoir IS NULL AND cn.number = v_piece))
      AND cl.analytic_section_id IS NOT NULL
      AND COALESCE(p.sale_account_code, pc.sale_account_code, cl.account_code,
                   CASE WHEN p.type = 'service' THEN '706000' ELSE '707000' END) = v_compte
    ORDER BY cl.line_order, cl.id
    LIMIT 1;

    -- Lignes d'avoir SANS article : `credit_note_guard` les passe aux comptes de
    -- l'écriture d'origine au prorata, à défaut au 709000 — le compte ne se déduit
    -- pas de la ligne. La première ligne libre qui porte une section la donne.
    IF v_sec IS NULL THEN
      SELECT cl.analytic_section_id INTO v_sec
      FROM credit_notes cn
      JOIN credit_note_lines cl ON cl.credit_note_id = cn.id AND cl.tenant_id = cn.tenant_id
      WHERE cn.tenant_id = NEW.tenant_id
        AND (cn.id = v_avoir OR (v_avoir IS NULL AND cn.number = v_piece))
        AND cl.product_id IS NULL
        AND cl.analytic_section_id IS NOT NULL
        AND v_compte ~ '^7'
      ORDER BY cl.line_order, cl.id
      LIMIT 1;
    END IF;
  END IF;

  IF v_sec IS NULL AND COALESCE(v_inv_ref, v_ref) IS NOT NULL THEN
    -- Ventes : compte de produit de l'article, sinon de sa catégorie, sinon 707000
    SELECT il.analytic_section_id INTO v_sec
    FROM invoices i
    JOIN invoice_lines il ON il.invoice_id = i.id AND il.tenant_id = i.tenant_id
    LEFT JOIN products p ON p.id = il.product_id AND p.tenant_id = i.tenant_id
    LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = i.tenant_id
    WHERE i.tenant_id = NEW.tenant_id
      AND i.number IN (v_inv_ref, v_ref)
      AND il.analytic_section_id IS NOT NULL
      AND COALESCE(p.sale_account_code, pc.sale_account_code, '707000') = v_compte
    LIMIT 1;

    -- Achats : compte de charge de l'article, sinon de sa catégorie, sinon 607000
    IF v_sec IS NULL THEN
      SELECT pil.analytic_section_id INTO v_sec
      FROM purchase_invoices pi
      JOIN purchase_invoice_lines pil ON pil.purchase_invoice_id = pi.id AND pil.tenant_id = pi.tenant_id
      LEFT JOIN products p ON p.id = pil.product_id AND p.tenant_id = pi.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = pi.tenant_id
      WHERE pi.tenant_id = NEW.tenant_id
        AND pi.number IN (v_inv_ref, v_ref)
        AND pil.analytic_section_id IS NOT NULL
        AND COALESCE(p.purchase_account_code, pc.purchase_account_code, '607000') = v_compte
      LIMIT 1;
    END IF;
  END IF;

  IF v_sec IS NOT NULL THEN
    NEW.analytic_section_id := v_sec;
    IF NEW.analytic_amount IS NULL OR NEW.analytic_amount = 0 THEN
      NEW.analytic_amount := COALESCE(NULLIF(NEW.debit, 0), NEW.credit, 0);
    END IF;
    RETURN NEW;
  END IF;

  -- ── 3. La grille de ventilation du compte (353) ─────────────────────────
  -- Personne n'a rien choisi : la grille du compte s'applique, si elle est
  -- entièrement valide. Les parts sont écrites après l'insertion de la ligne
  -- (`journal_line_materialize_grill`), reconnue par son identifiant.
  IF TG_OP = 'INSERT' THEN
    v_grille := analytic_grill_distribution(NEW.tenant_id, v_compte, v_journal);
    IF v_grille IS NOT NULL THEN
      SELECT s.key, (s.value)::numeric INTO v_section, v_pct
      FROM jsonb_each(v_grille) p, LATERAL jsonb_each(p.value) s
      ORDER BY (s.value)::numeric DESC, s.key
      LIMIT 1;

      v_base := COALESCE(NULLIF(NEW.debit, 0), NEW.credit, 0);
      NEW.analytic_distribution := v_grille;
      NEW.analytic_section_id := v_section::uuid;
      NEW.analytic_amount := round(v_base * v_pct / 100.0, 2);
      PERFORM set_config('app.analytic_grill_line', NEW.id::text, true);
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.propagate_analytic_section() FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 4. Les parts de la grille, écrites avec la ligne
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.journal_line_materialize_grill()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_base numeric := COALESCE(NULLIF(NEW.debit, 0), NEW.credit, 0);
  v_reste numeric := v_base;
  v_n integer;
  v_i integer := 0;
  r record;
  v_part numeric;
BEGIN
  -- Seule une ligne ventilée PAR UNE GRILLE dans cette transaction est traitée :
  -- les ventilations saisies à l'écran écrivent leurs parts elles-mêmes.
  IF current_setting('app.analytic_grill_line', true) IS DISTINCT FROM NEW.id::text THEN
    RETURN NULL;
  END IF;
  PERFORM set_config('app.analytic_grill_line', '', true);

  SELECT count(*) INTO v_n
  FROM jsonb_each(NEW.analytic_distribution) p, LATERAL jsonb_each(p.value) s;

  FOR r IN
    SELECT p.key AS plan, s.key AS section, (s.value)::numeric AS pct
    FROM jsonb_each(NEW.analytic_distribution) p, LATERAL jsonb_each(p.value) s
    ORDER BY (s.value)::numeric DESC, s.key
  LOOP
    v_i := v_i + 1;
    -- la dernière part absorbe l'arrondi : la somme des parts fait le montant de la ligne
    v_part := CASE WHEN v_i = v_n THEN v_reste ELSE round(v_base * r.pct / 100.0, 2) END;
    v_reste := v_reste - v_part;
    INSERT INTO analytic_distribution_lines (tenant_id, journal_line_id, plan_id, section_id, percentage, amount)
    VALUES (NEW.tenant_id, NEW.id,
            CASE WHEN r.plan ~ '^[0-9a-f-]{36}$' THEN r.plan::uuid END,
            r.section::uuid, r.pct, v_part);
  END LOOP;

  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.journal_line_materialize_grill() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS zz_journal_line_materialize_grill ON public.journal_lines;
CREATE TRIGGER zz_journal_line_materialize_grill
  AFTER INSERT ON public.journal_lines
  FOR EACH ROW
  WHEN (NEW.analytic_distribution IS NOT NULL)
  EXECUTE FUNCTION public.journal_line_materialize_grill();

-- ------------------------------------------------------------
-- 5. Un brouillon de facture se modifie, d'un seul geste
-- ------------------------------------------------------------
-- Même forme que `create_invoice_atomic` (221) : un appel, un verdict. La fonction
-- s'exécute avec les droits de l'APPELANT : la RLS et `can_perform` s'appliquent,
-- la garde `invoice_guard` aussi (numéro provisoire conservé, totaux tirés des lignes).
CREATE OR REPLACE FUNCTION public.update_invoice_draft(p_invoice_id uuid, p_invoice jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_statut text;
  v_numero text;
  v_set text;
  v_line jsonb;
  v_row jsonb;
  v_cols text;
  v_ordre integer := 0;
  -- ce qu'un brouillon laisse modifier ; le reste (numéro, statut, société, payé) ne se saisit pas
  c_champs constant text[] := ARRAY['customer_id', 'customer_name', 'date', 'due_date', 'notes',
                                    'recurring', 'recurring_frequency', 'project_id'];
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT validation_status, number INTO v_statut, v_numero
  FROM invoices WHERE id = p_invoice_id AND tenant_id = v_tid
  FOR UPDATE;
  IF NOT FOUND THEN
    -- Visible mais non verrouillable : l'appelant lit la facture sans pouvoir l'écrire
    -- (un lecteur, mesuré par le scénario d'écran AN05) — le refus dit pourquoi.
    IF EXISTS (SELECT 1 FROM invoices WHERE id = p_invoice_id AND tenant_id = v_tid) THEN
      RAISE EXCEPTION 'Vous n''avez pas le droit de modifier cette facture';
    END IF;
    RAISE EXCEPTION 'Facture introuvable';
  END IF;
  IF v_statut = 'validated' THEN
    RAISE EXCEPTION 'Facture % validée : elle ne se modifie plus (émettez un avoir)', v_numero;
  END IF;
  IF jsonb_typeof(COALESCE(p_lines, '[]'::jsonb)) <> 'array' OR jsonb_array_length(COALESCE(p_lines, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'Une facture porte au moins une ligne';
  END IF;
  IF EXISTS (SELECT 1 FROM invoice_lines
             WHERE invoice_id = p_invoice_id AND tenant_id = v_tid
               AND (time_entry_id IS NOT NULL OR delivery_note_line_id IS NOT NULL OR sales_order_line_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'Facture % : ses lignes viennent d''un autre document (temps passé, livraison ou commande) — elles se corrigent à leur source', v_numero;
  END IF;

  SELECT string_agg(format('%1$I = r.%1$I', k), ', ') INTO v_set
  FROM jsonb_object_keys(COALESCE(p_invoice, '{}'::jsonb)) k
  WHERE k = ANY (c_champs);
  IF v_set IS NOT NULL THEN
    EXECUTE format('UPDATE invoices i SET %s FROM jsonb_populate_record(NULL::invoices, $1) r WHERE i.id = $2 AND i.tenant_id = $3', v_set)
      USING p_invoice, p_invoice_id, v_tid;
  END IF;

  DELETE FROM invoice_lines WHERE invoice_id = p_invoice_id AND tenant_id = v_tid;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    -- Même règle que `insert_row_from_jsonb` (colonnes reconnues seulement), écrite ici
    -- parce que cette aide n'est pas exécutable par l'appelant — et qu'on veut SES droits.
    v_row := jsonb_strip_nulls(jsonb_build_object('line_order', v_ordre) || v_line
               || jsonb_build_object('invoice_id', p_invoice_id, 'tenant_id', v_tid));
    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a
    WHERE a.attrelid = 'public.invoice_lines'::regclass
      AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = ''
      AND a.attname NOT IN ('id', 'created_at', 'updated_at')
      AND v_row ? a.attname;
    EXECUTE format('INSERT INTO invoice_lines (%s) SELECT %s FROM jsonb_populate_record(NULL::invoice_lines, $1)', v_cols, v_cols)
      USING v_row;
    v_ordre := v_ordre + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'invoice_id', p_invoice_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.update_invoice_draft(uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_invoice_draft(uuid, jsonb, jsonb) TO authenticated;
