import { useState, useEffect, useMemo, useRef } from 'react'
import { useLocation, Link } from 'react-router-dom'
import { cn } from '@/lib/utils'
import { ChevronUp, ChevronDown, ChevronsUpDown, ChevronLeft, ChevronRight, Loader2, X, Search, Check } from 'lucide-react'
import type { ReactNode } from 'react'

interface CardProps {
  children: ReactNode
  className?: string
  title?: string
  subtitle?: string
  action?: ReactNode
}

export function Card({ children, className, title, subtitle, action }: CardProps) {
  return (
    <div className={cn('card', className)}>
      {(title || action) && (
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <div>
            {title && <h3 className="text-base font-semibold text-[var(--color-text)]">{title}</h3>}
            {subtitle && <p className="text-sm text-[var(--color-text-secondary)] mt-1">{subtitle}</p>}
          </div>
          {action}
        </div>
      )}
      <div className="p-6">{children}</div>
    </div>
  )
}

interface StatCardProps {
  label: string
  value: string
  icon?: ReactNode
  trend?: { value: string; positive: boolean }
  color?: 'primary' | 'success' | 'warning' | 'danger'
}

export function StatCard({ label, value, icon, trend, color = 'primary' }: StatCardProps) {
  const colorMap = {
    primary: 'text-[var(--color-primary)] bg-[rgba(0,102,204,0.1)]',
    success: 'text-[var(--color-success)] bg-[rgba(0,135,90,0.1)]',
    warning: 'text-[var(--color-warning)] bg-[rgba(255,149,0,0.1)]',
    danger: 'text-[var(--color-danger)] bg-[rgba(222,53,11,0.1)]',
  }

  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-4">
        <span className="text-sm font-medium text-[var(--color-text-secondary)]">{label}</span>
        {icon && (
          <div className={cn('w-10 h-10 rounded-lg flex items-center justify-center', colorMap[color])}>
            {icon}
          </div>
        )}
      </div>
      <div className="text-2xl font-bold text-[var(--color-text)]">{value}</div>
      {trend && (
        <div className="flex items-center gap-1 mt-2">
          <span className={cn('text-xs font-medium', trend.positive ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]')}>
            {trend.positive ? '↑' : '↓'} {trend.value}
          </span>
          <span className="text-xs text-[var(--color-text-secondary)]">vs période précédente</span>
        </div>
      )}
    </div>
  )
}

interface BadgeProps {
  variant?: 'success' | 'warning' | 'danger' | 'neutral' | 'primary'
  children: ReactNode
}

export function Badge({ variant = 'neutral', children }: BadgeProps) {
  const variantMap = {
    success: 'badge-success',
    warning: 'badge-warning',
    danger: 'badge-danger',
    neutral: 'badge-neutral',
    primary: 'badge-primary',
  }
  return <span className={cn('badge', variantMap[variant])}>{children}</span>
}

interface ButtonProps {
  variant?: 'primary' | 'secondary' | 'danger' | 'ghost'
  size?: 'sm' | 'md' | 'lg'
  children: ReactNode
  onClick?: () => void
  type?: 'button' | 'submit'
  disabled?: boolean
  loading?: boolean
  className?: string
}

export function Button({ variant = 'primary', size = 'md', children, onClick, type = 'button', disabled, loading, className }: ButtonProps) {
  const variantMap = {
    primary: 'btn-primary',
    secondary: 'btn-secondary',
    danger: 'btn-danger',
    ghost: 'btn-ghost',
  }
  const sizeMap = {
    sm: 'text-xs px-3 py-1.5',
    md: 'text-sm px-4 py-2',
    lg: 'text-base px-6 py-3',
  }
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled || loading}
      className={cn('btn', variantMap[variant], sizeMap[size], (disabled || loading) && 'opacity-50 cursor-not-allowed', 'inline-flex items-center gap-2', className)}
    >
      {loading && <Loader2 className="w-4 h-4 animate-spin" />}
      {children}
    </button>
  )
}

interface InputProps {
  label?: string
  type?: string
  value?: string | number
  onChange?: (e: React.ChangeEvent<HTMLInputElement>) => void
  placeholder?: string
  required?: boolean
  className?: string
  step?: string
}

export function Input({ label, type = 'text', value, onChange, placeholder, required, className, step }: InputProps) {
  return (
    <div className={className}>
      {label && (
        <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1.5">
          {label} {required && <span className="text-[var(--color-danger)]">*</span>}
        </label>
      )}
      <input
        type={type}
        step={step}
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        required={required}
        className="input"
      />
    </div>
  )
}

interface SelectProps {
  label?: string
  value?: string
  onChange?: (e: React.ChangeEvent<HTMLSelectElement>) => void
  options: { value: string; label: string }[]
  required?: boolean
  className?: string
}

export function Select({ label, value, onChange, options, required, className }: SelectProps) {
  return (
    <div className={className}>
      {label && (
        <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1.5">
          {label} {required && <span className="text-[var(--color-danger)]">*</span>}
        </label>
      )}
      <select value={value} onChange={onChange} required={required} className="input cursor-pointer">
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>{opt.label}</option>
        ))}
      </select>
    </div>
  )
}

interface TableProps {
  headers: string[]
  children: ReactNode
}

export function Table({ headers, children }: TableProps) {
  return (
    <div className="table-container">
      <table className="app-table">
        <thead>
          <tr className="border-b border-[var(--color-border)]">
            {headers.map((h, i) => (
              <th key={i} className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase tracking-wider px-4 py-3">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-[var(--color-border)]">{children}</tbody>
      </table>
    </div>
  )
}

// ============================================
// SORTABLE TABLE
// ============================================
export type SortDirection = 'asc' | 'desc'

interface SortableTableProps<T> {
  headers: { label: string; key?: string; sortable?: boolean; className?: string }[]
  data: T[]
  renderRow: (item: T, index: number) => ReactNode
  initialSortKey?: string
  initialSortDir?: SortDirection
  pageSize?: number
  emptyState?: ReactNode
}

export function SortableTable<T extends Record<string, any>>({
  headers,
  data,
  renderRow,
  initialSortKey,
  initialSortDir = 'asc',
  pageSize = 25,
  emptyState,
}: SortableTableProps<T>) {
  const [sortKey, setSortKey] = useState<string | undefined>(initialSortKey)
  const [sortDir, setSortDir] = useState<SortDirection>(initialSortDir)
  const [page, setPage] = useState(0)

  const sorted = useMemo(() => {
    if (!sortKey) return data
    const sortedData = [...data].sort((a, b) => {
      const av = a[sortKey]
      const bv = b[sortKey]
      if (av == null && bv == null) return 0
      if (av == null) return 1
      if (bv == null) return -1
      if (typeof av === 'number' && typeof bv === 'number') return av - bv
      return String(av).localeCompare(String(bv), 'fr')
    })
    return sortDir === 'desc' ? sortedData.reverse() : sortedData
  }, [data, sortKey, sortDir])

  const totalPages = Math.max(1, Math.ceil(sorted.length / pageSize))
  const currentPage = Math.min(page, totalPages - 1)
  const pageData = sorted.slice(currentPage * pageSize, (currentPage + 1) * pageSize)

  function handleSort(key?: string) {
    if (!key) return
    if (sortKey === key) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    } else {
      setSortKey(key)
      setSortDir('asc')
    }
    setPage(0)
  }

  return (
    <div>
      <div className="table-container">
        <table className="app-table">
          <thead>
            <tr className="border-b border-[var(--color-border)]">
              {headers.map((h, i) => (
                <th
                  key={i}
                  className={cn(
                    'text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase tracking-wider px-4 py-3 select-none',
                    h.sortable && 'cursor-pointer hover:text-[var(--color-text)] transition-colors',
                    h.className,
                  )}
                  onClick={() => h.sortable && handleSort(h.key)}
                >
                  <span className="inline-flex items-center gap-1">
                    {h.label}
                    {h.sortable && (
                      <span className="flex-shrink-0">
                        {sortKey === h.key ? (
                          sortDir === 'asc' ? <ChevronUp className="w-3 h-3" /> : <ChevronDown className="w-3 h-3" />
                        ) : (
                          <ChevronsUpDown className="w-3 h-3 opacity-40" />
                        )}
                      </span>
                    )}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--color-border)]">
            {pageData.length > 0 ? (
              pageData.map((item, i) => renderRow(item, currentPage * pageSize + i))
            ) : (
              <tr>
                <td colSpan={headers.length} className="px-4 py-12 text-center text-sm text-[var(--color-text-secondary)]">
                  {emptyState || 'Aucune donnée'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      {sorted.length > pageSize && (
        <div className="flex items-center justify-between px-4 py-3 border-t border-[var(--color-border)]">
          <span className="text-xs text-[var(--color-text-secondary)]">
            {currentPage * pageSize + 1}–{Math.min((currentPage + 1) * pageSize, sorted.length)} sur {sorted.length}
          </span>
          <div className="flex items-center gap-1">
            <button
              onClick={() => setPage((p) => Math.max(0, p - 1))}
              disabled={currentPage === 0}
              className="p-1.5 rounded-md text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <span className="text-xs text-[var(--color-text-secondary)] px-2">
              {currentPage + 1} / {totalPages}
            </span>
            <button
              onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
              disabled={currentPage >= totalPages - 1}
              className="p-1.5 rounded-md text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

interface TableRowProps {
  children: ReactNode
  onClick?: () => void
}

export function TableRow({ children, onClick }: TableRowProps) {
  return (
    <tr onClick={onClick} className={cn('align-middle hover:bg-[var(--color-neutral-50)] transition-colors', onClick && 'cursor-pointer')}>
      {children}
    </tr>
  )
}

interface TableCellProps {
  children?: ReactNode
  className?: string
  colSpan?: number
}

export function TableCell({ children, className, colSpan }: TableCellProps) {
  return <td colSpan={colSpan} className={cn('align-middle px-4 py-3 text-sm text-[var(--color-text)]', className)}>{children}</td>
}

interface EmptyStateProps {
  icon?: ReactNode
  title: string
  description?: string
  action?: ReactNode
}

export function EmptyState({ icon, title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-4">
      {icon && <div className="w-16 h-16 rounded-full bg-[var(--color-neutral-100)] flex items-center justify-center mb-4 text-[var(--color-neutral-400)]">{icon}</div>}
      <h3 className="text-lg font-semibold text-[var(--color-text)] mb-1">{title}</h3>
      {description && <p className="text-sm text-[var(--color-text-secondary)] text-center max-w-md mb-4">{description}</p>}
      {action}
    </div>
  )
}

interface PageHeaderProps {
  title: string
  subtitle?: string
  action?: ReactNode
}

export function PageHeader({ title, subtitle, action }: PageHeaderProps) {
  return (
    <div className="flex items-center justify-between mb-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold text-[var(--color-text)]">{title}</h1>
        {subtitle && <p className="text-sm text-[var(--color-text-secondary)] mt-1">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}

// ============================================
// SKELETON COMPONENTS
// ============================================
export function Skeleton({ className }: { className?: string }) {
  return <div className={cn('animate-pulse bg-[var(--color-neutral-100)] rounded', className)} />
}

export function SkeletonCard() {
  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-4">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-10 w-10 rounded-lg" />
      </div>
      <Skeleton className="h-8 w-32 mb-2" />
      <Skeleton className="h-3 w-20" />
    </div>
  )
}

export function SkeletonTable({ rows = 5, cols = 5 }: { rows?: number; cols?: number }) {
  return (
    <div className="space-y-3">
      <div className="flex gap-4">
        {Array.from({ length: cols }).map((_, i) => (
          <Skeleton key={i} className="h-4 flex-1" />
        ))}
      </div>
      {Array.from({ length: rows }).map((_, r) => (
        <div key={r} className="flex gap-4">
          {Array.from({ length: cols }).map((_, c) => (
            <Skeleton key={c} className="h-8 flex-1" />
          ))}
        </div>
      ))}
    </div>
  )
}

// ============================================
// ANIMATED COUNTER
// ============================================
interface AnimatedCounterProps {
  value: number
  format?: (n: number) => string
  duration?: number
}

export function AnimatedCounter({ value, format, duration = 800 }: AnimatedCounterProps) {
  const [display, setDisplay] = useState(0)

  useEffect(() => {
    let start = 0
    const startTime = performance.now()
    const step = (now: number) => {
      const progress = Math.min((now - startTime) / duration, 1)
      const eased = 1 - Math.pow(1 - progress, 3)
      setDisplay(start + (value - start) * eased)
      if (progress < 1) requestAnimationFrame(step)
    }
    requestAnimationFrame(step)
  }, [value, duration])

  return <span>{format ? format(display) : Math.round(display).toString()}</span>
}

// ============================================
// BREADCRUMB
// ============================================
interface BreadcrumbProps {
  items: { label: string; path?: string }[]
}

export function Breadcrumb({ items }: BreadcrumbProps) {
  return (
    <nav className="flex items-center gap-1.5 text-xs text-[var(--color-text-secondary)] mb-4">
      {items.map((item, i) => (
        <span key={i} className="flex items-center gap-1.5">
          {i > 0 && <span className="opacity-50">/</span>}
          {item.path ? (
            <Link to={item.path} className="hover:text-[var(--color-primary)] transition-colors">{item.label}</Link>
          ) : (
            <span className="text-[var(--color-text)] font-medium">{item.label}</span>
          )}
        </span>
      ))}
    </nav>
  )
}

// ============================================
// AUTO BREADCRUMB (derived from route)
// ============================================
const routeLabels: Record<string, string> = {
  '': 'Tableau de bord',
  'dashboard': 'Tableaux de bord',
  'workspace': 'Mon espace',
  'sales': 'Ventes',
  'customers': 'Clients',
  'invoices': 'Factures',
  'quotes': 'Devis',
  'credits': 'Avoirs',
  'recurring': 'Factures récurrentes',
  'orders': 'Commandes',
  'delivery-notes': 'Bons de livraison',
  'payments': 'Règlements',
  'purchases': 'Achats',
  'suppliers': 'Fournisseurs',
  'products': 'Produits & Services',
  'automation': 'Automatisation',
  'goods-receipts': 'Réceptions',
  'accounting': 'Comptabilité',
  'home': 'Accueil',
  'chart-accounts': 'Plan comptable',
  'third-party': 'Plan tiers',
  'payment-generation': 'Génération des règlements',
  'journals': 'Journaux',
  'entry-templates': 'Modèles de saisie',
  'journal-entries': 'Saisie des journaux',
  'general-ledger': 'Grand livre',
  'trial-balance': 'Balance générale',
  'brouillard': 'Brouillard',
  'aged-balance': 'Balance âgée',
  'echeancier': 'Échéancier',
  'sig': 'SIG',
  'analytic-balance': 'Balance analytique',
  'fec': 'Export FEC',
  'lettrage': 'Lettrage',
  'search': 'Recherche',
  'journal-closure': 'Clôture des journaux',
  'fiscal-year-closure': 'Clôture d\'exercice',
  'fixed-assets': 'Immobilisations',
  'projects': 'Projets',
  'budgets': 'Budgets',
  'analytic': 'Sections analytiques',
  'structure': 'Structure',
  'traitement': 'Traitement',
  'etats': 'États',
  'states': 'États',
  'banking': 'Banque',
  'banking/accounts': 'Comptes bancaires',
  'banking/transactions': 'Transactions',
  'banking/reconciliation': 'Rapprochement',
  'banking/rules': 'Règles bancaires',
  'treasury': 'Trésorerie',
  'forecast': 'Prévisions',
  'payment-orders': 'Ordres de paiement',
  'collections': 'Recouvrement',
  'stock': 'Stock',
  'quantities': 'Quantités',
  'movements': 'Mouvements',
  'warehouses': 'Dépôts',
  'inventory': 'Inventaire',
  'reorder': 'Réapprovisionnement',
  'price-lists': 'Listes de prix',
  'transfer': 'Transfert comptable',
  'boms': 'Nomenclatures',
  'manufacturing': 'Ordres de fabrication',
  'hr': 'Ressources humaines',
  'employees': 'Employés',
  'pay-runs': 'Campagnes de paie',
  'pay-slips': 'Bulletins de paie',
  'payroll-accounting': 'OD de paie',
  'timesheets': 'Feuilles de temps',
  'leave-requests': 'Congés',
  'contracts': 'Contrats',
  'declarations': 'Déclarations',
  'training': 'Formations',
  'reporting': 'Reporting',
  'financial': 'Tableau de bord financier',
  'bi': 'BI Reporting',
  'budget': 'Suivi budgétaire',
  'reports': 'Rapports',
  'profit-loss': 'Compte de résultat',
  'balance-sheet': 'Bilan',
  'cash-flow': 'Flux de trésorerie',
  'vat': 'TVA',
  'settings': 'Paramètres',
  'company': 'Entreprise',
  'users': 'Utilisateurs',
  'currencies': 'Devises',
  'integrations': 'Intégrations',
  'system': 'Système',
  'audit-log': 'Journal d\'audit',
  'fiscal-years': 'Exercices & périodes',
}

export function useAutoBreadcrumb(): { label: string; path?: string }[] {
  const location = useLocation()
  return useMemo(() => {
    const segments = location.pathname.split('/').filter(Boolean)
    const items: { label: string; path?: string }[] = [{ label: 'Accueil', path: '/' }]
    let currentPath = ''
    for (const seg of segments) {
      currentPath += '/' + seg
      const label = routeLabels[seg] || routeLabels[currentPath.slice(1)] || seg.charAt(0).toUpperCase() + seg.slice(1)
      items.push({ label, path: currentPath })
    }
    if (items.length > 1) {
      items[items.length - 1].path = undefined
    }
    return items
  }, [location.pathname])
}

export function AutoBreadcrumb() {
  const items = useAutoBreadcrumb()
  return <Breadcrumb items={items} />
}

// ============================================
// CONFIRM DIALOG
// ============================================
interface ConfirmDialogProps {
  open: boolean
  title: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  variant?: 'danger' | 'primary'
  onConfirm: () => void
  onCancel: () => void
}

export function ConfirmDialog({
  open, title, message, confirmLabel = 'Confirmer', cancelLabel = 'Annuler', variant = 'danger', onConfirm, onCancel,
}: ConfirmDialogProps) {
  if (!open) return null
  return (
    <div className="fixed inset-0 bg-black/40 z-[9995] flex items-center justify-center p-4">
      <div className="card shadow-2xl max-w-md w-full animate-scale-in">
        <div className="px-6 py-4 border-b border-[var(--color-border)] flex items-center justify-between">
          <h3 className="text-base font-semibold text-[var(--color-text)]">{title}</h3>
          <button onClick={onCancel} className="text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="px-6 py-4">
          <p className="text-sm text-[var(--color-text-secondary)]">{message}</p>
        </div>
        <div className="flex items-center justify-end gap-2 px-6 py-4 border-t border-[var(--color-border)]">
          <Button variant="secondary" size="sm" onClick={onCancel}>{cancelLabel}</Button>
          <Button variant={variant} size="sm" onClick={onConfirm}>{confirmLabel}</Button>
        </div>
      </div>
    </div>
  )
}

// ============================================
// COMBOBOX (searchable select)
// ============================================
interface ComboboxProps {
  label?: string
  value?: string
  onChange?: (value: string) => void
  options: { value: string; label: string }[]
  placeholder?: string
  required?: boolean
  className?: string
}

export function Combobox({ label, value, onChange, options, placeholder = 'Rechercher...', required, className }: ComboboxProps) {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const selected = options.find((o) => o.value === value)
  const filtered = useMemo(() => {
    if (!query) return options
    const q = query.toLowerCase()
    return options.filter((o) => o.label.toLowerCase().includes(q) || o.value.toLowerCase().includes(q))
  }, [options, query])

  return (
    <div className={className} ref={ref}>
      {label && (
        <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1.5">
          {label} {required && <span className="text-[var(--color-danger)]">*</span>}
        </label>
      )}
      <div className="relative">
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="input w-full text-left flex items-center justify-between"
        >
          <span className={cn(!selected && 'text-[var(--color-text-secondary)]')}>{selected?.label || placeholder}</span>
          <ChevronDown className="w-4 h-4 text-[var(--color-text-secondary)] flex-shrink-0" />
        </button>
        {open && (
          <div className="absolute top-full left-0 right-0 mt-1 bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg shadow-xl z-50 max-h-[260px] overflow-hidden flex flex-col">
            <div className="p-2 border-b border-[var(--color-border)]">
              <div className="relative">
                <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-[var(--color-text-secondary)]" />
                <input
                  autoFocus
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder={placeholder}
                  className="w-full pl-7 pr-2 py-1.5 text-sm bg-[var(--color-neutral-50)] rounded-md border-none outline-none focus:ring-1 focus:ring-[var(--color-primary)] text-[var(--color-text)]"
                />
              </div>
            </div>
            <div className="overflow-y-auto flex-1">
              {filtered.length === 0 ? (
                <p className="px-3 py-4 text-sm text-[var(--color-text-secondary)] text-center">Aucun résultat</p>
              ) : (
                filtered.map((opt) => (
                  <button
                    key={opt.value}
                    type="button"
                    onClick={() => {
                      onChange?.(opt.value)
                      setOpen(false)
                      setQuery('')
                    }}
                    className={cn(
                      'w-full text-left px-3 py-2 text-sm transition-colors flex items-center justify-between',
                      opt.value === value
                        ? 'bg-[rgba(0,102,204,0.08)] text-[var(--color-primary)] font-medium'
                        : 'text-[var(--color-text)] hover:bg-[var(--color-neutral-50)]',
                    )}
                  >
                    {opt.label}
                    {opt.value === value && <Check className="w-3.5 h-3.5" />}
                  </button>
                ))
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

// ============================================
// CSV EXPORT UTILITY
// ============================================
export function exportToCSV(filename: string, headers: string[], rows: (string | number)[][]) {
  const csvContent = [
    headers.join(';'),
    ...rows.map((r) => r.map((cell) => {
      const s = String(cell).replace(/"/g, '""')
      return s.includes(';') || s.includes('"') || s.includes('\n') ? `"${s}"` : s
    }).join(';')),
  ].join('\n')
  const blob = new Blob(['\uFEFF' + csvContent], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
