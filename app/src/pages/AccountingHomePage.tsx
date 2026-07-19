import { useNavigate } from 'react-router-dom'
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

  const sections: { title: string; tiles: Tile[] }[] = [
    {
      title: 'Gestion quotidienne',
      tiles: [
        { label: "Ajout d'une pièce", icon: <Plus className="w-5 h-5" />, path: '/accounting/journal-entries' },
        { label: "Visualisation / modification d'une pièce", icon: <FileSearch className="w-5 h-5" />, path: '/accounting/journal-entries' },
        { label: 'Journaux de saisie', icon: <JournalIcon className="w-5 h-5" />, path: '/accounting/traitement' },
        { label: "Recherche d'écritures", icon: <Search className="w-5 h-5" />, path: '/accounting/treatment/search' },
      ],
    },
    {
      title: 'Gestion des tiers',
      tiles: [
        { label: 'Plan tiers', icon: <IdCard className="w-5 h-5" />, path: '/accounting/third-party' },
        { label: 'Gestion des comptes tiers', icon: <Users2 className="w-5 h-5" />, path: '/accounting/third-party' },
        { label: 'Génération des règlements', icon: <Wallet className="w-5 h-5" />, path: '/accounting/payment-generation' },
      ],
    },
    {
      title: 'Gestion des comptes généraux',
      tiles: [
        { label: 'Plan comptable', icon: <Database className="w-5 h-5" />, path: '/accounting/chart-accounts' },
        { label: 'Gestion des comptes généraux', icon: <Settings2 className="w-5 h-5" />, path: '/accounting/chart-accounts' },
        { label: 'Balance des comptes', icon: <PieChart className="w-5 h-5" />, path: '/accounting/trial-balance' },
      ],
    },
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Accueil' }]} />
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-[var(--color-text)]">Comptabilité — Accueil</h1>
        <p className="text-sm text-[var(--color-text-secondary)] mt-1">Accès rapide aux opérations courantes, comme sur le poste de travail Sage 100</p>
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
