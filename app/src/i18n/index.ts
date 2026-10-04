import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import LanguageDetector from 'i18next-browser-languagedetector'

export const SUPPORTED_LANGUAGES = ['fr', 'en', 'ar'] as const
export type SupportedLanguage = (typeof SUPPORTED_LANGUAGES)[number]

export const LANGUAGE_LABELS: Record<SupportedLanguage, { label: string; flag: string; dir: 'ltr' | 'rtl' }> = {
  fr: { label: 'Français', flag: '🇫🇷', dir: 'ltr' },
  en: { label: 'English', flag: '🇬🇧', dir: 'ltr' },
  ar: { label: 'العربية', flag: '🇲🇦', dir: 'rtl' },
}

export const ALL_NAMESPACES = [
  'common', 'nav', 'auth', 'sales', 'purchases', 'accounting',
  'banking', 'treasury', 'stock', 'production', 'hr', 'payroll', 'assets', 'reports', 'settings', 'errors', 'features', 'crm', 'pos', 'demat', 'employee', 'taskManagement', 'documents', 'crossModule',
] as const

// PRF-02 : Chargement dynamique des traductions pour réduire le chunk initial
// Au lieu d'importer les 75 fichiers JSON statiquement (~500 KB),
// on les charge dynamiquement selon la langue détectée.
const localeLoaders: Record<string, () => Promise<Record<string, any>>> = {
  fr: () => import('./locales/fr').then(m => ({
    common: m.common, nav: m.nav, auth: m.auth, sales: m.sales, purchases: m.purchases,
    accounting: m.accounting, banking: m.banking, treasury: m.treasury, stock: m.stock,
    production: m.production, hr: m.hr, payroll: m.payroll, assets: m.assets,
    reports: m.reports, settings: m.settings, errors: m.errors, features: m.features,
    crm: m.crm, pos: m.pos, demat: m.demat, employee: m.employee,
    taskManagement: m.taskManagement, documents: m.documents, crossModule: m.crossModule,
  })),
  en: () => import('./locales/en').then(m => ({
    common: m.common, nav: m.nav, auth: m.auth, sales: m.sales, purchases: m.purchases,
    accounting: m.accounting, banking: m.banking, treasury: m.treasury, stock: m.stock,
    production: m.production, hr: m.hr, payroll: m.payroll, assets: m.assets,
    reports: m.reports, settings: m.settings, errors: m.errors, features: m.features,
    crm: m.crm, pos: m.pos, demat: m.demat, employee: m.employee,
    taskManagement: m.taskManagement, documents: m.documents, crossModule: m.crossModule,
  })),
  ar: () => import('./locales/ar').then(m => ({
    common: m.common, nav: m.nav, auth: m.auth, sales: m.sales, purchases: m.purchases,
    accounting: m.accounting, banking: m.banking, treasury: m.treasury, stock: m.stock,
    production: m.production, hr: m.hr, payroll: m.payroll, assets: m.assets,
    reports: m.reports, settings: m.settings, errors: m.errors, features: m.features,
    crm: m.crm, pos: m.pos, demat: m.demat, employee: m.employee,
    taskManagement: m.taskManagement, documents: m.documents, crossModule: m.crossModule,
  })),
}

// Initialiser i18n sans resources — elles seront chargées dynamiquement
i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {},
    fallbackLng: 'en',
    supportedLngs: SUPPORTED_LANGUAGES as unknown as string[],
    nonExplicitSupportedLngs: true,
    ns: ALL_NAMESPACES as unknown as string[],
    defaultNS: 'common',
    interpolation: {
      escapeValue: false,
    },
    detection: {
      order: ['localStorage', 'navigator'],
      lookupLocalStorage: 'i18nextLng',
      caches: ['localStorage'],
      convertDetectedLanguage: (lng: string) => {
        const base = lng.split('-')[0]
        if ((SUPPORTED_LANGUAGES as readonly string[]).includes(base)) {
          return base
        }
        return 'en'
      },
    },
    react: {
      useSuspense: false,
    },
  })

// Charger la langue détectée au démarrage
const detectedLang = (i18n.language || 'en').split('-')[0] as SupportedLanguage
const loadPromise = localeLoaders[detectedLang]?.().then(resources => {
  for (const [ns, data] of Object.entries(resources)) {
    i18n.addResourceBundle(detectedLang, ns, data, true, true)
  }
}) || Promise.resolve()

// Exporter une promesse que main.tsx peut attendre si nécessaire
export const i18nReady = loadPromise

export async function setLanguage(lng: SupportedLanguage) {
  // Charger les resources si pas déjà chargées
  if (!i18n.hasResourceBundle(lng, 'common')) {
    const resources = await localeLoaders[lng]()
    for (const [ns, data] of Object.entries(resources)) {
      i18n.addResourceBundle(lng, ns, data, true, true)
    }
  }
  await i18n.changeLanguage(lng)
  const dir = LANGUAGE_LABELS[lng].dir
  document.documentElement.dir = dir
  document.documentElement.lang = lng
}

export function initRtl() {
  const currentLang = (i18n.language || 'en').split('-')[0] as SupportedLanguage
  const dir = LANGUAGE_LABELS[currentLang]?.dir || 'ltr'
  document.documentElement.dir = dir
  document.documentElement.lang = currentLang
}

i18n.on('languageChanged', (lng) => {
  const lang = (lng || 'en').split('-')[0] as SupportedLanguage
  const dir = LANGUAGE_LABELS[lang]?.dir || 'ltr'
  document.documentElement.dir = dir
  document.documentElement.lang = lang
})

export default i18n
