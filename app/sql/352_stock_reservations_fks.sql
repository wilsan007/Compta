-- 352 — stock_reservations_fks
-- Numéro pris le 2026-10-04T18:31:25.767Z par migration-numero.mjs (ligne « partie 2 (défauts métier) », branche claude/busy-diffie-eb2ff5).
-- ============================================================
-- 352_stock_reservations_fks.sql — tâche 2.16, défaut révélé par la voie C
--
-- LE DÉFAUT. `stock_reservations` (118) ne portait AUCUNE clé étrangère —
-- mesuré le 04/10 dans `pg_constraint` sur base neuve (328 migrations) : la clé
-- primaire et deux CHECK. La 237 (ISO-02) convertit les clés mono-colonnes en
-- clés composites ; elle ne pouvait pas convertir une clé qui n'existait pas.
-- Mesuré par la suite 352, 0/11 avant :
--   * une réservation sur un article ou un dépôt INEXISTANT est acceptée ;
--   * une réservation sur l'article ou le dépôt d'une AUTRE société aussi ;
--   * supprimer l'article, le dépôt ou la société laisse la réservation en
--     place, vers rien.
--
-- LES CLÉS — doctrine de la 237, composites `(tenant_id, colonne)` :
--   (tenant_id, product_id)   → products   (tenant_id, id)
--   (tenant_id, warehouse_id) → warehouses (tenant_id, id)   (dépôt NULL = « sans
--        dépôt précis » : en MATCH SIMPLE, un NULL dispense du contrôle, voulu)
--   tenant_id                 → tenants (id) ON DELETE CASCADE
--
-- POURQUOI PAS DE CASCADE NI DE SET NULL SUR L'ARTICLE ET LE DÉPÔT. Une cascade
-- effacerait la réservation en silence avec l'article ; `SET NULL (warehouse_id)`
-- changerait son SENS (« réservé au dépôt X » deviendrait « réservé partout », et
-- `release_stock_reservation` rendrait alors la quantité à tous les dépôts).
-- Un article ou un dépôt qui porte une réservation ne se supprime donc pas
-- (23503) : on libère d'abord (454). `NO ACTION` et non `RESTRICT` : le contrôle
-- se fait en fin d'instruction, ce qui laisse passer l'effacement d'une société
-- entière — la clé vers `tenants` emporte ses réservations dans la même
-- instruction, le seul cas où l'historique part avec la société (doctrine 244).
--
-- LE SORT DES ORPHELINS DÉJÀ PRÉSENTS — jamais effacés en silence, jamais de
-- `NOT VALID`. `stock_reservations_reprendre_orphelins()` (rejouable, un second
-- appel rend 0) les traite AVANT la pose des clés :
--   a. ARTICLE introuvable dans la société (inexistant, ou d'une autre société) :
--      `product_id` est NOT NULL, la ligne ne peut pas rester. Elle est RETIRÉE,
--      et sa ligne ENTIÈRE est écrite avec le motif au journal d'audit de la
--      société (`audit_log`, action `delete`, `metadata.ligne`). Elle ne
--      réservait rien de réel : `stock_quantities` ne peut porter aucune ligne
--      pour un article absent de la société (clé composite en CASCADE, 237).
--   b. DÉPÔT introuvable, article sain : la ligne RESTE (elle garde le lien à sa
--      commande). Elle est détachée du dépôt (`warehouse_id` → NULL) ; si elle
--      était `active`, elle passe à `cancelled` — aucune quantité n'est réservée
--      dans un dépôt qui n'existe pas, et une réservation active « sans dépôt »
--      serait rendue à TOUS les dépôts à sa libération. Les autres statuts sont
--      gardés. Ligne d'origine et motif au journal d'audit (action `update`).
--   c. SOCIÉTÉ disparue : la ligne part, comme partent toutes les données d'une
--      société effacée (c'est ce que la clé vers `tenants` fera désormais). Il
--      n'existe plus de journal d'audit où l'écrire : le nombre est PUBLIÉ par
--      la migration (NOTICE).
--   Dans les cas a et b-annulée, les liens de chaîne ACTIFS dont la réservation
--   est l'aval sont FERMÉS (`rompu`, motif) quand le cycle du lien (402) est en
--   place — sinon la garde de suppression (453) refuserait le retrait. Sur une
--   base où la 352 passe avant la 402, la reprise 452 les fermera à son tour.
--
-- ORDRE D'EXÉCUTION. La 352 passe après la 237 (unicités `(tenant_id, id)` des
-- parents) et AVANT les 4xx sur base neuve ; sur une base déjà à la 456, elle
-- passe après. Les deux cas sont traités : le cycle du lien est sondé, pas
-- supposé.
-- ============================================================

-- ------------------------------------------------------------
-- 1. La reprise des orphelins
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.stock_reservations_reprendre_orphelins()
RETURNS integer
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
DECLARE
  r            stock_reservations%ROWTYPE;
  v_n          integer := 0;
  v_retirees   integer := 0;
  v_detachees  integer := 0;
  v_sans_soc   integer := 0;
  v_cycle      boolean;
  v_article    boolean;
  v_motif      text;
BEGIN
  v_cycle := EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'document_links' AND column_name = 'etat');

  FOR r IN
    SELECT sr.*
    FROM stock_reservations sr
    WHERE NOT EXISTS (SELECT 1 FROM products p
                      WHERE p.tenant_id = sr.tenant_id AND p.id = sr.product_id)
       OR (sr.warehouse_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM warehouses w
                           WHERE w.tenant_id = sr.tenant_id AND w.id = sr.warehouse_id))
       OR NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id = sr.tenant_id)
    ORDER BY sr.created_at, sr.id
    FOR UPDATE OF sr
  LOOP
    -- c. la société n'existe plus
    IF NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id = r.tenant_id) THEN
      DELETE FROM stock_reservations WHERE id = r.id;
      v_sans_soc := v_sans_soc + 1;
      v_n := v_n + 1;
      CONTINUE;
    END IF;

    v_article := EXISTS (SELECT 1 FROM products p
                         WHERE p.tenant_id = r.tenant_id AND p.id = r.product_id);

    IF NOT v_article THEN
      v_motif := '352 — reprise : l''article de cette réservation est introuvable dans la société (supprimé, ou article d''une autre société). La réservation ne réservait aucun stock réel ; elle est retirée de la table, sa ligne entière est conservée ici.';
    ELSE
      v_motif := '352 — reprise : le dépôt de cette réservation est introuvable dans la société (supprimé, ou dépôt d''une autre société). La réservation est détachée du dépôt'
                 || CASE WHEN r.status = 'active'
                         THEN ' et annulée : aucune quantité n''est réservée dans un dépôt qui n''existe pas.'
                         ELSE ' ; son statut est conservé.' END
                 || ' La ligne d''origine est conservée ici.';
    END IF;

    INSERT INTO audit_log (tenant_id, action, entity_type, entity_id, description, metadata)
    VALUES (r.tenant_id,
            CASE WHEN v_article THEN 'update' ELSE 'delete' END,
            'stock_reservations', r.id, v_motif,
            jsonb_build_object('migration', '352', 'motif', v_motif, 'ligne', to_jsonb(r)));

    -- Le lien de chaîne qui tient la réservation se ferme avec elle (402).
    IF v_cycle AND (NOT v_article OR r.status = 'active') THEN
      EXECUTE $sql$
        UPDATE document_links
           SET etat = 'rompu', ferme_le = now(), motif = $1
         WHERE tenant_id = $2
           AND aval_type = 'stock_reservations'
           AND aval_id = $3
           AND etat = 'actif'
      $sql$ USING v_motif, r.tenant_id, r.id;
    END IF;

    IF NOT v_article THEN
      DELETE FROM stock_reservations WHERE id = r.id;
      v_retirees := v_retirees + 1;
    ELSE
      UPDATE stock_reservations
         SET warehouse_id = NULL,
             status = CASE WHEN status = 'active' THEN 'cancelled' ELSE status END,
             updated_at = now()
       WHERE id = r.id;
      v_detachees := v_detachees + 1;
    END IF;
    v_n := v_n + 1;
  END LOOP;

  RAISE NOTICE '352 : % réservation(s) orpheline(s) reprise(s) — % retirée(s) (article introuvable, tracées au journal d''audit), % détachée(s) de leur dépôt (tracées), % d''une société disparue.',
    v_n, v_retirees, v_detachees, v_sans_soc;
  RETURN v_n;
END $fn$;

COMMENT ON FUNCTION public.stock_reservations_reprendre_orphelins() IS
  '352 : reprend les réservations dont l''article, le dépôt ou la société est introuvable. Article introuvable : retirée, ligne entière et motif dans audit_log. Dépôt introuvable : détachée (warehouse_id NULL), annulée si elle était active, tracée. Société disparue : retirée. Rend le nombre de lignes reprises. Rejouable.';

REVOKE ALL ON FUNCTION public.stock_reservations_reprendre_orphelins() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stock_reservations_reprendre_orphelins() TO service_role;

-- La reprise elle-même.
SELECT public.stock_reservations_reprendre_orphelins();

-- ------------------------------------------------------------
-- 2. Les clés
-- ------------------------------------------------------------
ALTER TABLE public.stock_reservations DROP CONSTRAINT IF EXISTS stock_reservations_tenant_id_fkey;
ALTER TABLE public.stock_reservations ADD CONSTRAINT stock_reservations_tenant_id_fkey
  FOREIGN KEY ("tenant_id")
  REFERENCES public.tenants ("id") ON DELETE CASCADE;

ALTER TABLE public.stock_reservations DROP CONSTRAINT IF EXISTS stock_reservations_product_id_fkey;
ALTER TABLE public.stock_reservations ADD CONSTRAINT stock_reservations_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id");

ALTER TABLE public.stock_reservations DROP CONSTRAINT IF EXISTS stock_reservations_warehouse_id_fkey;
ALTER TABLE public.stock_reservations ADD CONSTRAINT stock_reservations_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id");

COMMENT ON CONSTRAINT stock_reservations_product_id_fkey ON public.stock_reservations IS
  '352 : l''article réservé existe, dans la même société (clé composite, doctrine 237). NO ACTION : un article qui porte une réservation ne se supprime pas — on libère d''abord.';
COMMENT ON CONSTRAINT stock_reservations_warehouse_id_fkey ON public.stock_reservations IS
  '352 : le dépôt de la réservation existe, dans la même société (clé composite, doctrine 237). NULL = sans dépôt précis. NO ACTION : SET NULL changerait le sens de la réservation.';

-- La clé vers l'article a son index depuis la 118 (tenant_id, product_id, status).
CREATE INDEX IF NOT EXISTS idx_stock_reservations_warehouse
  ON public.stock_reservations (tenant_id, warehouse_id)
  WHERE warehouse_id IS NOT NULL;
