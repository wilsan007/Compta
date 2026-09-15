import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { QuickAccessModal } from './QuickAccessModal'
import { Button, Input, Select, EmptyState, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getTenantUsers, inviteUser } from '@/lib/queries/misc'
import { useAuth } from '@/lib/auth'
import { useToast } from '@/lib/toast'
import { useModuleAwareAccess } from './useModuleAwareAccess'
import { getModuleRoles, type ModuleName } from '@/lib/moduleRoles'
import { Users, ExternalLink, UserPlus } from 'lucide-react'
import type { TenantUser } from '@/lib/queries/misc'
import type { ModuleRole } from '@/types/documents'

interface QuickUserAccessProps {
  onClose: () => void
  onSaved?: () => void
  forceInline?: boolean
  module?: ModuleName
}

/**
 * Cross-module Quick Access for tenant users (team members).
 * - If system module is active → shows a link to /settings/team
 * - If system module is NOT active → shows inline invite + list
 *
 * Uses the same `tenant_users` table and `inviteUser` query.
 */
export function QuickUserAccess({ onClose, onSaved, forceInline, module }: QuickUserAccessProps) {
  const { t } = useTranslation('crossModule')
  const { t: tHr } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { user } = useAuth()
  const { getAccessStrategy } = useModuleAwareAccess()

  const strategy = forceInline ? 'inline' : getAccessStrategy('system')
  const [users, setUsers] = useState<TenantUser[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const [email, setEmail] = useState('')
  const [name, setName] = useState('')
  const [role, setRole] = useState<TenantUser['role']>('viewer')
  const [moduleRole, setModuleRole] = useState<ModuleRole | ''>('')
  const [saving, setSaving] = useState(false)

  const moduleRoleOptions = module ? getModuleRoles(module) : []

  const loadData = useCallback(async () => {
    if (!user?.tenantId) return
    setLoading(true)
    try {
      setUsers(await getTenantUsers(user.tenantId))
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [user?.tenantId, tCommon, toast])

  useEffect(() => {
    if (strategy === 'inline') loadData().catch(err => console.error('loadData:', err))
  }, [strategy, loadData])

  async function handleInvite(e: React.FormEvent) {
    e.preventDefault()
    if (!email.trim() || !name.trim() || !user?.tenantId) return
    setSaving(true)
    try {
      const moduleRoles = (module && moduleRole) ? { [module]: moduleRole } : {}
      const result = await inviteUser({
        tenantId: user.tenantId,
        email: email.trim(),
        name: name.trim(),
        role,
        moduleRoles,
        invitedBy: user.id,
      })
      if (result.success) {
        toast('success', tCommon('common.success'), t('user.invited'))
        onSaved?.()
        await loadData()
        setShowForm(false)
        setEmail(''); setName(''); setModuleRole('')
      } else {
        toast('error', tCommon('common.error'), result.error || t('user.inviteError'))
      }
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  if (strategy === 'full' && !forceInline) {
    return (
      <QuickAccessModal title={t('user.title')} onClose={onClose}>
        <EmptyState
          icon={<Users className="w-8 h-8" />}
          title={t('user.moduleActive')}
          description={t('user.moduleActiveDescription')}
          action={
            <Link to="/settings/team" onClick={onClose}>
              <Button><ExternalLink className="w-4 h-4" /> {t('user.goToTeam')}</Button>
            </Link>
          }
        />
      </QuickAccessModal>
    )
  }

  return (
    <QuickAccessModal title={t('user.title')} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex justify-end">
          <Button size="sm" onClick={() => setShowForm(!showForm)}>
            <UserPlus className="w-4 h-4" /> {t('user.invite')}
          </Button>
        </div>

        {showForm && (
          <form onSubmit={handleInvite} className="space-y-3 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
            <Input label={t('user.name')} required value={name} onChange={(e) => setName(e.target.value)} />
            <Input label={t('user.email')} type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
            <Select
              label={t('user.role')}
              value={role}
              onChange={(e) => setRole(e.target.value as TenantUser['role'])}
              options={[
                { value: 'admin', label: t('user.roles.admin') },
                { value: 'accountant', label: t('user.roles.accountant') },
                { value: 'manager', label: t('user.roles.manager') },
                { value: 'viewer', label: t('user.roles.viewer') },
                { value: 'auditor', label: t('user.roles.auditor') },
              ]}
            />
            {module && moduleRoleOptions.length > 0 && (
              <Select
                label={tHr('team.moduleLabels.' + module)}
                value={moduleRole}
                onChange={(e) => setModuleRole(e.target.value as ModuleRole)}
                options={[
                  { value: '', label: '—' },
                  ...moduleRoleOptions.map(r => ({ value: r.value, label: tHr(r.labelKey.replace('hr:', '')) })),
                ]}
              />
            )}
            <div className="flex justify-end gap-2">
              <Button type="button" variant="secondary" size="sm" onClick={() => setShowForm(false)}>{tCommon('actions.cancel')}</Button>
              <Button type="submit" size="sm" disabled={saving}>{saving ? '...' : t('user.sendInvite')}</Button>
            </div>
          </form>
        )}

        {loading ? (
          <p className="text-sm text-[var(--color-text-secondary)] text-center py-8">{tCommon('common.loading')}</p>
        ) : users.length === 0 ? (
          <EmptyState
            icon={<Users className="w-8 h-8" />}
            title={t('user.noUsers')}
            description={t('user.noUsersDescription')}
            action={<Button size="sm" onClick={() => setShowForm(true)}><UserPlus className="w-4 h-4" /> {t('user.invite')}</Button>}
          />
        ) : (
          <Table headers={[t('user.name'), t('user.email'), t('user.role'), tCommon('common.status')]}>
            {users.slice(0, 20).map((u) => (
              <TableRow key={u.id}>
                <TableCell className="font-medium">{u.name}</TableCell>
                <TableCell className="text-sm">{u.email}</TableCell>
                <TableCell>
                  <Badge variant={u.role === 'admin' ? 'danger' : u.role === 'accountant' ? 'primary' : 'neutral'}>
                    {t(`user.roles.${u.role}`)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={u.status === 'active' ? 'success' : u.status === 'pending' ? 'warning' : 'neutral'}>
                    {tCommon(`status.${u.status}`)}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </div>
    </QuickAccessModal>
  )
}
