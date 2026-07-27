import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { ThemeProvider } from '@/lib/theme'
import { ToastProvider } from '@/lib/toast'
import { AuthProvider } from '@/lib/auth'
import { LegislationProvider } from '@/lib/legislation'
import { ProtectedLayout, AdminRoute } from '@/components/ProtectedRoute'
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
import { BankReconciliationPdfPage } from '@/pages/BankReconciliationPdfPage'
import { BankRulesPage } from '@/pages/BankRulesPage'
import { BankSyncPage } from '@/pages/BankSyncPage'
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
import { ExchangeRatesPage } from '@/pages/ExchangeRatesPage'
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
import { ExchangeGainLossPage } from '@/pages/ExchangeGainLossPage'
import { CheckBooksPage } from '@/pages/CheckBooksPage'
import { EdiTvaPage } from '@/pages/EdiTvaPage'
import { TvsPage } from '@/pages/TvsPage'
import { ProgressiveBalancePage } from '@/pages/ProgressiveBalancePage'
import { CompanySettingsPage } from '@/pages/CompanySettingsPage'
import { TaxGridSettingsPage } from '@/pages/TaxGridSettingsPage'
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
import { LeaveRulesPage } from '@/pages/settings/LeaveRulesPage'
import { LeaveBalancesPage } from '@/pages/hr/LeaveBalancesPage'
import { LeavePlanningPage } from '@/pages/hr/LeavePlanningPage'
import { ManagerLeaveApprovalsPage } from '@/pages/employee/ManagerLeaveApprovalsPage'
import { PayrollPreparationPage } from '@/pages/payroll/PayrollPreparationPage'
import { MealVouchersPage } from '@/pages/payroll/MealVouchersPage'
import { SepaPaymentsPage } from '@/pages/payroll/SepaPaymentsPage'
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
import { TenantSelectionPage } from '@/pages/TenantSelectionPage'
import { AuditLogPage } from '@/pages/AuditLogPage'
import { TrainingPage } from '@/pages/TrainingPage'
import { SocialDeclarationsPage } from '@/pages/hr/SocialDeclarationsPage'
import { BdesPage } from '@/pages/hr/BdesPage'
import { DocumentManagementPage } from '@/pages/hr/DocumentManagementPage'
import { RhRequestsPage } from '@/pages/hr/RhRequestsPage'
import { RhKnowledgeBasePage } from '@/pages/hr/RhKnowledgeBasePage'
import { EmployeeDocumentsPage as EmployeeSelfDocsPage } from '@/pages/employee/EmployeeDocumentsPage'
import { EInvoicePage } from '@/pages/EInvoicePage'
import { SageImportPage } from '@/pages/SageImportPage'
import { AccountantPortalPage } from '@/pages/AccountantPortalPage'
import { SepaTransferPage } from '@/pages/SepaTransferPage'
import { PayrollCalcPage } from '@/pages/PayrollCalcPage'
import { CorporateTaxCalcPage } from '@/pages/CorporateTaxCalcPage'
import { LiasseFiscalePage } from '@/pages/LiasseFiscalePage'
import { MultiCompanyPage } from '@/pages/MultiCompanyPage'
import { ModuleHubPage, SubGroupHubPage } from '@/components/ModuleHub'
import { ModuleHomePage } from '@/components/ModuleHomePage'
import { ProspectsPage, RepresentativesPage, WarehouseLocationsPage, QualityCheckPage, PickListPage, SerialNumbersPage, ProductBatchesPage, DocumentTemplatesPage, DeliverySchedulePage, ProductSubstitutesPage, DormantStockPage } from '@/pages/Phase2Pages'
import { PromotionsPage } from '@/pages/PromotionsPage'
import { ProductGridsPage } from '@/pages/ProductGridsPage'
import { StockAlertsPage } from '@/pages/StockAlertsPage'
import { OpportunitiesPage } from '@/pages/crm/OpportunitiesPage'
import { ActivitiesPage } from '@/pages/crm/ActivitiesPage'
import { CampaignsPage } from '@/pages/crm/CampaignsPage'
import { TerritoriesPage } from '@/pages/crm/TerritoriesPage'
import { SalesForecastPage } from '@/pages/crm/SalesForecastPage'
import { TicketsPage } from '@/pages/crm/TicketsPage'
import { ServiceContractsPage } from '@/pages/crm/ServiceContractsPage'
import { KnowledgeBasePage } from '@/pages/crm/KnowledgeBasePage'
import { CustomerPortalPage } from '@/pages/crm/CustomerPortalPage'
import { MCFPage, TreasuryTransfersPage, CreditLinesPage, InvestmentsPage, ValueDateTrackingPage, TreasuryRecurringPage, ConsolidatedTreasuryPage } from '@/pages/Phase3Pages'
import { PayrollComponentsPage, PayrollTemplatesPage, SalaryAdvancesPage, DSNPage, DPAEPage, LegalWatchPage, ExpenseReportsPage, PayRecallsPage, PayrollArchivePage, InterviewsPage } from '@/pages/Phase4Pages'
import { AssetDepreciationPlansPage, AssetFamiliesPage, AssetRevaluationPage, BatchDisposalPage, AssetFromEntryPage } from '@/pages/Phase5Pages'
import { BatchEntryPage, AutoLabelRulesPage, ExtournePage, CarryForwardPage, LettrageDifferencesPage, AccountingControlsPage, CashControlPage, FECAttestationPage, TierRIBsPage, IFRSAdjustmentsPage, TaxPaymentsPage, CustomReportTemplatesPage, DeferredPrintingPage, JournalAccessRightsPage, VATOnCollectionsPage } from '@/pages/Phase6Pages'
import { TaxRatesPage } from '@/pages/TaxRatesPage'
import { FiscalPositionsPage } from '@/pages/FiscalPositionsPage'
import { AccountTagsPage } from '@/pages/AccountTagsPage'
import { PaymentTermsPage } from '@/pages/PaymentTermsPage'
import { SaisieParPiecePage } from '@/pages/SaisieParPiecePage'
import { JustificatifSoldePage } from '@/pages/JustificatifSoldePage'
import { EtatRapprochementPage } from '@/pages/EtatRapprochementPage'
import { ReminderLevelsPage } from '@/pages/ReminderLevelsPage'
import { RevisionCyclesPage } from '@/pages/RevisionCyclesPage'
import { FusionComptesPage } from '@/pages/FusionComptesPage'
import { PlanReportingPage } from '@/pages/PlanReportingPage'
import { CompactionPage } from '@/pages/CompactionPage'
import { RGPDPage } from '@/pages/RGPDPage'
import { GridTemplatesPage, PaymentTemplatesComptaPage, StandardLabelsPage, AnalyticJournalCodesPage } from '@/pages/Phase7DPages'
import { AnalyticODEntryPage, ThirdPartyInquiryPage, AnalyticInquiryPage, ReimputationPage } from '@/pages/Phase7DInquiryPages'
import { PartnerCategoriesPage } from '@/pages/PartnerCategoriesPage'
import { Customer360Page } from '@/pages/Customer360Page'
import { PurchaseRequestsPage } from '@/pages/PurchaseRequestsPage'
import { SupplierPriceListsPage } from '@/pages/SupplierPriceListsPage'
import { SupplierDeliverySchedulePage } from '@/pages/SupplierDeliverySchedulePage'
import { PosTerminalPage } from '@/pages/PosTerminalPage'
import { PosSessionsPage } from '@/pages/PosSessionsPage'
import { PosStatsPage } from '@/pages/PosStatsPage'
import { OnlinePaymentPage } from '@/pages/OnlinePaymentPage'
import { SharedDocumentPage } from '@/pages/SharedDocumentPage'
import { RevenueSimulationPage } from '@/pages/sales/RevenueSimulationPage'
import { MarginAnalysisPage } from '@/pages/sales/MarginAnalysisPage'
import { WorkHardshipPage } from '@/pages/WorkHardshipPage'
import { CareerHistoryPage } from '@/pages/CareerHistoryPage'
import { CPFPage } from '@/pages/CPFPage'
import { EmployeeDocumentsPage } from '@/pages/EmployeeDocumentsPage'
import { WorkStoppagesPage } from '@/pages/WorkStoppagesPage'
import { MedicalExamsPage } from '@/pages/MedicalExamsPage'
import { ExpenseCategoriesPage } from '@/pages/ExpenseCategoriesPage'
import { EmployeeExitPage } from '@/pages/EmployeeExitPage'
import { InterviewCampaignsPage } from '@/pages/InterviewCampaignsPage'
import { EmployeeExpensesPage } from '@/pages/EmployeeExpensesPage'
import { ManagerExpenseApprovalsPage } from '@/pages/ManagerExpenseApprovalsPage'
import { EmployeeInterviewsPage } from '@/pages/EmployeeInterviewsPage'
import { EmployeeLayout } from '@/components/EmployeeLayout'
import { EmployeeDashboardPage } from '@/pages/employee/EmployeeDashboardPage'
import { EmployeeProfilePage } from '@/pages/employee/EmployeeProfilePage'
import { EmployeeLeavesPage } from '@/pages/employee/EmployeeLeavesPage'
import { RhReportsPage } from '@/pages/hr/RhReportsPage'

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
          <Route path="/select-tenant" element={<TenantSelectionPage />} />
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
          <Route path="/commercial/home" element={<ModuleHomePage moduleId="commercial" />} />

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
          <Route path="/accounting/home" element={<AccountingHomePage />} />
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
          <Route path="/settings/company-settings" element={<AdminRoute><CompanySettingsPage /></AdminRoute>} />
          <Route path="/accounting/reports/fiscal-backup" element={<AdminRoute><FiscalBackupPage /></AdminRoute>} />
          <Route path="/accounting/general-ledger" element={<GeneralLedgerPage />} />
          <Route path="/accounting/trial-balance" element={<TrialBalancePage />} />
          <Route path="/accounting/chart-accounts" element={<ChartAccountsPage />} />
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
          <Route path="/banking/reconciliation-pdf" element={<BankReconciliationPdfPage />} />
          <Route path="/banking/rules" element={<BankRulesPage />} />
          <Route path="/banking/sync" element={<BankSyncPage />} />
          <Route path="/banking/exchange-gain-loss" element={<ExchangeGainLossPage />} />
          <Route path="/banking/check-books" element={<CheckBooksPage />} />

          {/* Treasury */}
          <Route path="/treasury" element={<ModuleHubPage moduleId="treasury" />} />
          <Route path="/treasury/home" element={<ModuleHomePage moduleId="treasury" />} />
          <Route path="/treasury/dashboard" element={<TreasuryDashboardPage />} />
          <Route path="/treasury/forecast" element={<TreasuryForecastPage />} />
          <Route path="/treasury/payment-orders" element={<AdminRoute><PaymentOrdersPage /></AdminRoute>} />
          <Route path="/treasury/collections" element={<CollectionDashboardPage />} />

          {/* Stock */}
          <Route path="/stock" element={<ModuleHubPage moduleId="stock" />} />
          <Route path="/stock/home" element={<ModuleHomePage moduleId="stock" />} />
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
          <Route path="/production/home" element={<ModuleHomePage moduleId="production" />} />
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
          <Route path="/treasury/sepa" element={<AdminRoute><SepaTransferPage /></AdminRoute>} />
          <Route path="/hr/payroll-calc" element={<PayrollCalcPage />} />
          <Route path="/accounting/corporate-tax-calc" element={<CorporateTaxCalcPage />} />
          <Route path="/accounting/liasse-fiscale" element={<LiasseFiscalePage />} />
          <Route path="/settings/multi-company" element={<AdminRoute><MultiCompanyPage /></AdminRoute>} />
          <Route path="/accounting/states/sig" element={<SIGPage />} />
          <Route path="/accounting/states/analytic-balance" element={<AnalyticBalancePage />} />

          {/* Projects & Fixed Assets */}
          <Route path="/accounting/projects" element={<ProjectsPage />} />
          <Route path="/accounting/fixed-assets" element={<FixedAssetsPage />} />

          {/* HR & Payroll */}
          <Route path="/hr" element={<ModuleHubPage moduleId="hr" />} />
          <Route path="/hr/home" element={<ModuleHomePage moduleId="hr" />} />
          <Route path="/hr/employees" element={<EmployeesPage />} />
          <Route path="/hr/pay-runs" element={<PayRunsPage />} />
          <Route path="/hr/timesheets" element={<TimesheetsPage />} />
          <Route path="/hr/pay-slips" element={<PaySlipsPage />} />
          <Route path="/hr/payroll-accounting" element={<PayrollAccountingPage />} />
          <Route path="/hr/leave-requests" element={<LeaveRequestsPage />} />
          <Route path="/hr/leave-rules" element={<LeaveRulesPage />} />
          <Route path="/hr/leave-balances" element={<LeaveBalancesPage />} />
          <Route path="/hr/leave-planning" element={<LeavePlanningPage />} />
          <Route path="/hr/leave-approvals" element={<ManagerLeaveApprovalsPage />} />
          <Route path="/hr/payroll-preparation" element={<PayrollPreparationPage />} />
          <Route path="/hr/meal-vouchers" element={<MealVouchersPage />} />
          <Route path="/hr/sepa-payments" element={<SepaPaymentsPage />} />
          <Route path="/hr/contracts" element={<ContractsPage />} />
          <Route path="/hr/declarations" element={<LegalDeclarationsPage />} />
          <Route path="/hr/social-declarations" element={<SocialDeclarationsPage />} />
          <Route path="/hr/bdes" element={<BdesPage />} />
          <Route path="/hr/document-management" element={<DocumentManagementPage />} />
          <Route path="/hr/rh-requests" element={<RhRequestsPage />} />
          <Route path="/hr/knowledge-base" element={<RhKnowledgeBasePage />} />
          <Route path="/employee/documents" element={<EmployeeSelfDocsPage />} />

          {/* Dashboards */}
          <Route path="/dashboard/home" element={<ModuleHomePage moduleId="dashboards" />} />
          <Route path="/dashboard/sales" element={<SalesDashboardPage />} />
          <Route path="/dashboard/purchases" element={<PurchasesDashboardPage />} />
          <Route path="/dashboard/banking" element={<BankingDashboardPage />} />
          <Route path="/dashboard/hr" element={<HRDashboardPage />} />

          {/* Settings */}
          <Route path="/settings" element={<ModuleHubPage moduleId="system" />} />
          <Route path="/settings/home" element={<ModuleHomePage moduleId="system" />} />
          <Route path="/settings/configuration" element={<SubGroupHubPage moduleId="system" sectionIndex={0} />} />
          <Route path="/settings/data" element={<SubGroupHubPage moduleId="system" sectionIndex={1} />} />
          <Route path="/settings/company" element={<AdminRoute><SettingsPage /></AdminRoute>} />
          <Route path="/settings/chart-accounts" element={<AdminRoute><SettingsPage /></AdminRoute>} />
          <Route path="/settings/users" element={<AdminRoute><SettingsPage /></AdminRoute>} />
          <Route path="/settings/integrations" element={<AdminRoute><SettingsPage /></AdminRoute>} />
          <Route path="/settings/modules" element={<AdminRoute><SettingsPage /></AdminRoute>} />
          <Route path="/settings/data-export" element={<AdminRoute><DataExportPage /></AdminRoute>} />
          <Route path="/settings/import" element={<AdminRoute><ImportPage /></AdminRoute>} />
          <Route path="/settings/import/sage" element={<AdminRoute><SageImportPage /></AdminRoute>} />
          <Route path="/settings/team" element={<AdminRoute><TeamPage /></AdminRoute>} />
          <Route path="/settings/currencies" element={<AdminRoute><CurrenciesPage /></AdminRoute>} />
          <Route path="/settings/exchange-rates" element={<AdminRoute><ExchangeRatesPage /></AdminRoute>} />
          <Route path="/settings/tax-grids" element={<AdminRoute><TaxGridSettingsPage /></AdminRoute>} />
          <Route path="/system/fiscal-years" element={<AdminRoute><FiscalYearsPage /></AdminRoute>} />
          <Route path="/system/audit-log" element={<AdminRoute><AuditLogPage /></AdminRoute>} />

          {/* Reporting & BI */}
          <Route path="/reporting" element={<ModuleHubPage moduleId="reporting" />} />
          <Route path="/reporting/home" element={<ModuleHomePage moduleId="reporting" />} />
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
          <Route path="/stock/product-grids" element={<ProductGridsPage />} />
          <Route path="/stock/alerts" element={<StockAlertsPage />} />
          <Route path="/sales/promotions" element={<PromotionsPage />} />
          <Route path="/crm/opportunities" element={<OpportunitiesPage />} />
          <Route path="/crm/activities" element={<ActivitiesPage />} />
          <Route path="/crm/campaigns" element={<CampaignsPage />} />
          <Route path="/crm/territories" element={<TerritoriesPage />} />
          <Route path="/crm/forecasts" element={<SalesForecastPage />} />
          <Route path="/crm/tickets" element={<TicketsPage />} />
          <Route path="/crm/contracts" element={<ServiceContractsPage />} />
          <Route path="/crm/knowledge-base" element={<KnowledgeBasePage />} />
          <Route path="/portal" element={<CustomerPortalPage />} />
          <Route path="/settings/document-templates" element={<AdminRoute><DocumentTemplatesPage /></AdminRoute>} />

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
          <Route path="/hr/hardship" element={<WorkHardshipPage />} />
          <Route path="/hr/career" element={<CareerHistoryPage />} />
          <Route path="/hr/cpf" element={<CPFPage />} />
          <Route path="/hr/employee-documents" element={<EmployeeDocumentsPage />} />
          <Route path="/hr/work-stoppages" element={<WorkStoppagesPage />} />
          <Route path="/hr/medical-exams" element={<MedicalExamsPage />} />
          <Route path="/hr/expense-categories" element={<ExpenseCategoriesPage />} />
          <Route path="/hr/employee-exit" element={<EmployeeExitPage />} />
          <Route path="/hr/interview-campaigns" element={<InterviewCampaignsPage />} />
          <Route path="/hr/my-expenses" element={<EmployeeExpensesPage />} />
          <Route path="/hr/expense-approvals" element={<ManagerExpenseApprovalsPage />} />
          <Route path="/hr/my-interviews" element={<EmployeeInterviewsPage />} />
          <Route path="/hr/reports" element={<RhReportsPage />} />

          {/* ============ Espace Employé ============ */}
          <Route path="/employee" element={<EmployeeLayout />}>
            <Route index element={<EmployeeDashboardPage />} />
            <Route path="leaves" element={<EmployeeLeavesPage />} />
            <Route path="profile" element={<EmployeeProfilePage />} />
            <Route path="expenses" element={<EmployeeExpensesPage />} />
            <Route path="interviews" element={<EmployeeInterviewsPage />} />
            <Route path="documents" element={<EmployeeSelfDocsPage />} />
            <Route path="manager/approvals" element={<ManagerLeaveApprovalsPage />} />
            <Route path="manager/expense-approvals" element={<ManagerExpenseApprovalsPage />} />
          </Route>

          {/* Phase 5: Fixed Assets */}
          <Route path="/accounting/asset-depreciation-plans" element={<AssetDepreciationPlansPage />} />
          <Route path="/accounting/asset-families" element={<AssetFamiliesPage />} />
          <Route path="/accounting/asset-revaluations" element={<AssetRevaluationPage />} />
          <Route path="/accounting/asset-batch-disposals" element={<BatchDisposalPage />} />
          <Route path="/accounting/asset-from-entry" element={<AssetFromEntryPage />} />

          {/* Phase 6: Sage 100 Accounting Features */}
          <Route path="/accounting/batch-entry" element={<BatchEntryPage />} />
          <Route path="/accounting/auto-labels" element={<AutoLabelRulesPage />} />
          <Route path="/accounting/extourne" element={<ExtournePage />} />
          <Route path="/accounting/carry-forward" element={<CarryForwardPage />} />
          <Route path="/accounting/lettrage-differences" element={<LettrageDifferencesPage />} />
          <Route path="/accounting/controls" element={<AccountingControlsPage />} />
          <Route path="/accounting/cash-control" element={<CashControlPage />} />
          <Route path="/accounting/fec-attestations" element={<FECAttestationPage />} />
          <Route path="/accounting/tier-ribs" element={<TierRIBsPage />} />
          <Route path="/accounting/ifrs-adjustments" element={<IFRSAdjustmentsPage />} />
          <Route path="/accounting/tax-payments" element={<TaxPaymentsPage />} />
          <Route path="/accounting/custom-reports" element={<CustomReportTemplatesPage />} />
          <Route path="/accounting/deferred-printing" element={<DeferredPrintingPage />} />
          <Route path="/accounting/journal-access-rights" element={<JournalAccessRightsPage />} />
          <Route path="/accounting/vat-on-collections" element={<VATOnCollectionsPage />} />
          {/* Phase 7A: Sage 100 Critical Features */}
          <Route path="/accounting/tax-rates" element={<TaxRatesPage />} />
          <Route path="/accounting/fiscal-positions" element={<FiscalPositionsPage />} />
          <Route path="/accounting/account-tags" element={<AccountTagsPage />} />
          <Route path="/accounting/payment-terms" element={<PaymentTermsPage />} />
          <Route path="/accounting/treatment/saisie-par-piece" element={<SaisieParPiecePage />} />
          {/* Phase 7B: Sage 100 Medium Features */}
          <Route path="/accounting/justificatif-solde" element={<JustificatifSoldePage />} />
          <Route path="/accounting/etat-rapprochement" element={<EtatRapprochementPage />} />
          <Route path="/accounting/reminder-levels" element={<ReminderLevelsPage />} />
          {/* Phase 7C: Sage 100 Minor Features */}
          <Route path="/accounting/revision-cycles" element={<RevisionCyclesPage />} />
          <Route path="/accounting/fusion-comptes" element={<FusionComptesPage />} />
          <Route path="/accounting/reporting-plans" element={<PlanReportingPage />} />
          <Route path="/accounting/compaction" element={<CompactionPage />} />
          <Route path="/accounting/rgpd" element={<RGPDPage />} />
          {/* Phase 7D: Remaining Sage 100 Features */}
          <Route path="/accounting/grid-templates" element={<GridTemplatesPage />} />
          <Route path="/accounting/payment-templates-compta" element={<PaymentTemplatesComptaPage />} />
          <Route path="/accounting/standard-labels" element={<StandardLabelsPage />} />
          <Route path="/accounting/analytic-journal-codes" element={<AnalyticJournalCodesPage />} />
          <Route path="/accounting/analytic-od-entry" element={<AnalyticODEntryPage />} />
          <Route path="/accounting/third-party-inquiry" element={<ThirdPartyInquiryPage />} />
          <Route path="/accounting/analytic-inquiry" element={<AnalyticInquiryPage />} />
          <Route path="/accounting/reimputation" element={<ReimputationPage />} />
          <Route path="/accounting/partner-categories" element={<PartnerCategoriesPage />} />
          <Route path="/banking/check-books" element={<CheckBooksPage />} />
          <Route path="/banking/exchange-gain-loss" element={<ExchangeGainLossPage />} />
          {/* Sprint B: Customer Advanced */}
          <Route path="/sales/customers/:id/360" element={<Customer360Page />} />
          {/* Sprint C: Purchase Advanced */}
          <Route path="/purchases/requests" element={<PurchaseRequestsPage />} />
          <Route path="/purchases/supplier-price-lists" element={<SupplierPriceListsPage />} />
          <Route path="/purchases/delivery-schedules" element={<SupplierDeliverySchedulePage />} />
          {/* Sprint D: Catalog Extended */}
          <Route path="/sales/promotions" element={<PromotionsPage />} />
          <Route path="/stock/product-grids" element={<ProductGridsPage />} />
          {/* Sprint E: Stock Advanced */}
          <Route path="/stock/alerts" element={<StockAlertsPage />} />
          {/* Sprint H: POS */}
          <Route path="/pos/terminal/:terminalId" element={<PosTerminalPage />} />
          <Route path="/pos/terminal" element={<PosTerminalPage />} />
          <Route path="/pos/sessions" element={<PosSessionsPage />} />
          <Route path="/pos/stats" element={<PosStatsPage />} />
          {/* Sprint I: Dématérialisation */}
          <Route path="/pay/:token" element={<OnlinePaymentPage />} />
          <Route path="/shared/:token" element={<SharedDocumentPage />} />
          {/* Sprint J: Pilotage */}
          <Route path="/sales/simulation" element={<RevenueSimulationPage />} />
          <Route path="/sales/margins" element={<MarginAnalysisPage />} />
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
