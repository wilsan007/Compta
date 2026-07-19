import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'

type Theme = 'light' | 'dark'

interface ThemeContextType {
  theme: Theme
  toggleTheme: () => void
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined)

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<Theme>(() => {
    const saved = localStorage.getItem('compta-theme') as Theme | null
    if (saved) return saved
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  })

  useEffect(() => {
    const root = document.documentElement
    if (theme === 'dark') {
      root.classList.add('dark')
      root.style.setProperty('color-scheme', 'dark')
      root.style.setProperty('--color-surface', '#1a1b23')
      root.style.setProperty('--color-background', '#131418')
      root.style.setProperty('--color-text', '#e4e6ea')
      root.style.setProperty('--color-text-secondary', '#9ca3af')
      root.style.setProperty('--color-border', '#2e3038')
      root.style.setProperty('--color-neutral-50', '#1e1f26')
      root.style.setProperty('--color-neutral-100', '#25262e')
      root.style.setProperty('--color-neutral-200', '#2e3038')
      root.style.setProperty('--color-neutral-300', '#3a3d47')
      root.style.setProperty('--color-neutral-400', '#5e6370')
      root.style.setProperty('--color-neutral-500', '#7a808c')
      root.style.setProperty('--color-neutral-600', '#9ca3af')
      root.style.setProperty('--color-neutral-700', '#b8bdc7')
      root.style.setProperty('--color-neutral-800', '#d1d5db')
      root.style.setProperty('--color-neutral-900', '#e4e6ea')
    } else {
      root.classList.remove('dark')
      root.style.setProperty('color-scheme', 'light')
      root.style.setProperty('--color-surface', '#ffffff')
      root.style.setProperty('--color-background', '#f4f5f7')
      root.style.setProperty('--color-text', '#172b4d')
      root.style.setProperty('--color-text-secondary', '#5e6c84')
      root.style.setProperty('--color-border', '#dfe1e6')
      root.style.setProperty('--color-neutral-50', '#f4f5f7')
      root.style.setProperty('--color-neutral-100', '#ebecf0')
      root.style.setProperty('--color-neutral-200', '#dfe1e6')
      root.style.setProperty('--color-neutral-300', '#c1c7d0')
      root.style.setProperty('--color-neutral-400', '#97a0af')
      root.style.setProperty('--color-neutral-500', '#6b778c')
      root.style.setProperty('--color-neutral-600', '#5e6c84')
      root.style.setProperty('--color-neutral-700', '#42526e')
      root.style.setProperty('--color-neutral-800', '#344563')
      root.style.setProperty('--color-neutral-900', '#172b4d')
    }
    localStorage.setItem('compta-theme', theme)
  }, [theme])

  const toggleTheme = () => setTheme((t) => (t === 'light' ? 'dark' : 'light'))

  return <ThemeContext.Provider value={{ theme, toggleTheme }}>{children}</ThemeContext.Provider>
}

export function useTheme() {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider')
  return ctx
}
