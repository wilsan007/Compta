import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './i18n'
import { initRtl } from './i18n'
import { initSentry } from './lib/sentry'
import App from './App.tsx'

// PRF-02 : Sentry lazy-loaded — init asynchrone pour ne pas bloquer le rendu
initSentry().catch(() => {})
initRtl()

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
