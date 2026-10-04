-- ═══════════════════════════════════════════════════════════════════════════
-- 463 — I-08 : le dictionnaire reçoit les DÉFINITIONS RÉELLES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- 461 a créé le dictionnaire et rendu la concurrence IMPOSSIBLE. 462 a
-- déroulé la chaîne d'un montant. Il manquait l'étape entre les deux :
-- dire QUELLE définition, pour QUEL indicateur, et où elle est écrite.
--
-- ⚠️ RECTIFICATION D'UNE MESURE, datée du 02/10/2026. La 461 annonçait
-- « 5 fichiers de src/lib/queries/ calculent une marge projet, 8 un suivi
-- budgétaire ». C'était FAUX, et le calcul était une erreur de méthode :
-- un `grep` sur le MOT « marge » compte les fichiers qui l'AFFICHENT, pas
-- ceux qui le calculent. Relevé exact, refait :
--
--   * marge projet : **UNE** seule fonction SQL,
--     `calculate_project_profitability`, et **UN** seul appel front
--     (`businessFunctions.ts`). Il n'y a PAS deux formules concurrentes ;
--   * budget : `getBudgetTracking` n'est pas une formule — c'est une
--     LECTURE de `budgets` complétée par le réalisé pris aux écritures et
--     borné aux dates de l'exercice (BUD-01). Une lecture, pas une
--     définition.
--
-- Le défaut « définitions concurrentes » reste RÉEL au registre
-- (BUD-01, PROJ-02), mais il est bien plus étroit que ce que la 461
-- criait. On ne réécrit pas l'histoire : on l'inscrit, et ce fichier
-- enregistre les définitions TELLES QU'ELLES SONT.
--
-- CE QUE POSE CE FICHIER. Deux définitions du standard, chacune nommant
-- l'implémentation RÉELLE qui la produit — pas une formule inventée ici.
-- Le dictionnaire devient ainsi un index trustworthy : à une date donnée,
-- un indicateur a UNE définition, et l'on sait où elle est écrite.
-- Le garde anti-chevauchement (461) interdit d'en ajouter une concurrente.
-- ═══════════════════════════════════════════════════════════════════════════

-- Les définitions sont insérées par la MIGRATION, jamais par l'écran :
-- la 461 a retiré tout droit d'écriture à `authenticated`.

-- ⚠️ PAS DE `ON CONFLICT DO NOTHING` ICI, et c'est mesuré : un déclencheur
-- `BEFORE INSERT` tire AVANT que PostgreSQL ne regarde le conflit. La
-- seconde exécution de cette migration se faisait donc REFUSER par le
-- garde — qui avait raison, la ligne étant bien déjà là. Une migration
-- doit être REJOUABLE : c'est un critère de sortie du plan (partie 5).
-- D'où le `IF NOT EXISTS` ci-dessous, qui teste AVANT d'insérer.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.metric_definitions
                  WHERE code = 'projet.marge' AND version = 1 AND tenant_id IS NULL) THEN
    INSERT INTO public.metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du, valide_au, note)
    VALUES (NULL, 'projet.marge', 1, 'Marge projet', '%',
            'calculate_project_profitability(p_project_id)',
            DATE '2026-01-01', NULL,
            'Implémentation RÉELLE existante : fonction SQL calculate_project_profitability, appelée par businessFunctions.ts : calculateProjectProfitability. Relevé du 02/10/2026 : UNE seule fonction, UN seul appel front — la concurrence mesurée à tort par la 461 n''existe pas sur cet indicateur.');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.metric_definitions
                  WHERE code = 'budget.realise' AND version = 1 AND tenant_id IS NULL) THEN
    INSERT INTO public.metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du, valide_au, note)
    VALUES (NULL, 'budget.realise', 1, 'Réalisé budgétaire', 'EUR',
            'somme des écritures postées bornées aux dates de l''exercice du budget',
            DATE '2026-01-01', NULL,
            'Implémentation RÉELLE : accounting/budgets.ts : getBudgetTracking — lecture de `budgets` + une requête de lignes par EXERCICE (et non par budget, BUD-04), bornée aux dates de l''exercice et aux écritures postées (BUD-01). Ce n''est pas une formule concurrente mais une lecture documentée.');
  END IF;
END $$;

COMMENT ON FUNCTION public.chain_expliquer_montant(uuid, text, uuid) IS
  '462 (I-08) : le « pourquoi ce chiffre ? ». Déroule, pour un document, les pièces de sa chaîne (460), les ÉCRITURES produites et les LIGNES qui portent le montant. Ne calcule rien et n''invente aucun lien : un chiffre qu''aucune chaîne ne porte est renvoyé vide, jamais fabriqué.';