-- ============================================================
-- 315_chain_trace_sans_effet.sql — le vocabulaire de trace gagne la valeur
--   qui lui manquait : `sans_effet`
--
-- LA LIMITE, DITE PAR LA TRANCHE 4 ET LEVÉE ICI. `chain_traces.resultat`
-- admettait cinq valeurs (`applique`, `ignore`, `tolere`, `refuse`, `regenere`)
-- et **aucune ne décrit « le maillon s'est exécuté, l'effet n'a pas été
-- produit »**. Les compagnons de la tranche 4 s'en étaient tirés en **n'écrivant
-- ni lien ni trace** quand l'aval était absent (une note de frais à 0 €, par
-- exemple) — honnête, mais muet : le tableau de bord du lot L5 aurait compté une
-- note de frais à 0 € comme un chaînage qui n'a **rien fait**, sans pouvoir le
-- dire, et un maillon dont l'aval disparaît (compte manquant, période fermée,
-- règle métier) serait **invisible**.
--
-- POURQUOI PAS `ignore` — la valeur existe déjà, mais elle dit autre chose :
-- `ignore` = « déjà appliqué » (le rejeu, l'idempotence qui marche). Confondre
-- les deux ferait perdre exactement ce que la mesure doit distinguer : un rejeu
-- sain (le socle fait son travail) et un maillon qui n'a rien produit (souvent le
-- signe d'un défaut). Deux faits, deux valeurs.
--
-- CE QUE CETTE MIGRATION CHANGE, ET RIEN D'AUTRE :
--   * la contrainte `chain_traces_resultat_check` admet `sans_effet` — sur la
--     table partitionnée **et sur ses partitions** (la contrainte y est clonée à
--     la création : elle est retirée puis reposée sur les huit relations, en deux
--     temps — sinon le nom se heurte) ;
--   * le commentaire de la colonne documente la sixième valeur ;
--   * **aucun code n'est modifié** : `chain_apres` acceptait déjà n'importe quelle
--     chaîne, c'est la contrainte qui décidait. Les compagnons qui doivent tracer
--     `sans_effet` sont mis à jour dans le même commit (314), et la suite du socle
--     (252) gagne le scénario qui l'éprouve.
--
-- REJOUABLE : la boucle retire `IF EXISTS` et repose la contrainte, sur chaque
-- relation. Rejouer la migration ne change rien (mesuré).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Les six valeurs admises — sur le PARENT, et PostgreSQL propage
--    Mesuré (premier jet refusé) : `ALTER TABLE chain_traces ADD CONSTRAINT …`
--    repose la contrainte **sur toutes les partitions** — la repose par partition
--    se heurtait alors au nom déjà propagé (« constraint … already exists »).
--    Le geste juste est donc de ne toucher qu'au parent : la contrainte y est
--    retirée (ce qui la retire partout : la repose n'a pas heurté de nom restant)
--    puis reposée avec la sixième valeur. Le §2 **vérifie** que les huit relations
--    la portent — c'est la mesure qui l'affirme, pas la documentation.
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  ALTER TABLE public.chain_traces DROP CONSTRAINT IF EXISTS chain_traces_resultat_check;
  ALTER TABLE public.chain_traces
    ADD CONSTRAINT chain_traces_resultat_check
    CHECK (resultat IN ('applique', 'ignore', 'tolere', 'refuse', 'regenere', 'sans_effet'));
END $bloc$;

COMMENT ON COLUMN chain_traces.resultat IS
  'applique = effet produit ; ignore = déjà appliqué (rejeu) ; tolere = effet non déclaré au contrat, appliqué parce que la société n''est pas en refuse ; refuse = bloqué, avec le message vu par l''utilisateur ; regenere = recalcul ; sans_effet = maillon EXÉCUTÉ, effet NON produit (l''aval est absent : total nul, compte manquant, période fermée, règle métier) — ajouté par la 315, et distinct de `ignore`, qui dit qu''un rejeu n''a rien eu à faire.';

-- ─────────────────────────────────────────────────────────────
-- 2. Ce que la migration constate
-- ─────────────────────────────────────────────────────────────
DO $bloc$
DECLARE
  v_relations int;
  v_avec     int;
  v_sans      int;
BEGIN
  SELECT count(*) INTO v_relations FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relkind IN ('r', 'p')
    AND (c.relname = 'chain_traces'
         OR EXISTS (SELECT 1 FROM pg_inherits i
                    WHERE i.inhrelid = c.oid AND i.inhparent = 'chain_traces'::regclass));

  SELECT count(*) INTO v_avec FROM pg_constraint k
  WHERE k.conname = 'chain_traces_resultat_check'
    AND pg_get_constraintdef(k.oid) LIKE '%sans_effet%';

  v_sans := v_relations - v_avec;

  RAISE NOTICE 'Vocabulaire de trace : % relation(s) (table partitionnée + partitions), % portent la valeur `sans_effet`, % ne la portent pas.',
    v_relations, v_avec, v_sans;

  -- La garde porte sur la PROPRIÉTÉ, pas sur un compte : le nombre de partitions
  -- dépend de la date et du calendrier créé (`chain_ensure_partitions`). Ce qui
  -- doit être vrai, c'est qu'aucune relation n'échappe à la contrainte.
  IF v_relations < 2 OR v_sans <> 0 THEN
    RAISE EXCEPTION 'Vocabulaire de trace incomplet : % relation(s) contrôlée(s), % sans la valeur `sans_effet`.', v_relations, v_sans;
  END IF;
END $bloc$;

