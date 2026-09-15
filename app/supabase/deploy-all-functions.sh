#!/bin/bash
# ============================================
# Script de déploiement des 20 Edge Functions
# Onusuite — Supabase Cloud
# ============================================
# Prérequis:
#   1. supabase login
#   2. supabase link --project-ref ndtaedcgwnaopopugiql
#   3. Configurer les secrets via dashboard Supabase:
#      - RESEND_API_KEY (https://resend.com/api-keys)
#      - STRIPE_WEBHOOK_SECRET (Stripe Dashboard > Webhooks)
#      - APP_URL (votre URL de production)
#      - CRON_SECRET (valeur aléatoire sécurisée)
# ============================================

set -e

cd "$(dirname "$0")"

FUNCTIONS=(
  "ai-import-mapping"
  "auth-signup"
  "create-user"
  "cron-payment-reminders"
  "generate-pdf"
  "handle-stripe-webhook"
  "ocr-invoice-import"
  "outgoing-webhooks"
  "parse-bank-statement"
  "public-api"
  "refresh-exchange-rates"
  "request-signature"
  "send-notification-email"
  "submit-e-invoice"
  "submit-vat-return"
  "sync-bank-transactions"
  "transmit-dsn"
  "validate-vat-vies"
  "verify-iban"
  "verify-siret"
)

echo "=========================================="
echo "  Déploiement de ${#FUNCTIONS[@]} Edge Functions"
echo "=========================================="

SUCCESS=0
FAILED=0

for fn in "${FUNCTIONS[@]}"; do
  echo -n "  Déploiement: $fn... "
  if supabase functions deploy "$fn" --no-verify-jwt 2>&1 | grep -q "Deployed"; then
    echo "✅"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "❌"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "=========================================="
echo "  Résultat: $SUCCESS ✅ | $FAILED ❌"
echo "=========================================="
echo ""
echo "Secrets à configurer via Dashboard Supabase:"
echo "  1. RESEND_API_KEY       — https://resend.com/api-keys"
echo "  2. STRIPE_WEBHOOK_SECRET — Stripe Dashboard > Developers > Webhooks"
echo "  3. APP_URL               — https://votre-domaine.com"
echo "  4. CRON_SECRET           — $(openssl rand -hex 16)"
echo ""
echo "pg_cron à configurer via SQL Editor:"
echo "  Voir: supabase/setup-pg-cron.sql"
