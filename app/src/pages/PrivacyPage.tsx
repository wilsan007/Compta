import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { ArrowLeft } from 'lucide-react'

export function PrivacyPage() {
  const { t } = useTranslation(['nav'])

  return (
    <div className="min-h-screen bg-[var(--color-neutral-50)]">
      <header className="sticky top-0 z-50 bg-[var(--color-surface)]/80 backdrop-blur-md border-b border-[var(--color-border)]">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#C44536] to-[#1E2A4A] flex items-center justify-center shadow-md">
              <span className="text-white font-bold text-lg">O</span>
            </div>
            <span className="text-lg font-bold text-[var(--color-text)]">Onusuite</span>
          </Link>
          <Link to="/" className="flex items-center gap-2 text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors">
            <ArrowLeft className="w-4 h-4" />
            {t('landing.footer.tryFree')}
          </Link>
        </div>
      </header>

      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <h1 className="text-3xl font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.title')}</h1>
        <p className="text-sm text-[var(--color-text-secondary)] mb-8">{t('landing.privacy.lastUpdated')}</p>

        <div className="prose prose-sm max-w-none space-y-6 text-[var(--color-text-secondary)]">
          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.intro.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.intro.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.collection.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.collection.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.use.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.use.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.sharing.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.sharing.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.security.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.security.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.retention.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.retention.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.rights.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.rights.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.cookies.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.cookies.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.children.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.children.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.international.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.international.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.changes.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.changes.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.privacy.contact.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.privacy.contact.body')}</p>
          </section>
        </div>

        <div className="mt-12 pt-8 border-t border-[var(--color-border)] flex flex-col sm:flex-row items-center justify-between gap-4">
          <p className="text-xs text-[var(--color-text-secondary)]">{t('landing.copyright')}</p>
          <div className="flex items-center gap-4">
            <Link to="/terms" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.footer.terms')}</Link>
            <Link to="/" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.footer.tryFree')}</Link>
          </div>
        </div>
      </div>
    </div>
  )
}
