import { NavLink, Outlet } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Home, Calendar, User, Receipt, MessageSquare, FileText } from 'lucide-react'

export function EmployeeLayout() {
  const { t } = useTranslation('employee')
  const navItems = [
    { to: '/employee', icon: Home, label: t('nav.dashboard'), end: true },
    { to: '/employee/leaves', icon: Calendar, label: t('nav.leaves'), end: false },
    { to: '/employee/profile', icon: User, label: t('nav.profile'), end: false },
    { to: '/employee/expenses', icon: Receipt, label: t('nav.expenses'), end: false },
    { to: '/employee/interviews', icon: MessageSquare, label: t('nav.interviews'), end: false },
    { to: '/employee/documents', icon: FileText, label: t('nav.documents'), end: false },
  ]

  return (
    <div className="min-h-screen flex flex-col lg:flex-row">
      <nav className="hidden lg:flex flex-col w-56 border-r border-[var(--color-border)] bg-[var(--color-surface)] p-3 gap-1">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              `flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                isActive
                  ? 'bg-[var(--color-primary)] text-white'
                  : 'text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)]'
              }`
            }
          >
            <item.icon className="w-4 h-4" />
            {item.label}
          </NavLink>
        ))}
      </nav>

      <nav className="lg:hidden fixed bottom-0 left-0 right-0 z-50 flex justify-around bg-[var(--color-surface)] border-t border-[var(--color-border)] py-2">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              `flex flex-col items-center gap-0.5 px-2 py-1 text-xs ${
                isActive ? 'text-[var(--color-primary)]' : 'text-[var(--color-text-secondary)]'
              }`
            }
          >
            <item.icon className="w-5 h-5" />
            <span className="hidden sm:inline">{item.label}</span>
          </NavLink>
        ))}
      </nav>

      <main className="flex-1 p-4 lg:p-6 pb-20 lg:pb-6 overflow-y-auto">
        <Outlet />
      </main>
    </div>
  )
}
