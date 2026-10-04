-- ============================================
-- 72_exchange_rate_cron.sql
-- Weekly cron job to refresh exchange rates via Frankfurter API (BCE rates)
-- Runs every Monday at 06:00 UTC via pg_cron
-- Calls the Supabase Edge Function: refresh-exchange-rates
-- ============================================

-- ============================================
-- 1. ENSURE pg_cron EXTENSION IS ENABLED
-- ============================================
-- pg_cron must be enabled in Supabase Dashboard > Database > Extensions
-- or via: CREATE EXTENSION IF NOT EXISTS pg_cron;
-- Note: pg_cron uses the default database (postgres) and runs as the postgres user

DO $$
BEGIN
  -- Check if pg_cron extension exists BEFORE touching cron.job
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron extension not found. Skipping cron setup. Enable pg_cron + pg_net in Supabase Dashboard > Database > Extensions, then re-run this migration.';
  ELSE
    -- Remove existing job if it exists (idempotent)
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-exchange-rates-weekly') THEN
      PERFORM cron.unschedule('refresh-exchange-rates-weekly');
      RAISE NOTICE 'Unscheduled existing refresh-exchange-rates-weekly job';
    END IF;

    -- Schedule the new job
    -- Cron format: minute hour day-of-month month day-of-week
    -- '0 6 * * 1' = every Monday at 06:00 UTC
    PERFORM cron.schedule(
      'refresh-exchange-rates-weekly',
      '0 6 * * 1',
      $cron$
        SELECT net.http_post(
          url := 'https://projet-compta.zdouce-zz.workers.dev/functions/v1/refresh-exchange-rates',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key', true)
          ),
          body := '{}'::jsonb
        );
      $cron$
    );
    RAISE NOTICE 'Scheduled refresh-exchange-rates-weekly cron job (every Monday 06:00 UTC)';
  END IF;
END $$;

-- ============================================
-- 3. ALSO ALLOW MANUAL TRIGGER VIA SQL FUNCTION
-- ============================================
-- This allows an admin to manually trigger the rate refresh from SQL editor
-- without waiting for the cron schedule

-- Guard: only create the function if pg_net is available
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    CREATE OR REPLACE FUNCTION trigger_exchange_rate_refresh()
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $func$
    DECLARE
      response jsonb;
    BEGIN
      SELECT net.http_post(
        url := 'https://projet-compta.zdouce-zz.workers.dev/functions/v1/refresh-exchange-rates',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key', true)
        ),
        body := '{}'::jsonb
      ) INTO response;

      RETURN jsonb_build_object(
        'success', true,
        'message', 'Exchange rate refresh triggered',
        'response', response
      );
    EXCEPTION WHEN OTHERS THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
      );
    END;
    $func$;

    GRANT EXECUTE ON FUNCTION trigger_exchange_rate_refresh() TO authenticated;

    COMMENT ON FUNCTION trigger_exchange_rate_refresh() IS
    'Manually triggers the refresh-exchange-rates Edge Function to fetch latest BCE rates from Frankfurter API. Call via: SELECT trigger_exchange_rate_refresh();';

    RAISE NOTICE 'Created trigger_exchange_rate_refresh() function';
  ELSE
    RAISE NOTICE 'pg_net not enabled. Skipping trigger_exchange_rate_refresh() function. Enable pg_net in Supabase Dashboard > Database > Extensions, then re-run.';
  END IF;
END $$;

-- ============================================
-- 4. SEED INITIAL GLOBAL RATES (if table is empty for global tenant)
-- ============================================
-- Insert initial rates with tenant_id = NULL (global rates for pricing display)
-- These will be overwritten by the first cron run or manual trigger

INSERT INTO exchange_rates (tenant_id, base_currency, quote_currency, rate, rate_date, source)
SELECT NULL, 'EUR', 'XOF', 655.957, CURRENT_DATE, 'frankfurter'
WHERE NOT EXISTS (
  SELECT 1 FROM exchange_rates
  WHERE tenant_id IS NULL AND base_currency = 'EUR' AND quote_currency = 'XOF'
);

INSERT INTO exchange_rates (tenant_id, base_currency, quote_currency, rate, rate_date, source)
SELECT NULL, 'EUR', 'XAF', 655.957, CURRENT_DATE, 'frankfurter'
WHERE NOT EXISTS (
  SELECT 1 FROM exchange_rates
  WHERE tenant_id IS NULL AND base_currency = 'EUR' AND quote_currency = 'XAF'
);

INSERT INTO exchange_rates (tenant_id, base_currency, quote_currency, rate, rate_date, source)
SELECT NULL, 'XOF', 'EUR', 1.0 / 655.957, CURRENT_DATE, 'frankfurter'
WHERE NOT EXISTS (
  SELECT 1 FROM exchange_rates
  WHERE tenant_id IS NULL AND base_currency = 'XOF' AND quote_currency = 'EUR'
);

-- ============================================
-- 5. DOCUMENTATION
-- ============================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    COMMENT ON FUNCTION trigger_exchange_rate_refresh() IS
    'Manually triggers the refresh-exchange-rates Edge Function to fetch latest BCE rates from Frankfurter API. Call via: SELECT trigger_exchange_rate_refresh();';
  ELSE
    RAISE NOTICE 'pg_net not enabled. Skipping COMMENT ON FUNCTION.';
  END IF;
END $$;

-- ============================================
-- NOTES:
-- ============================================
-- 1. Requires pg_cron AND pg_net extensions enabled in Supabase Dashboard
-- 2. The Edge Function URL must match your Supabase project URL
-- 3. The service role key must be set as a GUC: ALTER DATABASE postgres SET app.supabase_service_role_key = ''your-key'';
--    OR use a Supabase secret: supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-key
-- 4. To verify cron is running: SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
-- 5. To manually trigger: SELECT trigger_exchange_rate_refresh();
-- 6. To unschedule: SELECT cron.unschedule('refresh-exchange-rates-weekly');
