-- ════════════════════════════════════════════════════════════════════════════
-- 349 — Partie 2, tâche 2.12 (F5, cpt-006) : les noms de périodes portent
--       leurs accents
-- ════════════════════════════════════════════════════════════════════════════
--
-- LE DÉFAUT, MESURÉ. `bootstrap_tenant` nomme les périodes d'un exercice
-- « Fevrier », « Aout », « Decembre ». Trois mois sur douze s'affichent sans
-- accent dans chaque société créée.
--
-- CE QUE FAIT CE FICHIER.
--   1. La fonction en vigueur est réécrite À L'IDENTIQUE, ses trois libellés
--      corrigés : son corps est relu en base (pg_get_functiondef) et seuls ces
--      trois mots changent. Aucune autre ligne n'est recopiée à la main — une
--      copie figée effacerait un correctif ultérieur de la fonction.
--   2. Les périodes déjà créées sont renommées.
--
-- CE QU'IL NE FAIT PAS. Les libellés du PLAN COMPTABLE livré sont eux aussi
-- sans accents ni apostrophes (« Achats de matieres premieres », « Fournisseurs
-- d immobilisations » — 649 libellés distincts). Les restaurer demande une
-- liste relue, libellé par libellé : ce n'est pas fait ici.
-- ════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_def text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'bootstrap_tenant'
    AND pg_get_function_identity_arguments(p.oid) = 'p_tenant_id uuid';
  IF v_def IS NULL THEN
    -- la signature exacte peut différer d'un nom de paramètre : on prend l'unique fonction de ce nom
    SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'bootstrap_tenant';
  END IF;
  IF v_def IS NULL THEN
    RAISE NOTICE '349 : bootstrap_tenant introuvable — rien à corriger';
    RETURN;
  END IF;
  v_new := replace(replace(replace(v_def, '''Fevrier''', '''Février'''), '''Aout''', '''Août'''), '''Decembre''', '''Décembre''');
  IF v_new IS DISTINCT FROM v_def THEN
    EXECUTE v_new;
  END IF;
END $$;

UPDATE public.fiscal_periods
   SET period_label = replace(replace(replace(period_label, 'Fevrier', 'Février'), 'Aout', 'Août'), 'Decembre', 'Décembre')
 WHERE period_label ~ '(Fevrier|Aout|Decembre)';
