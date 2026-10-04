import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { ArrowLeft } from 'lucide-react'

export function TermsPage() {
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
        <h1 className="text-3xl font-bold text-[var(--color-text)] mb-2">{t('landing.terms.title')}</h1>
        <p className="text-sm text-[var(--color-text-secondary)] mb-8">{t('landing.terms.lastUpdated')}</p>

        <div className="prose prose-sm max-w-none space-y-6 text-[var(--color-text-secondary)]">
          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.acceptance.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.acceptance.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.eligibility.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.eligibility.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.accounts.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.accounts.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.trial.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.trial.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.subscriptions.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.subscriptions.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.acceptableUse.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.acceptableUse.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.data.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.data.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.ip.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.ip.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.disclaimer.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.disclaimer.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.liability.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.liability.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.termination.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.termination.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.governing.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.governing.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.changes.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.changes.body')}</p>
          </section>

          <section>
            <h2 className="text-lg font-bold text-[var(--color-text)] mb-2">{t('landing.terms.contact.title')}</h2>
            <p className="text-sm leading-relaxed">{t('landing.terms.contact.body')}</p>
          </section>
        </div>

        <div className="mt-12 pt-8 border-t border-[var(--color-border)] flex flex-col sm:flex-row items-center justify-between gap-4">
          <p className="text-xs text-[var(--color-text-secondary)]">{t('landing.copyright')}</p>
          <div className="flex items-center gap-4">
            <Link to="/privacy" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.footer.privacy')}</Link>
            <Link to="/" className="text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">{t('landing.footer.tryFree')}</Link>
          </div>
        </div>
      </div>
    </div>
  )
}
