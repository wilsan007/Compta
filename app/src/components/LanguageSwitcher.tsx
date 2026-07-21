import { useState, useRef, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { Globe, Check, ChevronDown } from 'lucide-react'
import { SUPPORTED_LANGUAGES, LANGUAGE_LABELS, setLanguage } from '../i18n'
import type { SupportedLanguage } from '../i18n'

export function LanguageSwitcher({ compact = false }: { compact?: boolean }) {
  const { i18n } = useTranslation()
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const currentLang = (i18n.language || 'fr').split('-')[0] as SupportedLanguage

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  function handleSelect(lng: SupportedLanguage) {
    setLanguage(lng)
    setOpen(false)
  }

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] dark:hover:bg-[var(--color-neutral-800)] transition-colors"
        aria-label="Language switcher"
      >
        <Globe className="w-4 h-4" />
        {!compact && (
          <span className="hidden sm:inline">
            {LANGUAGE_LABELS[currentLang]?.label || 'Français'}
          </span>
        )}
        <ChevronDown className="w-3 h-3" />
      </button>

      {open && (
        <div className="absolute right-0 mt-2 w-44 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] shadow-lg z-50 py-1">
          {SUPPORTED_LANGUAGES.map((lng) => (
            <button
              key={lng}
              onClick={() => handleSelect(lng)}
              className="flex items-center justify-between w-full px-3 py-2 text-sm text-[var(--color-text)] hover:bg-[var(--color-neutral-100)] dark:hover:bg-[var(--color-neutral-800)] transition-colors"
            >
              <span className="flex items-center gap-2">
                <span className="text-base">{LANGUAGE_LABELS[lng].flag}</span>
                {LANGUAGE_LABELS[lng].label}
              </span>
              {currentLang === lng && <Check className="w-4 h-4 text-[var(--color-primary)]" />}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
