#!/bin/bash
set -e

SB_URL="https://ndtaedcgwnaopopugiql.supabase.co"
SB_KEY="sb_publishable_6WZDE3wBMwc5ildtfy19Nw_pxdPnAZK"
H_API="apikey: $SB_KEY"
H_AUTH="Authorization: Bearer $SB_KEY"
H_CT="Content-Type: application/json"
H_PREF="Prefer: return=representation"

echo "=== Getting period IDs ==="
P1=$(curl -s "$SB_URL/rest/v1/fiscal_periods?select=id&period_number=eq.1" -H "$H_API" -H "$H_AUTH" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
P2=$(curl -s "$SB_URL/rest/v1/fiscal_periods?select=id&period_number=eq.2" -H "$H_API" -H "$H_AUTH" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
P3=$(curl -s "$SB_URL/rest/v1/fiscal_periods?select=id&period_number=eq.3" -H "$H_API" -H "$H_AUTH" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
echo "P1=$P1"
echo "P2=$P2"
echo "P3=$P3"

echo "=== Creating BQ entry period 1 ==="
JE1=$(curl -s -X POST "$SB_URL/rest/v1/journal_entries" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "{\"number\":\"BQ-2025-001\",\"date\":\"2025-01-15\",\"description\":\"Paiement fournisseur Facture F001\",\"reference\":\"F001\",\"status\":\"posted\",\"journal_code\":\"BQ\",\"fiscal_period_id\":\"$P1\",\"piece_number\":\"P001\",\"invoice_ref\":\"FAC-2025-001\",\"status_detail\":\"open\",\"total_debit\":1200,\"total_credit\":1200}")
JE1_ID=$(echo "$JE1" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
echo "JE1_ID=$JE1_ID"

curl -s -X POST "$SB_URL/rest/v1/journal_lines" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "[
    {\"journal_id\":\"$JE1_ID\",\"account_code\":\"607000\",\"account_name\":\"Achats de marchandises\",\"account_general\":\"607000\",\"debit\":1000,\"credit\":0,\"description\":\"Achat marchandises\",\"line_order\":1,\"piece_number\":\"P001\",\"reference\":\"FAC-2025-001\",\"line_date\":\"2025-01-15\"},
    {\"journal_id\":\"$JE1_ID\",\"account_code\":\"445660\",\"account_name\":\"TVA déductible\",\"account_general\":\"445660\",\"debit\":200,\"credit\":0,\"description\":\"TVA déductible 20%\",\"line_order\":2,\"piece_number\":\"P001\",\"reference\":\"FAC-2025-001\",\"line_date\":\"2025-01-15\"},
    {\"journal_id\":\"$JE1_ID\",\"account_code\":\"512000\",\"account_name\":\"Banque\",\"account_general\":\"512000\",\"debit\":0,\"credit\":1200,\"description\":\"Paiement bancaire\",\"line_order\":3,\"piece_number\":\"P001\",\"reference\":\"FAC-2025-001\",\"line_date\":\"2025-01-15\"}
  ]"
echo ""
echo "=== Creating BQ entry period 2 ==="
JE2=$(curl -s -X POST "$SB_URL/rest/v1/journal_entries" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "{\"number\":\"BQ-2025-002\",\"date\":\"2025-02-10\",\"description\":\"Encaissement client Vente V001\",\"reference\":\"V001\",\"status\":\"posted\",\"journal_code\":\"BQ\",\"fiscal_period_id\":\"$P2\",\"piece_number\":\"P002\",\"invoice_ref\":\"FAC-2025-002\",\"status_detail\":\"open\",\"total_debit\":2400,\"total_credit\":2400}")
JE2_ID=$(echo "$JE2" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
echo "JE2_ID=$JE2_ID"

curl -s -X POST "$SB_URL/rest/v1/journal_lines" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "[
    {\"journal_id\":\"$JE2_ID\",\"account_code\":\"512000\",\"account_name\":\"Banque\",\"account_general\":\"512000\",\"debit\":2400,\"credit\":0,\"description\":\"Encaissement bancaire\",\"line_order\":1,\"piece_number\":\"P002\",\"reference\":\"FAC-2025-002\",\"line_date\":\"2025-02-10\"},
    {\"journal_id\":\"$JE2_ID\",\"account_code\":\"411000\",\"account_name\":\"Clients\",\"account_general\":\"411000\",\"debit\":0,\"credit\":2400,\"description\":\"Client - paiement reçu\",\"line_order\":2,\"piece_number\":\"P002\",\"reference\":\"FAC-2025-002\",\"line_date\":\"2025-02-10\"}
  ]"
echo ""

echo "=== Creating VT entry period 1 ==="
JE3=$(curl -s -X POST "$SB_URL/rest/v1/journal_entries" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "{\"number\":\"VT-2025-001\",\"date\":\"2025-01-20\",\"description\":\"Vente de marchandises au client DUPONT\",\"reference\":\"V001\",\"status\":\"posted\",\"journal_code\":\"VT\",\"fiscal_period_id\":\"$P1\",\"piece_number\":\"P003\",\"invoice_ref\":\"FAC-VT-001\",\"status_detail\":\"open\",\"total_debit\":2400,\"total_credit\":2400}")
JE3_ID=$(echo "$JE3" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
echo "JE3_ID=$JE3_ID"

curl -s -X POST "$SB_URL/rest/v1/journal_lines" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "[
    {\"journal_id\":\"$JE3_ID\",\"account_code\":\"411000\",\"account_name\":\"Clients\",\"account_general\":\"411000\",\"debit\":2400,\"credit\":0,\"description\":\"Client DUPONT\",\"line_order\":1,\"piece_number\":\"P003\",\"reference\":\"FAC-VT-001\",\"line_date\":\"2025-01-20\"},
    {\"journal_id\":\"$JE3_ID\",\"account_code\":\"707000\",\"account_name\":\"Ventes de marchandises\",\"account_general\":\"707000\",\"debit\":0,\"credit\":2000,\"description\":\"Vente marchandises HT\",\"line_order\":2,\"piece_number\":\"P003\",\"reference\":\"FAC-VT-001\",\"line_date\":\"2025-01-20\"},
    {\"journal_id\":\"$JE3_ID\",\"account_code\":\"445710\",\"account_name\":\"TVA collectée 20%\",\"account_general\":\"445710\",\"debit\":0,\"credit\":400,\"description\":\"TVA collectée\",\"line_order\":3,\"piece_number\":\"P003\",\"reference\":\"FAC-VT-001\",\"line_date\":\"2025-01-20\"}
  ]"
echo ""

echo "=== Creating AC entry period 2 ==="
JE4=$(curl -s -X POST "$SB_URL/rest/v1/journal_entries" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "{\"number\":\"AC-2025-001\",\"date\":\"2025-02-05\",\"description\":\"Achat fournitures bureau\",\"reference\":\"F002\",\"status\":\"posted\",\"journal_code\":\"AC\",\"fiscal_period_id\":\"$P2\",\"piece_number\":\"P004\",\"invoice_ref\":\"FAC-AC-001\",\"status_detail\":\"printed\",\"total_debit\":600,\"total_credit\":600}")
JE4_ID=$(echo "$JE4" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
echo "JE4_ID=$JE4_ID"

curl -s -X POST "$SB_URL/rest/v1/journal_lines" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "[
    {\"journal_id\":\"$JE4_ID\",\"account_code\":\"607000\",\"account_name\":\"Achats de marchandises\",\"account_general\":\"607000\",\"debit\":500,\"credit\":0,\"description\":\"Fournitures bureau HT\",\"line_order\":1,\"piece_number\":\"P004\",\"reference\":\"FAC-AC-001\",\"line_date\":\"2025-02-05\"},
    {\"journal_id\":\"$JE4_ID\",\"account_code\":\"445660\",\"account_name\":\"TVA déductible\",\"account_general\":\"445660\",\"debit\":100,\"credit\":0,\"description\":\"TVA déductible 20%\",\"line_order\":2,\"piece_number\":\"P004\",\"reference\":\"FAC-AC-001\",\"line_date\":\"2025-02-05\"},
    {\"journal_id\":\"$JE4_ID\",\"account_code\":\"401000\",\"account_name\":\"Fournisseurs\",\"account_general\":\"401000\",\"debit\":0,\"credit\":600,\"description\":\"Fournisseur - facture à payer\",\"line_order\":3,\"piece_number\":\"P004\",\"reference\":\"FAC-AC-001\",\"line_date\":\"2025-02-05\"}
  ]"
echo ""

echo "=== Creating CA entry period 1 ==="
JE5=$(curl -s -X POST "$SB_URL/rest/v1/journal_entries" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "{\"number\":\"CA-2025-001\",\"date\":\"2025-01-08\",\"description\":\"Apport en caisse\",\"reference\":\"CA001\",\"status\":\"posted\",\"journal_code\":\"CA\",\"fiscal_period_id\":\"$P1\",\"piece_number\":\"P005\",\"invoice_ref\":\"\",\"status_detail\":\"open\",\"total_debit\":300,\"total_credit\":300}")
JE5_ID=$(echo "$JE5" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
echo "JE5_ID=$JE5_ID"

curl -s -X POST "$SB_URL/rest/v1/journal_lines" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "[
    {\"journal_id\":\"$JE5_ID\",\"account_code\":\"530000\",\"account_name\":\"Caisse\",\"account_general\":\"530000\",\"debit\":300,\"credit\":0,\"description\":\"Apport espèces\",\"line_order\":1,\"piece_number\":\"P005\",\"reference\":\"\",\"line_date\":\"2025-01-08\"},
    {\"journal_id\":\"$JE5_ID\",\"account_code\":\"512000\",\"account_name\":\"Banque\",\"account_general\":\"512000\",\"debit\":0,\"credit\":300,\"description\":\"Retrait bancaire pour caisse\",\"line_order\":2,\"piece_number\":\"P005\",\"reference\":\"\",\"line_date\":\"2025-01-08\"}
  ]"
echo ""

echo "=== Creating OD entry period 3 ==="
JE6=$(curl -s -X POST "$SB_URL/rest/v1/journal_entries" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "{\"number\":\"OD-2025-001\",\"date\":\"2025-03-15\",\"description\":\"Dotisation amortissements\",\"reference\":\"OD001\",\"status\":\"posted\",\"journal_code\":\"OD\",\"fiscal_period_id\":\"$P3\",\"piece_number\":\"P006\",\"invoice_ref\":\"\",\"status_detail\":\"closed\",\"total_debit\":1000,\"total_credit\":1000}")
JE6_ID=$(echo "$JE6" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
echo "JE6_ID=$JE6_ID"

curl -s -X POST "$SB_URL/rest/v1/journal_lines" \
  -H "$H_API" -H "$H_AUTH" -H "$H_CT" -H "$H_PREF" \
  -d "[
    {\"journal_id\":\"$JE6_ID\",\"account_code\":\"681000\",\"account_name\":\"Dotations aux amortissements\",\"account_general\":\"681000\",\"debit\":1000,\"credit\":0,\"description\":\"Dotation annuelle\",\"line_order\":1,\"piece_number\":\"P006\",\"reference\":\"\",\"line_date\":\"2025-03-15\"},
    {\"journal_id\":\"$JE6_ID\",\"account_code\":\"281000\",\"account_name\":\"Amortissements des immobilisations\",\"account_general\":\"281000\",\"debit\":0,\"credit\":1000,\"description\":\"Amortissements cumulés\",\"line_order\":2,\"piece_number\":\"P006\",\"reference\":\"\",\"line_date\":\"2025-03-15\"}
  ]"
echo ""

echo "=== Done seeding! ==="
echo "=== Verifying entries ==="
curl -s "$SB_URL/rest/v1/journal_entries?select=number,description,journal_code,status_detail&journal_code=not.is.null" -H "$H_API" -H "$H_AUTH" | python3 -m json.tool
