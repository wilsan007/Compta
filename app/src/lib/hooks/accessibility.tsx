// UX-02 : Composants d'accessibilité
import { useEffect, useRef, useState, type ReactNode } from 'react'

// Région aria-live pour annoncer les changements dynamiques
export function LiveRegion({ children, politeness = 'polite' }: { children: ReactNode; politeness?: 'polite' | 'assertive' }) {
  return (
    <div aria-live={politeness} aria-atomic="true" className="sr-only">
      {children}
    </div>
  )
}

// Bouton accessible pour remplacer les div/span cliquables
export function AccessibleButton({
  children,
  onClick,
  className,
  ariaLabel,
  disabled,
  type = 'button',
}: {
  children: ReactNode
  onClick?: () => void
  className?: string
  ariaLabel?: string
  disabled?: boolean
  type?: 'button' | 'submit'
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      className={className}
      aria-label={ariaLabel}
      disabled={disabled}
    >
      {children}
    </button>
  )
}

// Hook pour gérer le piège de focus dans les modales
export function useFocusTrap(active: boolean) {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!active || !containerRef.current) return

    const container = containerRef.current
    const focusableElements = container.querySelectorAll<HTMLElement>(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    if (focusableElements.length === 0) return

    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]

    firstElement.focus()

    const handleTabKey = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return
      if (e.shiftKey) {
        if (document.activeElement === firstElement) {
          e.preventDefault()
          lastElement.focus()
        }
      } else {
        if (document.activeElement === lastElement) {
          e.preventDefault()
          firstElement.focus()
        }
      }
    }

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        // Laisser le parent gérer la fermeture
        container.dispatchEvent(new CustomEvent('escape'))
      }
    }

    container.addEventListener('keydown', handleTabKey)
    container.addEventListener('keydown', handleEscape)

    return () => {
      container.removeEventListener('keydown', handleTabKey)
      container.removeEventListener('keydown', handleEscape)
    }
  }, [active])

  return containerRef
}

// Hook pour annoncer des notifications aux lecteurs d'écran
export function useAnnouncement() {
  const [announcement, setAnnouncement] = useState('')

  const announce = (message: string) => {
    setAnnouncement('')
    setTimeout(() => setAnnouncement(message), 50)
  }

  return { announcement, announce, LiveRegion: () => <LiveRegion>{announcement}</LiveRegion> }
}
