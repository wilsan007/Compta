-- ============================================================
-- 666_stock_transfer_lines_product_fk.sql — E.2 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Ce que la CI a trouvé APRÈS la 665, à l'étape `LOT7-04 — Vérifier les colonnes
-- et jointures contre PostgREST`, que ce job n'avait jamais atteinte sur cette
-- branche (R3) :
--
--   src/lib/queries/stock.ts:347  [stock_transfer_lines]
--     select : *, products(name, sku)
--     PGRST200 : Could not find a relationship between 'stock_transfer_lines'
--                and 'products' in the schema cache
--
-- Le select a été écrit par la 652 (E.2, commit a891161) pour l'écran
-- `/stock/transfers` : il joint l'article à chaque ligne de transfert. Il ne
-- pouvait PAS fonctionner : `stock_transfer_lines.product_id` n'a **aucune** clé
-- étrangère. La table vient de la 125, et la 237 — qui a composé `transfer_id`
-- avec sa société — ne pouvait pas inventer celle qui manquait entièrement : son
-- contrôle ne voit que les clés mono-colonnes EXISTANTES.
--
-- Conséquence en production : ouvrir une ligne de transfert renvoyait une erreur
-- PostgREST, donc « aucun article ». Ni `tsc`, ni `oxlint`, ni les tests
-- unitaires (Supabase y est simulé) ne pouvaient le voir : il faut un vrai
-- PostgREST devant un vrai schéma.
--
-- Le `ON DELETE CASCADE` suit la convention du dépôt pour une ligne d'article
-- (`bom_lines`), et `product_id` est NOT NULL — `SET NULL (product_id)`, que
-- portent les lignes de commande, y serait impossible.
-- ============================================================

ALTER TABLE public.stock_transfer_lines
  DROP CONSTRAINT IF EXISTS stock_transfer_lines_product_id_fkey;

ALTER TABLE public.stock_transfer_lines
  ADD CONSTRAINT stock_transfer_lines_product_fk
  FOREIGN KEY (tenant_id, product_id)
  REFERENCES public.products (tenant_id, id) ON DELETE CASCADE;

COMMENT ON CONSTRAINT stock_transfer_lines_product_fk ON public.stock_transfer_lines IS
  '666 (LOT7-04) : la ligne de transfert tient son article AVEC sa société. Sans cette clé, l''embed `products(name, sku)` de /stock/transfers répondait PGRST200.';

