import { useEffect, useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuth } from '@/lib/auth'
import { useTenantModules } from '@/lib/useTenantModules'
import { navModules, setEnabledModuleIds, type NavModule, type ModuleColor } from '@/components/Sidebar'
import { cn } from '@/lib/utils'
import {
  BookOpen, Wallet, Users,
  ClipboardList,
  ChevronRight, ArrowUpRight, Sparkles,
  type LucideIcon,
} from 'lucide-react'

const RBAC_MODULE_IDS = new Set(['accounting', 'commercial', 'treasury', 'stock', 'production', 'hr', 'projectManagement'])

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

interface QuickAction {
  labelKey: string
  icon: LucideIcon
  path: string
  color: string
}

const quickActions: QuickAction[] = [
  { labelKey: 'nav:items.invoices', icon: BookOpen, path: '/sales/invoices', color: 'emerald' },
  { labelKey: 'nav:items.journalEntry', icon: ClipboardList, path: '/accounting/treatment/journal-entry', color: 'indigo' },
  { labelKey: 'nav:items.employees', icon: Users, path: '/hr/employees', color: 'cyan' },
  { labelKey: 'nav:items.treasuryDashboard', icon: Wallet, path: '/treasury/dashboard', color: 'amber' },
]

export function HomePage() {
  const { t } = useTranslation(['nav', 'common'])
  const { user } = useAuth()
  const { modules: enabledModules } = useTenantModules()
  const navigate = useNavigate()
  const [animateIn, setAnimateIn] = useState(false)

  useEffect(() => {
    setEnabledModuleIds(enabledModules)
    const timer = setTimeout(() => setAnimateIn(true), 50)
    return () => clearTimeout(timer)
  }, [enabledModules])

  // Filter modules by enabled + RBAC
  const moduleRoles = useMemo(() => user?.module_roles || {}, [user])
  const isGlobalAdmin = user?.role === 'admin'
  const accessibleModules = useMemo(() => {
    return navModules.filter((mod) => {
      if (mod.id === 'home') return false // skip "home" module, we ARE the home page
      if (!enabledModules.includes(mod.id)) return false
      if (!RBAC_MODULE_IDS.has(mod.id)) return true
      if (isGlobalAdmin) return true
      const role = moduleRoles[mod.id]
      return role != null && String(role) !== ''
    })
  }, [enabledModules, moduleRoles, isGlobalAdmin])

  const greeting = useMemo(() => {
    const hour = new Date().getHours()
    if (hour < 12) return t('homePage.greetingMorning')
    if (hour < 18) return t('homePage.greetingAfternoon')
    return t('homePage.greetingEvening')
  }, [t])

  return (
    <div className="animate-fade-in">
      {/* Hero */}
      <div className="relative mb-8 overflow-hidden rounded-3xl border border-[var(--color-border)] bg-gradient-to-br from-[var(--color-surface)] via-[var(--color-surface)] to-[var(--color-neutral-50)] dark:to-white/5 p-8 backdrop-blur-sm">
        <img
          src="/brand/hero-geometric.png"
          alt=""
          className="absolute inset-0 w-full h-full object-cover opacity-[0.05] pointer-events-none"
          aria-hidden="true"
        />
        <div className="absolute top-0 right-0 w-64 h-64 bg-gradient-to-br from-[#C44536]/10 to-[#1E2A4A]/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-0 w-48 h-48 bg-gradient-to-tr from-[#2D7D6F]/10 to-[#E8A838]/5 rounded-full blur-3xl pointer-events-none" />
        <div className="relative">
          <p className="text-sm text-[var(--color-text-secondary)] mb-1">{greeting}</p>
          <h1 className="text-3xl font-bold bg-gradient-to-r from-[var(--color-text)] to-[var(--color-text-secondary)] bg-clip-text text-transparent">
            {user?.name || user?.email}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-2 max-w-2xl">
            {t('homePage.subtitle')}
          </p>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        {quickActions.map((action, idx) => {
          const colorVar = colorVarMap[action.color as ModuleColor]
          const colorBg = colorBgMap[action.color as ModuleColor]
          return (
            <button
              key={action.path}
              onClick={() => navigate(action.path)}
              className={cn(
                'group relative flex items-center gap-3 p-4 rounded-2xl border transition-all duration-300 hover:-translate-y-1 hover:shadow-lg',
                'border-[var(--color-border)] bg-[var(--color-surface)]',
                animateIn ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'
              )}
              style={{ transitionDelay: `${idx * 75}ms` }}
            >
              <div
                className="w-11 h-11 rounded-xl flex items-center justify-center transition-transform group-hover:scale-110"
                style={{ background: `var(${colorBg})` }}
              >
                <action.icon
                  className="w-5 h-5"
                  style={{ color: `var(${colorVar})` }}
                />
              </div>
              <div className="text-left flex-1 min-w-0">
                <p className="text-sm font-semibold text-[var(--color-text)] truncate">{t(action.labelKey)}</p>
                <p className="text-xs text-[var(--color-text-secondary)] flex items-center gap-0.5">
                  {t('homePage.open')} <ArrowUpRight className="w-3 h-3" />
                </p>
              </div>
            </button>
          )
        })}
      </div>

      {/* Modules Grid */}
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-lg font-bold text-[var(--color-text)]">{t('homePage.modules')}</h2>
        <span className="text-xs text-[var(--color-text-secondary)]">
          {accessibleModules.length} {t('homePage.modulesAvailable')}
        </span>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5">
        {accessibleModules.map((mod, idx) => (
          <ModuleCard
            key={mod.id}
            mod={mod}
            index={idx}
            animateIn={animateIn}
            onNavigate={(path) => navigate(path)}
          />
        ))}
      </div>

      {/* Footer hint */}
      <div className="mt-10 flex items-center justify-center gap-2 text-xs text-[var(--color-text-secondary)]">
        <Sparkles className="w-3.5 h-3.5" />
        <span>{t('homePage.footerHint')}</span>
      </div>
    </div>
  )
}

// ============================================
// Module Card
// ============================================
function ModuleCard({
  mod,
  index,
  animateIn,
  onNavigate,
}: {
  mod: NavModule
  index: number
  animateIn: boolean
  onNavigate: (path: string) => void
}) {
  const { t } = useTranslation('nav')
  const colorVar = colorVarMap[mod.color]
  const colorBg = colorBgMap[mod.color]

  // Get top 4 items for quick access
  const allItems = mod.sections
    ? mod.sections.flatMap((s) => s.items)
    : mod.items || []
  const topItems = allItems.slice(0, 4)

  return (
    <div
      className={cn(
        'group relative rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden transition-all duration-300 hover:shadow-xl hover:-translate-y-1',
        animateIn ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'
      )}
      style={{ transitionDelay: `${index * 60}ms` }}
    >
      {/* Header */}
      <div
        className="relative p-5 cursor-pointer"
        style={{ background: `var(${colorBg})` }}
        onClick={() => onNavigate(mod.homePath || mod.path)}
      >
        <div className="flex items-center gap-3">
          <div
            className={cn('mod-icon w-12 h-12 rounded-2xl flex items-center justify-center transition-transform group-hover:scale-110')}
            style={{ background: `var(${colorBg})` }}
          >
            <mod.icon className="w-6 h-6" style={{ color: `var(${colorVar})` }} />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="text-base font-bold text-[var(--color-text)] truncate">
              {t(mod.groupKey)}
            </h3>
            <p className="text-xs text-[var(--color-text-secondary)] truncate">
              {t(`hub.${mod.id}.subtitle`)}
            </p>
          </div>
          <ChevronRight className="w-5 h-5 text-[var(--color-text-secondary)] group-hover:translate-x-1 transition-transform" />
        </div>
      </div>

      {/* Quick links */}
      <div className="p-4 space-y-1">
        {topItems.map((item) => (
          <button
            key={item.path}
            onClick={() => onNavigate(item.path)}
            className="w-full flex items-center justify-between px-3 py-2 rounded-lg text-sm text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-50)] transition-colors text-left"
          >
            <span className="truncate">{t(item.labelKey)}</span>
            <ArrowUpRight className="w-3.5 h-3.5 flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity" />
          </button>
        ))}
        {allItems.length > 4 && (
          <button
            onClick={() => onNavigate(mod.homePath || mod.path)}
            className="w-full flex items-center justify-center gap-1 px-3 py-2 mt-1 rounded-lg text-xs font-medium transition-colors"
            style={{ color: `var(${colorVar})` }}
          >
            {t('hub.viewAll')} ({allItems.length} {t('hub.pages')})
            <ChevronRight className="w-3 h-3" />
          </button>
        )}
      </div>
    </div>
  )
}
