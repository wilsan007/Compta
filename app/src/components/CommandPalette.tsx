import { useState, useEffect, useRef, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Search, ArrowRight, Plus, Sparkles } from 'lucide-react'
import { cn } from '@/lib/utils'
import { getEnabledNavGroups } from './Sidebar'

interface Command {
  id: string
  label: string
  description?: string
  icon: React.ComponentType<{ className?: string }>
  path?: string
  action?: () => void
  category: string
  keywords?: string
}

export function CommandPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const navigate = useNavigate()
  const { t } = useTranslation('nav')
  const [query, setQuery] = useState('')
  const [selectedIndex, setSelectedIndex] = useState(0)
  const inputRef = useRef<HTMLInputElement>(null)

  const commands: Command[] = useMemo(() => {
    const cmds: Command[] = []
    // Auto-generate from navGroups
    for (const group of getEnabledNavGroups()) {
      for (const item of group.items) {
        const label = t(item.labelKey)
        cmds.push({
          id: item.path,
          label,
          icon: item.icon,
          path: item.path,
          category: t(group.groupKey),
          keywords: label.toLowerCase(),
        })
        for (const sub of item.subItems) {
          if (sub.path === item.path) continue // skip duplicates of parent
          const subLabel = t(sub.labelKey)
          cmds.push({
            id: sub.path,
            label: subLabel,
            icon: item.icon,
            path: sub.path,
            category: t(group.groupKey),
            keywords: subLabel.toLowerCase(),
          })
        }
      }
    }
    // Add quick actions
    const quickActions: Command[] = [
      { id: 'new-invoice', label: t('commandPalette.newInvoice'), icon: Plus, path: '/sales/invoices', category: t('commandPalette.quickActions'), keywords: 'créer facture new invoice' },
      { id: 'new-customer', label: t('commandPalette.newCustomer'), icon: Plus, path: '/sales/customers', category: t('commandPalette.quickActions'), keywords: 'créer client new customer' },
      { id: 'new-quote', label: t('commandPalette.newQuote'), icon: Plus, path: '/sales/quotes', category: t('commandPalette.quickActions'), keywords: 'créer devis new quote' },
      { id: 'new-product', label: t('commandPalette.newProduct'), icon: Plus, path: '/purchases/products', category: t('commandPalette.quickActions'), keywords: 'créer produit new product' },
      { id: 'new-employee', label: t('commandPalette.newEmployee'), icon: Plus, path: '/hr/employees', category: t('commandPalette.quickActions'), keywords: 'créer employé new employee' },
      { id: 'new-supplier', label: t('commandPalette.newSupplier'), icon: Plus, path: '/purchases/suppliers', category: t('commandPalette.quickActions'), keywords: 'créer fournisseur new supplier' },
      { id: 'ai-assistant', label: t('layout.aiAssistant'), icon: Sparkles, category: t('commandPalette.quickActions'), keywords: 'ai copilot assistant', action: () => {} },
    ]
    return [...cmds, ...quickActions]
  }, [t])

  const filtered = useMemo(() => {
    if (!query) return commands
    const q = query.toLowerCase()
    return commands.filter((c) =>
      c.label.toLowerCase().includes(q) ||
      c.category.toLowerCase().includes(q) ||
      c.keywords?.toLowerCase().includes(q)
    )
  }, [query, commands])

  useEffect(() => {
    if (open) {
      setQuery('')
      setSelectedIndex(0)
      setTimeout(() => inputRef.current?.focus(), 50)
    }
  }, [open])

  useEffect(() => {
    setSelectedIndex(0)
  }, [query])

  function handleSelect(cmd: Command) {
    if (cmd.action) cmd.action()
    if (cmd.path) navigate(cmd.path)
    onClose()
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setSelectedIndex((i) => Math.min(i + 1, filtered.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setSelectedIndex((i) => Math.max(i - 1, 0))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      if (filtered[selectedIndex]) handleSelect(filtered[selectedIndex])
    } else if (e.key === 'Escape') {
      onClose()
    }
  }

  if (!open) return null

  const categories = [...new Set(filtered.map((c) => c.category))]

  return (
    <>
      <div className="fixed inset-0 bg-black/40 z-[9998]" onClick={onClose} />
      <div className="fixed top-[15%] left-1/2 -translate-x-1/2 w-[90%] max-w-2xl z-[9999]">
        <div className="card shadow-2xl overflow-hidden">
          {/* Search input */}
          <div className="flex items-center gap-3 px-4 py-3 border-b border-[var(--color-border)]">
            <Search className="w-5 h-5 text-[var(--color-text-secondary)]" />
            <input
              ref={inputRef}
              className="flex-1 bg-transparent border-none outline-none text-base text-[var(--color-text)] placeholder:text-[var(--color-text-secondary)]"
              placeholder={t('commandPalette.searchPlaceholder')}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={handleKeyDown}
            />
            <kbd className="text-xs text-[var(--color-text-secondary)] bg-[var(--color-neutral-100)] px-2 py-1 rounded">ESC</kbd>
          </div>

          {/* Results */}
          <div className="max-h-[400px] overflow-y-auto p-2">
            {filtered.length === 0 ? (
              <div className="py-8 text-center text-[var(--color-text-secondary)] text-sm">
                {t('commandPalette.noResults', { query })}
              </div>
            ) : (
              categories.map((cat) => (
                <div key={cat} className="mb-2">
                  <p className="text-xs font-semibold text-[var(--color-text-secondary)] uppercase tracking-wider px-3 py-1.5">{cat}</p>
                  {filtered.filter((c) => c.category === cat).map((cmd) => {
                    const globalIndex = filtered.indexOf(cmd)
                    return (
                      <button
                        key={cmd.id}
                        onClick={() => handleSelect(cmd)}
                        onMouseEnter={() => setSelectedIndex(globalIndex)}
                        className={cn(
                          'w-full flex items-center gap-3 px-3 py-2.5 rounded-md text-left transition-colors',
                          selectedIndex === globalIndex
                            ? 'bg-[var(--color-primary)] text-white'
                            : 'hover:bg-[var(--color-neutral-50)] text-[var(--color-text)]'
                        )}
                      >
                        <cmd.icon className={cn('w-4 h-4 flex-shrink-0', selectedIndex === globalIndex ? 'text-white' : 'text-[var(--color-text-secondary)]')} />
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium">{cmd.label}</p>
                          {cmd.description && <p className="text-xs opacity-70">{cmd.description}</p>}
                        </div>
                        <ArrowRight className={cn('w-3 h-3', selectedIndex === globalIndex ? 'text-white' : 'text-[var(--color-text-secondary)]')} />
                      </button>
                    )
                  })}
                </div>
              ))
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between px-4 py-2 border-t border-[var(--color-border)] text-xs text-[var(--color-text-secondary)]">
            <div className="flex items-center gap-3">
              <span className="flex items-center gap-1"><kbd className="bg-[var(--color-neutral-100)] px-1.5 py-0.5 rounded">↑↓</kbd> {t('commandPalette.navigate')}</span>
              <span className="flex items-center gap-1"><kbd className="bg-[var(--color-neutral-100)] px-1.5 py-0.5 rounded">↵</kbd> {t('commandPalette.select')}</span>
            </div>
            <span>Compta v0.2</span>
          </div>
        </div>
      </div>
    </>
  )
}
