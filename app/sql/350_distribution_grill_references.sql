-- ════════════════════════════════════════════════════════════════════════════
-- 350 — Partie 2, tâche 2.13 (G2, pil-007) : une grille de ventilation
--       désigne un compte du plan et des sections qui existent
-- ════════════════════════════════════════════════════════════════════════════
--
-- LE DÉFAUT, MESURÉ (suite 350). Le compte d'une grille (`account_code`) et la
-- section de chacune de ses lignes (`section_code`) étaient du TEXTE LIBRE :
-- une grille sur le compte « 706999 » (inexistant) ventilant vers la section
-- « ZZZ99 » (inexistante) s'enregistrait. Elle ne ventilait jamais rien, sans
-- le dire.
--
-- CE QUE FAIT CE FICHIER. Deux clés étrangères COMPOSITES (société comprise,
-- doctrine ISO-02) : le compte vers `chart_accounts (tenant_id, code)`, la
-- section vers `analytic_sections (tenant_id, code)`. Renommer un compte ou une
-- section suit (ON UPDATE CASCADE) ; les supprimer est refusé tant qu'une
-- grille les désigne.
--
-- Rattrapage : les clés sont posées pour les écritures NOUVELLES. Si des
-- grilles existantes désignent un compte ou une section introuvables, elles ne
-- sont pas modifiées et leur nombre est dit.
-- ════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.distribution_grills DROP CONSTRAINT IF EXISTS distribution_grills_account_fkey;
ALTER TABLE public.distribution_grills ADD CONSTRAINT distribution_grills_account_fkey
  FOREIGN KEY (tenant_id, account_code) REFERENCES public.chart_accounts (tenant_id, code)
  ON UPDATE CASCADE ON DELETE RESTRICT NOT VALID;

ALTER TABLE public.distribution_grill_lines DROP CONSTRAINT IF EXISTS distribution_grill_lines_section_fkey;
ALTER TABLE public.distribution_grill_lines ADD CONSTRAINT distribution_grill_lines_section_fkey
  FOREIGN KEY (tenant_id, section_code) REFERENCES public.analytic_sections (tenant_id, code)
  ON UPDATE CASCADE ON DELETE RESTRICT NOT VALID;

DO $$
DECLARE n_g int; n_l int;
BEGIN
  SELECT count(*) INTO n_g FROM public.distribution_grills g
   WHERE NOT EXISTS (SELECT 1 FROM public.chart_accounts c WHERE c.tenant_id = g.tenant_id AND c.code = g.account_code);
  SELECT count(*) INTO n_l FROM public.distribution_grill_lines l
   WHERE NOT EXISTS (SELECT 1 FROM public.analytic_sections s WHERE s.tenant_id = l.tenant_id AND s.code = l.section_code);
  IF n_g = 0 THEN
    ALTER TABLE public.distribution_grills VALIDATE CONSTRAINT distribution_grills_account_fkey;
  END IF;
  IF n_l = 0 THEN
    ALTER TABLE public.distribution_grill_lines VALIDATE CONSTRAINT distribution_grill_lines_section_fkey;
  END IF;
  IF n_g > 0 OR n_l > 0 THEN
    RAISE NOTICE '350 : % grille(s) sur un compte introuvable, % ligne(s) vers une section introuvable — non modifiées, à reprendre', n_g, n_l;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_distribution_grills_tenant_account ON public.distribution_grills (tenant_id, account_code);
CREATE INDEX IF NOT EXISTS ix_distribution_grill_lines_tenant_section ON public.distribution_grill_lines (tenant_id, section_code);
