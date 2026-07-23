import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Breadcrumb } from '@/components/ui'
import {
  Plus, Search, BookOpen, IdCard, Wallet,
  Database, PieChart, RefreshCw, Bell, Landmark,
  FileText, FileSpreadsheet, Calculator, Lock,
  type LucideIcon,
} from 'lucide-react'

type SectionTheme = {
  gradient: string
  glow: string
  iconBg: string
  iconColor: string
  border: string
  hoverBorder: string
}

interface Tile {
  label: string
  icon: LucideIcon
  path: string
}

interface Section {
  titleKey: string
  theme: SectionTheme
  tiles: Tile[]
}

const sectionThemes: Record<string, SectionTheme> = {
  blue: {
    gradient: 'from-blue-500/10 via-blue-500/5 to-transparent',
    glow: 'group-hover:shadow-[0_0_24px_-4px_rgba(59,130,246,0.4)]',
    iconBg: 'bg-gradient-to-br from-blue-500/20 to-blue-600/10',
    iconColor: 'text-blue-500',
    border: 'border-blue-500/15',
    hoverBorder: 'group-hover:border-blue-500/50',
  },
  emerald: {
    gradient: 'from-emerald-500/10 via-emerald-500/5 to-transparent',
    glow: 'group-hover:shadow-[0_0_24px_-4px_rgba(16,185,129,0.4)]',
    iconBg: 'bg-gradient-to-br from-emerald-500/20 to-emerald-600/10',
    iconColor: 'text-emerald-500',
    border: 'border-emerald-500/15',
    hoverBorder: 'group-hover:border-emerald-500/50',
  },
  violet: {
    gradient: 'from-violet-500/10 via-violet-500/5 to-transparent',
    glow: 'group-hover:shadow-[0_0_24px_-4px_rgba(139,92,246,0.4)]',
    iconBg: 'bg-gradient-to-br from-violet-500/20 to-violet-600/10',
    iconColor: 'text-violet-500',
    border: 'border-violet-500/15',
    hoverBorder: 'group-hover:border-violet-500/50',
  },
  amber: {
    gradient: 'from-amber-500/10 via-amber-500/5 to-transparent',
    glow: 'group-hover:shadow-[0_0_24px_-4px_rgba(245,158,11,0.4)]',
    iconBg: 'bg-gradient-to-br from-amber-500/20 to-amber-600/10',
    iconColor: 'text-amber-500',
    border: 'border-amber-500/15',
    hoverBorder: 'group-hover:border-amber-500/50',
  },
}

function TileButton({ tile, theme, index, onClick }: { tile: Tile; theme: SectionTheme; index: number; onClick: () => void }) {
  const Icon = tile.icon
  return (
    <button
      onClick={onClick}
      className={`group relative flex flex-col items-center justify-center gap-3 w-[140px] h-[140px] rounded-2xl border ${theme.border} ${theme.hoverBorder} bg-gradient-to-br ${theme.gradient} backdrop-blur-sm transition-all duration-300 hover:-translate-y-1 hover:scale-[1.03] ${theme.glow} p-4 text-center overflow-hidden`}
      style={{ animationDelay: `${index * 60}ms` }}
    >
      <div className={`absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500 bg-gradient-to-br ${theme.gradient}`} />
      <div className={`relative w-12 h-12 rounded-xl flex items-center justify-center ${theme.iconBg} ${theme.iconColor} transition-transform duration-300 group-hover:scale-110 group-hover:rotate-3`}>
        <Icon className="w-6 h-6" strokeWidth={1.8} />
      </div>
      <span className="relative text-xs font-semibold text-[var(--color-text)] leading-tight line-clamp-2">{tile.label}</span>
      <div className={`absolute bottom-0 left-0 right-0 h-0.5 bg-gradient-to-r ${theme.gradient} opacity-0 group-hover:opacity-100 transition-opacity duration-300`} style={{ background: 'currentColor' }} />
    </button>
  )
}

function SectionCard({ section, onNavigate }: { section: Section; onNavigate: (path: string) => void }) {
  const theme = section.theme
  return (
    <div className={`relative rounded-3xl border ${theme.border} bg-gradient-to-br ${theme.gradient} backdrop-blur-sm p-6 overflow-hidden`}>
      <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-current to-transparent opacity-20" style={{ color: theme.iconColor.includes('blue') ? '#3b82f6' : theme.iconColor.includes('emerald') ? '#10b981' : theme.iconColor.includes('violet') ? '#8b5cf6' : '#f59e0b' }} />
      <div className="flex items-center gap-3 mb-5">
        <div className={`w-1 h-6 rounded-full ${theme.iconColor}`} style={{ background: 'currentColor' }} />
        <h2 className="text-sm font-bold text-[var(--color-text)] uppercase tracking-wider">{section.titleKey}</h2>
        <span className="text-[10px] font-medium text-[var(--color-text-secondary)] bg-[var(--color-neutral-100)] dark:bg-white/5 px-2 py-0.5 rounded-full">
          {section.tiles.length}
        </span>
      </div>
      <div className="flex flex-wrap gap-4">
        {section.tiles.map((tile, idx) => (
          <TileButton key={tile.path + idx} tile={tile} theme={theme} index={idx} onClick={() => onNavigate(tile.path)} />
        ))}
      </div>
    </div>
  )
}

export function AccountingHomePage() {
  const navigate = useNavigate()
  const { t } = useTranslation('accounting')

  const sections: Section[] = [
    {
      titleKey: t('home.dailyEntry'),
      theme: sectionThemes.blue,
      tiles: [
        { label: t('home.addPiece'), icon: Plus, path: '/accounting/treatment/journal-entry' },
        { label: t('home.searchEntries'), icon: Search, path: '/accounting/treatment/search' },
        { label: t('home.lettrage'), icon: BookOpen, path: '/accounting/treatment/lettrage' },
        { label: t('home.recurringEntries'), icon: RefreshCw, path: '/accounting/treatment/recurring-entries' },
      ],
    },
    {
      titleKey: t('home.thirdPartyPayments'),
      theme: sectionThemes.emerald,
      tiles: [
        { label: t('home.thirdPartyPlan'), icon: IdCard, path: '/accounting/third-party' },
        { label: t('home.paymentGeneration'), icon: Wallet, path: '/accounting/payment-generation' },
        { label: t('home.paymentReminders'), icon: Bell, path: '/accounting/treatment/payment-reminders' },
        { label: t('home.bankReconciliation'), icon: Landmark, path: '/banking/reconciliation' },
      ],
    },
    {
      titleKey: t('home.accountsStructure'),
      theme: sectionThemes.violet,
      tiles: [
        { label: t('home.chartOfAccounts'), icon: Database, path: '/accounting/chart-accounts' },
        { label: t('home.accountsBalance'), icon: PieChart, path: '/accounting/trial-balance' },
        { label: t('home.entryTemplates'), icon: FileText, path: '/accounting/entry-templates' },
        { label: t('home.fixedAssets'), icon: FileSpreadsheet, path: '/accounting/fixed-assets' },
      ],
    },
    {
      titleKey: t('home.statesClosures'),
      theme: sectionThemes.amber,
      tiles: [
        { label: t('home.generalLedger'), icon: BookOpen, path: '/accounting/general-ledger' },
        { label: t('home.fecExport'), icon: FileText, path: '/accounting/states/fec' },
        { label: t('home.ediTva'), icon: Calculator, path: '/accounting/treatment/edi-tva' },
        { label: t('home.journalClosure'), icon: Lock, path: '/accounting/treatment/journal-closure' },
      ],
    },
  ]

  return (
    <div className="animate-fade-in">
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.title') }]} />

      <div className="relative mb-8 overflow-hidden rounded-3xl border border-[var(--color-border)] bg-gradient-to-br from-[var(--color-surface)] via-[var(--color-surface)] to-[var(--color-neutral-50)] dark:to-white/5 p-8 backdrop-blur-sm">
        <div className="absolute top-0 right-0 w-64 h-64 bg-gradient-to-br from-blue-500/10 to-violet-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-0 w-48 h-48 bg-gradient-to-tr from-emerald-500/10 to-amber-500/5 rounded-full blur-3xl pointer-events-none" />
        <div className="relative">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-[var(--color-text)] to-[var(--color-text-secondary)] bg-clip-text text-transparent">
            {t('home.pageTitle')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1.5 max-w-xl">{t('home.pageSubtitle')}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        {sections.map((section) => (
          <SectionCard key={section.titleKey} section={section} onNavigate={navigate} />
        ))}
      </div>
    </div>
  )
}
