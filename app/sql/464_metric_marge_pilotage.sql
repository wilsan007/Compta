-- ═══════════════════════════════════════════════════════════════════════════
-- 464 — I-08 : la marge de pilotage, une DEUXIÈME définition réelle
-- ═══════════════════════════════════════════════════════════════════════════
--
-- La 463 a inscrit les deux définitions trouvées du premier relevé. Un
-- second relevé, conduit correctement cette fois — en cherchant des
-- LIGNES DE CALCUL et non le mot « marge » — en trouve une troisième,
-- et celle-là est une vraie :
--
--   * `calculate_project_profitability` (SQL) → marge PROJET ;
--   * `pilotage.ts` (deux endroits : agrégat par produit/client, et
--     synthèse) → marge en % du CHIFFRE D'AFFAIRES, calculée en JavaScript.
--
-- Ce sont deux indicateurs DIFFÉRENTS qui portent le même mot : « marge ».
-- Les confondre, c'est exactement le défaut que le dictionnaire existe
-- pour empêcher — deux définitions concurrentes pour un même mot. Elles
-- sont donc nommées distinctement, `projet.marge` et `pilotage.marge_pct`,
-- et chacune inscrit son implémentation réelle.
--
-- Le budget, lui, n'a qu'UNE implémentation (`budgets.ts`, réalisé =
-- débit moins crédit des écritures validées et hors à-nouveaux) : rien à
-- faire de plus pour lui, et on ne crée pas une entrée pour une seule
-- version qui n'a pas de concurrente — sauf à l'inscrire pour la
--Traçabilité, ce que fait déjà la 463.
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.metric_definitions
                  WHERE code = 'pilotage.marge_pct' AND tenant_id IS NULL) THEN
  INSERT INTO public.metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du, valide_au, note)
  VALUES
    (NULL, 'pilotage.marge_pct', 1, 'Marge en % du chiffre d''affaires', '%',
     'marge / chiffre d''affaires * 100',
     DATE '2026-01-01', NULL,
     'Implémentation RÉELLE : src/lib/queries/pilotage.ts — (margin / revenue) * 100, en deux endroits (agrégat par produit/client ligne 146, synthèse ligne 295), et accounting/pilotage.ts ligne 295. Calcul JAVACRIPT, donc refait à l''affichage — c''est le reliquat du défaut que le dictionnaire supprime. À migrer vers une fonction SQL nommée, puis à pointer depuis le dictionnaire.');
  END IF;
END $$;