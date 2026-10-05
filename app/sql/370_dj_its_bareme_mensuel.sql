-- ═══════════════════════════════════════════════════════════════════════════
-- 370 — Djibouti : le barème mensuel de l'I.T.S. (grille de paie « en table »)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. L'Impôt sur les Traitements et Salaires de Djibouti n'est pas une
-- formule à taux marginal : c'est une TABLE DE CORRESPONDANCE — « si le salaire
-- imposable tombe entre min_amount et max_amount, l'impôt vaut fixed_amount ».
-- 391 tranches de 5 000 DJF, exonération sous 50 000 DJF, extraites de
-- « salaires janvier 2026-1.xlsx », onglet « Barème ITS ».
--
-- D'OÙ VIENT CE FICHIER. Il est porté de la branche
-- `claude/extract-tax-salary-table-2a3267`, où il s'appelait
-- `65_seed_dj_its_payroll_grid.sql`. Le numéro 65 est IMPOSSIBLE ici : dans
-- `main`, 65 est déjà `65_project_management.sql` — les deux fichiers se
-- percuteraient, et la porte SOC-06 refuse un numéro qui porte deux noms. Le
-- numéro 370 avait été pris pour lui par `migration-numero.mjs` (ligne « lot K
-- (localisation Djibouti) ») ; c'est ce fichier-là qui était resté vide. Les 393
-- lignes de données sont reprises VERBATIM de la branche, extraites par script —
-- jamais recopiées à la main.
--
-- LE MOTEUR AVAIT BESOIN D'ÊTRE CORRIGÉ AVANT. La migration est triviale ; ce qui
-- manquait était le LECTEUR. Une grille « en table » n'a de sens que si le montant
-- ne s'applique QUE dans sa tranche — et le moteur ne le testait pas :
-- `payroll.ts` et `taxCalculator.ts` lisaient `line.fixed_amount` sans regarder
-- `min_amount`/`max_amount`, alors que `bracket` et `percentage` les testaient.
-- MESURÉ le 04/10 sur trois tranches (3 650 / 4 400 / 5 150 DJF) : TOUT salaire
-- imposait 13 200 DJF, y compris un salaire SOUS la première tranche ; sur les
-- lignes extrapolées, 1 643 050 au lieu de 1 045 400. Sur les 393 lignes réelles,
-- l'ITS était LA SOMME des montants. Le garde s'appelle `inFixedBracket`
-- (payroll.ts) ; il est tenu par `src/lib/__tests__/grid-fixed-amount.test.ts`,
-- écrit pour être ROUGE avant le correctif.
--
-- REJOUABLE. `payroll_tax_grids` ne porte AUCUNE contrainte d'unicité : le
-- `ON CONFLICT DO NOTHING` du fichier d'origine était donc un no-op — un second
-- passage créait une seconde grille et doublait les 393 lignes. Le motif retenu
-- est celui de la 276 (France) : la fonction `pg_temp` rend l'identifiant de la
-- grille et n'écrit QUE si elle n'existe pas.
--
-- LE PACK DJ N'EST PAS RÉPÉTÉ ICI. La 201 (`201_chart_by_country.sql`) crée déjà
-- `legislation_packs` 'DJ'. Le bloc ci-dessous ne l'insère que s'il MANQUE (une
-- base modernisée avant la 201), avec la même règle de rattachement que la 201.
--
-- ⚠️ LIMITE À LEVER D'UN SCEAU. Les deux dernières lignes sont une
-- EXTRAPOLATION, signalée comme telle dans leur libellé : le fichier source
-- s'arrête à 2 004 999 DJF. Elles se recouvrent DÉLIBÉRÉMENT — l'une (392) pose
-- un plancher de 597 650, l'autre (393) un taux marginal de 45 % sur l'excédent
-- au-delà de 2 005 000 — et n'ont de sens qu'ENSEMBLE. À faire valider auprès de
-- la DGI avant tout usage sur un salaire réel dépassant ce seuil.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le pack de législation, seulement s'il manque ───────────────────────────
-- Même règle de rattachement que la 201 : un pack global appartient à la société
-- technique du pack FR, pas à « personne ».
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM legislation_packs WHERE code = 'DJ') THEN
    INSERT INTO legislation_packs (code, name, country_code, country_name, accounting_standard,
      currency, currency_decimals, date_format, locale, fiscal_year_start,
      tax_id_label, tax_id_secondary_label, is_default, active, tenant_id)
    SELECT 'DJ', 'Djibouti — Plan Comptable', 'DJ', 'Djibouti', 'PCG', 'DJF', 0,
           'DD/MM/YYYY', 'fr-DJ', '01-01', 'N° NIF', 'RCCM', false, true,
           (SELECT tenant_id FROM legislation_packs WHERE code = 'FR');
    RAISE NOTICE '370 : pack DJ créé (il était absent de la base).';
  END IF;
END $$;

-- ── 2. La grille et ses 393 lignes — REJOUABLE (motif 276) ────────────────────
-- La fonction est PERMANENTE (`public`), pas `pg_temp` : une fonction `pg_temp`
-- disparaît à la fin de la session psql, donc la suite 370 — jouée dans une AUTRE
-- connexion par la CI — ne pourrait pas la rappeler pour prouver la rejouabilité,
-- et personne ne pourrait réamorcer la grille sur une base de reprise.
CREATE OR REPLACE FUNCTION public.dj_its_2026_grid()
RETURNS uuid LANGUAGE plpgsql AS $fn$
-- Les 393 lignes de données nomment la variable `g`. Elles venaient de la branche
-- sous le nom `v_grid_id`, et PostgreSQL échouait alors sur « column v_grid_id does
-- not exist » (MESURÉ le 04/10 sur PostgreSQL 17) : le nom de la variable EST la
-- donnée. Le nom court est donc ici un choix, pas un raccourci.
DECLARE
  g uuid;
BEGIN
  SELECT id INTO g
  FROM payroll_tax_grids
  WHERE tenant_id IS NULL AND country_code = 'DJ'
    AND grid_type = 'its' AND source = 'platform';
  IF g IS NOT NULL THEN
    RAISE NOTICE '370 : grille ITS Djibouti déjà présente (%), rien n''est réécrit.', g;
    RETURN g;                     -- rejouable : un second passage rend la MÊME grille
  END IF;

  INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description,
                                 status, source, is_default, effective_from, file_url)
  VALUES (NULL, 'DJ', 'its',
          'Grille ITS Djibouti - Barème mensuel',
          'Impôt sur les Traitements et Salaires — barème mensuel officiel (tranches de 5 000 DJF), '
          'extrait de « salaires janvier 2026-1.xlsx » (onglet « Barème ITS »), exonération sous 50 000 DJF. '
          'Grille EN TABLE : chaque ligne porte le montant dû quand le salaire imposable tombe dans sa tranche. '
          'Les deux dernières lignes sont une EXTRAPOLATION non officielle, à valider auprès de la DGI.',
          'active', 'platform', TRUE, '2026-01-01',
          'tax-grid-sources/dj/its-bareme-2026-01.xlsx')
  RETURNING id INTO g;
INSERT INTO payroll_tax_grid_lines
    (grid_id, line_type, category, label, base_type, min_amount, max_amount,
     rate_employee, rate_employer, cap_amount, fixed_amount, sort_order)
  VALUES
    (g, 'fixed_amount', 'its', 'Tranche 50000 - 54999 DJF', 'taxable_gross', 50000, 54999, 0, 0, NULL, 3650, 1),
    (g, 'fixed_amount', 'its', 'Tranche 55000 - 59999 DJF', 'taxable_gross', 55000, 59999, 0, 0, NULL, 4400, 2),
    (g, 'fixed_amount', 'its', 'Tranche 60000 - 64999 DJF', 'taxable_gross', 60000, 64999, 0, 0, NULL, 5150, 3),
    (g, 'fixed_amount', 'its', 'Tranche 65000 - 69999 DJF', 'taxable_gross', 65000, 69999, 0, 0, NULL, 5900, 4),
    (g, 'fixed_amount', 'its', 'Tranche 70000 - 74999 DJF', 'taxable_gross', 70000, 74999, 0, 0, NULL, 6650, 5),
    (g, 'fixed_amount', 'its', 'Tranche 75000 - 79999 DJF', 'taxable_gross', 75000, 79999, 0, 0, NULL, 7400, 6),
    (g, 'fixed_amount', 'its', 'Tranche 80000 - 84999 DJF', 'taxable_gross', 80000, 84999, 0, 0, NULL, 8150, 7),
    (g, 'fixed_amount', 'its', 'Tranche 85000 - 89999 DJF', 'taxable_gross', 85000, 89999, 0, 0, NULL, 8900, 8),
    (g, 'fixed_amount', 'its', 'Tranche 90000 - 94999 DJF', 'taxable_gross', 90000, 94999, 0, 0, NULL, 9650, 9),
    (g, 'fixed_amount', 'its', 'Tranche 95000 - 99999 DJF', 'taxable_gross', 95000, 99999, 0, 0, NULL, 10400, 10),
    (g, 'fixed_amount', 'its', 'Tranche 100000 - 104999 DJF', 'taxable_gross', 100000, 104999, 0, 0, NULL, 11150, 11),
    (g, 'fixed_amount', 'its', 'Tranche 105000 - 109999 DJF', 'taxable_gross', 105000, 109999, 0, 0, NULL, 11900, 12),
    (g, 'fixed_amount', 'its', 'Tranche 110000 - 114999 DJF', 'taxable_gross', 110000, 114999, 0, 0, NULL, 12650, 13),
    (g, 'fixed_amount', 'its', 'Tranche 115000 - 119999 DJF', 'taxable_gross', 115000, 119999, 0, 0, NULL, 13400, 14),
    (g, 'fixed_amount', 'its', 'Tranche 120000 - 124999 DJF', 'taxable_gross', 120000, 124999, 0, 0, NULL, 14150, 15),
    (g, 'fixed_amount', 'its', 'Tranche 125000 - 129999 DJF', 'taxable_gross', 125000, 129999, 0, 0, NULL, 14900, 16),
    (g, 'fixed_amount', 'its', 'Tranche 130000 - 134999 DJF', 'taxable_gross', 130000, 134999, 0, 0, NULL, 15650, 17),
    (g, 'fixed_amount', 'its', 'Tranche 135000 - 139999 DJF', 'taxable_gross', 135000, 139999, 0, 0, NULL, 16400, 18),
    (g, 'fixed_amount', 'its', 'Tranche 140000 - 144999 DJF', 'taxable_gross', 140000, 144999, 0, 0, NULL, 17150, 19),
    (g, 'fixed_amount', 'its', 'Tranche 145000 - 149999 DJF', 'taxable_gross', 145000, 149999, 0, 0, NULL, 17900, 20),
    (g, 'fixed_amount', 'its', 'Tranche 150000 - 154999 DJF', 'taxable_gross', 150000, 154999, 0, 0, NULL, 19000, 21),
    (g, 'fixed_amount', 'its', 'Tranche 155000 - 159999 DJF', 'taxable_gross', 155000, 159999, 0, 0, NULL, 20100, 22),
    (g, 'fixed_amount', 'its', 'Tranche 160000 - 164999 DJF', 'taxable_gross', 160000, 164999, 0, 0, NULL, 21200, 23),
    (g, 'fixed_amount', 'its', 'Tranche 165000 - 169999 DJF', 'taxable_gross', 165000, 169999, 0, 0, NULL, 22300, 24),
    (g, 'fixed_amount', 'its', 'Tranche 170000 - 174999 DJF', 'taxable_gross', 170000, 174999, 0, 0, NULL, 23400, 25),
    (g, 'fixed_amount', 'its', 'Tranche 175000 - 179999 DJF', 'taxable_gross', 175000, 179999, 0, 0, NULL, 24500, 26),
    (g, 'fixed_amount', 'its', 'Tranche 180000 - 184999 DJF', 'taxable_gross', 180000, 184999, 0, 0, NULL, 25600, 27),
    (g, 'fixed_amount', 'its', 'Tranche 185000 - 189999 DJF', 'taxable_gross', 185000, 189999, 0, 0, NULL, 26700, 28),
    (g, 'fixed_amount', 'its', 'Tranche 190000 - 194999 DJF', 'taxable_gross', 190000, 194999, 0, 0, NULL, 27800, 29),
    (g, 'fixed_amount', 'its', 'Tranche 195000 - 199999 DJF', 'taxable_gross', 195000, 199999, 0, 0, NULL, 28900, 30),
    (g, 'fixed_amount', 'its', 'Tranche 200000 - 204999 DJF', 'taxable_gross', 200000, 204999, 0, 0, NULL, 30000, 31),
    (g, 'fixed_amount', 'its', 'Tranche 205000 - 209999 DJF', 'taxable_gross', 205000, 209999, 0, 0, NULL, 31100, 32),
    (g, 'fixed_amount', 'its', 'Tranche 210000 - 214999 DJF', 'taxable_gross', 210000, 214999, 0, 0, NULL, 32200, 33),
    (g, 'fixed_amount', 'its', 'Tranche 215000 - 219999 DJF', 'taxable_gross', 215000, 219999, 0, 0, NULL, 33300, 34),
    (g, 'fixed_amount', 'its', 'Tranche 220000 - 224999 DJF', 'taxable_gross', 220000, 224999, 0, 0, NULL, 34400, 35),
    (g, 'fixed_amount', 'its', 'Tranche 225000 - 229999 DJF', 'taxable_gross', 225000, 229999, 0, 0, NULL, 35500, 36),
    (g, 'fixed_amount', 'its', 'Tranche 230000 - 234999 DJF', 'taxable_gross', 230000, 234999, 0, 0, NULL, 36600, 37),
    (g, 'fixed_amount', 'its', 'Tranche 235000 - 239999 DJF', 'taxable_gross', 235000, 239999, 0, 0, NULL, 37700, 38),
    (g, 'fixed_amount', 'its', 'Tranche 240000 - 244999 DJF', 'taxable_gross', 240000, 244999, 0, 0, NULL, 38800, 39),
    (g, 'fixed_amount', 'its', 'Tranche 245000 - 249999 DJF', 'taxable_gross', 245000, 249999, 0, 0, NULL, 39900, 40),
    (g, 'fixed_amount', 'its', 'Tranche 250000 - 254999 DJF', 'taxable_gross', 250000, 254999, 0, 0, NULL, 41000, 41),
    (g, 'fixed_amount', 'its', 'Tranche 255000 - 259999 DJF', 'taxable_gross', 255000, 259999, 0, 0, NULL, 42100, 42),
    (g, 'fixed_amount', 'its', 'Tranche 260000 - 264999 DJF', 'taxable_gross', 260000, 264999, 0, 0, NULL, 43200, 43),
    (g, 'fixed_amount', 'its', 'Tranche 265000 - 269999 DJF', 'taxable_gross', 265000, 269999, 0, 0, NULL, 44300, 44),
    (g, 'fixed_amount', 'its', 'Tranche 270000 - 274999 DJF', 'taxable_gross', 270000, 274999, 0, 0, NULL, 45400, 45),
    (g, 'fixed_amount', 'its', 'Tranche 275000 - 279999 DJF', 'taxable_gross', 275000, 279999, 0, 0, NULL, 46500, 46),
    (g, 'fixed_amount', 'its', 'Tranche 280000 - 284999 DJF', 'taxable_gross', 280000, 284999, 0, 0, NULL, 47600, 47),
    (g, 'fixed_amount', 'its', 'Tranche 285000 - 289999 DJF', 'taxable_gross', 285000, 289999, 0, 0, NULL, 48700, 48),
    (g, 'fixed_amount', 'its', 'Tranche 290000 - 294999 DJF', 'taxable_gross', 290000, 294999, 0, 0, NULL, 49800, 49),
    (g, 'fixed_amount', 'its', 'Tranche 295000 - 299999 DJF', 'taxable_gross', 295000, 299999, 0, 0, NULL, 50900, 50),
    (g, 'fixed_amount', 'its', 'Tranche 300000 - 304999 DJF', 'taxable_gross', 300000, 304999, 0, 0, NULL, 52150, 51),
    (g, 'fixed_amount', 'its', 'Tranche 305000 - 309999 DJF', 'taxable_gross', 305000, 309999, 0, 0, NULL, 53400, 52),
    (g, 'fixed_amount', 'its', 'Tranche 310000 - 314999 DJF', 'taxable_gross', 310000, 314999, 0, 0, NULL, 54650, 53),
    (g, 'fixed_amount', 'its', 'Tranche 315000 - 319999 DJF', 'taxable_gross', 315000, 319999, 0, 0, NULL, 55900, 54),
    (g, 'fixed_amount', 'its', 'Tranche 320000 - 324999 DJF', 'taxable_gross', 320000, 324999, 0, 0, NULL, 57150, 55),
    (g, 'fixed_amount', 'its', 'Tranche 325000 - 329999 DJF', 'taxable_gross', 325000, 329999, 0, 0, NULL, 58400, 56),
    (g, 'fixed_amount', 'its', 'Tranche 330000 - 334999 DJF', 'taxable_gross', 330000, 334999, 0, 0, NULL, 59650, 57),
    (g, 'fixed_amount', 'its', 'Tranche 335000 - 339999 DJF', 'taxable_gross', 335000, 339999, 0, 0, NULL, 60900, 58),
    (g, 'fixed_amount', 'its', 'Tranche 340000 - 344999 DJF', 'taxable_gross', 340000, 344999, 0, 0, NULL, 62150, 59),
    (g, 'fixed_amount', 'its', 'Tranche 345000 - 349999 DJF', 'taxable_gross', 345000, 349999, 0, 0, NULL, 63400, 60),
    (g, 'fixed_amount', 'its', 'Tranche 350000 - 354999 DJF', 'taxable_gross', 350000, 354999, 0, 0, NULL, 64650, 61),
    (g, 'fixed_amount', 'its', 'Tranche 355000 - 359999 DJF', 'taxable_gross', 355000, 359999, 0, 0, NULL, 65900, 62),
    (g, 'fixed_amount', 'its', 'Tranche 360000 - 364999 DJF', 'taxable_gross', 360000, 364999, 0, 0, NULL, 67150, 63),
    (g, 'fixed_amount', 'its', 'Tranche 365000 - 369999 DJF', 'taxable_gross', 365000, 369999, 0, 0, NULL, 68400, 64),
    (g, 'fixed_amount', 'its', 'Tranche 370000 - 374999 DJF', 'taxable_gross', 370000, 374999, 0, 0, NULL, 69650, 65),
    (g, 'fixed_amount', 'its', 'Tranche 375000 - 379999 DJF', 'taxable_gross', 375000, 379999, 0, 0, NULL, 70900, 66),
    (g, 'fixed_amount', 'its', 'Tranche 380000 - 384999 DJF', 'taxable_gross', 380000, 384999, 0, 0, NULL, 72150, 67),
    (g, 'fixed_amount', 'its', 'Tranche 385000 - 389999 DJF', 'taxable_gross', 385000, 389999, 0, 0, NULL, 73400, 68),
    (g, 'fixed_amount', 'its', 'Tranche 390000 - 394999 DJF', 'taxable_gross', 390000, 394999, 0, 0, NULL, 74650, 69),
    (g, 'fixed_amount', 'its', 'Tranche 395000 - 399999 DJF', 'taxable_gross', 395000, 399999, 0, 0, NULL, 75900, 70),
    (g, 'fixed_amount', 'its', 'Tranche 400000 - 404999 DJF', 'taxable_gross', 400000, 404999, 0, 0, NULL, 77150, 71),
    (g, 'fixed_amount', 'its', 'Tranche 405000 - 409999 DJF', 'taxable_gross', 405000, 409999, 0, 0, NULL, 78400, 72),
    (g, 'fixed_amount', 'its', 'Tranche 410000 - 414999 DJF', 'taxable_gross', 410000, 414999, 0, 0, NULL, 79650, 73),
    (g, 'fixed_amount', 'its', 'Tranche 415000 - 419999 DJF', 'taxable_gross', 415000, 419999, 0, 0, NULL, 80900, 74),
    (g, 'fixed_amount', 'its', 'Tranche 420000 - 424999 DJF', 'taxable_gross', 420000, 424999, 0, 0, NULL, 82150, 75),
    (g, 'fixed_amount', 'its', 'Tranche 425000 - 429999 DJF', 'taxable_gross', 425000, 429999, 0, 0, NULL, 83400, 76),
    (g, 'fixed_amount', 'its', 'Tranche 430000 - 434999 DJF', 'taxable_gross', 430000, 434999, 0, 0, NULL, 84650, 77),
    (g, 'fixed_amount', 'its', 'Tranche 435000 - 439999 DJF', 'taxable_gross', 435000, 439999, 0, 0, NULL, 85900, 78),
    (g, 'fixed_amount', 'its', 'Tranche 440000 - 444999 DJF', 'taxable_gross', 440000, 444999, 0, 0, NULL, 87150, 79),
    (g, 'fixed_amount', 'its', 'Tranche 445000 - 449999 DJF', 'taxable_gross', 445000, 449999, 0, 0, NULL, 88400, 80),
    (g, 'fixed_amount', 'its', 'Tranche 450000 - 454999 DJF', 'taxable_gross', 450000, 454999, 0, 0, NULL, 89650, 81),
    (g, 'fixed_amount', 'its', 'Tranche 455000 - 459999 DJF', 'taxable_gross', 455000, 459999, 0, 0, NULL, 90900, 82),
    (g, 'fixed_amount', 'its', 'Tranche 460000 - 464999 DJF', 'taxable_gross', 460000, 464999, 0, 0, NULL, 92150, 83),
    (g, 'fixed_amount', 'its', 'Tranche 465000 - 469999 DJF', 'taxable_gross', 465000, 469999, 0, 0, NULL, 93400, 84),
    (g, 'fixed_amount', 'its', 'Tranche 470000 - 474999 DJF', 'taxable_gross', 470000, 474999, 0, 0, NULL, 94650, 85),
    (g, 'fixed_amount', 'its', 'Tranche 475000 - 479999 DJF', 'taxable_gross', 475000, 479999, 0, 0, NULL, 95900, 86),
    (g, 'fixed_amount', 'its', 'Tranche 480000 - 484999 DJF', 'taxable_gross', 480000, 484999, 0, 0, NULL, 97150, 87),
    (g, 'fixed_amount', 'its', 'Tranche 485000 - 489999 DJF', 'taxable_gross', 485000, 489999, 0, 0, NULL, 98400, 88),
    (g, 'fixed_amount', 'its', 'Tranche 490000 - 494999 DJF', 'taxable_gross', 490000, 494999, 0, 0, NULL, 99650, 89),
    (g, 'fixed_amount', 'its', 'Tranche 495000 - 499999 DJF', 'taxable_gross', 495000, 499999, 0, 0, NULL, 100900, 90),
    (g, 'fixed_amount', 'its', 'Tranche 500000 - 504999 DJF', 'taxable_gross', 500000, 504999, 0, 0, NULL, 102150, 91),
    (g, 'fixed_amount', 'its', 'Tranche 505000 - 509999 DJF', 'taxable_gross', 505000, 509999, 0, 0, NULL, 103400, 92),
    (g, 'fixed_amount', 'its', 'Tranche 510000 - 514999 DJF', 'taxable_gross', 510000, 514999, 0, 0, NULL, 104650, 93),
    (g, 'fixed_amount', 'its', 'Tranche 515000 - 519999 DJF', 'taxable_gross', 515000, 519999, 0, 0, NULL, 105900, 94),
    (g, 'fixed_amount', 'its', 'Tranche 520000 - 524999 DJF', 'taxable_gross', 520000, 524999, 0, 0, NULL, 107150, 95),
    (g, 'fixed_amount', 'its', 'Tranche 525000 - 529999 DJF', 'taxable_gross', 525000, 529999, 0, 0, NULL, 108400, 96),
    (g, 'fixed_amount', 'its', 'Tranche 530000 - 534999 DJF', 'taxable_gross', 530000, 534999, 0, 0, NULL, 109650, 97),
    (g, 'fixed_amount', 'its', 'Tranche 535000 - 539999 DJF', 'taxable_gross', 535000, 539999, 0, 0, NULL, 110900, 98),
    (g, 'fixed_amount', 'its', 'Tranche 540000 - 544999 DJF', 'taxable_gross', 540000, 544999, 0, 0, NULL, 112150, 99),
    (g, 'fixed_amount', 'its', 'Tranche 545000 - 549999 DJF', 'taxable_gross', 545000, 549999, 0, 0, NULL, 113400, 100),
    (g, 'fixed_amount', 'its', 'Tranche 550000 - 554999 DJF', 'taxable_gross', 550000, 554999, 0, 0, NULL, 114650, 101),
    (g, 'fixed_amount', 'its', 'Tranche 555000 - 559999 DJF', 'taxable_gross', 555000, 559999, 0, 0, NULL, 115900, 102),
    (g, 'fixed_amount', 'its', 'Tranche 560000 - 564999 DJF', 'taxable_gross', 560000, 564999, 0, 0, NULL, 117150, 103),
    (g, 'fixed_amount', 'its', 'Tranche 565000 - 569999 DJF', 'taxable_gross', 565000, 569999, 0, 0, NULL, 118400, 104),
    (g, 'fixed_amount', 'its', 'Tranche 570000 - 574999 DJF', 'taxable_gross', 570000, 574999, 0, 0, NULL, 119650, 105),
    (g, 'fixed_amount', 'its', 'Tranche 575000 - 579999 DJF', 'taxable_gross', 575000, 579999, 0, 0, NULL, 120900, 106),
    (g, 'fixed_amount', 'its', 'Tranche 580000 - 584999 DJF', 'taxable_gross', 580000, 584999, 0, 0, NULL, 122150, 107),
    (g, 'fixed_amount', 'its', 'Tranche 585000 - 589999 DJF', 'taxable_gross', 585000, 589999, 0, 0, NULL, 123400, 108),
    (g, 'fixed_amount', 'its', 'Tranche 590000 - 594999 DJF', 'taxable_gross', 590000, 594999, 0, 0, NULL, 124650, 109),
    (g, 'fixed_amount', 'its', 'Tranche 595000 - 599999 DJF', 'taxable_gross', 595000, 599999, 0, 0, NULL, 125900, 110),
    (g, 'fixed_amount', 'its', 'Tranche 600000 - 604999 DJF', 'taxable_gross', 600000, 604999, 0, 0, NULL, 127400, 111),
    (g, 'fixed_amount', 'its', 'Tranche 605000 - 609999 DJF', 'taxable_gross', 605000, 609999, 0, 0, NULL, 128900, 112),
    (g, 'fixed_amount', 'its', 'Tranche 610000 - 614999 DJF', 'taxable_gross', 610000, 614999, 0, 0, NULL, 130400, 113),
    (g, 'fixed_amount', 'its', 'Tranche 615000 - 619999 DJF', 'taxable_gross', 615000, 619999, 0, 0, NULL, 131900, 114),
    (g, 'fixed_amount', 'its', 'Tranche 620000 - 624999 DJF', 'taxable_gross', 620000, 624999, 0, 0, NULL, 133400, 115),
    (g, 'fixed_amount', 'its', 'Tranche 625000 - 629999 DJF', 'taxable_gross', 625000, 629999, 0, 0, NULL, 134900, 116),
    (g, 'fixed_amount', 'its', 'Tranche 630000 - 634999 DJF', 'taxable_gross', 630000, 634999, 0, 0, NULL, 136400, 117),
    (g, 'fixed_amount', 'its', 'Tranche 635000 - 639999 DJF', 'taxable_gross', 635000, 639999, 0, 0, NULL, 137900, 118),
    (g, 'fixed_amount', 'its', 'Tranche 640000 - 644999 DJF', 'taxable_gross', 640000, 644999, 0, 0, NULL, 139400, 119),
    (g, 'fixed_amount', 'its', 'Tranche 645000 - 649999 DJF', 'taxable_gross', 645000, 649999, 0, 0, NULL, 140900, 120),
    (g, 'fixed_amount', 'its', 'Tranche 650000 - 654999 DJF', 'taxable_gross', 650000, 654999, 0, 0, NULL, 142400, 121),
    (g, 'fixed_amount', 'its', 'Tranche 655000 - 659999 DJF', 'taxable_gross', 655000, 659999, 0, 0, NULL, 143900, 122),
    (g, 'fixed_amount', 'its', 'Tranche 660000 - 664999 DJF', 'taxable_gross', 660000, 664999, 0, 0, NULL, 145400, 123),
    (g, 'fixed_amount', 'its', 'Tranche 665000 - 669999 DJF', 'taxable_gross', 665000, 669999, 0, 0, NULL, 146900, 124),
    (g, 'fixed_amount', 'its', 'Tranche 670000 - 674999 DJF', 'taxable_gross', 670000, 674999, 0, 0, NULL, 148400, 125),
    (g, 'fixed_amount', 'its', 'Tranche 675000 - 679999 DJF', 'taxable_gross', 675000, 679999, 0, 0, NULL, 149900, 126),
    (g, 'fixed_amount', 'its', 'Tranche 680000 - 684999 DJF', 'taxable_gross', 680000, 684999, 0, 0, NULL, 151400, 127),
    (g, 'fixed_amount', 'its', 'Tranche 685000 - 689999 DJF', 'taxable_gross', 685000, 689999, 0, 0, NULL, 152900, 128),
    (g, 'fixed_amount', 'its', 'Tranche 690000 - 694999 DJF', 'taxable_gross', 690000, 694999, 0, 0, NULL, 154400, 129),
    (g, 'fixed_amount', 'its', 'Tranche 695000 - 699999 DJF', 'taxable_gross', 695000, 699999, 0, 0, NULL, 155900, 130),
    (g, 'fixed_amount', 'its', 'Tranche 700000 - 704999 DJF', 'taxable_gross', 700000, 704999, 0, 0, NULL, 157400, 131),
    (g, 'fixed_amount', 'its', 'Tranche 705000 - 709999 DJF', 'taxable_gross', 705000, 709999, 0, 0, NULL, 158900, 132),
    (g, 'fixed_amount', 'its', 'Tranche 710000 - 714999 DJF', 'taxable_gross', 710000, 714999, 0, 0, NULL, 160400, 133),
    (g, 'fixed_amount', 'its', 'Tranche 715000 - 719999 DJF', 'taxable_gross', 715000, 719999, 0, 0, NULL, 161900, 134),
    (g, 'fixed_amount', 'its', 'Tranche 720000 - 724999 DJF', 'taxable_gross', 720000, 724999, 0, 0, NULL, 163400, 135),
    (g, 'fixed_amount', 'its', 'Tranche 725000 - 729999 DJF', 'taxable_gross', 725000, 729999, 0, 0, NULL, 164900, 136),
    (g, 'fixed_amount', 'its', 'Tranche 730000 - 734999 DJF', 'taxable_gross', 730000, 734999, 0, 0, NULL, 166400, 137),
    (g, 'fixed_amount', 'its', 'Tranche 735000 - 739999 DJF', 'taxable_gross', 735000, 739999, 0, 0, NULL, 167900, 138),
    (g, 'fixed_amount', 'its', 'Tranche 740000 - 744999 DJF', 'taxable_gross', 740000, 744999, 0, 0, NULL, 169400, 139),
    (g, 'fixed_amount', 'its', 'Tranche 745000 - 749999 DJF', 'taxable_gross', 745000, 749999, 0, 0, NULL, 170900, 140),
    (g, 'fixed_amount', 'its', 'Tranche 750000 - 754999 DJF', 'taxable_gross', 750000, 754999, 0, 0, NULL, 172400, 141),
    (g, 'fixed_amount', 'its', 'Tranche 755000 - 759999 DJF', 'taxable_gross', 755000, 759999, 0, 0, NULL, 173900, 142),
    (g, 'fixed_amount', 'its', 'Tranche 760000 - 764999 DJF', 'taxable_gross', 760000, 764999, 0, 0, NULL, 175400, 143),
    (g, 'fixed_amount', 'its', 'Tranche 765000 - 769999 DJF', 'taxable_gross', 765000, 769999, 0, 0, NULL, 176900, 144),
    (g, 'fixed_amount', 'its', 'Tranche 770000 - 774999 DJF', 'taxable_gross', 770000, 774999, 0, 0, NULL, 178400, 145),
    (g, 'fixed_amount', 'its', 'Tranche 775000 - 779999 DJF', 'taxable_gross', 775000, 779999, 0, 0, NULL, 179900, 146),
    (g, 'fixed_amount', 'its', 'Tranche 780000 - 784999 DJF', 'taxable_gross', 780000, 784999, 0, 0, NULL, 181400, 147),
    (g, 'fixed_amount', 'its', 'Tranche 785000 - 789999 DJF', 'taxable_gross', 785000, 789999, 0, 0, NULL, 182900, 148),
    (g, 'fixed_amount', 'its', 'Tranche 790000 - 794999 DJF', 'taxable_gross', 790000, 794999, 0, 0, NULL, 184400, 149),
    (g, 'fixed_amount', 'its', 'Tranche 795000 - 799999 DJF', 'taxable_gross', 795000, 799999, 0, 0, NULL, 185900, 150),
    (g, 'fixed_amount', 'its', 'Tranche 800000 - 804999 DJF', 'taxable_gross', 800000, 804999, 0, 0, NULL, 187400, 151),
    (g, 'fixed_amount', 'its', 'Tranche 805000 - 809999 DJF', 'taxable_gross', 805000, 809999, 0, 0, NULL, 188900, 152),
    (g, 'fixed_amount', 'its', 'Tranche 810000 - 814999 DJF', 'taxable_gross', 810000, 814999, 0, 0, NULL, 190400, 153),
    (g, 'fixed_amount', 'its', 'Tranche 815000 - 819999 DJF', 'taxable_gross', 815000, 819999, 0, 0, NULL, 191900, 154),
    (g, 'fixed_amount', 'its', 'Tranche 820000 - 824999 DJF', 'taxable_gross', 820000, 824999, 0, 0, NULL, 193400, 155),
    (g, 'fixed_amount', 'its', 'Tranche 825000 - 829999 DJF', 'taxable_gross', 825000, 829999, 0, 0, NULL, 194900, 156),
    (g, 'fixed_amount', 'its', 'Tranche 830000 - 834999 DJF', 'taxable_gross', 830000, 834999, 0, 0, NULL, 196400, 157),
    (g, 'fixed_amount', 'its', 'Tranche 835000 - 839999 DJF', 'taxable_gross', 835000, 839999, 0, 0, NULL, 197900, 158),
    (g, 'fixed_amount', 'its', 'Tranche 840000 - 844999 DJF', 'taxable_gross', 840000, 844999, 0, 0, NULL, 199400, 159),
    (g, 'fixed_amount', 'its', 'Tranche 845000 - 849999 DJF', 'taxable_gross', 845000, 849999, 0, 0, NULL, 200900, 160),
    (g, 'fixed_amount', 'its', 'Tranche 850000 - 854999 DJF', 'taxable_gross', 850000, 854999, 0, 0, NULL, 202400, 161),
    (g, 'fixed_amount', 'its', 'Tranche 855000 - 859999 DJF', 'taxable_gross', 855000, 859999, 0, 0, NULL, 203900, 162),
    (g, 'fixed_amount', 'its', 'Tranche 860000 - 864999 DJF', 'taxable_gross', 860000, 864999, 0, 0, NULL, 205400, 163),
    (g, 'fixed_amount', 'its', 'Tranche 865000 - 869999 DJF', 'taxable_gross', 865000, 869999, 0, 0, NULL, 206900, 164),
    (g, 'fixed_amount', 'its', 'Tranche 870000 - 874999 DJF', 'taxable_gross', 870000, 874999, 0, 0, NULL, 208400, 165),
    (g, 'fixed_amount', 'its', 'Tranche 875000 - 879999 DJF', 'taxable_gross', 875000, 879999, 0, 0, NULL, 209900, 166),
    (g, 'fixed_amount', 'its', 'Tranche 880000 - 884999 DJF', 'taxable_gross', 880000, 884999, 0, 0, NULL, 211400, 167),
    (g, 'fixed_amount', 'its', 'Tranche 885000 - 889999 DJF', 'taxable_gross', 885000, 889999, 0, 0, NULL, 212900, 168),
    (g, 'fixed_amount', 'its', 'Tranche 890000 - 894999 DJF', 'taxable_gross', 890000, 894999, 0, 0, NULL, 214400, 169),
    (g, 'fixed_amount', 'its', 'Tranche 895000 - 899999 DJF', 'taxable_gross', 895000, 899999, 0, 0, NULL, 215900, 170),
    (g, 'fixed_amount', 'its', 'Tranche 900000 - 904999 DJF', 'taxable_gross', 900000, 904999, 0, 0, NULL, 217400, 171),
    (g, 'fixed_amount', 'its', 'Tranche 905000 - 909999 DJF', 'taxable_gross', 905000, 909999, 0, 0, NULL, 218900, 172),
    (g, 'fixed_amount', 'its', 'Tranche 910000 - 914999 DJF', 'taxable_gross', 910000, 914999, 0, 0, NULL, 220400, 173),
    (g, 'fixed_amount', 'its', 'Tranche 915000 - 919999 DJF', 'taxable_gross', 915000, 919999, 0, 0, NULL, 221900, 174),
    (g, 'fixed_amount', 'its', 'Tranche 920000 - 924999 DJF', 'taxable_gross', 920000, 924999, 0, 0, NULL, 223400, 175),
    (g, 'fixed_amount', 'its', 'Tranche 925000 - 929999 DJF', 'taxable_gross', 925000, 929999, 0, 0, NULL, 224900, 176),
    (g, 'fixed_amount', 'its', 'Tranche 930000 - 934999 DJF', 'taxable_gross', 930000, 934999, 0, 0, NULL, 226400, 177),
    (g, 'fixed_amount', 'its', 'Tranche 935000 - 939999 DJF', 'taxable_gross', 935000, 939999, 0, 0, NULL, 227900, 178),
    (g, 'fixed_amount', 'its', 'Tranche 940000 - 944999 DJF', 'taxable_gross', 940000, 944999, 0, 0, NULL, 229400, 179),
    (g, 'fixed_amount', 'its', 'Tranche 945000 - 949999 DJF', 'taxable_gross', 945000, 949999, 0, 0, NULL, 230900, 180),
    (g, 'fixed_amount', 'its', 'Tranche 950000 - 954999 DJF', 'taxable_gross', 950000, 954999, 0, 0, NULL, 232400, 181),
    (g, 'fixed_amount', 'its', 'Tranche 955000 - 959999 DJF', 'taxable_gross', 955000, 959999, 0, 0, NULL, 233900, 182),
    (g, 'fixed_amount', 'its', 'Tranche 960000 - 964999 DJF', 'taxable_gross', 960000, 964999, 0, 0, NULL, 235400, 183),
    (g, 'fixed_amount', 'its', 'Tranche 965000 - 969999 DJF', 'taxable_gross', 965000, 969999, 0, 0, NULL, 236900, 184),
    (g, 'fixed_amount', 'its', 'Tranche 970000 - 974999 DJF', 'taxable_gross', 970000, 974999, 0, 0, NULL, 238400, 185),
    (g, 'fixed_amount', 'its', 'Tranche 975000 - 979999 DJF', 'taxable_gross', 975000, 979999, 0, 0, NULL, 239900, 186),
    (g, 'fixed_amount', 'its', 'Tranche 980000 - 984999 DJF', 'taxable_gross', 980000, 984999, 0, 0, NULL, 241400, 187),
    (g, 'fixed_amount', 'its', 'Tranche 985000 - 989999 DJF', 'taxable_gross', 985000, 989999, 0, 0, NULL, 242900, 188),
    (g, 'fixed_amount', 'its', 'Tranche 990000 - 994999 DJF', 'taxable_gross', 990000, 994999, 0, 0, NULL, 244400, 189),
    (g, 'fixed_amount', 'its', 'Tranche 995000 - 999999 DJF', 'taxable_gross', 995000, 999999, 0, 0, NULL, 245900, 190),
    (g, 'fixed_amount', 'its', 'Tranche 1000000 - 1004999 DJF', 'taxable_gross', 1000000, 1004999, 0, 0, NULL, 247650, 191),
    (g, 'fixed_amount', 'its', 'Tranche 1005000 - 1009999 DJF', 'taxable_gross', 1005000, 1009999, 0, 0, NULL, 249400, 192),
    (g, 'fixed_amount', 'its', 'Tranche 1010000 - 1014999 DJF', 'taxable_gross', 1010000, 1014999, 0, 0, NULL, 251150, 193),
    (g, 'fixed_amount', 'its', 'Tranche 1015000 - 1019999 DJF', 'taxable_gross', 1015000, 1019999, 0, 0, NULL, 252900, 194),
    (g, 'fixed_amount', 'its', 'Tranche 1020000 - 1024999 DJF', 'taxable_gross', 1020000, 1024999, 0, 0, NULL, 254650, 195),
    (g, 'fixed_amount', 'its', 'Tranche 1025000 - 1029999 DJF', 'taxable_gross', 1025000, 1029999, 0, 0, NULL, 256400, 196),
    (g, 'fixed_amount', 'its', 'Tranche 1030000 - 1034999 DJF', 'taxable_gross', 1030000, 1034999, 0, 0, NULL, 258150, 197),
    (g, 'fixed_amount', 'its', 'Tranche 1035000 - 1039999 DJF', 'taxable_gross', 1035000, 1039999, 0, 0, NULL, 259900, 198),
    (g, 'fixed_amount', 'its', 'Tranche 1040000 - 1044999 DJF', 'taxable_gross', 1040000, 1044999, 0, 0, NULL, 261650, 199),
    (g, 'fixed_amount', 'its', 'Tranche 1045000 - 1049999 DJF', 'taxable_gross', 1045000, 1049999, 0, 0, NULL, 263400, 200),
    (g, 'fixed_amount', 'its', 'Tranche 1050000 - 1054999 DJF', 'taxable_gross', 1050000, 1054999, 0, 0, NULL, 265150, 201),
    (g, 'fixed_amount', 'its', 'Tranche 1055000 - 1059999 DJF', 'taxable_gross', 1055000, 1059999, 0, 0, NULL, 266900, 202),
    (g, 'fixed_amount', 'its', 'Tranche 1060000 - 1064999 DJF', 'taxable_gross', 1060000, 1064999, 0, 0, NULL, 268650, 203),
    (g, 'fixed_amount', 'its', 'Tranche 1065000 - 1069999 DJF', 'taxable_gross', 1065000, 1069999, 0, 0, NULL, 270400, 204),
    (g, 'fixed_amount', 'its', 'Tranche 1070000 - 1074999 DJF', 'taxable_gross', 1070000, 1074999, 0, 0, NULL, 272150, 205),
    (g, 'fixed_amount', 'its', 'Tranche 1075000 - 1079999 DJF', 'taxable_gross', 1075000, 1079999, 0, 0, NULL, 273900, 206),
    (g, 'fixed_amount', 'its', 'Tranche 1080000 - 1084999 DJF', 'taxable_gross', 1080000, 1084999, 0, 0, NULL, 275650, 207),
    (g, 'fixed_amount', 'its', 'Tranche 1085000 - 1089999 DJF', 'taxable_gross', 1085000, 1089999, 0, 0, NULL, 277400, 208),
    (g, 'fixed_amount', 'its', 'Tranche 1090000 - 1094999 DJF', 'taxable_gross', 1090000, 1094999, 0, 0, NULL, 279150, 209),
    (g, 'fixed_amount', 'its', 'Tranche 1095000 - 1099999 DJF', 'taxable_gross', 1095000, 1099999, 0, 0, NULL, 280900, 210),
    (g, 'fixed_amount', 'its', 'Tranche 1100000 - 1104999 DJF', 'taxable_gross', 1100000, 1104999, 0, 0, NULL, 282650, 211),
    (g, 'fixed_amount', 'its', 'Tranche 1105000 - 1109999 DJF', 'taxable_gross', 1105000, 1109999, 0, 0, NULL, 284400, 212),
    (g, 'fixed_amount', 'its', 'Tranche 1110000 - 1114999 DJF', 'taxable_gross', 1110000, 1114999, 0, 0, NULL, 286150, 213),
    (g, 'fixed_amount', 'its', 'Tranche 1115000 - 1119999 DJF', 'taxable_gross', 1115000, 1119999, 0, 0, NULL, 287900, 214),
    (g, 'fixed_amount', 'its', 'Tranche 1120000 - 1124999 DJF', 'taxable_gross', 1120000, 1124999, 0, 0, NULL, 289650, 215),
    (g, 'fixed_amount', 'its', 'Tranche 1125000 - 1129999 DJF', 'taxable_gross', 1125000, 1129999, 0, 0, NULL, 291400, 216),
    (g, 'fixed_amount', 'its', 'Tranche 1130000 - 1134999 DJF', 'taxable_gross', 1130000, 1134999, 0, 0, NULL, 293150, 217),
    (g, 'fixed_amount', 'its', 'Tranche 1135000 - 1139999 DJF', 'taxable_gross', 1135000, 1139999, 0, 0, NULL, 294900, 218),
    (g, 'fixed_amount', 'its', 'Tranche 1140000 - 1144999 DJF', 'taxable_gross', 1140000, 1144999, 0, 0, NULL, 296650, 219),
    (g, 'fixed_amount', 'its', 'Tranche 1145000 - 1149999 DJF', 'taxable_gross', 1145000, 1149999, 0, 0, NULL, 298400, 220),
    (g, 'fixed_amount', 'its', 'Tranche 1150000 - 1154999 DJF', 'taxable_gross', 1150000, 1154999, 0, 0, NULL, 300150, 221),
    (g, 'fixed_amount', 'its', 'Tranche 1155000 - 1159999 DJF', 'taxable_gross', 1155000, 1159999, 0, 0, NULL, 301900, 222),
    (g, 'fixed_amount', 'its', 'Tranche 1160000 - 1164999 DJF', 'taxable_gross', 1160000, 1164999, 0, 0, NULL, 303650, 223),
    (g, 'fixed_amount', 'its', 'Tranche 1165000 - 1169999 DJF', 'taxable_gross', 1165000, 1169999, 0, 0, NULL, 305400, 224),
    (g, 'fixed_amount', 'its', 'Tranche 1170000 - 1174999 DJF', 'taxable_gross', 1170000, 1174999, 0, 0, NULL, 307150, 225),
    (g, 'fixed_amount', 'its', 'Tranche 1175000 - 1179999 DJF', 'taxable_gross', 1175000, 1179999, 0, 0, NULL, 308900, 226),
    (g, 'fixed_amount', 'its', 'Tranche 1180000 - 1184999 DJF', 'taxable_gross', 1180000, 1184999, 0, 0, NULL, 310650, 227),
    (g, 'fixed_amount', 'its', 'Tranche 1185000 - 1189999 DJF', 'taxable_gross', 1185000, 1189999, 0, 0, NULL, 312400, 228),
    (g, 'fixed_amount', 'its', 'Tranche 1190000 - 1194999 DJF', 'taxable_gross', 1190000, 1194999, 0, 0, NULL, 314150, 229),
    (g, 'fixed_amount', 'its', 'Tranche 1195000 - 1199999 DJF', 'taxable_gross', 1195000, 1199999, 0, 0, NULL, 315900, 230),
    (g, 'fixed_amount', 'its', 'Tranche 1200000 - 1204999 DJF', 'taxable_gross', 1200000, 1204999, 0, 0, NULL, 317650, 231),
    (g, 'fixed_amount', 'its', 'Tranche 1205000 - 1209999 DJF', 'taxable_gross', 1205000, 1209999, 0, 0, NULL, 319400, 232),
    (g, 'fixed_amount', 'its', 'Tranche 1210000 - 1214999 DJF', 'taxable_gross', 1210000, 1214999, 0, 0, NULL, 321150, 233),
    (g, 'fixed_amount', 'its', 'Tranche 1215000 - 1219999 DJF', 'taxable_gross', 1215000, 1219999, 0, 0, NULL, 322900, 234),
    (g, 'fixed_amount', 'its', 'Tranche 1220000 - 1224999 DJF', 'taxable_gross', 1220000, 1224999, 0, 0, NULL, 324650, 235),
    (g, 'fixed_amount', 'its', 'Tranche 1225000 - 1229999 DJF', 'taxable_gross', 1225000, 1229999, 0, 0, NULL, 326400, 236),
    (g, 'fixed_amount', 'its', 'Tranche 1230000 - 1234999 DJF', 'taxable_gross', 1230000, 1234999, 0, 0, NULL, 328150, 237),
    (g, 'fixed_amount', 'its', 'Tranche 1235000 - 1239999 DJF', 'taxable_gross', 1235000, 1239999, 0, 0, NULL, 329900, 238),
    (g, 'fixed_amount', 'its', 'Tranche 1240000 - 1244999 DJF', 'taxable_gross', 1240000, 1244999, 0, 0, NULL, 331650, 239),
    (g, 'fixed_amount', 'its', 'Tranche 1245000 - 1249999 DJF', 'taxable_gross', 1245000, 1249999, 0, 0, NULL, 333400, 240),
    (g, 'fixed_amount', 'its', 'Tranche 1250000 - 1254999 DJF', 'taxable_gross', 1250000, 1254999, 0, 0, NULL, 335150, 241),
    (g, 'fixed_amount', 'its', 'Tranche 1255000 - 1259999 DJF', 'taxable_gross', 1255000, 1259999, 0, 0, NULL, 336900, 242),
    (g, 'fixed_amount', 'its', 'Tranche 1260000 - 1264999 DJF', 'taxable_gross', 1260000, 1264999, 0, 0, NULL, 338650, 243),
    (g, 'fixed_amount', 'its', 'Tranche 1265000 - 1269999 DJF', 'taxable_gross', 1265000, 1269999, 0, 0, NULL, 340400, 244),
    (g, 'fixed_amount', 'its', 'Tranche 1270000 - 1274999 DJF', 'taxable_gross', 1270000, 1274999, 0, 0, NULL, 342150, 245),
    (g, 'fixed_amount', 'its', 'Tranche 1275000 - 1279999 DJF', 'taxable_gross', 1275000, 1279999, 0, 0, NULL, 343900, 246),
    (g, 'fixed_amount', 'its', 'Tranche 1280000 - 1284999 DJF', 'taxable_gross', 1280000, 1284999, 0, 0, NULL, 345650, 247),
    (g, 'fixed_amount', 'its', 'Tranche 1285000 - 1289999 DJF', 'taxable_gross', 1285000, 1289999, 0, 0, NULL, 347400, 248),
    (g, 'fixed_amount', 'its', 'Tranche 1290000 - 1294999 DJF', 'taxable_gross', 1290000, 1294999, 0, 0, NULL, 349150, 249),
    (g, 'fixed_amount', 'its', 'Tranche 1295000 - 1299999 DJF', 'taxable_gross', 1295000, 1299999, 0, 0, NULL, 350900, 250),
    (g, 'fixed_amount', 'its', 'Tranche 1300000 - 1304999 DJF', 'taxable_gross', 1300000, 1304999, 0, 0, NULL, 352650, 251),
    (g, 'fixed_amount', 'its', 'Tranche 1305000 - 1309999 DJF', 'taxable_gross', 1305000, 1309999, 0, 0, NULL, 354400, 252),
    (g, 'fixed_amount', 'its', 'Tranche 1310000 - 1314999 DJF', 'taxable_gross', 1310000, 1314999, 0, 0, NULL, 356150, 253),
    (g, 'fixed_amount', 'its', 'Tranche 1315000 - 1319999 DJF', 'taxable_gross', 1315000, 1319999, 0, 0, NULL, 357900, 254),
    (g, 'fixed_amount', 'its', 'Tranche 1320000 - 1324999 DJF', 'taxable_gross', 1320000, 1324999, 0, 0, NULL, 359650, 255),
    (g, 'fixed_amount', 'its', 'Tranche 1325000 - 1329999 DJF', 'taxable_gross', 1325000, 1329999, 0, 0, NULL, 361400, 256),
    (g, 'fixed_amount', 'its', 'Tranche 1330000 - 1334999 DJF', 'taxable_gross', 1330000, 1334999, 0, 0, NULL, 363150, 257),
    (g, 'fixed_amount', 'its', 'Tranche 1335000 - 1339999 DJF', 'taxable_gross', 1335000, 1339999, 0, 0, NULL, 364900, 258),
    (g, 'fixed_amount', 'its', 'Tranche 1340000 - 1344999 DJF', 'taxable_gross', 1340000, 1344999, 0, 0, NULL, 366650, 259),
    (g, 'fixed_amount', 'its', 'Tranche 1345000 - 1349999 DJF', 'taxable_gross', 1345000, 1349999, 0, 0, NULL, 368400, 260),
    (g, 'fixed_amount', 'its', 'Tranche 1350000 - 1354999 DJF', 'taxable_gross', 1350000, 1354999, 0, 0, NULL, 370150, 261),
    (g, 'fixed_amount', 'its', 'Tranche 1355000 - 1359999 DJF', 'taxable_gross', 1355000, 1359999, 0, 0, NULL, 371900, 262),
    (g, 'fixed_amount', 'its', 'Tranche 1360000 - 1364999 DJF', 'taxable_gross', 1360000, 1364999, 0, 0, NULL, 373650, 263),
    (g, 'fixed_amount', 'its', 'Tranche 1365000 - 1369999 DJF', 'taxable_gross', 1365000, 1369999, 0, 0, NULL, 375400, 264),
    (g, 'fixed_amount', 'its', 'Tranche 1370000 - 1374999 DJF', 'taxable_gross', 1370000, 1374999, 0, 0, NULL, 377150, 265),
    (g, 'fixed_amount', 'its', 'Tranche 1375000 - 1379999 DJF', 'taxable_gross', 1375000, 1379999, 0, 0, NULL, 378900, 266),
    (g, 'fixed_amount', 'its', 'Tranche 1380000 - 1384999 DJF', 'taxable_gross', 1380000, 1384999, 0, 0, NULL, 380650, 267),
    (g, 'fixed_amount', 'its', 'Tranche 1385000 - 1389999 DJF', 'taxable_gross', 1385000, 1389999, 0, 0, NULL, 382400, 268),
    (g, 'fixed_amount', 'its', 'Tranche 1390000 - 1394999 DJF', 'taxable_gross', 1390000, 1394999, 0, 0, NULL, 384150, 269),
    (g, 'fixed_amount', 'its', 'Tranche 1395000 - 1399999 DJF', 'taxable_gross', 1395000, 1399999, 0, 0, NULL, 385900, 270),
    (g, 'fixed_amount', 'its', 'Tranche 1400000 - 1404999 DJF', 'taxable_gross', 1400000, 1404999, 0, 0, NULL, 387650, 271),
    (g, 'fixed_amount', 'its', 'Tranche 1405000 - 1409999 DJF', 'taxable_gross', 1405000, 1409999, 0, 0, NULL, 389400, 272),
    (g, 'fixed_amount', 'its', 'Tranche 1410000 - 1414999 DJF', 'taxable_gross', 1410000, 1414999, 0, 0, NULL, 391150, 273),
    (g, 'fixed_amount', 'its', 'Tranche 1415000 - 1419999 DJF', 'taxable_gross', 1415000, 1419999, 0, 0, NULL, 392900, 274),
    (g, 'fixed_amount', 'its', 'Tranche 1420000 - 1424999 DJF', 'taxable_gross', 1420000, 1424999, 0, 0, NULL, 394650, 275),
    (g, 'fixed_amount', 'its', 'Tranche 1425000 - 1429999 DJF', 'taxable_gross', 1425000, 1429999, 0, 0, NULL, 396400, 276),
    (g, 'fixed_amount', 'its', 'Tranche 1430000 - 1434999 DJF', 'taxable_gross', 1430000, 1434999, 0, 0, NULL, 398150, 277),
    (g, 'fixed_amount', 'its', 'Tranche 1435000 - 1439999 DJF', 'taxable_gross', 1435000, 1439999, 0, 0, NULL, 399900, 278),
    (g, 'fixed_amount', 'its', 'Tranche 1440000 - 1444999 DJF', 'taxable_gross', 1440000, 1444999, 0, 0, NULL, 401650, 279),
    (g, 'fixed_amount', 'its', 'Tranche 1445000 - 1449999 DJF', 'taxable_gross', 1445000, 1449999, 0, 0, NULL, 403400, 280),
    (g, 'fixed_amount', 'its', 'Tranche 1450000 - 1454999 DJF', 'taxable_gross', 1450000, 1454999, 0, 0, NULL, 405150, 281),
    (g, 'fixed_amount', 'its', 'Tranche 1455000 - 1459999 DJF', 'taxable_gross', 1455000, 1459999, 0, 0, NULL, 406900, 282),
    (g, 'fixed_amount', 'its', 'Tranche 1460000 - 1464999 DJF', 'taxable_gross', 1460000, 1464999, 0, 0, NULL, 408650, 283),
    (g, 'fixed_amount', 'its', 'Tranche 1465000 - 1469999 DJF', 'taxable_gross', 1465000, 1469999, 0, 0, NULL, 410400, 284),
    (g, 'fixed_amount', 'its', 'Tranche 1470000 - 1474999 DJF', 'taxable_gross', 1470000, 1474999, 0, 0, NULL, 412150, 285),
    (g, 'fixed_amount', 'its', 'Tranche 1475000 - 1479999 DJF', 'taxable_gross', 1475000, 1479999, 0, 0, NULL, 413900, 286),
    (g, 'fixed_amount', 'its', 'Tranche 1480000 - 1484999 DJF', 'taxable_gross', 1480000, 1484999, 0, 0, NULL, 415650, 287),
    (g, 'fixed_amount', 'its', 'Tranche 1485000 - 1489999 DJF', 'taxable_gross', 1485000, 1489999, 0, 0, NULL, 417400, 288),
    (g, 'fixed_amount', 'its', 'Tranche 1490000 - 1494999 DJF', 'taxable_gross', 1490000, 1494999, 0, 0, NULL, 419150, 289),
    (g, 'fixed_amount', 'its', 'Tranche 1495000 - 1499999 DJF', 'taxable_gross', 1495000, 1499999, 0, 0, NULL, 420900, 290),
    (g, 'fixed_amount', 'its', 'Tranche 1500000 - 1504999 DJF', 'taxable_gross', 1500000, 1504999, 0, 0, NULL, 422650, 291),
    (g, 'fixed_amount', 'its', 'Tranche 1505000 - 1509999 DJF', 'taxable_gross', 1505000, 1509999, 0, 0, NULL, 424400, 292),
    (g, 'fixed_amount', 'its', 'Tranche 1510000 - 1514999 DJF', 'taxable_gross', 1510000, 1514999, 0, 0, NULL, 426150, 293),
    (g, 'fixed_amount', 'its', 'Tranche 1515000 - 1519999 DJF', 'taxable_gross', 1515000, 1519999, 0, 0, NULL, 427900, 294),
    (g, 'fixed_amount', 'its', 'Tranche 1520000 - 1524999 DJF', 'taxable_gross', 1520000, 1524999, 0, 0, NULL, 429650, 295),
    (g, 'fixed_amount', 'its', 'Tranche 1525000 - 1529999 DJF', 'taxable_gross', 1525000, 1529999, 0, 0, NULL, 431400, 296),
    (g, 'fixed_amount', 'its', 'Tranche 1530000 - 1534999 DJF', 'taxable_gross', 1530000, 1534999, 0, 0, NULL, 433150, 297),
    (g, 'fixed_amount', 'its', 'Tranche 1535000 - 1539999 DJF', 'taxable_gross', 1535000, 1539999, 0, 0, NULL, 434900, 298),
    (g, 'fixed_amount', 'its', 'Tranche 1540000 - 1544999 DJF', 'taxable_gross', 1540000, 1544999, 0, 0, NULL, 436650, 299),
    (g, 'fixed_amount', 'its', 'Tranche 1545000 - 1549999 DJF', 'taxable_gross', 1545000, 1549999, 0, 0, NULL, 438400, 300),
    (g, 'fixed_amount', 'its', 'Tranche 1550000 - 1554999 DJF', 'taxable_gross', 1550000, 1554999, 0, 0, NULL, 440150, 301),
    (g, 'fixed_amount', 'its', 'Tranche 1555000 - 1559999 DJF', 'taxable_gross', 1555000, 1559999, 0, 0, NULL, 441900, 302),
    (g, 'fixed_amount', 'its', 'Tranche 1560000 - 1564999 DJF', 'taxable_gross', 1560000, 1564999, 0, 0, NULL, 443650, 303),
    (g, 'fixed_amount', 'its', 'Tranche 1565000 - 1569999 DJF', 'taxable_gross', 1565000, 1569999, 0, 0, NULL, 445400, 304),
    (g, 'fixed_amount', 'its', 'Tranche 1570000 - 1574999 DJF', 'taxable_gross', 1570000, 1574999, 0, 0, NULL, 447150, 305),
    (g, 'fixed_amount', 'its', 'Tranche 1575000 - 1579999 DJF', 'taxable_gross', 1575000, 1579999, 0, 0, NULL, 448900, 306),
    (g, 'fixed_amount', 'its', 'Tranche 1580000 - 1584999 DJF', 'taxable_gross', 1580000, 1584999, 0, 0, NULL, 450650, 307),
    (g, 'fixed_amount', 'its', 'Tranche 1585000 - 1589999 DJF', 'taxable_gross', 1585000, 1589999, 0, 0, NULL, 452400, 308),
    (g, 'fixed_amount', 'its', 'Tranche 1590000 - 1594999 DJF', 'taxable_gross', 1590000, 1594999, 0, 0, NULL, 454150, 309),
    (g, 'fixed_amount', 'its', 'Tranche 1595000 - 1599999 DJF', 'taxable_gross', 1595000, 1599999, 0, 0, NULL, 455900, 310),
    (g, 'fixed_amount', 'its', 'Tranche 1600000 - 1604999 DJF', 'taxable_gross', 1600000, 1604999, 0, 0, NULL, 457650, 311),
    (g, 'fixed_amount', 'its', 'Tranche 1605000 - 1609999 DJF', 'taxable_gross', 1605000, 1609999, 0, 0, NULL, 459400, 312),
    (g, 'fixed_amount', 'its', 'Tranche 1610000 - 1614999 DJF', 'taxable_gross', 1610000, 1614999, 0, 0, NULL, 461150, 313),
    (g, 'fixed_amount', 'its', 'Tranche 1615000 - 1619999 DJF', 'taxable_gross', 1615000, 1619999, 0, 0, NULL, 462900, 314),
    (g, 'fixed_amount', 'its', 'Tranche 1620000 - 1624999 DJF', 'taxable_gross', 1620000, 1624999, 0, 0, NULL, 464650, 315),
    (g, 'fixed_amount', 'its', 'Tranche 1625000 - 1629999 DJF', 'taxable_gross', 1625000, 1629999, 0, 0, NULL, 466400, 316),
    (g, 'fixed_amount', 'its', 'Tranche 1630000 - 1634999 DJF', 'taxable_gross', 1630000, 1634999, 0, 0, NULL, 468150, 317),
    (g, 'fixed_amount', 'its', 'Tranche 1635000 - 1639999 DJF', 'taxable_gross', 1635000, 1639999, 0, 0, NULL, 469900, 318),
    (g, 'fixed_amount', 'its', 'Tranche 1640000 - 1644999 DJF', 'taxable_gross', 1640000, 1644999, 0, 0, NULL, 471650, 319),
    (g, 'fixed_amount', 'its', 'Tranche 1645000 - 1649999 DJF', 'taxable_gross', 1645000, 1649999, 0, 0, NULL, 473400, 320),
    (g, 'fixed_amount', 'its', 'Tranche 1650000 - 1654999 DJF', 'taxable_gross', 1650000, 1654999, 0, 0, NULL, 475150, 321),
    (g, 'fixed_amount', 'its', 'Tranche 1655000 - 1659999 DJF', 'taxable_gross', 1655000, 1659999, 0, 0, NULL, 476900, 322),
    (g, 'fixed_amount', 'its', 'Tranche 1660000 - 1664999 DJF', 'taxable_gross', 1660000, 1664999, 0, 0, NULL, 478650, 323),
    (g, 'fixed_amount', 'its', 'Tranche 1665000 - 1669999 DJF', 'taxable_gross', 1665000, 1669999, 0, 0, NULL, 480400, 324),
    (g, 'fixed_amount', 'its', 'Tranche 1670000 - 1674999 DJF', 'taxable_gross', 1670000, 1674999, 0, 0, NULL, 482150, 325),
    (g, 'fixed_amount', 'its', 'Tranche 1675000 - 1679999 DJF', 'taxable_gross', 1675000, 1679999, 0, 0, NULL, 483900, 326),
    (g, 'fixed_amount', 'its', 'Tranche 1680000 - 1684999 DJF', 'taxable_gross', 1680000, 1684999, 0, 0, NULL, 485650, 327),
    (g, 'fixed_amount', 'its', 'Tranche 1685000 - 1689999 DJF', 'taxable_gross', 1685000, 1689999, 0, 0, NULL, 487400, 328),
    (g, 'fixed_amount', 'its', 'Tranche 1690000 - 1694999 DJF', 'taxable_gross', 1690000, 1694999, 0, 0, NULL, 489150, 329),
    (g, 'fixed_amount', 'its', 'Tranche 1695000 - 1699999 DJF', 'taxable_gross', 1695000, 1699999, 0, 0, NULL, 490900, 330),
    (g, 'fixed_amount', 'its', 'Tranche 1700000 - 1704999 DJF', 'taxable_gross', 1700000, 1704999, 0, 0, NULL, 492650, 331),
    (g, 'fixed_amount', 'its', 'Tranche 1705000 - 1709999 DJF', 'taxable_gross', 1705000, 1709999, 0, 0, NULL, 494400, 332),
    (g, 'fixed_amount', 'its', 'Tranche 1710000 - 1714999 DJF', 'taxable_gross', 1710000, 1714999, 0, 0, NULL, 496150, 333),
    (g, 'fixed_amount', 'its', 'Tranche 1715000 - 1719999 DJF', 'taxable_gross', 1715000, 1719999, 0, 0, NULL, 497900, 334),
    (g, 'fixed_amount', 'its', 'Tranche 1720000 - 1724999 DJF', 'taxable_gross', 1720000, 1724999, 0, 0, NULL, 499650, 335),
    (g, 'fixed_amount', 'its', 'Tranche 1725000 - 1729999 DJF', 'taxable_gross', 1725000, 1729999, 0, 0, NULL, 501400, 336),
    (g, 'fixed_amount', 'its', 'Tranche 1730000 - 1734999 DJF', 'taxable_gross', 1730000, 1734999, 0, 0, NULL, 503150, 337),
    (g, 'fixed_amount', 'its', 'Tranche 1735000 - 1739999 DJF', 'taxable_gross', 1735000, 1739999, 0, 0, NULL, 504900, 338),
    (g, 'fixed_amount', 'its', 'Tranche 1740000 - 1744999 DJF', 'taxable_gross', 1740000, 1744999, 0, 0, NULL, 506650, 339),
    (g, 'fixed_amount', 'its', 'Tranche 1745000 - 1749999 DJF', 'taxable_gross', 1745000, 1749999, 0, 0, NULL, 508400, 340),
    (g, 'fixed_amount', 'its', 'Tranche 1750000 - 1754999 DJF', 'taxable_gross', 1750000, 1754999, 0, 0, NULL, 510150, 341),
    (g, 'fixed_amount', 'its', 'Tranche 1755000 - 1759999 DJF', 'taxable_gross', 1755000, 1759999, 0, 0, NULL, 511900, 342),
    (g, 'fixed_amount', 'its', 'Tranche 1760000 - 1764999 DJF', 'taxable_gross', 1760000, 1764999, 0, 0, NULL, 513650, 343),
    (g, 'fixed_amount', 'its', 'Tranche 1765000 - 1769999 DJF', 'taxable_gross', 1765000, 1769999, 0, 0, NULL, 515400, 344),
    (g, 'fixed_amount', 'its', 'Tranche 1770000 - 1774999 DJF', 'taxable_gross', 1770000, 1774999, 0, 0, NULL, 517150, 345),
    (g, 'fixed_amount', 'its', 'Tranche 1775000 - 1779999 DJF', 'taxable_gross', 1775000, 1779999, 0, 0, NULL, 518900, 346),
    (g, 'fixed_amount', 'its', 'Tranche 1780000 - 1784999 DJF', 'taxable_gross', 1780000, 1784999, 0, 0, NULL, 520650, 347),
    (g, 'fixed_amount', 'its', 'Tranche 1785000 - 1789999 DJF', 'taxable_gross', 1785000, 1789999, 0, 0, NULL, 522400, 348),
    (g, 'fixed_amount', 'its', 'Tranche 1790000 - 1794999 DJF', 'taxable_gross', 1790000, 1794999, 0, 0, NULL, 524150, 349),
    (g, 'fixed_amount', 'its', 'Tranche 1795000 - 1799999 DJF', 'taxable_gross', 1795000, 1799999, 0, 0, NULL, 525900, 350),
    (g, 'fixed_amount', 'its', 'Tranche 1800000 - 1804999 DJF', 'taxable_gross', 1800000, 1804999, 0, 0, NULL, 527650, 351),
    (g, 'fixed_amount', 'its', 'Tranche 1805000 - 1809999 DJF', 'taxable_gross', 1805000, 1809999, 0, 0, NULL, 529400, 352),
    (g, 'fixed_amount', 'its', 'Tranche 1810000 - 1814999 DJF', 'taxable_gross', 1810000, 1814999, 0, 0, NULL, 531150, 353),
    (g, 'fixed_amount', 'its', 'Tranche 1815000 - 1819999 DJF', 'taxable_gross', 1815000, 1819999, 0, 0, NULL, 532900, 354),
    (g, 'fixed_amount', 'its', 'Tranche 1820000 - 1824999 DJF', 'taxable_gross', 1820000, 1824999, 0, 0, NULL, 534650, 355),
    (g, 'fixed_amount', 'its', 'Tranche 1825000 - 1829999 DJF', 'taxable_gross', 1825000, 1829999, 0, 0, NULL, 536400, 356),
    (g, 'fixed_amount', 'its', 'Tranche 1830000 - 1834999 DJF', 'taxable_gross', 1830000, 1834999, 0, 0, NULL, 538150, 357),
    (g, 'fixed_amount', 'its', 'Tranche 1835000 - 1839999 DJF', 'taxable_gross', 1835000, 1839999, 0, 0, NULL, 539900, 358),
    (g, 'fixed_amount', 'its', 'Tranche 1840000 - 1844999 DJF', 'taxable_gross', 1840000, 1844999, 0, 0, NULL, 541650, 359),
    (g, 'fixed_amount', 'its', 'Tranche 1845000 - 1849999 DJF', 'taxable_gross', 1845000, 1849999, 0, 0, NULL, 543400, 360),
    (g, 'fixed_amount', 'its', 'Tranche 1850000 - 1854999 DJF', 'taxable_gross', 1850000, 1854999, 0, 0, NULL, 545150, 361),
    (g, 'fixed_amount', 'its', 'Tranche 1855000 - 1859999 DJF', 'taxable_gross', 1855000, 1859999, 0, 0, NULL, 546900, 362),
    (g, 'fixed_amount', 'its', 'Tranche 1860000 - 1864999 DJF', 'taxable_gross', 1860000, 1864999, 0, 0, NULL, 548650, 363),
    (g, 'fixed_amount', 'its', 'Tranche 1865000 - 1869999 DJF', 'taxable_gross', 1865000, 1869999, 0, 0, NULL, 550400, 364),
    (g, 'fixed_amount', 'its', 'Tranche 1870000 - 1874999 DJF', 'taxable_gross', 1870000, 1874999, 0, 0, NULL, 552150, 365),
    (g, 'fixed_amount', 'its', 'Tranche 1875000 - 1879999 DJF', 'taxable_gross', 1875000, 1879999, 0, 0, NULL, 553900, 366),
    (g, 'fixed_amount', 'its', 'Tranche 1880000 - 1884999 DJF', 'taxable_gross', 1880000, 1884999, 0, 0, NULL, 555650, 367),
    (g, 'fixed_amount', 'its', 'Tranche 1885000 - 1889999 DJF', 'taxable_gross', 1885000, 1889999, 0, 0, NULL, 557400, 368),
    (g, 'fixed_amount', 'its', 'Tranche 1890000 - 1894999 DJF', 'taxable_gross', 1890000, 1894999, 0, 0, NULL, 559150, 369),
    (g, 'fixed_amount', 'its', 'Tranche 1895000 - 1899999 DJF', 'taxable_gross', 1895000, 1899999, 0, 0, NULL, 560900, 370),
    (g, 'fixed_amount', 'its', 'Tranche 1900000 - 1904999 DJF', 'taxable_gross', 1900000, 1904999, 0, 0, NULL, 562650, 371),
    (g, 'fixed_amount', 'its', 'Tranche 1905000 - 1909999 DJF', 'taxable_gross', 1905000, 1909999, 0, 0, NULL, 564400, 372),
    (g, 'fixed_amount', 'its', 'Tranche 1910000 - 1914999 DJF', 'taxable_gross', 1910000, 1914999, 0, 0, NULL, 566150, 373),
    (g, 'fixed_amount', 'its', 'Tranche 1915000 - 1919999 DJF', 'taxable_gross', 1915000, 1919999, 0, 0, NULL, 567900, 374),
    (g, 'fixed_amount', 'its', 'Tranche 1920000 - 1924999 DJF', 'taxable_gross', 1920000, 1924999, 0, 0, NULL, 569650, 375),
    (g, 'fixed_amount', 'its', 'Tranche 1925000 - 1929999 DJF', 'taxable_gross', 1925000, 1929999, 0, 0, NULL, 571400, 376),
    (g, 'fixed_amount', 'its', 'Tranche 1930000 - 1934999 DJF', 'taxable_gross', 1930000, 1934999, 0, 0, NULL, 573150, 377),
    (g, 'fixed_amount', 'its', 'Tranche 1935000 - 1939999 DJF', 'taxable_gross', 1935000, 1939999, 0, 0, NULL, 574900, 378),
    (g, 'fixed_amount', 'its', 'Tranche 1940000 - 1944999 DJF', 'taxable_gross', 1940000, 1944999, 0, 0, NULL, 576650, 379),
    (g, 'fixed_amount', 'its', 'Tranche 1945000 - 1949999 DJF', 'taxable_gross', 1945000, 1949999, 0, 0, NULL, 578400, 380),
    (g, 'fixed_amount', 'its', 'Tranche 1950000 - 1954999 DJF', 'taxable_gross', 1950000, 1954999, 0, 0, NULL, 580150, 381),
    (g, 'fixed_amount', 'its', 'Tranche 1955000 - 1959999 DJF', 'taxable_gross', 1955000, 1959999, 0, 0, NULL, 581900, 382),
    (g, 'fixed_amount', 'its', 'Tranche 1960000 - 1964999 DJF', 'taxable_gross', 1960000, 1964999, 0, 0, NULL, 583650, 383),
    (g, 'fixed_amount', 'its', 'Tranche 1965000 - 1969999 DJF', 'taxable_gross', 1965000, 1969999, 0, 0, NULL, 585400, 384),
    (g, 'fixed_amount', 'its', 'Tranche 1970000 - 1974999 DJF', 'taxable_gross', 1970000, 1974999, 0, 0, NULL, 587150, 385),
    (g, 'fixed_amount', 'its', 'Tranche 1975000 - 1979999 DJF', 'taxable_gross', 1975000, 1979999, 0, 0, NULL, 588900, 386),
    (g, 'fixed_amount', 'its', 'Tranche 1980000 - 1984999 DJF', 'taxable_gross', 1980000, 1984999, 0, 0, NULL, 590650, 387),
    (g, 'fixed_amount', 'its', 'Tranche 1985000 - 1989999 DJF', 'taxable_gross', 1985000, 1989999, 0, 0, NULL, 592400, 388),
    (g, 'fixed_amount', 'its', 'Tranche 1990000 - 1994999 DJF', 'taxable_gross', 1990000, 1994999, 0, 0, NULL, 594150, 389),
    (g, 'fixed_amount', 'its', 'Tranche 1995000 - 1999999 DJF', 'taxable_gross', 1995000, 1999999, 0, 0, NULL, 595900, 390),
    (g, 'fixed_amount', 'its', 'Tranche 2000000 - 2004999 DJF', 'taxable_gross', 2000000, 2004999, 0, 0, NULL, 597650, 391),
    (g, 'fixed_amount', 'its', 'Plancher extrapolé au-delà du barème publié (non officiel — à valider)', 'taxable_gross', 2005000, NULL, 0, 0, NULL, 597650, 392),
    (g, 'bracket', 'its', 'Tranche marginale extrapolée > 2005000 DJF a 45% (non officiel — à valider)', 'taxable_gross', 2005000, NULL, 45, 0, NULL, 0, 393)
  ;

  RETURN g;
END $fn$;

COMMENT ON FUNCTION public.dj_its_2026_grid() IS
  '370 : rend l''identifiant de la grille ITS Djibouti, en la créant si elle n''existe pas. '
  'REJOUABLE — un second appel ne réécrit rien. Réservée à service_role.';

-- Écrire une grille de paie est un acte d'exploitation : personne ne l'appelle
-- depuis un écran. La fonction rend un uuid, pas une grille modifiable.
REVOKE ALL ON FUNCTION public.dj_its_2026_grid() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dj_its_2026_grid() TO service_role;

SELECT public.dj_its_2026_grid();

-- ── 3. La preuve, dans la migration elle-même ──────────────────────────────────
-- Une grille sans ses lignes est une grille MUETTE : la migration refuse de
-- passer si les 393 lignes n'y sont pas, et publie le compte.
DO $$
DECLARE
  g     uuid;
  v_n   integer;
  v_fix integer;
  v_max numeric;
BEGIN
  SELECT id INTO g
  FROM payroll_tax_grids
  WHERE tenant_id IS NULL AND country_code = 'DJ' AND grid_type = 'its' AND source = 'platform';
  IF g IS NULL THEN
    RAISE EXCEPTION '[370] la grille ITS Djibouti est absente après création.';
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE line_type = 'fixed_amount'),
         max(coalesce(max_amount, min_amount))
    INTO v_n, v_fix, v_max
  FROM payroll_tax_grid_lines
  WHERE grid_id = g;

  IF v_n <> 393 THEN
    RAISE EXCEPTION '[370] la grille ne compte que % ligne(s) au lieu de 393 — les tranches sont incomplètes.', v_n;
  END IF;

  -- Une tranche officielle doit être bornée vers le haut : deux lignes sans borne
  -- signifieraient qu'une assiette les additionne toutes les deux (cf. inFixedBracket).
  IF EXISTS (SELECT 1 FROM payroll_tax_grid_lines
              WHERE grid_id = g AND max_amount IS NULL AND sort_order < 392) THEN
    RAISE EXCEPTION '[370] une tranche officielle n''est pas bornée vers le haut.';
  END IF;

  RAISE NOTICE '[370] grille ITS Djibouti : % ligne(s), dont % en montant fixe ; dernier seuil % .',
    v_n, v_fix, v_max;
END $$;

-- ── 4. Le bucket des fichiers sources (le file_url de la grille y pointe) ──────
-- Aucune migration de `main` ne le crée : il était posé à la main sur les
-- environnements. On le pose ici pour que le lien de la grille ne soit pas un trou.
INSERT INTO storage.buckets (id, name, public)
VALUES ('tax-grid-sources', 'tax-grid-sources', false)
ON CONFLICT (id) DO NOTHING;

-- Lecture : les barèmes sont des documents de référence, consultables par tout
-- utilisateur authentifié. Écriture : administrateur de la société seulement.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'authenticated_read_tax_grid_sources') THEN
    CREATE POLICY "authenticated_read_tax_grid_sources" ON storage.objects
      FOR SELECT TO authenticated USING (bucket_id = 'tax-grid-sources');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'admin_insert_tax_grid_sources') THEN
    CREATE POLICY "admin_insert_tax_grid_sources" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'tax-grid-sources' AND current_user_role() = 'admin');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'admin_update_tax_grid_sources') THEN
    CREATE POLICY "admin_update_tax_grid_sources" ON storage.objects
      FOR UPDATE TO authenticated
      USING (bucket_id = 'tax-grid-sources' AND current_user_role() = 'admin')
      WITH CHECK (bucket_id = 'tax-grid-sources' AND current_user_role() = 'admin');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'admin_delete_tax_grid_sources') THEN
    CREATE POLICY "admin_delete_tax_grid_sources" ON storage.objects
      FOR DELETE TO authenticated
      USING (bucket_id = 'tax-grid-sources' AND current_user_role() = 'admin');
  END IF;
END $$;
