-- ═══════════════════════════════════════════════════════════════════════════
-- 752_chain_l23_automatisations_tests.sql — L23-b · automatisations
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : un événement émis DÉCLENCHE la règle ; l'action `chain.link`
--        pose le lien ; `automation_runs` porte `executed` ;
--   T02  IDEMPOTENCE (D1) : rejouer le MÊME événement ne repose rien
--        (`rules_run = 0`, une seule ligne d'exécution) ;
--   T03  SKIPPED : une règle aux `params` incomplets est tracée `skipped`, sans
--        casser l'événement ;
--   T04  FAILED : une action qui échoue (uuid invalide) est tracée `failed`
--        (`SQLERRM` conservée), la transaction métier survit ;
--   T05  ISOLATION (D8) : un événement de la société B ne joue PAS les règles de A.
--
-- D2 (concurrence) : l'unicité `(tenant, règle, événement)` de `automation_runs`
-- est le garde-fou (deux passages ne posent qu'une exécution) ; D3/D5 restent
-- hors de portée d'une suite d'un seul processus.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '752', false);
DELETE FROM _audit_results WHERE file = '752';

-- ── T01 — LE NOMINAL : l'événement déclenche la règle et le lien ───────────
DO $$
DECLARE t uuid; c uuid; inv uuid; pay uuid; ev bigint; n int; st text;
BEGIN
  t := _mk_tenant('T752A');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 752', 'C0752') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-752-1', c, '2026-03-06', '2026-04-05', 'sent', 100, 20, 120) RETURNING id INTO inv;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'RC-752-1', c, '2026-03-10', 120, 'transfer', 'recorded') RETURNING id INTO pay;
  INSERT INTO automation_rules (tenant_id, code, event_name, action_code, params)
    VALUES (t, 'R-752', 'invoices.validated', 'chain.link',
            jsonb_build_object('aval_type', 'customer_payments', 'aval_id', pay,
                               'effet', 'sale.invoice.paid', 'link_type', 'paid_by'));

  ev := emit_domain_event(t, 'invoices.validated', 'invoices', inv,
          jsonb_build_object('number', 'FA-752-1'), NULL);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'invoices' AND amont_id = inv
     AND aval_type = 'customer_payments' AND aval_id = pay
     AND effet = 'sale.invoice.paid' AND etat = 'actif';
  PERFORM _rec('T01a', 'l''événement émis a DÉCLENCHÉ la règle : le lien est posé', n = 1, 'liens actifs = ' || n);

  SELECT statut INTO st FROM automation_runs WHERE tenant_id = t AND event_id = ev;
  PERFORM _rec('T01b', 'l''exécution est tracée `executed`', st = 'executed', 'statut = ' || COALESCE(st, 'NULL'));
END $$;

-- ── T02 — IDEMPOTENCE (D1) : rejouer le même événement ne repose rien ──────
DO $$
DECLARE t uuid; c uuid; inv uuid; pay uuid; ev bigint; r jsonb; n int; runs int;
BEGIN
  t := _mk_tenant('T752B');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 752 B', 'C0752B') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-752-B', c, '2026-03-06', '2026-04-05', 'sent', 100, 20, 120) RETURNING id INTO inv;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'RC-752-B', c, '2026-03-11', 120, 'transfer', 'recorded') RETURNING id INTO pay;
  INSERT INTO automation_rules (tenant_id, code, event_name, action_code, params)
    VALUES (t, 'R-752-B', 'invoices.validated', 'chain.link',
            jsonb_build_object('aval_type', 'customer_payments', 'aval_id', pay,
                               'effet', 'sale.invoice.paid', 'link_type', 'paid_by'));

  ev := emit_domain_event(t, 'invoices.validated', 'invoices', inv, '{}'::jsonb, NULL);
  r := chain_l23_automatiser(ev);   -- rejeu du MÊME événement

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = inv AND aval_id = pay AND effet = 'sale.invoice.paid' AND etat = 'actif';
  PERFORM _rec('T02a', 'le rejeu ne pose AUCUN second lien', n = 1, 'liens = ' || n);

  SELECT count(*) INTO runs FROM automation_runs WHERE tenant_id = t AND event_id = ev;
  PERFORM _rec('T02b', 'une SEULE ligne d''exécution pour l''événement', runs = 1, 'runs = ' || runs);
  PERFORM _rec('T02c', 'le rejeu rend `rules_run = 0` (rien de neuf)', (r->>'rules_run')::int = 0, r::text);
END $$;

-- ── T03 — SKIPPED : paramètres incomplets ──────────────────────────────────
DO $$
DECLARE t uuid; ev bigint; st text; n int;
BEGIN
  t := _mk_tenant('T752C');
  INSERT INTO automation_rules (tenant_id, code, event_name, action_code, params)
    VALUES (t, 'R-752-C', 'invoices.validated', 'chain.link', jsonb_build_object('effet', 'sale.invoice.paid'));
  ev := emit_domain_event(t, 'invoices.validated', 'invoices', gen_random_uuid(), '{}'::jsonb, NULL);
  SELECT statut INTO st FROM automation_runs WHERE tenant_id = t AND event_id = ev;
  PERFORM _rec('T03a', 'une règle aux paramètres incomplets est tracée `skipped`, pas exécutée', st = 'skipped',
    'statut = ' || COALESCE(st, 'NULL'));
  SELECT count(*) INTO n FROM automation_runs WHERE tenant_id = t AND event_id = ev AND statut = 'executed';
  PERFORM _rec('T03b', 'aucune exécution pour cette règle', n = 0, 'exécutions = ' || n);
END $$;

-- ── T04 — FAILED : une action qui échoue est tracée, pas propagée ──────────
DO $$
DECLARE t uuid; ev bigint; st text; det text;
BEGIN
  t := _mk_tenant('T752D');
  INSERT INTO automation_rules (tenant_id, code, event_name, action_code, params)
    VALUES (t, 'R-752-D', 'invoices.validated', 'chain.link',
            jsonb_build_object('aval_type', 'customer_payments', 'aval_id', 'pas-un-uuid',
                               'effet', 'sale.invoice.paid'));
  ev := emit_domain_event(t, 'invoices.validated', 'invoices', gen_random_uuid(), '{}'::jsonb, NULL);
  SELECT statut, detail INTO st, det FROM automation_runs WHERE tenant_id = t AND event_id = ev;
  PERFORM _rec('T04a', 'une action qui échoue est tracée `failed` (la transaction métier survit)', st = 'failed',
    'statut = ' || COALESCE(st, 'NULL') || ' | ' || left(COALESCE(det, ''), 80));
END $$;

-- ── T05 — ISOLATION (D8) : l'événement de B ne joue pas les règles de A ─────
DO $$
DECLARE ta uuid; tb uuid; ra uuid; evb bigint; n int;
BEGIN
  ta := _mk_tenant('T752E1');
  INSERT INTO automation_rules (tenant_id, code, event_name, action_code, params)
    VALUES (ta, 'R-752-E1', 'invoices.validated', 'chain.link',
            jsonb_build_object('aval_type', 'customer_payments', 'aval_id', gen_random_uuid(),
                               'effet', 'sale.invoice.paid'))
    RETURNING id INTO ra;
  RESET ROLE;
  tb := _mk_tenant('T752E2');
  evb := emit_domain_event(tb, 'invoices.validated', 'invoices', gen_random_uuid(), '{}'::jsonb, NULL);

  SELECT count(*) INTO n FROM automation_runs WHERE rule_id = ra;
  PERFORM _rec('T05a', 'l''événement de B n''a PAS joué la règle de A', n = 0, 'exécutions de la règle de A = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM automation_runs WHERE event_id = evb AND tenant_id = tb;
  PERFORM _rec('T05b', 'aucune règle de B n''existe : l''événement ne trace rien', n = 0, 'runs de l''événement de B = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('752');
