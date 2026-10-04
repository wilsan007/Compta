// PRF-02 : Sentry lazy-loaded pour réduire le chunk initial
// @sentry/react fait ~1MB — ne doit pas être dans le chunk initial

const SENTRY_DSN = import.meta.env.VITE_SENTRY_DSN || ''
const isProd = import.meta.env.PROD

let sentryInitialized = false

export async function initSentry() {
  if (!SENTRY_DSN || sentryInitialized) return
  sentryInitialized = true

  const Sentry = await import('@sentry/react')
  Sentry.init({
    dsn: SENTRY_DSN,
    environment: import.meta.env.MODE,
    tracesSampleRate: isProd ? 0.1 : 1.0,
    profilesSampleRate: isProd ? 0.1 : 1.0,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({
        maskAllText: true,
        blockAllMedia: true,
      }),
    ],
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 1.0,
    beforeSend(event) {
      if (event.request?.url?.includes('localhost')) return null
      return event
    },
  })
}

// Wrapper async pour captureException — charge Sentry à la demande
export async function captureException(error: unknown, extra?: Record<string, unknown>) {
  if (!SENTRY_DSN) {
    console.error('[Sentry disabled]', error, extra)
    return
  }
  const Sentry = await import('@sentry/react')
  Sentry.captureException(error, extra ? { extra } : undefined)
}
