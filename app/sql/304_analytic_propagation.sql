-- ============================================================
-- 304_analytic_propagation.sql — W7 (M-05) : l'analytique circule vraiment
--
-- Trois défauts prouvés par `304_analytic_propagation_tests.sql`, vus **rouges
-- avant** ce fichier :
--
--   ANA-01 🟠 Les deux déclencheurs de `journal_lines` étaient **vides** : deux
--             appels de fonction par ligne pour zéro effet. Mesuré : une ligne
--             portant une ventilation à 100 % restait sans section ni montant
--             analytique ; une ventilation à 60 % était acceptée.
--   ANA-02 🔴 `analytic_section_id` n'était écrit que par la **saisie manuelle**
--             (`post_journal_entry`). Les lignes de facture n'avaient même pas
--             de colonne pour porter une section : mesuré, `column
--             "analytic_section_id" of relation "invoice_lines" does not exist`.
--   ANA-03 🟠 La balance analytique (écran) portait sur tout l'historique.
--
-- CE QUI EST POSÉ.
--   1. Une ligne de **document** peut porter une section : `invoice_lines` et
--      `purchase_invoice_lines` reçoivent `analytic_section_id` (clés composites
--      vers `analytic_sections`, `ON DELETE SET NULL`).
--   2. Les deux fonctions de comptabilisation **la transmettent** : les lignes
--      d'écriture de produits (707/70x) et de charges (607/60x) sont regroupées
--      par (compte, section) et portent la section — donc les écritures
--      **générées** par les ventes et les achats, pas seulement les saisies.
--   3. `propagate_analytic_section` fait son travail : quand seul le multi-axes
--      (`journal_lines.analytic_distribution`) est renseigné, la section et le
--      montant analytique de la ligne en sont **dérivés** (la section de plus
--      fort pourcentage, montant = assiette × pourcentage).
--   4. `check_analytic_balance` vérifie la seule chose qui s'appelle « équilibre
--      analytique » : une ventilation donnée doit faire **100 %** par plan. La
--      règle existait déjà côté écran (`validateDistribution`) ; elle est
--      désormais tenue par la base, comme le reste.
--
-- LES LIMITES, DITES.
--   • La paie, le stock, la caisse et la production **ne portent pas encore** de
--     section : aucune de leurs lignes sources n'en porte (ni le salarié, ni
--     l'article, ni le ticket) — il faudra d'abord un porteur dans ces domaines.
--     L'exigence « balance analytique = balance générale » n'est donc satisfaite
--     que pour les ventes et les achats.
--   • Les lignes de TVA ne portent pas de section (elles ne sont ni en classe 6
--     ni en classe 7).
--   • `analytic_distribution_lines` reste écrit par l'écran (il n'est lu par
--     aucune fonction SQL) : la 304 ne le remplit pas.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Le porteur : une section par ligne de document
-- ------------------------------------------------------------
ALTER TABLE public.invoice_lines ADD COLUMN IF NOT EXISTS analytic_section_id uuid;
ALTER TABLE public.purchase_invoice_lines ADD COLUMN IF NOT EXISTS analytic_section_id uuid;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'invoice_lines_analytic_section_fk'
                   AND conrelid = 'public.invoice_lines'::regclass) THEN
    ALTER TABLE public.invoice_lines ADD CONSTRAINT invoice_lines_analytic_section_fk
      FOREIGN KEY (tenant_id, analytic_section_id)
      REFERENCES public.analytic_sections (tenant_id, id) ON DELETE SET NULL (analytic_section_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'purchase_invoice_lines_analytic_section_fk'
                   AND conrelid = 'public.purchase_invoice_lines'::regclass) THEN
    ALTER TABLE public.purchase_invoice_lines ADD CONSTRAINT purchase_invoice_lines_analytic_section_fk
      FOREIGN KEY (tenant_id, analytic_section_id)
      REFERENCES public.analytic_sections (tenant_id, id) ON DELETE SET NULL (analytic_section_id);
  END IF;
END $$;

COMMENT ON COLUMN public.invoice_lines.analytic_section_id IS
  'Section analytique de la ligne de vente : transmise à la ligne d''écriture de produit à la validation. 304 (W7).';
COMMENT ON COLUMN public.purchase_invoice_lines.analytic_section_id IS
  'Section analytique de la ligne d''achat : transmise à la ligne d''écriture de charge à l''approbation. 304 (W7).';

-- ------------------------------------------------------------
-- 2. Les deux déclencheurs cessent d'être des placebos (ANA-01)
-- ------------------------------------------------------------
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
  v_sec uuid;
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
    END IF;
  END IF;

  -- ── 2. La section de la ligne de **document** d'origine ─────────────────
  -- ANA-02 : les écritures engendrées (ventes, achats) naissent d'un document
  -- qui sait à quoi la dépense ou le produit se rattache. La ligne d'écriture
  -- porte le compte ; la ligne de document porte la section : on les apparie par
  -- le numéro du document (`invoice_ref`) et par le compte.
  IF NEW.analytic_section_id IS NULL
     AND COALESCE(NEW.account_code, NEW.account_general) ~ '^[67]' THEN

    SELECT e.invoice_ref, e.reference INTO v_inv_ref, v_ref
    FROM journal_entries e
    WHERE e.id = NEW.journal_id AND e.tenant_id = NEW.tenant_id;

    IF COALESCE(v_inv_ref, v_ref) IS NOT NULL THEN
      -- Ventes : compte de produit de l'article, sinon de sa catégorie, sinon 707000
      SELECT il.analytic_section_id INTO v_sec
      FROM invoices i
      JOIN invoice_lines il ON il.invoice_id = i.id AND il.tenant_id = i.tenant_id
      LEFT JOIN products p ON p.id = il.product_id AND p.tenant_id = i.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = i.tenant_id
      WHERE i.tenant_id = NEW.tenant_id
        AND i.number IN (v_inv_ref, v_ref)
        AND il.analytic_section_id IS NOT NULL
        AND COALESCE(p.sale_account_code, pc.sale_account_code, '707000') = COALESCE(NEW.account_code, NEW.account_general)
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
          AND COALESCE(p.purchase_account_code, pc.purchase_account_code, '607000') = COALESCE(NEW.account_code, NEW.account_general)
        LIMIT 1;
      END IF;

      IF v_sec IS NOT NULL THEN
        NEW.analytic_section_id := v_sec;
        IF NEW.analytic_amount IS NULL OR NEW.analytic_amount = 0 THEN
          NEW.analytic_amount := COALESCE(NULLIF(NEW.debit, 0), NEW.credit, 0);
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.propagate_analytic_section() FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.check_analytic_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_plan text;
  v_somme numeric;
BEGIN
  IF NEW.analytic_distribution IS NULL
     OR jsonb_typeof(NEW.analytic_distribution) <> 'object' THEN
    RETURN NEW;
  END IF;

  -- L'équilibre analytique d'une ligne : chaque plan ventilé fait 100 %.
  -- C'est la règle que l'écran applique déjà (`validateDistribution`, ±0,01).
  FOR v_plan, v_somme IN
    SELECT p.key,
           COALESCE(sum(CASE WHEN (s.value)::text ~ '^-?[0-9]+(\.[0-9]+)?$'
                             THEN (s.value)::numeric ELSE 0 END), 0)
    FROM jsonb_each(NEW.analytic_distribution) p,
         LATERAL jsonb_each(CASE WHEN jsonb_typeof(p.value) = 'object' THEN p.value ELSE '{}'::jsonb END) s
    GROUP BY p.key
  LOOP
    IF abs(v_somme - 100) > 0.01 THEN
      RAISE EXCEPTION 'Ventilation analytique déséquilibrée : le plan % fait % (100 attendus)',
        v_plan, v_somme USING ERRCODE = '23514';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.check_analytic_balance() FROM PUBLIC, anon;

-- Le déclencheur de propagation se branche aussi sur la mise à jour de la
-- ventilation : un écran ou un import peut poser la ventilation après la ligne
-- (l'ancien corps ne se branchait que sur l'INSERT, pour ne rien faire).
DROP TRIGGER IF EXISTS trigger_propagate_analytic ON public.journal_lines;
CREATE TRIGGER trigger_propagate_analytic
  BEFORE INSERT OR UPDATE OF analytic_distribution
  ON public.journal_lines
  FOR EACH ROW EXECUTE FUNCTION public.propagate_analytic_section();

