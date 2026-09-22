import { lazy, Suspense } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { ThemeProvider } from '@/lib/theme'
import { ToastProvider } from '@/lib/toast'
import { AuthProvider } from '@/lib/auth'
import { LegislationProvider } from '@/lib/legislation'
import { ConfirmProvider } from '@/lib/hooks/useConfirm'
import { ProtectedLayout, AdminRoute, ProtectedRoute } from '@/components/ProtectedRoute'
import { AppErrorBoundary } from '@/components/AppErrorBoundary'

// PRF-02 : Composants de layout lazy-loaded pour réduire le bundle initial
const ModuleHubPage = lazy(() => import('@/components/ModuleHub').then(m => ({ default: m.ModuleHubPage })))
const SubGroupHubPage = lazy(() => import('@/components/ModuleHub').then(m => ({ default: m.SubGroupHubPage })))
const ModuleHomePage = lazy(() => import('@/components/ModuleHomePage').then(m => ({ default: m.ModuleHomePage })))
const EmployeeLayout = lazy(() => import('@/components/EmployeeLayout').then(m => ({ default: m.EmployeeLayout })))

// PRF-02 : Pages publiques lazy-loaded pour réduire le bundle initial
const LandingPage = lazy(() => import('@/pages/LandingPage').then(m => ({ default: m.LandingPage })))
const TermsPage = lazy(() => import('@/pages/TermsPage').then(m => ({ default: m.TermsPage })))
const PrivacyPage = lazy(() => import('@/pages/PrivacyPage').then(m => ({ default: m.PrivacyPage })))
const LoginPage = lazy(() => import('@/pages/LoginPage').then(m => ({ default: m.LoginPage })))

// Lazy-loaded pages — split into separate chunks so the landing page bundle stays small
const DashboardPage = lazy(() => import('@/pages/DashboardPage').then(m => ({ default: m.DashboardPage })))
const HomePage = lazy(() => import('@/pages/HomePage').then(m => ({ default: m.HomePage })))
const CustomersPage = lazy(() => import('@/pages/CustomersPage').then(m => ({ default: m.CustomersPage })))
const InvoicesPage = lazy(() => import('@/pages/InvoicesPage').then(m => ({ default: m.InvoicesPage })))
const SuppliersPage = lazy(() => import('@/pages/SuppliersPage').then(m => ({ default: m.SuppliersPage })))
const PurchaseInvoicesPage = lazy(() => import('@/pages/PurchaseInvoicesPage').then(m => ({ default: m.PurchaseInvoicesPage })))
const BankAccountsPage = lazy(() => import('@/pages/BankAccountsPage').then(m => ({ default: m.BankAccountsPage })))
const ReportsPage = lazy(() => import('@/pages/ReportsPage').then(m => ({ default: m.ReportsPage })))
const SettingsPage = lazy(() => import('@/pages/SettingsPage').then(m => ({ default: m.SettingsPage })))
const ChartPacksAdminPage = lazy(() => import('@/pages/ChartPacksAdminPage').then(m => ({ default: m.ChartPacksAdminPage })))
const AccountingDashboardPage = lazy(() => import('@/pages/AccountingDashboardPage').then(m => ({ default: m.AccountingDashboardPage })))
const JournalEntriesPage = lazy(() => import('@/pages/JournalEntriesPage').then(m => ({ default: m.JournalEntriesPage })))
const GeneralLedgerPage = lazy(() => import('@/pages/GeneralLedgerPage').then(m => ({ default: m.GeneralLedgerPage })))
const TrialBalancePage = lazy(() => import('@/pages/TrialBalancePage').then(m => ({ default: m.TrialBalancePage })))
const ChartAccountsPage = lazy(() => import('@/pages/ChartAccountsPage').then(m => ({ default: m.ChartAccountsPage })))
const QuotesPage = lazy(() => import('@/pages/QuotesPage').then(m => ({ default: m.QuotesPage })))
const CreditNotesPage = lazy(() => import('@/pages/CreditNotesPage').then(m => ({ default: m.CreditNotesPage })))
const RecurringInvoicesPage = lazy(() => import('@/pages/RecurringInvoicesPage').then(m => ({ default: m.RecurringInvoicesPage })))
const ProductsPage = lazy(() => import('@/pages/ProductsPage').then(m => ({ default: m.ProductsPage })))
const PurchaseCreditNotesPage = lazy(() => import('@/pages/PurchaseCreditNotesPage').then(m => ({ default: m.PurchaseCreditNotesPage })))
const BankTransactionsPage = lazy(() => import('@/pages/BankTransactionsPage').then(m => ({ default: m.BankTransactionsPage })))
const BankReconciliationPage = lazy(() => import('@/pages/BankReconciliationPage').then(m => ({ default: m.BankReconciliationPage })))
const BankReconciliationPdfPage = lazy(() => import('@/pages/BankReconciliationPdfPage').then(m => ({ default: m.BankReconciliationPdfPage })))
const BankRulesPage = lazy(() => import('@/pages/BankRulesPage').then(m => ({ default: m.BankRulesPage })))
const BankSyncPage = lazy(() => import('@/pages/BankSyncPage').then(m => ({ default: m.BankSyncPage })))
const BalanceSheetPage = lazy(() => import('@/pages/BalanceSheetPage').then(m => ({ default: m.BalanceSheetPage })))
const CashFlowPage = lazy(() => import('@/pages/CashFlowPage').then(m => ({ default: m.CashFlowPage })))
const VatReturnsPage = lazy(() => import('@/pages/VatReturnsPage').then(m => ({ default: m.VatReturnsPage })))
const JournalsReportPage = lazy(() => import('@/pages/JournalsReportPage').then(m => ({ default: m.JournalsReportPage })))
const ProjectsPage = lazy(() => import('@/pages/ProjectsPage').then(m => ({ default: m.ProjectsPage })))
const ProjectManagementPage = lazy(() => import('@/pages/ProjectManagementPage').then(m => ({ default: m.ProjectManagementPage })))
const FixedAssetsPage = lazy(() => import('@/pages/FixedAssetsPage').then(m => ({ default: m.FixedAssetsPage })))
const EmployeesPage = lazy(() => import('@/pages/EmployeesPage').then(m => ({ default: m.EmployeesPage })))
const PayRunsPage = lazy(() => import('@/pages/PayRunsPage').then(m => ({ default: m.PayRunsPage })))
const TimesheetsPage = lazy(() => import('@/pages/TimesheetsPage').then(m => ({ default: m.TimesheetsPage })))
const SalesDashboardPage = lazy(() => import('@/pages/SalesDashboardPage').then(m => ({ default: m.SalesDashboardPage })))
const PurchasesDashboardPage = lazy(() => import('@/pages/PurchasesDashboardPage').then(m => ({ default: m.PurchasesDashboardPage })))
const BankingDashboardPage = lazy(() => import('@/pages/BankingDashboardPage').then(m => ({ default: m.BankingDashboardPage })))
const HRDashboardPage = lazy(() => import('@/pages/HRDashboardPage').then(m => ({ default: m.HRDashboardPage })))
const CurrenciesPage = lazy(() => import('@/pages/CurrenciesPage').then(m => ({ default: m.CurrenciesPage })))
const ExchangeRatesPage = lazy(() => import('@/pages/ExchangeRatesPage').then(m => ({ default: m.ExchangeRatesPage })))
const WorkspacePage = lazy(() => import('@/pages/WorkspacePage').then(m => ({ default: m.WorkspacePage })))
const JournalsPage = lazy(() => import('@/pages/JournalsPage').then(m => ({ default: m.JournalsPage })))
const FiscalYearsPage = lazy(() => import('@/pages/FiscalYearsPage').then(m => ({ default: m.FiscalYearsPage })))
const EntryTemplatesPage = lazy(() => import('@/pages/EntryTemplatesPage').then(m => ({ default: m.EntryTemplatesPage })))
const ThirdPartyAccountsPage = lazy(() => import('@/pages/ThirdPartyAccountsPage').then(m => ({ default: m.ThirdPartyAccountsPage })))
const PaymentGenerationPage = lazy(() => import('@/pages/PaymentGenerationPage').then(m => ({ default: m.PaymentGenerationPage })))
const AccountingHomePage = lazy(() => import('@/pages/AccountingHomePage').then(m => ({ default: m.AccountingHomePage })))
const JournalSaisiePage = lazy(() => import('@/pages/JournalSaisiePage').then(m => ({ default: m.JournalSaisiePage })))
const LettragePage = lazy(() => import('@/pages/LettragePage').then(m => ({ default: m.LettragePage })))
const SearchEntriesPage = lazy(() => import('@/pages/SearchEntriesPage').then(m => ({ default: m.SearchEntriesPage })))
const JournalClosurePage = lazy(() => import('@/pages/JournalClosurePage').then(m => ({ default: m.JournalClosurePage })))
const FiscalYearClosurePage = lazy(() => import('@/pages/FiscalYearClosurePage').then(m => ({ default: m.FiscalYearClosurePage })))
const RecurringEntriesPage = lazy(() => import('@/pages/RecurringEntriesPage').then(m => ({ default: m.RecurringEntriesPage })))
const RegularizationPage = lazy(() => import('@/pages/RegularizationPage').then(m => ({ default: m.RegularizationPage })))
const PurchaseInvoiceApprovalPage = lazy(() => import('@/pages/PurchaseInvoiceApprovalPage').then(m => ({ default: m.PurchaseInvoiceApprovalPage })))
const PaymentDelayReportPage = lazy(() => import('@/pages/PaymentDelayReportPage').then(m => ({ default: m.PaymentDelayReportPage })))
const CurrencyRevaluationPage = lazy(() => import('@/pages/CurrencyRevaluationPage').then(m => ({ default: m.CurrencyRevaluationPage })))
const PaymentRemindersPage = lazy(() => import('@/pages/PaymentRemindersPage').then(m => ({ default: m.PaymentRemindersPage })))
const AnalyticPlansPage = lazy(() => import('@/pages/AnalyticPlansPage').then(m => ({ default: m.AnalyticPlansPage })))
const DistributionGrillsPage = lazy(() => import('@/pages/DistributionGrillsPage').then(m => ({ default: m.DistributionGrillsPage })))
const BankReconciliationRulesPage = lazy(() => import('@/pages/BankReconciliationRulesPage').then(m => ({ default: m.BankReconciliationRulesPage })))
const BankStatementImportPage = lazy(() => import('@/pages/BankStatementImportPage').then(m => ({ default: m.BankStatementImportPage })))
const ExchangeGainLossPage = lazy(() => import('@/pages/ExchangeGainLossPage').then(m => ({ default: m.ExchangeGainLossPage })))
const CheckBooksPage = lazy(() => import('@/pages/CheckBooksPage').then(m => ({ default: m.CheckBooksPage })))
const EdiTvaPage = lazy(() => import('@/pages/EdiTvaPage').then(m => ({ default: m.EdiTvaPage })))
const TvsPage = lazy(() => import('@/pages/TvsPage').then(m => ({ default: m.TvsPage })))
const ProgressiveBalancePage = lazy(() => import('@/pages/ProgressiveBalancePage').then(m => ({ default: m.ProgressiveBalancePage })))
const CompanySettingsPage = lazy(() => import('@/pages/CompanySettingsPage').then(m => ({ default: m.CompanySettingsPage })))
const TaxGridSettingsPage = lazy(() => import('@/pages/TaxGridSettingsPage').then(m => ({ default: m.TaxGridSettingsPage })))
const FiscalBackupPage = lazy(() => import('@/pages/FiscalBackupPage').then(m => ({ default: m.FiscalBackupPage })))
const BrouillardPage = lazy(() => import('@/pages/BrouillardPage').then(m => ({ default: m.BrouillardPage })))
const AgedBalancePage = lazy(() => import('@/pages/AgedBalancePage').then(m => ({ default: m.AgedBalancePage })))
const EcheancierPage = lazy(() => import('@/pages/EcheancierPage').then(m => ({ default: m.EcheancierPage })))
const GrandLivreTiersPage = lazy(() => import('@/pages/GrandLivreTiersPage').then(m => ({ default: m.GrandLivreTiersPage })))
const FECExportPage = lazy(() => import('@/pages/FECExportPage').then(m => ({ default: m.FECExportPage })))
const SIGPage = lazy(() => import('@/pages/SIGPage').then(m => ({ default: m.SIGPage })))
const AnalyticBalancePage = lazy(() => import('@/pages/AnalyticBalancePage').then(m => ({ default: m.AnalyticBalancePage })))
const AnalyticSectionsPage = lazy(() => import('@/pages/AnalyticSectionsPage').then(m => ({ default: m.AnalyticSectionsPage })))
const BudgetsPage = lazy(() => import('@/pages/BudgetsPage').then(m => ({ default: m.BudgetsPage })))
const TreasuryDashboardPage = lazy(() => import('@/pages/TreasuryDashboardPage').then(m => ({ default: m.TreasuryDashboardPage })))
const TreasuryForecastPage = lazy(() => import('@/pages/TreasuryForecastPage').then(m => ({ default: m.TreasuryForecastPage })))
const PaymentOrdersPage = lazy(() => import('@/pages/PaymentOrdersPage').then(m => ({ default: m.PaymentOrdersPage })))
const SupplierInvoiceAutomationPage = lazy(() => import('@/pages/SupplierInvoiceAutomationPage').then(m => ({ default: m.SupplierInvoiceAutomationPage })))
const CollectionDashboardPage = lazy(() => import('@/pages/CollectionDashboardPage').then(m => ({ default: m.CollectionDashboardPage })))
const SalesOrdersPage = lazy(() => import('@/pages/SalesOrdersPage').then(m => ({ default: m.SalesOrdersPage })))
const DeliveryNotesPage = lazy(() => import('@/pages/DeliveryNotesPage').then(m => ({ default: m.DeliveryNotesPage })))
const CustomerPaymentsPage = lazy(() => import('@/pages/CustomerPaymentsPage').then(m => ({ default: m.CustomerPaymentsPage })))
const PurchaseOrdersPage = lazy(() => import('@/pages/PurchaseOrdersPage').then(m => ({ default: m.PurchaseOrdersPage })))
const GoodsReceiptPage = lazy(() => import('@/pages/GoodsReceiptPage').then(m => ({ default: m.GoodsReceiptPage })))
const SupplierPaymentsPage = lazy(() => import('@/pages/SupplierPaymentsPage').then(m => ({ default: m.SupplierPaymentsPage })))
const WarehousesPage = lazy(() => import('@/pages/WarehousesPage').then(m => ({ default: m.WarehousesPage })))
const StockQuantitiesPage = lazy(() => import('@/pages/StockQuantitiesPage').then(m => ({ default: m.StockQuantitiesPage })))
const StockMovementsPage = lazy(() => import('@/pages/StockMovementsPage').then(m => ({ default: m.StockMovementsPage })))
const InventoryPage = lazy(() => import('@/pages/InventoryPage').then(m => ({ default: m.InventoryPage })))
const ReorderPage = lazy(() => import('@/pages/ReorderPage').then(m => ({ default: m.ReorderPage })))
const PriceListsPage = lazy(() => import('@/pages/PriceListsPage').then(m => ({ default: m.PriceListsPage })))
const GescomTransferPage = lazy(() => import('@/pages/GescomTransferPage').then(m => ({ default: m.GescomTransferPage })))
const BOMPage = lazy(() => import('@/pages/BOMPage').then(m => ({ default: m.BOMPage })))
const ManufacturingOrdersPage = lazy(() => import('@/pages/ManufacturingOrdersPage').then(m => ({ default: m.ManufacturingOrdersPage })))
const RoutingsPage = lazy(() => import('@/pages/RoutingsPage').then(m => ({ default: m.RoutingsPage })))
const MachinesPage = lazy(() => import('@/pages/MachinesPage').then(m => ({ default: m.MachinesPage })))
const ToolingsPage = lazy(() => import('@/pages/ToolingsPage').then(m => ({ default: m.ToolingsPage })))
const ManufacturingOrderDetailPage = lazy(() => import('@/pages/ManufacturingOrderDetailPage').then(m => ({ default: m.ManufacturingOrderDetailPage })))
const SubcontractingOrdersPage = lazy(() => import('@/pages/SubcontractingPages').then(m => ({ default: m.SubcontractingOrdersPage })))
const SubcontractingShipmentsPage = lazy(() => import('@/pages/SubcontractingPages').then(m => ({ default: m.SubcontractingShipmentsPage })))
const SubcontractingReceiptsPage = lazy(() => import('@/pages/SubcontractingPages').then(m => ({ default: m.SubcontractingReceiptsPage })))
const SubcontractingSupervisorPage = lazy(() => import('@/pages/SubcontractingPages').then(m => ({ default: m.SubcontractingSupervisorPage })))
const MRPPage = lazy(() => import('@/pages/MRPPages').then(m => ({ default: m.MRPPage })))
const MRPPendingDocsPage = lazy(() => import('@/pages/MRPPages').then(m => ({ default: m.MRPPendingDocsPage })))
const ForecastsPage = lazy(() => import('@/pages/ForecastsPage').then(m => ({ default: m.ForecastsPage })))
const PlanningPage = lazy(() => import('@/pages/PlanningPage').then(m => ({ default: m.PlanningPage })))
const WorkflowsPage = lazy(() => import('@/pages/ComplementaryPages').then(m => ({ default: m.WorkflowsPage })))
const EquivalencesPage = lazy(() => import('@/pages/ComplementaryPages').then(m => ({ default: m.EquivalencesPage })))
const OFDocumentAccessPage = lazy(() => import('@/pages/ComplementaryPages').then(m => ({ default: m.OFDocumentAccessPage })))
const ProductionDashboardPage = lazy(() => import('@/pages/ProductionDashboardPage').then(m => ({ default: m.ProductionDashboardPage })))
const PaySlipsPage = lazy(() => import('@/pages/PaySlipsPage').then(m => ({ default: m.PaySlipsPage })))
const PayrollAccountingPage = lazy(() => import('@/pages/PayrollAccountingPage').then(m => ({ default: m.PayrollAccountingPage })))
const LeaveRequestsPage = lazy(() => import('@/pages/LeaveRequestsPage').then(m => ({ default: m.LeaveRequestsPage })))
const LeaveRulesPage = lazy(() => import('@/pages/settings/LeaveRulesPage').then(m => ({ default: m.LeaveRulesPage })))
const ApiWebhooksPage = lazy(() => import('@/pages/settings/ApiWebhooksPage').then(m => ({ default: m.ApiWebhooksPage })))
const EmailTemplatesPage = lazy(() => import('@/pages/settings/EmailTemplatesPage').then(m => ({ default: m.EmailTemplatesPage })))
const TwoFactorPage = lazy(() => import('@/pages/settings/TwoFactorPage').then(m => ({ default: m.TwoFactorPage })))
const ApiDocsPage = lazy(() => import('@/pages/settings/ApiDocsPage').then(m => ({ default: m.ApiDocsPage })))
const Nf525AuditPage = lazy(() => import('@/pages/settings/Nf525AuditPage').then(m => ({ default: m.Nf525AuditPage })))
const LeaveBalancesPage = lazy(() => import('@/pages/hr/LeaveBalancesPage').then(m => ({ default: m.LeaveBalancesPage })))
const LeavePlanningPage = lazy(() => import('@/pages/hr/LeavePlanningPage').then(m => ({ default: m.LeavePlanningPage })))
const ManagerLeaveApprovalsPage = lazy(() => import('@/pages/employee/ManagerLeaveApprovalsPage').then(m => ({ default: m.ManagerLeaveApprovalsPage })))
const PayrollPreparationPage = lazy(() => import('@/pages/payroll/PayrollPreparationPage').then(m => ({ default: m.PayrollPreparationPage })))
const MealVouchersPage = lazy(() => import('@/pages/payroll/MealVouchersPage').then(m => ({ default: m.MealVouchersPage })))
const SepaPaymentsPage = lazy(() => import('@/pages/payroll/SepaPaymentsPage').then(m => ({ default: m.SepaPaymentsPage })))
const ContractsPage = lazy(() => import('@/pages/ContractsPage').then(m => ({ default: m.ContractsPage })))
const LegalDeclarationsPage = lazy(() => import('@/pages/LegalDeclarationsPage').then(m => ({ default: m.LegalDeclarationsPage })))
const FinancialDashboardPage = lazy(() => import('@/pages/FinancialDashboardPage').then(m => ({ default: m.FinancialDashboardPage })))
const BIReportingPage = lazy(() => import('@/pages/BIReportingPage').then(m => ({ default: m.BIReportingPage })))
const BudgetTrackingPage = lazy(() => import('@/pages/BudgetTrackingPage').then(m => ({ default: m.BudgetTrackingPage })))
const BudgetCommitmentsPage = lazy(() => import('@/pages/BudgetCommitmentsPage').then(m => ({ default: m.BudgetCommitmentsPage })))
const DataExportPage = lazy(() => import('@/pages/DataExportPage').then(m => ({ default: m.DataExportPage })))
const ImportPage = lazy(() => import('@/pages/ImportPage').then(m => ({ default: m.ImportPage })))
const TeamPage = lazy(() => import('@/pages/TeamPage').then(m => ({ default: m.TeamPage })))
const OnboardingPage = lazy(() => import('@/pages/OnboardingPage').then(m => ({ default: m.OnboardingPage })))
const SignupPage = lazy(() => import('@/pages/SignupPage').then(m => ({ default: m.SignupPage })))
const AcceptInvitationPage = lazy(() => import('@/pages/AcceptInvitationPage').then(m => ({ default: m.AcceptInvitationPage })))
const TenantSelectionPage = lazy(() => import('@/pages/TenantSelectionPage').then(m => ({ default: m.TenantSelectionPage })))
const AuditLogPage = lazy(() => import('@/pages/AuditLogPage').then(m => ({ default: m.AuditLogPage })))
const TrainingPage = lazy(() => import('@/pages/TrainingPage').then(m => ({ default: m.TrainingPage })))
const SocialDeclarationsPage = lazy(() => import('@/pages/hr/SocialDeclarationsPage').then(m => ({ default: m.SocialDeclarationsPage })))
const BdesPage = lazy(() => import('@/pages/hr/BdesPage').then(m => ({ default: m.BdesPage })))
const DocumentManagementPage = lazy(() => import('@/pages/hr/DocumentManagementPage').then(m => ({ default: m.DocumentManagementPage })))
const RhRequestsPage = lazy(() => import('@/pages/hr/RhRequestsPage').then(m => ({ default: m.RhRequestsPage })))
const RhKnowledgeBasePage = lazy(() => import('@/pages/hr/RhKnowledgeBasePage').then(m => ({ default: m.RhKnowledgeBasePage })))
const EmployeeSelfDocsPage = lazy(() => import('@/pages/employee/EmployeeDocumentsPage').then(m => ({ default: m.EmployeeDocumentsPage })))
const EInvoicePage = lazy(() => import('@/pages/EInvoicePage').then(m => ({ default: m.EInvoicePage })))
const SageImportPage = lazy(() => import('@/pages/SageImportPage').then(m => ({ default: m.SageImportPage })))
const AccountantPortalPage = lazy(() => import('@/pages/AccountantPortalPage').then(m => ({ default: m.AccountantPortalPage })))
const SepaTransferPage = lazy(() => import('@/pages/SepaTransferPage').then(m => ({ default: m.SepaTransferPage })))
const PayrollCalcPage = lazy(() => import('@/pages/PayrollCalcPage').then(m => ({ default: m.PayrollCalcPage })))
const CorporateTaxCalcPage = lazy(() => import('@/pages/CorporateTaxCalcPage').then(m => ({ default: m.CorporateTaxCalcPage })))
const LiasseFiscalePage = lazy(() => import('@/pages/LiasseFiscalePage').then(m => ({ default: m.LiasseFiscalePage })))
const MultiCompanyPage = lazy(() => import('@/pages/MultiCompanyPage').then(m => ({ default: m.MultiCompanyPage })))
const ProspectsPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.ProspectsPage })))
const RepresentativesPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.RepresentativesPage })))
const WarehouseLocationsPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.WarehouseLocationsPage })))
const QualityCheckPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.QualityCheckPage })))
const PickListPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.PickListPage })))
const SerialNumbersPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.SerialNumbersPage })))
const ProductBatchesPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.ProductBatchesPage })))
const DocumentTemplatesPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.DocumentTemplatesPage })))
const DeliverySchedulePage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.DeliverySchedulePage })))
const ProductSubstitutesPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.ProductSubstitutesPage })))
const DormantStockPage = lazy(() => import('@/pages/Phase2Pages').then(m => ({ default: m.DormantStockPage })))
const PromotionsPage = lazy(() => import('@/pages/PromotionsPage').then(m => ({ default: m.PromotionsPage })))
const ProductGridsPage = lazy(() => import('@/pages/ProductGridsPage').then(m => ({ default: m.ProductGridsPage })))
const StockAlertsPage = lazy(() => import('@/pages/StockAlertsPage').then(m => ({ default: m.StockAlertsPage })))
const StockReservationsPage = lazy(() => import('@/pages/StockReservationsPage').then(m => ({ default: m.StockReservationsPage })))
const LotTraceabilityPage = lazy(() => import('@/pages/LotTraceabilityPage').then(m => ({ default: m.LotTraceabilityPage })))
const PosPaymentMethodsPage = lazy(() => import('@/pages/PosPaymentMethodsPage').then(m => ({ default: m.PosPaymentMethodsPage })))
const OnboardingDashboardPage = lazy(() => import('@/pages/OnboardingDashboardPage').then(m => ({ default: m.OnboardingDashboardPage })))
const CreditControlPage = lazy(() => import('@/pages/CreditControlPage').then(m => ({ default: m.CreditControlPage })))
const OpportunitiesPage = lazy(() => import('@/pages/crm/OpportunitiesPage').then(m => ({ default: m.OpportunitiesPage })))
const ActivitiesPage = lazy(() => import('@/pages/crm/ActivitiesPage').then(m => ({ default: m.ActivitiesPage })))
const CampaignsPage = lazy(() => import('@/pages/crm/CampaignsPage').then(m => ({ default: m.CampaignsPage })))
const TerritoriesPage = lazy(() => import('@/pages/crm/TerritoriesPage').then(m => ({ default: m.TerritoriesPage })))
const SalesForecastPage = lazy(() => import('@/pages/crm/SalesForecastPage').then(m => ({ default: m.SalesForecastPage })))
const TicketsPage = lazy(() => import('@/pages/crm/TicketsPage').then(m => ({ default: m.TicketsPage })))
const ServiceContractsPage = lazy(() => import('@/pages/crm/ServiceContractsPage').then(m => ({ default: m.ServiceContractsPage })))
const KnowledgeBasePage = lazy(() => import('@/pages/crm/KnowledgeBasePage').then(m => ({ default: m.KnowledgeBasePage })))
const CustomerPortalPage = lazy(() => import('@/pages/crm/CustomerPortalPage').then(m => ({ default: m.CustomerPortalPage })))
const MCFPage = lazy(() => import('@/pages/Phase3Pages').then(m => ({ default: m.MCFPage })))
const TreasuryTransfersPage = lazy(() => import('@/pages/Phase3Pages').then(m => ({ default: m.TreasuryTransfersPage })))
const CreditLinesPage = lazy(() => import('@/pages/Phase3Pages').then(m => ({ default: m.CreditLinesPage })))
const InvestmentsPage = lazy(() => import('@/pages/Phase3Pages').then(m => ({ default: m.InvestmentsPage })))
const ValueDateTrackingPage = lazy(() => import('@/pages/Phase3Pages').then(m => ({ default: m.ValueDateTrackingPage })))
const TreasuryRecurringPage = lazy(() => import('@/pages/Phase3Pages').then(m => ({ default: m.TreasuryRecurringPage })))
const ConsolidatedTreasuryPage = lazy(() => import('@/pages/Phase3Pages').then(m => ({ default: m.ConsolidatedTreasuryPage })))
const PayrollComponentsPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.PayrollComponentsPage })))
const PayrollTemplatesPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.PayrollTemplatesPage })))
const SalaryAdvancesPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.SalaryAdvancesPage })))
const DSNPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.DSNPage })))
const DPAEPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.DPAEPage })))
const LegalWatchPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.LegalWatchPage })))
const ExpenseReportsPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.ExpenseReportsPage })))
const PayRecallsPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.PayRecallsPage })))
const PayrollArchivePage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.PayrollArchivePage })))
const InterviewsPage = lazy(() => import('@/pages/Phase4Pages').then(m => ({ default: m.InterviewsPage })))
const AssetDepreciationPlansPage = lazy(() => import('@/pages/Phase5Pages').then(m => ({ default: m.AssetDepreciationPlansPage })))
const AssetFamiliesPage = lazy(() => import('@/pages/Phase5Pages').then(m => ({ default: m.AssetFamiliesPage })))
const AssetRevaluationPage = lazy(() => import('@/pages/Phase5Pages').then(m => ({ default: m.AssetRevaluationPage })))
const BatchDisposalPage = lazy(() => import('@/pages/Phase5Pages').then(m => ({ default: m.BatchDisposalPage })))
const AssetFromEntryPage = lazy(() => import('@/pages/Phase5Pages').then(m => ({ default: m.AssetFromEntryPage })))
const BatchEntryPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.BatchEntryPage })))
const AutoLabelRulesPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.AutoLabelRulesPage })))
const ExtournePage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.ExtournePage })))
const CarryForwardPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.CarryForwardPage })))
const LettrageDifferencesPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.LettrageDifferencesPage })))
const AccountingControlsPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.AccountingControlsPage })))
const CashControlPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.CashControlPage })))
const FECAttestationPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.FECAttestationPage })))
const TierRIBsPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.TierRIBsPage })))
const IFRSAdjustmentsPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.IFRSAdjustmentsPage })))
const TaxPaymentsPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.TaxPaymentsPage })))
const CustomReportTemplatesPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.CustomReportTemplatesPage })))
const DeferredPrintingPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.DeferredPrintingPage })))
const JournalAccessRightsPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.JournalAccessRightsPage })))
const VATOnCollectionsPage = lazy(() => import('@/pages/Phase6Pages').then(m => ({ default: m.VATOnCollectionsPage })))
const TaxRatesPage = lazy(() => import('@/pages/TaxRatesPage').then(m => ({ default: m.TaxRatesPage })))
const FiscalPositionsPage = lazy(() => import('@/pages/FiscalPositionsPage').then(m => ({ default: m.FiscalPositionsPage })))
const AccountTagsPage = lazy(() => import('@/pages/AccountTagsPage').then(m => ({ default: m.AccountTagsPage })))
const PaymentTermsPage = lazy(() => import('@/pages/PaymentTermsPage').then(m => ({ default: m.PaymentTermsPage })))
const SaisieParPiecePage = lazy(() => import('@/pages/SaisieParPiecePage').then(m => ({ default: m.SaisieParPiecePage })))
const JustificatifSoldePage = lazy(() => import('@/pages/JustificatifSoldePage').then(m => ({ default: m.JustificatifSoldePage })))
const EtatRapprochementPage = lazy(() => import('@/pages/EtatRapprochementPage').then(m => ({ default: m.EtatRapprochementPage })))
const ReminderLevelsPage = lazy(() => import('@/pages/ReminderLevelsPage').then(m => ({ default: m.ReminderLevelsPage })))
const RevisionCyclesPage = lazy(() => import('@/pages/RevisionCyclesPage').then(m => ({ default: m.RevisionCyclesPage })))
const FusionComptesPage = lazy(() => import('@/pages/FusionComptesPage').then(m => ({ default: m.FusionComptesPage })))
const PlanReportingPage = lazy(() => import('@/pages/PlanReportingPage').then(m => ({ default: m.PlanReportingPage })))
const CompactionPage = lazy(() => import('@/pages/CompactionPage').then(m => ({ default: m.CompactionPage })))
const RGPDPage = lazy(() => import('@/pages/RGPDPage').then(m => ({ default: m.RGPDPage })))
const GridTemplatesPage = lazy(() => import('@/pages/Phase7DPages').then(m => ({ default: m.GridTemplatesPage })))
const PaymentTemplatesComptaPage = lazy(() => import('@/pages/Phase7DPages').then(m => ({ default: m.PaymentTemplatesComptaPage })))
const StandardLabelsPage = lazy(() => import('@/pages/Phase7DPages').then(m => ({ default: m.StandardLabelsPage })))
const AnalyticJournalCodesPage = lazy(() => import('@/pages/Phase7DPages').then(m => ({ default: m.AnalyticJournalCodesPage })))
const AnalyticODEntryPage = lazy(() => import('@/pages/Phase7DInquiryPages').then(m => ({ default: m.AnalyticODEntryPage })))
const ThirdPartyInquiryPage = lazy(() => import('@/pages/Phase7DInquiryPages').then(m => ({ default: m.ThirdPartyInquiryPage })))
const AnalyticInquiryPage = lazy(() => import('@/pages/Phase7DInquiryPages').then(m => ({ default: m.AnalyticInquiryPage })))
const ReimputationPage = lazy(() => import('@/pages/Phase7DInquiryPages').then(m => ({ default: m.ReimputationPage })))
const PartnerCategoriesPage = lazy(() => import('@/pages/PartnerCategoriesPage').then(m => ({ default: m.PartnerCategoriesPage })))
const Customer360Page = lazy(() => import('@/pages/Customer360Page').then(m => ({ default: m.Customer360Page })))
const PurchaseRequestsPage = lazy(() => import('@/pages/PurchaseRequestsPage').then(m => ({ default: m.PurchaseRequestsPage })))
const SupplierPriceListsPage = lazy(() => import('@/pages/SupplierPriceListsPage').then(m => ({ default: m.SupplierPriceListsPage })))
const SupplierDeliverySchedulePage = lazy(() => import('@/pages/SupplierDeliverySchedulePage').then(m => ({ default: m.SupplierDeliverySchedulePage })))
const PosTerminalPage = lazy(() => import('@/pages/PosTerminalPage').then(m => ({ default: m.PosTerminalPage })))
const PosSessionsPage = lazy(() => import('@/pages/PosSessionsPage').then(m => ({ default: m.PosSessionsPage })))
const PosStatsPage = lazy(() => import('@/pages/PosStatsPage').then(m => ({ default: m.PosStatsPage })))
const OnlinePaymentPage = lazy(() => import('@/pages/OnlinePaymentPage').then(m => ({ default: m.OnlinePaymentPage })))
const SharedDocumentPage = lazy(() => import('@/pages/SharedDocumentPage').then(m => ({ default: m.SharedDocumentPage })))
const RevenueSimulationPage = lazy(() => import('@/pages/sales/RevenueSimulationPage').then(m => ({ default: m.RevenueSimulationPage })))
const MarginAnalysisPage = lazy(() => import('@/pages/sales/MarginAnalysisPage').then(m => ({ default: m.MarginAnalysisPage })))
const WorkHardshipPage = lazy(() => import('@/pages/WorkHardshipPage').then(m => ({ default: m.WorkHardshipPage })))
const CareerHistoryPage = lazy(() => import('@/pages/CareerHistoryPage').then(m => ({ default: m.CareerHistoryPage })))
const CPFPage = lazy(() => import('@/pages/CPFPage').then(m => ({ default: m.CPFPage })))
const EmployeeDocumentsPage = lazy(() => import('@/pages/EmployeeDocumentsPage').then(m => ({ default: m.EmployeeDocumentsPage })))
const WorkStoppagesPage = lazy(() => import('@/pages/WorkStoppagesPage').then(m => ({ default: m.WorkStoppagesPage })))
const MedicalExamsPage = lazy(() => import('@/pages/MedicalExamsPage').then(m => ({ default: m.MedicalExamsPage })))
const ExpenseCategoriesPage = lazy(() => import('@/pages/ExpenseCategoriesPage').then(m => ({ default: m.ExpenseCategoriesPage })))
const EmployeeExitPage = lazy(() => import('@/pages/EmployeeExitPage').then(m => ({ default: m.EmployeeExitPage })))
const InterviewCampaignsPage = lazy(() => import('@/pages/InterviewCampaignsPage').then(m => ({ default: m.InterviewCampaignsPage })))
const EmployeeExpensesPage = lazy(() => import('@/pages/EmployeeExpensesPage').then(m => ({ default: m.EmployeeExpensesPage })))
const ManagerExpenseApprovalsPage = lazy(() => import('@/pages/ManagerExpenseApprovalsPage').then(m => ({ default: m.ManagerExpenseApprovalsPage })))
const EmployeeInterviewsPage = lazy(() => import('@/pages/EmployeeInterviewsPage').then(m => ({ default: m.EmployeeInterviewsPage })))
const EmployeeDashboardPage = lazy(() => import('@/pages/employee/EmployeeDashboardPage').then(m => ({ default: m.EmployeeDashboardPage })))
const EmployeeProfilePage = lazy(() => import('@/pages/employee/EmployeeProfilePage').then(m => ({ default: m.EmployeeProfilePage })))
const EmployeeLeavesPage = lazy(() => import('@/pages/employee/EmployeeLeavesPage').then(m => ({ default: m.EmployeeLeavesPage })))
const RhReportsPage = lazy(() => import('@/pages/hr/RhReportsPage').then(m => ({ default: m.RhReportsPage })))

function App() {
  return (
    <AppErrorBoundary>
    <ThemeProvider>
      <AuthProvider>
        <LegislationProvider>
        <ToastProvider>
          <ConfirmProvider>
          <BrowserRouter>
            <Suspense fallback={<div className="flex items-center justify-center min-h-screen">Chargement...</div>}>
            <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/signup" element={<SignupPage />} />
          <Route path="/accept-invitation" element={<AcceptInvitationPage />} />
          <Route path="/select-tenant" element={<TenantSelectionPage />} />
          <Route path="/onboarding" element={<OnboardingPage />} />
          <Route path="/" element={<LandingPage />} />
          <Route path="/terms" element={<TermsPage />} />
          <Route path="/privacy" element={<PrivacyPage />} />
          {/* SEC-05: Routes publiques hors ProtectedLayout — accessibles sans authentification */}
          <Route path="/pay/:token" element={<OnlinePaymentPage />} />
          <Route path="/shared/:token" element={<SharedDocumentPage />} />

          <Route element={<ProtectedLayout />}>
          {/* Home + Dashboard */}
          <Route path="/home" element={<HomePage />} />
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
          <Route path="/production/planning-hub" element={<SubGroupHubPage moduleId="production" sectionIndex={2} />} />
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
          <Route path="/accounting/projects" element={<ProjectManagementPage />} />
          <Route path="/accounting/projects/legacy" element={<ProjectsPage />} />
          <Route path="/project-management" element={<ModuleHubPage moduleId="projectManagement" />} />
          <Route path="/project-management/tasks" element={<SubGroupHubPage moduleId="projectManagement" sectionIndex={0} />} />
          <Route path="/project-management/graph" element={<SubGroupHubPage moduleId="projectManagement" sectionIndex={1} />} />
          <Route path="/project-management/pivot" element={<ProjectManagementPage initialView="pivot" />} />
          <Route path="/project-management/burndown" element={<ProjectManagementPage initialView="burndown" />} />
          <Route path="/project-management/my-tasks" element={<SubGroupHubPage moduleId="projectManagement" sectionIndex={2} />} />
          <Route path="/project-management/calendar" element={<ProjectManagementPage initialView="calendar" />} />
          <Route path="/project-management/large-screen" element={<SubGroupHubPage moduleId="projectManagement" sectionIndex={3} />} />
          <Route path="/project-management/workload" element={<ProjectManagementPage initialView="workload" />} />
          <Route path="/project-management/timeline" element={<ProjectManagementPage initialView="timeline" />} />
          <Route path="/project-management/activity" element={<ProjectManagementPage initialView="activity" />} />
          <Route path="/project-management/notifications" element={<ProjectManagementPage initialView="notifications" />} />
          <Route path="/project-management/kanban" element={<ProjectManagementPage initialView="kanban" />} />
          <Route path="/project-management/gantt" element={<ProjectManagementPage initialView="gantt" />} />
          <Route path="/project-management/mind-map" element={<SubGroupHubPage moduleId="projectManagement" sectionIndex={4} />} />
          <Route path="/project-management/box" element={<ProjectManagementPage initialView="box" />} />
          <Route path="/project-management/doc" element={<SubGroupHubPage moduleId="projectManagement" sectionIndex={5} />} />
          <Route path="/project-management/chat" element={<ProjectManagementPage initialView="chat" />} />
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
          {/* Plans comptables par pays : réservé aux administrateurs de la plateforme (contrôle dans la page) */}
          <Route path="/settings/chart-packs" element={<ChartPacksAdminPage />} />
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
          <Route path="/settings/api-webhooks" element={<AdminRoute><ApiWebhooksPage /></AdminRoute>} />
          <Route path="/settings/email-templates" element={<AdminRoute><EmailTemplatesPage /></AdminRoute>} />
          <Route path="/settings/2fa" element={<ProtectedRoute><TwoFactorPage /></ProtectedRoute>} />
          <Route path="/settings/api-docs" element={<ProtectedRoute><ApiDocsPage /></ProtectedRoute>} />
          <Route path="/settings/nf525-audit" element={<AdminRoute><Nf525AuditPage /></AdminRoute>} />
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
          <Route path="/stock/reservations" element={<StockReservationsPage />} />
          <Route path="/stock/traceability" element={<LotTraceabilityPage />} />
          <Route path="/sales/credit-control" element={<CreditControlPage />} />
          <Route path="/pos/payment-methods" element={<PosPaymentMethodsPage />} />
          <Route path="/settings/onboarding" element={<OnboardingDashboardPage />} />
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
          {/* Sprint B: Customer Advanced */}
          <Route path="/sales/customers/:id/360" element={<Customer360Page />} />
          {/* Sprint C: Purchase Advanced */}
          <Route path="/purchases/requests" element={<PurchaseRequestsPage />} />
          <Route path="/purchases/supplier-price-lists" element={<SupplierPriceListsPage />} />
          <Route path="/purchases/delivery-schedules" element={<SupplierDeliverySchedulePage />} />
          {/* Sprint D: Catalog Extended */}
          {/* Sprint E: Stock Advanced */}
          {/* Sprint H: POS */}
          <Route path="/pos/terminal/:terminalId" element={<PosTerminalPage />} />
          <Route path="/pos/terminal" element={<PosTerminalPage />} />
          <Route path="/pos/sessions" element={<PosSessionsPage />} />
          <Route path="/pos/stats" element={<PosStatsPage />} />
          {/* Sprint I: Dématérialisation — routes publiques déplacées hors ProtectedLayout (SEC-05) */}
          {/* Sprint J: Pilotage */}
          <Route path="/sales/simulation" element={<RevenueSimulationPage />} />
          <Route path="/sales/margins" element={<MarginAnalysisPage />} />
          </Route>
          {/* Catch-all: redirect unmatched routes to landing page */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
            </Suspense>
        </BrowserRouter>
          </ConfirmProvider>
        </ToastProvider>
        </LegislationProvider>
    </AuthProvider>
    </ThemeProvider>
    </AppErrorBoundary>
  )
}

export default App
