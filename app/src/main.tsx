import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './i18n'
import { initRtl } from './i18n'
import { initAntiInspection } from './lib/antiInspection'
import { initSentry } from './lib/sentry'
import App from './App.tsx'

initSentry()
initRtl()
initAntiInspection()

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {})
  })
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
