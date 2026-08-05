import * as Sentry from '@sentry/react'

const SENTRY_DSN = import.meta.env.VITE_SENTRY_DSN || ''
const isProd = import.meta.env.PROD

export function initSentry() {
  if (!SENTRY_DSN) {
    if (isProd) {
      console.warn('[Sentry] VITE_SENTRY_DSN not set — error monitoring disabled in production!')
    }
    return
  }

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

export { Sentry }
