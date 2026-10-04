-- ============================================================
-- 227_tenant_guard_tests.sql — agir au nom d'une autre société
--
-- Même défaut que celui du versement de la paie (224), trouvé cette fois par
-- ci/check_tenant_guard.sql : une fonction SECURITY DEFINER exposée à
-- `authenticated` reçoit un identifiant du client, retrouve la ligne sans filtre
-- de société, puis travaille dans la société de cette ligne.
--
-- Mesuré avant la 227, sur base neuve : le client importé de l'autre société
-- était RÉELLEMENT supprimé (T01), son lot passait à « validé » (T02) et une
-- écriture comptable naissait dans ses livres (T04).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '227', false);
DELETE FROM _audit_results WHERE file = '227';

-- Lot d'import de clients, avec un client qui en est issu
CREATE OR REPLACE FUNCTION _mk_batch227(t uuid, p_nom text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE b uuid;
BEGIN
  INSERT INTO import_batches (tenant_id, target_table, file_name, total_rows, valid_rows, invalid_rows, status)
  VALUES (t, 'customers', p_nom || '.csv', 1, 1, 0, 'pending') RETURNING id INTO b;
  INSERT INTO customers (tenant_id, name, import_batch_id) VALUES (t, 'Client ' || p_nom, b);
  RETURN b;
END $$;

-- T01 : annuler le lot d'import d'une autre société — la fonction SUPPRIME des clients
DO $$
DECLARE tb uuid; ta uuid; b uuid; refuse boolean := false; err text := '—'; n int; st text;
BEGIN
  tb := _mk_tenant('T01B');
  b := _mk_batch227(tb, 'T01B');
  ta := _mk_tenant('T01A');                       -- le contexte bascule sur la société A
  PERFORM _as_user();
  BEGIN
    PERFORM cancel_import_batch(b);
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);   -- constater sans RLS
  SELECT count(*) INTO n FROM customers WHERE tenant_id = tb AND import_batch_id = b;
  SELECT status INTO st FROM import_batches WHERE id = b;
  PERFORM _rec('T01', 'annuler le lot d''import d''une autre société : refusé, ses clients ne sont pas supprimés',
    refuse AND n = 1 AND st = 'pending',
    format('refus=%s clients restants chez B=%s (1 attendu) statut du lot=%s | %s', refuse, n, st, left(err, 80)));
END $$;

-- T02 : valider le lot d'import d'une autre société
DO $$
DECLARE tb uuid; ta uuid; b uuid; refuse boolean := false; err text := '—'; st text;
BEGIN
  tb := _mk_tenant('T02B');
  b := _mk_batch227(tb, 'T02B');
  ta := _mk_tenant('T02A');
  PERFORM _as_user();
  BEGIN
    PERFORM validate_import_batch(b);
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT status INTO st FROM import_batches WHERE id = b;
  PERFORM _rec('T02', 'valider le lot d''import d''une autre société : refusé, son statut ne bouge pas',
    refuse AND st = 'pending',
    format('refus=%s statut=%s (pending attendu) | %s', refuse, st, left(err, 80)));
END $$;

-- T03 : rapprochement à trois voies sur la facture fournisseur d'une autre société.
--       La fonction RETOURNE le rapprochement (montants commandés, reçus,
--       facturés) : le défaut est d'abord une fuite. La facture est laissée « à
--       approuver », sinon c'est le trigger d'immuabilité qui refuse l'écriture
--       et le scénario passerait au vert sans rien prouver.
DO $$
DECLARE tb uuid; ta uuid; s uuid; p uuid; inv uuid;
        refuse boolean := false; err text := '—'; n int := 0; st text;
BEGIN
  tb := _mk_tenant('T03B');
  INSERT INTO suppliers (tenant_id, name) VALUES (tb, 'Fournisseur T03') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (tb, 'Article T03', 'T03-1', 'stock') RETURNING id INTO p;
  PERFORM _as_user();
  INSERT INTO purchase_invoices (tenant_id, supplier_id, supplier_name, number, date, due_date, status)
  VALUES (tb, s, 'Fournisseur T03', 'FA-T03', '2026-03-01', '2026-03-31', 'draft') RETURNING id INTO inv;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, product_id, description, quantity, unit_price, vat_rate, line_order)
  VALUES (tb, inv, p, 'Ligne 1', 1, 100, 0, 0);

  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('T03A');
  PERFORM _as_user();
  BEGIN
    SELECT count(*) INTO n FROM run_three_way_match(inv);
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT approval_status INTO st FROM purchase_invoices WHERE id = inv;
  PERFORM _rec('T03', 'rapprocher la facture fournisseur d''une autre société : refusé, aucun montant rendu',
    refuse AND n = 0,
    format('refus=%s lignes rendues=%s (0 attendue) approbation=%s | %s', refuse, n, st, left(err, 70)));
END $$;

-- T04 : écriture récurrente — la société passée en paramètre l'emportait sur
--       celle de l'appelant (COALESCE(p_tenant_id, current_tenant_id()))
DO $$
DECLARE tb uuid; ta uuid; e uuid; refuse boolean := false; err text := '—'; n int;
BEGIN
  tb := _mk_tenant('T04B');
  PERFORM _as_user();
  e := _entry(tb, 'REC-T04', DATE '2026-03-01',
    '[{"a":"606000","d":100,"c":0},{"a":"401000","d":0,"c":100}]'::jsonb, true);
  PERFORM set_config('role', 'postgres', true);
  ta := _mk_tenant('T04A');
  PERFORM _as_user();
  BEGIN
    PERFORM generate_recurring_entry(e, tb);      -- la société de B, passée en paramètre
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = tb AND description LIKE '[Récurrent]%';
  PERFORM _rec('T04', 'écriture récurrente : la société passée en paramètre n''écrase plus celle de l''appelant',
    n = 0, format('refus=%s écritures récurrentes créées chez B=%s (0 attendue) | %s', refuse, n, left(err, 80)));
END $$;

-- T05 : non-régression — dans sa propre société, tout fonctionne comme avant
DO $$
DECLARE t uuid; b1 uuid; b2 uuid; n int; st text; err text := '—';
BEGIN
  t := _mk_tenant('T05');
  b1 := _mk_batch227(t, 'T05a');
  b2 := _mk_batch227(t, 'T05b');
  PERFORM _as_user();
  BEGIN
    PERFORM cancel_import_batch(b1);
    PERFORM validate_import_batch(b2);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT count(*) INTO n FROM customers WHERE tenant_id = t AND import_batch_id = b1;
  SELECT string_agg(status, '/' ORDER BY status) INTO st FROM import_batches WHERE id IN (b1, b2);
  PERFORM _rec('T05', 'dans sa propre société : le lot s''annule (client supprimé) et l''autre se valide',
    n = 0 AND st = 'cancelled/validated',
    format('clients restants=%s statuts=%s | %s', n, st, left(err, 80)));
END $$;

DROP FUNCTION _mk_batch227(uuid, text);
SELECT _audit_assert('227');
