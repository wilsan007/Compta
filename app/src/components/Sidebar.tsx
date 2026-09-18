/* oxlint-disable react/only-export-components -- composants et hooks/constantes associes exportes ensemble */
import { useState, useEffect, useMemo, useRef } from 'react'
import { NavLink, useLocation, useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import {
  ChevronRight,
  Search,
  PanelLeft,
  X,
  Pin,
  PinOff,
  ChevronDown,
  Building2,
  Check,
  type LucideIcon,
} from 'lucide-react'
import { useTenantModules } from '@/lib/useTenantModules'
import { useAuth } from '@/lib/auth'
// PRF-02 : Types et config de navigation extraits dans navModules.ts
import {
  type ModuleColor,
  type NavItem,
  type NavSection,
  type NavModule,
  navModules,
} from '@/components/navModules'

// Re-export pour compatibilité
export { type ModuleColor, type NavItem, type NavSection, type NavModule, navModules }

// Modules that require module_roles RBAC check
const RBAC_MODULE_IDS = new Set(['accounting', 'commercial', 'treasury', 'stock', 'production', 'hr', 'projectManagement'])


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
  moduleId: string
  items: LegacyNavItem[]
}

export const navGroups: LegacyNavGroup[] = navModules.map((mod) => ({
  groupKey: mod.groupKey,
  moduleId: mod.id,
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
    moduleId: mod.id,
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
  // Collect all (moduleId, path) pairs across all modules, sort by path length
  // descending so more specific paths match before shorter prefixes
  const allEntries: { modId: string; path: string }[] = []
  for (const mod of getEnabledNavModules()) {
    if (mod.homePath && mod.homePath !== '/') allEntries.push({ modId: mod.id, path: mod.homePath })
    if (mod.path !== '/') allEntries.push({ modId: mod.id, path: mod.path })
    const itemPaths = mod.sections
      ? mod.sections.flatMap((s) => s.items.map((i) => i.path))
      : mod.items?.map((i) => i.path) || []
    for (const p of itemPaths) {
      allEntries.push({ modId: mod.id, path: p })
    }
  }
  allEntries.sort((a, b) => b.path.length - a.path.length)
  for (const { modId, path } of allEntries) {
    if (path === '/' && pathname === '/') return modId
    if (path !== '/' && pathname.startsWith(path)) return modId
  }
  return null
}

function getSubGroupForPath(mod: NavModule, pathname: string): string | null {
  if (!mod.sections) return null
  // Flatten all items with their subGroupKey, sort by path length descending
  // so more specific paths (e.g. /project-management/graph) match before
  // shorter prefixes (e.g. /project-management) that would falsely capture them
  const allItems = mod.sections
    .flatMap((sec) => sec.items.map((item) => ({ path: item.path, subGroupKey: sec.subGroupKey || '' })))
    .sort((a, b) => b.path.length - a.path.length)
  for (const { path, subGroupKey } of allItems) {
    if (path === '/' && pathname === '/') return subGroupKey || null
    if (path !== '/' && pathname.startsWith(path)) return subGroupKey || null
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

function getAllItems(modules?: NavModule[]): { mod: NavModule; item: NavItem }[] {
  const mods = modules || getEnabledNavModules()
  const result: { mod: NavModule; item: NavItem }[] = []
  for (const mod of mods) {
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
  const { t: tCommon } = useTranslation('common')
  const { modules: enabledModules } = useTenantModules()
  const { user, availableTenants, switchTenant } = useAuth()
  const [expandedModule, setExpandedModule] = useState<string | null>(null)
  const [expandedSubGroup, setExpandedSubGroup] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState('')
  const [pinnedPaths, setPinnedPaths] = useState<string[]>([])
  const [peeking, setPeeking] = useState(false)
  const peekTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const sidebarRef = useRef<HTMLElement>(null)
  const [showTenantMenu, setShowTenantMenu] = useState(false)
  const [switchingTenant, setSwitchingTenant] = useState(false)

  // Sync enabled modules with the module-level filter
  useEffect(() => {
    setEnabledModuleIds(enabledModules)
  }, [enabledModules])

  // Filter modules by user's module_roles (RBAC)
  const moduleRoles = useMemo(() => user?.module_roles || {}, [user])
  const isGlobalAdmin = user?.role === 'admin'
  const accessibleNavModules = useMemo(() => {
    return getEnabledNavModules().filter(mod => {
      if (!RBAC_MODULE_IDS.has(mod.id)) return true
      if (isGlobalAdmin) return true
      const role = moduleRoles[mod.id]
      return role != null && String(role) !== ''
    })
  }, [moduleRoles, isGlobalAdmin])

  // Load pinned items from localStorage
  useEffect(() => {
    const saved = localStorage.getItem('compta-pinned')
    if (saved) {
      try {
        setPinnedPaths(JSON.parse(saved))
      } catch (err) {
        console.error("catch:", err)
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
      const mod = accessibleNavModules.find((m) => m.id === modId)
      if (mod?.sections) {
        const subKey = getSubGroupForPath(mod, location.pathname)
        if (subKey) {
          setExpandedSubGroup(`${modId}:${subKey}`)
        }
      }
    }
  }, [location.pathname, accessibleNavModules])

  // Close search when collapsing
  useEffect(() => {
    if (collapsed && !peeking) {
      setSearchQuery('')
      setExpandedModule(null)
      setExpandedSubGroup(null)
    }
  }, [collapsed, peeking])

  // Auto-close peek on navigation
  useEffect(() => {
    setPeeking(false)
  }, [location.pathname])

  // Click-outside to close peek
  useEffect(() => {
    if (!peeking) return
    function handleClickOutside(e: MouseEvent) {
      if (sidebarRef.current && !sidebarRef.current.contains(e.target as Node)) {
        setPeeking(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [peeking])

  // Escape to close peek
  useEffect(() => {
    if (!peeking) return
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') setPeeking(false)
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [peeking])

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
    if (collapsed && !peeking) return
    if (mod.id === expandedModule) {
      setExpandedModule(null)
      setExpandedSubGroup(null)
    } else {
      setExpandedModule(mod.id)
      setExpandedSubGroup(null)
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
    return getAllItems(accessibleNavModules).filter(({ item }) => {
      const label = t(item.labelKey).toLowerCase()
      return label.includes(q)
    })
  }, [searchQuery, t, accessibleNavModules])

  // Pinned items
  const pinnedItems = useMemo(() => {
    return getAllItems(accessibleNavModules).filter(({ item }) => pinnedPaths.includes(item.path))
  }, [pinnedPaths, accessibleNavModules])

  function handleRailMouseEnter() {
    if (!collapsed) return
    if (peekTimerRef.current) clearTimeout(peekTimerRef.current)
    peekTimerRef.current = setTimeout(() => setPeeking(true), 200)
  }

  function handleSidebarMouseLeave() {
    if (!peeking) return
    if (peekTimerRef.current) clearTimeout(peekTimerRef.current)
    peekTimerRef.current = setTimeout(() => setPeeking(false), 150)
  }

  function handleSidebarMouseEnter() {
    if (peekTimerRef.current) clearTimeout(peekTimerRef.current)
  }

  // ============================================
  // RENDER: COLLAPSED RAIL (with peek overlay)
  // ============================================
  if (collapsed) {
    return (
      <>
      <aside
        ref={sidebarRef}
        className={cn(
          'fixed lg:sticky top-0 left-0 h-screen w-16 border-r border-[var(--color-border)] sidebar-glass flex flex-col z-50 transition-transform duration-300',
          mobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
        )}
        onMouseEnter={handleRailMouseEnter}
        onMouseLeave={handleSidebarMouseLeave}
      >
        {/* Logo collapsed */}
        <div className="flex items-center justify-center h-14 border-b border-[var(--color-border)] flex-shrink-0">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center shadow-md">
            <span className="text-white font-bold text-base">C</span>
          </div>
        </div>

        {/* Module icons */}
        <nav className="flex-1 overflow-y-auto sidebar-scroll py-3 px-2 space-y-1">
          {accessibleNavModules.map((mod) => {
            const active = isModuleActive(mod)
            const colorVar = colorVarMap[mod.color]
            return (
              <button
                key={mod.id}
                onClick={() => {
                  navigate(mod.homePath || mod.path)
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

      {/* Peek overlay — full sidebar floating panel */}
      {peeking && (
        <div
          className="sidebar-peek fixed top-0 left-16 h-screen w-72 z-[60] sidebar-glass border-r border-[var(--color-border)] flex flex-col shadow-2xl"
          onMouseEnter={handleSidebarMouseEnter}
          onMouseLeave={handleSidebarMouseLeave}
        >
          {/* Logo + tenant switcher + close */}
          <div className="flex items-center gap-3 h-14 px-4 border-b border-[var(--color-border)] flex-shrink-0">
            <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center shadow-md flex-shrink-0">
              <span className="text-white font-bold text-base">C</span>
            </div>
            <div className="overflow-hidden flex-1">
              <p className="font-bold text-[var(--color-text)] text-sm whitespace-nowrap truncate">{user?.tenantName || 'Compta'}</p>
              <p className="text-[10px] text-[var(--color-text-secondary)] whitespace-nowrap">v0.3 - Aurora</p>
            </div>
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
                autoFocus
              />
              {searchQuery && (
                <button
                  onClick={() => setSearchQuery('')}
                  className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded text-[var(--color-text-secondary)] hover:text-[var(--color-text)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}>
                  <X className="w-3.5 h-3.5" aria-hidden="true" /></button>
              )}
            </div>
          </div>

          {/* Navigation — same as expanded sidebar */}
          <nav className="flex-1 overflow-y-auto sidebar-scroll px-2 py-2">
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
                        onClick={() => { onCloseMobile(); setPeeking(false) }}
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
                              onClick={() => { onCloseMobile(); setPeeking(false) }}
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
                              className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded opacity-0 group-hover:opacity-100 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)] transition-all" aria-label={tCommon('actions.unpin')} title={tCommon('actions.unpin')}>
                              <PinOff className="w-3 h-3" aria-hidden="true" /></button>
                          </div>
                        )
                      })}
                    </div>
                    <div className="mx-3 my-2 h-px bg-[var(--color-border)]" />
                  </div>
                )}

                {/* Modules */}
                {accessibleNavModules.map((mod) => {
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
                            to={mod.homePath || mod.path}
                            onClick={() => { onCloseMobile(); setPeeking(false) }}
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
                              className="p-1.5 mr-1 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-200)] transition-colors flex-shrink-0" aria-label={tCommon('actions.next')} title={tCommon('actions.next')}>
                              <ChevronRight className={cn('w-3.5 h-3.5 chevron-rotate', isExpanded && 'expanded')} aria-hidden="true" /></button>
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
                                        onClick={() => { onCloseMobile(); setPeeking(false) }}
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
                                            onClick={() => { onCloseMobile(); setPeeking(false) }}
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
                                            )} aria-label={tCommon('actions.pin')} title={tCommon('actions.pin')}>
                                            <Pin className="w-3 h-3" aria-hidden="true" /></button>
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
                                    onClick={() => { onCloseMobile(); setPeeking(false) }}
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
                                    )} aria-label={tCommon('actions.pin')} title={tCommon('actions.pin')}>
                                    <Pin className="w-3 h-3" aria-hidden="true" /></button>
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

          {/* Collapse button at bottom */}
          <div className="border-t border-[var(--color-border)] p-2 flex-shrink-0">
            <button
              onClick={() => { onToggleCollapse(); setPeeking(false) }}
              className="w-full flex items-center justify-center gap-2 p-2 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors text-xs"
            >
              <PanelLeft className="w-4 h-4" />
              <span>{t('layout.expand')}</span>
            </button>
          </div>
        </div>
      )}
      </>
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
      {/* Logo + tenant switcher + close */}
      <div className="flex items-center gap-3 h-14 px-4 border-b border-[var(--color-border)] flex-shrink-0">
        <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center shadow-md flex-shrink-0">
          <span className="text-white font-bold text-base">C</span>
        </div>
        <div className="overflow-hidden flex-1 relative">
          {availableTenants.length > 1 ? (
            <>
              <button
                onClick={() => setShowTenantMenu(!showTenantMenu)}
                className="flex items-center gap-1.5 w-full text-left group"
              >
                <div className="overflow-hidden flex-1">
                  <p className="font-bold text-[var(--color-text)] text-sm whitespace-nowrap truncate">{user?.tenantName || 'Compta'}</p>
                  <p className="text-[10px] text-[var(--color-text-secondary)] whitespace-nowrap flex items-center gap-1">
                    {t('layout.switchTenant')}
                    <ChevronDown className="w-2.5 h-2.5 group-hover:translate-y-0.5 transition-transform" />
                  </p>
                </div>
              </button>
              {showTenantMenu && (
                <>
                  <div className="fixed inset-0 z-40" onClick={() => setShowTenantMenu(false)} />
                  <div className="absolute left-0 top-full mt-1 bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg shadow-xl py-1 min-w-[220px] z-50">
                    <p className="px-3 py-2 text-[10px] font-bold uppercase tracking-wider text-[var(--color-text-secondary)] border-b border-[var(--color-border)]">
                      {t('layout.switchTenant')}
                    </p>
                    {availableTenants.map((tenant) => (
                      <button
                        key={tenant.tenantId}
                        disabled={switchingTenant}
                        onClick={async () => {
                          if (tenant.tenantId === user?.tenantId) {
                            setShowTenantMenu(false)
                            return
                          }
                          setSwitchingTenant(true)
                          await switchTenant(tenant.tenantId)
                          setSwitchingTenant(false)
                          setShowTenantMenu(false)
                        }}
                        className={`w-full text-left px-3 py-2 text-sm flex items-center gap-2 hover:bg-[var(--color-neutral-50)] transition-colors ${switchingTenant ? 'opacity-50 cursor-wait' : ''}`}
                      >
                        <Building2 className="w-3.5 h-3.5 flex-shrink-0 text-[var(--color-text-secondary)]" />
                        <div className="flex-1 min-w-0">
                          <p className="truncate text-[var(--color-text)]">{tenant.tenantName}</p>
                          <p className="text-[10px] text-[var(--color-text-secondary)] capitalize">{t('layout.tenantRole')}: {tenant.role}</p>
                        </div>
                        {tenant.tenantId === user?.tenantId && (
                          <Check className="w-4 h-4 text-[var(--color-primary)] flex-shrink-0" />
                        )}
                      </button>
                    ))}
                  </div>
                </>
              )}
            </>
          ) : (
            <>
              <p className="font-bold text-[var(--color-text)] text-sm whitespace-nowrap truncate">{user?.tenantName || 'Compta'}</p>
              <p className="text-[10px] text-[var(--color-text-secondary)] whitespace-nowrap">v0.3 - Aurora</p>
            </>
          )}
        </div>
        <button
          onClick={onCloseMobile}
          aria-label={tCommon('actions.close')}
          title={tCommon('actions.close')}
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
              className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded text-[var(--color-text-secondary)] hover:text-[var(--color-text)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}>
              <X className="w-3.5 h-3.5" aria-hidden="true" /></button>
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
                          className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded opacity-0 group-hover:opacity-100 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)] transition-all" aria-label={tCommon('actions.unpin')} title={tCommon('actions.unpin')}>
                          <PinOff className="w-3 h-3" aria-hidden="true" /></button>
                      </div>
                    )
                  })}
                </div>
                <div className="mx-3 my-2 h-px bg-[var(--color-border)]" />
              </div>
            )}

            {/* Modules */}
            {accessibleNavModules.map((mod) => {
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
                        to={mod.homePath || mod.path}
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
                          className="p-1.5 mr-1 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-200)] transition-colors flex-shrink-0" aria-label={tCommon('actions.next')} title={tCommon('actions.next')}>
                          <ChevronRight className={cn('w-3.5 h-3.5 chevron-rotate', isExpanded && 'expanded')} aria-hidden="true" /></button>
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
                                        )} aria-label={tCommon('actions.pin')} title={tCommon('actions.pin')}>
                                        <Pin className="w-3 h-3" aria-hidden="true" /></button>
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
                                )} aria-label={tCommon('actions.pin')} title={tCommon('actions.pin')}>
                                <Pin className="w-3 h-3" aria-hidden="true" /></button>
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
          <PanelLeft className="w-4 h-4" />
          <span>{t('layout.collapse')}</span>
        </button>
      </div>
    </aside>
  )
}
