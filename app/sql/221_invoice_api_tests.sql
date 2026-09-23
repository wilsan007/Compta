-- ============================================================
-- 221_invoice_api_tests.sql — R-12 : une facture créée par l'API a des lignes
--
-- Avant la 221, l'API publique insérait l'en-tête seul. Depuis la 190, une
-- facture sans ligne n'est ni validable ni approuvable : tout ce qu'une
-- intégration créait était une pièce inutilisable, découverte seulement en
-- essayant de la valider dans l'interface.
--
-- V01 — la facture créée par l'API porte ses lignes et est validable de bout en bout
-- V02 — sans ligne : refus explicite, AUCUNE pièce laissée derrière
-- V03 — les totaux viennent des lignes, jamais de la charge utile de l'appelant
-- V04 — la fonction n'est pas ouverte à un jeton utilisateur (authenticated)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '221', false);
DELETE FROM _audit_results WHERE file = '221';

-- Charge utile d'un appel d'intégration : deux lignes, taux différents
CREATE OR REPLACE FUNCTION _api221(p_t uuid, p_lines jsonb, p_annonce numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RETURN create_invoice_service(p_t, jsonb_build_object(
    'customer_id', (SELECT id FROM customers WHERE tenant_id = p_t LIMIT 1),
    'customer_name', 'Client API',
    'date', '2026-03-10',
    'due_date', '2026-04-09',
    'status', 'draft',
    'total', COALESCE(p_annonce, 1)   -- valeur annoncée par l'appelant, à écarter
  ), p_lines);
END $$;

DO $$
DECLARE t uuid; res jsonb; inv uuid; n_lines int; h record;
BEGIN
  BEGIN
    EXECUTE 'RESET ROLE';
    t := _mk_tenant('API221');
    PERFORM ensure_standard_journals(t);
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client API');

    -- V01 — deux lignes, la pièce est créée puis validée par les chemins réels.
    -- _mk_tenant a déjà posé le jeton de l'administrateur de cette société :
    -- c'est ce que fait l'application, et sans ce contexte RLS masquerait tout.
    res := _api221(t, '[{"description":"Prestation","quantity":2,"unit_price":100,"vat_rate":20},
                        {"description":"Fourniture","quantity":1,"unit_price":50,"vat_rate":10}]'::jsonb);
    inv := (res->>'invoice_id')::uuid;
    SELECT count(*) INTO n_lines FROM invoice_lines WHERE invoice_id = inv;
    PERFORM _as_user();
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT validation_status, number, subtotal, vat_total, total INTO h
    FROM invoices WHERE id = inv;
    PERFORM _rec('V01', 'facture API avec ses 2 lignes : validée et numérotée FAC-2026-000001, totaux 250 / 45 / 295',
      n_lines = 2 AND h.validation_status = 'validated' AND h.number = 'FAC-2026-000001'
        AND h.subtotal = 250 AND h.vat_total = 45 AND h.total = 295,
      format('lignes=%s statut=%s HT=%s TVA=%s TTC=%s numéro=%s',
             n_lines, h.validation_status, h.subtotal, h.vat_total, h.total, h.number));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V01', 'facture API avec ses 2 lignes : validée et numérotée FAC-2026-000001, totaux 250 / 45 / 295', false, SQLERRM); END;
END $$;

-- V02 — facture sans ligne : refus explicite, et rien n'est créé
DO $$
DECLARE t uuid; avant int; apres int; msg text;
BEGIN
  BEGIN
    EXECUTE 'RESET ROLE';
    t := _mk_tenant('API221B');
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client API B');
    SELECT count(*) INTO avant FROM invoices WHERE tenant_id = t;
    msg := '';
    BEGIN
      PERFORM _api221(t, '[]'::jsonb);
    EXCEPTION WHEN OTHERS THEN msg := SQLERRM; END;
    SELECT count(*) INTO apres FROM invoices WHERE tenant_id = t;
    PERFORM _rec('V02', 'aucune ligne fournie : refus explicite, aucune facture laissée derrière',
      msg LIKE '%Au moins une ligne%' AND apres = avant,
      format('refus=%s, factures avant=%s après=%s', msg, avant, apres));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V02', 'aucune ligne fournie : refus explicite, aucune facture laissée derrière', false, SQLERRM); END;
END $$;

-- V03 — les totaux annoncés par l'appelant sont écrasés par ceux des lignes
DO $$
DECLARE t uuid; res jsonb; h record;
BEGIN
  BEGIN
    EXECUTE 'RESET ROLE';
    t := _mk_tenant('API221C');
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client API C');
    res := _api221(t, '[{"description":"Prestation","quantity":1,"unit_price":100,"vat_rate":20}]'::jsonb, 9999);
    SELECT subtotal, vat_total, total INTO h FROM invoices WHERE id = (res->>'invoice_id')::uuid;
    PERFORM _rec('V03', 'total annoncé 9 999 ignoré : les totaux viennent des lignes (100 / 20 / 120)',
      h.subtotal = 100 AND h.vat_total = 20 AND h.total = 120,
      format('HT=%s TVA=%s TTC=%s (annoncé 9999)', h.subtotal, h.vat_total, h.total));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V03', 'total annoncé 9 999 ignoré : les totaux viennent des lignes (100 / 20 / 120)', false, SQLERRM); END;
END $$;

-- V04 — la porte est fermée aux jetons utilisateur : un client ne peut pas créer
-- une facture pour une autre société en appelant la fonction directement.
DO $$
BEGIN
  BEGIN
    PERFORM _rec('V04', 'create_invoice_service n''est pas exécutable par authenticated (service_role seul)',
      NOT has_function_privilege('authenticated', 'public.create_invoice_service(uuid, jsonb, jsonb)', 'EXECUTE')
        AND NOT has_function_privilege('anon', 'public.create_invoice_service(uuid, jsonb, jsonb)', 'EXECUTE')
        AND has_function_privilege('service_role', 'public.create_invoice_service(uuid, jsonb, jsonb)', 'EXECUTE'),
      'anon et authenticated révoqués, service_role conservé');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V04', 'create_invoice_service n''est pas exécutable par authenticated (service_role seul)', false, SQLERRM); END;
END $$;

DROP FUNCTION _api221(uuid, jsonb, numeric);

SELECT _audit_assert('221');