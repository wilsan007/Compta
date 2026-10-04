import { useAuth } from '@/lib/auth'

/**
 * Droits de l'utilisateur courant sur une table, pour conditionner l'affichage
 * des actions. S'appuie sur l'unique matrice `hasPermission` (queries/misc.ts).
 *
 * Confort d'interface, pas protection : le contrôle s'exécute dans le navigateur.
 * Une règle opposable doit vivre dans une politique RLS ou un trigger.
 */
export function usePermission(table: string) {
  const { canPerform } = useAuth()
  return {
    canRead: canPerform(table, 'select'),
    canCreate: canPerform(table, 'insert'),
    canEdit: canPerform(table, 'update'),
    canDelete: canPerform(table, 'delete'),
  }
}
