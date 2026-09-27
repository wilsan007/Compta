export * from './core'
export * from './accounting'
export * from './partners'
export * from './sales'
export * from './purchases'
export * from './banking'
export * from './stock'
export * from './production'
export * from './payroll'
export * from './misc'
export * from './customerAdvanced'
export * from './purchaseAdvanced'
export * from './catalogAdvanced'
export * from './posAdvanced'
export * from './dematerialisation'
export * from './crmAdvanced'
export * from './pilotage'
export * from './leavesAbsences'
export * from './socialDeclarations'
export * from './dematRh'
export * from './sprintDE'
export * from './sprintH'
export * from './projectManagement'
export {
  calculatePayslip,
  generateDsn,
  calculateVatCa3,
  generateVatReturn,
  generateBalanceSheet,
  generateProfitLoss,
  closeFiscalYearRpc,
  autoLetterAccounts,
  smartBankReconciliation,
  calculateStockValuation,
  cashFlowForecast,
  calculateLeaveAcquisition,
  calculateSeverancePay,
  calculatePaymentDueDates,
  generateGeneralLedgerRpc,
  generateTrialBalanceRpc,
  generateAdjustingEntries,
  calculateLatePaymentPenalties,
  calculateSalesCommissions,
  customerCreditScore,
  calculateProjectProfitability,
  calculateProvisions,
  postDeferredCharge,
  generateAccountingAnnex,
  calculateProductionCost,
  calculateInventoryVariance,
  performThreeWayMatch,
  runMRP,
  previewOvertimePay,
  getOvertimeMajoration,
  calculateSickLeavePay,
  calculateNoticeCompensation,
  findEquivalentProduct,
  closeNf525Period,
  getNf525Attestation,
} from './businessFunctions'
// W10 : `explodeBOMRecursive`, `autoReconcileByScore`,
// `applyBankReconciliationRules`, `checkCustomerCreditLimit`, `convertUom` et
// `distributeLandedCost` sont retirés — leurs fonctions cibles n'existent pas
// (ou sont des déclencheurs, jamais exposés par PostgREST). Le contrôle
// `scripts/check-rpc-contract.mjs` interdit leur retour.
// W5 (IMMO-01) : l'alias `calculateDepreciationRpc` est retiré avec la RPC
// `calculate_depreciation` — un seul moteur d'amortissement, côté SQL.
