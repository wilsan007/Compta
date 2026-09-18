import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './i18n'
import { initRtl } from './i18n'
import { initSentry } from './lib/sentry'
import { installGlobalRejectionHandler } from './lib/silentFailureGuard'
import App from './App.tsx'

// PRF-02 : Sentry lazy-loaded — init asynchrone pour ne pas bloquer le rendu
initSentry().catch(() => {})

// LOT7-01 : `silentFailureGuard` avait été écrit pour ce projet — avec son mode
// d'emploi dans son en-tête — mais n'avait jamais été branché : les rejets de
// promesse et les erreurs globales passaient donc inaperçus. Inerte par défaut,
// il ne rapporte rien tant que VITE_SILENT_FAILURE_GUARD=true n'est pas posé.
installGlobalRejectionHandler()

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
