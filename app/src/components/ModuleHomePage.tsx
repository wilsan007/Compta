import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { navModules, type ModuleColor } from './Sidebar'
import {
  ChevronRight,
  PenLine, Search, Link2, ListTree, BookCopy, Contact, ScrollText, Scale, FileDown,
  ReceiptText, UserCircle, FileSpreadsheet, Receipt, Truck, ShoppingCart,
  LayoutDashboard, TrendingUp, Layers, CreditCard, Send, HandCoins,
  Boxes, ArrowLeftRight, ClipboardCheck, Warehouse, RefreshCw, Tag,
  Factory, GitBranch, Cog, Calculator, CalendarRange,
  Banknote, FileText, Users, Clock, CalendarX,
  BarChart3, PieChart, Activity, Target,
  Building2, UserCog, Coins, Upload, Download, History,
  type LucideIcon,
} from 'lucide-react'
import { Link } from 'react-router-dom'

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
  lime: '--mod-lime',
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
  lime: '--mod-lime-bg',
}

interface HomeTab {
  labelKey: string
  icon: LucideIcon
  path: string
}

interface HomeSection {
  titleKey: string
  tabs: HomeTab[]
}

interface ModuleHomeConfig {
  sections: HomeSection[]
}

const moduleHomeConfigs: Record<string, ModuleHomeConfig> = {
  accounting: {
    sections: [
      {
        titleKey: 'nav:hub.accounting.sections.dailyEntry',
        tabs: [
          { labelKey: 'nav:items.journalEntry', icon: PenLine, path: '/accounting/treatment/journal-entry' },
          { labelKey: 'nav:items.searchEntries', icon: Search, path: '/accounting/treatment/search' },
          { labelKey: 'nav:items.lettrage', icon: Link2, path: '/accounting/treatment/lettrage' },
        ],
      },
      {
        titleKey: 'nav:hub.accounting.sections.structure',
        tabs: [
          { labelKey: 'nav:items.chartAccounts', icon: ListTree, path: '/accounting/chart-accounts' },
          { labelKey: 'nav:items.journals', icon: BookCopy, path: '/accounting/journals' },
          { labelKey: 'nav:items.thirdParty', icon: Contact, path: '/accounting/third-party' },
        ],
      },
      {
        titleKey: 'nav:hub.accounting.sections.states',
        tabs: [
          { labelKey: 'nav:items.generalLedger', icon: ScrollText, path: '/accounting/general-ledger' },
          { labelKey: 'nav:items.trialBalance', icon: Scale, path: '/accounting/trial-balance' },
          { labelKey: 'nav:items.fecExport', icon: FileDown, path: '/accounting/states/fec' },
        ],
      },
    ],
  },
  commercial: {
    sections: [
      {
        titleKey: 'nav:hub.commercial.sections.sales',
        tabs: [
          { labelKey: 'nav:items.invoices', icon: ReceiptText, path: '/sales/invoices' },
          { labelKey: 'nav:items.customers', icon: UserCircle, path: '/sales/customers' },
          { labelKey: 'nav:items.quotes', icon: FileSpreadsheet, path: '/sales/quotes' },
        ],
      },
      {
        titleKey: 'nav:hub.commercial.sections.purchases',
        tabs: [
          { labelKey: 'nav:items.purchaseInvoices', icon: Receipt, path: '/purchases/invoices' },
          { labelKey: 'nav:items.suppliers', icon: Truck, path: '/purchases/suppliers' },
          { labelKey: 'nav:items.purchaseOrders', icon: ShoppingCart, path: '/purchases/orders' },
        ],
      },
    ],
  },
  treasury: {
    sections: [
      {
        titleKey: 'nav:hub.treasury.sections.cashflow',
        tabs: [
          { labelKey: 'nav:items.treasuryDashboard', icon: LayoutDashboard, path: '/treasury/dashboard' },
          { labelKey: 'nav:items.forecasts', icon: TrendingUp, path: '/treasury/forecast' },
          { labelKey: 'nav:items.consolidatedTreasury', icon: Layers, path: '/treasury/consolidated' },
        ],
      },
      {
        titleKey: 'nav:hub.treasury.sections.payments',
        tabs: [
          { labelKey: 'nav:items.paymentOrders', icon: CreditCard, path: '/treasury/payment-orders' },
          { labelKey: 'nav:items.sepaTransfers', icon: Send, path: '/treasury/sepa' },
          { labelKey: 'nav:items.collections', icon: HandCoins, path: '/treasury/collections' },
        ],
      },
    ],
  },
  stock: {
    sections: [
      {
        titleKey: 'nav:hub.stock.sections.inventory',
        tabs: [
          { labelKey: 'nav:items.stockQuantities', icon: Boxes, path: '/stock/quantities' },
          { labelKey: 'nav:items.stockMovements', icon: ArrowLeftRight, path: '/stock/movements' },
          { labelKey: 'nav:items.inventory', icon: ClipboardCheck, path: '/stock/inventory' },
        ],
      },
      {
        titleKey: 'nav:hub.stock.sections.management',
        tabs: [
          { labelKey: 'nav:items.warehouses', icon: Warehouse, path: '/stock/warehouses' },
          { labelKey: 'nav:items.reorder', icon: RefreshCw, path: '/stock/reorder' },
          { labelKey: 'nav:items.priceLists', icon: Tag, path: '/stock/price-lists' },
        ],
      },
    ],
  },
  production: {
    sections: [
      {
        titleKey: 'nav:hub.production.sections.manufacturing',
        tabs: [
          { labelKey: 'nav:items.manufacturingOrders', icon: Factory, path: '/production/manufacturing' },
          { labelKey: 'nav:items.routings', icon: GitBranch, path: '/production/routings' },
          { labelKey: 'nav:items.machines', icon: Cog, path: '/production/machines' },
        ],
      },
      {
        titleKey: 'nav:hub.production.sections.planning',
        tabs: [
          { labelKey: 'nav:items.mrp', icon: Calculator, path: '/production/mrp' },
          { labelKey: 'nav:items.forecasts', icon: TrendingUp, path: '/production/forecasts' },
          { labelKey: 'nav:items.planning', icon: CalendarRange, path: '/production/planning' },
        ],
      },
    ],
  },
  hr: {
    sections: [
      {
        titleKey: 'nav:hub.hr.sections.payroll',
        tabs: [
          { labelKey: 'nav:items.payRuns', icon: Banknote, path: '/hr/pay-runs' },
          { labelKey: 'nav:items.paySlips', icon: FileText, path: '/hr/pay-slips' },
          { labelKey: 'nav:items.payrollAccounting', icon: Calculator, path: '/hr/payroll-accounting' },
        ],
      },
      {
        titleKey: 'nav:hub.hr.sections.admin',
        tabs: [
          { labelKey: 'nav:items.employees', icon: Users, path: '/hr/employees' },
          { labelKey: 'nav:items.timesheets', icon: Clock, path: '/hr/timesheets' },
          { labelKey: 'nav:items.leaveRequests', icon: CalendarX, path: '/hr/leave-requests' },
        ],
      },
    ],
  },
  dashboards: {
    sections: [
      {
        titleKey: 'nav:hub.dashboards.sections.analytics',
        tabs: [
          { labelKey: 'nav:items.salesDashboard', icon: BarChart3, path: '/dashboard/sales' },
          { labelKey: 'nav:items.purchasesDashboard', icon: ShoppingCart, path: '/dashboard/purchases' },
          { labelKey: 'nav:items.hrDashboard', icon: PieChart, path: '/dashboard/hr' },
        ],
      },
    ],
  },
  reporting: {
    sections: [
      {
        titleKey: 'nav:hub.reporting.sections.reports',
        tabs: [
          { labelKey: 'nav:items.financialDashboard', icon: PieChart, path: '/reporting/financial' },
          { labelKey: 'nav:items.biReporting', icon: Activity, path: '/reporting/bi' },
          { labelKey: 'nav:items.budgetTracking', icon: Target, path: '/reporting/budget' },
        ],
      },
    ],
  },
  system: {
    sections: [
      {
        titleKey: 'nav:hub.system.sections.configuration',
        tabs: [
          { labelKey: 'nav:items.company', icon: Building2, path: '/settings/company' },
          { labelKey: 'nav:items.usersMenu', icon: UserCog, path: '/settings/users' },
          { labelKey: 'nav:items.currencies', icon: Coins, path: '/settings/currencies' },
        ],
      },
      {
        titleKey: 'nav:hub.system.sections.data',
        tabs: [
          { labelKey: 'nav:items.dataImport', icon: Upload, path: '/settings/import' },
          { labelKey: 'nav:items.dataExport', icon: Download, path: '/settings/data-export' },
          { labelKey: 'nav:items.auditLog', icon: History, path: '/system/audit-log' },
        ],
      },
    ],
  },
}

interface ModuleHomePageProps {
  moduleId: string
}

export function ModuleHomePage({ moduleId }: ModuleHomePageProps) {
  const navigate = useNavigate()
  const { t } = useTranslation(['nav', 'accounting'])

  const mod = navModules.find((m) => m.id === moduleId)
  if (!mod) return null

  const config = moduleHomeConfigs[moduleId]
  if (!config) return null

  const colorVar = colorVarMap[mod.color]
  const colorBg = colorBgMap[mod.color]

  return (
    <div className="animate-fade-in">
      {/* Breadcrumb */}
      <nav className="flex items-center gap-1.5 text-sm text-[var(--color-text-secondary)] mb-6">
        <Link to="/" className="hover:text-[var(--color-text)] transition-colors">{t('nav:groups.home')}</Link>
        <ChevronRight className="w-3.5 h-3.5" />
        <span className="text-[var(--color-text)] font-medium" style={{ color: `var(${colorVar})` }}>
          {t(`nav:${mod.groupKey}`)}
        </span>
      </nav>

      {/* Hero header */}
      <div
        className="relative overflow-hidden rounded-2xl p-6 mb-8 border border-[var(--color-border)]"
        style={{ background: `var(${colorBg})` }}
      >
        <img
          src="/brand/hero-geometric.png"
          alt=""
          className="absolute inset-0 w-full h-full object-cover opacity-[0.06] pointer-events-none"
          aria-hidden="true"
        />
        <div className="absolute top-0 right-0 w-40 h-40 rounded-full opacity-10 blur-3xl" style={{ background: `var(${colorVar})` }} />
        <div className="relative flex items-start gap-4">
          <div
            className={cn('mod-icon w-14 h-14 rounded-2xl', `mod-${mod.color}`)}
            style={{ background: `var(${colorBg})` }}
          >
            <mod.icon className="w-7 h-7" />
          </div>
          <div className="flex-1">
            <h1 className="text-2xl font-bold text-[var(--color-text)]">
              {t(`nav:${mod.groupKey}`)}
            </h1>
            <p className="text-sm text-[var(--color-text-secondary)] mt-1">
              {t(`nav:hub.${mod.id}.subtitle`)}
            </p>
          </div>
        </div>
      </div>

      {/* Sections with tabs */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {config.sections.map((section, secIdx) => (
          <div
            key={secIdx}
            className="relative rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-6 overflow-hidden"
          >
            <div className="flex items-center gap-3 mb-5">
              <span
                className="w-1 h-6 rounded-full"
                style={{ background: `var(${colorVar})` }}
              />
              <h2 className="text-sm font-bold text-[var(--color-text)] uppercase tracking-wider">
                {t(section.titleKey)}
              </h2>
            </div>
            <div className="flex flex-wrap gap-3">
              {section.tabs.map((tab, tabIdx) => {
                const Icon = tab.icon
                return (
                  <button
                    key={tabIdx}
                    onClick={() => navigate(tab.path)}
                    className="group relative flex flex-col items-center justify-center gap-3 w-[130px] h-[130px] rounded-2xl border transition-all duration-300 hover:-translate-y-1 hover:scale-[1.03] p-4 text-center overflow-hidden"
                    style={{
                      borderWidth: '1px',
                      borderStyle: 'solid',
                      borderColor: `color-mix(in srgb, var(${colorVar}) 15%, transparent)`,
                      background: `var(${colorBg})`,
                    }}
                  >
                    <div
                      className="relative w-14 h-14 rounded-2xl flex items-center justify-center transition-transform duration-300 group-hover:scale-110"
                      style={{
                        background: `color-mix(in srgb, var(${colorVar}) 15%, transparent)`,
                        color: `var(${colorVar})`,
                      }}
                    >
                      <Icon className="w-7 h-7" strokeWidth={1.7} />
                    </div>
                    <span className="relative text-xs font-semibold text-[var(--color-text)] leading-tight line-clamp-2">
                      {t(tab.labelKey)}
                    </span>
                  </button>
                )
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
