-- ============================================================
-- 503_regle_ventes_devis_valide_tests.sql — partie B, lot Ventes, règle R-003
--
-- Ce que la règle R-003 garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  valider un devis au numéro de BROUILLON lui donne un numéro DÉFINITIF ;
--   T02  un devis validé REFUSE de changer de client (verrou d'en-tête) ;
--   T03  les LIGNES d'un devis validé sont GELÉES (modification refusée) ;
--   T04  NON-RÉGRESSION R-001 — accepter un devis VALIDÉ crée quand même sa commande
--        (le verrou ne porte pas sur la transformation).
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '503', false);
DELETE FROM _audit_results WHERE file = '503';

-- Société isolée : un devis « envoyé » (numéro paramétré) et une ligne (2 × 100 @20).
CREATE OR REPLACE FUNCTION _b503(p_nom text, p_num text, OUT t uuid, OUT c uuid, OUT q uuid, OUT ql uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, date, expiry_date, status, validation_status)
    VALUES (t, p_num, c, '2026-03-10', '2026-04-10', 'sent', 'draft') RETURNING id INTO q;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, line_order)
    VALUES (t, q, 'Ligne ' || p_nom, 2, 100, 20, 0) RETURNING id INTO ql;
END $$;

-- ── T01 : validation → numéro définitif ─────────────────────────
DO $$
DECLARE v record; v_num text;
BEGIN
  v := _b503('T01', 'BROUILLON-DEV-T01');
  PERFORM _as_user();
  UPDATE quotes SET validation_status = 'validated' WHERE id = v.q;
  SELECT number INTO v_num FROM quotes WHERE id = v.q;
  PERFORM _rec('T01', 'la validation remplace le numéro de brouillon par un numéro définitif',
    v_num NOT LIKE 'BROUILLON-%' AND v_num IS NOT NULL, format('numéro=%s', v_num));
END $$;

-- ── T04 : non-régression R-001 — la transformation reste possible ──
DO $$
DECLARE v record; n int;
BEGIN
  v := _b503('T04', 'DEV-2026-000404');
  PERFORM _as_user();
  UPDATE quotes SET validation_status = 'validated' WHERE id = v.q;
  UPDATE quotes SET status = 'accepted' WHERE id = v.q;   -- R-001 doit encore agir
  SELECT count(*) INTO n FROM sales_orders WHERE tenant_id = v.t AND quote_id = v.q;
  PERFORM _rec('T04', 'accepter un devis validé crée quand même sa commande (R-001 préservée)',
    n = 1, format('commandes=%s (1 attendue)', n));
END $$;

-- ── T02 : verrou d'en-tête ──────────────────────────────────────
DO $$
DECLARE v record; refuse boolean := false;
BEGIN
  v := _b503('T02', 'DEV-2026-000502');
  PERFORM _as_user();
  UPDATE quotes SET validation_status = 'validated' WHERE id = v.q;
  BEGIN
    UPDATE quotes SET customer_id = NULL WHERE id = v.q;
  EXCEPTION WHEN check_violation THEN refuse := true;
  END;
  PERFORM _rec('T02', 'un devis validé refuse de changer de client',
    refuse, format('refus=%s (true attendu)', refuse));
END $$;

-- ── T03 : les lignes d'un devis validé sont gelées ──────────────
DO $$
DECLARE v record; refuse boolean := false;
BEGIN
  v := _b503('T03', 'DEV-2026-000503');
  PERFORM _as_user();
  UPDATE quotes SET validation_status = 'validated' WHERE id = v.q;
  BEGIN
    UPDATE quote_lines SET quantity = 99 WHERE id = v.ql;
  EXCEPTION WHEN check_violation THEN refuse := true;
  END;
  PERFORM _rec('T03', 'une ligne de devis validé ne se modifie plus',
    refuse, format('refus=%s (true attendu)', refuse));
END $$;

SELECT _audit_assert('503');