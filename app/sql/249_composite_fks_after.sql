-- ============================================================
-- 249_composite_fks_after.sql — ISO-02, seconde passe : les clés nées après la 237
--
-- GÉNÉRÉ par scripts/generate-composite-fks.mjs — ne pas éditer à la main.
--
-- POURQUOI UNE SECONDE PASSE. La 237 s'exécute avant les migrations 240 à 248 :
-- les clés qu'elles créent ne pouvaient pas figurer dans son relevé, et deux
-- d'entre elles ont rouvert la porte — `goods_receipts_warehouse_id_fkey`
-- (créée par la 241 en même temps que sa colonne) et
-- `stock_movements_product_id_fkey` (recréée MONO-COLONNE par la 244, qui
-- change son `ON DELETE` pour préserver l'historique : un correctif juste qui
-- défait, sans le savoir, la clé composite de la 237). Mesuré après la 237 sur
-- la chaîne complète : 408 clés composites, 2 mono-colonnes restantes.
-- Cette passe est générée sur l'état FINAL, où son relevé ne trouve que celles-là.
-- Relevé du 2026-09-24 : 2 clé(s) mono-colonne(s)
-- reliant deux tables cloisonnées, sur 2 table(s)
-- enfant, et 2 contrainte(s) d'unicité à poser avant que la clé
-- composite ne puisse exister (PostgreSQL exige que les colonnes référencées
-- portent une unicité).
--
-- LA FORME. La référence devient `(tenant_id, colonne)` : la société de l'enfant est
-- comparée à celle du parent, dans les DONNÉES. Un `UPDATE` de société ne peut plus
-- « emporter » la référence, et un `INSERT` inter-sociétés est refusé pour tout le
-- monde — `service_role` et déclencheurs `SECURITY DEFINER` compris, ce que la RLS ne
-- peut pas faire puisqu'elle ne les voit pas.
--
-- CE QUE LA MIGRATION NE FAIT PAS. Elle ne devine rien : si des lignes violent déjà la
-- clé, elle échoue et les nomme — jamais de `NOT VALID`, qui laisserait le défaut
-- derrière un nom de contrainte. Une ligne dont `tenant_id` est NULL (ligne système)
-- reste hors du contrôle : en `MATCH SIMPLE`, un NULL dispense de la vérification —
-- c'est voulu, ces lignes n'appartiennent à personne.
--
-- LES ACTIONS DE SUPPRESSION SONT RECOPIÉES, jamais réinventées, et avec leur
-- liste de colonnes : `ON DELETE SET NULL (colonne)` détache la seule colonne
-- concernée. Sans cette liste, une clé composite annulerait aussi `tenant_id` —
-- NOT NULL — et la suppression du parent échouerait au lieu de détacher.
-- ============================================================

-- ── 1. Les unicité des parents : (tenant_id, colonne référencée) ──────────

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'warehouses_tenant_id_id_key' AND conrelid = 'public.warehouses'::regclass) THEN
    ALTER TABLE public.warehouses ADD CONSTRAINT warehouses_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'products_tenant_id_id_key' AND conrelid = 'public.products'::regclass) THEN
    ALTER TABLE public.products ADD CONSTRAINT products_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;

-- ── 2. Les clés étrangères composites ────────────────────────────────────

-- goods_receipts
ALTER TABLE public.goods_receipts DROP CONSTRAINT IF EXISTS goods_receipts_warehouse_id_fkey;
ALTER TABLE public.goods_receipts ADD CONSTRAINT goods_receipts_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
-- stock_movements
ALTER TABLE public.stock_movements DROP CONSTRAINT IF EXISTS stock_movements_product_id_fkey;
ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");

-- ── 3. La preuve, dans la migration elle-même ────────────────────────────
-- Le contrôle permanent (`ci/check_composite_fks.sql`) relit ce relevé à chaque
-- exécution ; la migration, elle, refuse de passer s'il reste une clé. La mesure
-- emploie EXACTEMENT le filtre du générateur, schéma du parent compris :
-- `auth.users` n'est pas cloisonné — un même compte appartient légitimement à
-- plusieurs sociétés, une clé composite y serait fausse.

DO $$
DECLARE v_reste text; v_n int;
BEGIN
  SELECT count(*), string_agg(cc.relname || '.' || a.attname || ' → ' || cp.relname, ', ' ORDER BY cc.relname)
    INTO v_n, v_reste
  FROM pg_constraint f
  JOIN pg_class cc     ON cc.oid = f.conrelid
  JOIN pg_namespace nc ON nc.oid = cc.relnamespace AND nc.nspname = 'public'
  JOIN pg_class cp     ON cp.oid = f.confrelid
  JOIN pg_namespace np ON np.oid = cp.relnamespace AND np.nspname = 'public'
  JOIN pg_attribute a  ON a.attrelid = f.conrelid AND a.attnum = f.conkey[1]
  WHERE f.contype = 'f' AND array_length(f.conkey, 1) = 1 AND a.attname <> 'tenant_id'
    AND EXISTS (SELECT 1 FROM information_schema.columns x
                WHERE x.table_schema = 'public' AND x.table_name = cc.relname AND x.column_name = 'tenant_id')
    AND EXISTS (SELECT 1 FROM information_schema.columns y
                WHERE y.table_schema = 'public' AND y.table_name = cp.relname AND y.column_name = 'tenant_id');
  IF v_n > 0 THEN
    RAISE EXCEPTION '[ISO-02] % clé(s) étrangère(s) mono-colonne(s) relient encore deux tables cloisonnées : %', v_n, v_reste;
  END IF;
  RAISE NOTICE '[ISO-02] aucune clé étrangère mono-colonne entre deux tables cloisonnées.';
END $$;

