import { useState, useEffect } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useTheme } from '@/lib/theme'
import {
  BookOpen, ShoppingCart, Wallet, Boxes, Factory, Users,
  BarChart3, PieChart, ClipboardList, Settings,
  ArrowRight, Sparkles, Check, Shield, Zap,
  TrendingDown, RefreshCw, Clock, Server, Lock, FileText,
  ChevronDown, Minus, Plus, ArrowLeftRight,
  Store, Briefcase, Hammer, Wheat, HeartHandshake,
  Quote, Sun, Moon,
  X, GitBranch, ListChecks, Users2,
  Repeat, MessageSquare, Timer, Trello, LayoutGrid,
} from 'lucide-react'

const modules = [
  { icon: BookOpen, color: 'indigo', labelKey: 'nav:groups.accounting', descKey: 'landing.modules.accounting' },
  { icon: ShoppingCart, color: 'emerald', labelKey: 'nav:groups.commercial', descKey: 'landing.modules.commercial' },
  { icon: Wallet, color: 'amber', labelKey: 'nav:groups.treasury', descKey: 'landing.modules.treasury' },
  { icon: Boxes, color: 'violet', labelKey: 'nav:groups.stock', descKey: 'landing.modules.stock' },
  { icon: Factory, color: 'lime', labelKey: 'nav:groups.production', descKey: 'landing.modules.production' },
  { icon: Users, color: 'cyan', labelKey: 'nav:groups.hr', descKey: 'landing.modules.hr' },
  { icon: ClipboardList, color: 'rose', labelKey: 'nav:groups.projectManagement', descKey: 'landing.modules.projectManagement' },
  { icon: BarChart3, color: 'teal', labelKey: 'nav:groups.dashboards', descKey: 'landing.modules.dashboards' },
  { icon: PieChart, color: 'fuchsia', labelKey: 'nav:groups.reporting', descKey: 'landing.modules.reporting' },
  { icon: Settings, color: 'slate', labelKey: 'nav:groups.system', descKey: 'landing.modules.system' },
]

const colorHexMap: Record<string, string> = {
  indigo: '#6366f1',
  emerald: '#10b981',
  amber: '#f59e0b',
  violet: '#8b5cf6',
  lime: '#84cc16',
  cyan: '#06b6d4',
  rose: '#f43f5e',
  teal: '#14b8a6',
  fuchsia: '#d946ef',
  slate: '#64748b',
}

const modulesRow1 = modules.slice(0, 5)
const modulesRow2 = modules.slice(5)

const useCases = [
  { icon: Store, color: '#10b981', bgGradient: 'from-emerald-500/10 to-teal-500/5', key: 'retail' },
  { icon: Briefcase, color: '#6366f1', bgGradient: 'from-indigo-500/10 to-blue-500/5', key: 'services' },
  { icon: Factory, color: '#f59e0b', bgGradient: 'from-amber-500/10 to-orange-500/5', key: 'manufacturing' },
  { icon: Hammer, color: '#f43f5e', bgGradient: 'from-rose-500/10 to-red-500/5', key: 'construction' },
  { icon: Wheat, color: '#84cc16', bgGradient: 'from-lime-500/10 to-green-500/5', key: 'agriculture' },
  { icon: HeartHandshake, color: '#d946ef', bgGradient: 'from-fuchsia-500/10 to-pink-500/5', key: 'nonprofit' },
]

const roiStats = [
  { key: 'hoursSaved', color: '#6366f1', bgGradient: 'from-indigo-500 to-blue-600' },
  { key: 'fasterInvoicing', color: '#10b981', bgGradient: 'from-emerald-500 to-teal-600' },
  { key: 'automation', color: '#f59e0b', bgGradient: 'from-amber-500 to-orange-600' },
  { key: 'payback', color: '#f43f5e', bgGradient: 'from-rose-500 to-pink-600' },
]

const comparisonRows = [
  { featureKey: 'modules', onusuiteKey: 'modulesOnusuite', sageKey: 'modulesSage', qbKey: 'modulesQuickbooks', excelKey: 'modulesExcel' },
  { featureKey: 'price', onusuiteKey: 'priceOnusuite', sageKey: 'priceSage', qbKey: 'priceQuickbooks', excelKey: 'priceExcel' },
  { featureKey: 'migration', onusuiteKey: 'migrationOnusuite', sageKey: 'migrationSage', qbKey: 'migrationQuickbooks', excelKey: 'migrationExcel' },
  { featureKey: 'multiTenant', onusuiteKey: 'multiTenantOnusuite', sageKey: 'multiTenantSage', qbKey: 'multiTenantQuickbooks', excelKey: 'multiTenantExcel' },
  { featureKey: 'i18n', onusuiteKey: 'i18nOnusuite', sageKey: 'i18nSage', qbKey: 'i18nQuickbooks', excelKey: 'i18nExcel' },
  { featureKey: 'support', onusuiteKey: 'supportOnusuite', sageKey: 'supportSage', qbKey: 'supportQuickbooks', excelKey: 'supportExcel' },
]

const stats = [
  { value: '60%', labelKey: 'landing.stats.costReduction', color: '#C44536', bgGradient: 'from-[#C44536] to-[#E8755A]' },
  { value: '17', labelKey: 'landing.stats.modules', color: '#1E2A4A', bgGradient: 'from-[#1E2A4A] to-[#3B4F8A]' },
  { value: '45d', labelKey: 'landing.stats.trialDays', color: '#2D7D6F', bgGradient: 'from-[#2D7D6F] to-[#4FA89A]' },
  { value: '3', labelKey: 'landing.stats.companies', color: '#E8A838', bgGradient: 'from-[#E8A838] to-[#F5C56B]' },
]

const pillars = [
  { key: 'landing.pillars.saveMoney', icon: TrendingDown, color: '#C44536' },
  { key: 'landing.pillars.saveTime', icon: Zap, color: '#E8A838' },
  { key: 'landing.pillars.onePlatform', icon: Server, color: '#2D7D6F' },
]

const withoutPoints = ['1', '2', '3', '4', '5']
const withPoints = ['1', '2', '3', '4', '5']

const foundationScenarios = [
  { key: 'scenario1', icon: BookOpen, color: '#6366f1', gradient: 'from-indigo-500/10 to-blue-500/5' },
  { key: 'scenario2', icon: ShoppingCart, color: '#10b981', gradient: 'from-emerald-500/10 to-teal-500/5' },
  { key: 'scenario3', icon: Boxes, color: '#f59e0b', gradient: 'from-amber-500/10 to-orange-500/5' },
  { key: 'scenario4', icon: Users, color: '#06b6d4', gradient: 'from-cyan-500/10 to-sky-500/5' },
  { key: 'scenario5', icon: BarChart3, color: '#f43f5e', gradient: 'from-rose-500/10 to-red-500/5' },
  { key: 'scenario6', icon: ClipboardList, color: '#8b5cf6', gradient: 'from-violet-500/10 to-purple-500/5' },
]

const featuresGridItems = [
  { key: 'customFields', icon: LayoutGrid, color: '#6366f1' },
  { key: 'multipleViews', icon: Trello, color: '#10b981' },
  { key: 'automations', icon: Zap, color: '#f59e0b' },
  { key: 'dependencies', icon: GitBranch, color: '#f43f5e' },
  { key: 'subtasks', icon: ListChecks, color: '#8b5cf6' },
  { key: 'multiAssignees', icon: Users2, color: '#06b6d4' },
  { key: 'recurringTasks', icon: Repeat, color: '#84cc16' },
  { key: 'comments', icon: MessageSquare, color: '#d946ef' },
  { key: 'timeTracking', icon: Timer, color: '#C44536' },
]

const colorVarMap: Record<string, string> = {
  indigo: '--mod-indigo',
  emerald: '--mod-emerald',
  amber: '--mod-amber',
  violet: '--mod-violet',
  lime: '--mod-lime',
  cyan: '--mod-cyan',
  rose: '--mod-rose',
  teal: '--mod-teal',
  fuchsia: '--mod-fuchsia',
  slate: '--mod-slate',
}

const colorBgMap: Record<string, string> = {
  indigo: '--mod-indigo-bg',
  emerald: '--mod-emerald-bg',
  amber: '--mod-amber-bg',
  violet: '--mod-violet-bg',
  lime: '--mod-lime-bg',
  cyan: '--mod-cyan-bg',
  rose: '--mod-rose-bg',
  teal: '--mod-teal-bg',
  fuchsia: '--mod-fuchsia-bg',
  slate: '--mod-slate-bg',
}

const features = [
  { icon: TrendingDown, key: 'landing.features.lowerCost' },
  { icon: Zap, key: 'landing.features.efficiency' },
  { icon: Shield, key: 'landing.features.robustness' },
  { icon: RefreshCw, key: 'landing.features.migration' },
]

const whyPoints = [
  { icon: TrendingDown, key: 'landing.why.lowerCost' },
  { icon: Zap, key: 'landing.why.efficiency' },
  { icon: Shield, key: 'landing.why.robustness' },
  { icon: ArrowLeftRight, key: 'landing.why.flexibility' },
  { icon: RefreshCw, key: 'landing.why.migration' },
  { icon: Server, key: 'landing.why.allInOne' },
]

const currencies = [
  { code: 'USD', symbol: '$', rate: 1, label: 'USD' },
  { code: 'EUR', symbol: '€', rate: 1, label: 'EUR' },
  { code: 'XOF', symbol: 'FCFA', rate: 655.957, label: 'XOF' },
  { code: 'XAF', symbol: 'FCFA', rate: 655.957, label: 'XAF' },
  { code: 'MAD', symbol: 'DH', rate: 10, label: 'MAD' },
  { code: 'TND', symbol: 'DT', rate: 3.1, label: 'TND' },
  { code: 'DZD', symbol: 'DA', rate: 134, label: 'DZD' },
  { code: 'DJF', symbol: 'FDJ', rate: 177.721, label: 'DJF' },
  { code: 'EGP', symbol: 'E£', rate: 48, label: 'EGP' },
  { code: 'GHS', symbol: 'GH₵', rate: 15, label: 'GHS' },
  { code: 'NGN', symbol: '₦', rate: 1600, label: 'NGN' },
  { code: 'KES', symbol: 'KSh', rate: 129, label: 'KES' },
  { code: 'ETB', symbol: 'Br', rate: 126, label: 'ETB' },
  { code: 'RWF', symbol: 'RF', rate: 1300, label: 'RWF' },
  { code: 'SOS', symbol: 'SOS', rate: 571, label: 'SOS' },
  { code: 'AOA', symbol: 'Kz', rate: 920, label: 'AOA' },
  { code: 'ZMW', symbol: 'ZK', rate: 27, label: 'ZMW' },
  { code: 'CDF', symbol: 'FC', rate: 2750, label: 'CDF' },
  { code: 'GMD', symbol: 'GMD', rate: 72, label: 'GMD' },
  { code: 'LRD', symbol: 'LRD', rate: 200, label: 'LRD' },
  { code: 'SLL', symbol: 'Le', rate: 23000, label: 'SLL' },
  { code: 'GNF', symbol: 'GNF', rate: 8600, label: 'GNF' },
  { code: 'MWK', symbol: 'MK', rate: 1740, label: 'MWK' },
  { code: 'MZN', symbol: 'MT', rate: 64, label: 'MZN' },
  { code: 'BIF', symbol: 'BIF', rate: 2950, label: 'BIF' },
  { code: 'KMF', symbol: 'CF', rate: 485, label: 'KMF' },
  { code: 'SCR', symbol: 'SR', rate: 14.5, label: 'SCR' },
  { code: 'MUR', symbol: 'Rs', rate: 47, label: 'MUR' },
  { code: 'ZWL', symbol: 'ZWL', rate: 13.5, label: 'ZWL' },
]

const countryCurrencyMap: Record<string, string> = {
  DJ: 'DJF', CI: 'XOF', SN: 'XOF', BF: 'XOF', ML: 'XOF', BJ: 'XOF', TG: 'XOF', NE: 'XOF', GN: 'XOF',
  CM: 'XAF', GA: 'XAF', CG: 'XAF', TD: 'XAF', CF: 'XAF', GQ: 'XAF',
  MA: 'MAD', TN: 'TND', DZ: 'DZD',
  EG: 'EGP', GH: 'GHS', NG: 'NGN', KE: 'KES', ET: 'ETB', RW: 'RWF',
  SO: 'SOS', AO: 'AOA', ZM: 'ZMW', CD: 'CDF', GM: 'GMD', LR: 'LRD',
  SL: 'SLL', GN2: 'GNF', MW: 'MWK', MZ: 'MZN', BI: 'BIF', KM: 'KMF',
  SC: 'SCR', MU: 'MUR', ZW: 'ZWL',
}

const tiers = [
  { id: 'T1', usersKey: 'landing.pricing.tier1Users' },
  { id: 'T2', usersKey: 'landing.pricing.tier2Users' },
  { id: 'T3', usersKey: 'landing.pricing.tier3Users' },
]

const plans = [
  {
    id: 'essential',
    nameKey: 'landing.pricing.essential.name',
    descKey: 'landing.pricing.essential.desc',
    modulesKey: 'landing.pricing.essential.modules',
    featuresKey: 'landing.pricing.essential.features',
    prices: { T1: 60, T2: 100, T3: 170 },
    highlighted: false,
  },
  {
    id: 'management',
    nameKey: 'landing.pricing.management.name',
    descKey: 'landing.pricing.management.desc',
    modulesKey: 'landing.pricing.management.modules',
    featuresKey: 'landing.pricing.management.features',
    prices: { T1: 100, T2: 170, T3: 260 },
    highlighted: true,
  },
  {
    id: 'full',
    nameKey: 'landing.pricing.full.name',
    descKey: 'landing.pricing.full.desc',
    modulesKey: 'landing.pricing.full.modules',
    featuresKey: 'landing.pricing.full.features',
    prices: { T1: 150, T2: 250, T3: 420 },
    highlighted: false,
  },
]

const faqItems = [
  { qKey: 'landing.faq.trialDuration.q', aKey: 'landing.faq.trialDuration.a' },
  { qKey: 'landing.faq.noCard.q', aKey: 'landing.faq.noCard.a' },
  { qKey: 'landing.faq.migration.q', aKey: 'landing.faq.migration.a' },
  { qKey: 'landing.faq.afterTrial.q', aKey: 'landing.faq.afterTrial.a' },
  { qKey: 'landing.faq.cancel.q', aKey: 'landing.faq.cancel.a' },
  { qKey: 'landing.faq.support.q', aKey: 'landing.faq.support.a' },
]

function formatPrice(usdPrice: number, currency: typeof currencies[0]): string {
  const converted = usdPrice * currency.rate
  if (currency.code === 'USD' || currency.code === 'EUR') {
    return `${currency.symbol}${Math.round(converted)}`
  }
  const rounded = Math.round(converted / 50) * 50
  return `${rounded.toLocaleString('fr-FR')} ${currency.symbol}`
}

export function LandingPage() {
  const { t } = useTranslation(['nav', 'common'])
  const navigate = useNavigate()
  const [selectedTier, setSelectedTier] = useState('T1')
  const [localCurrency, setLocalCurrency] = useState<typeof currencies[0] | null>(null)
  const [detectedCountry, setDetectedCountry] = useState<string>('')
  const [openFaq, setOpenFaq] = useState<number | null>(0)
  const [currencyOpen, setCurrencyOpen] = useState(false)
  const { theme, toggleTheme } = useTheme()

  useEffect(() => {
    const stored = typeof localStorage !== 'undefined' ? localStorage.getItem('detected_currency') : null
    if (stored) {
      const found = currencies.find(c => c.code === stored)
      if (found) setLocalCurrency(found)
    }
    fetch('https://ipwho.is/')
      .then(res => res.json())
      .then(data => {
        if (data && data.country_code) {
          setDetectedCountry(data.country_code)
          const currencyCode = countryCurrencyMap[data.country_code]
          if (currencyCode) {
            const found = currencies.find(c => c.code === currencyCode)
            if (found) {
              setLocalCurrency(found)
              if (typeof localStorage !== 'undefined') {
                localStorage.setItem('detected_currency', found.code)
              }
            }
          }
        }
      })
      .catch(() => {})
  }, [])

  return (
    <div className="min-h-screen bg-[var(--color-neutral-50)]">
      {/* Header */}
      <header className="sticky top-0 z-50 bg-[var(--color-surface)]/80 backdrop-blur-md border-b border-[var(--color-border)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#C44536] to-[#1E2A4A] flex items-center justify-center shadow-md">
              <span className="text-white font-bold text-lg">O</span>
            </div>
            <span className="text-lg font-bold text-[var(--color-text)]">Onusuite</span>
          </div>
          <nav className="hidden md:flex items-center gap-6">
            <a href="#why" className="text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors">{t('landing.nav.why')}</a>
            <a href="#features" className="text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors">{t('landing.nav.features')}</a>
            <a href="#modules" className="text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors">{t('landing.nav.modules')}</a>
            <a href="#useCases" className="text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors">{t('landing.useCasesTitle')}</a>
            <a href="#pricing" className="text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors">{t('landing.nav.pricing')}</a>
            <a href="#faq" className="text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors">{t('landing.nav.faq')}</a>
          </nav>
          <div className="flex items-center gap-3">
            <button
              onClick={toggleTheme}
              className="w-9 h-9 rounded-lg border border-[var(--color-border)] flex items-center justify-center text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] hover:text-[var(--color-text)] transition-colors"
              aria-label="Toggle dark mode"
            >
              {theme === 'dark' ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
            </button>
            <button
              onClick={() => navigate('/login')}
              className="text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors px-4 py-2"
            >
              {t('landing.login')}
            </button>
            <button
              onClick={() => navigate('/signup')}
              className="text-sm font-medium text-white bg-[var(--color-primary)] hover:opacity-90 transition-opacity px-4 py-2 rounded-lg"
            >
              {t('landing.ctaStart')}
            </button>
          </div>
        </div>
      </header>

      {/* Hero */}
      <section className="relative overflow-hidden">
        <img
          src="/brand/hero-geometric.png"
          alt=""
          className="absolute inset-0 w-full h-full object-cover opacity-[0.04] pointer-events-none"
          aria-hidden="true"
        />
        <div className="absolute top-0 right-0 w-96 h-96 bg-gradient-to-br from-[#C44536]/10 to-[#1E2A4A]/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-0 w-72 h-72 bg-gradient-to-tr from-[#2D7D6F]/10 to-[#E8A838]/5 rounded-full blur-3xl pointer-events-none" />
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20 lg:py-32 text-center">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-[var(--color-neutral-100)] border border-[var(--color-border)] mb-6">
            <Sparkles className="w-4 h-4 text-[#E8A838]" />
            <span className="text-xs font-medium text-[var(--color-text-secondary)]">{t('landing.badge')}</span>
          </div>
          <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold text-[var(--color-text)] leading-tight max-w-3xl mx-auto">
            {t('landing.heroTitle')}
          </h1>
          <p className="text-lg text-[var(--color-text-secondary)] mt-6 max-w-2xl mx-auto">
            {t('landing.heroSubtitle')}
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mt-10">
            <button
              onClick={() => navigate('/signup')}
              className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-[var(--color-primary)] text-white font-semibold hover:opacity-90 transition-opacity shadow-lg"
            >
              {t('landing.ctaStart')}
              <ArrowRight className="w-4 h-4" />
            </button>
            <button
              onClick={() => navigate('/login')}
              className="inline-flex items-center gap-2 px-6 py-3 rounded-xl border border-[var(--color-border)] text-[var(--color-text)] font-semibold hover:bg-[var(--color-neutral-100)] transition-colors"
            >
              {t('landing.ctaDemo')}
            </button>
          </div>
          <p className="text-sm text-[var(--color-text-secondary)] mt-6">
            {t('landing.heroNoCard')}
          </p>
        </div>
      </section>

      {/* 3 Pillars */}
      <section className="bg-[var(--color-surface)] border-y border-[var(--color-border)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {pillars.map((p, idx) => (
              <div key={idx} className="flex items-center gap-4 p-4 rounded-2xl" style={{ background: `linear-gradient(135deg, ${p.color}08, ${p.color}03)` }}>
                <div className="w-12 h-12 rounded-xl flex items-center justify-center flex-shrink-0" style={{ background: `${p.color}15`, boxShadow: `0 0 16px -4px ${p.color}50` }}>
                  <p.icon className="w-6 h-6" style={{ color: p.color }} />
                </div>
                <span className="text-sm font-semibold text-[var(--color-text)]">{t(p.key)}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Stats band */}
      <section className="bg-gradient-to-r from-[#1E2A4A] via-[#2D7D6F] to-[#C44536] py-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-6">
            {stats.map((s, idx) => (
              <div key={idx} className="text-center">
                <div className={`text-4xl lg:text-5xl font-bold bg-gradient-to-br ${s.bgGradient} bg-clip-text text-transparent`}>
                  {s.value}
                </div>
                <div className="text-sm text-white/80 mt-2">{t(s.labelKey)}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Why Onusuite */}
      <section id="why" className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.whyTitle')}</h2>
          <p className="text-[var(--color-text-secondary)] mt-3 max-w-2xl mx-auto">{t('landing.whySubtitle')}</p>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {whyPoints.map((pt, idx) => (
            <div key={idx} className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-6">
              <div className="w-12 h-12 rounded-xl bg-[var(--color-neutral-100)] flex items-center justify-center mb-4">
                <pt.icon className="w-6 h-6 text-[var(--color-primary)]" />
              </div>
              <h3 className="text-base font-bold text-[var(--color-text)] mb-2">{t(`${pt.key}.title`)}</h3>
              <p className="text-sm text-[var(--color-text-secondary)] leading-relaxed">{t(`${pt.key}.desc`)}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Features bar */}
      <section id="features" className="border-y border-[var(--color-border)] bg-[var(--color-surface)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-6">
            {features.map((feat, idx) => (
              <div key={idx} className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-[var(--color-neutral-100)] flex items-center justify-center flex-shrink-0">
                  <feat.icon className="w-5 h-5 text-[var(--color-primary)]" />
                </div>
                <span className="text-sm font-medium text-[var(--color-text)]">{t(feat.key)}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* A better way to work */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.betterWayTitle')}</h2>
          <p className="text-[var(--color-text-secondary)] mt-3 max-w-2xl mx-auto">{t('landing.betterWaySubtitle')}</p>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {/* Without Onusuite */}
          <div className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-8">
            <h3 className="text-xl font-bold text-[var(--color-text-secondary)] mb-6 flex items-center gap-2">
              <X className="w-5 h-5 text-[#C44536]" />
              {t('landing.betterWay.withoutTitle')}
            </h3>
            <div className="space-y-4">
              {withoutPoints.map(p => (
                <div key={p} className="flex items-start gap-3">
                  <div className="w-6 h-6 rounded-full bg-[#C44536]/10 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <X className="w-3.5 h-3.5 text-[#C44536]" />
                  </div>
                  <span className="text-sm text-[var(--color-text-secondary)]">{t(`landing.betterWay.without.${p}`)}</span>
                </div>
              ))}
            </div>
          </div>
          {/* With Onusuite */}
          <div className="rounded-2xl border-2 border-[#2D7D6F]/30 bg-gradient-to-br from-[#2D7D6F]/5 to-[#10b981]/5 p-8" style={{ boxShadow: '0 8px 40px -12px rgba(45,125,111,0.2)' }}>
            <h3 className="text-xl font-bold text-[var(--color-text)] mb-6 flex items-center gap-2">
              <Check className="w-5 h-5 text-[#2D7D6F]" />
              {t('landing.betterWay.withTitle')}
            </h3>
            <div className="space-y-4">
              {withPoints.map(p => (
                <div key={p} className="flex items-start gap-3">
                  <div className="w-6 h-6 rounded-full bg-[#2D7D6F]/15 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <Check className="w-3.5 h-3.5 text-[#2D7D6F]" />
                  </div>
                  <span className="text-sm font-medium text-[var(--color-text)]">{t(`landing.betterWay.with.${p}`)}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Foundation for every workflow */}
      <section className="bg-[var(--color-surface)] border-y border-[var(--color-border)] py-20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.foundationTitle')}</h2>
            <p className="text-[var(--color-text-secondary)] mt-3 max-w-2xl mx-auto">{t('landing.foundationSubtitle')}</p>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {foundationScenarios.map((sc, idx) => (
              <div
                key={idx}
                className={`group relative rounded-2xl border border-[var(--color-border)] bg-gradient-to-br ${sc.gradient} p-6 hover:-translate-y-1 transition-all duration-300 overflow-hidden`}
                style={{ boxShadow: `0 4px 24px -8px ${sc.color}15` }}
              >
                <div
                  className="absolute -bottom-12 -right-12 w-40 h-40 rounded-full opacity-5 group-hover:opacity-10 transition-opacity"
                  style={{ background: sc.color }}
                />
                <div
                  className="relative w-14 h-14 rounded-2xl flex items-center justify-center mb-4 transition-transform group-hover:scale-110"
                  style={{ background: `${sc.color}20`, boxShadow: `0 0 24px -4px ${sc.color}40` }}
                >
                  <sc.icon className="w-7 h-7" style={{ color: sc.color }} />
                </div>
                <h3 className="relative text-lg font-bold text-[var(--color-text)] mb-2">{t(`landing.foundation.${sc.key}.title`)}</h3>
                <p className="relative text-sm text-[var(--color-text-secondary)] leading-relaxed">{t(`landing.foundation.${sc.key}.desc`)}</p>

                {/* Permanent CSS-only decorative UI window mockup */}
                <div className="relative mt-5 rounded-xl overflow-hidden border border-[var(--color-border)] bg-[var(--color-surface)]">
                  {/* Window title bar */}
                  <div className="flex items-center gap-1.5 px-3 py-2 border-b border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                    <div className="w-2.5 h-2.5 rounded-full" style={{ background: '#C4453640' }} />
                    <div className="w-2.5 h-2.5 rounded-full" style={{ background: '#E8A83840' }} />
                    <div className="w-2.5 h-2.5 rounded-full" style={{ background: '#2D7D6F40' }} />
                    <div className="flex-1 h-3 rounded-full ml-2" style={{ background: `${sc.color}10` }} />
                  </div>

                  {/* Scenario-specific decorative content */}
                  <div className="p-3 h-36" style={{ background: `linear-gradient(135deg, ${sc.color}05, transparent)` }}>
                    {sc.key === 'scenario1' && (
                      <div className="space-y-1.5">
                        {[100, 85, 92, 70].map((w, i) => (
                          <div key={i} className="flex items-center gap-2">
                            <div className="h-2.5 rounded flex-shrink-0" style={{ background: `${sc.color}20`, width: '20px' }} />
                            <div className="h-2.5 rounded-full" style={{ background: `${sc.color}${i % 2 ? '15' : '25'}`, width: `${w}%` }} />
                            <div className="h-2.5 rounded-full ml-auto" style={{ background: `${sc.color}10`, width: '30px' }} />
                          </div>
                        ))}
                        <div className="flex justify-between pt-1.5 border-t border-[var(--color-border)]">
                          <div className="h-2.5 rounded-full" style={{ background: `${sc.color}30`, width: '40px' }} />
                          <div className="h-2.5 rounded-full" style={{ background: `${sc.color}30`, width: '40px' }} />
                        </div>
                      </div>
                    )}

                    {sc.key === 'scenario2' && (
                      <div className="space-y-1.5">
                        {[90, 75, 60].map((w, i) => (
                          <div key={i} className="flex items-center gap-2">
                            <div className="h-2.5 rounded-full flex-1" style={{ background: `${sc.color}${i === 0 ? '25' : '12'}`, width: `${w}%` }} />
                            <div className="h-5 rounded-md flex-shrink-0" style={{ background: `${sc.color}20`, width: '36px' }} />
                          </div>
                        ))}
                        <div className="flex justify-end pt-1.5">
                          <div className="h-6 rounded-lg flex items-center" style={{ background: `${sc.color}25`, width: '60px' }} />
                        </div>
                      </div>
                    )}

                    {sc.key === 'scenario3' && (
                      <div className="flex items-end justify-between h-full gap-1.5 pb-2">
                        {[40, 65, 50, 80, 55, 70, 45].map((h, i) => (
                          <div key={i} className="flex-1 rounded-t-md" style={{ background: `linear-gradient(to top, ${sc.color}30, ${sc.color}10)`, height: `${h}%` }} />
                        ))}
                      </div>
                    )}

                    {sc.key === 'scenario4' && (
                      <div className="space-y-1.5">
                        {[0, 1, 2].map(i => (
                          <div key={i} className="flex items-center gap-2">
                            <div className="w-6 h-6 rounded-full flex-shrink-0" style={{ background: `${sc.color}20` }} />
                            <div className="flex-1 space-y-1">
                              <div className="h-2 rounded-full" style={{ background: `${sc.color}25`, width: '70%' }} />
                              <div className="h-1.5 rounded-full" style={{ background: `${sc.color}10`, width: '50%' }} />
                            </div>
                            <div className="h-5 rounded-md flex-shrink-0" style={{ background: `${sc.color}15`, width: '28px' }} />
                          </div>
                        ))}
                      </div>
                    )}

                    {sc.key === 'scenario5' && (
                      <div className="flex items-center justify-center h-full gap-4">
                        <div className="relative w-20 h-20 rounded-full" style={{ background: `conic-gradient(${sc.color}40 0% 35%, ${sc.color}25 35% 60%, ${sc.color}15 60% 80%, ${sc.color}08 80% 100%)` }}>
                          <div className="absolute inset-3 rounded-full bg-[var(--color-surface)]" />
                        </div>
                        <div className="space-y-1.5 flex-1">
                          {[80, 60, 45].map((w, i) => (
                            <div key={i} className="flex items-center gap-1.5">
                              <div className="w-2 h-2 rounded-sm" style={{ background: `${sc.color}${['40', '25', '15'][i]}` }} />
                              <div className="h-2 rounded-full" style={{ background: `${sc.color}${['25', '15', '10'][i]}`, width: `${w}%` }} />
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {sc.key === 'scenario6' && (
                      <div className="grid grid-cols-3 gap-1.5 h-full">
                        {['TODO', 'DOING', 'DONE'].map((col, ci) => (
                          <div key={ci} className="space-y-1.5">
                            <div className="h-2.5 rounded-full" style={{ background: `${sc.color}${['15', '25', '30'][ci]}`, width: '80%' }} />
                            {[0, 1].map(ti => (
                              <div key={ti} className="rounded-md p-1.5 space-y-1 border" style={{ borderColor: `${sc.color}15`, background: `${sc.color}05` }}>
                                <div className="h-1.5 rounded-full" style={{ background: `${sc.color}20`, width: '90%' }} />
                                <div className="h-1.5 rounded-full" style={{ background: `${sc.color}10`, width: '60%' }} />
                                <div className="flex gap-1">
                                  <div className="w-3 h-3 rounded-full" style={{ background: `${sc.color}20` }} />
                                  <div className="h-2 rounded-full flex-1" style={{ background: `${sc.color}08` }} />
                                </div>
                              </div>
                            ))}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features grid (ClickUp-inspired) */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.featuresGridTitle')}</h2>
          <p className="text-[var(--color-text-secondary)] mt-3 max-w-2xl mx-auto">{t('landing.featuresGridSubtitle')}</p>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {featuresGridItems.map((item, idx) => (
            <div
              key={idx}
              className="group flex items-start gap-4 p-5 rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] hover:-translate-y-1 transition-all duration-300"
              style={{ boxShadow: `0 2px 16px -8px ${item.color}20` }}
              onMouseEnter={(e) => { e.currentTarget.style.boxShadow = `0 8px 32px -6px ${item.color}30` }}
              onMouseLeave={(e) => { e.currentTarget.style.boxShadow = `0 2px 16px -8px ${item.color}20` }}
            >
              <div
                className="w-12 h-12 rounded-xl flex items-center justify-center flex-shrink-0 transition-transform group-hover:scale-110"
                style={{ background: `${item.color}15`, boxShadow: `0 0 20px -4px ${item.color}40` }}
              >
                <item.icon className="w-6 h-6" style={{ color: item.color }} />
              </div>
              <div>
                <h3 className="text-base font-bold text-[var(--color-text)] mb-1">{t(`landing.featuresGrid.${item.key}.title`)}</h3>
                <p className="text-sm text-[var(--color-text-secondary)] leading-relaxed">{t(`landing.featuresGrid.${item.key}.desc`)}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Modules carousel */}
      <section id="modules" className="py-20 overflow-hidden">
        <div className="text-center mb-12 px-4">
          <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.modulesTitle')}</h2>
          <p className="text-[var(--color-text-secondary)] mt-3 max-w-xl mx-auto">{t('landing.modulesSubtitle')}</p>
        </div>

        {/* Row 1: right-to-left */}
        <div className="relative mb-6">
          <div className="flex gap-6 animate-marquee-rtl" style={{ animationDuration: '30s' }}>
            {[...modulesRow1, ...modulesRow1, ...modulesRow1].map((mod, idx) => {
              const colorVar = colorVarMap[mod.color]
              const colorBg = colorBgMap[mod.color]
              const hex = colorHexMap[mod.color]
              return (
                <div
                  key={`r1-${idx}`}
                  className="group relative flex-shrink-0 w-72 rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-6 cursor-pointer transition-all duration-500 hover:-translate-y-2"
                  style={{
                    boxShadow: `0 4px 24px -8px ${hex}30, 0 2px 8px -4px rgba(0,0,0,0.06)`,
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.boxShadow = `0 8px 40px -6px ${hex}50, 0 4px 16px -4px ${hex}30, 0 0 0 1px ${hex}20`
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.boxShadow = `0 4px 24px -8px ${hex}30, 0 2px 8px -4px rgba(0,0,0,0.06)`
                  }}
                  onClick={() => navigate('/signup')}
                >
                  <div
                    className="absolute inset-0 rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-500 pointer-events-none"
                    style={{ background: `radial-gradient(circle at 50% 0%, ${hex}08, transparent 70%)` }}
                  />
                  <div
                    className="relative w-14 h-14 rounded-2xl flex items-center justify-center mb-4 transition-transform group-hover:scale-110"
                    style={{
                      background: `var(${colorBg})`,
                      boxShadow: `0 0 20px -4px ${hex}60`,
                    }}
                  >
                    <mod.icon className="w-7 h-7" style={{ color: `var(${colorVar})` }} />
                  </div>
                  <h3 className="relative text-base font-bold text-[var(--color-text)] mb-1">{t(mod.labelKey)}</h3>
                  <p className="relative text-sm text-[var(--color-text-secondary)] leading-relaxed">{t(mod.descKey)}</p>
                </div>
              )
            })}
          </div>
        </div>

        {/* Row 2: left-to-right */}
        <div className="relative">
          <div className="flex gap-6 animate-marquee-ltr" style={{ animationDuration: '30s' }}>
            {[...modulesRow2, ...modulesRow2, ...modulesRow2].map((mod, idx) => {
              const colorVar = colorVarMap[mod.color]
              const colorBg = colorBgMap[mod.color]
              const hex = colorHexMap[mod.color]
              return (
                <div
                  key={`r2-${idx}`}
                  className="group relative flex-shrink-0 w-72 rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-6 cursor-pointer transition-all duration-500 hover:-translate-y-2"
                  style={{
                    boxShadow: `0 4px 24px -8px ${hex}30, 0 2px 8px -4px rgba(0,0,0,0.06)`,
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.boxShadow = `0 8px 40px -6px ${hex}50, 0 4px 16px -4px ${hex}30, 0 0 0 1px ${hex}20`
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.boxShadow = `0 4px 24px -8px ${hex}30, 0 2px 8px -4px rgba(0,0,0,0.06)`
                  }}
                  onClick={() => navigate('/signup')}
                >
                  <div
                    className="absolute inset-0 rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-500 pointer-events-none"
                    style={{ background: `radial-gradient(circle at 50% 0%, ${hex}08, transparent 70%)` }}
                  />
                  <div
                    className="relative w-14 h-14 rounded-2xl flex items-center justify-center mb-4 transition-transform group-hover:scale-110"
                    style={{
                      background: `var(${colorBg})`,
                      boxShadow: `0 0 20px -4px ${hex}60`,
                    }}
                  >
                    <mod.icon className="w-7 h-7" style={{ color: `var(${colorVar})` }} />
                  </div>
                  <h3 className="relative text-base font-bold text-[var(--color-text)] mb-1">{t(mod.labelKey)}</h3>
                  <p className="relative text-sm text-[var(--color-text-secondary)] leading-relaxed">{t(mod.descKey)}</p>
                </div>
              )
            })}
          </div>
        </div>
      </section>

      {/* Use Cases */}
      <section id="useCases" className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.useCasesTitle')}</h2>
          <p className="text-[var(--color-text-secondary)] mt-3 max-w-2xl mx-auto">{t('landing.useCasesSubtitle')}</p>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {useCases.map((uc, idx) => (
            <div
              key={idx}
              className={`group relative rounded-2xl border border-[var(--color-border)] bg-gradient-to-br ${uc.bgGradient} p-6 hover:-translate-y-1 transition-all duration-300 cursor-pointer overflow-hidden`}
              style={{ boxShadow: `0 4px 24px -8px ${uc.color}20` }}
              onMouseEnter={(e) => { e.currentTarget.style.boxShadow = `0 8px 40px -6px ${uc.color}40` }}
              onMouseLeave={(e) => { e.currentTarget.style.boxShadow = `0 4px 24px -8px ${uc.color}20` }}
              onClick={() => navigate('/signup')}
            >
              <div
                className="absolute -top-8 -right-8 w-32 h-32 rounded-full opacity-10 group-hover:opacity-20 transition-opacity"
                style={{ background: uc.color }}
              />
              <div
                className="relative w-14 h-14 rounded-2xl flex items-center justify-center mb-4 transition-transform group-hover:scale-110"
                style={{ background: `${uc.color}20`, boxShadow: `0 0 24px -4px ${uc.color}50` }}
              >
                <uc.icon className="w-7 h-7" style={{ color: uc.color }} />
              </div>
              <h3 className="relative text-lg font-bold text-[var(--color-text)] mb-2">{t(`landing.useCases.${uc.key}.title`)}</h3>
              <p className="relative text-sm text-[var(--color-text-secondary)] leading-relaxed">{t(`landing.useCases.${uc.key}.desc`)}</p>
              <div className="relative mt-4 flex items-center gap-1 text-sm font-medium" style={{ color: uc.color }}>
                <span>{t('landing.getStarted')}</span>
                <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* ROI Stats */}
      <section className="bg-gradient-to-br from-[#1E2A4A] via-[#2D7D6F]/40 to-[#C44536]/20 py-20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-3xl font-bold text-white">{t('landing.roiTitle')}</h2>
            <p className="text-white/70 mt-3 max-w-2xl mx-auto">{t('landing.roiSubtitle')}</p>
          </div>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-6">
            {roiStats.map((stat, idx) => (
              <div
                key={idx}
                className="relative rounded-2xl bg-white/10 backdrop-blur-sm border border-white/20 p-8 text-center overflow-hidden hover:scale-105 transition-transform duration-300"
              >
                <div className={`absolute inset-0 bg-gradient-to-br ${stat.bgGradient} opacity-10`} />
                <div className="relative">
                  <div className={`text-4xl lg:text-5xl font-bold bg-gradient-to-r ${stat.bgGradient} bg-clip-text text-transparent`}>
                    {t(`landing.roi.${stat.key}.value`)}
                  </div>
                  <div className="text-sm text-white/70 mt-3">{t(`landing.roi.${stat.key}.label`)}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Comparison Table */}
      <section className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.comparisonTitle')}</h2>
          <p className="text-[var(--color-text-secondary)] mt-3 max-w-2xl mx-auto">{t('landing.comparisonSubtitle')}</p>
        </div>
        <div className="overflow-x-auto rounded-2xl border border-[var(--color-border)] shadow-lg">
          <table className="w-full">
            <thead>
              <tr className="bg-[var(--color-surface)]">
                <th className="px-5 py-4 text-left text-sm font-bold text-[var(--color-text)]">{t('landing.comparison.feature')}</th>
                <th className="px-5 py-4 text-center text-sm font-bold bg-gradient-to-br from-[#C44536]/15 to-[#E8A838]/10 text-[#C44536] rounded-tl-xl">{t('landing.comparison.onusuite')}</th>
                <th className="px-5 py-4 text-center text-sm font-semibold text-[var(--color-text-secondary)]">{t('landing.comparison.sage')}</th>
                <th className="px-5 py-4 text-center text-sm font-semibold text-[var(--color-text-secondary)]">{t('landing.comparison.quickbooks')}</th>
                <th className="px-5 py-4 text-center text-sm font-semibold text-[var(--color-text-secondary)]">{t('landing.comparison.excel')}</th>
              </tr>
            </thead>
            <tbody>
              {comparisonRows.map((row, idx) => (
                <tr key={idx} className={idx % 2 === 0 ? 'bg-[var(--color-surface)]' : 'bg-[var(--color-neutral-50)]'}>
                  <td className="px-5 py-4 text-sm font-medium text-[var(--color-text)]">{t(`landing.comparison.${row.featureKey}`)}</td>
                  <td className="px-5 py-4 text-center text-sm font-bold text-[#C44536] bg-[#C44536]/5">{t(`landing.comparison.${row.onusuiteKey}`)}</td>
                  <td className="px-5 py-4 text-center text-sm text-[var(--color-text-secondary)]">{t(`landing.comparison.${row.sageKey}`)}</td>
                  <td className="px-5 py-4 text-center text-sm text-[var(--color-text-secondary)]">{t(`landing.comparison.${row.qbKey}`)}</td>
                  <td className="px-5 py-4 text-center text-sm text-[var(--color-text-secondary)]">{t(`landing.comparison.${row.excelKey}`)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {/* Testimonials */}
      <section className="bg-[var(--color-surface)] border-y border-[var(--color-border)] py-20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.testimonialsTitle')}</h2>
            <p className="text-[var(--color-text-secondary)] mt-3 max-w-2xl mx-auto">{t('landing.testimonialsSubtitle')}</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {[1, 2, 3].map(i => (
              <div
                key={i}
                className="relative rounded-2xl border border-[var(--color-border)] bg-gradient-to-br from-[var(--color-surface)] to-[var(--color-neutral-50)] p-6"
                style={{ boxShadow: '0 4px 24px -8px rgba(0,0,0,0.08)' }}
              >
                <Quote
                  className="absolute top-4 right-4 w-10 h-10 opacity-10"
                  style={{ color: ['#C44536', '#2D7D6F', '#E8A838'][i - 1] }}
                />
                <div
                  className="w-12 h-12 rounded-full flex items-center justify-center mb-4 text-white font-bold text-lg"
                  style={{ background: `linear-gradient(135deg, ${['#C44536', '#2D7D6F', '#E8A838'][i - 1]}, ${['#E8755A', '#4FA89A', '#F5C56B'][i - 1]})` }}
                >
                  {t(`landing.testimonials.${i}.author`).charAt(0)}
                </div>
                <p className="text-sm text-[var(--color-text)] leading-relaxed mb-4 italic">
                  "{t(`landing.testimonials.${i}.quote`)}"
                </p>
                <div className="border-t border-[var(--color-border)] pt-3">
                  <div className="text-sm font-bold text-[var(--color-text)]">{t(`landing.testimonials.${i}.author`)}</div>
                  <div className="text-xs text-[var(--color-text-secondary)]">{t(`landing.testimonials.${i}.role`)}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Pricing */}
      <section id="pricing" className="bg-[var(--color-surface)] border-y border-[var(--color-border)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
          <div className="text-center mb-12">
            <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.pricing.title')}</h2>
            <p className="text-[var(--color-text-secondary)] mt-3 max-w-xl mx-auto">{t('landing.pricing.subtitle')}</p>
          </div>

          {/* Tier + Currency selectors */}
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4 mb-10">
            <div className="flex items-center gap-2">
              {tiers.map(tier => (
                <button
                  key={tier.id}
                  onClick={() => setSelectedTier(tier.id)}
                  className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                    selectedTier === tier.id
                      ? 'bg-[var(--color-primary)] text-white'
                      : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
                  }`}
                >
                  {t(tier.usersKey)}
                </button>
              ))}
            </div>
            <div className="flex items-center gap-3">
              {detectedCountry && (
                <span className="text-xs text-[var(--color-text-secondary)]">
                  📍 {detectedCountry}
                </span>
              )}
              <div className="relative">
                <button
                  onClick={() => setCurrencyOpen(!currencyOpen)}
                  className="flex items-center gap-2 px-4 py-2 rounded-lg border border-[var(--color-border)] text-sm font-medium text-[var(--color-text)] hover:bg-[var(--color-neutral-100)] transition-colors"
                >
                  <span>{localCurrency?.code || 'USD'}</span>
                  <ChevronDown className="w-4 h-4" />
                </button>
                {currencyOpen && (
                  <div className="absolute right-0 mt-2 w-40 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] shadow-lg z-10 max-h-64 overflow-y-auto">
                    {currencies.map(cur => (
                      <button
                        key={cur.code}
                        onClick={() => {
                          setLocalCurrency(cur)
                          setCurrencyOpen(false)
                          if (typeof localStorage !== 'undefined') {
                            localStorage.setItem('detected_currency', cur.code)
                          }
                        }}
                        className={`w-full text-left px-4 py-2 text-sm hover:bg-[var(--color-neutral-100)] transition-colors first:rounded-t-lg last:rounded-b-lg ${
                          localCurrency?.code === cur.code ? 'font-bold text-[var(--color-primary)]' : 'text-[var(--color-text)]'
                        }`}
                      >
                        {cur.code} — {cur.symbol}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Pricing cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {plans.map(plan => (
              <div
                key={plan.id}
                className={`relative rounded-2xl border-2 p-6 ${
                  plan.highlighted
                    ? 'border-[var(--color-primary)] bg-[var(--color-neutral-50)] shadow-lg'
                    : 'border-[var(--color-border)] bg-[var(--color-surface)]'
                }`}
              >
                {plan.highlighted && (
                  <div className="absolute -top-3 left-1/2 -translate-x-1/2 px-3 py-1 rounded-full bg-[var(--color-primary)] text-white text-xs font-bold">
                    {t('landing.pricing.popular')}
                  </div>
                )}
                <h3 className="text-lg font-bold text-[var(--color-text)]">{t(plan.nameKey)}</h3>
                <p className="text-sm text-[var(--color-text-secondary)] mt-1 mb-4">{t(plan.descKey)}</p>
                <div className="mb-4">
                  <div className="flex items-baseline gap-1">
                    <span className="text-3xl font-bold text-[var(--color-text)]">
                      ${plan.prices[selectedTier as keyof typeof plan.prices]}
                    </span>
                    <span className="text-sm text-[var(--color-text-secondary)]">{t('landing.pricing.perMonth')}</span>
                  </div>
                  {localCurrency && localCurrency.code !== 'USD' && (
                    <p className="text-sm text-[var(--color-text-secondary)] mt-1">
                      ≈ {formatPrice(plan.prices[selectedTier as keyof typeof plan.prices], localCurrency)} {t('landing.pricing.perMonth')}
                    </p>
                  )}
                </div>
                <p className="text-xs text-[var(--color-text-secondary)] mb-4">{t(plan.modulesKey)}</p>
                <button
                  onClick={() => navigate('/signup')}
                  className={`w-full py-2.5 rounded-xl font-semibold text-sm transition-colors ${
                    plan.highlighted
                      ? 'bg-[var(--color-primary)] text-white hover:opacity-90'
                      : 'border border-[var(--color-border)] text-[var(--color-text)] hover:bg-[var(--color-neutral-100)]'
                  }`}
                >
                  {t('landing.pricing.startTrial')}
                </button>
              </div>
            ))}
          </div>

          {/* Pricing info */}
          <div className="mt-8 flex flex-wrap items-center justify-center gap-6 text-sm text-[var(--color-text-secondary)]">
            <span className="flex items-center gap-2"><Clock className="w-4 h-4" /> {t('landing.pricing.trial45')}</span>
            <span className="flex items-center gap-2"><RefreshCw className="w-4 h-4" /> {t('landing.pricing.migrationFree')}</span>
            <span className="flex items-center gap-2"><Check className="w-4 h-4" /> {t('landing.pricing.annualDiscount')}</span>
            <span className="flex items-center gap-2"><Server className="w-4 h-4" /> {t('landing.pricing.multiCompany')}</span>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold text-[var(--color-text)]">{t('landing.faq.title')}</h2>
        </div>
        <div className="space-y-3">
          {faqItems.map((item, idx) => (
            <div key={idx} className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden">
              <button
                onClick={() => setOpenFaq(openFaq === idx ? null : idx)}
                className="w-full flex items-center justify-between px-5 py-4 text-left"
              >
                <span className="text-sm font-semibold text-[var(--color-text)]">{t(item.qKey)}</span>
                {openFaq === idx ? <Minus className="w-4 h-4 text-[var(--color-text-secondary)] flex-shrink-0" /> : <Plus className="w-4 h-4 text-[var(--color-text-secondary)] flex-shrink-0" />}
              </button>
              {openFaq === idx && (
                <div className="px-5 pb-4 text-sm text-[var(--color-text-secondary)] leading-relaxed">
                  {t(item.aKey)}
                </div>
              )}
            </div>
          ))}
        </div>
      </section>

      {/* CTA section */}
      <section className="relative overflow-hidden bg-gradient-to-br from-[#1E2A4A] via-[#1E2A4A] to-[#C44536]/30">
        <img
          src="/brand/founder-office.png"
          alt=""
          className="absolute inset-0 w-full h-full object-cover opacity-10 pointer-events-none"
          aria-hidden="true"
        />
        <div className="relative max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-20 text-center text-white">
          <h2 className="text-3xl font-bold">{t('landing.ctaTitle')}</h2>
          <p className="text-white/80 mt-4 max-w-xl mx-auto">{t('landing.ctaSubtitle')}</p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mt-8">
            <button
              onClick={() => navigate('/signup')}
              className="inline-flex items-center gap-2 px-8 py-3 rounded-xl bg-white text-[#1E2A4A] font-semibold hover:bg-white/90 transition-colors shadow-lg"
            >
              {t('landing.ctaStart')}
              <ArrowRight className="w-4 h-4" />
            </button>
            <a
              href="mailto:contact@onusuite.com"
              className="inline-flex items-center gap-2 px-8 py-3 rounded-xl border border-white/30 text-white font-semibold hover:bg-white/10 transition-colors"
            >
              {t('landing.ctaContact')}
            </a>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-[var(--color-border)] bg-[var(--color-surface)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mb-8">
            <div>
              <div className="flex items-center gap-3 mb-4">
                <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#C44536] to-[#1E2A4A] flex items-center justify-center">
                  <span className="text-white font-bold text-sm">O</span>
                </div>
                <span className="text-sm font-bold text-[var(--color-text)]">Onusuite</span>
              </div>
              <p className="text-xs text-[var(--color-text-secondary)]">{t('landing.tagline')}</p>
            </div>
            <div>
              <h4 className="text-xs font-bold text-[var(--color-text)] uppercase mb-3">{t('landing.footer.product')}</h4>
              <ul className="space-y-2">
                <li><a href="#why" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.nav.why')}</a></li>
                <li><a href="#features" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.nav.features')}</a></li>
                <li><a href="#modules" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.nav.modules')}</a></li>
                <li><a href="#pricing" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.nav.pricing')}</a></li>
              </ul>
            </div>
            <div>
              <h4 className="text-xs font-bold text-[var(--color-text)] uppercase mb-3">{t('landing.footer.company')}</h4>
              <ul className="space-y-2">
                <li><a href="#faq" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.nav.faq')}</a></li>
                <li><a href="mailto:contact@onusuite.com" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.footer.contact')}</a></li>
                <li><button onClick={() => navigate('/signup')} className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.footer.tryFree')}</button></li>
              </ul>
            </div>
            <div>
              <h4 className="text-xs font-bold text-[var(--color-text)] uppercase mb-3">{t('landing.footer.legal')}</h4>
              <ul className="space-y-2">
                <li><Link to="/terms" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)] flex items-center gap-1"><FileText className="w-3 h-3" /> {t('landing.footer.terms')}</Link></li>
                <li><Link to="/privacy" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)] flex items-center gap-1"><Lock className="w-3 h-3" /> {t('landing.footer.privacy')}</Link></li>
              </ul>
            </div>
          </div>
          <div className="border-t border-[var(--color-border)] pt-6 flex flex-col sm:flex-row items-center justify-between gap-4">
            <p className="text-xs text-[var(--color-text-secondary)]">{t('landing.copyright')}</p>
            <p className="text-xs text-[var(--color-text-secondary)]">1 USD = 1 EUR</p>
          </div>
        </div>
      </footer>
    </div>
  )
}
