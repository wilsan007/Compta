import { useState, useMemo } from 'react'
import { useNavigate, useLocation, Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { navModules, getEnabledNavModules, type NavModule, type NavSection, type ModuleColor } from './Sidebar'
import {
  ArrowRight,
  ChevronRight,
  Search,
} from 'lucide-react'

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
// MODULE HUB PAGE
// ============================================
interface ModuleHubPageProps {
  moduleId: string
}

export function ModuleHubPage({ moduleId }: ModuleHubPageProps) {
  const { t } = useTranslation('nav')
  const navigate = useNavigate()
  const location = useLocation()
  const [searchQuery, setSearchQuery] = useState('')

  const mod = navModules.find((m) => m.id === moduleId)
  if (!mod) return null

  const colorVar = colorVarMap[mod.color]
  const colorBg = colorBgMap[mod.color]

  const allItems = useMemo(() => {
    if (mod.sections) {
      return mod.sections.flatMap((s) => s.items.map((i) => ({ ...i, section: s })))
    }
    return (mod.items || []).map((i) => ({ ...i, section: null }))
  }, [mod])

  const filteredItems = useMemo(() => {
    if (!searchQuery.trim()) return null
    const q = searchQuery.toLowerCase()
    return allItems.filter((item) => t(item.labelKey).toLowerCase().includes(q))
  }, [searchQuery, allItems, t])

  function isActive(path: string): boolean {
    if (path === '/') return location.pathname === '/'
    return location.pathname === path || location.pathname.startsWith(path + '/')
  }

  return (
    <div className="animate-fade-in">
      {/* Breadcrumb */}
      <nav className="flex items-center gap-1.5 text-sm text-[var(--color-text-secondary)] mb-6">
        <Link to="/" className="hover:text-[var(--color-text)] transition-colors">{t('groups.home')}</Link>
        <ChevronRight className="w-3.5 h-3.5" />
        <span className="text-[var(--color-text)] font-medium" style={{ color: `var(${colorVar})` }}>
          {t(mod.groupKey)}
        </span>
      </nav>

      {/* Hero header */}
      <div
        className="relative overflow-hidden rounded-2xl p-6 mb-6 border border-[var(--color-border)]"
        style={{ background: `var(${colorBg})` }}
      >
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
              {t(mod.groupKey)}
            </h1>
            <p className="text-sm text-[var(--color-text-secondary)] mt-1">
              {t(`hub.${mod.id}.subtitle`)}
            </p>
          </div>
        </div>
      </div>

      {/* Search bar */}
      <div className="relative mb-6">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t('layout.filterPages')}
          className="sidebar-search"
          style={{ paddingLeft: '36px' }}
        />
      </div>

      {/* Search results */}
      {filteredItems ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
          {filteredItems.length === 0 ? (
            <p className="col-span-full text-center text-sm text-[var(--color-text-secondary)] py-12">
              {t('layout.noResults')}
            </p>
          ) : (
            filteredItems.map((item) => (
              <HubTile
                key={item.path}
                label={t(item.labelKey)}
                colorVar={colorVar}
                colorBg={colorBg}
                active={isActive(item.path)}
                onClick={() => navigate(item.path)}
              />
            ))
          )}
        </div>
      ) : (
        <>
          {/* Sections with sub-group hubs */}
          {mod.sections ? (
            <div className="space-y-8">
              {mod.sections.map((sec, secIdx) => (
                <SectionGroup
                  key={secIdx}
                  mod={mod}
                  section={sec}
                  colorVar={colorVar}
                  colorBg={colorBg}
                  isActive={isActive}
                  onNavigate={(p) => navigate(p)}
                  t={t}
                />
              ))}
            </div>
          ) : (
            /* Flat items grid */
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
              {mod.items?.map((item) => (
                <HubTile
                  key={item.path}
                  label={t(item.labelKey)}
                  colorVar={colorVar}
                  colorBg={colorBg}
                  active={isActive(item.path)}
                  onClick={() => navigate(item.path)}
                />
              ))}
            </div>
          )}

          {/* Quick shortcuts */}
          <QuickShortcuts mod={mod} t={t} />
        </>
      )}
    </div>
  )
}

// ============================================
// SECTION GROUP (sub-group hub within a module)
// ============================================
interface SectionGroupProps {
  mod: NavModule
  section: NavSection
  colorVar: string
  colorBg: string
  isActive: (path: string) => boolean
  onNavigate: (path: string) => void
  t: (key: string) => string
}

function SectionGroup({ mod, section, colorVar, colorBg, isActive, onNavigate, t }: SectionGroupProps) {
  const sectionActive = section.items.some((item) => isActive(item.path))

  return (
    <div>
      {/* Section header with link to sub-hub */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <span
            className="w-1 h-5 rounded-full"
            style={{ background: `var(${colorVar})` }}
          />
          <h2 className="text-base font-semibold text-[var(--color-text)]">
            {section.subGroupKey ? t(section.subGroupKey) : t(mod.groupKey)}
          </h2>
          <span className="text-xs text-[var(--color-text-secondary)] bg-[var(--color-neutral-100)] px-2 py-0.5 rounded-full">
            {section.items.length}
          </span>
        </div>
        {section.hubPath && (
          <Link
            to={section.hubPath}
            className="flex items-center gap-1 text-xs font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors"
            style={{ color: sectionActive ? `var(${colorVar})` : undefined }}
          >
            {t('hub.viewAll')}
            <ArrowRight className="w-3 h-3" />
          </Link>
        )}
      </div>

      {/* Items grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
        {section.items.map((item) => (
          <HubTile
            key={item.path}
            label={t(item.labelKey)}
            colorVar={colorVar}
            colorBg={colorBg}
            active={isActive(item.path)}
            onClick={() => onNavigate(item.path)}
          />
        ))}
      </div>
    </div>
  )
}

// ============================================
// HUB TILE
// ============================================
interface HubTileProps {
  label: string
  colorVar: string
  colorBg: string
  active: boolean
  onClick: () => void
}

function HubTile({ label, colorVar, colorBg, active, onClick }: HubTileProps) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'group relative flex items-center gap-3 p-4 rounded-xl border transition-all duration-200 text-left overflow-hidden',
        active
          ? 'border-transparent shadow-md'
          : 'border-[var(--color-border)] bg-[var(--color-surface)] hover:border-[var(--color-neutral-300)] hover:shadow-sm'
      )}
      style={active ? { background: `var(${colorBg})`, borderColor: `var(${colorVar})` } : undefined}
    >
      {/* Left accent bar */}
      <span
        className="w-1 h-8 rounded-full flex-shrink-0 transition-all"
        style={{
          background: `var(${colorVar})`,
          opacity: active ? 1 : 0.3,
        }}
      />
      <span
        className={cn(
          'text-sm font-medium flex-1 truncate transition-colors',
          active ? '' : 'text-[var(--color-text-secondary)] group-hover:text-[var(--color-text)]'
        )}
        style={active ? { color: `var(${colorVar})` } : undefined}
      >
        {label}
      </span>
      <ArrowRight
        className="w-4 h-4 flex-shrink-0 transition-all opacity-0 group-hover:opacity-100 -translate-x-1 group-hover:translate-x-0"
        style={{ color: `var(${colorVar})` }}
      />
    </button>
  )
}

// ============================================
// QUICK SHORTCUTS
// ============================================
interface QuickShortcutsProps {
  mod: NavModule
  t: (key: string) => string
}

function QuickShortcuts({ mod, t }: QuickShortcutsProps) {
  const otherModules = getEnabledNavModules().filter((m) => m.id !== mod.id).slice(0, 5)

  return (
    <div className="mt-10 pt-6 border-t border-[var(--color-border)]">
      <p className="text-[10px] font-semibold text-[var(--color-text-secondary)] uppercase tracking-wider mb-3">
        {t('hub.quickNavigation')}
      </p>
      <div className="flex flex-wrap gap-2">
        {otherModules.map((other) => {
          return (
            <Link
              key={other.id}
              to={other.path}
              className="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] hover:shadow-sm transition-all group"
            >
              <div className={cn('mod-icon w-6 h-6 rounded-md', `mod-${other.color}`)}>
                <other.icon className="w-3.5 h-3.5" />
              </div>
              <span className="text-xs font-medium text-[var(--color-text-secondary)] group-hover:text-[var(--color-text)] transition-colors">
                {t(other.groupKey)}
              </span>
            </Link>
          )
        })}
      </div>
    </div>
  )
}

// ============================================
// SUB-GROUP HUB PAGE
// ============================================
interface SubGroupHubPageProps {
  moduleId: string
  sectionIndex: number
}

export function SubGroupHubPage({ moduleId, sectionIndex }: SubGroupHubPageProps) {
  const { t } = useTranslation('nav')
  const navigate = useNavigate()
  const location = useLocation()

  const mod = navModules.find((m) => m.id === moduleId)
  if (!mod || !mod.sections) return null

  const section = mod.sections[sectionIndex]
  if (!section) return null

  const colorVar = colorVarMap[mod.color]
  const colorBg = colorBgMap[mod.color]

  function isActive(path: string): boolean {
    if (path === '/') return location.pathname === '/'
    return location.pathname === path || location.pathname.startsWith(path + '/')
  }

  return (
    <div className="animate-fade-in">
      {/* Breadcrumb */}
      <nav className="flex items-center gap-1.5 text-sm text-[var(--color-text-secondary)] mb-6">
        <Link to="/" className="hover:text-[var(--color-text)] transition-colors">{t('groups.home')}</Link>
        <ChevronRight className="w-3.5 h-3.5" />
        <Link to={mod.path} className="hover:text-[var(--color-text)] transition-colors">{t(mod.groupKey)}</Link>
        <ChevronRight className="w-3.5 h-3.5" />
        <span className="text-[var(--color-text)] font-medium" style={{ color: `var(${colorVar})` }}>
          {section.subGroupKey ? t(section.subGroupKey) : ''}
        </span>
      </nav>

      {/* Section hero */}
      <div
        className="relative overflow-hidden rounded-2xl p-6 mb-6 border border-[var(--color-border)]"
        style={{ background: `var(${colorBg})` }}
      >
        <div className="absolute top-0 right-0 w-32 h-32 rounded-full opacity-10 blur-3xl" style={{ background: `var(${colorVar})` }} />
        <div className="relative flex items-center gap-4">
          <div className={cn('mod-icon w-12 h-12 rounded-xl', `mod-${mod.color}`)}>
            <mod.icon className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-[var(--color-text)]">
              {t(mod.groupKey)} — {section.subGroupKey ? t(section.subGroupKey) : ''}
            </h1>
            <p className="text-sm text-[var(--color-text-secondary)] mt-0.5">
              {section.items.length} {t('hub.pages')}
            </p>
          </div>
        </div>
      </div>

      {/* Items grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
        {section.items.map((item) => (
          <HubTile
            key={item.path}
            label={t(item.labelKey)}
            colorVar={colorVar}
            colorBg={colorBg}
            active={isActive(item.path)}
            onClick={() => navigate(item.path)}
          />
        ))}
      </div>

      {/* Back to module */}
      <div className="mt-8">
        <Link
          to={mod.path}
          className="inline-flex items-center gap-2 text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors"
        >
          <ChevronRight className="w-4 h-4 rotate-180" />
          {t('hub.backToModule')} {t(mod.groupKey)}
        </Link>
      </div>
    </div>
  )
}
