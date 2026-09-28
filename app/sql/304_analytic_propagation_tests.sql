-- ============================================================
-- 304_analytic_propagation_tests.sql — W7 (M-05) : l'analytique circule
--
--   ANA-01 🟠 Les **deux** déclencheurs analytiques de `journal_lines` sont
--             vides : deux appels de fonction par ligne d'écriture pour zéro
--             effet. `propagate_analytic_section` (158) ne fait que `RETURN NEW`,
--             et `check_analytic_balance` (124) n'a qu'un `IF` commenté.
--   ANA-02 🔴 `analytic_section_id` n'est écrit que par `post_journal_entry`, donc
--             par la **saisie manuelle** : aucune écriture produite par les
--             ventes, les achats, la paie, le stock, la caisse ou la production
--             ne porte de section. L'exigence « balance analytique = balance
--             générale sur les classes 6 et 7 » ne peut pas être satisfaite.
--   ANA-03 🟠 La balance analytique porte sur **tout l'historique** : aucun
--             exercice, aucune période.
--
-- Ce fichier prouve la circulation : une section posée sur une **ligne de
-- document** (facture de vente, facture d'achat) se retrouve sur la **ligne
-- d'écriture** engendrée ; une ventilation multi-axes se traduit en section
-- (ANA-01) et une ventilation qui ne fait pas 100 % est refusée.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '304', false);
DELETE FROM _audit_results WHERE file = '304';

DROP FUNCTION IF EXISTS _ana304_section(uuid, text);
CREATE OR REPLACE FUNCTION _ana304_section(p_t uuid, p_code text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; pl uuid;
BEGIN
  SELECT id INTO pl FROM analytic_plans WHERE tenant_id = p_t LIMIT 1;
  IF pl IS NULL THEN
    INSERT INTO analytic_plans (tenant_id, code, name) VALUES (p_t, 'AX-' || p_code, 'Plan ' || p_code)
      RETURNING id INTO pl;
  END IF;
  INSERT INTO analytic_sections (tenant_id, plan_id, code, name, axis, level)
    VALUES (p_t, pl, p_code, 'Section ' || p_code, 1, 1)
    ON CONFLICT DO NOTHING;
  SELECT id INTO v FROM analytic_sections WHERE tenant_id = p_t AND code = p_code LIMIT 1;
  RETURN v;
END $$;

DROP FUNCTION IF EXISTS _ana304_vente(uuid, uuid, uuid);
CREATE OR REPLACE FUNCTION _ana304_vente(p_t uuid, p_c uuid, p_section uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date,
                        status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (p_t, 'FAC-' || left(uuid_generate_v4()::text, 8), p_c, 'Client', CURRENT_DATE,
          CURRENT_DATE + 30, 'draft', 0, 0, 0, 0, 0)
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price,
                             vat_rate, vat_code, analytic_section_id, line_order)
  VALUES (p_t, inv, 'Prestation', 1, 1000, 20, 'FR20', p_section, 1);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  RETURN inv;
END $$;

DROP FUNCTION IF EXISTS _ana304_achat(uuid, uuid, uuid);
CREATE OR REPLACE FUNCTION _ana304_achat(p_t uuid, p_s uuid, p_section uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pi uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date,
                                 status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
  VALUES (p_t, 'FRN-' || left(uuid_generate_v4()::text, 8), p_s, 'Fournisseur', CURRENT_DATE,
          CURRENT_DATE + 30, 'draft', 0, 0, 0, 0, 0, 'pending')
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity,
                                      unit_price, vat_rate, vat_code, analytic_section_id, line_order)
  VALUES (p_t, pi, 'Achat', 1, 500, 20, 'FR20', p_section, 1);
  UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
  RETURN pi;
END $$;

-- T01 — ANA-02 (ventes) : une section posée sur la ligne de facture se retrouve
-- sur la ligne d'écriture de produit engendrée par la validation.
DO $$
DECLARE t uuid; c uuid; s uuid; n int; sec uuid;
BEGIN
  t := _mk_tenant('ANA01');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ANA') RETURNING id INTO c;
  s := _ana304_section(t, 'S-VENTE');
  PERFORM _as_user();
  BEGIN
    PERFORM _ana304_vente(t, c, s);
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) INTO n FROM journal_lines l
      JOIN journal_entries e ON e.id = l.journal_id AND e.tenant_id = l.tenant_id
      WHERE l.tenant_id = t AND e.journal_code = 'VT' AND l.account_code = '707000' AND l.analytic_section_id = s;
    PERFORM _rec('T01', 'une facture de vente dont la ligne porte une section produit une ligne d''écriture qui la porte',
      n = 1, format('lignes 707000 portant la section=%s (1 attendue)', n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T01', 'une facture de vente dont la ligne porte une section produit une ligne d''écriture qui la porte', false, SQLERRM);
  END;
END $$;

-- T02 — ANA-02 (achats) : même chose du côté fournisseur (compte de charge).
DO $$
DECLARE t uuid; s2 uuid; sec uuid; n int; ing uuid;
BEGIN
  t := _mk_tenant('ANA02');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur ANA', 'F0001') RETURNING id INTO ing;
  sec := _ana304_section(t, 'S-ACHAT');
  PERFORM _as_user();
  BEGIN
    PERFORM _ana304_achat(t, ing, sec);
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) INTO n FROM journal_lines l
      JOIN journal_entries e ON e.id = l.journal_id AND e.tenant_id = l.tenant_id
      WHERE l.tenant_id = t AND e.journal_code = 'AC' AND l.account_code = '607000' AND l.analytic_section_id = sec;
    PERFORM _rec('T02', 'une facture d''achat dont la ligne porte une section produit une ligne d''écriture qui la porte',
      n = 1, format('lignes 607000 portant la section=%s (1 attendue)', n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T02', 'une facture d''achat dont la ligne porte une section produit une ligne d''écriture qui la porte', false, SQLERRM);
  END;
END $$;

-- T03 — ANA-01 : une ventilation multi-axes (`analytic_distribution`) se traduit
-- sur la ligne : la section et le montant analytique en sont dérivés.
DO $$
DECLARE t uuid; sec uuid; pl uuid; e uuid; l uuid; v_sec uuid; v_mnt numeric;
BEGIN
  t := _mk_tenant('ANA03');
  sec := _ana304_section(t, 'S-DIST');
  SELECT plan_id INTO pl FROM analytic_sections WHERE id = sec;
  PERFORM _as_user();
  BEGIN
    e := _entry(t, 'OD-ANA-01', CURRENT_DATE,
      '[{"a":"607000","d":200,"c":0}]'::jsonb, false);
    UPDATE journal_lines SET analytic_distribution = jsonb_build_object(pl::text, jsonb_build_object(sec::text, 100))
      WHERE journal_id = e;
    PERFORM set_config('role', 'postgres', true);
    SELECT analytic_section_id, analytic_amount INTO v_sec, v_mnt
      FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('T03', 'une ventilation à 100 % pose la section et le montant analytique sur la ligne',
      v_sec = sec AND v_mnt = 200,
      format('section dérivée=%s (attendu %s) montant analytique=%s (200 attendu)', v_sec, sec, v_mnt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T03', 'une ventilation à 100 % pose la section et le montant analytique sur la ligne', false, SQLERRM);
  END;
END $$;

-- T04 — ANA-01 : une ventilation qui ne fait pas 100 % est refusée (la règle
-- que `validateDistribution` applique déjà côté écran, désormais tenue par la base).
DO $$
DECLARE t uuid; sec uuid; pl uuid; e uuid; refuse boolean := false; err text := '—';
BEGIN
  t := _mk_tenant('ANA04');
  sec := _ana304_section(t, 'S-60');
  SELECT plan_id INTO pl FROM analytic_sections WHERE id = sec;
  PERFORM _as_user();
  BEGIN
    e := _entry(t, 'OD-ANA-02', CURRENT_DATE, '[{"a":"607000","d":100,"c":0}]'::jsonb, false);
    UPDATE journal_lines SET analytic_distribution = jsonb_build_object(pl::text, jsonb_build_object(sec::text, 60))
      WHERE journal_id = e;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T04', 'une ventilation analytique qui ne fait pas 100 % est refusée',
    refuse, format('refus=%s | %s', refuse, left(err, 100)));
END $$;

-- T05 — non-régression : une ligne sans ventilation n'est pas touchée (aucune
-- section, aucun montant analytique), et la base ne refuse rien.
DO $$
DECLARE t uuid; e uuid; v_sec uuid; v_mnt numeric; ok boolean := true; err text := '—';
BEGIN
  t := _mk_tenant('ANA05');
  PERFORM _as_user();
  BEGIN
    e := _entry(t, 'OD-ANA-03', CURRENT_DATE,
      '[{"a":"607000","d":50,"c":0},{"a":"401000","d":0,"c":50}]'::jsonb, true);
  EXCEPTION WHEN OTHERS THEN ok := false; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT analytic_section_id, analytic_amount INTO v_sec, v_mnt FROM journal_lines WHERE journal_id = e;
  PERFORM _rec('T05', 'une ligne sans ventilation reste sans section et sans montant analytique',
    ok AND v_sec IS NULL AND COALESCE(v_mnt, 0) = 0,
    format('écriture acceptée=%s section=%s montant analytique=%s | %s', ok, v_sec, COALESCE(v_mnt, 0), left(err, 60)));
END $$;

DROP FUNCTION _ana304_achat(uuid, uuid, uuid);
DROP FUNCTION _ana304_vente(uuid, uuid, uuid);
DROP FUNCTION _ana304_section(uuid, text);
SELECT _audit_assert('304');

