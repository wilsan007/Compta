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

# ============================================
# Deux listes, et une raison par liste.
#
# `--no-verify-jwt` désactive la vérification du JWT par la PASSERELLE : la
# fonction est alors seule à devoir refuser un appel sans jeton. Ne l'utiliser
# que pour les points d'entrée qui n'ont pas de session utilisateur.
#
# Le défaut est **vérifié par la passerelle** (défense en profondeur : un appel
# sans jeton est refusé avant même d'exécuter la fonction).
# ============================================

# Appelées AVEC le jeton de l'utilisateur connecté
FUNCTIONS_JWT=(
  "ai-import-mapping"
  "create-user"
  "ocr-invoice-import"
  "parse-bank-statement"
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

# Appelées SANS jeton d'utilisateur — chacune porte sa propre garde :
#   auth-signup            inscription : pas encore de session
#   cron-payment-reminders pg_cron : en-tête `x-cron-secret`
#   handle-stripe-webhook  Stripe : signature vérifiée dans la fonction
#   outgoing-webhooks      pg_cron / appel interne : clé de service
#   public-api             API publique : clé d'API
#   refresh-exchange-rates pg_cron
FUNCTIONS_SANS_JWT=(
  "auth-signup"
  "cron-payment-reminders"
  "handle-stripe-webhook"
  "outgoing-webhooks"
  "public-api"
  "refresh-exchange-rates"
)

# NON DÉPLOYÉE : `generate-pdf`. Décision D-4 — l'audit prévoyait, « à défaut »
# de décision, de la retirer du déploiement : elle acceptait du HTML fourni par
# le client (SSRF en lecture prouvée, AUD-H03), n'avait **aucun appelant**, et
# était déployée `--no-verify-jwt`. Son code est durci dans le même mouvement
# (le HTML client est refusé, les valeurs sont échappées) et couvert par les
# tests d'entrée ; la décision de la rebrancher ou de la supprimer reste
# ouverte.
FUNCTIONS_NON_DEPLOYEES=(
  "generate-pdf"
)

echo "=========================================="
echo "  Déploiement des Edge Functions"
echo "    ${#FUNCTIONS_JWT[@]} avec JWT vérifié par la passerelle"
echo "    ${#FUNCTIONS_SANS_JWT[@]} sans JWT (garde propre à la fonction)"
echo "    ${#FUNCTIONS_NON_DEPLOYEES[@]} non déployée(s) : ${FUNCTIONS_NON_DEPLOYEES[*]}"
echo "=========================================="

SUCCESS=0
FAILED=0

deploy() {
  local fn="$1"; shift
  echo -n "  Déploiement: $fn... "
  if supabase functions deploy "$fn" "$@" 2>&1 | grep -q "Deployed"; then
    echo "✅"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "❌"
    FAILED=$((FAILED + 1))
  fi
}

for fn in "${FUNCTIONS_JWT[@]}"; do
  deploy "$fn"
done

for fn in "${FUNCTIONS_SANS_JWT[@]}"; do
  deploy "$fn" --no-verify-jwt
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
