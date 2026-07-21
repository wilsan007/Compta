import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { Card, PageHeader, AutoBreadcrumb, EmptyState } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { getCompanySettings, getFiscalYears, getJournalEntries } from '@/lib/queries'
import { formatDate } from '@/lib/utils'
import {
  FileText, BookOpen, Scale, Library, Receipt, BarChart3, FolderOpen, Lock, ArrowRight,
} from 'lucide-react'
import type { CompanySettings, FiscalYear, JournalEntry } from '@/types'

export function AccountantPortalPage() {
  const { t } = useTranslation('features')
  const { user, hasRole } = useAuth()
  const [company, setCompany] = useState<CompanySettings | null>(null)
  const [currentYear, setCurrentYear] = useState<FiscalYear | null>(null)
  const [entries, setEntries] = useState<JournalEntry[]>([])

  const allowed = hasRole('admin', 'accountant')

  useEffect(() => {
    if (!allowed) return
    loadData()
  }, [allowed])

  async function loadData() {
    try {
      const [comp, years, ent] = await Promise.all([
        getCompanySettings().catch(() => null),
        getFiscalYears().catch(() => []),
        getJournalEntries().catch(() => []),
      ])
      setCompany(comp)
      setCurrentYear((years || []).find((y) => y.status === 'open') || (years || [])[0] || null)
      setEntries((ent || []).slice(0, 5))
    } catch (err) {
      console.error('Error loading accountant portal:', err)
    }
  }

  if (!allowed) {
    return (
      <div className="animate-fade-in">
        <AutoBreadcrumb />
        <PageHeader title={t('accountantPortal.title')} subtitle={t('accountantPortal.subtitle')} />
        <EmptyState
          icon={<Lock className="w-8 h-8" />}
          title={t('accountantPortal.noAccess')}
          description={t('accountantPortal.noAccessDesc')}
        />
      </div>
    )
  }

  const links = [
    { to: '/accounting/states/fec', icon: FileText, title: t('accountantPortal.fecExport'), desc: t('accountantPortal.fecExportDesc') },
    { to: '/reports/journals', icon: BookOpen, title: t('accountantPortal.journals'), desc: t('accountantPortal.journalsDesc') },
    { to: '/accounting/trial-balance', icon: Scale, title: t('accountantPortal.trialBalance'), desc: t('accountantPortal.trialBalanceDesc') },
    { to: '/accounting/general-ledger', icon: Library, title: t('accountantPortal.generalLedger'), desc: t('accountantPortal.generalLedgerDesc') },
    { to: '/reports/vat', icon: Receipt, title: t('accountantPortal.vatReturns'), desc: t('accountantPortal.vatReturnsDesc') },
    { to: '/reports/balance-sheet', icon: BarChart3, title: t('accountantPortal.reports'), desc: t('accountantPortal.reportsDesc') },
    { to: '/settings/data-export', icon: FolderOpen, title: t('accountantPortal.documents'), desc: t('accountantPortal.documentsDesc') },
  ]

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader title={t('accountantPortal.title')} subtitle={t('accountantPortal.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 grid md:grid-cols-3 gap-4">
          <div>
            <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('accountantPortal.companyInfo')}</p>
            <p className="font-semibold">{company?.legal_name || company?.name || user?.tenantName || '—'}</p>
            {company?.siret && <p className="text-sm text-[var(--color-text-secondary)]">SIRET: {company.siret}</p>}
            {company?.vat_number && <p className="text-sm text-[var(--color-text-secondary)]">TVA: {company.vat_number}</p>}
          </div>
          <div>
            <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('accountantPortal.period')}</p>
            <p className="font-semibold">{currentYear?.code || '—'}</p>
            {currentYear && (
              <p className="text-sm text-[var(--color-text-secondary)]">
                {formatDate(currentYear.start_date)} → {formatDate(currentYear.end_date)}
              </p>
            )}
          </div>
          <div>
            <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('accountantPortal.grantedTo')}</p>
            <p className="font-semibold">{user?.name}</p>
            <p className="text-sm text-[var(--color-text-secondary)]">{user?.email}</p>
          </div>
        </div>
      </Card>

      <p className="text-sm text-[var(--color-text-secondary)] mb-3">{t('accountantPortal.intro')}</p>

      <h2 className="text-sm font-semibold mb-3">{t('accountantPortal.quickAccess')}</h2>
      <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
        {links.map((l) => {
          const Icon = l.icon
          return (
            <Link key={l.to} to={l.to} className="card p-4 hover:border-[var(--color-primary)] transition-colors group">
              <div className="flex items-start gap-3">
                <div className="w-10 h-10 rounded-lg bg-[var(--color-primary)]/10 flex items-center justify-center flex-shrink-0">
                  <Icon className="w-5 h-5 text-[var(--color-primary)]" />
                </div>
                <div className="flex-1">
                  <div className="flex items-center justify-between">
                    <h3 className="font-semibold">{l.title}</h3>
                    <ArrowRight className="w-4 h-4 text-[var(--color-text-secondary)] group-hover:translate-x-1 transition-transform" />
                  </div>
                  <p className="text-sm text-[var(--color-text-secondary)] mt-0.5">{l.desc}</p>
                </div>
              </div>
            </Link>
          )
        })}
      </div>

      {entries.length > 0 && (
        <Card>
          <div className="p-4">
            <h3 className="text-sm font-semibold mb-3">{t('accountantPortal.lastEntries')}</h3>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <tbody>
                  {entries.map((e) => (
                    <tr key={e.id} className="border-b border-[var(--color-border)] last:border-0">
                      <td className="p-2 font-mono">{e.number}</td>
                      <td className="p-2">{formatDate(e.date)}</td>
                      <td className="p-2">{e.description}</td>
                      <td className="p-2 text-right font-mono">{Number(e.total_debit).toFixed(2)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </Card>
      )}
    </div>
  )
}
