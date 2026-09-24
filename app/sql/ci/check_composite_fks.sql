-- ============================================================
-- check_composite_fks.sql — ISO-02 : aucune clé étrangère mono-colonne entre
--                            deux tables cloisonnées
--
-- LE DÉFAUT QUE CE CONTRÔLE FERME. Une clé étrangère mono-colonne
-- (`invoice_lines.invoice_id → invoices.id`) ne regarde pas la société : la ligne
-- de la société A peut désigner la ligne de la société B, que A ne voit même pas
-- en lecture. Mesuré le 24/09/2026 sur base neuve : 411 clés de ce type, sur 219
-- tables enfant. La migration 237 les a toutes converties en clés composites
-- `(tenant_id, colonne)` — générées depuis le relevé, jamais écrites à la main.
--
-- LA RÈGLE. Toute clé étrangère dont l'enfant porte `tenant_id`, dont le parent
-- porte `tenant_id` (dans le schéma `public`), et dont la colonne n'est pas
-- `tenant_id` elle-même, doit porter `tenant_id` dans sa définition. La clé
-- `…_tenant_id_fkey` vers `tenants` n'est pas concernée : elle EST le lien de
-- société, et `tenants` ne porte pas de `tenant_id`.
--
-- POURQUOI PAS `auth.users`. Un même compte d'authentification appartient
-- légitimement à plusieurs sociétés : une clé composite `(tenant_id, auth_id)`
-- vers `auth.users` serait fausse. Le contrôle ne regarde donc que les parents
-- du schéma `public`, exactement comme le générateur.
--
-- CE QUE LE CONTRÔLE NE PROUVE PAS. Il lit le catalogue : il ne dit rien des
-- lignes dont `tenant_id` est NULL (lignes système, hors contrôle en `MATCH
-- SIMPLE`) ni des valeurs NULL dans la colonne de référence. C'est le rôle des
-- scénarios 237, qui mesurent l'effet et non la forme.
--
-- LE REGISTRE. Aucune exception à ce jour, et il est gelé : un jour où une clé
-- composite serait retirée pour une raison légitime, la ligne s'inscrit ici avec
-- sa raison, et disparaît avec le défaut. Même contrat que
-- `ci/expected_failures.sql`, `ci/check_tenant_guard.sql` et
-- `ci/check_policy_duplicates.sql`.
-- ============================================================

\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- 1. Le détecteur
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_fk_mono AS
SELECT cc.relname AS child, a.attname AS child_col, cp.relname AS parent, pa.attname AS parent_col,
       f.conname
FROM pg_constraint f
JOIN pg_class cc     ON cc.oid = f.conrelid
JOIN pg_namespace nc ON nc.oid = cc.relnamespace AND nc.nspname = 'public'
JOIN pg_class cp     ON cp.oid = f.confrelid
JOIN pg_namespace np ON np.oid = cp.relnamespace AND np.nspname = 'public'
JOIN pg_attribute a  ON a.attrelid = f.conrelid AND a.attnum = f.conkey[1]
JOIN pg_attribute pa ON pa.attrelid = f.confrelid AND pa.attnum = f.confkey[1]
WHERE f.contype = 'f'
  AND array_length(f.conkey, 1) = 1
  AND a.attname <> 'tenant_id'
  AND EXISTS (SELECT 1 FROM information_schema.columns x
              WHERE x.table_schema = 'public' AND x.table_name = cc.relname
                AND x.column_name = 'tenant_id')
  AND EXISTS (SELECT 1 FROM information_schema.columns y
              WHERE y.table_schema = 'public' AND y.table_name = cp.relname
                AND y.column_name = 'tenant_id');

-- ------------------------------------------------------------
-- 2. L'auto-test : la contre-épreuve par réintroduction (§4.7)
--    Deux tables cloisonnées, reliées par une clé MONO-colonne : le détecteur
--    doit la voir. Sans cet auto-test, un détecteur cassé annoncerait « aucun
--    défaut » sur toutes les bases. La fixture vit dans `public` (et non en
--    table temporaire) : le détecteur ne regarde que le schéma `public`,
--    puisqu'une clé composite vers `auth.users` serait fausse. Elle est
--    supprimée juste après.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS public.fk_selftest_child;
DROP TABLE IF EXISTS public.fk_selftest_parent;
CREATE TABLE public.fk_selftest_parent (id uuid PRIMARY KEY, tenant_id uuid NOT NULL);
CREATE TABLE public.fk_selftest_child (id uuid PRIMARY KEY, tenant_id uuid NOT NULL,
                                       parent_id uuid REFERENCES public.fk_selftest_parent(id));

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_temp.w_fk_mono
  WHERE child = 'fk_selftest_child' AND child_col = 'parent_id';
  IF n <> 1 THEN
    RAISE EXCEPTION '[ISO-02] le détecteur est aveugle : une clé mono-colonne entre deux tables cloisonnées ne l''atteint pas (n=%).', n;
  END IF;
END $$;

DROP TABLE public.fk_selftest_child;
DROP TABLE public.fk_selftest_parent;

-- ------------------------------------------------------------
-- 3. Le registre gelé, vide à ce jour
-- ------------------------------------------------------------
CREATE TEMP TABLE fk_registre (table_name text, colonne text, raison text);
-- Format d'une ligne, si un jour il en fallait une :
--   ('enfant', 'colonne', 'pourquoi la clé composite ne peut pas exister ici, daté');

-- ------------------------------------------------------------
-- 4. Le verdict
-- ------------------------------------------------------------
DO $$
DECLARE
  v_total int; v_fk int; v_hors text; v_perimees text;
BEGIN
  SELECT count(*) INTO v_total FROM pg_temp.w_fk_mono;

  SELECT count(*) INTO v_fk
  FROM pg_constraint f
  JOIN pg_class cc     ON cc.oid = f.conrelid
  JOIN pg_namespace nc ON nc.oid = cc.relnamespace AND nc.nspname = 'public'
  JOIN pg_attribute a  ON a.attrelid = f.conrelid AND a.attnum = f.conkey[1]
  WHERE f.contype = 'f' AND array_length(f.conkey, 1) = 2 AND a.attname = 'tenant_id';

  -- Un contrôle qui n'examine rien ne prouve rien (cf. B3 du 18/09) : le nombre
  -- de clés composites est la mesure de ce qu'il regarde.
  IF v_fk < 300 THEN
    RAISE EXCEPTION '[ISO-02] le détecteur ne trouve que % clé(s) composite(s) — il est cassé, ou le schéma n''est pas chargé', v_fk;
  END IF;

  SELECT string_agg(format('    %s.%s → %s.%s (contrainte %s)', m.child, m.child_col, m.parent, m.parent_col, m.conname),
                    E'\n' ORDER BY m.child, m.child_col)
    INTO v_hors
  FROM pg_temp.w_fk_mono m
  WHERE NOT EXISTS (SELECT 1 FROM fk_registre r WHERE r.table_name = m.child AND r.colonne = m.child_col);

  SELECT string_agg(r.table_name || '.' || r.colonne, ', ' ORDER BY r.table_name)
    INTO v_perimees
  FROM fk_registre r
  WHERE NOT EXISTS (SELECT 1 FROM pg_temp.w_fk_mono m WHERE m.child = r.table_name AND m.child_col = r.colonne);

  RAISE NOTICE '[ISO-02] % clé(s) composite(s) (tenant_id, …) tenue(s) par la base, % mono-colonne(s) restante(s).',
    v_fk, v_total;

  IF v_hors IS NOT NULL THEN
    RAISE EXCEPTION E'[ISO-02] clé(s) étrangère(s) mono-colonne(s) entre deux tables cloisonnées :\n%\n'
      '  Convertissez-les en clés composites `(tenant_id, colonne)` — `scripts/generate-composite-fks.mjs` produit le SQL depuis le schéma —, ou inscrivez-les au registre de ci/check_composite_fks.sql avec leur raison.',
      v_hors;
  END IF;

  IF v_perimees IS NOT NULL THEN
    RAISE EXCEPTION '[ISO-02] registre périmé — ces clés sont désormais composites ou ont disparu : %. Retirez la ligne dans le même commit.',
      v_perimees;
  END IF;

  RAISE NOTICE '[ISO-02] aucune clé étrangère mono-colonne entre deux tables cloisonnées.';
END $$;

