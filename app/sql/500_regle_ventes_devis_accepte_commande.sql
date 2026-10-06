-- ============================================================
-- 500_regle_ventes_devis_accepte_commande.sql — partie B, lot Ventes, règle R-001
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 1) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-001 = ⬜).
--
-- R-001 — « quotes.status = accepted → création de la commande, gel du prix,
-- réservation prévisionnelle, sortie du pipeline CRM, alerte d'expiration ».
--
-- MESURÉ (B.1, base neuve 333 migrations). L'état `quotes.status = accepted` ne
-- produisait RIEN en base : aucun déclencheur sur `quotes` ne teste ce statut. La
-- commande n'était créée que par une action EXPLICITE de l'écran
-- (`transformQuoteToSalesOrder`, app/src/lib/queries/misc/commercial.ts) — et cet
-- écran ne fait PAS passer le devis à `accepted`. Le chaînage manquait donc, et
-- un appel d'API qui acceptait un devis ne créait aucune commande.
--
-- CE QUE CE FICHIER FAIT
--   * à l'acceptation d'un devis : création de la COMMANDE (statut `draft`), avec
--     ses lignes et le PRIX GELÉ (les prix du devis, recopiés tels quels) ;
--   * le lien devis → commande (`link_type` `created_from`), un événement
--     `quotes.accepted`, l'entrée et la sortie du maillon tracées ;
--   * IDEMPOTENT : si le devis a déjà une commande (`transformed_to_order_id`),
--     il ne fait rien — l'action de l'écran et cette règle ne peuvent pas créer
--     deux commandes ; le devis est marqué `transformed` (l'écran cache son bouton).
--
-- CE QUE CE FICHIER NE FAIT PAS (dits, et laissés à leurs parties)
--   * la RÉSERVATION ferme du stock reste posée à la CONFIRMATION de la commande
--     (`reserve_stock_on_sales_order_confirm`) — R-001 parle d'une réservation
--     « prévisionnelle » qui n'a pas de support au schéma, et la créer ici
--     ferait tomber les contrôles de plafond client à l'acceptation d'un devis ;
--   * la « sortie du pipeline CRM » (partie F, écrans CRM) et l'« alerte
--     d'expiration » (R-002, devis expiré) : reste de R-001, journalisé dans
--     PARTIE-B.md.
--
-- DÉCISION (dite). La commande naît `draft`. La créer `confirmed` déclencherait
-- `check_customer_credit_limit` et `check_stock_on_sales_order_confirm` — un devis
-- accepté pourrait alors être REFUSÉ pour dépassement de plafond, effet de bord
-- que R-001 ne demande pas. Confirmer la commande reste un geste explicite.
-- ============================================================

-- ── 1. Le contrat d'effet (L7 / M-05) : l'effet est nommé et actif ──
-- (sans lui, `chain_avant` laisserait passer en mode `observe` en traçant `tolere` ;
--  déclaré, il rend `true` silencieusement — c'est le contrat qui fait foi.)
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'quotes', 'accepted', 'sale.quote.order',
        false, NULL, false, false,
        true, false, true,
        'R-001 : un devis accepté produit sa commande (brouillon), prix gelé. Partie B, lot Ventes.')
ON CONFLICT DO NOTHING;

-- ── 1bis. Le registre des types de document (450) : `quotes` doit y être ──
-- `link_documents` refuse un type non inscrit au registre (règle posée par 450).
-- `quotes` n'y figurait pas : le devis n'était donc l'AMONT d'aucun maillon.
INSERT INTO chain_document_types (code, table_name, ligne_table, libelle_fr)
VALUES ('quotes', 'quotes', 'quote_lines', 'Devis client')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : devis accepté → commande ──
CREATE OR REPLACE FUNCTION public.regle_r001_devis_accepte_commande()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_order  uuid := gen_random_uuid();
  v_num    text;
  v_lignes integer := 0;
  v_l      record;
BEGIN
  -- 0. Le fait générateur : le devis vient d'être ACCEPTÉ (et ne l'était pas).
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'accepted' THEN
    RETURN NULL;
  END IF;
  -- Cloisonnement fermé : un document sans société n'entre pas dans la chaîne.
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;
  -- Idempotence métier : le devis a déjà une commande (action de l'écran, ou rejeu).
  IF COALESCE(NEW.transformed_to_order_id, OLD.transformed_to_order_id) IS NOT NULL THEN
    RETURN NULL;
  END IF;

  -- 1. Entrée du maillon — rejeu, contrat, drapeau de la société.
  IF NOT chain_avant(NEW.tenant_id, 'quotes', 'accepted', 'sale.quote.order',
                     'quotes', NEW.id, NULL,
                     format('Devis %s du %s : la commande n''a pas été créée à l''acceptation (règle sale.quote.order, module ventes).',
                            NEW.number, to_char(NEW.date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  -- 2. L'en-tête de la commande — BROUILLON, numéro de brouillon.
  v_num := draft_document_number('CMD', v_order);
  INSERT INTO sales_orders (id, tenant_id, number, customer_id, order_date, status,
                            subtotal, vat, total, notes, quote_id, validation_status)
  VALUES (v_order, NEW.tenant_id, v_num, NEW.customer_id, COALESCE(NEW.date, CURRENT_DATE),
          'draft', COALESCE(NEW.subtotal, 0), COALESCE(NEW.vat_total, 0),
          COALESCE(NEW.total, 0), NEW.notes, NEW.id, 'draft');

  -- 3. Les lignes — LE PRIX GELÉ (celui du devis, recopié).
  FOR v_l IN
    SELECT ql.product_id, ql.description, ql.quantity, ql.unit_price, ql.vat_rate
    FROM quote_lines ql
    WHERE ql.quote_id = NEW.id AND ql.tenant_id = NEW.tenant_id
    ORDER BY ql.line_order NULLS LAST, ql.id
  LOOP
    INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description,
                                   quantity, unit_price, vat_rate, delivered_quantity)
    VALUES (NEW.tenant_id, v_order, v_l.product_id, v_l.description,
            COALESCE(v_l.quantity, 0), COALESCE(v_l.unit_price, 0),
            COALESCE(v_l.vat_rate, 0), 0);
    v_lignes := v_lignes + 1;
  END LOOP;

  -- 4. Les totaux d'en-tête se recalculent depuis les lignes
  --    (`order_header_totals` ne le fait qu'à l'UPDATE) — sans quoi ils resteraient à 0.
  UPDATE sales_orders SET updated_at = now() WHERE id = v_order AND tenant_id = NEW.tenant_id;

  -- 5. LE LIEN — l'ascendance de la commande (vue chaîne, analyse d'impact).
  PERFORM link_documents(NEW.tenant_id, 'quotes', NEW.id, 'sales_orders', v_order,
                         'sale.quote.order', 'created_from',
                         jsonb_build_object('quote_number', NEW.number,
                                            'order_number', v_num, 'lignes', v_lignes));

  -- 6. Le devis se déclare transformé (l'écran cache alors son bouton « transformer »).
  UPDATE quotes
  SET transformed_to_order_id = v_order, transformation_status = 'transformed', updated_at = now()
  WHERE id = NEW.id AND tenant_id = NEW.tenant_id;

  -- 7. L'ÉVÉNEMENT — lu par les automatisations et les webhooks (I-06).
  PERFORM emit_domain_event(NEW.tenant_id, 'quotes.accepted', 'quotes', NEW.id,
                            jsonb_build_object('order_id', v_order, 'order_number', v_num,
                                               'lignes', v_lignes), NULL);

  -- 8. La mesure.
  PERFORM chain_apres(NEW.tenant_id, 'sale.quote.order', 'quotes', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (nommé `zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r001_devis_accepte_commande ON quotes;
CREATE TRIGGER zz_b2r001_devis_accepte_commande
AFTER UPDATE ON quotes
FOR EACH ROW
EXECUTE FUNCTION public.regle_r001_devis_accepte_commande();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r001_devis_accepte_commande() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r001_devis_accepte_commande() TO service_role;
