import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Breadcrumb } from '@/components/ui'
import {
  Plus, Search, BookOpen as JournalIcon, FileSearch, Users2, IdCard, Wallet,
  Database, Settings2, PieChart,
} from 'lucide-react'

interface Tile {
  label: string
  icon: React.ReactNode
  path: string
}

function TileButton({ tile, onClick }: { tile: Tile; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="flex flex-col items-center justify-center gap-2 w-28 h-28 rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] hover:border-[var(--color-primary)] hover:shadow-md transition-all p-3 text-center"
    >
      <div className="w-10 h-10 rounded-lg flex items-center justify-center bg-[rgba(0,102,204,0.1)] text-[var(--color-primary)]">
        {tile.icon}
      </div>
      <span className="text-xs font-medium text-[var(--color-text)] leading-tight">{tile.label}</span>
    </button>
  )
}

export function AccountingHomePage() {
  const navigate = useNavigate()
  const { t } = useTranslation('accounting')

  const sections: { title: string; tiles: Tile[] }[] = [
    {
      title: t('home.dailyManagement'),
      tiles: [
        { label: t('home.addPiece'), icon: <Plus className="w-5 h-5" />, path: '/accounting/journal-entries' },
        { label: t('home.viewEditPiece'), icon: <FileSearch className="w-5 h-5" />, path: '/accounting/journal-entries' },
        { label: t('home.entryJournals'), icon: <JournalIcon className="w-5 h-5" />, path: '/accounting/traitement' },
        { label: t('home.searchEntries'), icon: <Search className="w-5 h-5" />, path: '/accounting/treatment/search' },
      ],
    },
    {
      title: t('home.thirdPartyManagement'),
      tiles: [
        { label: t('home.thirdPartyPlan'), icon: <IdCard className="w-5 h-5" />, path: '/accounting/third-party' },
        { label: t('home.thirdPartyAccounts'), icon: <Users2 className="w-5 h-5" />, path: '/accounting/third-party' },
        { label: t('home.paymentGeneration'), icon: <Wallet className="w-5 h-5" />, path: '/accounting/payment-generation' },
      ],
    },
    {
      title: t('home.generalAccountsManagement'),
      tiles: [
        { label: t('home.chartOfAccounts'), icon: <Database className="w-5 h-5" />, path: '/accounting/chart-accounts' },
        { label: t('home.generalAccounts'), icon: <Settings2 className="w-5 h-5" />, path: '/accounting/chart-accounts' },
        { label: t('home.accountsBalance'), icon: <PieChart className="w-5 h-5" />, path: '/accounting/trial-balance' },
      ],
    },
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.title') }]} />
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-[var(--color-text)]">{t('home.pageTitle')}</h1>
        <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('home.pageSubtitle')}</p>
      </div>

      <div className="space-y-10">
        {sections.map((section) => (
          <div key={section.title}>
            <h2 className="text-sm font-semibold text-[var(--color-text-secondary)] uppercase tracking-wide mb-4">{section.title}</h2>
            <div className="flex flex-wrap gap-4">
              {section.tiles.map((tile) => (
                <TileButton key={tile.label} tile={tile} onClick={() => navigate(tile.path)} />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
