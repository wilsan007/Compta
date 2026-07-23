import { useState, useEffect, useMemo, useRef } from 'react'
import { NavLink, useLocation, useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import {
  BookOpen,
  ShoppingCart,
  Wallet,
  Boxes,
  Factory,
  Users,
  BarChart3,
  PieChart,
  Settings,
  ChevronRight,
  Search,
  PanelLeftClose,
  PanelLeft,
  X,
  Pin,
  PinOff,
  Home,
  type LucideIcon,
} from 'lucide-react'
import { useTenantModules } from '@/lib/useTenantModules'

// ============================================
// TYPES
// ============================================
export type ModuleColor = 'blue' | 'indigo' | 'emerald' | 'amber' | 'violet' | 'rose' | 'cyan' | 'teal' | 'fuchsia' | 'slate'

interface NavItem {
  labelKey: string
  path: string
}

export interface NavSection {
  subGroupKey?: string
  hubPath?: string
  items: NavItem[]
}

export interface NavModule {
  id: string
  groupKey: string
  color: ModuleColor
  icon: LucideIcon
  path: string
  sections?: NavSection[]
  items?: NavItem[]
}

// ============================================
// NAVIGATION CONFIG
// ============================================
export const navModules: NavModule[] = [
  {
    id: 'home',
    groupKey: 'groups.home',
    color: 'blue',
    icon: Home,
    path: '/',
    items: [
      { labelKey: 'items.dashboard', path: '/' },
      { labelKey: 'items.myWorkspace', path: '/dashboard/workspace' },
    ],
  },
  {
    id: 'accounting',
    groupKey: 'groups.accounting',
    color: 'indigo',
    icon: BookOpen,
    path: '/accounting',
    sections: [
      {
        subGroupKey: 'subGroups.structure',
        hubPath: '/accounting/structure',
        items: [
          { labelKey: 'items.accountingHome', path: '/accounting/home' },
          { labelKey: 'items.chartAccounts', path: '/accounting/chart-accounts' },
          { labelKey: 'items.thirdParty', path: '/accounting/third-party' },
          { labelKey: 'items.paymentGeneration', path: '/accounting/payment-generation' },
          { labelKey: 'items.journals', path: '/accounting/journals' },
          { labelKey: 'items.entryTemplates', path: '/accounting/entry-templates' },
          { labelKey: 'items.fiscalYears', path: '/system/fiscal-years' },
          { labelKey: 'items.analyticSections', path: '/accounting/structure/analytic' },
          { labelKey: 'items.budgets', path: '/accounting/structure/budgets' },
          { labelKey: 'items.budgetCommitments', path: '/accounting/structure/budget-commitments' },
          { labelKey: 'items.analyticPlans', path: '/accounting/structure/analytic-plans' },
          { labelKey: 'items.distributionGrills', path: '/accounting/structure/distribution-grills' },
          { labelKey: 'items.banks', path: '/banking/accounts' },
          { labelKey: 'items.projects', path: '/accounting/projects' },
          { labelKey: 'items.fixedAssets', path: '/accounting/fixed-assets' },
          { labelKey: 'items.assetDepreciationPlans', path: '/accounting/asset-depreciation-plans' },
          { labelKey: 'items.assetFamilies', path: '/accounting/asset-families' },
          { labelKey: 'items.assetRevaluations', path: '/accounting/asset-revaluations' },
          { labelKey: 'items.assetBatchDisposals', path: '/accounting/asset-batch-disposals' },
          { labelKey: 'items.assetFromEntry', path: '/accounting/asset-from-entry' },
        ],
      },
      {
        subGroupKey: 'subGroups.processing',
        hubPath: '/accounting/traitement',
        items: [
          { labelKey: 'items.journalEntry', path: '/accounting/treatment/journal-entry' },
          { labelKey: 'items.lettrage', path: '/accounting/treatment/lettrage' },
          { labelKey: 'items.searchEntries', path: '/accounting/treatment/search' },
          { labelKey: 'items.journalClosure', path: '/accounting/treatment/journal-closure' },
          { labelKey: 'items.fiscalYearClosure', path: '/accounting/treatment/fiscal-year-closure' },
          { labelKey: 'items.bankReconciliation', path: '/banking/reconciliation' },
          { labelKey: 'items.bankTransactions', path: '/banking/transactions' },
          { labelKey: 'items.bankRules', path: '/banking/rules' },
          { labelKey: 'items.recurringEntries', path: '/accounting/treatment/recurring-entries' },
          { labelKey: 'items.regularization', path: '/accounting/treatment/regularization' },
          { labelKey: 'items.paymentReminders', path: '/accounting/treatment/payment-reminders' },
          { labelKey: 'items.bankReconRules', path: '/accounting/treatment/bank-reconciliation-rules' },
          { labelKey: 'items.bankStatementImport', path: '/accounting/treatment/bank-statement-import' },
          { labelKey: 'items.ediTva', path: '/accounting/treatment/edi-tva' },
        ],
      },
      {
        subGroupKey: 'subGroups.states',
        hubPath: '/accounting/etats',
        items: [
          { labelKey: 'items.generalLedger', path: '/accounting/general-ledger' },
          { labelKey: 'items.generalLedgerTiers', path: '/accounting/states/general-ledger-tiers' },
          { labelKey: 'items.trialBalance', path: '/accounting/trial-balance' },
          { labelKey: 'items.brouillard', path: '/accounting/states/brouillard' },
          { labelKey: 'items.agedBalance', path: '/accounting/states/aged-balance' },
          { labelKey: 'items.echeancier', path: '/accounting/states/echeancier' },
          { labelKey: 'items.sig', path: '/accounting/states/sig' },
          { labelKey: 'items.analyticBalance', path: '/accounting/states/analytic-balance' },
          { labelKey: 'items.fecExport', path: '/accounting/states/fec' },
          { labelKey: 'items.paymentDelay', path: '/accounting/reports/payment-delay' },
          { labelKey: 'items.currencyRevaluation', path: '/accounting/reports/currency-revaluation' },
          { labelKey: 'items.tvs', path: '/accounting/reports/tvs' },
          { labelKey: 'items.progressiveBalance', path: '/accounting/reports/progressive-balance' },
          { labelKey: 'items.fiscalBackup', path: '/accounting/reports/fiscal-backup' },
          { labelKey: 'items.liasseFiscale', path: '/accounting/liasse-fiscale' },
          { labelKey: 'items.accountantPortal', path: '/accounting/accountant-portal' },
          { labelKey: 'items.profitLoss', path: '/reports/profit-loss' },
          { labelKey: 'items.balanceSheet', path: '/reports/balance-sheet' },
          { labelKey: 'items.cashFlow', path: '/reports/cash-flow' },
          { labelKey: 'items.vat', path: '/reports/vat' },
          { labelKey: 'items.journalsReport', path: '/reports/journals' },
        ],
      },
    ],
  },
  {
    id: 'commercial',
    groupKey: 'groups.commercial',
    color: 'emerald',
    icon: ShoppingCart,
    path: '/commercial',
    sections: [
      {
        subGroupKey: 'subGroups.sales',
        hubPath: '/sales',
        items: [
          { labelKey: 'items.customers', path: '/sales/customers' },
          { labelKey: 'items.invoices', path: '/sales/invoices' },
          { labelKey: 'items.quotes', path: '/sales/quotes' },
          { labelKey: 'items.creditNotes', path: '/sales/credits' },
          { labelKey: 'items.recurringInvoices', path: '/sales/recurring' },
          { labelKey: 'items.salesOrders', path: '/sales/orders' },
          { labelKey: 'items.deliveryNotes', path: '/sales/delivery-notes' },
          { labelKey: 'items.customerPayments', path: '/sales/payments' },
          { labelKey: 'items.eInvoice', path: '/sales/e-invoice' },
          { labelKey: 'items.prospects', path: '/commercial/prospects' },
          { labelKey: 'items.representatives', path: '/commercial/representatives' },
          { labelKey: 'items.deliverySchedules', path: '/commercial/delivery-schedules' },
        ],
      },
      {
        subGroupKey: 'subGroups.purchases',
        hubPath: '/purchases',
        items: [
          { labelKey: 'items.suppliers', path: '/purchases/suppliers' },
          { labelKey: 'items.purchaseInvoices', path: '/purchases/invoices' },
          { labelKey: 'items.supplierCreditNotes', path: '/purchases/credits' },
          { labelKey: 'items.productsServices', path: '/purchases/products' },
          { labelKey: 'items.invoiceAutomation', path: '/purchases/automation' },
          { labelKey: 'items.purchaseOrders', path: '/purchases/orders' },
          { labelKey: 'items.goodsReceipts', path: '/purchases/goods-receipts' },
          { labelKey: 'items.supplierPayments', path: '/purchases/payments' },
        ],
      },
    ],
  },
  {
    id: 'treasury',
    groupKey: 'groups.treasury',
    color: 'amber',
    icon: Wallet,
    path: '/treasury',
    items: [
      { labelKey: 'items.treasuryDashboard', path: '/treasury/dashboard' },
      { labelKey: 'items.forecasts', path: '/treasury/forecast' },
      { labelKey: 'items.paymentOrders', path: '/treasury/payment-orders' },
      { labelKey: 'items.sepaTransfers', path: '/treasury/sepa' },
      { labelKey: 'items.collections', path: '/treasury/collections' },
      { labelKey: 'items.mcf', path: '/treasury/mcf' },
      { labelKey: 'items.treasuryTransfers', path: '/treasury/transfers' },
      { labelKey: 'items.creditLines', path: '/treasury/credit-lines' },
      { labelKey: 'items.investments', path: '/treasury/investments' },
      { labelKey: 'items.valueDates', path: '/treasury/value-dates' },
      { labelKey: 'items.treasuryRecurring', path: '/treasury/recurring' },
      { labelKey: 'items.consolidatedTreasury', path: '/treasury/consolidated' },
    ],
  },
  {
    id: 'stock',
    groupKey: 'groups.stock',
    color: 'violet',
    icon: Boxes,
    path: '/stock',
    items: [
      { labelKey: 'items.stockQuantities', path: '/stock/quantities' },
      { labelKey: 'items.stockMovements', path: '/stock/movements' },
      { labelKey: 'items.warehouses', path: '/stock/warehouses' },
      { labelKey: 'items.inventory', path: '/stock/inventory' },
      { labelKey: 'items.reorder', path: '/stock/reorder' },
      { labelKey: 'items.priceLists', path: '/stock/price-lists' },
      { labelKey: 'items.gescomTransfer', path: '/stock/transfer' },
      { labelKey: 'items.bom', path: '/stock/boms' },
      { labelKey: 'items.manufacturingOrders', path: '/stock/manufacturing' },
      { labelKey: 'items.warehouseLocations', path: '/stock/warehouse-locations' },
      { labelKey: 'items.qualityChecks', path: '/stock/quality-checks' },
      { labelKey: 'items.pickLists', path: '/stock/pick-lists' },
      { labelKey: 'items.serialNumbers', path: '/stock/serial-numbers' },
      { labelKey: 'items.productBatches', path: '/stock/product-batches' },
      { labelKey: 'items.productSubstitutes', path: '/stock/product-substitutes' },
      { labelKey: 'items.dormantStock', path: '/stock/dormant-stock' },
    ],
  },
  {
    id: 'production',
    groupKey: 'groups.production',
    color: 'rose',
    icon: Factory,
    path: '/production',
    sections: [
      {
        subGroupKey: 'subGroups.manufacturing',
        hubPath: '/production/manufacturing',
        items: [
          { labelKey: 'items.productionDashboard', path: '/production' },
          { labelKey: 'items.routings', path: '/production/routings' },
          { labelKey: 'items.machines', path: '/production/machines' },
          { labelKey: 'items.toolings', path: '/production/toolings' },
          { labelKey: 'items.manufacturingOrders', path: '/production/manufacturing' },
        ],
      },
      {
        subGroupKey: 'subGroups.subcontracting',
        hubPath: '/production/subcontracting',
        items: [
          { labelKey: 'items.subcontracting', path: '/production/subcontracting/orders' },
          { labelKey: 'items.subcontractingShipments', path: '/production/subcontracting/shipments' },
          { labelKey: 'items.subcontractingReceipts', path: '/production/subcontracting/receipts' },
          { labelKey: 'items.subcontractingSupervisor', path: '/production/subcontracting/supervisor' },
        ],
      },
      {
        subGroupKey: 'subGroups.planning',
        hubPath: '/production/planning',
        items: [
          { labelKey: 'items.mrp', path: '/production/mrp' },
          { labelKey: 'items.pendingDocs', path: '/production/mrp/pending' },
          { labelKey: 'items.forecasts', path: '/production/forecasts' },
          { labelKey: 'items.planning', path: '/production/planning' },
          { labelKey: 'items.workflows', path: '/production/workflows' },
          { labelKey: 'items.equivalences', path: '/production/equivalences' },
          { labelKey: 'items.ofAccess', path: '/production/of-access' },
        ],
      },
    ],
  },
  {
    id: 'hr',
    groupKey: 'groups.hr',
    color: 'cyan',
    icon: Users,
    path: '/hr',
    items: [
      { labelKey: 'items.employees', path: '/hr/employees' },
      { labelKey: 'items.payRuns', path: '/hr/pay-runs' },
      { labelKey: 'items.paySlips', path: '/hr/pay-slips' },
      { labelKey: 'items.payrollAccounting', path: '/hr/payroll-accounting' },
      { labelKey: 'items.timesheets', path: '/hr/timesheets' },
      { labelKey: 'items.leaveRequests', path: '/hr/leave-requests' },
      { labelKey: 'items.contracts', path: '/hr/contracts' },
      { labelKey: 'items.declarations', path: '/hr/declarations' },
      { labelKey: 'items.payrollCalc', path: '/hr/payroll-calc' },
      { labelKey: 'items.training', path: '/hr/training' },
      { labelKey: 'items.payrollComponents', path: '/hr/payroll-components' },
      { labelKey: 'items.payrollTemplates', path: '/hr/payroll-templates' },
      { labelKey: 'items.salaryAdvances', path: '/hr/salary-advances' },
      { labelKey: 'items.dsn', path: '/hr/dsn' },
      { labelKey: 'items.dpae', path: '/hr/dpae' },
      { labelKey: 'items.legalWatch', path: '/hr/legal-watch' },
      { labelKey: 'items.expenseReports', path: '/hr/expense-reports' },
      { labelKey: 'items.payRecalls', path: '/hr/pay-recalls' },
      { labelKey: 'items.payrollArchives', path: '/hr/payroll-archives' },
      { labelKey: 'items.interviews', path: '/hr/interviews' },
    ],
  },
  {
    id: 'dashboards',
    groupKey: 'groups.dashboards',
    color: 'teal',
    icon: BarChart3,
    path: '/dashboard',
    items: [
      { labelKey: 'items.salesDashboard', path: '/dashboard/sales' },
      { labelKey: 'items.purchasesDashboard', path: '/dashboard/purchases' },
      { labelKey: 'items.bankingDashboard', path: '/dashboard/banking' },
      { labelKey: 'items.hrDashboard', path: '/dashboard/hr' },
    ],
  },
  {
    id: 'reporting',
    groupKey: 'groups.reporting',
    color: 'fuchsia',
    icon: PieChart,
    path: '/reporting',
    items: [
      { labelKey: 'items.financialDashboard', path: '/reporting/financial' },
      { labelKey: 'items.biReporting', path: '/reporting/bi' },
      { labelKey: 'items.budgetTracking', path: '/reporting/budget' },
    ],
  },
  {
    id: 'system',
    groupKey: 'groups.system',
    color: 'slate',
    icon: Settings,
    path: '/settings',
    sections: [
      {
        subGroupKey: 'subGroups.configuration',
        hubPath: '/settings/configuration',
        items: [
          { labelKey: 'items.company', path: '/settings/company' },
          { labelKey: 'items.companySettings', path: '/settings/company-settings' },
          { labelKey: 'items.usersMenu', path: '/settings/users' },
          { labelKey: 'items.teamRoles', path: '/settings/team' },
          { labelKey: 'items.currencies', path: '/settings/currencies' },
          { labelKey: 'items.integrations', path: '/settings/integrations' },
          { labelKey: 'items.modulesSettings', path: '/settings/modules' },
          { labelKey: 'items.multiCompany', path: '/settings/multi-company' },
          { labelKey: 'items.documentTemplates', path: '/settings/document-templates' },
        ],
      },
      {
        subGroupKey: 'subGroups.processing',
        hubPath: '/settings/data',
        items: [
          { labelKey: 'items.dataImport', path: '/settings/import' },
          { labelKey: 'items.sageImport', path: '/settings/import/sage' },
          { labelKey: 'items.dataExport', path: '/settings/data-export' },
          { labelKey: 'items.auditLog', path: '/system/audit-log' },
        ],
      },
    ],
  },
]

// ============================================
// BACKWARD-COMPATIBLE navGroups (for CommandPalette)
// ============================================
interface LegacyNavItem {
  labelKey: string
  icon: LucideIcon
  path: string
  subItems: NavItem[]
}

interface LegacyNavGroup {
  groupKey: string
  items: LegacyNavItem[]
}

export const navGroups: LegacyNavGroup[] = navModules.map((mod) => ({
  groupKey: mod.groupKey,
  items: [
    {
      labelKey: mod.groupKey,
      icon: mod.icon,
      path: mod.path,
      subItems: mod.sections
        ? mod.sections.flatMap((s) => s.items)
        : mod.items || [],
    },
  ],
}))

export function getEnabledNavGroups(): LegacyNavGroup[] {
  const enabled = getEnabledNavModules()
  return enabled.map((mod) => ({
    groupKey: mod.groupKey,
    items: [
      {
        labelKey: mod.groupKey,
        icon: mod.icon,
        path: mod.path,
        subItems: mod.sections
          ? mod.sections.flatMap((s) => s.items)
          : mod.items || [],
      },
    ],
  }))
}

// ============================================
// HELPERS
// ============================================
function getModuleIdForPath(pathname: string): string | null {
  for (const mod of getEnabledNavModules()) {
    const allPaths = mod.sections
      ? mod.sections.flatMap((s) => s.items.map((i) => i.path))
      : mod.items?.map((i) => i.path) || []
    for (const p of allPaths) {
      if (p === '/' && pathname === '/') return mod.id
      if (p !== '/' && pathname.startsWith(p)) return mod.id
    }
  }
  return null
}

function getSubGroupForPath(mod: NavModule, pathname: string): string | null {
  if (!mod.sections) return null
  for (const sec of mod.sections) {
    for (const item of sec.items) {
      if (item.path === '/' && pathname === '/') return sec.subGroupKey || null
      if (item.path !== '/' && pathname.startsWith(item.path)) return sec.subGroupKey || null
    }
  }
  return null
}

let _enabledModuleIds: string[] | null = null

export function setEnabledModuleIds(ids: string[]) {
  _enabledModuleIds = ids
}

export function getEnabledNavModules(): NavModule[] {
  if (!_enabledModuleIds) return navModules
  return navModules.filter((m) => _enabledModuleIds!.includes(m.id))
}

function getAllItems(): { mod: NavModule; item: NavItem }[] {
  const result: { mod: NavModule; item: NavItem }[] = []
  for (const mod of getEnabledNavModules()) {
    if (mod.sections) {
      for (const sec of mod.sections) {
        for (const item of sec.items) {
          result.push({ mod, item })
        }
      }
    } else if (mod.items) {
      for (const item of mod.items) {
        result.push({ mod, item })
      }
    }
  }
  return result
}

const colorVarMap: Record<ModuleColor, string> = {
  blue: '--mod-blue',
  indigo: '--mod-indigo',
  emerald: '--mod-emerald',
  amber: '--mod-amber',
  violet: '--mod-violet',
  rose: '--mod-rose',
  cyan: '--mod-cyan',
  teal: '--mod-teal',
  fuchsia: '--mod-fuchsia',
  slate: '--mod-slate',
}

const colorBgMap: Record<ModuleColor, string> = {
  blue: '--mod-blue-bg',
  indigo: '--mod-indigo-bg',
  emerald: '--mod-emerald-bg',
  amber: '--mod-amber-bg',
  violet: '--mod-violet-bg',
  rose: '--mod-rose-bg',
  cyan: '--mod-cyan-bg',
  teal: '--mod-teal-bg',
  fuchsia: '--mod-fuchsia-bg',
  slate: '--mod-slate-bg',
}

// ============================================
// SIDEBAR COMPONENT
// ============================================
interface SidebarProps {
  collapsed: boolean
  onToggleCollapse: () => void
  mobileOpen: boolean
  onCloseMobile: () => void
}

export function Sidebar({ collapsed, onToggleCollapse, mobileOpen, onCloseMobile }: SidebarProps) {
  const location = useLocation()
  const navigate = useNavigate()
  const { t } = useTranslation('nav')
  const { modules: enabledModules } = useTenantModules()
  const [expandedModule, setExpandedModule] = useState<string | null>(null)
  const [expandedSubGroup, setExpandedSubGroup] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState('')
  const [pinnedPaths, setPinnedPaths] = useState<string[]>([])
  const [hoveredModule, setHoveredModule] = useState<string | null>(null)
  const hoverTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Sync enabled modules with the module-level filter
  useEffect(() => {
    setEnabledModuleIds(enabledModules)
  }, [enabledModules])

  // Load pinned items from localStorage
  useEffect(() => {
    const saved = localStorage.getItem('compta-pinned')
    if (saved) {
      try {
        setPinnedPaths(JSON.parse(saved))
      } catch {
        // ignore
      }
    }
  }, [])

  // Save pinned items
  useEffect(() => {
    localStorage.setItem('compta-pinned', JSON.stringify(pinnedPaths))
  }, [pinnedPaths])

  // Auto-expand module for current route
  useEffect(() => {
    const modId = getModuleIdForPath(location.pathname)
    if (modId) {
      setExpandedModule(modId)
      const mod = getEnabledNavModules().find((m) => m.id === modId)
      if (mod?.sections) {
        const subKey = getSubGroupForPath(mod, location.pathname)
        if (subKey) {
          setExpandedSubGroup(`${modId}:${subKey}`)
        }
      }
    }
  }, [location.pathname])

  // Close search when collapsing
  useEffect(() => {
    if (collapsed) {
      setSearchQuery('')
      setExpandedModule(null)
      setExpandedSubGroup(null)
    }
  }, [collapsed])

  function togglePin(path: string) {
    setPinnedPaths((prev) =>
      prev.includes(path) ? prev.filter((p) => p !== path) : [...prev, path]
    )
  }

  function isActive(path: string): boolean {
    if (path === '/') return location.pathname === '/'
    return location.pathname === path || location.pathname.startsWith(path + '/')
  }

  function isModuleActive(mod: NavModule): boolean {
    const allPaths = mod.sections
      ? mod.sections.flatMap((s) => s.items.map((i) => i.path))
      : mod.items?.map((i) => i.path) || []
    return allPaths.some((p) => isActive(p))
  }

  function handleModuleClick(mod: NavModule) {
    if (collapsed) return
    if (mod.id === expandedModule) {
      setExpandedModule(null)
      setExpandedSubGroup(null)
    } else {
      setExpandedModule(mod.id)
    }
  }

  function handleSubGroupClick(modId: string, subGroupKey: string) {
    const key = `${modId}:${subGroupKey}`
    setExpandedSubGroup((prev) => (prev === key ? null : key))
  }

  // Search results
  const searchResults = useMemo(() => {
    if (!searchQuery.trim()) return []
    const q = searchQuery.toLowerCase()
    return getAllItems().filter(({ item }) => {
      const label = t(item.labelKey).toLowerCase()
      return label.includes(q)
    })
  }, [searchQuery, t])

  // Pinned items
  const pinnedItems = useMemo(() => {
    return getAllItems().filter(({ item }) => pinnedPaths.includes(item.path))
  }, [pinnedPaths])

  function handleHoverEnter(modId: string) {
    if (!collapsed) return
    if (hoverTimerRef.current) clearTimeout(hoverTimerRef.current)
    hoverTimerRef.current = setTimeout(() => setHoveredModule(modId), 200)
  }

  function handleHoverLeave() {
    if (hoverTimerRef.current) clearTimeout(hoverTimerRef.current)
    hoverTimerRef.current = setTimeout(() => setHoveredModule(null), 150)
  }

  // ============================================
  // RENDER: COLLAPSED RAIL
  // ============================================
  if (collapsed) {
    return (
      <aside className={cn(
      'fixed lg:sticky top-0 left-0 h-screen w-16 border-r border-[var(--color-border)] sidebar-glass flex flex-col z-50 transition-transform duration-300',
      mobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
    )}>
        {/* Logo collapsed */}
        <div className="flex items-center justify-center h-14 border-b border-[var(--color-border)] flex-shrink-0">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center shadow-md">
            <span className="text-white font-bold text-base">C</span>
          </div>
        </div>

        {/* Module icons */}
        <nav className="flex-1 overflow-y-auto sidebar-scroll py-3 px-2 space-y-1">
          {getEnabledNavModules().map((mod) => {
            const active = isModuleActive(mod)
            const colorVar = colorVarMap[mod.color]
            const colorBg = colorBgMap[mod.color]
            return (
              <div
                key={mod.id}
                className="relative group"
                onMouseEnter={() => handleHoverEnter(mod.id)}
                onMouseLeave={handleHoverLeave}
              >
                <button
                  onClick={() => {
                    navigate(mod.path)
                    onCloseMobile()
                  }}
                  className={cn(
                    'w-full flex items-center justify-center p-2 rounded-xl transition-all duration-200 relative',
                    active && 'mod-' + mod.color + '-bg'
                  )}
                  title={t(mod.groupKey)}
                >
                  {active && (
                    <span
                      className="mod-active-bar"
                      style={{ background: `var(${colorVar})` }}
                    />
                  )}
                  <div className={cn('mod-icon', `mod-${mod.color}`, active && `mod-${mod.color}-bg`)}>
                    <mod.icon className="w-4 h-4" />
                  </div>
                </button>

                {/* Flyout panel */}
                {hoveredModule === mod.id && (
                  <div className="flyout-panel absolute left-full top-0 ml-2 z-50 min-w-[240px]">
                    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl shadow-2xl py-2 overflow-hidden">
                      <p className="px-3 py-2 text-xs font-bold uppercase tracking-wider text-[var(--color-text-secondary)] flex items-center gap-2">
                        <span className={cn('w-2 h-2 rounded-full')} style={{ background: `var(${colorVar})` }} />
                        {t(mod.groupKey)}
                      </p>
                      <div className="max-h-[400px] overflow-y-auto sidebar-scroll">
                        {mod.sections ? (
                          mod.sections.map((sec) => (
                            <div key={sec.subGroupKey}>
                              {sec.subGroupKey && (
                                <NavLink
                                  to={sec.hubPath || mod.path}
                                  onClick={onCloseMobile}
                                  className="flex items-center gap-2 px-3 pt-2 pb-1.5 text-[10px] font-bold uppercase tracking-wider transition-all rounded-md mx-1"
                                  style={{
                                    color: `var(${colorVar})`,
                                    borderLeft: `2px solid var(${colorVar})`,
                                    background: `var(${colorBg})`,
                                  }}
                                >
                                  {t(sec.subGroupKey)}
                                  <span className="text-[9px] normal-case font-semibold px-1.5 py-0.5 rounded-full" style={{ background: `var(${colorVar})`, color: '#fff' }}>
                                    {sec.items.length}
                                  </span>
                                </NavLink>
                              )}
                              {sec.items.map((item) => (
                                <NavLink
                                  key={item.path}
                                  to={item.path}
                                  onClick={onCloseMobile}
                                  className={cn(
                                    'flex items-center gap-2 px-3 py-1.5 text-sm transition-colors',
                                    isActive(item.path)
                                      ? 'font-medium'
                                      : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-50)]'
                                  )}
                                  style={isActive(item.path) ? { color: `var(${colorVar})` } : undefined}
                                >
                                  <span className={cn('pinned-dot', `mod-${mod.color}`)} style={{ background: `var(${colorVar})`, opacity: isActive(item.path) ? 1 : 0.3 }} />
                                  {t(item.labelKey)}
                                </NavLink>
                              ))}
                            </div>
                          ))
                        ) : (
                          mod.items?.map((item) => (
                            <NavLink
                              key={item.path}
                              to={item.path}
                              onClick={onCloseMobile}
                              className={cn(
                                'flex items-center gap-2 px-3 py-1.5 text-sm transition-colors',
                                isActive(item.path)
                                  ? 'font-medium'
                                  : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-50)]'
                              )}
                              style={isActive(item.path) ? { color: `var(${colorVar})` } : undefined}
                            >
                              <span className="pinned-dot" style={{ background: `var(${colorVar})`, opacity: isActive(item.path) ? 1 : 0.3 }} />
                              {t(item.labelKey)}
                            </NavLink>
                          ))
                        )}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )
          })}
        </nav>

        {/* Expand button */}
        <div className="border-t border-[var(--color-border)] p-2 flex-shrink-0">
          <button
            onClick={onToggleCollapse}
            className="w-full flex items-center justify-center p-2 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
            title={t('layout.expand')}
          >
            <PanelLeft className="w-4 h-4" />
          </button>
        </div>
      </aside>
    )
  }

  // ============================================
  // RENDER: EXPANDED SIDEBAR
  // ============================================
  return (
    <aside className={cn(
      'fixed lg:sticky top-0 left-0 h-screen w-72 border-r border-[var(--color-border)] sidebar-glass flex flex-col z-50 transition-all duration-300',
      mobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
    )}>
      {/* Logo + close */}
      <div className="flex items-center gap-3 h-14 px-4 border-b border-[var(--color-border)] flex-shrink-0">
        <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center shadow-md flex-shrink-0">
          <span className="text-white font-bold text-base">C</span>
        </div>
        <div className="overflow-hidden flex-1">
          <p className="font-bold text-[var(--color-text)] text-sm whitespace-nowrap">Compta</p>
          <p className="text-[10px] text-[var(--color-text-secondary)] whitespace-nowrap">v0.3 - Aurora</p>
        </div>
        <button
          onClick={onCloseMobile}
          className="lg:hidden p-1.5 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
        >
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* Search */}
      <div className="px-3 py-3 border-b border-[var(--color-border)] flex-shrink-0">
        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-[var(--color-text-secondary)] pointer-events-none" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={t('layout.filterPages')}
            className="sidebar-search"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded text-[var(--color-text-secondary)] hover:text-[var(--color-text)]"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto sidebar-scroll px-2 py-2">
        {/* Search results */}
        {searchQuery.trim() ? (
          <div className="space-y-0.5">
            {searchResults.length === 0 ? (
              <p className="text-center text-sm text-[var(--color-text-secondary)] py-8">
                {t('layout.noResults')}
              </p>
            ) : (
              searchResults.map(({ mod, item }) => {
                const colorVar = colorVarMap[mod.color]
                return (
                  <NavLink
                    key={item.path}
                    to={item.path}
                    onClick={onCloseMobile}
                    className={cn(
                      'flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm transition-colors',
                      isActive(item.path)
                        ? 'font-medium'
                        : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-100)]'
                    )}
                    style={isActive(item.path) ? { color: `var(${colorVar})`, background: `var(${colorBgMap[mod.color]})` } : undefined}
                  >
                    <span className="pinned-dot" style={{ background: `var(${colorVar})`, opacity: 0.5 }} />
                    <span className="flex-1 truncate">{t(item.labelKey)}</span>
                    <span className="text-[10px] text-[var(--color-text-secondary)] opacity-50 whitespace-nowrap">
                      {t(mod.groupKey)}
                    </span>
                  </NavLink>
                )
              })
            )}
          </div>
        ) : (
          <>
            {/* Pinned section */}
            {pinnedItems.length > 0 && (
              <div className="mb-3">
                <p className="text-[10px] font-semibold text-[var(--color-text-secondary)] uppercase tracking-wider px-3 mb-1.5 flex items-center gap-1.5">
                  <Pin className="w-3 h-3" />
                  {t('layout.pinned')}
                </p>
                <div className="space-y-0.5">
                  {pinnedItems.map(({ mod, item }) => {
                    const colorVar = colorVarMap[mod.color]
                    const active = isActive(item.path)
                    return (
                      <div key={`pin-${item.path}`} className="group relative">
                        <NavLink
                          to={item.path}
                          onClick={onCloseMobile}
                          className={cn(
                            'flex items-center gap-2.5 px-3 py-1.5 rounded-lg text-sm transition-colors',
                            active
                              ? 'font-medium'
                              : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-100)]'
                          )}
                          style={active ? { color: `var(${colorVar})`, background: `var(${colorBgMap[mod.color]})` } : undefined}
                        >
                          <span className="pinned-dot" style={{ background: `var(${colorVar})`, opacity: active ? 1 : 0.4 }} />
                          <span className="flex-1 truncate">{t(item.labelKey)}</span>
                        </NavLink>
                        <button
                          onClick={(e) => { e.preventDefault(); togglePin(item.path) }}
                          className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded opacity-0 group-hover:opacity-100 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)] transition-all"
                        >
                          <PinOff className="w-3 h-3" />
                        </button>
                      </div>
                    )
                  })}
                </div>
                <div className="mx-3 my-2 h-px bg-[var(--color-border)]" />
              </div>
            )}

            {/* Modules */}
            {getEnabledNavModules().map((mod) => {
              const isExpanded = expandedModule === mod.id
              const active = isModuleActive(mod)
              const colorVar = colorVarMap[mod.color]
              const colorBg = colorBgMap[mod.color]
              const allModItems = mod.sections
                ? mod.sections.flatMap((s) => s.items)
                : mod.items || []
              const hasItems = allModItems.length > 0

              return (
                <div key={mod.id} className="mb-0.5">
                  {/* Module header */}
                  <div
                    className={cn('mod-header rounded-xl', active && 'active')}
                    style={active ? { background: `var(${colorBg})` } : undefined}
                  >
                    <div className="flex items-center">
                      <NavLink
                        to={mod.path}
                        onClick={onCloseMobile}
                        className="flex items-center gap-3 px-3 py-2.5 flex-1 min-w-0"
                      >
                        {active && (
                          <span
                            className="mod-active-bar"
                            style={{ background: `var(${colorVar})` }}
                          />
                        )}
                        <div className={cn('mod-icon', `mod-${mod.color}`, active && `mod-${mod.color}-bg`)}>
                          <mod.icon className="w-4 h-4" />
                        </div>
                        <span
                          className={cn(
                            'text-sm font-medium whitespace-nowrap truncate',
                            active ? '' : 'text-[var(--color-text-secondary)]'
                          )}
                          style={active ? { color: `var(${colorVar})` } : undefined}
                        >
                          {t(mod.groupKey)}
                        </span>
                      </NavLink>
                      {hasItems && (
                        <button
                          onClick={() => handleModuleClick(mod)}
                          className="p-1.5 mr-1 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-200)] transition-colors flex-shrink-0"
                        >
                          <ChevronRight className={cn('w-3.5 h-3.5 chevron-rotate', isExpanded && 'expanded')} />
                        </button>
                      )}
                    </div>
                  </div>

                  {/* Expanded content */}
                  {isExpanded && hasItems && (
                    <div className="accordion-content ml-2 mt-0.5 mb-1">
                      {mod.sections ? (
                        mod.sections.map((sec, secIdx) => {
                          const subKey = sec.subGroupKey || ''
                          const sectionKey = `${mod.id}:${subKey}`
                          const isSubExpanded = expandedSubGroup === sectionKey
                          const sectionActive = sec.items.some((item) => isActive(item.path))
                          return (
                          <div key={secIdx} className="mb-1">
                            {sec.subGroupKey && (
                              <div className="flex items-center group/sub rounded-lg overflow-hidden">
                                <button
                                  onClick={() => handleSubGroupClick(mod.id, subKey)}
                                  className={cn(
                                    'flex items-center gap-2 flex-1 text-[11px] font-bold uppercase tracking-wider px-3 py-2.5 rounded-lg transition-all',
                                    sectionActive ? '' : 'opacity-70 hover:opacity-100'
                                  )}
                                  style={{
                                    color: sectionActive ? `var(${colorVar})` : undefined,
                                    background: isSubExpanded
                                      ? `var(${colorBg})`
                                      : sectionActive
                                        ? `var(${colorBg})`
                                        : 'var(--color-neutral-50)',
                                    borderLeft: `3px solid var(${colorVar})`,
                                    borderLeftColor: isSubExpanded || sectionActive ? `var(${colorVar})` : 'transparent',
                                  }}
                                >
                                  <ChevronRight className={cn('w-3 h-3 chevron-rotate transition-transform', isSubExpanded && 'expanded')} />
                                  <span className="flex-1 text-left">{t(sec.subGroupKey)}</span>
                                  <span
                                    className={cn(
                                      'text-[9px] normal-case font-semibold px-1.5 py-0.5 rounded-full transition-colors',
                                    )}
                                    style={{
                                      background: isSubExpanded || sectionActive ? `var(${colorVar})` : 'var(--color-neutral-200)',
                                      color: isSubExpanded || sectionActive ? '#fff' : 'var(--color-text-secondary)',
                                    }}
                                  >
                                    {sec.items.length}
                                  </span>
                                </button>
                                {sec.hubPath && (
                                  <NavLink
                                    to={sec.hubPath}
                                    onClick={onCloseMobile}
                                    className="p-1.5 mr-1 rounded-lg text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-100)] opacity-0 group-hover/sub:opacity-100 transition-all"
                                    title={t(sec.subGroupKey)}
                                  >
                                    <ChevronRight className="w-3 h-3" />
                                  </NavLink>
                                )}
                              </div>
                            )}
                            {isSubExpanded && (
                              <div className="space-y-0">
                                {sec.items.map((item, itemIdx) => {
                                  const itemActive = isActive(item.path)
                                  const isPinned = pinnedPaths.includes(item.path)
                                  return (
                                    <div
                                      key={item.path}
                                      className="stagger-item group relative"
                                      style={{ animationDelay: `${itemIdx * 30}ms` }}
                                    >
                                      <NavLink
                                        to={item.path}
                                        onClick={onCloseMobile}
                                        className={cn(
                                          'sub-link flex items-center gap-2 pl-3 pr-8 py-1.5 rounded-lg text-xs transition-colors',
                                          itemActive
                                            ? 'active font-medium'
                                            : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
                                        )}
                                        style={itemActive ? { color: `var(${colorVar})`, background: `var(${colorBg})` } : undefined}
                                      >
                                        <span
                                          className="pinned-dot"
                                          style={{
                                            background: `var(${colorVar})`,
                                            opacity: itemActive ? 1 : 0.25,
                                          }}
                                        />
                                        <span className="truncate">{t(item.labelKey)}</span>
                                      </NavLink>
                                      <button
                                        onClick={(e) => { e.preventDefault(); togglePin(item.path) }}
                                        className={cn(
                                          'absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded transition-all',
                                          isPinned
                                            ? 'opacity-100 text-[var(--color-primary)]'
                                            : 'opacity-0 group-hover:opacity-100 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]'
                                        )}
                                      >
                                        <Pin className="w-3 h-3" />
                                      </button>
                                    </div>
                                  )
                                })}
                              </div>
                            )}
                          </div>
                          )
                        })
                      ) : (
                        mod.items?.map((item, itemIdx) => {
                          const itemActive = isActive(item.path)
                          const isPinned = pinnedPaths.includes(item.path)
                          return (
                            <div
                              key={item.path}
                              className="stagger-item group relative"
                              style={{ animationDelay: `${itemIdx * 30}ms` }}
                            >
                              <NavLink
                                to={item.path}
                                onClick={onCloseMobile}
                                className={cn(
                                  'sub-link flex items-center gap-2 pl-3 pr-8 py-1.5 rounded-lg text-xs transition-colors',
                                  itemActive
                                    ? 'active font-medium'
                                    : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
                                )}
                                style={itemActive ? { color: `var(${colorVar})`, background: `var(${colorBg})` } : undefined}
                              >
                                <span
                                  className="pinned-dot"
                                  style={{
                                    background: `var(${colorVar})`,
                                    opacity: itemActive ? 1 : 0.25,
                                  }}
                                />
                                <span className="truncate">{t(item.labelKey)}</span>
                              </NavLink>
                              <button
                                onClick={(e) => { e.preventDefault(); togglePin(item.path) }}
                                className={cn(
                                  'absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded transition-all',
                                  isPinned
                                    ? 'opacity-100 text-[var(--color-primary)]'
                                    : 'opacity-0 group-hover:opacity-100 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]'
                                )}
                              >
                                <Pin className="w-3 h-3" />
                              </button>
                            </div>
                          )
                        })
                      )}
                    </div>
                  )}
                </div>
              )
            })}
          </>
        )}
      </nav>

      {/* Collapse button */}
      <div className="border-t border-[var(--color-border)] p-2 flex-shrink-0">
        <button
          onClick={onToggleCollapse}
          className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
        >
          <PanelLeftClose className="w-4 h-4" />
          <span>{t('layout.collapse')}</span>
        </button>
      </div>
    </aside>
  )
}
