import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { ThemeProvider } from '@/lib/theme'
import { ToastProvider } from '@/lib/toast'
import { AuthProvider } from '@/lib/auth'
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
import { TeamPage } from '@/pages/TeamPage'
import { OnboardingPage } from '@/pages/OnboardingPage'
import { AuditLogPage } from '@/pages/AuditLogPage'
import { TrainingPage } from '@/pages/TrainingPage'

function App() {
  return (
    <ThemeProvider>
      <AuthProvider>
        <ToastProvider>
          <BrowserRouter>
            <Routes>
          <Route path="/login" element={<LoginPage />} />
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

          {/* Sales */}
          <Route path="/sales" element={<InvoicesPage />} />
          <Route path="/sales/customers" element={<CustomersPage />} />
          <Route path="/sales/invoices" element={<InvoicesPage />} />
          <Route path="/sales/quotes" element={<QuotesPage />} />
          <Route path="/sales/credits" element={<CreditNotesPage />} />
          <Route path="/sales/recurring" element={<RecurringInvoicesPage />} />
          <Route path="/sales/orders" element={<SalesOrdersPage />} />
          <Route path="/sales/delivery-notes" element={<DeliveryNotesPage />} />
          <Route path="/sales/payments" element={<CustomerPaymentsPage />} />

          {/* Purchases */}
          <Route path="/purchases" element={<PurchaseInvoicesPage />} />
          <Route path="/purchases/suppliers" element={<SuppliersPage />} />
          <Route path="/purchases/invoices" element={<PurchaseInvoicesPage />} />
          <Route path="/purchases/credits" element={<PurchaseCreditNotesPage />} />
          <Route path="/purchases/products" element={<ProductsPage />} />
          <Route path="/purchases/automation" element={<SupplierInvoiceAutomationPage />} />
          <Route path="/purchases/orders" element={<PurchaseOrdersPage />} />
          <Route path="/purchases/goods-receipts" element={<GoodsReceiptPage />} />
          <Route path="/purchases/payments" element={<SupplierPaymentsPage />} />

          {/* Accounting */}
          <Route path="/accounting" element={<AccountingDashboardPage />} />
          <Route path="/accounting/structure" element={<ChartAccountsPage />} />
          <Route path="/accounting/traitement" element={<JournalSaisiePage />} />
          <Route path="/accounting/etats" element={<GeneralLedgerPage />} />
          <Route path="/accounting/journal-entries" element={<JournalEntriesPage />} />
          <Route path="/accounting/treatment/journal-entry" element={<JournalSaisiePage />} />
          <Route path="/accounting/treatment/lettrage" element={<LettragePage />} />
          <Route path="/accounting/treatment/search" element={<SearchEntriesPage />} />
          <Route path="/accounting/treatment/journal-closure" element={<JournalClosurePage />} />
          <Route path="/accounting/treatment/fiscal-year-closure" element={<FiscalYearClosurePage />} />
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
          <Route path="/treasury" element={<TreasuryDashboardPage />} />
          <Route path="/treasury/dashboard" element={<TreasuryDashboardPage />} />
          <Route path="/treasury/forecast" element={<TreasuryForecastPage />} />
          <Route path="/treasury/payment-orders" element={<PaymentOrdersPage />} />
          <Route path="/treasury/collections" element={<CollectionDashboardPage />} />

          {/* Stock */}
          <Route path="/stock" element={<StockQuantitiesPage />} />
          <Route path="/stock/warehouses" element={<WarehousesPage />} />
          <Route path="/stock/quantities" element={<StockQuantitiesPage />} />
          <Route path="/stock/movements" element={<StockMovementsPage />} />
          <Route path="/stock/inventory" element={<InventoryPage />} />
          <Route path="/stock/reorder" element={<ReorderPage />} />
          <Route path="/stock/price-lists" element={<PriceListsPage />} />
          <Route path="/stock/transfer" element={<GescomTransferPage />} />
          <Route path="/stock/boms" element={<BOMPage />} />
          <Route path="/stock/manufacturing" element={<ManufacturingOrdersPage />} />

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
          <Route path="/accounting/states/sig" element={<SIGPage />} />
          <Route path="/accounting/states/analytic-balance" element={<AnalyticBalancePage />} />

          {/* Projects & Fixed Assets */}
          <Route path="/accounting/projects" element={<ProjectsPage />} />
          <Route path="/accounting/fixed-assets" element={<FixedAssetsPage />} />

          {/* HR & Payroll */}
          <Route path="/hr" element={<HRDashboardPage />} />
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
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="/settings/company" element={<SettingsPage />} />
          <Route path="/settings/chart-accounts" element={<SettingsPage />} />
          <Route path="/settings/users" element={<SettingsPage />} />
          <Route path="/settings/integrations" element={<SettingsPage />} />
          <Route path="/settings/data-export" element={<DataExportPage />} />
          <Route path="/settings/team" element={<TeamPage />} />
          <Route path="/settings/currencies" element={<CurrenciesPage />} />
          <Route path="/system/fiscal-years" element={<FiscalYearsPage />} />
          <Route path="/system/audit-log" element={<AuditLogPage />} />

          {/* Reporting & BI */}
          <Route path="/reporting/financial" element={<FinancialDashboardPage />} />
          <Route path="/reporting/bi" element={<BIReportingPage />} />
          <Route path="/reporting/budget" element={<BudgetTrackingPage />} />

          {/* HR Training */}
          <Route path="/hr/training" element={<TrainingPage />} />
          </Route>
        </Routes>
        </BrowserRouter>
      </ToastProvider>
    </AuthProvider>
    </ThemeProvider>
  )
}

export default App
