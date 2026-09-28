import { Component, type ErrorInfo, type ReactNode } from 'react'
import { captureException } from '@/lib/sentry'

interface Props {
  children: ReactNode
  fallback?: ReactNode
  // M11 (audit du 28/09/2026) : une page qui plantait laissait l'écran d'erreur
  // affiché sur TOUTES les routes suivantes. Quand la clé change (le chemin, pour
  // RouteErrorBoundary), l'erreur est oubliée et la nouvelle page s'affiche.
  resetKey?: string
}

interface State {
  hasError: boolean
  error?: Error
  resetKey?: string
}

export class AppErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, resetKey: this.props.resetKey }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true, error }
  }

  // La clé a changé depuis l'erreur : on l'oublie avant le rendu (sans second rendu).
  static getDerivedStateFromProps(props: Props, state: State): Partial<State> | null {
    if (props.resetKey !== state.resetKey) {
      return { hasError: false, error: undefined, resetKey: props.resetKey }
    }
    return null
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    captureException(error, { componentStack: errorInfo.componentStack })
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || (
        <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900">
          <div className="text-center p-8 max-w-md">
            <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-4">
              Une erreur est survenue
            </h1>
            <p className="text-gray-600 dark:text-gray-400 mb-6">
              L'application a rencontré une erreur inattendue. L'équipe a été notifiée.
            </p>
            <button
              onClick={() => window.location.reload()}
              className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            >
              Recharger la page
            </button>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}
