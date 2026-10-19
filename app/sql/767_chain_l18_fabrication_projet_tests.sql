-- ═══════════════════════════════════════════════════════════════════════
-- 767 — L18, TRANCHE 2 : LA FABRICATION À LA COMMANDE (un projet
--       commande un OF — le couple production ↔ projets)
-- ═══════════════════════════════════════════════════════════════════════
--
-- Voir l'en-tête de la migration pour le défaut et les décisions. Rouge
-- d'abord : `manufacturing_orders` n'a AUCUN porteur projet — la colonne
-- `project_id` n'existe pas (erreur mesurée au premier passage :
-- « column "project_id" of relation "manufacturing_orders" does not
-- exist »), aucun lien projects → manufacturing_orders n'existe (0), et
-- les consommations d'OF (`stock_movements.reference_type = 'production'`)
-- n'atteignent jamais `projects.actual_cost` : pour un projet FABRIQUÉ,
-- la marge reste à 0 — même famille que D3/D4 de la tranche 1 (418).
--
-- Les dix scénarios : T01 le lien · T02 le coût matière · T03 le sens
-- (une entrée n'impute pas) · T04 l'UPDATE remplace · T05 le DELETE rend ·
-- T06 le cas ordinaire muet (OF sans projet) · T07 un OF visant un projet
-- INEXISTANT est refusé · T08 le projet d'une AUTRE société refusé ·
-- T09 le contrat (déclaration + producteur) · T10 le changement de projet
-- (fermeture + nouveau lien — et un UPDATE sans changement de porteur
-- n'y touche pas).
-- ═══════════════════════════════════════════════════════════════════════

SELECT set_config('audit.file', '767', false);

\ir ci/audit_helpers.sql
DELETE FROM _audit_results WHERE file = '767';

-- ─────────────────────────────────────────────────────────────
-- Décor : société, nomenclature, stock de composant, et — selon
-- `p_projet` — le projet + l'OF PORTANT LE PORTEUR du couple.
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS _b767(text, boolean);
CREATE OR REPLACE FUNCTION _b767(p_nom text, p_projet boolean,
  OUT t uuid, OUT proj uuid, OUT mo uuid, OUT wh uuid,
  OUT comp uuid, OUT pf uuid, OUT bom uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant('L18C' || p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name)
    VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type)
    VALUES (t, 'PF ' || p_nom, 'PF767-' || p_nom, 'stock') RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type)
    VALUES (t, 'MP ' || p_nom, 'MP767-' || p_nom, 'stock') RETURNING id INTO comp;
  INSERT INTO boms (tenant_id, code, name, product_id)
    VALUES (t, 'BOM-' || p_nom, 'Nomenclature ' || p_nom, pf) RETURNING id INTO bom;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity)
    VALUES (t, bom, comp, 2);
  -- Stock initial du composant (le geste des suites 418/527).
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id,
    movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, comp, wh, 'in', 'in', 100, 5, 'INIT', CURRENT_DATE, CURRENT_DATE);

  IF p_projet THEN
    INSERT INTO projects (tenant_id, name)
      VALUES (t, 'Chantier ' || p_nom) RETURNING id INTO proj;
    INSERT INTO manufacturing_orders (tenant_id, number, product_id, bom_id,
      quantity, warehouse_id, status, project_id)
      VALUES (t, 'OF-' || p_nom, pf, bom, 5, wh, 'planned', proj)
      RETURNING id INTO mo;
  ELSE
    INSERT INTO manufacturing_orders (tenant_id, number, product_id, bom_id,
      quantity, warehouse_id, status)
      VALUES (t, 'OF-' || p_nom, pf, bom, 5, wh, 'planned')
      RETURNING id INTO mo;
  END IF;
END $$;

-- Le geste exact de la clôture d'OF : une SORTIE qui référence l'OF
-- (`reference_type = 'production'` — la valeur que 176/229/241/302/315
-- lisent tous). Le coût matière du mouvement est quantité × coût unitaire.
DROP FUNCTION IF EXISTS _cons767(uuid, uuid, uuid, uuid, numeric, numeric);
CREATE OR REPLACE FUNCTION _cons767(p_t uuid, p_prod uuid, p_wh uuid,
  p_mo uuid, p_q numeric, p_cout numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id,
    movement_type, type, quantity, unit_cost, reference,
    reference_type, reference_id, movement_date, date)
  VALUES (p_t, p_prod, p_wh, 'out', 'out', p_q, p_cout,
          'CONS-' || p_mo, 'production', p_mo, CURRENT_DATE, CURRENT_DATE)
  RETURNING id INTO v;
  RETURN v;
END $$;

-- ════════════════════════════════════════════════════════════
-- T01 — l'OF commandé par le projet est LIÉ : le chaînage
--      production ↔ projets existe (actif, type created_from).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; n int; lt text;
BEGIN
  x := _b767('T01', true);
  SELECT count(*), max(dl.link_type) INTO n, lt
    FROM document_links dl
   WHERE dl.tenant_id = x.t
     AND dl.amont_type = 'projects' AND dl.amont_id = x.proj
     AND dl.aval_type = 'manufacturing_orders' AND dl.aval_id = x.mo
     AND dl.effet = 'project.to_manufacturing_order'
     AND dl.etat = 'actif';
  PERFORM _rec('T01', 'l''OF commandé par le projet est LIÉ (actif, created_from)',
    n = 1 AND lt = 'created_from',
    format('liens=%s type=%s (1 / created_from attendu)', n, lt));
END $$;

-- ════════════════════════════════════════════════════════════
-- T02 — la consommation de l'OF fabriqué POUR le projet impute
--      sa matière : 4 × 5 = 20 sur actual_cost.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; c numeric;
BEGIN
  x := _b767('T02', true);
  PERFORM _cons767(x.t, x.comp, x.wh, x.mo, 4, 5);
  SELECT actual_cost INTO c FROM projects WHERE id = x.proj;
  PERFORM _rec('T02', 'la consommation de l''OF impute la matière du projet (4 × 5 = 20)',
    c = 20, format('actual_cost=%s (20 attendu)', c));
END $$;

-- ════════════════════════════════════════════════════════════
-- T03 — LE SENS : une ENTRÉE de produit fini sur l'OF n'est pas
--      une consommation — elle n'impute rien (5 × 30 = 150 en jeu).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; c numeric;
BEGIN
  x := _b767('T03', true);
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id,
    movement_type, type, quantity, unit_cost, reference,
    reference_type, reference_id, movement_date, date)
    VALUES (x.t, x.pf, x.wh, 'in', 'in', 5, 30, 'ENT-' || x.mo,
            'production', x.mo, CURRENT_DATE, CURRENT_DATE);
  SELECT actual_cost INTO c FROM projects WHERE id = x.proj;
  PERFORM _rec('T03', 'une ENTRÉE sur l''OF n''impute pas (le sens est lu, pas deviné)',
    c = 0, format('actual_cost=%s (0 attendu)', c));
END $$;

-- ════════════════════════════════════════════════════════════
-- T04 — l'UPDATE REMPLACE : corriger la quantité d'une
--      consommation remet le bon coût (6 × 5 = 30, pas 20 + 30).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; mv uuid; c numeric;
BEGIN
  x := _b767('T04', true);
  mv := _cons767(x.t, x.comp, x.wh, x.mo, 4, 5);
  UPDATE stock_movements SET quantity = 6 WHERE id = mv;
  SELECT actual_cost INTO c FROM projects WHERE id = x.proj;
  PERFORM _rec('T04', 'corriger la consommation REMPLACE le coût (6 × 5 = 30)',
    c = 30, format('actual_cost=%s (30 attendu : ni 20 ni 50)', c));
END $$;

-- ════════════════════════════════════════════════════════════
-- T05 — le DELETE REND : une consommation annulée laisse zéro
--      au projet, jamais un coût fantôme (borné à 0).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; mv uuid; c numeric;
BEGIN
  x := _b767('T05', true);
  mv := _cons767(x.t, x.comp, x.wh, x.mo, 4, 5);
  DELETE FROM stock_movements WHERE id = mv;
  SELECT actual_cost INTO c FROM projects WHERE id = x.proj;
  PERFORM _rec('T05', 'supprimer la consommation RETIRE tout son coût (0, jamais négatif)',
    c = 0, format('actual_cost=%s (0 attendu)', c));
END $$;

-- ════════════════════════════════════════════════════════════
-- T06 — LE CAS ORDINAIRE EST MUET : un OF sans projet consomme
--      sans rien imputer et sans rien lier (les 3 autres types
--      de mouvements, les45 sans référence : même silence).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; c numeric; n int;
BEGIN
  x := _b767('T06', false);
  -- Un projet TÉMOIN dans la même société : c'est lui qui mesurerait un
  -- coût que l'OF sans projet ne doit imputer nulle part.
  INSERT INTO projects (tenant_id, name) VALUES (x.t, 'Chantier témoin');
  PERFORM _cons767(x.t, x.comp, x.wh, x.mo, 4, 5);
  SELECT COALESCE(sum(actual_cost), 0) INTO c
    FROM projects WHERE tenant_id = x.t;
  SELECT count(*) INTO n FROM document_links dl
   WHERE (dl.aval_type = 'manufacturing_orders' AND dl.aval_id = x.mo)
      OR (dl.amont_type = 'manufacturing_orders' AND dl.amont_id = x.mo);
  PERFORM _rec('T06', 'un OF SANS projet consomme sans rien imputer ni lier',
    c = 0 AND n = 0,
    format('coût total des projets=%s liens=%s (0 / 0 attendus)', c, n));
END $$;

-- ════════════════════════════════════════════════════════════
-- T07 — un OF qui vise un projet INEXISTANT est refusé par la
--      CLÉ COMPOSITE nommée (23503) : la garde appartient au
--      dépôt, pas à un IF de déclencheur (celui-ci lèverait
--      après la contrainte — jamais le premier à parler).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; msg text := '';
BEGIN
  x := _b767('T07', false);
  BEGIN
    INSERT INTO manufacturing_orders (tenant_id, number, product_id, bom_id,
      quantity, warehouse_id, status, project_id)
      VALUES (x.t, 'OF-767-BAD', x.pf, x.bom, 1, x.wh, 'planned',
              'ffffffff-ffff-ffff-ffff-ffffffffffff');
  EXCEPTION WHEN foreign_key_violation THEN
    msg := SQLERRM;
  END;
  PERFORM _rec('T07', 'un OF visant un projet INEXISTANT est REFUSÉ — clé composite nommée (23503)',
    msg LIKE '%manufacturing_orders_project_fk%',
    CASE WHEN msg <> '' THEN 'refus : ' || left(msg, 96)
         ELSE 'OF accepté avec un projet fantôme' END);
END $$;

-- ════════════════════════════════════════════════════════════
-- T08 — LE CLOISONNEMENT : pointer le projet d'une AUTRE
--      société est refusé par la même clé composite (le couple
--      (tenant_id, project_id) n'existe pas chez l'autre).
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; tb uuid; pjb uuid; msg text := '';
BEGIN
  x := _b767('T08', false);
  tb := _mk_tenant('L18CT08B');
  INSERT INTO projects (tenant_id, name) VALUES (tb, 'Chantier B') RETURNING id INTO pjb;
  BEGIN
    UPDATE manufacturing_orders
       SET project_id = pjb
     WHERE id = x.mo AND tenant_id = x.t;
  EXCEPTION WHEN foreign_key_violation THEN
    msg := SQLERRM;
  END;
  PERFORM _rec('T08', 'pointer le projet d''une AUTRE société est REFUSÉ — clé composite (cloisonnement)',
    msg LIKE '%manufacturing_orders_project_fk%',
    CASE WHEN msg <> '' THEN 'refus : ' || left(msg, 96)
         ELSE 'porteur accepté chez une autre société' END);
END $$;

-- ════════════════════════════════════════════════════════════
-- T09 — LE CONTRAT (porte G2) : l'effet est DÉCLARÉ dans
--      document_effects et PRODUIT par un corps de fonction —
--      les deux sens du contrôle, dans la même livraison.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE nd int; np int;
BEGIN
  SELECT count(*) INTO nd FROM document_effects de
   WHERE de.tenant_id IS NULL
     AND de.effet = 'project.to_manufacturing_order'
     AND de.actif;
  SELECT count(*) INTO np
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.prosrc LIKE '%link_documents%'
     AND p.prosrc LIKE '%project.to_manufacturing_order%';
  PERFORM _rec('T09', 'l''effet est déclaré (document_effects) ET produit (corps de fonction)',
    nd = 1 AND np >= 1,
    format('déclarations=%s producteurs=%s (1 / ≥1 attendus)', nd, np));
END $$;

-- ════════════════════════════════════════════════════════════
-- T10 — le CHANGEMENT DE PROJET ferme l'ancien lien et ouvre le
--      nouveau ; et un UPDATE qui ne touche PAS le porteur
--      (quantité ici) ne recreuse ni ne double le lien.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE x record; p2 uuid; n_act int := 0; n_rem int := 0; n_new int := 0; n_q int := 0;
BEGIN
  x := _b767('T10', true);
  INSERT INTO projects (tenant_id, name) VALUES (x.t, 'Chantier bis') RETURNING id INTO p2;

  UPDATE manufacturing_orders SET quantity = 8 WHERE id = x.mo;   -- pas le porteur
  SELECT count(*) INTO n_q FROM document_links dl
   WHERE dl.tenant_id = x.t AND dl.amont_type = 'projects' AND dl.amont_id = x.proj
     AND dl.aval_id = x.mo AND dl.effet = 'project.to_manufacturing_order'
     AND dl.etat = 'actif';

  UPDATE manufacturing_orders SET project_id = p2 WHERE id = x.mo;  -- le porteur change

  SELECT count(*) INTO n_rem FROM document_links dl
   WHERE dl.tenant_id = x.t AND dl.amont_type = 'projects' AND dl.amont_id = x.proj
     AND dl.aval_id = x.mo AND dl.effet = 'project.to_manufacturing_order'
     AND dl.etat = 'remplace';
  SELECT count(*) INTO n_act FROM document_links dl
   WHERE dl.tenant_id = x.t AND dl.amont_type = 'projects' AND dl.amont_id = x.proj
     AND dl.aval_id = x.mo AND dl.effet = 'project.to_manufacturing_order'
     AND dl.etat = 'actif';
  SELECT count(*) INTO n_new FROM document_links dl
   WHERE dl.tenant_id = x.t AND dl.amont_type = 'projects' AND dl.amont_id = p2
     AND dl.aval_id = x.mo AND dl.effet = 'project.to_manufacturing_order'
     AND dl.etat = 'actif';

  PERFORM _rec('T10', 'changement de projet : ancien LIEN REMPLACÉ, nouveau ACTIF — et un UPDATE sans changement de porteur n''y touche pas',
    n_q = 1 AND n_rem = 1 AND n_act = 0 AND n_new = 1,
    format('sans changement=%s | remplacé ancien=%s | actif ancien=%s | actif nouveau=%s (1 / 1 / 0 / 1 attendus)',
           n_q, n_rem, n_act, n_new));
END $$;

DROP FUNCTION _b767(text, boolean);
DROP FUNCTION _cons767(uuid, uuid, uuid, uuid, numeric, numeric);

SELECT _audit_assert('767');