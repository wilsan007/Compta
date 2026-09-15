// @ts-nocheck
// businessFunctions.ts — Wrappers pour les fonctions SQL métier critiques
// (migrations 87-89). Toutes les fonctions appellent des RPC PostgreSQL
// SECURITY DEFINER côté serveur pour garantir l'intégrité et l'isolation.

import { supabase } from '@/lib/supabase'

// ============================================================
// PAIE (migration 87)
// ============================================================

/** Calcule un bulletin de paie (brut → net) et le crée/met à jour en base.
 *  LOT4-02 : Le moteur SQL lit payroll_legal_parameters (PMSS, CSG, CRDS) et
 *  payroll_tax_grids pour les taux. Si payRunId est fourni, les éléments
 *  variables (heures supp, primes, acomptes) sont intégrés. */
export async function calculatePayslip(employeeId: string, period: string, payRunId?: string) {
  const params: Record<string, any> = {
    p_employee_id: employeeId,
    p_period: period,
  }
  if (payRunId) params.p_pay_run_id = payRunId
  const { data, error } = await supabase.rpc('calculate_payslip', params)
  if (error) throw error
  return data
}

/** Génère une déclaration DSN mensuelle agrégée */
export async function generateDsn(period: string) {
  const { data, error } = await supabase.rpc('generate_dsn', {
    p_period: period,
  })
  if (error) throw error
  return data
}

// ============================================================
// TVA (migration 87)
// ============================================================

/** Calcule la TVA CA3 pour une période (collectée + déductible) */
export async function calculateVatCa3(periodStart: string, periodEnd: string) {
  const { data, error } = await supabase.rpc('calculate_vat_ca3', {
    p_period_start: periodStart,
    p_period_end: periodEnd,
  })
  if (error) throw error
  return data
}

/** Génère une déclaration TVA CA3 en base */
export async function generateVatReturn(periodStart: string, periodEnd: string) {
  const { data, error } = await supabase.rpc('generate_vat_return', {
    p_period_start: periodStart,
    p_period_end: periodEnd,
  })
  if (error) throw error
  return data
}

// ============================================================
// COMPTABILITÉ (migration 87)
// ============================================================

/** Génère le bilan (actif/passif) pour un exercice */
export async function generateBalanceSheet(fiscalYearId: string) {
  const { data, error } = await supabase.rpc('generate_balance_sheet', {
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data
}

/** Génère le compte de résultat (charges/produits) */
export async function generateProfitLoss(fiscalYearId: string) {
  const { data, error } = await supabase.rpc('generate_profit_loss', {
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data
}

/** Clôture un exercice : écriture de solde, résultat, nouvel exercice */
export async function closeFiscalYearRpc(fiscalYearId: string) {
  const { data, error } = await supabase.rpc('close_fiscal_year', {
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data
}

// ============================================================
// IMMOBILISATIONS (migration 88)
// ============================================================

/** Calcule l'amortissement d'une immobilisation pour une période */
export async function calculateDepreciation(assetId: string, period?: string) {
  const { data, error } = await supabase.rpc('calculate_depreciation', {
    p_asset_id: assetId,
    p_period: period,
  })
  if (error) throw error
  return data
}

// ============================================================
// LETTRAGE & RAPPROCHEMENT (migration 88)
// ============================================================

/** Lettrage automatique des comptes tiers */
export async function autoLetterAccounts(accountCode?: string, tolerance?: number) {
  const { data, error } = await supabase.rpc('auto_letter_accounts', {
    p_account_code: accountCode,
    p_tolerance: tolerance,
  })
  if (error) throw error
  return data
}

/** Rapprochement bancaire intelligent */
export async function smartBankReconciliation(
  bankAccountId: string,
  fromDate?: string,
  toDate?: string
) {
  const { data, error } = await supabase.rpc('smart_bank_reconciliation', {
    p_bank_account_id: bankAccountId,
    p_from_date: fromDate,
    p_to_date: toDate,
  })
  if (error) throw error
  return data
}

// ============================================================
// STOCK (migration 88)
// ============================================================

/** Valorisation des stocks (CUMP / FIFO / LIFO) */
export async function calculateStockValuation(method?: string, warehouseId?: string) {
  const { data, error } = await supabase.rpc('calculate_stock_valuation', {
    p_method: method,
    p_warehouse_id: warehouseId,
  })
  if (error) throw error
  return data
}

// ============================================================
// TRÉSORERIE (migration 88)
// ============================================================

/** Prévisions de trésorerie à N jours */
export async function cashFlowForecast(days?: number) {
  const { data, error } = await supabase.rpc('cash_flow_forecast', {
    p_days: days,
  })
  if (error) throw error
  return data
}

// ============================================================
// RH / CONGÉS (migration 88)
// ============================================================

/** Calcule les droits aux congés payés (2.5j/mois) */
export async function calculateLeaveAcquisition(employeeId: string, year?: number) {
  const { data, error } = await supabase.rpc('calculate_leave_acquisition', {
    p_employee_id: employeeId,
    p_year: year,
  })
  if (error) throw error
  return data
}

/** Calcule l'indemnité de rupture conventionnelle / licenciement */
export async function calculateSeverancePay(employeeId: string, exitDate?: string) {
  const { data, error } = await supabase.rpc('calculate_severance_pay', {
    p_employee_id: employeeId,
    p_exit_date: exitDate,
  })
  if (error) throw error
  return data
}

// ============================================================
// ÉCHÉANCES (migration 88)
// ============================================================

/** Calcule les échéances de paiement selon les conditions */
export async function calculatePaymentDueDates(
  invoiceDate: string,
  paymentTermsId: string
) {
  const { data, error } = await supabase.rpc('calculate_payment_due_dates', {
    p_invoice_date: invoiceDate,
    p_payment_terms_id: paymentTermsId,
  })
  if (error) throw error
  return data
}

// ============================================================
// ÉTATS COMPTABLES (migration 88)
// ============================================================

/** Génère le grand livre */
export async function generateGeneralLedgerRpc(
  fromDate?: string,
  toDate?: string,
  accountCode?: string
) {
  const { data, error } = await supabase.rpc('generate_general_ledger', {
    p_from_date: fromDate,
    p_to_date: toDate,
    p_account_code: accountCode,
  })
  if (error) throw error
  return data
}

/** Génère la balance générale */
export async function generateTrialBalanceRpc(fromDate?: string, toDate?: string) {
  const { data, error } = await supabase.rpc('generate_trial_balance', {
    p_from_date: fromDate,
    p_to_date: toDate,
  })
  if (error) throw error
  return data
}

/** Génère les écritures de régularisation (provisions créances douteuses) */
export async function generateAdjustingEntries(fiscalYearId: string) {
  const { data, error } = await supabase.rpc('generate_adjusting_entries', {
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data
}

// ============================================================
// MEDIUM — Pénalités, Commissions, Scoring (migration 89)
// ============================================================

/** Calcule les pénalités de retard (Art L441-10 CDC) */
export async function calculateLatePaymentPenalties(invoiceId: string) {
  const { data, error } = await supabase.rpc('calculate_late_payment_penalties', {
    p_invoice_id: invoiceId,
  })
  if (error) throw error
  return data
}

/** Calcule les commissions des commerciaux */
export async function calculateSalesCommissions(period?: string, repId?: string) {
  const { data, error } = await supabase.rpc('calculate_sales_commissions', {
    p_period: period,
    p_rep_id: repId,
  })
  if (error) throw error
  return data
}

/** Scoring de risque client (0-100, rating A-E) */
export async function customerCreditScore(customerId: string) {
  const { data, error } = await supabase.rpc('customer_credit_score', {
    p_customer_id: customerId,
  })
  if (error) throw error
  return data
}

// ============================================================
// MEDIUM — Projets, Provisions, Production (migration 89)
// ============================================================

/** Rentabilité projet (EAC, ETC, CPI, marge) */
export async function calculateProjectProfitability(projectId: string) {
  const { data, error } = await supabase.rpc('calculate_project_profitability', {
    p_project_id: projectId,
  })
  if (error) throw error
  return data
}

/** Provisions (créances douteuses + stocks obsolètes) */
export async function calculateProvisions(fiscalYearId: string) {
  const { data, error } = await supabase.rpc('calculate_provisions', {
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data
}

/** CCA / PCA avec répartition mensuelle */
export async function postDeferredCharge(
  entryId: string,
  type: 'cca' | 'pca',
  amount: number,
  months?: number
) {
  const { data, error } = await supabase.rpc('post_deferred_charge', {
    p_entry_id: entryId,
    p_type: type,
    p_amount: amount,
    p_months: months,
  })
  if (error) throw error
  return data
}

/** Annexe comptable (6 sections) */
export async function generateAccountingAnnex(fiscalYearId: string) {
  const { data, error } = await supabase.rpc('generate_accounting_annex', {
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data
}

/** Coût de production d'un ordre de fabrication */
export async function calculateProductionCost(manufacturingOrderId: string) {
  const { data, error } = await supabase.rpc('calculate_production_cost', {
    p_manufacturing_order_id: manufacturingOrderId,
  })
  if (error) throw error
  return data
}

/** Écarts d'inventaire (théorique vs réel) */
export async function calculateInventoryVariance(warehouseId?: string) {
  const { data, error } = await supabase.rpc('calculate_inventory_variance', {
    p_warehouse_id: warehouseId,
  })
  if (error) throw error
  return data
}

// ============================================================
// ACHATS — Rapprochement 3 voies (migration 89)
// ============================================================

/** Rapprochement 3 voies (commande / réception / facture) */
export async function performThreeWayMatch(purchaseInvoiceId: string) {
  const { data, error } = await supabase.rpc('perform_three_way_match', {
    p_purchase_invoice_id: purchaseInvoiceId,
  })
  if (error) throw error
  return data
}

// ============================================================
// PRODUCTION — MRP & Nomenclatures (migration 89)
// ============================================================

/** Lance le calcul des besoins nets (MRP) */
export async function runMRP(productId: string, depth?: number) {
  const { data, error } = await supabase.rpc('run_mrp', {
    p_product_id: productId,
    p_depth: depth || 5,
  })
  if (error) throw error
  return data
}

/** Éclate une nomenclature récursivement */
export async function explodeBOMRecursive(productId: string, quantity: number) {
  const { data, error } = await supabase.rpc('explode_bom_recursive', {
    p_product_id: productId,
    p_quantity: quantity,
  })
  if (error) throw error
  return data
}

// ============================================================
// PAIE — Heures sup, IJSS, Préavis (migration 89)
// ============================================================

/** Calcule la rémunération des heures supplémentaires */
export async function calculateOvertimePay(employeeId: string, hours: number, rate: number) {
  const { data, error } = await supabase.rpc('calculate_overtime_pay', {
    p_employee_id: employeeId,
    p_hours: hours,
    p_rate: rate,
  })
  if (error) throw error
  return data
}

/** Calcule les indemnités journalières de sécurité sociale (IJSS) */
export async function calculateSickLeavePay(employeeId: string, days: number) {
  const { data, error } = await supabase.rpc('calculate_sick_leave_pay', {
    p_employee_id: employeeId,
    p_days: days,
  })
  if (error) throw error
  return data
}

/** Calcule l'indemnité compensatrice de préavis */
export async function calculateNoticeCompensation(employeeId: string) {
  const { data, error } = await supabase.rpc('calculate_notice_compensation', {
    p_employee_id: employeeId,
  })
  if (error) throw error
  return data
}

// ============================================================
// BANQUE — Rapprochement automatique (migration 89)
// ============================================================

/** Rapprochement bancaire automatique par score de similarité */
export async function autoReconcileByScore(bankAccountId: string) {
  const { data, error } = await supabase.rpc('auto_reconcile_by_score', {
    p_bank_account_id: bankAccountId,
  })
  if (error) throw error
  return data
}

/** Applique les règles de rapprochement bancaire paramétrées */
export async function applyBankReconciliationRules(bankAccountId: string) {
  const { data, error } = await supabase.rpc('apply_bank_reconciliation_rules', {
    p_bank_account_id: bankAccountId,
  })
  if (error) throw error
  return data
}

// ============================================================
// COMMERCIAL — Crédit client (migration 89)
// ============================================================

/** Vérifie la limite de crédit d'un client */
export async function checkCustomerCreditLimit(customerId: string) {
  const { data, error } = await supabase.rpc('check_customer_credit_limit', {
    p_customer_id: customerId,
  })
  if (error) throw error
  return data
}

// ============================================================
// STOCK — Conversion d'unités & coûts logistiques (migration 89)
// ============================================================

/** Conversion d'unités de mesure */
export async function convertUom(fromUnit: string, toUnit: string, quantity: number) {
  const { data, error } = await supabase.rpc('convert_uom', {
    p_from_unit: fromUnit,
    p_to_unit: toUnit,
    p_quantity: quantity,
  })
  if (error) throw error
  return data
}

/** Répartition des coûts logistiques sur une réception */
export async function distributeLandedCost(receiptId: string, costItems: any) {
  const { data, error } = await supabase.rpc('distribute_landed_cost', {
    p_receipt_id: receiptId,
    p_cost_items: costItems,
  })
  if (error) throw error
  return data
}

/** Recherche d'un produit équivalent (substitution) */
export async function findEquivalentProduct(productId: string) {
  const { data, error } = await supabase.rpc('find_equivalent_product', {
    p_product_id: productId,
  })
  if (error) throw error
  return data
}

// ============================================================
// NF525 — Clôture & Attestation (migration 89)
// ============================================================

/** Clôture une période NF525 (fige la chaîne) */
export async function closeNf525Period(periodEnd: string) {
  const { data, error } = await supabase.rpc('close_nf525_period', {
    p_period_end: periodEnd,
  })
  if (error) throw error
  return data
}

/** Génère l'attestation NF525 pour une période */
export async function getNf525Attestation(periodStart: string, periodEnd: string) {
  const { data, error } = await supabase.rpc('get_nf525_attestation', {
    p_period_start: periodStart,
    p_period_end: periodEnd,
  })
  if (error) throw error
  return data
}
