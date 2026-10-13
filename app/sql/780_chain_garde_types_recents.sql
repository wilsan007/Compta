-- ═══════════════════════════════════════════════════════════════════════════
-- 457 — Partie 5 : la garde de suppression des types inscrits APRÈS la 453
-- ═══════════════════════════════════════════════════════════════════════════
--
-- La 453 pose la garde EN BOUCLE sur `chain_document_types` : elle ne peut couvrir
-- que les types INSCRITS AVANT ELLE. Or la règle de la 450 dit que « tout nouveau
-- maillon qui emploie un type absent d'ici l'inscrit DANS LA MÊME MIGRATION, et pose
-- la garde de suppression (453) sur sa table » — et les lots suivants ont bien inscrit
-- leurs types, mais sans pouvoir rejouer la boucle.
--
-- MESURÉ (base neuve, avant cette migration) : **37 types** au registre, **32 gardes**
-- posées (les 27 types d'origine + leurs 5 tables de lignes). Dix types inscrits par
-- les lots fusionnés — `quotes`, `projects`, `payment_orders`, `mrp_proposals`,
-- `purchase_orders`, `purchase_credit_notes`, `collection_reminders`, `lettrage_groups`,
-- `pay_slips`, `fiscal_years` — n'avaient donc AUCUNE garde de suppression, et la suite
-- 450 (T11) le mesurait : une commande d'achat ou une proposition MRP reliée se
-- supprimait en laissant ses liens actifs derrière elle.
--
-- Cette migration REJOUE la boucle de la 453 (idempotente : `DROP TRIGGER IF EXISTS`
-- puis `CREATE`), puis VÉRIFIE que le registre et les gardes disent la même chose :
-- une omission future échoue ICI, à l'application, et pas seulement dans une suite.
--
-- Après : **45 gardes** (37 types + 8 tables de lignes).
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT code, table_name, ligne_table FROM public.chain_document_types ORDER BY code LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS zz_garde_p5_suppression ON public.%I', r.table_name);
    EXECUTE format('CREATE TRIGGER zz_garde_p5_suppression BEFORE DELETE ON public.%I '
                   'FOR EACH ROW EXECUTE FUNCTION public.chain_refuser_suppression_liee(%L, %L)',
                   r.table_name, r.code, 'document');
    IF r.ligne_table IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS zz_garde_p5_suppression_ligne ON public.%I', r.ligne_table);
      EXECUTE format('CREATE TRIGGER zz_garde_p5_suppression_ligne BEFORE DELETE ON public.%I '
                     'FOR EACH ROW EXECUTE FUNCTION public.chain_refuser_suppression_liee(%L, %L)',
                     r.ligne_table, r.code, 'ligne');
    END IF;
  END LOOP;
END $$;

-- Le contrôle de cohérence : registre = gardes. Ni table oubliée, ni garde orpheline.
DO $$
DECLARE v_sans_garde text; v_types int; v_lignes int; v_gardes int; v_attendues int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE ligne_table IS NOT NULL)
    INTO v_types, v_lignes FROM public.chain_document_types;
  v_attendues := v_types + v_lignes;

  SELECT count(*) INTO v_gardes FROM pg_trigger WHERE tgname LIKE 'zz_garde_p5_suppression%';

  SELECT string_agg(x.tbl, ', ' ORDER BY x.tbl) INTO v_sans_garde
  FROM public.chain_document_types t
  CROSS JOIN LATERAL (VALUES (t.table_name, 'zz_garde_p5_suppression'),
                             (t.ligne_table, 'zz_garde_p5_suppression_ligne')) x(tbl, trig)
  WHERE x.tbl IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM pg_trigger g
                     WHERE g.tgrelid = to_regclass('public.' || x.tbl)
                       AND g.tgname = x.trig AND g.tgenabled <> 'D');

  IF v_sans_garde IS NOT NULL THEN
    RAISE EXCEPTION '457 : table(s) du registre sans garde de suppression : %. Tout type inscrit doit porter sa garde (règle de la 450).', v_sans_garde;
  END IF;

  IF v_gardes <> v_attendues THEN
    RAISE EXCEPTION '457 : % garde(s) posée(s) pour % attendue(s) (% types + % tables de lignes). Le registre et les gardes doivent dire la même chose.',
      v_gardes, v_attendues, v_types, v_lignes;
  END IF;
END $$;
