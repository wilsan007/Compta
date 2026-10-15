-- ============================================================
-- 715_alertes_metier_abonnements_tests.sql — F.6 / NOT-02 :
--   LES ALERTES MÉTIER, DÉCLARÉES ET LIVRÉES
--
--   T01  RLS FORCED, 4 politiques, index de société (les 2 tables)
--   T02  `anon` n'a aucun droit
--   T03  les 3 commandes d'ÉCRITURE portent `can_perform`
--   T04  un LECTEUR ne crée pas de règle ; un admin en crée une
--   T05  CHECK alert_type et severity (hors liste refusé)
--   T06  CHECK conditions par type (le mauvais seuil est refusé)
--   T07  un abonnement pour un NON-MEMBRE est refusé (déclencheur)
--   T08  un membre ne s'abonne qu'UNE fois à une règle (unicité)
--   T09  le moteur ALERTE une facture échue au-dessus du seuil
--        (diffusion si aucun abonné — jamais un silence)
--   T10  le moteur livre à l'ABONNÉ (canal in_app)
--   T11  idempotence : le même jour, une règle ne notifie pas deux fois
--   T12  cloisonnement : la règle d'une autre société ne s'évalue pas
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '715', false);
DELETE FROM _audit_results WHERE file = '715';

-- T01 : RLS FORCED + 4 politiques + index de société
DO $$
DECLARE n bigint; v boolean;
BEGIN
  SELECT COUNT(*) INTO n FROM pg_policies
   WHERE tablename = 'business_alert_rules' AND schemaname = 'public';
  PERFORM _rec('T01a', 'business_alert_rules : 4 politiques', n = 4,
    format('politiques = %s (attendu 4)', n));

  SELECT COUNT(*) INTO n FROM pg_policies
   WHERE tablename = 'alert_subscriptions' AND schemaname = 'public';
  PERFORM _rec('T01b', 'alert_subscriptions : 4 politiques', n = 4,
    format('politiques = %s (attendu 4)', n));

  SELECT relforcerowsecurity INTO v FROM pg_class
   WHERE relname = 'business_alert_rules';
  PERFORM _rec('T01c', 'business_alert_rules : RLS FORCED', v, NULL);

  SELECT relforcerowsecurity INTO v FROM pg_class
   WHERE relname = 'alert_subscriptions';
  PERFORM _rec('T01d', 'alert_subscriptions : RLS FORCED', v, NULL);

  SELECT COUNT(*) INTO n FROM pg_indexes
   WHERE tablename = 'business_alert_rules' AND indexdef LIKE '%tenant_id%';
  PERFORM _rec('T01e', 'business_alert_rules : index tenant_id', n >= 1,
    format('index tenant_id = %s (attendu >= 1)', n));

  SELECT COUNT(*) INTO n FROM pg_indexes
   WHERE tablename = 'alert_subscriptions' AND indexdef LIKE '%tenant_id%';
  PERFORM _rec('T01f', 'alert_subscriptions : index tenant_id', n >= 1,
    format('index tenant_id = %s (attendu >= 1)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01a', 'RLS / politiques / index', false, SQLERRM);
END $$;

-- T02 : anon n'a aucun droit (statique — voir 713/714)
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM information_schema.role_table_grants
   WHERE table_name IN ('business_alert_rules', 'alert_subscriptions')
     AND grantee = 'anon';
  PERFORM _rec('T02', 'anon ne lit pas, n''écrit pas (0 droit sur les 2 tables)',
    n = 0, format('droits de table du visiteur = %s (attendu 0)', n));
END $$;

-- T03 : les 3 commandes d'écriture portent can_perform (les 2 tables)
DO $$
DECLARE n bigint;
BEGIN
  SELECT COUNT(*) INTO n FROM pg_policies
   WHERE tablename = 'business_alert_rules' AND cmd IN ('INSERT','UPDATE','DELETE')
     AND (COALESCE(qual,'') LIKE '%can_perform%'
          OR COALESCE(with_check,'') LIKE '%can_perform%');
  PERFORM _rec('T03a', 'business_alert_rules : 3 commandes portent can_perform',
    n = 3, format('commandes avec can_perform = %s (attendu 3)', n));

  SELECT COUNT(*) INTO n FROM pg_policies
   WHERE tablename = 'alert_subscriptions' AND cmd IN ('INSERT','UPDATE','DELETE')
     AND (COALESCE(qual,'') LIKE '%can_perform%'
          OR COALESCE(with_check,'') LIKE '%can_perform%');
  PERFORM _rec('T03b', 'alert_subscriptions : 3 commandes portent can_perform',
    n = 3, format('commandes avec can_perform = %s (attendu 3)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03a', 'can_perform', false, SQLERRM);
END $$;

-- Décor partagé pour T04→T08 : une société, un admin, un lecteur,
-- un autre membre. Recréé par DO bloc : isolé et rejouable.
-- T04 : lecteur ne crée pas de règle ; admin en crée une
DO $$
DECLARE
  ta uuid; aAdmin uuid; aLect uuid; v_ok boolean; n bigint;
BEGIN
  ta := _mk_tenant('F715A');
  SELECT auth_id INTO aAdmin FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;
  aLect := uuid_generate_v4();
  INSERT INTO auth.users (id, email) VALUES (aLect, 'lecteur715@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
    VALUES (ta, aLect, 'lecteur715@audit.test', 'Lecteur', 'viewer', 'active', now());

  -- LECTEUR : INSERT refusé
  PERFORM set_config('request.jwt.claim.sub', aLect::text, true);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', ta::text)::text, false);
  PERFORM _as_user();
  BEGIN
    INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
      VALUES (ta, 'Regle lecteur', 'invoice_overdue', '{"min_amount": 100}');
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T04a', 'LECTEUR ne cree pas de regle', v_ok, NULL);

  -- ADMIN : INSERT OK
  PERFORM set_config('request.jwt.claim.sub', aAdmin::text, true);
  BEGIN
    INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
      VALUES (ta, 'Regle admin', 'invoice_overdue', '{"min_amount": 100}');
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN v_ok := false;
  END;
  SELECT COUNT(*) INTO n FROM business_alert_rules WHERE tenant_id = ta;
  PERFORM _rec('T04b', 'ADMIN cree une regle', v_ok AND n = 1,
    format('insert ok = %s, regles = %s', v_ok, n));

  PERFORM set_config('request.jwt.claim.sub', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04a', 'lecteur/admin', false, SQLERRM);
END $$;

-- T05 : CHECK alert_type et severity (hors liste refusé)
DO $$
DECLARE
  ta uuid; aAdmin uuid; v_ok boolean;
BEGIN
  ta := _mk_tenant('F715B');
  SELECT auth_id INTO aAdmin FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', aAdmin::text, true);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', ta::text)::text, false);
  PERFORM _as_user();

  BEGIN
    INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
      VALUES (ta, 'Bad type', 'INVALID_TYPE', '{"min_amount": 1}');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T05a', 'CHECK alert_type refuse INVALID_TYPE', v_ok, NULL);

  BEGIN
    INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions, severity)
      VALUES (ta, 'Bad sev', 'invoice_overdue', '{"min_amount": 1}', 'URGENT');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T05b', 'CHECK severity refuse URGENT', v_ok, NULL);

  PERFORM set_config('request.jwt.claim.sub', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05a', 'CHECK alert_type / severity', false, SQLERRM);
END $$;

-- T06 : CHECK conditions par type — le mauvais seuil est refusé
DO $$
DECLARE
  ta uuid; aAdmin uuid; v_ok boolean;
BEGIN
  ta := _mk_tenant('F715C');
  SELECT auth_id INTO aAdmin FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', aAdmin::text, true);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', ta::text)::text, false);
  PERFORM _as_user();

  -- invoice_overdue SANS min_amount : refusé
  BEGIN
    INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
      VALUES (ta, 'Pas de seuil', 'invoice_overdue', '{}');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T06a', 'invoice_overdue SANS min_amount est refuse', v_ok, NULL);

  -- stock_below_threshold avec le seuil DU BON TYPE : accepté
  BEGIN
    INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
      VALUES (ta, 'Bon seuil stock', 'stock_below_threshold', '{"threshold": 5}');
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN v_ok := false;
  END;
  PERFORM _rec('T06b', 'stock_below_threshold avec threshold est accepte', v_ok, NULL);

  PERFORM set_config('request.jwt.claim.sub', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06a', 'CHECK conditions par type', false, SQLERRM);
END $$;

-- T07 : un abonnement pour un NON-MEMBRE est refusé (déclencheur 715)
DO $$
DECLARE ta uuid; r uuid; outsider uuid; v_ok boolean; v_detail text;
BEGIN
  ta := _mk_tenant('F715D');
  outsider := uuid_generate_v4();
  INSERT INTO auth.users (id, email) VALUES (outsider, 'outsider715@audit.test');
  INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
    VALUES (ta, 'Réglage T07', 'invoice_overdue', '{"min_amount": 100}')
    RETURNING id INTO r;
  BEGIN
    INSERT INTO alert_subscriptions (tenant_id, rule_id, user_id)
      VALUES (ta, r, outsider);
    v_ok := false; v_detail := 'l''abonnement non-membre a PASSÉ';
  EXCEPTION WHEN sqlstate '23514' THEN
    v_ok := true; v_detail := NULL;
  WHEN OTHERS THEN
    v_ok := false; v_detail := SQLERRM;
  END;
  PERFORM _rec('T07', 'un abonnement pour un NON-MEMBRE est refusé (déclencheur)',
    v_ok, v_detail);
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'un abonnement pour un NON-MEMBRE est refusé (déclencheur)',
    false, SQLERRM);
END $$;

-- T08 : un membre ne s'abonne qu'UNE fois à une règle (as_unique_rule_user)
DO $$
DECLARE ta uuid; r uuid; adm uuid; v_ok boolean; n int; v_detail text;
BEGIN
  ta := _mk_tenant('F715E');
  SELECT auth_id INTO adm FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;
  INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
    VALUES (ta, 'Réglage T08', 'stock_below_threshold', '{"threshold": 5}')
    RETURNING id INTO r;
  INSERT INTO alert_subscriptions (tenant_id, rule_id, user_id) VALUES (ta, r, adm);
  BEGIN
    INSERT INTO alert_subscriptions (tenant_id, rule_id, user_id) VALUES (ta, r, adm);
    v_ok := false; v_detail := 'le doublon a PASSÉ';
  EXCEPTION WHEN unique_violation THEN
    v_ok := true; v_detail := NULL;
  WHEN OTHERS THEN
    v_ok := false; v_detail := SQLERRM;
  END;
  SELECT count(*) INTO n FROM alert_subscriptions
   WHERE tenant_id = ta AND rule_id = r AND user_id = adm;
  PERFORM _rec('T08', 'un membre ne s''abonne qu''UNE fois à une règle (unicité)',
    v_ok AND n = 1,
    COALESCE(v_detail, format('doublon refusé = %s, abonnements = %s', v_ok, n)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'un membre ne s''abonne qu''UNE fois à une règle (unicité)',
    false, SQLERRM);
END $$;

-- T09 → T11 : le moteur — il ALERTE, il LIVRE à l'abonné, il ne se répète pas
DO $$
DECLARE ta uuid; r uuid; adm uuid; v_fired int; v_fired2 int; n1 int;
BEGIN
  ta := _mk_tenant('F715F');
  SELECT auth_id INTO adm FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;
  INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
    VALUES (ta, 'Retard client', 'invoice_overdue', '{"min_amount": 1000}')
    RETURNING id INTO r;
  INSERT INTO alert_subscriptions (tenant_id, rule_id, user_id) VALUES (ta, r, adm);
  INSERT INTO invoices (tenant_id, number, date, due_date, status,
                        subtotal, vat_total, total, amount_paid, amount_due,
                        customer_name)
    VALUES (ta, 'F715-001', '2026-01-01', '2026-02-01', 'sent',
            5000, 0, 5000, 0, 5000, 'Client T09');

  v_fired := evaluate_business_alert_rules(ta);
  SELECT count(*) INTO n1 FROM notifications
   WHERE tenant_id = ta AND metadata->>'alert_rule_id' = r::text;
  PERFORM _rec('T09', 'le moteur ALERTE une facture échue au-dessus du seuil',
    v_fired >= 1 AND n1 = 1,
    format('règles déclenchées = %s, notifications = %s', v_fired, n1));

  SELECT count(*) INTO n1 FROM notifications
   WHERE tenant_id = ta AND user_id = adm AND category = 'alert'
     AND metadata->>'alert_rule_id' = r::text;
  PERFORM _rec('T10', 'le moteur livre à l''ABONNÉ (canal in_app)',
    n1 = 1, format('notifications remises à l''abonné = %s (attendu 1)', n1));

  v_fired2 := evaluate_business_alert_rules(ta);
  SELECT count(*) INTO n1 FROM notifications
   WHERE tenant_id = ta AND metadata->>'alert_rule_id' = r::text;
  PERFORM _rec('T11', 'idempotence : le même jour, une règle ne notifie pas deux fois',
    v_fired2 = 0 AND n1 = 1,
    format('second appel : déclenchées = %s, notifications au total = %s', v_fired2, n1));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T09', 'le moteur ALERTE une facture échue au-dessus du seuil',
    false, SQLERRM);
END $$;

-- T12 : cloisonnement — la règle d'une société ne voit PAS l'autre société
DO $$
DECLARE ta uuid; nb uuid; rta uuid; rnb uuid; v_fired int; n1 int;
BEGIN
  ta := _mk_tenant('F715G');  -- règle ICI, aucune facture échue ici
  nb := _mk_tenant('F715H');  -- facture échue ICI, règle aussi ICI
  INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
    VALUES (ta, 'Réglage société A', 'invoice_overdue', '{"min_amount": 100}')
    RETURNING id INTO rta;
  INSERT INTO business_alert_rules (tenant_id, name, alert_type, conditions)
    VALUES (nb, 'Réglage société B', 'invoice_overdue', '{"min_amount": 100}')
    RETURNING id INTO rnb;
  INSERT INTO invoices (tenant_id, number, date, due_date, status,
                        subtotal, vat_total, total, amount_paid, amount_due,
                        customer_name)
    VALUES (nb, 'F715-002', '2026-01-01', '2026-02-01', 'sent',
            5000, 0, 5000, 0, 5000, 'Client T12');

  v_fired := evaluate_business_alert_rules(ta);
  SELECT count(*) INTO n1 FROM notifications
   WHERE metadata->>'alert_rule_id' IN (rta::text, rnb::text);
  PERFORM _rec('T12', 'la règle d''une société ne s''évalue pas sur une autre société',
    v_fired = 0 AND n1 = 0,
    format('déclenchées (A) = %s, notifications (A ou B) = %s — la facture échue est à B',
           v_fired, n1));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T12', 'la règle d''une société ne s''évalue pas sur une autre société',
    false, SQLERRM);
END $$;

-- Le VERDICT (G5 : toute suite rend un verdict). Ajouté le 13/10/2026 — la
-- suite ne se terminait pas par `_audit_assert`, et portait un `END $$;`
-- orphelin (le `END` du bloc T03 avait été perdu : erreur de syntaxe
-- « at or near DECLARE » mesurée au premier passage de cette suite).
SELECT _audit_assert('715');
