import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatCurrency(amount: number, currency = 'EUR'): string {
  return new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency,
    minimumFractionDigits: 2,
  }).format(amount)
}

export function formatDate(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date
  return new Intl.DateTimeFormat('fr-FR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(d)
}

export function formatNumber(num: number): string {
  return new Intl.NumberFormat('fr-FR').format(num)
}

export function getInitials(name: string): string {
  return name
    .split(' ')
    .map((n) => n[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}

const statusTranslations: Record<string, string> = {
  draft: 'Brouillon',
  sent: 'Envoyée',
  viewed: 'Vue',
  paid: 'Payée',
  overdue: 'En retard',
  cancelled: 'Annulée',
  partial: 'Partielle',
  accepted: 'Accepté',
  rejected: 'Refusé',
  pending: 'En attente',
  approved: 'Approuvé',
  submitted: 'Soumise',
  active: 'Actif',
  inactive: 'Inactif',
  on_leave: 'Congé',
  completed: 'Terminé',
  on_hold: 'En pause',
  fully_depreciated: 'Amorti',
  disposed: 'Cédé',
  recurring: 'Récurrente',
  applied: 'Appliqué',
}

export function translateStatus(status: string): string {
  return statusTranslations[status] || status
}
