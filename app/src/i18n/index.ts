import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import LanguageDetector from 'i18next-browser-languagedetector'

import frCommon from './locales/fr/common.json'
import frNav from './locales/fr/nav.json'
import frAuth from './locales/fr/auth.json'
import frSales from './locales/fr/sales.json'
import frPurchases from './locales/fr/purchases.json'
import frAccounting from './locales/fr/accounting.json'
import frBanking from './locales/fr/banking.json'
import frTreasury from './locales/fr/treasury.json'
import frStock from './locales/fr/stock.json'
import frProduction from './locales/fr/production.json'
import frHr from './locales/fr/hr.json'
import frReports from './locales/fr/reports.json'
import frSettings from './locales/fr/settings.json'
import frErrors from './locales/fr/errors.json'
import frFeatures from './locales/fr/features.json'

import enCommon from './locales/en/common.json'
import enNav from './locales/en/nav.json'
import enAuth from './locales/en/auth.json'
import enSales from './locales/en/sales.json'
import enPurchases from './locales/en/purchases.json'
import enAccounting from './locales/en/accounting.json'
import enBanking from './locales/en/banking.json'
import enTreasury from './locales/en/treasury.json'
import enStock from './locales/en/stock.json'
import enProduction from './locales/en/production.json'
import enHr from './locales/en/hr.json'
import enReports from './locales/en/reports.json'
import enSettings from './locales/en/settings.json'
import enErrors from './locales/en/errors.json'
import enFeatures from './locales/en/features.json'

import arCommon from './locales/ar/common.json'
import arNav from './locales/ar/nav.json'
import arAuth from './locales/ar/auth.json'
import arSales from './locales/ar/sales.json'
import arPurchases from './locales/ar/purchases.json'
import arAccounting from './locales/ar/accounting.json'
import arBanking from './locales/ar/banking.json'
import arTreasury from './locales/ar/treasury.json'
import arStock from './locales/ar/stock.json'
import arProduction from './locales/ar/production.json'
import arHr from './locales/ar/hr.json'
import arReports from './locales/ar/reports.json'
import arSettings from './locales/ar/settings.json'
import arErrors from './locales/ar/errors.json'
import arFeatures from './locales/ar/features.json'

export const SUPPORTED_LANGUAGES = ['fr', 'en', 'ar'] as const
export type SupportedLanguage = (typeof SUPPORTED_LANGUAGES)[number]

export const LANGUAGE_LABELS: Record<SupportedLanguage, { label: string; flag: string; dir: 'ltr' | 'rtl' }> = {
  fr: { label: 'Français', flag: '🇫🇷', dir: 'ltr' },
  en: { label: 'English', flag: '🇬🇧', dir: 'ltr' },
  ar: { label: 'العربية', flag: '🇲🇦', dir: 'rtl' },
}

export const ALL_NAMESPACES = [
  'common', 'nav', 'auth', 'sales', 'purchases', 'accounting',
  'banking', 'treasury', 'stock', 'production', 'hr', 'reports', 'settings', 'errors', 'features',
] as const

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      fr: {
        common: frCommon,
        nav: frNav,
        auth: frAuth,
        sales: frSales,
        purchases: frPurchases,
        accounting: frAccounting,
        banking: frBanking,
        treasury: frTreasury,
        stock: frStock,
        production: frProduction,
        hr: frHr,
        reports: frReports,
        settings: frSettings,
        errors: frErrors,
        features: frFeatures,
      },
      en: {
        common: enCommon,
        nav: enNav,
        auth: enAuth,
        sales: enSales,
        purchases: enPurchases,
        accounting: enAccounting,
        banking: enBanking,
        treasury: enTreasury,
        stock: enStock,
        production: enProduction,
        hr: enHr,
        reports: enReports,
        settings: enSettings,
        errors: enErrors,
        features: enFeatures,
      },
      ar: {
        common: arCommon,
        nav: arNav,
        auth: arAuth,
        sales: arSales,
        purchases: arPurchases,
        accounting: arAccounting,
        banking: arBanking,
        treasury: arTreasury,
        stock: arStock,
        production: arProduction,
        hr: arHr,
        reports: arReports,
        settings: arSettings,
        errors: arErrors,
        features: arFeatures,
      },
    },
    fallbackLng: 'fr',
    supportedLngs: SUPPORTED_LANGUAGES as unknown as string[],
    ns: ALL_NAMESPACES as unknown as string[],
    defaultNS: 'common',
    interpolation: {
      escapeValue: false,
    },
    detection: {
      order: ['localStorage', 'navigator'],
      lookupLocalStorage: 'i18nextLng',
      caches: ['localStorage'],
    },
    react: {
      useSuspense: false,
    },
  })

export function setLanguage(lng: SupportedLanguage) {
  i18n.changeLanguage(lng)
  const dir = LANGUAGE_LABELS[lng].dir
  document.documentElement.dir = dir
  document.documentElement.lang = lng
}

export function initRtl() {
  const currentLang = (i18n.language || 'fr').split('-')[0] as SupportedLanguage
  const dir = LANGUAGE_LABELS[currentLang]?.dir || 'ltr'
  document.documentElement.dir = dir
  document.documentElement.lang = currentLang
}

i18n.on('languageChanged', (lng) => {
  const lang = (lng || 'fr').split('-')[0] as SupportedLanguage
  const dir = LANGUAGE_LABELS[lang]?.dir || 'ltr'
  document.documentElement.dir = dir
  document.documentElement.lang = lang
})

export default i18n
