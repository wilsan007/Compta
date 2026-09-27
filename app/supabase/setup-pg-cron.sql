-- ============================================
-- pg_cron setup pour Onusuite
-- À exécuter via Supabase Dashboard > SQL Editor
-- ============================================

-- 1. Activer pg_cron (si pas déjà activé)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. Configurer la timezone
ALTER DATABASE postgres SET cron.timezone = 'Europe/Paris';

-- ============================================
-- Cron jobs
-- ============================================

-- 3. Relances de paiement automatiques — tous les jours à 9h
SELECT cron.schedule(
  'payment-reminders-daily',
  '0 9 * * *',
  $$
    SELECT net.http_post(
      url := 'https://ndtaedcgwnaopopugiql.supabase.co/functions/v1/cron-payment-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer REMPLACEZ_PAR_VOTRE_SERVICE_ROLE_KEY',
        'x-cron-secret', 'REMPLACEZ_PAR_VOTRE_CRON_SECRET'
      ),
      body := '{}'::jsonb
    );
  $$
);

-- 4. Taux de change — tous les jours à 6h
--    W6 : la fonction EXIGE désormais une identité (avant, elle lisait le jeton
--    sans jamais le comparer : n'importe qui pouvait la déclencher). Le job
--    envoie les deux jetons qu'elle accepte — la clé de service ET le secret de
--    cron ; remplacez les deux espaces réservés avant d'exécuter ce script.
SELECT cron.schedule(
  'refresh-exchange-rates-daily',
  '0 6 * * *',
  $$
    SELECT net.http_post(
      url := 'https://ndtaedcgwnaopopugiql.supabase.co/functions/v1/refresh-exchange-rates',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer REMPLACEZ_PAR_VOTRE_SERVICE_ROLE_KEY',
        'x-cron-secret', 'REMPLACEZ_PAR_VOTRE_CRON_SECRET'
      ),
      body := '{}'::jsonb
    );
  $$
);

-- 5. Vérifier les jobs configurés
SELECT jobid, schedule, command, active FROM cron.job;

-- ============================================
-- Pour annuler un cron job:
-- SELECT cron.unschedule('payment-reminders-daily');
-- SELECT cron.unschedule('refresh-exchange-rates-daily');
-- ============================================
