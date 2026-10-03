// @ts-nocheck
// businessFunctions.ts — Wrappers pour les fonctions SQL métier critiques
// (migrations 87-89). Toutes les fonctions appellent des RPC PostgreSQL
// SECURITY DEFINER côté serveur pour garantir l'intégrité et l'isolation.

import { supabase } from '@/lib/supabase'
import type { VatCode } from '@/lib/vatLines'

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

/** Codes TVA du paramétrage (migration 198) : ceux que portent factures et écritures */
export async function getVatCodes(): Promise<VatCode[]> {
  const { data, error } = await supabase.rpc('get_vat_codes')
  if (error) throw error
  // Le taux revient en `numeric` : PostgREST le rend enchaîne, on le convertit
  // une fois pour que l'appelant fasse des calculs et non des comparaisons de texte.
  const rows = (data ?? []) as unknown as Omit<VatCode, 'rate'> & { rate: number | string | null }[]
  return rows.map((r) => ({ ...r, rate: Number(r.rate) || 0 }))
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
// IMMOBILISATIONS
// ============================================================
// W5 (IMMO-01) : `calculateDepreciation` (RPC `calculate_depreciation`) est
// SUPPRIMÉE — le second moteur. La dotation se demande par
// `generateDepreciationEntry` / `generateDepreciationEntries` de
// `@/lib/queries/accounting`, qui comptabilisent (D 681x / C 28x) et rendent un
// verdict par immobilisation.

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

/** CCA / PCA avec répartition mensuelle (régularisation de l'écran) */
export async function postDeferredCharge(
  regularizationId: string,
  type: 'cca' | 'pca',
  amount?: number,
  months?: number
) {
  const { data, error } = await supabase.rpc('post_deferred_charge', {
    p_regularization_id: regularizationId,
    p_type: type,
    p_amount: amount ?? null,
    p_months: months ?? null,
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

/**
 * Rapprochement 3 voies (commande / réception / facture).
 *
 * W10 : la fonction appelée avant (`perform_three_way_match`) est un
 * DÉCLENCHEUR (`RETURNS trigger`, `BEFORE UPDATE OF approval_status` sur
 * `purchase_invoices`) : PostgREST ne l'expose JAMAIS — l'appel ne pouvait que
 * renvoyer 404. La fonction RÉELLE et appelable est `run_three_way_match` :
 * elle pose le statut `pending` (ce qui fait jouer le contrôle), puis rend
 * `match_status` et les écarts (quantités, prix) ligne à ligne.
 */
export async function performThreeWayMatch(purchaseInvoiceId: string) {
  const { data, error } = await supabase.rpc('run_three_way_match', {
    p_invoice_id: purchaseInvoiceId,
  })
  if (error) throw error
  const row = Array.isArray(data) ? data[0] : data
  return row as {
    match_status: string
    total_ordered: number
    total_received: number
    total_invoiced: number
    price_variance: number
    quantity_variance: number
    line_results: unknown
  } | undefined
}

// ============================================================
// PRODUCTION — MRP & Nomenclatures (migration 89)
// ============================================================

/**
 * Lance le calcul des besoins nets (MRP) sur l'horizon demandé, en jours.
 *
 * W10 : la base expose `run_mrp(p_tenant_id, p_horizon_days)` — la société est
 * celle du contexte (`current_tenant_id()`), donc `p_tenant_id` s'omet et garde
 * son défaut. Le front envoyait `p_product_id` / `p_depth`, deux arguments qui
 * n'existent dans AUCUNE signature : l'appel ne pouvait pas aboutir.
 */
export async function runMRP(horizonDays = 90) {
  const { data, error } = await supabase.rpc('run_mrp', { p_horizon_days: horizonDays })
  if (error) throw error
  return data as {
    product_id: string
    product_name: string
    net_need: number
    suggested_qty: number
    suggested_date: string
    source: string
    is_late: boolean
  }[]
}

// ============================================================
// PAIE — Heures sup, IJSS, Préavis (migration 89)
// ============================================================

/**
 * W5 (RH-04) : ce que la BASE applique à N heures supplémentaires pour un
 * salarié — taux horaire de la société (diviseur de la 256) × majoration
 * (première tranche `overtime_tiers`, sinon le paramètre
 * MAJORATION_HEURES_SUP). L'écran ne transmet AUCUN taux : il ne calcule plus
 * rien, il lit.
 */
export async function previewOvertimePay(employeeId: string, hours: number) {
  const { data, error } = await supabase.rpc('payroll_overtime_preview', {
    p_employee_id: employeeId,
    p_hours: hours,
  })
  if (error) throw error
  return data as {
    heures: number
    taux_horaire_majore: number
    montant: number
    source: 'tranches' | 'parametre'
  }
}

/**
 * W5 (RH-04) : la majoration des heures supplémentaires de la société active.
 * Les écrans de SIMULATION (PayrollCalcPage) la lisent ici au lieu de porter
 * une constante légale en dur.
 */
export async function getOvertimeMajoration() {
  const { data, error } = await supabase.rpc('payroll_overtime_majoration')
  if (error) throw error
  return Number(data ?? 1.25)
}

/**
 * Indemnités journalières de sécurité sociale (IJSS) d'un arrêt de maladie.
 *
 * W10 : la base calcule à partir de l'ARRÊT DÉCLARÉ (`sick_leaves`), pas d'un
 * couple (salarié, jours) inventé par l'écran — `calculate_sick_leave_pay`
 * n'accepte que `p_sick_leave_id`. L'écran doit donc désigner l'arrêt, ce que la
 * fonction lit vraiment : jours d'arrêt, délai de carence, garantie employeur et
 * IJSS. Avant, `p_employee_id` / `p_days` n'existaient dans aucune signature :
 * l'appel ne pouvait pas aboutir.
 */
export async function calculateSickLeavePay(sickLeaveId: string) {
  const { data, error } = await supabase.rpc('calculate_sick_leave_pay', {
    p_sick_leave_id: sickLeaveId,
  })
  if (error) throw error
  const row = Array.isArray(data) ? data[0] : data
  return row as {
    leave_days: number
    waiting_days: number
    retained_days: number
    daily_rate: number
    retention_amount: number
    maintenance_amount: number
    ijss_amount: number
    net_impact: number
  } | undefined
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
//
// W10 : `auto_reconcile_by_score()` et `apply_bank_reconciliation_rules()` sont
// des DÉCLENCHEURS (`RETURNS trigger`) sur `bank_transactions` — le second
// `BEFORE INSERT`, le premier `AFTER INSERT`. PostgREST n'expose jamais une
// fonction de déclencheur : les enveloppes `autoReconcileByScore()` et
// `applyBankReconciliationRules()` (supprimées ici) ne pouvaient QUE échouer, et
// leur bouton prétendait pourtant agir. Les règles s'appliquent à l'import ; la
// seule action réelle offerte est le rapprochement par score déjà branché
// (`smart_bank_reconciliation`, lu par `smartBankReconciliation()`).

// ============================================================
// COMMERCIAL — Crédit client (migration 89)
// ============================================================
//
// W10 : `check_customer_credit_limit()` est un DÉCLENCHEUR (`BEFORE UPDATE` sur
// `sales_orders`) : il refuse une commande qui dépasse la limite, il ne se
// « demande » pas. PostgREST ne l'expose pas — l'enveloppe
// `checkCustomerCreditLimit()` (supprimée ici) ne pouvait pas aboutir. La
// lecture réelle du risque client est `customer_credit_score()`, déjà branchée
// sur l'écran 360 (`customerCreditScore()`).

// ============================================================
// STOCK — Conversion d'unités & coûts logistiques (migration 89)
// ============================================================
//
// W10 : `convertUom()` et `distributeLandedCost()` (supprimées ici) ne
// correspondaient à aucune signature réelle : `convert_uom` attend
// `(p_quantity, p_from_uom_id, p_to_uom_id)` — des IDENTIFIANTS d'unité, pas des
// codes — et `distribute_landed_cost` attend `p_landed_cost_id`, non un
// `p_receipt_id` avec des lignes de coût. Aucun écran ne les appelait : les
// deviner aurait inventé un contrat. Elles reviendront le jour où un écran
// portera l'action, alignées sur la base.

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

/**
 * Clôture une période NF525 (fige la chaîne).
 *
 * W10 : la base raisonne par PÉRIODE au format `YYYY-MM` — c'est ce que les
 * déclencheurs écrivent (`to_char(now(), 'YYYY-MM')`, `to_char(NEW.date,
 * 'YYYY-MM')`) et ce que `get_nf525_attestation` reçoit. L'écran envoyait une
 * DATE de fin (`p_period_end`) : la fonction cherchait les événements d'une
 * période nommée « 2026-09-30 » et n'en trouvait aucun.
 */
export async function closeNf525Period(period: string) {
  const { data, error } = await supabase.rpc('close_nf525_period', {
    p_period: period,
  })
  if (error) throw error
  return data as {
    period: string
    event_count: number
    closing_hash: string
    closed_at: string
  }
}

/**
 * Attestation NF525 d'une période clôturée (`YYYY-MM`), vérifiée contre la
 * chaîne (W10 : une seule période, comme la fonction l'exige).
 */
export async function getNf525Attestation(period: string) {
  const { data, error } = await supabase.rpc('get_nf525_attestation', {
    p_period: period,
  })
  if (error) throw error
  return data
}
