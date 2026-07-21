import { Outlet, useNavigate } from 'react-router-dom'
import {
  Bell,
  HelpCircle,
  Search,
  Sparkles,
  ChevronDown,
  Moon,
  Sun,
  PanelLeft,
  User,
  LogOut,
  Globe,
} from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { useState, useEffect } from 'react'
import { useTheme } from '@/lib/theme'
import { useTranslation } from 'react-i18next'
import { SUPPORTED_LANGUAGES, LANGUAGE_LABELS, setLanguage, type SupportedLanguage } from '@/i18n'
import { CommandPalette } from './CommandPalette'
import { AIAssistant } from './AIAssistant'
import { OnboardingModal } from './OnboardingModal'
import { Sidebar, navGroups, getEnabledNavGroups } from './Sidebar'

export { navGroups, getEnabledNavGroups }

export function Layout({ children }: { children?: React.ReactNode }) {
  const navigate = useNavigate()
  const { theme, toggleTheme } = useTheme()
  const { user, signOut } = useAuth()
  const { t } = useTranslation('nav')
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [showProfile, setShowProfile] = useState(false)
  const [showCommand, setShowCommand] = useState(false)
  const [showAI, setShowAI] = useState(false)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [mobileSidebar, setMobileSidebar] = useState(false)
  const [showLangMenu, setShowLangMenu] = useState(false)
  const { i18n } = useTranslation()
  const currentLang = (i18n.language || 'fr').split('-')[0] as SupportedLanguage

  // Sync sidebar collapsed state with localStorage
  useEffect(() => {
    const saved = localStorage.getItem('compta-sidebar-collapsed')
    if (saved === 'true') setSidebarCollapsed(true)
  }, [])

  useEffect(() => {
    localStorage.setItem('compta-sidebar-collapsed', String(sidebarCollapsed))
  }, [sidebarCollapsed])

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

  return (
    <div className="min-h-screen flex flex-row">
      {/* Sidebar */}
      <Sidebar
        collapsed={sidebarCollapsed}
        onToggleCollapse={() => setSidebarCollapsed((v) => !v)}
        mobileOpen={mobileSidebar}
        onCloseMobile={() => setMobileSidebar(false)}
      />

      {/* Mobile overlay */}
      {mobileSidebar && <div className="fixed inset-0 bg-black/30 z-40 lg:hidden" onClick={() => setMobileSidebar(false)} />}

      {/* Main area */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Top bar */}
        <header className="sticky top-0 z-40 bg-[var(--color-surface)] border-b border-[var(--color-border)] h-14 flex flex-row items-center px-4 gap-3 glass">
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
            <span className="flex-1 text-left">{t('layout.search')}</span>
            <kbd className="text-[10px] bg-[var(--color-surface)] px-1.5 py-0.5 rounded border border-[var(--color-border)]">Cmd+K</kbd>
          </button>

          {/* Right actions */}
          <div className="flex flex-row items-center gap-1.5 ml-auto">
            {/* AI Assistant */}
            <button
              onClick={() => setShowAI(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-gradient-to-r from-[var(--color-primary)] to-purple-600 text-white hover:opacity-90 transition-opacity text-sm font-medium"
            >
              <Sparkles className="w-4 h-4" />
              <span className="hidden sm:block">{t('layout.aiAssistant')}</span>
            </button>

            {/* Language switcher */}
            <div className="relative">
              <button
                onClick={() => setShowLangMenu(!showLangMenu)}
                className="flex items-center gap-1.5 p-2 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
                title={t('layout.language')}
              >
                <Globe className="w-4 h-4" />
                <span className="text-xs font-medium hidden sm:block">{LANGUAGE_LABELS[currentLang]?.flag}</span>
              </button>
              {showLangMenu && (
                <>
                  <div className="fixed inset-0 z-40" onClick={() => setShowLangMenu(false)} />
                  <div className="absolute right-0 top-full mt-1 bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg shadow-xl py-1 min-w-[150px] z-50">
                    {SUPPORTED_LANGUAGES.map((lng) => (
                      <button
                        key={lng}
                        onClick={() => { setLanguage(lng); setShowLangMenu(false) }}
                        className={`w-full text-left px-3 py-2 text-sm flex items-center gap-2 hover:bg-[var(--color-neutral-50)] transition-colors ${currentLang === lng ? 'text-[var(--color-primary)] font-medium' : 'text-[var(--color-text-secondary)]'}`}
                      >
                        <span>{LANGUAGE_LABELS[lng].flag}</span>
                        <span>{LANGUAGE_LABELS[lng].label}</span>
                        {currentLang === lng && <ChevronDown className="w-3 h-3 ml-auto rotate-180" />}
                      </button>
                    ))}
                  </div>
                </>
              )}
            </div>

            {/* Dark mode toggle */}
            <button
              onClick={toggleTheme}
              className="p-2 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
              title={t('layout.darkLightMode')}
            >
              {theme === 'dark' ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
            </button>

            {/* Help */}
            <button
              onClick={() => setShowOnboarding(true)}
              className="p-2 rounded-lg text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
              title={t('layout.help')}
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
                      <p className="text-sm font-medium text-[var(--color-text)]">{user?.name || t('layout.user')}</p>
                      <p className="text-xs text-[var(--color-text-secondary)]">{user?.email || '—'}</p>
                      <p className="text-xs text-[var(--color-primary)] mt-0.5 capitalize">{user?.role || ''}</p>
                    </div>
                    <button className="w-full text-left px-4 py-2 text-sm text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-50)] flex items-center gap-2">
                      <User className="w-4 h-4" /> {t('layout.myProfile')}
                    </button>
                    <button
                      onClick={() => { setShowOnboarding(true); setShowProfile(false) }}
                      className="w-full text-left px-4 py-2 text-sm text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-50)] flex items-center gap-2"
                    >
                      <HelpCircle className="w-4 h-4" /> {t('layout.startupGuide')}
                    </button>
                    <div className="border-t border-[var(--color-border)] mt-1 pt-1">
                      <button
                        onClick={async () => { await signOut(); navigate('/login') }}
                        className="w-full text-left px-4 py-2 text-sm text-[var(--color-danger)] hover:bg-[var(--color-neutral-50)] flex items-center gap-2"
                      >
                        <LogOut className="w-4 h-4" /> {t('layout.logout')}
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
            <span>{t('layout.footer')}</span>
            <span>{t('layout.copyright')}</span>
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
