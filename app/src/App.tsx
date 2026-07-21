import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { ThemeProvider } from '@/lib/theme'
import { ToastProvider } from '@/lib/toast'
import { AuthProvider } from '@/lib/auth'
import { LegislationProvider } from '@/lib/legislation'
import { ProtectedLayout } from '@/components/ProtectedRoute'
import { DashboardPage } from '@/pages/DashboardPage'
import { LoginPage } from '@/pages/LoginPage'
import { CustomersPage } from '@/pages/CustomersPage'
import { InvoicesPage } from '@/pages/InvoicesPage'
import { SuppliersPage } from '@/pages/SuppliersPage'
import { PurchaseInvoicesPage } from '@/pages/PurchaseInvoicesPage'
import { BankAccountsPage } from '@/pages/BankAccountsPage'
import { ReportsPage } from '@/pages/ReportsPage'
import { SettingsPage } from '@/pages/SettingsPage'
import { AccountingDashboardPage } from '@/pages/AccountingDashboardPage'
import { JournalEntriesPage } from '@/pages/JournalEntriesPage'
import { GeneralLedgerPage } from '@/pages/GeneralLedgerPage'
import { TrialBalancePage } from '@/pages/TrialBalancePage'
import { ChartAccountsPage } from '@/pages/ChartAccountsPage'
import { QuotesPage } from '@/pages/QuotesPage'
import { CreditNotesPage } from '@/pages/CreditNotesPage'
import { RecurringInvoicesPage } from '@/pages/RecurringInvoicesPage'
import { ProductsPage } from '@/pages/ProductsPage'
import { PurchaseCreditNotesPage } from '@/pages/PurchaseCreditNotesPage'
import { BankTransactionsPage } from '@/pages/BankTransactionsPage'
import { BankReconciliationPage } from '@/pages/BankReconciliationPage'
import { BankRulesPage } from '@/pages/BankRulesPage'
import { BalanceSheetPage } from '@/pages/BalanceSheetPage'
import { CashFlowPage } from '@/pages/CashFlowPage'
import { VatReturnsPage } from '@/pages/VatReturnsPage'
import { JournalsReportPage } from '@/pages/JournalsReportPage'
import { ProjectsPage } from '@/pages/ProjectsPage'
import { FixedAssetsPage } from '@/pages/FixedAssetsPage'
import { EmployeesPage } from '@/pages/EmployeesPage'
import { PayRunsPage } from '@/pages/PayRunsPage'
import { TimesheetsPage } from '@/pages/TimesheetsPage'
import { SalesDashboardPage } from '@/pages/SalesDashboardPage'
import { PurchasesDashboardPage } from '@/pages/PurchasesDashboardPage'
import { BankingDashboardPage } from '@/pages/BankingDashboardPage'
import { HRDashboardPage } from '@/pages/HRDashboardPage'
import { CurrenciesPage } from '@/pages/CurrenciesPage'
import { WorkspacePage } from '@/pages/WorkspacePage'
import { JournalsPage } from '@/pages/JournalsPage'
import { FiscalYearsPage } from '@/pages/FiscalYearsPage'
import { EntryTemplatesPage } from '@/pages/EntryTemplatesPage'
import { ThirdPartyAccountsPage } from '@/pages/ThirdPartyAccountsPage'
import { PaymentGenerationPage } from '@/pages/PaymentGenerationPage'
import { AccountingHomePage } from '@/pages/AccountingHomePage'
import { JournalSaisiePage } from '@/pages/JournalSaisiePage'
import { LettragePage } from '@/pages/LettragePage'
import { SearchEntriesPage } from '@/pages/SearchEntriesPage'
import { JournalClosurePage } from '@/pages/JournalClosurePage'
import { FiscalYearClosurePage } from '@/pages/FiscalYearClosurePage'
import { RecurringEntriesPage } from '@/pages/RecurringEntriesPage'
import { RegularizationPage } from '@/pages/RegularizationPage'
import { PurchaseInvoiceApprovalPage } from '@/pages/PurchaseInvoiceApprovalPage'
import { PaymentDelayReportPage } from '@/pages/PaymentDelayReportPage'
import { CurrencyRevaluationPage } from '@/pages/CurrencyRevaluationPage'
import { PaymentRemindersPage } from '@/pages/PaymentRemindersPage'
import { AnalyticPlansPage } from '@/pages/AnalyticPlansPage'
import { DistributionGrillsPage } from '@/pages/DistributionGrillsPage'
import { BankReconciliationRulesPage } from '@/pages/BankReconciliationRulesPage'
import { BankStatementImportPage } from '@/pages/BankStatementImportPage'
import { EdiTvaPage } from '@/pages/EdiTvaPage'
import { TvsPage } from '@/pages/TvsPage'
import { ProgressiveBalancePage } from '@/pages/ProgressiveBalancePage'
import { CompanySettingsPage } from '@/pages/CompanySettingsPage'
import { FiscalBackupPage } from '@/pages/FiscalBackupPage'
import { BrouillardPage } from '@/pages/BrouillardPage'
import { AgedBalancePage } from '@/pages/AgedBalancePage'
import { EcheancierPage } from '@/pages/EcheancierPage'
import { GrandLivreTiersPage } from '@/pages/GrandLivreTiersPage'
import { FECExportPage } from '@/pages/FECExportPage'
import { SIGPage } from '@/pages/SIGPage'
import { AnalyticBalancePage } from '@/pages/AnalyticBalancePage'
import { AnalyticSectionsPage } from '@/pages/AnalyticSectionsPage'
import { BudgetsPage } from '@/pages/BudgetsPage'
import { TreasuryDashboardPage } from '@/pages/TreasuryDashboardPage'
import { TreasuryForecastPage } from '@/pages/TreasuryForecastPage'
import { PaymentOrdersPage } from '@/pages/PaymentOrdersPage'
import { SupplierInvoiceAutomationPage } from '@/pages/SupplierInvoiceAutomationPage'
import { CollectionDashboardPage } from '@/pages/CollectionDashboardPage'
import { SalesOrdersPage } from '@/pages/SalesOrdersPage'
import { DeliveryNotesPage } from '@/pages/DeliveryNotesPage'
import { CustomerPaymentsPage } from '@/pages/CustomerPaymentsPage'
import { PurchaseOrdersPage } from '@/pages/PurchaseOrdersPage'
import { GoodsReceiptPage } from '@/pages/GoodsReceiptPage'
import { SupplierPaymentsPage } from '@/pages/SupplierPaymentsPage'
import { WarehousesPage } from '@/pages/WarehousesPage'
import { StockQuantitiesPage } from '@/pages/StockQuantitiesPage'
import { StockMovementsPage } from '@/pages/StockMovementsPage'
import { InventoryPage } from '@/pages/InventoryPage'
import { ReorderPage } from '@/pages/ReorderPage'
import { PriceListsPage } from '@/pages/PriceListsPage'
import { GescomTransferPage } from '@/pages/GescomTransferPage'
import { BOMPage } from '@/pages/BOMPage'
import { ManufacturingOrdersPage } from '@/pages/ManufacturingOrdersPage'
import { RoutingsPage } from '@/pages/RoutingsPage'
import { MachinesPage } from '@/pages/MachinesPage'
import { ToolingsPage } from '@/pages/ToolingsPage'
import { ManufacturingOrderDetailPage } from '@/pages/ManufacturingOrderDetailPage'
import { SubcontractingOrdersPage, SubcontractingShipmentsPage, SubcontractingReceiptsPage, SubcontractingSupervisorPage } from '@/pages/SubcontractingPages'
import { MRPPage, MRPPendingDocsPage } from '@/pages/MRPPages'
import { ForecastsPage } from '@/pages/ForecastsPage'
import { PlanningPage } from '@/pages/PlanningPage'
import { WorkflowsPage, EquivalencesPage, OFDocumentAccessPage } from '@/pages/ComplementaryPages'
import { ProductionDashboardPage } from '@/pages/ProductionDashboardPage'
import { PaySlipsPage } from '@/pages/PaySlipsPage'
import { PayrollAccountingPage } from '@/pages/PayrollAccountingPage'
import { LeaveRequestsPage } from '@/pages/LeaveRequestsPage'
import { ContractsPage } from '@/pages/ContractsPage'
import { LegalDeclarationsPage } from '@/pages/LegalDeclarationsPage'
import { FinancialDashboardPage } from '@/pages/FinancialDashboardPage'
import { BIReportingPage } from '@/pages/BIReportingPage'
import { BudgetTrackingPage } from '@/pages/BudgetTrackingPage'
import { BudgetCommitmentsPage } from '@/pages/BudgetCommitmentsPage'
import { DataExportPage } from '@/pages/DataExportPage'
import { ImportPage } from '@/pages/ImportPage'
import { TeamPage } from '@/pages/TeamPage'
import { OnboardingPage } from '@/pages/OnboardingPage'
import { SignupPage } from '@/pages/SignupPage'
import { AcceptInvitationPage } from '@/pages/AcceptInvitationPage'
import { AuditLogPage } from '@/pages/AuditLogPage'
import { TrainingPage } from '@/pages/TrainingPage'
import { EInvoicePage } from '@/pages/EInvoicePage'
import { SageImportPage } from '@/pages/SageImportPage'
import { AccountantPortalPage } from '@/pages/AccountantPortalPage'
import { SepaTransferPage } from '@/pages/SepaTransferPage'
import { PayrollCalcPage } from '@/pages/PayrollCalcPage'
import { LiasseFiscalePage } from '@/pages/LiasseFiscalePage'
import { MultiCompanyPage } from '@/pages/MultiCompanyPage'
import { ModuleHubPage, SubGroupHubPage } from '@/components/ModuleHub'
import { ProspectsPage, RepresentativesPage, WarehouseLocationsPage, QualityCheckPage, PickListPage, SerialNumbersPage, ProductBatchesPage, DocumentTemplatesPage, DeliverySchedulePage, ProductSubstitutesPage, DormantStockPage } from '@/pages/Phase2Pages'
import { MCFPage, TreasuryTransfersPage, CreditLinesPage, InvestmentsPage, ValueDateTrackingPage, TreasuryRecurringPage, ConsolidatedTreasuryPage } from '@/pages/Phase3Pages'
import { PayrollComponentsPage, PayrollTemplatesPage, SalaryAdvancesPage, DSNPage, DPAEPage, LegalWatchPage, ExpenseReportsPage, PayRecallsPage, PayrollArchivePage, InterviewsPage } from '@/pages/Phase4Pages'
import { AssetDepreciationPlansPage, AssetFamiliesPage, AssetRevaluationPage, BatchDisposalPage, AssetFromEntryPage } from '@/pages/Phase5Pages'

function App() {
  return (
    <ThemeProvider>
      <AuthProvider>
        <LegislationProvider>
        <ToastProvider>
          <BrowserRouter>
            <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/signup" element={<SignupPage />} />
          <Route path="/accept-invitation" element={<AcceptInvitationPage />} />
          <Route path="/onboarding" element={<OnboardingPage />} />

          <Route element={<ProtectedLayout />}>
          {/* Dashboard */}
          <Route path="/" element={<DashboardPage />} />
          <Route path="/dashboard" element={<DashboardPage />} />
          <Route path="/dashboard/customers" element={<CustomersPage />} />
          <Route path="/dashboard/suppliers" element={<SuppliersPage />} />
          <Route path="/dashboard/products" element={<ProductsPage />} />
          <Route path="/dashboard/financial" element={<AccountingDashboardPage />} />
          <Route path="/dashboard/workspace" element={<WorkspacePage />} />

          {/* Commercial Hub */}
          <Route path="/commercial" element={<ModuleHubPage moduleId="commercial" />} />

          {/* Sales */}
          <Route path="/sales" element={<SubGroupHubPage moduleId="commercial" sectionIndex={0} />} />
          <Route path="/sales/customers" element={<CustomersPage />} />
          <Route path="/sales/invoices" element={<InvoicesPage />} />
          <Route path="/sales/quotes" element={<QuotesPage />} />
          <Route path="/sales/credits" element={<CreditNotesPage />} />
          <Route path="/sales/recurring" element={<RecurringInvoicesPage />} />
          <Route path="/sales/orders" element={<SalesOrdersPage />} />
          <Route path="/sales/delivery-notes" element={<DeliveryNotesPage />} />
          <Route path="/sales/payments" element={<CustomerPaymentsPage />} />
          <Route path="/sales/e-invoice" element={<EInvoicePage />} />

          {/* Purchases */}
          <Route path="/purchases" element={<SubGroupHubPage moduleId="commercial" sectionIndex={1} />} />
          <Route path="/purchases/suppliers" element={<SuppliersPage />} />
          <Route path="/purchases/invoices" element={<PurchaseInvoicesPage />} />
          <Route path="/purchases/credits" element={<PurchaseCreditNotesPage />} />
          <Route path="/purchases/products" element={<ProductsPage />} />
          <Route path="/purchases/automation" element={<SupplierInvoiceAutomationPage />} />
          <Route path="/purchases/orders" element={<PurchaseOrdersPage />} />
          <Route path="/purchases/goods-receipts" element={<GoodsReceiptPage />} />
          <Route path="/purchases/payments" element={<SupplierPaymentsPage />} />

          {/* Accounting */}
          <Route path="/accounting" element={<ModuleHubPage moduleId="accounting" />} />
          <Route path="/accounting/structure" element={<SubGroupHubPage moduleId="accounting" sectionIndex={0} />} />
          <Route path="/accounting/traitement" element={<SubGroupHubPage moduleId="accounting" sectionIndex={1} />} />
          <Route path="/accounting/etats" element={<SubGroupHubPage moduleId="accounting" sectionIndex={2} />} />
          <Route path="/accounting/journal-entries" element={<JournalEntriesPage />} />
          <Route path="/accounting/treatment/journal-entry" element={<JournalSaisiePage />} />
          <Route path="/accounting/treatment/lettrage" element={<LettragePage />} />
          <Route path="/accounting/treatment/search" element={<SearchEntriesPage />} />
          <Route path="/accounting/treatment/journal-closure" element={<JournalClosurePage />} />
          <Route path="/accounting/treatment/fiscal-year-closure" element={<FiscalYearClosurePage />} />
          <Route path="/accounting/treatment/recurring-entries" element={<RecurringEntriesPage />} />
          <Route path="/accounting/treatment/regularization" element={<RegularizationPage />} />
          <Route path="/purchases/approval" element={<PurchaseInvoiceApprovalPage />} />
          <Route path="/accounting/reports/payment-delay" element={<PaymentDelayReportPage />} />
          <Route path="/accounting/reports/currency-revaluation" element={<CurrencyRevaluationPage />} />
          <Route path="/accounting/treatment/payment-reminders" element={<PaymentRemindersPage />} />
          <Route path="/accounting/structure/analytic-plans" element={<AnalyticPlansPage />} />
          <Route path="/accounting/structure/distribution-grills" element={<DistributionGrillsPage />} />
          <Route path="/accounting/treatment/bank-reconciliation-rules" element={<BankReconciliationRulesPage />} />
          <Route path="/accounting/treatment/bank-statement-import" element={<BankStatementImportPage />} />
          <Route path="/accounting/treatment/edi-tva" element={<EdiTvaPage />} />
          <Route path="/accounting/reports/tvs" element={<TvsPage />} />
          <Route path="/accounting/reports/progressive-balance" element={<ProgressiveBalancePage />} />
          <Route path="/settings/company-settings" element={<CompanySettingsPage />} />
          <Route path="/accounting/reports/fiscal-backup" element={<FiscalBackupPage />} />
          <Route path="/accounting/general-ledger" element={<GeneralLedgerPage />} />
          <Route path="/accounting/trial-balance" element={<TrialBalancePage />} />
          <Route path="/accounting/chart-accounts" element={<ChartAccountsPage />} />
          <Route path="/accounting/home" element={<AccountingHomePage />} />
          <Route path="/accounting/third-party" element={<ThirdPartyAccountsPage />} />
          <Route path="/accounting/payment-generation" element={<PaymentGenerationPage />} />
          <Route path="/accounting/journals" element={<JournalsPage />} />
          <Route path="/accounting/entry-templates" element={<EntryTemplatesPage />} />
          <Route path="/accounting/structure/analytic" element={<AnalyticSectionsPage />} />
          <Route path="/accounting/structure/budgets" element={<BudgetsPage />} />
          <Route path="/accounting/structure/budget-commitments" element={<BudgetCommitmentsPage />} />

          {/* Banking */}
          <Route path="/banking" element={<BankAccountsPage />} />
          <Route path="/banking/accounts" element={<BankAccountsPage />} />
          <Route path="/banking/transactions" element={<BankTransactionsPage />} />
          <Route path="/banking/reconciliation" element={<BankReconciliationPage />} />
          <Route path="/banking/rules" element={<BankRulesPage />} />

          {/* Treasury */}
          <Route path="/treasury" element={<ModuleHubPage moduleId="treasury" />} />
          <Route path="/treasury/dashboard" element={<TreasuryDashboardPage />} />
          <Route path="/treasury/forecast" element={<TreasuryForecastPage />} />
          <Route path="/treasury/payment-orders" element={<PaymentOrdersPage />} />
          <Route path="/treasury/collections" element={<CollectionDashboardPage />} />

          {/* Stock */}
          <Route path="/stock" element={<ModuleHubPage moduleId="stock" />} />
          <Route path="/stock/warehouses" element={<WarehousesPage />} />
          <Route path="/stock/quantities" element={<StockQuantitiesPage />} />
          <Route path="/stock/movements" element={<StockMovementsPage />} />
          <Route path="/stock/inventory" element={<InventoryPage />} />
          <Route path="/stock/reorder" element={<ReorderPage />} />
          <Route path="/stock/price-lists" element={<PriceListsPage />} />
          <Route path="/stock/transfer" element={<GescomTransferPage />} />
          <Route path="/stock/boms" element={<BOMPage />} />
          <Route path="/stock/manufacturing" element={<ManufacturingOrdersPage />} />

          {/* Production */}
          <Route path="/production" element={<ModuleHubPage moduleId="production" />} />
          <Route path="/production/manufacturing" element={<SubGroupHubPage moduleId="production" sectionIndex={0} />} />
          <Route path="/production/subcontracting" element={<SubGroupHubPage moduleId="production" sectionIndex={1} />} />
          <Route path="/production/planning" element={<SubGroupHubPage moduleId="production" sectionIndex={2} />} />
          <Route path="/production/routings" element={<RoutingsPage />} />
          <Route path="/production/machines" element={<MachinesPage />} />
          <Route path="/production/toolings" element={<ToolingsPage />} />
          <Route path="/production/subcontracting/orders" element={<SubcontractingOrdersPage />} />
          <Route path="/production/subcontracting/shipments" element={<SubcontractingShipmentsPage />} />
          <Route path="/production/subcontracting/receipts" element={<SubcontractingReceiptsPage />} />
          <Route path="/production/subcontracting/supervisor" element={<SubcontractingSupervisorPage />} />
          <Route path="/production/of/:id" element={<ManufacturingOrderDetailPage />} />
          <Route path="/production/mrp" element={<MRPPage />} />
          <Route path="/production/mrp/pending" element={<MRPPendingDocsPage />} />
          <Route path="/production/forecasts" element={<ForecastsPage />} />
          <Route path="/production/planning" element={<PlanningPage />} />
          <Route path="/production/dashboard" element={<ProductionDashboardPage />} />
          <Route path="/production/workflows" element={<WorkflowsPage />} />
          <Route path="/production/equivalences" element={<EquivalencesPage />} />
          <Route path="/production/of-access" element={<OFDocumentAccessPage />} />

          {/* Reports */}
          <Route path="/reports" element={<ReportsPage />} />
          <Route path="/reports/profit-loss" element={<ReportsPage />} />
          <Route path="/reports/balance-sheet" element={<BalanceSheetPage />} />
          <Route path="/reports/trial-balance" element={<TrialBalancePage />} />
          <Route path="/reports/cash-flow" element={<CashFlowPage />} />
          <Route path="/reports/vat" element={<VatReturnsPage />} />
          <Route path="/reports/journals" element={<JournalsReportPage />} />
          <Route path="/accounting/states/brouillard" element={<BrouillardPage />} />
          <Route path="/accounting/states/aged-balance" element={<AgedBalancePage />} />
          <Route path="/accounting/states/echeancier" element={<EcheancierPage />} />
          <Route path="/accounting/states/general-ledger-tiers" element={<GrandLivreTiersPage />} />
          <Route path="/accounting/states/fec" element={<FECExportPage />} />
          <Route path="/accounting/accountant-portal" element={<AccountantPortalPage />} />
          <Route path="/treasury/sepa" element={<SepaTransferPage />} />
          <Route path="/hr/payroll-calc" element={<PayrollCalcPage />} />
          <Route path="/accounting/liasse-fiscale" element={<LiasseFiscalePage />} />
          <Route path="/settings/multi-company" element={<MultiCompanyPage />} />
          <Route path="/accounting/states/sig" element={<SIGPage />} />
          <Route path="/accounting/states/analytic-balance" element={<AnalyticBalancePage />} />

          {/* Projects & Fixed Assets */}
          <Route path="/accounting/projects" element={<ProjectsPage />} />
          <Route path="/accounting/fixed-assets" element={<FixedAssetsPage />} />

          {/* HR & Payroll */}
          <Route path="/hr" element={<ModuleHubPage moduleId="hr" />} />
          <Route path="/hr/employees" element={<EmployeesPage />} />
          <Route path="/hr/pay-runs" element={<PayRunsPage />} />
          <Route path="/hr/timesheets" element={<TimesheetsPage />} />
          <Route path="/hr/pay-slips" element={<PaySlipsPage />} />
          <Route path="/hr/payroll-accounting" element={<PayrollAccountingPage />} />
          <Route path="/hr/leave-requests" element={<LeaveRequestsPage />} />
          <Route path="/hr/contracts" element={<ContractsPage />} />
          <Route path="/hr/declarations" element={<LegalDeclarationsPage />} />

          {/* Dashboards */}
          <Route path="/dashboard/sales" element={<SalesDashboardPage />} />
          <Route path="/dashboard/purchases" element={<PurchasesDashboardPage />} />
          <Route path="/dashboard/banking" element={<BankingDashboardPage />} />
          <Route path="/dashboard/hr" element={<HRDashboardPage />} />

          {/* Settings */}
          <Route path="/settings" element={<ModuleHubPage moduleId="system" />} />
          <Route path="/settings/configuration" element={<SubGroupHubPage moduleId="system" sectionIndex={0} />} />
          <Route path="/settings/data" element={<SubGroupHubPage moduleId="system" sectionIndex={1} />} />
          <Route path="/settings/company" element={<SettingsPage />} />
          <Route path="/settings/chart-accounts" element={<SettingsPage />} />
          <Route path="/settings/users" element={<SettingsPage />} />
          <Route path="/settings/integrations" element={<SettingsPage />} />
          <Route path="/settings/modules" element={<SettingsPage />} />
          <Route path="/settings/data-export" element={<DataExportPage />} />
          <Route path="/settings/import" element={<ImportPage />} />
          <Route path="/settings/import/sage" element={<SageImportPage />} />
          <Route path="/settings/team" element={<TeamPage />} />
          <Route path="/settings/currencies" element={<CurrenciesPage />} />
          <Route path="/system/fiscal-years" element={<FiscalYearsPage />} />
          <Route path="/system/audit-log" element={<AuditLogPage />} />

          {/* Reporting & BI */}
          <Route path="/reporting" element={<ModuleHubPage moduleId="reporting" />} />
          <Route path="/reporting/financial" element={<FinancialDashboardPage />} />
          <Route path="/reporting/bi" element={<BIReportingPage />} />
          <Route path="/reporting/budget" element={<BudgetTrackingPage />} />

          {/* HR Training */}
          <Route path="/hr/training" element={<TrainingPage />} />

          {/* Phase 2: GesCom */}
          <Route path="/commercial/prospects" element={<ProspectsPage />} />
          <Route path="/commercial/representatives" element={<RepresentativesPage />} />
          <Route path="/commercial/delivery-schedules" element={<DeliverySchedulePage />} />
          <Route path="/stock/warehouse-locations" element={<WarehouseLocationsPage />} />
          <Route path="/stock/quality-checks" element={<QualityCheckPage />} />
          <Route path="/stock/pick-lists" element={<PickListPage />} />
          <Route path="/stock/serial-numbers" element={<SerialNumbersPage />} />
          <Route path="/stock/product-batches" element={<ProductBatchesPage />} />
          <Route path="/stock/product-substitutes" element={<ProductSubstitutesPage />} />
          <Route path="/stock/dormant-stock" element={<DormantStockPage />} />
          <Route path="/settings/document-templates" element={<DocumentTemplatesPage />} />

          {/* Phase 3: Treasury */}
          <Route path="/treasury/mcf" element={<MCFPage />} />
          <Route path="/treasury/transfers" element={<TreasuryTransfersPage />} />
          <Route path="/treasury/credit-lines" element={<CreditLinesPage />} />
          <Route path="/treasury/investments" element={<InvestmentsPage />} />
          <Route path="/treasury/value-dates" element={<ValueDateTrackingPage />} />
          <Route path="/treasury/recurring" element={<TreasuryRecurringPage />} />
          <Route path="/treasury/consolidated" element={<ConsolidatedTreasuryPage />} />

          {/* Phase 4: Payroll & HR */}
          <Route path="/hr/payroll-components" element={<PayrollComponentsPage />} />
          <Route path="/hr/payroll-templates" element={<PayrollTemplatesPage />} />
          <Route path="/hr/salary-advances" element={<SalaryAdvancesPage />} />
          <Route path="/hr/dsn" element={<DSNPage />} />
          <Route path="/hr/dpae" element={<DPAEPage />} />
          <Route path="/hr/legal-watch" element={<LegalWatchPage />} />
          <Route path="/hr/expense-reports" element={<ExpenseReportsPage />} />
          <Route path="/hr/pay-recalls" element={<PayRecallsPage />} />
          <Route path="/hr/payroll-archives" element={<PayrollArchivePage />} />
          <Route path="/hr/interviews" element={<InterviewsPage />} />

          {/* Phase 5: Fixed Assets */}
          <Route path="/accounting/asset-depreciation-plans" element={<AssetDepreciationPlansPage />} />
          <Route path="/accounting/asset-families" element={<AssetFamiliesPage />} />
          <Route path="/accounting/asset-revaluations" element={<AssetRevaluationPage />} />
          <Route path="/accounting/asset-batch-disposals" element={<BatchDisposalPage />} />
          <Route path="/accounting/asset-from-entry" element={<AssetFromEntryPage />} />
          </Route>
        </Routes>
        </BrowserRouter>
        </ToastProvider>
        </LegislationProvider>
    </AuthProvider>
    </ThemeProvider>
  )
}

export default App
