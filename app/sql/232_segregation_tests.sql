-- ============================================================
-- 232_segregation_tests.sql — H06 : la séparation des tâches
--
-- Le plan demandait un scénario « avec enforce_segregation, l'auteur d'une
-- écriture ne peut pas la valider ». En l'écrivant, le contrôle s'est révélé
-- inopérant : `journal_entries.created_by` n'est JAMAIS renseigné (aucun
-- défaut de colonne, aucun trigger, `post_journal_entry` ne l'écrit pas), et
-- `check_segregation_of_duties` rend `true` dès que l'auteur est inconnu.
-- `validated_by` et `validated_at` ne sont pas davantage écrits : ni l'auteur
-- ni le valideur d'une écriture ne sont enregistrés nulle part.
--
-- T01, T02, T03 et T05 ont été vus ROUGES avant la 232.
--
-- Périmètre (décision D-13) : la séparation porte sur les écritures SAISIES à
-- la main. Les écritures produites par un document (vente, achat, paie) sont
-- couvertes par la validation du document lui-même — les bloquer rendrait la
-- facturation impossible dès que l'option est activée (T07).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '232', false);
DELETE FROM _audit_results WHERE file = '232';

CREATE OR REPLACE FUNCTION _user232(p_tenant uuid, p_email text, p_role text DEFAULT 'admin')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a uuid := uuid_generate_v4();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (a, p_email);
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
  VALUES (p_tenant, a, p_email, p_email, p_role, 'active');
  RETURN a;
END $$;

CREATE OR REPLACE FUNCTION _as232(p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END $$;

-- Deux lignes équilibrées, sur des comptes du plan semé
CREATE OR REPLACE FUNCTION _lignes232() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_array(
    jsonb_build_object('account_code', '512000', 'debit', 100, 'credit', 0, 'description', 'H06'),
    jsonb_build_object('account_code', '706000', 'debit', 0, 'credit', 100, 'description', 'H06'))
$$;

-- T01 : l'auteur d'une écriture saisie est enregistré
DO $$
DECLARE t uuid; ua uuid; r jsonb; e uuid; v_auteur uuid; err text := '—';
BEGIN
  t := _mk_tenant('T01SEG');
  ua := _user232(t, 't01seg-a@seg.test');
  PERFORM _as232(ua);
  BEGIN
    r := post_journal_entry(jsonb_build_object('date', '2026-03-01', 'journal_code', 'OD',
           'description', 'T01', 'status', 'draft'), _lignes232());
    e := (r ->> 'entry_id')::uuid;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT created_by INTO v_auteur FROM journal_entries WHERE id = e;
  PERFORM _rec('T01', 'une écriture saisie garde le nom de son auteur',
    v_auteur IS NOT DISTINCT FROM ua,
    format('created_by=%s attendu=%s | %s', coalesce(v_auteur::text, 'NULL'), ua, left(err, 80)));
END $$;

-- T02 : le valideur et la date de validation sont enregistrés
DO $$
DECLARE t uuid; ua uuid; ub uuid; r jsonb; e uuid; v_val uuid; v_date timestamptz; err text := '—';
BEGIN
  t := _mk_tenant('T02SEG');
  ua := _user232(t, 't02seg-a@seg.test');
  ub := _user232(t, 't02seg-b@seg.test');
  PERFORM _as232(ua);
  r := post_journal_entry(jsonb_build_object('date', '2026-03-01', 'journal_code', 'OD',
         'description', 'T02', 'status', 'draft'), _lignes232());
  e := (r ->> 'entry_id')::uuid;
  PERFORM _as232(ub);
  BEGIN
    UPDATE journal_entries SET status = 'posted' WHERE id = e;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT validated_by, validated_at INTO v_val, v_date FROM journal_entries WHERE id = e;
  PERFORM _rec('T02', 'une écriture validée garde le nom de son valideur et la date',
    v_val IS NOT DISTINCT FROM ub AND v_date IS NOT NULL,
    format('validated_by=%s attendu=%s date=%s | %s', coalesce(v_val::text, 'NULL'), ub,
           coalesce(v_date::text, 'NULL'), left(err, 80)));
END $$;

-- T03 : séparation active — l'auteur ne valide pas son écriture
DO $$
DECLARE t uuid; ua uuid; r jsonb; e uuid; refuse boolean := false; st text; err text := '—';
BEGIN
  t := _mk_tenant('T03SEG');
  ua := _user232(t, 't03seg-a@seg.test');
  UPDATE company_settings SET enforce_segregation = true WHERE tenant_id = t;
  PERFORM _as232(ua);
  r := post_journal_entry(jsonb_build_object('date', '2026-03-01', 'journal_code', 'OD',
         'description', 'T03', 'status', 'draft'), _lignes232());
  e := (r ->> 'entry_id')::uuid;
  BEGIN
    UPDATE journal_entries SET status = 'posted' WHERE id = e;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT status INTO st FROM journal_entries WHERE id = e;
  PERFORM _rec('T03', 'séparation active : l''auteur ne peut pas valider sa propre écriture',
    refuse AND st = 'draft', format('refus=%s statut=%s | %s', refuse, st, left(err, 90)));
END $$;

-- T04 : séparation active — quelqu'un d'autre valide, et cela passe
DO $$
DECLARE t uuid; ua uuid; ub uuid; r jsonb; e uuid; st text; err text := '—';
BEGIN
  t := _mk_tenant('T04SEG');
  ua := _user232(t, 't04seg-a@seg.test');
  ub := _user232(t, 't04seg-b@seg.test');
  UPDATE company_settings SET enforce_segregation = true WHERE tenant_id = t;
  PERFORM _as232(ua);
  r := post_journal_entry(jsonb_build_object('date', '2026-03-01', 'journal_code', 'OD',
         'description', 'T04', 'status', 'draft'), _lignes232());
  e := (r ->> 'entry_id')::uuid;
  PERFORM _as232(ub);
  BEGIN
    UPDATE journal_entries SET status = 'posted' WHERE id = e;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT status INTO st FROM journal_entries WHERE id = e;
  PERFORM _rec('T04', 'séparation active : un autre utilisateur valide l''écriture',
    st = 'posted', format('statut=%s | %s', st, left(err, 90)));
END $$;

-- T05 : séparation active — saisir et valider d'un seul geste est refusé
--       (sans quoi la règle se contourne en cochant « comptabilisée » à la saisie)
DO $$
DECLARE t uuid; ua uuid; r jsonb; refuse boolean := false; n int; err text := '—';
BEGIN
  t := _mk_tenant('T05SEG');
  ua := _user232(t, 't05seg-a@seg.test');
  UPDATE company_settings SET enforce_segregation = true WHERE tenant_id = t;
  PERFORM _as232(ua);
  BEGIN
    -- post_journal_entry rattrape ses erreurs et rend { success: false } :
    -- le refus se lit dans la réponse, pas dans une exception SQL.
    r := post_journal_entry(jsonb_build_object('date', '2026-03-01', 'journal_code', 'OD',
      'description', 'T05', 'status', 'posted'), _lignes232());
    refuse := NOT COALESCE((r ->> 'success')::boolean, false);
    err := COALESCE(r ->> 'error', '—');
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND status = 'posted';
  PERFORM _rec('T05', 'séparation active : saisir et valider d''un seul geste est refusé, et le message le dit',
    refuse AND n = 0 AND err ~* 'séparation', format('refus=%s écritures validées=%s | %s', refuse, n, left(err, 90)));
END $$;

-- T06 : non-régression — séparation inactive (le défaut), l'auteur valide sans entrave
DO $$
DECLARE t uuid; ua uuid; r jsonb; n int; err text := '—';
BEGIN
  t := _mk_tenant('T06SEG');
  ua := _user232(t, 't06seg-a@seg.test');
  PERFORM _as232(ua);
  BEGIN
    r := post_journal_entry(jsonb_build_object('date', '2026-03-01', 'journal_code', 'OD',
           'description', 'T06', 'status', 'posted'), _lignes232());
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND status = 'posted';
  PERFORM _rec('T06', 'séparation inactive : l''auteur saisit et valide comme avant',
    n = 1, format('écritures validées=%s (1 attendue) | %s', n, left(err, 90)));
END $$;

-- T07 : non-régression — séparation active, la facture produit toujours son écriture
--       (D-13 : le document porte sa propre validation)
DO $$
DECLARE t uuid; ua uuid; c uuid; r jsonb; inv uuid; n int; err text := '—';
BEGIN
  t := _mk_tenant('T07SEG');
  ua := _user232(t, 't07seg-a@seg.test');
  UPDATE company_settings SET enforce_segregation = true WHERE tenant_id = t;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client T07') RETURNING id INTO c;
  PERFORM _as232(ua);
  BEGIN
    r := create_invoice_atomic(
      jsonb_build_object('customer_id', c, 'date', '2026-03-01', 'due_date', '2026-03-31', 'status', 'draft'),
      jsonb_build_array(jsonb_build_object('description', 'P', 'quantity', 1, 'unit_price', 100, 'vat_rate', 20)));
    inv := (r ->> 'invoice_id')::uuid;
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND journal_code = 'VT' AND status = 'posted';
  PERFORM _rec('T07', 'séparation active : la validation d''une facture produit toujours son écriture',
    n = 1, format('écritures VT validées=%s (1 attendue) | %s', n, left(err, 110)));
END $$;

-- T08 : le drapeau « saisie » ne s'éteint pas depuis le client — ni à l'insertion,
--       ni par une mise à jour avant validation
DO $$
DECLARE t uuid; ua uuid; e uuid; v_manual boolean; refuse boolean := false; st text; err text := '—';
BEGIN
  t := _mk_tenant('T08SEG');
  ua := _user232(t, 't08seg-a@seg.test');
  UPDATE company_settings SET enforce_segregation = true WHERE tenant_id = t;
  PERFORM _as232(ua);
  -- insertion directe en prétendant que l'écriture est automatique
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, is_manual)
  VALUES (t, 'T08-DIRECT', '2026-03-01', 'OD', 'draft', 'T08', false) RETURNING id INTO e;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description)
  VALUES (t, e, '512000', '512000', 100, 0, 'T08'), (t, e, '706000', '706000', 0, 100, 'T08');
  -- puis en tentant de l'éteindre par une mise à jour
  UPDATE journal_entries SET is_manual = false WHERE id = e;
  BEGIN
    UPDATE journal_entries SET status = 'posted' WHERE id = e;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT is_manual, status INTO v_manual, st FROM journal_entries WHERE id = e;
  PERFORM _rec('T08', 'le drapeau « saisie » est calculé, pas accepté du client',
    v_manual AND refuse AND st = 'draft',
    format('is_manual=%s refus=%s statut=%s | %s', v_manual, refuse, st, left(err, 80)));
END $$;

DROP FUNCTION _user232(uuid, text, text);
DROP FUNCTION _as232(uuid);
DROP FUNCTION _lignes232();
SELECT _audit_assert('232');
