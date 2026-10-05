-- ============================================================
-- 470_purchase_payables_cash_forecast_tests.sql — tâche 2.17 :
--   UNE FACTURE D'ACHAT APPROUVÉE ET IMPAYÉE EST UN DÉCAISSEMENT
--   À VENIR
--
-- ⚠️ MESURÉ LE 05/10/2026, SUR BASE NEUVE (328 migrations, 0 erreur) :
--   `purchase_invoices_status_check` n'admet que draft | sent | viewed |
--   paid | overdue | cancelled, et l'approbation ne touche pas `status` :
--   une facture approuvée et impayée reste `draft / approved / not_paid`.
--   Or `cash_flow_forecast` — le SEUL moteur de prévision (420, 422) —
--   la cherchait sous `status IN ('received', 'overdue')` : `received`
--   n'existe pas, et rien ne pose `overdue` sur une facture d'achat. Les
--   sorties prévues valaient donc 0 quelle que soit la dette fournisseur.
--
-- Le critère, désormais (le même dans le moteur et dans ses lecteurs,
-- `getTreasuryDashboard` et `getTreasuryForecast`) :
--     approval_status = 'approved'  ET  status <> 'cancelled'
--     ET  amount_due > 0            — montant = amount_due
--
--   T01  approuvée, impayée, échéance à 20 jours → sortie prévue = son dû
--        (ROUGE avant : 0)
--   T02  NON approuvée (à approuver) → n'engage rien (non-régression)
--   T03  partiellement réglée → seul le RESTE DÛ sort (ROUGE avant : 0)
--   T04  soldée → ne sort plus (non-régression)
--   T05  l'horizon borne : échéance à 60 jours, absente à 30, présente
--        à 90 (ROUGE avant : absente à 90)
--   T06  l'isolation : la dette d'une société ne se lit pas d'une autre
--   T07  les clés de l'écran et les clés historiques disent le même
--        chiffre, et le net le retranche (ROUGE avant : 0 partout)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '470', false);
DELETE FROM _audit_results WHERE file = '470';

-- Facture fournisseur à une ligne de 100 HT + 20 de TVA = 120, en-tête
-- posé comme l'écran (brouillon, à approuver), approuvée si demandé.
-- Le décor est celui de la suite 192, l'échéance en plus.
CREATE OR REPLACE FUNCTION _l470_achat(p_t uuid, p_s uuid, p_echeance date, p_approve boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pi uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status,
                                 subtotal, vat_total, total, amount_paid, amount_due, approval_status)
  VALUES (p_t, 'FOURN-' || left(uuid_generate_v4()::text, 8), p_s, 'Fournisseur', CURRENT_DATE, p_echeance, 'draft',
          0, 0, 0, 0, 0, 'pending')
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  VALUES (p_t, pi, 'Achat', 1, 100, 20, 'FR20', 100, 20, 1);
  UPDATE purchase_invoices SET subtotal = 100, vat_total = 20, total = 120, amount_due = 120 WHERE id = pi;
  IF p_approve THEN UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi; END IF;
  RETURN pi;
END $$;

-- T01 — approuvée, impayée, à échéance future
DO $$
DECLARE t uuid := _mk_tenant('L470T01'); s uuid; pi uuid; r jsonb; v record;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur T01', 'F0001') RETURNING id INTO s;
  pi := _l470_achat(t, s, CURRENT_DATE + 20);
  SELECT status, approval_status, payment_state, amount_due INTO v FROM purchase_invoices WHERE id = pi;
  r := cash_flow_forecast(30);
  PERFORM _rec('T01', 'une facture d''achat approuvée, impayée, à échéance dans 20 jours est une sortie prévue de son reste dû',
    v.approval_status = 'approved' AND v.amount_due = 120 AND (r ->> 'expected_outflows')::numeric = 120,
    format('facture=%s/%s/%s dû=%s | sorties prévues=%s (120 attendu)', v.status, v.approval_status, v.payment_state, v.amount_due, r ->> 'expected_outflows'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'une facture d''achat approuvée et impayée est une sortie prévue', false, SQLERRM);
END $$;

-- T02 — non approuvée : rien n'est encore dû
DO $$
DECLARE t uuid := _mk_tenant('L470T02'); s uuid; pi uuid; r jsonb;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur T02', 'F0002') RETURNING id INTO s;
  pi := _l470_achat(t, s, CURRENT_DATE + 20, false);
  r := cash_flow_forecast(30);
  PERFORM _rec('T02', 'une facture d''achat encore à approuver n''engage aucune sortie',
    (r ->> 'expected_outflows')::numeric = 0,
    format('sorties prévues=%s (0 attendu)', r ->> 'expected_outflows'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'une facture d''achat encore à approuver n''engage aucune sortie', false, SQLERRM);
END $$;

-- T03 / T04 — le décaissement : le reste dû, puis plus rien
DO $$
DECLARE t uuid := _mk_tenant('L470T03'); s uuid; pi uuid; b uuid; r1 jsonb; r2 jsonb; due1 numeric; v record;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur T03', 'F0003') RETURNING id INTO s;
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque T03', 'chequing') RETURNING id INTO b;
  pi := _l470_achat(t, s, CURRENT_DATE + 20);
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method, bank_account_id)
  VALUES (t, 'DEC-T03-1', s, pi, CURRENT_DATE, 50, 'transfer', b);
  SELECT amount_due INTO due1 FROM purchase_invoices WHERE id = pi;
  r1 := cash_flow_forecast(30);
  PERFORM _rec('T03', 'une facture d''achat réglée de 50 sur 120 ne sort plus que pour son reste dû',
    due1 = 70 AND (r1 ->> 'expected_outflows')::numeric = 70,
    format('reste dû=%s | sorties prévues=%s (70 attendu)', due1, r1 ->> 'expected_outflows'));

  INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method, bank_account_id)
  VALUES (t, 'DEC-T03-2', s, pi, CURRENT_DATE, 70, 'transfer', b);
  SELECT status, amount_due INTO v FROM purchase_invoices WHERE id = pi;
  r2 := cash_flow_forecast(30);
  PERFORM _rec('T04', 'une facture d''achat soldée ne sort plus de la prévision',
    v.amount_due = 0 AND (r2 ->> 'expected_outflows')::numeric = 0,
    format('statut=%s reste dû=%s | sorties prévues=%s (0 attendu)', v.status, v.amount_due, r2 ->> 'expected_outflows'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'le reste dû d''une facture partiellement réglée, puis plus rien une fois soldée', false, SQLERRM);
END $$;

-- T05 — l'horizon
DO $$
DECLARE t uuid := _mk_tenant('L470T05'); s uuid; pi uuid; r30 jsonb; r90 jsonb;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur T05', 'F0005') RETURNING id INTO s;
  pi := _l470_achat(t, s, CURRENT_DATE + 60);
  r30 := cash_flow_forecast(30);
  r90 := cash_flow_forecast(90);
  PERFORM _rec('T05', 'l''horizon borne la sortie : une échéance à 60 jours est absente à 30 jours et présente à 90',
    (r30 ->> 'expected_outflows')::numeric = 0 AND (r90 ->> 'expected_outflows')::numeric = 120,
    format('à 30 j=%s (0 attendu) | à 90 j=%s (120 attendu)', r30 ->> 'expected_outflows', r90 ->> 'expected_outflows'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'l''horizon borne la sortie', false, SQLERRM);
END $$;

-- T06 — l'isolation : la société B ne lit pas la dette de la société A
DO $$
DECLARE ta uuid; tb uuid; s uuid; pi uuid; rb jsonb;
BEGIN
  ta := _mk_tenant('L470T06A');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (ta, 'Fournisseur T06', 'F0006') RETURNING id INTO s;
  pi := _l470_achat(ta, s, CURRENT_DATE + 20);
  tb := _mk_tenant('L470T06B');
  rb := cash_flow_forecast(30);
  PERFORM _rec('T06', 'la dette fournisseur d''une société ne sort pas dans la prévision d''une autre',
    current_tenant_id() = tb AND (rb ->> 'expected_outflows')::numeric = 0,
    format('société lue=%s | sorties prévues=%s (0 attendu)', CASE WHEN current_tenant_id() = tb THEN 'B' ELSE 'autre' END, rb ->> 'expected_outflows'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'la dette fournisseur d''une société ne sort pas dans la prévision d''une autre', false, SQLERRM);
END $$;

-- T07 — un seul chiffre sous ses deux noms, et le net le retranche
DO $$
DECLARE t uuid := _mk_tenant('L470T07'); s uuid; pi uuid; r jsonb;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur T07', 'F0007') RETURNING id INTO s;
  pi := _l470_achat(t, s, CURRENT_DATE + 20);
  r := cash_flow_forecast(30);
  PERFORM _rec('T07', 'la clé de l''écran (totalOutgoing) et la clé historique (expected_outflows) disent le même chiffre, et le net le retranche',
    (r ->> 'totalOutgoing')::numeric = 120 AND (r ->> 'expected_outflows')::numeric = 120
      AND (r ->> 'net_forecast')::numeric = -120 AND (r ->> 'net_with_production')::numeric = -120,
    format('totalOutgoing=%s expected_outflows=%s net_forecast=%s net_with_production=%s',
           r ->> 'totalOutgoing', r ->> 'expected_outflows', r ->> 'net_forecast', r ->> 'net_with_production'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'un seul chiffre sous ses deux noms, et le net le retranche', false, SQLERRM);
END $$;

DROP FUNCTION _l470_achat(uuid, uuid, date, boolean);
SELECT _audit_assert('470');
