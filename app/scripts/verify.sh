#!/usr/bin/env bash
# verify.sh — Pipeline de vérification modulaire
# Usage: ./scripts/verify.sh [--skip-tests] [--skip-lint] [--list-rules]
#
# Architecture:
#   1. TypeScript type-check (tsc --noEmit)        — fixe
#   2. Lint (oxlint)                               — fixe
#   3. i18n key parity (check-i18n.mjs)            — fixe
#   4. Audit grep rules (scripts/verify-rules/*.rule) — MODULAIRE
#   5. Tests Vitest                                — fixe
#
# Pour ajouter un nouveau check:
#   1. Copier scripts/verify-rules/00-TEMPLATE.rule
#   2. Renommer en NN-description.rule
#   3. Éditer les variables (RULE_NAME, RULE_GREP_PATTERN, etc.)
#   4. Relancer: npm run verify
#
# Sortie: code d'exit 0 = tout passe, 1 = erreurs trouvées

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Compteurs
TOTAL_ERRORS=0
TOTAL_WARNINGS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

SKIP_TESTS=false
SKIP_LINT=false
LIST_RULES=false

for arg in "$@"; do
  case $arg in
    --skip-tests) SKIP_TESTS=true ;;
    --skip-lint)  SKIP_LINT=true ;;
    --list-rules) LIST_RULES=true ;;
  esac
done

section() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pass() {
  echo -e "  ${GREEN}✓ PASSED${NC} — $1"
  ((PASSED_CHECKS++))
}

fail() {
  echo -e "  ${RED}✗ FAILED${NC} — $1"
  ((FAILED_CHECKS++))
  TOTAL_ERRORS=$((TOTAL_ERRORS + $2))
}

warn() {
  echo -e "  ${YELLOW}⚠ WARNING${NC} — $1"
  ((TOTAL_WARNINGS++))
}

# ──────────────────────────────────────────────────────────────
# Mode --list-rules: affiche les règles disponibles et quitte
# ──────────────────────────────────────────────────────────────
if [ "$LIST_RULES" = true ]; then
  echo "Règles de vérification disponibles:"
  echo ""
  for rulefile in scripts/verify-rules/*.rule; do
    [ -f "$rulefile" ] || continue
    [[ "$(basename "$rulefile")" == "00-TEMPLATE"* ]] && continue
    RULE_NAME=""
    RULE_DESC=""
    RULE_SEVERITY=""
    source "$rulefile"
    if [ -n "$RULE_NAME" ]; then
      printf "  %-25s [%s] %s\n" "$RULE_NAME" "$RULE_SEVERITY" "$RULE_DESC"
    fi
  done
  exit 0
fi

# ══════════════════════════════════════════════════════════════
# FIXE 1/5: TypeScript Type-Check
# ══════════════════════════════════════════════════════════════
section "1/5  TypeScript Type-Check (tsc --noEmit)"

TSC_OUTPUT=$(npx tsc --noEmit --pretty 2>&1 || true)
TSC_ERRORS=$(echo "$TSC_OUTPUT" | grep -c "error TS" || true)

if [ "$TSC_ERRORS" -eq 0 ]; then
  pass "tsc --noEmit: 0 erreurs de type"
else
  fail "tsc --noEmit: ${TSC_ERRORS} erreurs de type" "$TSC_ERRORS"
  echo "$TSC_OUTPUT" | head -80 | sed 's/^/    /'
fi

# ══════════════════════════════════════════════════════════════
# FIXE 2/5: Lint
# ══════════════════════════════════════════════════════════════
section "2/5  Lint (oxlint)"

if [ "$SKIP_LINT" = true ]; then
  warn "Lint skippé (--skip-lint)"
else
  LINT_OUTPUT=$(npx oxlint --max-warnings=0 2>&1 || true)
  LINT_EXIT=$?
  if [ "$LINT_EXIT" -eq 0 ]; then
    pass "oxlint: 0 warnings, 0 erreurs"
  else
    LINT_ERR=$(echo "$LINT_OUTPUT" | grep -c "error" || true)
    LINT_WARN=$(echo "$LINT_OUTPUT" | grep -c "warning" || true)
    fail "oxlint: ${LINT_ERR} erreurs, ${LINT_WARN} warnings" "$LINT_ERR"
    echo "$LINT_OUTPUT" | tail -20 | sed 's/^/    /'
  fi
fi

# ══════════════════════════════════════════════════════════════
# FIXE 3/5: i18n Key Parity
# ══════════════════════════════════════════════════════════════
section "3/5  i18n Key Parity (fr / en / ar)"

if node scripts/check-i18n.mjs 2>&1; then
  pass "i18n key parity: toutes les clés sont présentes dans les 3 langues"
else
  fail "i18n key parity: clés manquantes détectées" 1
fi

# ══════════════════════════════════════════════════════════════
# MODULAIRE 4/5: Audit grep rules (scripts/verify-rules/*.rule)
# ══════════════════════════════════════════════════════════════
RULES_DIR="scripts/verify-rules"
RULE_COUNT=0

for rulefile in "$RULES_DIR"/*.rule; do
  [ -f "$rulefile" ] || continue
  [[ "$(basename "$rulefile")" == "00-TEMPLATE"* ]] && continue
  ((RULE_COUNT++))
done

section "4/5  Audit grep rules (${RULE_COUNT} règles dans ${RULES_DIR}/)"

for rulefile in "$RULES_DIR"/*.rule; do
  [ -f "$rulefile" ] || continue
  [[ "$(basename "$rulefile")" == "00-TEMPLATE"* ]] && continue

  # Reset variables
  RULE_NAME=""
  RULE_DESC=""
  RULE_SEVERITY="error"
  RULE_GREP_PATTERN=""
  RULE_GREP_INCLUDES=""
  RULE_GREP_PATHS=""
  RULE_GREP_EXCLUDES=""
  RULE_USE_GREP_L=false
  RULE_GREP_SEARCH=""
  RULE_USE_MULTI_PATTERN=false
  RULE_USE_CUSTOM=false

  # Source the rule file
  source "$rulefile"

  [ -z "$RULE_NAME" ] && continue

  # Build exclude grep chain
  EXCLUDE_CHAIN=""
  if [ -n "$RULE_GREP_EXCLUDES" ]; then
    IFS='|' read -ra EXCLUDES <<< "$RULE_GREP_EXCLUDES"
    for excl in "${EXCLUDES[@]}"; do
      EXCLUDE_CHAIN="$EXCLUDE_CHAIN | grep -v \"$excl\""
    done
  fi

  # Run the appropriate grep command
  if [ "$RULE_USE_CUSTOM" = true ]; then
    COUNT=$(run_custom_rule 2>/dev/null || echo "0")
  elif [ "$RULE_USE_GREP_L" = true ]; then
    CMD="grep -rL \"$RULE_GREP_SEARCH\" $RULE_GREP_INCLUDES $RULE_GREP_PATHS"
    [ -n "$EXCLUDE_CHAIN" ] && CMD="$CMD$EXCLUDE_CHAIN"
    COUNT=$(eval "$CMD" | wc -l | tr -d ' ')
  elif [ "$RULE_USE_MULTI_PATTERN" = true ]; then
    PATTERN_ARGS=""
    for pat in "${RULE_GREP_PATTERNS[@]}"; do
      PATTERN_ARGS="$PATTERN_ARGS -e \"$pat\""
    done
    CMD="grep -rn $PATTERN_ARGS $RULE_GREP_INCLUDES $RULE_GREP_PATHS"
    [ -n "$EXCLUDE_CHAIN" ] && CMD="$CMD$EXCLUDE_CHAIN"
    COUNT=$(eval "$CMD" | wc -l | tr -d ' ')
  else
    CMD="grep -rn \"$RULE_GREP_PATTERN\" $RULE_GREP_INCLUDES $RULE_GREP_PATHS"
    [ -n "$EXCLUDE_CHAIN" ] && CMD="$CMD$EXCLUDE_CHAIN"
    COUNT=$(eval "$CMD" | wc -l | tr -d ' ')
  fi

  # Report result
  if [ "$COUNT" -eq 0 ]; then
    pass "$RULE_NAME: 0 occurrence"
  else
    if [ "$RULE_SEVERITY" = "warning" ]; then
      warn "$RULE_NAME: ${COUNT} — $RULE_DESC"
      SHOW_COUNT=5
    else
      fail "$RULE_NAME: ${COUNT} — $RULE_DESC" "$COUNT"
      SHOW_COUNT=10
    fi
    # Show matches
    if [ "$RULE_USE_GREP_L" = true ]; then
      CMD="grep -rL \"$RULE_GREP_SEARCH\" $RULE_GREP_INCLUDES $RULE_GREP_PATHS"
      [ -n "$EXCLUDE_CHAIN" ] && CMD="$CMD$EXCLUDE_CHAIN"
      eval "$CMD" | head -$SHOW_COUNT | sed 's/^/    /'
    elif [ "$RULE_USE_MULTI_PATTERN" = true ]; then
      PATTERN_ARGS=""
      for pat in "${RULE_GREP_PATTERNS[@]}"; do
        PATTERN_ARGS="$PATTERN_ARGS -e \"$pat\""
      done
      CMD="grep -rn $PATTERN_ARGS $RULE_GREP_INCLUDES $RULE_GREP_PATHS"
      [ -n "$EXCLUDE_CHAIN" ] && CMD="$CMD$EXCLUDE_CHAIN"
      eval "$CMD" | head -$SHOW_COUNT | sed 's/^/    /'
    else
      CMD="grep -rn \"$RULE_GREP_PATTERN\" $RULE_GREP_INCLUDES $RULE_GREP_PATHS"
      [ -n "$EXCLUDE_CHAIN" ] && CMD="$CMD$EXCLUDE_CHAIN"
      eval "$CMD" | head -$SHOW_COUNT | sed 's/^/    /'
    fi
  fi
done

# ══════════════════════════════════════════════════════════════
# FIXE 5/5: Tests Vitest
# ══════════════════════════════════════════════════════════════
section "5/5  Tests Vitest"

if [ "$SKIP_TESTS" = true ]; then
  warn "Tests skippés (--skip-tests)"
else
  TEST_OUTPUT=$(npx vitest run 2>&1 || true)
  if echo "$TEST_OUTPUT" | grep -q "Test Files.*passed" && ! echo "$TEST_OUTPUT" | grep -q "failed"; then
    pass "Vitest: tous les tests passent"
  else
    TEST_FAIL=$(echo "$TEST_OUTPUT" | grep -c "FAIL\|×" || true)
    fail "Vitest: ${TEST_FAIL} tests échouent" "$TEST_FAIL"
    echo "$TEST_OUTPUT" | tail -30 | sed 's/^/    /'
  fi
fi

# ══════════════════════════════════════════════════════════════
# RÉSUMÉ FINAL
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  RÉSUMÉ FINAL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Checks passés:    ${GREEN}${PASSED_CHECKS}${NC}"
echo -e "  Checks échoués:   ${RED}${FAILED_CHECKS}${NC}"
echo -e "  Erreurs totales:  ${RED}${TOTAL_ERRORS}${NC}"
echo -e "  Warnings:         ${YELLOW}${TOTAL_WARNINGS}${NC}"
echo ""

if [ "$TOTAL_ERRORS" -eq 0 ] && [ "$FAILED_CHECKS" -eq 0 ]; then
  echo -e "  ${GREEN}✅ VÉRIFICATION PASSÉE — 0 erreur, 0 check échoué${NC}"
  echo -e "  ${GREEN}   Le code est prêt pour production.${NC}"
  echo ""
  echo -e "  ${YELLOW}💡 Pour ajouter un nouveau check:${NC}"
  echo -e "  ${YELLOW}   cp scripts/verify-rules/00-TEMPLATE.rule scripts/verify-rules/NN-nom.rule${NC}"
  echo -e "  ${YELLOW}   Éditer les variables, puis relancer: npm run verify${NC}"
  exit 0
else
  echo -e "  ${RED}❌ VÉRIFICATION ÉCHOUÉE — ${TOTAL_ERRORS} erreurs, ${FAILED_CHECKS} checks échoués${NC}"
  echo -e "  ${YELLOW}   Corriger les erreurs ci-dessus puis relancer: ./scripts/verify.sh${NC}"
  exit 1
fi
