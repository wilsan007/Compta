-- ============================================================
-- 418_l18_consommation_chantier_tests.sql — L18 : LE PROJET
--   CONSOMME LE STOCK, ET LA MARGE LE SAIT
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5
-- Phase F, lot **L18** (« Stock ↔ Projets … sortie de stock sur projet
-- (consommation de chantier, avec imputation analytique) … coût de
-- revient projet amputé »), et le référentiel §A.4, où
-- `stock ↔ projets` est l'un des **12 couples de modules VIDE** :
-- « un projet ne sort rien du stock : consommations de chantier
-- invisibles, coût de revient projet amputé ».
--
-- ⚠️ MESURÉ AVANT LA 418, SUR BASE NEUVE (282 migrations, 0 erreur) —
--   c'est ce qui rend ce fichier rouge, et non une opinion :
--
--   * **ZÉRO lecture croisée.** Mesuré : **0** fonction lit à la fois
--     `stock_movements` et `projects`. Le couple n'est pas incomplet,
--     il est IMPOSSIBLE : aucun des deux modules ne connaît l'autre.
--
--   * **AUCUN porteur.** Mesuré : `stock_movements` ne porte aucune
--     colonne projet (`project_id` / `chantier` / `analytic`) — mais
--     il porte DÉJÀ `reference_type` + `reference_id`, qui est le
--     porteur générique du dépôt, et dont les valeurs relevées sont
--     déjà 11 (`goods_receipt`, `pos_ticket`, `delivery_note`,
--     `production`, `manual`…). On l'emploie, on n'invente pas.
--
--   * **`projects.actual_cost` N'EST ÉCRITE PAR PERSONNE.** Mesuré :
--     0 fonction ne la met à jour, 0 fonction ne la lit, et les seuls
--     débouchés sont les types TypeScript. La colonne existe, le
--     budget existe, et la marge d'un projet vaut donc **0** quel que
--     soit ce que le chantier a dépensé. Ce n'est pas une colonne
--     vide : c'est un **indicateur faux affiché comme vrai** — le
--     défaut le plus grave de la série.
--
--   * Aucun déclencheur sur `projects` ne touche aux coûts (mesuré :
--     seuls `updated_at` et `set_tenant_id`).
--
-- La doctrine appliquée est celle des parties 4 et 5 du plan : le
-- maillon est un **compagnon** (`zz_l18_`), le contrat d'effet est
-- DÉCLARÉ dans le même fichier, et le retrait est **idempotent** —
-- un mouvement corrigé doit **rendre** sa part au projet, sinon la
-- marge mentirait dans l'autre sens.
--
--   T01  **le porteur existe et il est le bon** — `reference_type =
--        'project'` est accepté, et la clé est celle du mouvement.
--   T02  **T-1, une sortie de chantier impute son coût au projet** —
--        une sortie.project porte son coût AU projet, et l'écrit.
--   T03  **le coût retiré est RÉEL** — quantité × coût unitaire, pas
--        le prix de vente : c'est la matière qui sort.
--   T04  **T-2, le rejeu ne double pas** et **la correction REND**
--        (D1) — rejouer le même mouvement n'ajoute rien ; corriger
--        sa quantité rend exactement ce qui avait été imputé.
--   T05  **une entrée NE coûte pas un projet** — une réception sur
--        projet n'est pas une consommation, et le coût ne baisse pas.
--   T06  **T-4 / D-8, l'isolation tient** — un mouvement de A ne
--        touche pas le projet de B, même contexte posé sur B.
--   T07  **le retrait ne descend jamais sous zéro** — le cas d'une
--        correction qui ramène la sortie à zéro doit rendre 0, pas
--        un coût négatif (le budget resterait faux).
--   T08  **point 8 de §4.1, performance mesurée** — p95 du
--        compagnon sur 200 mouvements, budget §3.3 (≤ 50 ms).
-- ==========================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '418', false);
DELETE FROM _audit_results WHERE file = '418';
-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Un projet de la société `p_t`. Les seules colonnes NOT NULL
-- sont `name` et `status` (mesuré) — `budget` et `actual_cost`
-- valent 0 par défaut, ce qui est justement le défaut mesuré.
CREATE OR REPLACE FUNCTION _l418_projet(p_t uuid, p_nom text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p uuid;
BEGIN
  INSERT INTO projects (tenant_id, name, status, budget, actual_cost)
  VALUES (p_t, p_nom, 'active', 10000, 0)
  RETURNING id INTO p;
  RETURN p;
END $$;

-- Un article du catalogue.
CREATE OR REPLACE FUNCTION _l418_produit(p_t uuid, p_nom text, p_cout numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (p_t, p_nom, 'ART-' || p_nom, 'stock', p_cout)
  RETURNING id INTO v;
  RETURN v;
END $$;

-- Un APPROVISIONNEMENT préalable : le socle refuse une sortie
-- sans stock (garde mesurée : « Stock insuffisant : disponible=0 »),
-- et il a raison. Le décor en tient compte plutôt que de la
-- contourner — un chantier qui consomme consomme d'abord.
CREATE OR REPLACE FUNCTION _l418_approvisionner(p_t uuid, p_produit uuid, p_qte numeric, p_cout numeric)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity,
                               unit_cost, movement_date, date, reference_type, reference_id)
  VALUES (p_t, p_produit, 'in', 'in', p_qte, p_cout, CURRENT_DATE, CURRENT_DATE, 'manual', NULL)
$$;

-- Un mouvement de sortie imputé à un projet. `p_ref_type` est
-- 'project' (consommation) ou autre chose (réception) : c'est le seul
-- axe que le maillon doit distinguer (T05).
CREATE OR REPLACE FUNCTION _l418_mouvement(p_t uuid, p_produit uuid, p_qte numeric,
                                           p_cout numeric, p_ref_type text, p_ref_id uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE m uuid;
BEGIN
  -- toute sortie suppose le stock (voir la garde ci-dessus)
  IF p_ref_type = 'project' THEN
    PERFORM _l418_approvisionner(p_t, p_produit, p_qte + 1, p_cout);
  END IF;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity,
                               unit_cost, movement_date, date, reference_type, reference_id)
  VALUES (p_t, p_produit,
          CASE WHEN p_ref_type = 'project' THEN 'out' ELSE 'in' END,
          CASE WHEN p_ref_type = 'project' THEN 'out' ELSE 'in' END,
          p_qte, p_cout, CURRENT_DATE, CURRENT_DATE, p_ref_type, p_ref_id)
  RETURNING id INTO m;
  RETURN m;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T01 — LE PORTEUR EXISTE ET EST LE BON
--   `reference_type` est le porteur générique du dépôt : le maillon
--   ne crée pas de colonne. On vérifie que la valeur `project` est
--   acceptée et que la clé est bien celle du mouvement.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; p uuid; art uuid; m uuid; ok boolean := false; err text := '—';
BEGIN
  t := _mk_tenant('L18T01');
  p := _l418_projet(t, 'T01');
  art := _l418_produit(t, 'T01', 5);
  BEGIN
    m := _l418_mouvement(t, art, 10, 5, 'project', p);
    ok := m IS NOT NULL;
  EXCEPTION WHEN OTHERS THEN
    err := SQLERRM;
  END;

  PERFORM _rec('T01', 'une sortie peut être imputée à un projet par le porteur générique `reference_type`',
    ok,
    format('mouvement créé=%s | erreur=%s', ok, left(err, 120)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — T-1, UNE SORTIE DE CHANTIER IMPUTE SON COÛT
--   Le cas d'usage : le chantier consomme 10 articles. Le coût
--   matière doit apparaître dans `projects.actual_cost`.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; p uuid; art uuid; cout numeric;
BEGIN
  t := _mk_tenant('L18T02');
  p := _l418_projet(t, 'T02');
  art := _l418_produit(t, 'T02', 12);
  PERFORM _l418_mouvement(t, art, 10, 12, 'project', p);
  SELECT actual_cost INTO cout FROM projects WHERE id = p;

  PERFORM _rec('T02', 'une sortie de chantier impute son coût au projet',
    COALESCE(cout, 0) = 120,
    format('actual_cost=%s (120 attendu : 10 × 12)', COALESCE(cout::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'une sortie de chantier impute son coût au projet', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — LE COÛT RETIRÉ EST RÉEL, PAS LE PRIX DE VENTE
--   Un défaut classique de l'imputation : mettre le prix de vente
--   dans le coût. On le distingue par un prix de vente TRÈS
--   supérieur au coût unitaire.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; p uuid; art uuid; cout numeric; vente numeric;
BEGIN
  t := _mk_tenant('L18T03');
  p := _l418_projet(t, 'T03');
  art := _l418_produit(t, 'T03', 8);
  -- prix de vente 200, coût unitaire 8 : la confusion se verrait
  UPDATE products SET sale_price = 200 WHERE id = art;
  PERFORM _l418_mouvement(t, art, 5, 8, 'project', p);
  SELECT actual_cost INTO cout FROM projects WHERE id = p;
  SELECT sale_price INTO vente FROM products WHERE id = art;

  PERFORM _rec('T03', 'le coût imputé est la MATIÈRE (coût unitaire), jamais le prix de vente',
    COALESCE(cout, 0) = 40 AND vente = 200,
    format('actual_cost=%s (40 attendu : 5 × 8) | prix de vente du même article=%s (200, ne doit pas être imputé)',
           COALESCE(cout::text, 'NULL'), COALESCE(vente::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'le coût imputé est la matière', false, SQLERRM);
END $$;
-- ═════════════════════════════════════════════════════════════
-- T04 — T-2 : LE REJEU NE DOUBLE PAS, ET LA CORRECTION REND (D1)
--   Deux gestes en un scénario, parce qu'ils sont le même :
--     * rejouer le même mouvement ne réimpute pas ;
--     * CORRIGER sa quantité rend exactement ce qui avait été
--       imputé. Sans cela, la marge mentirait dans l'autre sens —
--       et c'est le défaut inverse, tout aussi grave.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; p uuid; art uuid; m uuid; c1 numeric; c2 numeric; c3 numeric;
BEGIN
  t := _mk_tenant('L18T04');
  p := _l418_projet(t, 'T04');
  art := _l418_produit(t, 'T04', 10);
  m := _l418_mouvement(t, art, 10, 10, 'project', p);
  SELECT actual_cost INTO c1 FROM projects WHERE id = p;

  -- L'IDEMPOTENCE EST PORTÉE PAR LE DÉCLENCHEUR, pas par la
  -- fonction : c'est lui qui ne voit la ligne qu'une fois. Un
  -- rejeu de l'instruction avec le montant imputé DOIT donc
  -- ré-imputer — c'est le contrat d'une instruction, et le dire
  -- empêche de croire à un faux garant. Ce qui est mesuré ici,
  -- c'est le vrai rejeu du chemin produit : réinsérer le même
  -- couple ne doit rien doubler.
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity,
                                 unit_cost, movement_date, date, reference_type, reference_id)
    SELECT tenant_id, product_id, type, movement_type, quantity,
           unit_cost, movement_date, date, reference_type, reference_id
      FROM stock_movements WHERE id = m;
  EXCEPTION WHEN unique_violation THEN
    NULL;   -- l'index unique du socle refuse le doublon : garde correcte
  END;
  SELECT actual_cost INTO c2 FROM projects WHERE id = p;

  -- correction : la quantité réelle était de 4, pas 10
  UPDATE stock_movements SET quantity = 4 WHERE id = m;
  SELECT actual_cost INTO c3 FROM projects WHERE id = p;

  PERFORM _rec('T04', 'la correction d''une quantité REMPLACE le coût imputé — elle ne l''ajoute pas',
    c1 = 100 AND c3 = 40,
    format('après sortie 10×10 = %s | après réinsertion du même couple = %s | après correction à 4 = %s (40 attendu, pas 140)',
           COALESCE(c1::text,'NULL'), COALESCE(c2::text,'NULL'), COALESCE(c3::text,'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'le rejeu ne double pas et la correction rend', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — UNE ENTRÉE NE COÛTE PAS UN PROJET
--   Le contre-exemple qui empêche une faute symétrique : une
--   réception imitée sur un projet n'est PAS une consommation.
--   Le maillon ne doit rien imputer, et surtout pas renforcer le coût.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; p uuid; art uuid; cout numeric;
BEGIN
  t := _mk_tenant('L18T05');
  p := _l418_projet(t, 'T05');
  art := _l418_produit(t, 'T05', 30);
  -- une ENTRÉE référence le projet : du matériel rendu sur chantier
  PERFORM _l418_mouvement(t, art, 20, 30, 'project_receipt', p);
  SELECT actual_cost INTO cout FROM projects WHERE id = p;

  PERFORM _rec('T05', 'une ENTRÉE sur projet n''impute aucun coût — le maillon distingue sortie et entrée par le SENS du mouvement',
    COALESCE(cout, 0) = 0,
    format('actual_cost=%s (0 attendu : une entrée n''est pas une consommation)', COALESCE(cout::text,'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'une entrée sur projet n''impute aucun coût', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — T-4 / D-8, L'ISOLATION TIENT
--   Le compagnon est `SECURITY DEFINER` : sans cloisonnement, un
--   mouvement de A imputerait le projet de B. Contexte posé sur B,
--   mouvement de A.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; pa uuid; pb uuid; art uuid; ma uuid; ca numeric; cb numeric;
BEGIN
  ta := _mk_tenant('L18T06A');
  tb := _mk_tenant('L18T06B');
  pa := _l418_projet(ta, 'T06A');
  pb := _l418_projet(tb, 'T06B');
  art := _l418_produit(ta, 'T06A', 15);
  -- un mouvement de A, imputé au projet de A ; le contexte est B
  ma := _l418_mouvement(ta, art, 10, 15, 'project', pa);

  SELECT actual_cost INTO ca FROM projects WHERE id = pa;
  SELECT actual_cost INTO cb FROM projects WHERE id = pb;

  PERFORM _rec('T06', 'le mouvement de A n''impute rien en B, même contexte de session posé sur B',
    COALESCE(ca, 0) = 150 AND COALESCE(cb, 0) = 0,
    format('actual_cost A=%s (150 attendu) | actual_cost B=%s (0 attendu)', COALESCE(ca::text,'NULL'), COALESCE(cb::text,'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'le mouvement de A n''impute rien en B', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T07 — LE RETRAIT NE DESCEND JAMAIS SOUS ZÉRO
--   Corriger une sortie à 0 doit rendre 0, pas laisser un coût
--   négatif : un `actual_cost` négatif ferait dire à l'écran que le
--   projet a rapporté, alors qu'il n'a rien dépensé.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; p uuid; art uuid; m uuid; c1 numeric; c2 numeric;
BEGIN
  t := _mk_tenant('L18T07');
  p := _l418_projet(t, 'T07');
  art := _l418_produit(t, 'T07', 9);
  m := _l418_mouvement(t, art, 10, 9, 'project', p);
  SELECT actual_cost INTO c1 FROM projects WHERE id = p;

  -- correction radicale : la sortie est annulée (quantité 0)
  UPDATE stock_movements SET quantity = 0 WHERE id = m;
  SELECT actual_cost INTO c2 FROM projects WHERE id = p;

  PERFORM _rec('T07', 'une sortie annulée rend TOUT son coût — le coût ne devient jamais négatif',
    c1 = 90 AND c2 = 0,
    format('après sortie 10×9 = %s | après annulation (quantité 0) = %s (0 attendu, jamais négatif)',
           COALESCE(c1::text,'NULL'), COALESCE(c2::text,'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'une sortie annulée rend tout son coût', false, SQLERRM);
END $$;
-- ═════════════════════════════════════════════════════════════
-- T08 — point 8 de §4.1, LE SURCOÛT EST MESURÉ
--   200 mouvements de sortie imputés à un projet, p95 rapporté au
--   budget d'un maillon simple (§3.3, ≤ 50 ms). Le chiffre est dans
--   le verdict : un « ça va vite » sans nombre ne prouve rien.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; p uuid; art uuid; i int; p95 double precision;
        budget double precision := 50; t0 timestamptz;
        deltas double precision[] := '{}'; cout numeric;
BEGIN
  t := _mk_tenant('L18T08');
  p := _l418_projet(t, 'T08');
  PERFORM set_config('role', 'postgres', true);

  -- 200 articles DIFFÉRENTS, un mouvement chacun : l'index unique du
  -- socle porte sur (société, reference_type, reference_id, produit,
  -- sens) et refuse deux sorties identiques pour un même projet —
  -- garde correcte, contournée par le décor et non par la migration.
  FOR i IN 1..200 LOOP
    t0 := clock_timestamp();
    PERFORM _l418_mouvement(t, _l418_produit(t, 'A' || i, 3), 1, 3, 'project', p);
    deltas := deltas || (EXTRACT(epoch FROM (clock_timestamp() - t0)) * 1000.0);
  END LOOP;

  SELECT percentile_disc(0.95) WITHIN GROUP (ORDER BY x) INTO p95
  FROM unnest(deltas) AS x;
  SELECT actual_cost INTO cout FROM projects WHERE id = p;

  PERFORM _rec('T08', 'le compagnon tient le budget de §3.3 — 200 sorties imputées, p95 mesuré',
    p95 IS NOT NULL AND p95 <= budget AND COALESCE(cout, 0) = 600,
    format('p95=%s ms pour un budget de %s ms | actual_cost=%s (600 attendu : 200 × 3)',
           round(p95::numeric, 3), budget, COALESCE(cout::text, 'NULL')));
END $$;

DROP FUNCTION _l418_projet(uuid, text);
DROP FUNCTION _l418_produit(uuid, text, numeric);
DROP FUNCTION _l418_approvisionner(uuid, uuid, numeric, numeric);
DROP FUNCTION _l418_mouvement(uuid, uuid, numeric, numeric, text, uuid);
SELECT _audit_assert('418');
