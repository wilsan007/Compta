import { NavLink, useLocation, Outlet, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard,
  ShoppingCart,
  Package,
  Settings,
  Bell,
  HelpCircle,
  Search,
  Sparkles,
  ChevronDown,
  Moon,
  Sun,
  PanelLeftClose,
  PanelLeft,
  User,
  X,
  Users,
  BarChart3,
  LogOut,
  Database,
  PenTool,
  FileBarChart,
  Wallet,
  Boxes,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { useAuth } from '@/lib/auth'
import { useState, useEffect } from 'react'
import { useTheme } from '@/lib/theme'
import { CommandPalette } from './CommandPalette'
import { AIAssistant } from './AIAssistant'
import { OnboardingModal } from './OnboardingModal'

export const navGroups = [
  {
    label: 'Accueil',
    items: [
      {
        label: 'Tableau de bord',
        icon: LayoutDashboard,
        path: '/',
        subItems: [
          { label: 'Vue d\'ensemble', path: '/' },
          { label: 'Mon espace', path: '/dashboard/workspace' },
        ],
      },
    ],
  },
  {
    label: 'Comptabilité',
    items: [
      {
        label: 'Accueil',
        icon: LayoutDashboard,
        path: '/accounting/home',
        subItems: [
          { label: 'Menu comptabilité', path: '/accounting/home' },
          { label: 'Tableau de bord', path: '/accounting' },
        ],
      },
      {
        label: 'Structure',
        icon: Database,
        path: '/accounting/structure',
        subItems: [
          { label: 'Plan comptable général', path: '/accounting/chart-accounts' },
          { label: 'Plan tiers', path: '/accounting/third-party' },
          { label: 'Génération des règlements', path: '/accounting/payment-generation' },
          { label: 'Codes journaux', path: '/accounting/journals' },
          { label: 'Modèles de saisie', path: '/accounting/entry-templates' },
          { label: 'Exercices & périodes', path: '/system/fiscal-years' },
          { label: 'Sections analytiques', path: '/accounting/structure/analytic' },
          { label: 'Budgets', path: '/accounting/structure/budgets' },
          { label: 'Engagements budgétaires', path: '/accounting/structure/budget-commitments' },
          { label: 'Banques & établissements', path: '/banking/accounts' },
          { label: 'Projets', path: '/accounting/projects' },
          { label: 'Immobilisations', path: '/accounting/fixed-assets' },
        ],
      },
      {
        label: 'Traitement',
        icon: PenTool,
        path: '/accounting/traitement',
        subItems: [
          { label: 'Saisie des journaux', path: '/accounting/treatment/journal-entry' },
          { label: 'Lettrage', path: '/accounting/treatment/lettrage' },
          { label: 'Recherche d\'écritures', path: '/accounting/treatment/search' },
          { label: 'Clôture des journaux', path: '/accounting/treatment/journal-closure' },
          { label: 'Clôture d\'exercice', path: '/accounting/treatment/fiscal-year-closure' },
          { label: 'Rapprochement bancaire', path: '/banking/reconciliation' },
          { label: 'Transactions bancaires', path: '/banking/transactions' },
          { label: 'Règles bancaires', path: '/banking/rules' },
        ],
      },
      {
        label: 'États',
        icon: FileBarChart,
        path: '/accounting/etats',
        subItems: [
          { label: 'Grand livre', path: '/accounting/general-ledger' },
          { label: 'Grand livre tiers', path: '/accounting/states/general-ledger-tiers' },
          { label: 'Balance générale', path: '/accounting/trial-balance' },
          { label: 'Brouillard', path: '/accounting/states/brouillard' },
          { label: 'Balance âgée tiers', path: '/accounting/states/aged-balance' },
          { label: 'Échéancier', path: '/accounting/states/echeancier' },
          { label: 'SIG', path: '/accounting/states/sig' },
          { label: 'Balance analytique', path: '/accounting/states/analytic-balance' },
          { label: 'Export FEC', path: '/accounting/states/fec' },
          { label: 'Compte de résultat', path: '/reports/profit-loss' },
          { label: 'Bilan', path: '/reports/balance-sheet' },
          { label: 'Flux de trésorerie', path: '/reports/cash-flow' },
          { label: 'TVA', path: '/reports/vat' },
          { label: 'Journaux', path: '/reports/journals' },
        ],
      },
    ],
  },
  {
    label: 'Commercial',
    items: [
      {
        label: 'Ventes',
        icon: ShoppingCart,
        path: '/sales',
        subItems: [
          { label: 'Clients', path: '/sales/customers' },
          { label: 'Factures', path: '/sales/invoices' },
          { label: 'Devis', path: '/sales/quotes' },
          { label: 'Avoirs', path: '/sales/credits' },
          { label: 'Factures récurrentes', path: '/sales/recurring' },
          { label: 'Commandes', path: '/sales/orders' },
          { label: 'Bons de livraison', path: '/sales/delivery-notes' },
          { label: 'Règlements clients', path: '/sales/payments' },
        ],
      },
      {
        label: 'Achats',
        icon: Package,
        path: '/purchases',
        subItems: [
          { label: 'Fournisseurs', path: '/purchases/suppliers' },
          { label: 'Factures d\'achat', path: '/purchases/invoices' },
          { label: 'Avoirs fournisseurs', path: '/purchases/credits' },
          { label: 'Produits & Services', path: '/purchases/products' },
          { label: 'Automatisation factures', path: '/purchases/automation' },
          { label: 'Commandes fournisseurs', path: '/purchases/orders' },
          { label: 'Réceptions marchandises', path: '/purchases/goods-receipts' },
          { label: 'Règlements fournisseurs', path: '/purchases/payments' },
        ],
      },
    ],
  },
  {
    label: 'Trésorerie',
    items: [
      {
        label: 'Financement',
        icon: Wallet,
        path: '/treasury',
        subItems: [
          { label: 'Tableau de bord', path: '/treasury/dashboard' },
          { label: 'Prévisions', path: '/treasury/forecast' },
          { label: 'Ordres de paiement', path: '/treasury/payment-orders' },
          { label: 'Recouvrement', path: '/treasury/collections' },
        ],
      },
    ],
  },
  {
    label: 'Stock',
    items: [
      {
        label: 'Gestion stock',
        icon: Boxes,
        path: '/stock',
        subItems: [
          { label: 'Quantités en stock', path: '/stock/quantities' },
          { label: 'Mouvements', path: '/stock/movements' },
          { label: 'Dépôts', path: '/stock/warehouses' },
          { label: 'Inventaire', path: '/stock/inventory' },
          { label: 'Réapprovisionnement', path: '/stock/reorder' },
          { label: 'Listes de prix', path: '/stock/price-lists' },
          { label: 'Transfert comptable', path: '/stock/transfer' },
          { label: 'Nomenclatures (BOM)', path: '/stock/boms' },
          { label: 'Ordres de fabrication', path: '/stock/manufacturing' },
        ],
      },
    ],
  },
  {
    label: 'RH & Paie',
    items: [
      {
        label: 'Ressources humaines',
        icon: Users,
        path: '/hr',
        subItems: [
          { label: 'Employés', path: '/hr/employees' },
          { label: 'Campagnes de paie', path: '/hr/pay-runs' },
          { label: 'Bulletins de paie', path: '/hr/pay-slips' },
          { label: 'OD de paie', path: '/hr/payroll-accounting' },
          { label: 'Feuilles de temps', path: '/hr/timesheets' },
          { label: 'Congés', path: '/hr/leave-requests' },
          { label: 'Contrats', path: '/hr/contracts' },
          { label: 'Déclarations', path: '/hr/declarations' },
          { label: 'Formations', path: '/hr/training' },
        ],
      },
    ],
  },
  {
    label: 'Tableaux de bord',
    items: [
      {
        label: 'Analyse',
        icon: BarChart3,
        path: '/dashboard',
        subItems: [
          { label: 'Ventes', path: '/dashboard/sales' },
          { label: 'Achats', path: '/dashboard/purchases' },
          { label: 'Banque', path: '/dashboard/banking' },
          { label: 'RH & Paie', path: '/dashboard/hr' },
        ],
      },
    ],
  },
  {
    label: 'Reporting & BI',
    items: [
      {
        label: 'Rapports',
        icon: BarChart3,
        path: '/reporting/financial',
        subItems: [
          { label: 'Tableau de bord financier', path: '/reporting/financial' },
          { label: 'BI Reporting', path: '/reporting/bi' },
          { label: 'Suivi budgétaire', path: '/reporting/budget' },
        ],
      },
    ],
  },
  {
    label: 'Système',
    items: [
      {
        label: 'Paramètres',
        icon: Settings,
        path: '/settings',
        subItems: [
          { label: 'Entreprise', path: '/settings/company' },
          { label: 'Utilisateurs', path: '/settings/users' },
          { label: 'Equipe & roles', path: '/settings/team' },
          { label: 'Devises', path: '/settings/currencies' },
          { label: 'Intégrations', path: '/settings/integrations' },
          { label: 'Export des données', path: '/settings/data-export' },
          { label: 'Journal d\'audit', path: '/system/audit-log' },
        ],
      },
    ],
  },
]

export function Layout({ children }: { children?: React.ReactNode }) {
  const location = useLocation()
  const navigate = useNavigate()
  const { theme, toggleTheme } = useTheme()
  const { user, signOut } = useAuth()
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [showProfile, setShowProfile] = useState(false)
  const [showCommand, setShowCommand] = useState(false)
  const [showAI, setShowAI] = useState(false)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [mobileSidebar, setMobileSidebar] = useState(false)

  useEffect(() => {
    const seen = localStorage.getItem('compta-onboarded')
    if (!seen) {
      setShowOnboarding(true)
    }
  }, [])

  function closeOnboarding() {
    setShowOnboarding(false)
    localStorage.setItem('compta-onboarded', 'true')
  }

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault()
        setShowCommand((v) => !v)
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  function isActive(path: string): boolean {
    if (path === '/') return location.pathname === '/'
    return location.pathname.startsWith(path)
  }

  return (
    <div className="min-h-screen flex">
      {/* Sidebar */}
      <aside
        className={cn(
          'fixed lg:sticky top-0 left-0 h-screen bg-[var(--color-surface)] border-r border-[var(--color-border)] flex flex-col transition-all duration-300 z-50',
          sidebarCollapsed ? 'w-16' : 'w-60',
          mobileSidebar ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
        )}
      >
        {/* Logo */}
        <div className="flex items-center gap-2 h-14 px-4 border-b border-[var(--color-border)] flex-shrink-0">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center flex-shrink-0">
            <span className="text-white font-bold text-sm">C</span>
          </div>
          {!sidebarCollapsed && (
            <div className="overflow-hidden">
              <p className="font-bold text-[var(--color-text)] text-sm whitespace-nowrap">Compta</p>
              <p className="text-[10px] text-[var(--color-text-secondary)] whitespace-nowrap">v0.2 - Alpha</p>
            </div>
          )}
          <button
            onClick={() => setMobileSidebar(false)}
            className="ml-auto lg:hidden p-1 rounded text-[var(--color-text-secondary)]"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Navigation */}
        <nav className="flex-1 overflow-y-auto py-3 px-2">
          {navGroups.map((group) => (
            <div key={group.label} className="mb-4">
              {!sidebarCollapsed && (
                <p className="text-[10px] font-semibold text-[var(--color-text-secondary)] uppercase tracking-wider px-3 mb-1.5">
                  {group.label}
                </p>
              )}
              {group.items.map((item) => {
                const active = isActive(item.path)
                return (
                  <div key={item.path} className="relative group">
                    <NavLink
                      to={item.path}
                      onClick={() => setMobileSidebar(false)}
                      className={cn(
                        'flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors mb-0.5',
                        active
                          ? 'bg-[rgba(0,102,204,0.08)] text-[var(--color-primary)]'
                          : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-50)]'
                      )}
                      title={sidebarCollapsed ? item.label : undefined}
                    >
                      <item.icon className="w-4 h-4 flex-shrink-0" />
                      {!sidebarCollapsed && <span className="whitespace-nowrap">{item.label}</span>}
                      {!sidebarCollapsed && item.subItems.length > 0 && (
                        <ChevronDown className="w-3 h-3 ml-auto opacity-50" />
                      )}
                    </NavLink>

                    {/* Sub-items dropdown on hover when collapsed */}
                    {sidebarCollapsed && (
                      <div className="absolute left-full top-0 ml-2 hidden group-hover:block z-50">
                        <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg shadow-xl py-2 min-w-[200px]">
                          <p className="px-3 py-1 text-xs font-semibold text-[var(--color-text-secondary)] uppercase">{item.label}</p>
                          {item.subItems.map((sub) => (
                            <NavLink
                              key={sub.path}
                              to={sub.path}
                              onClick={() => setMobileSidebar(false)}
                              className={cn(
                                'block px-3 py-1.5 text-sm transition-colors',
                                location.pathname === sub.path
                                  ? 'text-[var(--color-primary)] bg-[rgba(0,102,204,0.05)] font-medium'
                                  : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-50)]'
                              )}
                            >
                              {sub.label}
                            </NavLink>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Sub-items inline when expanded */}
                    {!sidebarCollapsed && active && (
                      <div className="ml-4 mt-0.5 mb-1 border-l border-[var(--color-border)] pl-2">
                        {item.subItems.map((sub) => (
                          <NavLink
                            key={sub.path}
                            to={sub.path}
                            onClick={() => setMobileSidebar(false)}
                            className={cn(
                              'block px-3 py-1.5 rounded-md text-xs transition-colors',
                              location.pathname === sub.path
                                ? 'text-[var(--color-primary)] font-medium bg-[rgba(0,102,204,0.05)]'
                                : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-neutral-50)]'
                            )}
                          >
                            {sub.label}
                          </NavLink>
                        ))}
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          ))}
        </nav>

        {/* Sidebar footer - collapse toggle */}
        <div className="border-t border-[var(--color-border)] p-2 flex-shrink-0">
          <button
            onClick={() => setSidebarCollapsed(!sidebarCollapsed)}
            className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-50)] transition-colors"
          >
            {sidebarCollapsed ? <PanelLeft className="w-4 h-4 mx-auto" /> : (<><PanelLeftClose className="w-4 h-4" /> Reduire</>)}
          </button>
        </div>
      </aside>

      {/* Mobile overlay */}
      {mobileSidebar && <div className="fixed inset-0 bg-black/30 z-40 lg:hidden" onClick={() => setMobileSidebar(false)} />}

      {/* Main area */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Top bar */}
        <header className="sticky top-0 z-40 bg-[var(--color-surface)] border-b border-[var(--color-border)] h-14 flex items-center px-4 gap-3">
          {/* Mobile menu */}
          <button
            onClick={() => setMobileSidebar(true)}
            className="lg:hidden p-2 rounded-md text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]"
          >
            <PanelLeft className="w-5 h-5" />
          </button>

          {/* Search / Command */}
          <button
            onClick={() => setShowCommand(true)}
            className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)] text-sm hover:bg-[var(--color-neutral-200)] transition-colors w-full max-w-xs"
          >
            <Search className="w-4 h-4" />
            <span className="flex-1 text-left">Rechercher...</span>
            <kbd className="text-[10px] bg-[var(--color-surface)] px-1.5 py-0.5 rounded border border-[var(--color-border)]">Cmd+K</kbd>
          </button>

          {/* Right actions */}
          <div className="flex items-center gap-1.5 ml-auto">
            {/* AI Assistant */}
            <button
              onClick={() => setShowAI(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-gradient-to-r from-[var(--color-primary)] to-purple-600 text-white hover:opacity-90 transition-opacity text-sm font-medium"
            >
              <Sparkles className="w-4 h-4" />
              <span className="hidden sm:block">Assistant IA</span>
            </button>

            {/* Dark mode toggle */}
            <button
              onClick={toggleTheme}
              className="p-2 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
              title="Mode sombre / clair"
            >
              {theme === 'dark' ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
            </button>

            {/* Help */}
            <button
              onClick={() => setShowOnboarding(true)}
              className="p-2 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
              title="Aide"
            >
              <HelpCircle className="w-4 h-4" />
            </button>

            {/* Notifications */}
            <button className="p-2 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors relative">
              <Bell className="w-4 h-4" />
              <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-[var(--color-danger)] rounded-full"></span>
            </button>

            {/* Profile */}
            <div className="relative">
              <button
                onClick={() => setShowProfile(!showProfile)}
                className="flex items-center gap-2 p-1 pr-2 rounded-lg hover:bg-[var(--color-neutral-100)] transition-colors"
              >
                <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center text-white text-xs font-medium">
                  AD
                </div>
                <ChevronDown className="w-3 h-3 text-[var(--color-text-secondary)]" />
              </button>
              {showProfile && (
                <>
                  <div className="fixed inset-0 z-40" onClick={() => setShowProfile(false)} />
                  <div className="absolute right-0 top-full mt-1 bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg shadow-xl py-2 min-w-[200px] z-50">
                    <div className="px-4 py-2 border-b border-[var(--color-border)]">
                      <p className="text-sm font-medium text-[var(--color-text)]">{user?.name || 'Utilisateur'}</p>
                      <p className="text-xs text-[var(--color-text-secondary)]">{user?.email || '—'}</p>
                      <p className="text-xs text-[var(--color-primary)] mt-0.5 capitalize">{user?.role || ''}</p>
                    </div>
                    <button className="w-full text-left px-4 py-2 text-sm text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-50)] flex items-center gap-2">
                      <User className="w-4 h-4" /> Mon profil
                    </button>
                    <button
                      onClick={() => { setShowOnboarding(true); setShowProfile(false) }}
                      className="w-full text-left px-4 py-2 text-sm text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-50)] flex items-center gap-2"
                    >
                      <HelpCircle className="w-4 h-4" /> Guide de démarrage
                    </button>
                    <div className="border-t border-[var(--color-border)] mt-1 pt-1">
                      <button
                        onClick={async () => { await signOut(); navigate('/login') }}
                        className="w-full text-left px-4 py-2 text-sm text-[var(--color-danger)] hover:bg-[var(--color-neutral-50)] flex items-center gap-2"
                      >
                        <LogOut className="w-4 h-4" /> Déconnexion
                      </button>
                    </div>
                  </div>
                </>
              )}
            </div>
          </div>
        </header>

        {/* Main content */}
        <main className="flex-1 p-4 lg:p-6 max-w-[1600px] mx-auto w-full">
          {children ?? <Outlet />}
        </main>

        {/* Footer */}
        <footer className="border-t border-[var(--color-border)] bg-[var(--color-surface)] py-3 px-6">
          <div className="flex items-center justify-between text-xs text-[var(--color-text-secondary)]">
            <span>Compta v0.2.0 - Inspire de Sage Accounting, ameliore pour vous</span>
            <span>&copy; 2026 Compta</span>
          </div>
        </footer>
      </div>

      {/* Overlays */}
      <CommandPalette open={showCommand} onClose={() => setShowCommand(false)} />
      <AIAssistant open={showAI} onClose={() => setShowAI(false)} />
      <OnboardingModal open={showOnboarding} onClose={closeOnboarding} />
    </div>
  )
}
