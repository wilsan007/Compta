-- ============================================================
-- 157_fix_nf525_invoice_modify.sql
--
-- LOT2-07 : nf525_log_invoice_modify (migration 91) applique l'opérateur
-- ->> directement sur les enregistrements OLD et NEW :
--   ERROR: operator does not exist: invoices ->> text
-- Toute modification du numéro, du total, de la date ou du statut d'une
-- facture lève donc une exception et annule l'UPDATE.
--
-- Fix : convertir OLD et NEW en jsonb une seule fois, puis comparer.
-- ============================================================

CREATE OR REPLACE FUNCTION nf525_log_invoice_modify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old jsonb := to_jsonb(OLD);
  v_new jsonb := to_jsonb(NEW);
  v_changes jsonb;
BEGIN
  v_changes := jsonb_build_object(
    'number', NEW.number,
    'changed_fields',
    (SELECT jsonb_object_agg(e.key, jsonb_build_array(v_old -> e.key, e.value))
     FROM jsonb_each(v_new) AS e(key, value)
     WHERE (v_old -> e.key) IS DISTINCT FROM e.value
       AND e.key NOT IN ('updated_at', 'created_at'))
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
