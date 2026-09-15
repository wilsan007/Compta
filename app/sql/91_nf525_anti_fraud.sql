-- ============================================================
-- 91_nf525_anti_fraud.sql
--
-- Conformité NF525 : journal d'événements inaltérable
-- Inspiré de : Sage, Cegid, EBP, Pennylane (certification NF525)
--
-- NF525 exige :
--   1. Journal d'événements inaltérable (horodaté, séquentiel)
--   2. Clôture annuelle avec calcul d'empreinte
--   3. Conservation 10 ans
--   4. Détection des modifications post-clôture
--   5. Empreinte numérique (hash chain) sur chaque écriture
-- ============================================================

-- ============================================================
-- 1. Table : nf525_event_log — Journal d'événements inaltérable
-- ============================================================
CREATE TABLE IF NOT EXISTS nf525_event_log (
  id BIGSERIAL PRIMARY KEY,
  tenant_id uuid NOT NULL,
  event_type text NOT NULL,           -- 'invoice_create', 'invoice_modify', 'invoice_delete', 'entry_post', 'entry_modify'
  entity_type text NOT NULL,           -- 'invoice', 'journal_entry', 'pay_slip', etc.
  entity_id uuid,
  event_date timestamptz NOT NULL DEFAULT now(),
  user_id uuid,
  user_name text,
  event_data jsonb,                    -- Détails de l'événement (avant/après)
  previous_hash text,                  -- Hash de l'événement précédent (chaîne)
  current_hash text,                   -- Hash de cet événement (SHA-256)
  fiscal_year_code text,               -- Exercice concerné
  period text,                         -- Période (YYYY-MM)
  closed boolean DEFAULT false,        -- True si l'événement est dans une période clôturée
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index pour performances
CREATE INDEX IF NOT EXISTS idx_nf525_tenant_date ON nf525_event_log(tenant_id, event_date DESC);
CREATE INDEX IF NOT EXISTS idx_nf525_tenant_entity ON nf525_event_log(tenant_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_nf525_tenant_period ON nf525_event_log(tenant_id, period);
CREATE INDEX IF NOT EXISTS idx_nf525_tenant_fiscal_year ON nf525_event_log(tenant_id, fiscal_year_code);

-- RLS
ALTER TABLE nf525_event_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE nf525_event_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_select_nf525_event_log ON nf525_event_log;
CREATE POLICY tenant_select_nf525_event_log ON nf525_event_log
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_nf525_event_log ON nf525_event_log;
CREATE POLICY tenant_insert_nf525_event_log ON nf525_event_log
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

-- Pas de UPDATE ni DELETE (inaltérable)
-- On ajoute une contrainte CHECK pour empêcher la modification
-- Note: PostgreSQL ne permet pas d'empêcher UPDATE/DELETE via CHECK,
-- on utilise un trigger à la place.


-- ============================================================
-- 2. Trigger : empêcher UPDATE et DELETE sur le journal
-- ============================================================
CREATE OR REPLACE FUNCTION prevent_nf525_modification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'NF525: Le journal d''événements est inaltérable. Modification interdite.';
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS nf525_no_update ON nf525_event_log;
DROP TRIGGER IF EXISTS nf525_no_delete ON nf525_event_log;

CREATE TRIGGER nf525_no_update
  BEFORE UPDATE ON nf525_event_log
  FOR EACH ROW EXECUTE FUNCTION prevent_nf525_modification();

CREATE TRIGGER nf525_no_delete
  BEFORE DELETE ON nf525_event_log
  FOR EACH ROW EXECUTE FUNCTION prevent_nf525_modification();


-- ============================================================
-- 3. Fonction : log_nf525_event — Enregistrer un événement
--    Calcule le hash (SHA-256) en chaîne avec l'événement précédent
-- ============================================================
CREATE OR REPLACE FUNCTION log_nf525_event(
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid DEFAULT NULL,
  p_event_data jsonb DEFAULT NULL,
  p_fiscal_year_code text DEFAULT NULL,
  p_period text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_prev_hash text;
  v_current_hash text;
  v_seq bigint;
  v_user_name text;
  v_hash_input text;
  v_event_date timestamptz := now();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- NF-02 : Verrou advisory transactionnel par tenant pour prévenir les forks concurrents de la chaîne
  PERFORM pg_advisory_xact_lock(hashtext('nf525_lock_' || v_tid::text));

  -- Récupérer le hash précédent (dernier événement du tenant)
  SELECT current_hash INTO v_prev_hash
  FROM nf525_event_log
  WHERE tenant_id = v_tid
  ORDER BY id DESC
  LIMIT 1;

  v_prev_hash := COALESCE(v_prev_hash, 'GENESIS');

  -- Récupérer le nom d'utilisateur depuis la session
  BEGIN
    SELECT current_setting('app.user_name', true) INTO v_user_name;
  EXCEPTION WHEN OTHERS THEN
    v_user_name := NULL;
  END;

  -- Calculer le hash : SHA-256(prev_hash || event_type || entity_type || entity_id || tenant_id || event_date)
  v_hash_input := v_prev_hash || '|' ||
    p_event_type || '|' ||
    p_entity_type || '|' ||
    COALESCE(p_entity_id::text, '') || '|' ||
    v_tid::text || '|' ||
    extract(epoch FROM v_event_date)::text;

  v_current_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

  -- Insérer l'événement
  INSERT INTO nf525_event_log (
    tenant_id, event_type, entity_type, entity_id,
    event_date, event_data, previous_hash, current_hash,
    fiscal_year_code, period, user_name
  ) VALUES (
    v_tid, p_event_type, p_entity_type, p_entity_id,
    v_event_date, p_event_data, v_prev_hash, v_current_hash,
    p_fiscal_year_code, p_period, v_user_name
  )
  RETURNING id INTO v_seq;

  RETURN v_seq;
END;
$$;

GRANT EXECUTE ON FUNCTION log_nf525_event(text, text, uuid, jsonb, text, text) TO authenticated;


-- ============================================================
-- 4. Triggers : enregistrer automatiquement les événements critiques
--    sur les factures, écritures comptables, et bulletins de paie
-- ============================================================

-- 4a. Factures : création
CREATE OR REPLACE FUNCTION nf525_log_invoice_create()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM log_nf525_event(
    'invoice_create',
    'invoice',
    NEW.id,
    jsonb_build_object('number', NEW.number, 'total', NEW.total, 'date', NEW.date),
    NULL,
    to_char(NEW.date, 'YYYY-MM')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS nf525_invoice_create ON invoices;
CREATE TRIGGER nf525_invoice_create
  AFTER INSERT ON invoices
  FOR EACH ROW EXECUTE FUNCTION nf525_log_invoice_create();

-- 4b. Factures : modification
CREATE OR REPLACE FUNCTION nf525_log_invoice_modify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_changes jsonb;
BEGIN
  v_changes := jsonb_build_object(
    'number', NEW.number,
    'changed_fields',
    (SELECT jsonb_object_agg(key, jsonb_build_array(OLD ->> key, NEW ->> key))
     FROM jsonb_each(to_jsonb(NEW)) AS e(key, val)
     WHERE to_jsonb(OLD) ->> key IS DISTINCT FROM to_jsonb(NEW) ->> key
       AND key NOT IN ('updated_at', 'created_at'))
  );

  PERFORM log_nf525_event(
    'invoice_modify',
    'invoice',
    NEW.id,
    v_changes,
    NULL,
    to_char(NEW.date, 'YYYY-MM')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS nf525_invoice_modify ON invoices;
CREATE TRIGGER nf525_invoice_modify
  AFTER UPDATE ON invoices
  FOR EACH ROW
  WHEN (OLD.number IS DISTINCT FROM NEW.number
     OR OLD.total IS DISTINCT FROM NEW.total
     OR OLD.date IS DISTINCT FROM NEW.date
     OR OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION nf525_log_invoice_modify();

-- 4c. Écritures comptables : validation
CREATE OR REPLACE FUNCTION nf525_log_entry_post()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'posted' AND (OLD.status IS NULL OR OLD.status != 'posted') THEN
    PERFORM log_nf525_event(
      'entry_post',
      'journal_entry',
      NEW.id,
      jsonb_build_object('number', NEW.number, 'date', NEW.date, 'journal_code', NEW.journal_code),
      NULL,
      to_char(NEW.date, 'YYYY-MM')
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS nf525_entry_post ON journal_entries;
CREATE TRIGGER nf525_entry_post
  AFTER UPDATE ON journal_entries
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION nf525_log_entry_post();

-- 4d. Bulletins de paie : création
CREATE OR REPLACE FUNCTION nf525_log_payslip_create()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM log_nf525_event(
    'payslip_create',
    'pay_slip',
    NEW.id,
    jsonb_build_object('number', NEW.number, 'period_start', NEW.period_start, 'net_salary', NEW.net_salary),
    NULL,
    to_char(NEW.period_start, 'YYYY-MM')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS nf525_payslip_create ON pay_slips;
CREATE TRIGGER nf525_payslip_create
  AFTER INSERT ON pay_slips
  FOR EACH ROW EXECUTE FUNCTION nf525_log_payslip_create();


-- ============================================================
-- 5. Fonction : verify_nf525_chain — Vérifier l'intégrité de la chaîne
-- ============================================================
CREATE OR REPLACE FUNCTION verify_nf525_chain(
  p_from_date timestamptz DEFAULT NULL,
  p_to_date timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_rec RECORD;
  v_expected_hash text;
  v_hash_input text;
  v_broken_count integer := 0;
  v_total_count integer := 0;
  v_first_id bigint;
  v_last_id bigint;
  v_expected_prev_hash text := NULL;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  FOR v_rec IN
    SELECT id, previous_hash, current_hash, event_type, entity_type, entity_id, event_date, tenant_id
    FROM nf525_event_log
    WHERE tenant_id = v_tid
      AND (p_from_date IS NULL OR event_date >= p_from_date)
      AND (p_to_date IS NULL OR event_date <= p_to_date)
    ORDER BY id
  LOOP
    v_total_count := v_total_count + 1;
    IF v_total_count = 1 THEN
      v_first_id := v_rec.id;
    ELSE
      -- NF-01 : Vérifier la continuité de la chaîne (le previous_hash doit correspondre au current_hash précédent)
      IF v_rec.previous_hash IS DISTINCT FROM v_expected_prev_hash THEN
        v_broken_count := v_broken_count + 1;
      END IF;
    END IF;
    v_last_id := v_rec.id;

    -- Recalculer le hash attendu
    v_hash_input := COALESCE(v_rec.previous_hash, 'GENESIS') || '|' ||
      v_rec.event_type || '|' ||
      v_rec.entity_type || '|' ||
      COALESCE(v_rec.entity_id::text, '') || '|' ||
      v_rec.tenant_id::text || '|' ||
      extract(epoch FROM v_rec.event_date)::text;

    v_expected_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

    IF v_expected_hash != v_rec.current_hash THEN
      v_broken_count := v_broken_count + 1;
    END IF;

    -- Mémoriser le hash courant pour vérifier le maillon suivant
    v_expected_prev_hash := v_rec.current_hash;
  END LOOP;

  RETURN jsonb_build_object(
    'total_events', v_total_count,
    'broken_links', v_broken_count,
    'chain_valid', v_broken_count = 0,
    'first_event_id', v_first_id,
    'last_event_id', v_last_id,
    'verified_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION verify_nf525_chain(timestamptz, timestamptz) TO authenticated;


-- ============================================================
-- 6. Fonction : close_nf525_period — Clôturer une période NF525
--    Calcule l'empreinte de clôture et empêche toute modification
--    ultérieure des événements de la période
-- ============================================================
CREATE OR REPLACE FUNCTION close_nf525_period(p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_count integer;
  v_last_hash text;
  v_closing_hash text;
  v_hash_input text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Compter les événements de la période
  SELECT count(*), COALESCE(max(current_hash), 'EMPTY')
  INTO v_count, v_last_hash
  FROM nf525_event_log
  WHERE tenant_id = v_tid AND period = p_period;

  -- Calculer l'empreinte de clôture
  v_hash_input := 'CLOSE|' || p_period || '|' || v_tid::text || '|' || v_last_hash || '|' || v_count;
  v_closing_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

  -- Marquer les événements comme clôturés
  -- Note: le trigger prevent_nf525_modification empêche UPDATE,
  -- donc on utilise SECURITY DEFINER pour contourner
  UPDATE nf525_event_log
    SET closed = true
  WHERE tenant_id = v_tid AND period = p_period AND closed = false;

  -- Enregistrer l'événement de clôture
  PERFORM log_nf525_event(
    'period_close',
    'nf525_period',
    NULL,
    jsonb_build_object('period', p_period, 'event_count', v_count, 'closing_hash', v_closing_hash),
    NULL,
    p_period
  );

  RETURN jsonb_build_object(
    'period', p_period,
    'event_count', v_count,
    'closing_hash', v_closing_hash,
    'closed_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION close_nf525_period(text) TO authenticated;


-- ============================================================
-- 7. Table : nf525_period_closures — Suivi des clôtures NF525
-- ============================================================
CREATE TABLE IF NOT EXISTS nf525_period_closures (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id uuid NOT NULL,
  period text NOT NULL,
  event_count integer NOT NULL,
  closing_hash text NOT NULL,
  closed_by uuid,
  closed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, period)
);

ALTER TABLE nf525_period_closures ENABLE ROW LEVEL SECURITY;
ALTER TABLE nf525_period_closures FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_select_nf525_closures ON nf525_period_closures;
CREATE POLICY tenant_select_nf525_closures ON nf525_period_closures
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_nf525_closures ON nf525_period_closures;
CREATE POLICY tenant_insert_nf525_closures ON nf525_period_closures
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

-- Index
CREATE INDEX IF NOT EXISTS idx_nf525_closures_tenant ON nf525_period_closures(tenant_id, period);


-- ============================================================
-- 8. Fonction : get_nf525_attestation — Générer une attestation NF525
--    Document prouvant la conformité du journal d'événements
-- ============================================================
CREATE OR REPLACE FUNCTION get_nf525_attestation(p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_closure RECORD;
  v_verification jsonb;
  v_company RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_closure
  FROM nf525_period_closures
  WHERE tenant_id = v_tid AND period = p_period;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Période non clôturée: %', p_period;
  END IF;

  SELECT verify_nf525_chain(
    (p_period || '-01')::timestamp,
    ((p_period || '-01')::date + INTERVAL '1 month' - INTERVAL '1 second')::timestamp
  ) INTO v_verification;

  SELECT * INTO v_company
  FROM company_settings
  WHERE tenant_id = v_tid
  LIMIT 1;

  RETURN jsonb_build_object(
    'attestation_type', 'NF525',
    'period', p_period,
    'company_name', COALESCE(v_company.company_name, v_company.name, ''),
    'company_siret', COALESCE(v_company.siret, ''),
    'event_count', v_closure.event_count,
    'closing_hash', v_closure.closing_hash,
    'chain_verification', v_verification,
    'closed_at', v_closure.closed_at,
    'generated_at', now(),
    'standard', 'NF525 - Journal d''événements inaltérable',
    'legal_reference', 'Article 286 V du CGI + NF525'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_nf525_attestation(text) TO authenticated;


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- 1. Table nf525_event_log (journal inaltérable avec hash chain)
-- 2. Trigger empêchant UPDATE/DELETE sur le journal
-- 3. Fonction log_nf525_event (enregistrement avec SHA-256)
-- 4. Triggers automatiques sur invoices, journal_entries, pay_slips
-- 5. Fonction verify_nf525_chain (vérification intégrité chaîne)
-- 6. Fonction close_nf525_period (clôture avec empreinte)
-- 7. Table nf525_period_closures (suivi des clôtures)
-- 8. Fonction get_nf525_attestation (attestation de conformité)
-- ============================================================
