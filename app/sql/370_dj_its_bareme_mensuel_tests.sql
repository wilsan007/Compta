-- ============================================================
-- 370_dj_its_bareme_mensuel_tests.sql — Djibouti : le barème ITS
--
--   T01  la grille existe, elle est GLOBALE (tenant_id NULL), de type 'its',
--        marquée par défaut, et son file_url pointe le bucket des barèmes ;
--   T02  elle compte exactement 393 lignes, dont 392 en `fixed_amount` ;
--   T03  les tranches SONT BORNÉES et CONSÉCUTIVES : pas de trou entre deux
--        tranches (sinon une assiette n'imposerait rien), pas de recouvrement
--        non plus — sauf les deux lignes extrapolées, qui se recouvrent
--        volontairement (plancher + marginal) ;
--   T04  le barème est bien « en table » : sous 50 000 DJF il n'y a aucune
--        tranche, et la PREMIÈRE tranche vaut ce que dit le fichier source ;
--   T05  REJOUABLE : la fonction de la 370 ne duplique ni la grille ni ses
--        lignes (c'était le défaut du fichier d'origine : `payroll_tax_grids`
--        n'a aucune contrainte d'unicité, donc son `ON CONFLICT DO NOTHING`
--        était un no-op) ;
--   T06  le pack 'DJ' existe, et le bucket `tax-grid-sources` aussi — le lien
--        de la grille ne doit pas être un trou.
--
-- Vu ROUGE avant la 370, sur la base d'aujourd'hui : T01 → T06 (aucune grille
-- DJ : le 370 était un fichier vide de deux lignes). Le moteur, lui, est tenu
-- côté front par `src/lib/__tests__/grid-fixed-amount.test.ts` (6 tests,
-- rouges avant le garde `inFixedBracket`) : une base ne peut pas prouver que le
-- TypeScript lit `min_amount`/`max_amount`, et un TypeScript ne peut pas prouver
-- que les 393 lignes sont bien là. Les deux moitiés sont nécessaires.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '370', false);
DELETE FROM _audit_results WHERE file = '370';

-- ─────────────────────────────────────────────────────────────
-- T01 — la grille existe, globale, par défaut
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v uuid; v_tier text; v_def bool; v_url text; v_stat text;
BEGIN
  SELECT id, coalesce(tenant_id::text, 'GLOBALE'), is_default, file_url, status
    INTO v, v_tier, v_def, v_url, v_stat
  FROM payroll_tax_grids
  WHERE country_code = 'DJ' AND grid_type = 'its' AND source = 'platform';

  PERFORM _rec('T01', 'la grille ITS Djibouti existe, elle est GLOBALE, de type its, par défaut, active, et son file_url est écrit',
    v IS NOT NULL AND v_tier = 'GLOBALE' AND v_def AND v_stat = 'active'
      AND v_url IS NOT NULL AND btrim(v_url) <> '',
    format('trouvée=%s tier=%s défaut=%s statut=%s file_url=%s',
           v IS NOT NULL, v_tier, v_def, v_stat, coalesce(v_url, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'la grille ITS Djibouti existe, elle est GLOBALE, de type its, par défaut, active, et son file_url est écrit', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — 393 lignes, dont 392 en montant fixe
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_n int; v_fix int; v_cat int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE line_type = 'fixed_amount'),
         count(*) FILTER (WHERE category = 'its' AND base_type = 'taxable_gross')
    INTO v_n, v_fix, v_cat
  FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
  WHERE g.country_code = 'DJ' AND g.grid_type = 'its';

  PERFORM _rec('T02', 'la grille compte exactement 393 lignes, dont 392 en montant fixe, toutes en catégorie its sur le salaire imposable',
    v_n = 393 AND v_fix = 392 AND v_cat = 393,
    format('lignes=%s (393 attendues) fixed_amount=%s (392) its/taxable_gross=%s (393)', v_n, v_fix, v_cat));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'la grille compte exactement 393 lignes, dont 392 en montant fixe, toutes en catégorie its sur le salaire imposable', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — les tranches sont bornées, consécutives, sans trou ni recouvrement
--         (les deux lignes extrapolées font exception : elles se recouvrent
--          volontairement, l'une posant un plancher et l'autre un taux)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_trous text; v_couvre text; v_non_bornee int;
BEGIN
  -- Un trou : le haut d'une tranche ne rejoint pas le bas de la suivante.
  SELECT string_agg(format('%s→%s', p.min_amount, p.max_amount), ', ' ORDER BY p.sort_order)
    INTO v_trous
  FROM (SELECT min_amount, max_amount, sort_order,
               lead(min_amount) OVER (ORDER BY sort_order) AS suivant
          FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
         WHERE g.country_code = 'DJ' AND g.grid_type = 'its' AND sort_order < 392) p
  WHERE p.suivant IS NOT NULL AND p.max_amount + 1 <> p.suivant;

  -- Un recouvrement INDÉSIRABLE : deux tranches se chevauchent. La SEULE
  -- superposition admise est 392/393 — le plancher extrapolé et le marginal
  -- extrapolé, faits pour s'additionner au-delà du barème publié (cf. en-tête).
  SELECT string_agg(format('%s et %s', a.sort_order, b.sort_order), ', ' ORDER BY a.sort_order)
    INTO v_couvre
  FROM (SELECT l.* FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
         WHERE g.country_code = 'DJ' AND g.grid_type = 'its') a
  JOIN (SELECT l.* FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
         WHERE g.country_code = 'DJ' AND g.grid_type = 'its') b
    ON a.grid_id = b.grid_id AND a.sort_order < b.sort_order
   AND NOT (a.sort_order = 392 AND b.sort_order = 393)
   AND a.min_amount <= coalesce(b.max_amount, a.min_amount)
   AND b.min_amount <= coalesce(a.max_amount, b.min_amount);

  -- Une tranche officielle sans borne haute additionnerait tout ce qui suit.
  SELECT count(*) INTO v_non_bornee
  FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
  WHERE g.country_code = 'DJ' AND g.grid_type = 'its'
    AND l.max_amount IS NULL AND l.sort_order < 392;

  PERFORM _rec('T03', 'les tranches sont consécutives : aucun trou, aucun recouvrement indesirable, et toute tranche officielle est bornée vers le haut',
    v_trous IS NULL AND v_couvre IS NULL AND v_non_bornee = 0,
    format('trous=%s recouvrements=%s non bornees=%s',
           coalesce(v_trous, 'aucun'), coalesce(v_couvre, 'aucun'), v_non_bornee));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'les tranches sont consécutives : aucun trou, aucun recouvrement indesirable, et toute tranche officielle est bornée vers le haut', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — la forme « en table » : rien sous 50 000, et la première tranche
--         vaut bien 3 650 (source : « salaires janvier 2026-1.xlsx »)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_min numeric; v_m1 numeric; v_mont numeric; v_sous int; v_au int;
BEGIN
  SELECT min(min_amount) INTO v_min
  FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
  WHERE g.country_code = 'DJ' AND g.grid_type = 'its';

  SELECT fixed_amount, min_amount INTO v_mont, v_m1
  FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
  WHERE g.country_code = 'DJ' AND g.grid_type = 'its' AND line_type = 'fixed_amount'
  ORDER BY sort_order LIMIT 1;

  -- Combien de tranches s'appliquent à 49 000 (sous l'exonération), puis à 60 000 ?
  SELECT count(*) INTO v_sous FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
   WHERE g.country_code = 'DJ' AND g.grid_type = 'its'
     AND 49000 BETWEEN l.min_amount AND coalesce(l.max_amount, l.min_amount);
  SELECT count(*) INTO v_au FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
   WHERE g.country_code = 'DJ' AND g.grid_type = 'its'
     AND 60000 BETWEEN l.min_amount AND coalesce(l.max_amount, l.min_amount);

  PERFORM _rec('T04', 'la grille est bien en table : la première tranche commence à 50 000 pour 3 650 DJF, 49 000 ne tombe dans aucune tranche et 60 000 dans une seule',
    v_min = 50000 AND v_mont = 3650 AND v_m1 = 50000 AND v_sous = 0 AND v_au = 1,
    format('début=%s montant première tranche=%s | 49 000 → %s tranche(s) | 60 000 → %s tranche(s)',
           v_min, v_mont, v_sous, v_au));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'la grille est bien en table : la première tranche commence à 50 000 pour 3 650 DJF, 49 000 ne tombe dans aucune tranche et 60 000 dans une seule', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — REJOUABLE : un second appel ne duplique ni la grille ni ses lignes
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_avant int; v_lignes_avant int; v_apres int; v_lignes_apres int; v_id1 uuid; v_id2 uuid;
BEGIN
  SELECT count(*) INTO v_avant FROM payroll_tax_grids WHERE country_code = 'DJ' AND grid_type = 'its';
  SELECT count(*) INTO v_lignes_avant
  FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
  WHERE g.country_code = 'DJ' AND g.grid_type = 'its';
  SELECT id INTO v_id1 FROM payroll_tax_grids WHERE country_code = 'DJ' AND grid_type = 'its';

  -- Le corps de la 370, rejoué : il doit rendre la MÊME grille.
  PERFORM public.dj_its_2026_grid();

  SELECT count(*) INTO v_apres FROM payroll_tax_grids WHERE country_code = 'DJ' AND grid_type = 'its';
  SELECT count(*) INTO v_lignes_apres
  FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
  WHERE g.country_code = 'DJ' AND g.grid_type = 'its';
  SELECT id INTO v_id2 FROM payroll_tax_grids WHERE country_code = 'DJ' AND grid_type = 'its';

  PERFORM _rec('T05', 'rejouable : un second passage rend la MÊME grille et ne duplique aucune ligne (le ON CONFLICT du fichier d''origine était un no-op)',
    v_avant = 1 AND v_apres = 1 AND v_lignes_avant = v_lignes_apres AND v_id1 = v_id2,
    format('grilles %s→%s | lignes %s→%s | même identique=%s',
           v_avant, v_apres, v_lignes_avant, v_lignes_apres, v_id1 = v_id2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'rejouable : un second passage rend la MÊME grille et ne duplique aucune ligne (le ON CONFLICT du fichier d''origine était un no-op)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — le pack DJ et le bucket des barèmes : le lien de la grille
--         ne doit pas pointer dans le vide
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_pack int; v_bucket int; v_pol int;
BEGIN
  SELECT count(*) INTO v_pack FROM legislation_packs WHERE code = 'DJ' AND active;
  SELECT count(*) INTO v_bucket FROM storage.buckets WHERE id = 'tax-grid-sources';
  -- `pg_policies` expose `policyname` (la colonne `polname` appartient à pg_policy).
  SELECT count(*) INTO v_pol FROM pg_policies
   WHERE policyname IN ('authenticated_read_tax_grid_sources','admin_insert_tax_grid_sources',
                        'admin_update_tax_grid_sources','admin_delete_tax_grid_sources');

  PERFORM _rec('T06', 'le pack DJ est actif, le bucket tax-grid-sources existe (le file_url de la grille y pointe) et ses 4 politiques aussi',
    v_pack >= 1 AND v_bucket = 1 AND v_pol = 4,
    format('pack DJ=%s bucket=%s politiques=%s (4 attendues)', v_pack, v_bucket, v_pol));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'le pack DJ est actif, le bucket tax-grid-sources existe (le file_url de la grille y pointe) et ses 4 politiques aussi', false, SQLERRM);
END $$;

SELECT _audit_assert('370');