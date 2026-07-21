import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, Badge, Select, Input } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { useToast } from '@/lib/toast'
import {
  getTenantUsers, inviteUser, updateUserRole, revokeUser, reactivateUser, reinviteUser,
  ROLE_LABELS, ROLE_DESCRIPTIONS, PERMISSION_TABLES, PERMISSION_ACTIONS,
  type TenantUser,
} from '@/lib/queries'
import { Users, UserPlus, Loader2, Ban, RotateCcw, Send, Shield, Check } from 'lucide-react'

export function TeamPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { user } = useAuth()
  const [users, setUsers] = useState<TenantUser[]>([])
  const [loading, setLoading] = useState(true)
  const [showInvite, setShowInvite] = useState(false)
  const [editingUser, setEditingUser] = useState<TenantUser | null>(null)

  const loadData = useCallback(async () => {
    if (!user?.tenantId) return
    try {
      const data = await getTenantUsers(user.tenantId)
      setUsers(data)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [user?.tenantId, toast])

  useEffect(() => { loadData() }, [loadData])

  const isAdmin = user?.role === 'admin'

  if (!isAdmin) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('team.title') }]} />
        <PageHeader title={t('team.title')} subtitle={t('team.subtitle')} />
        <EmptyState
          icon={<Shield className="w-8 h-8" />}
          title={t('team.accessRestricted')}
          description={t('team.accessRestrictedDescription')}
        />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('team.title') }]} />
      <PageHeader
        title={t('team.title')}
        subtitle={`${users.length} ${t('team.members')} - ${users.filter(u => u.status === 'active').length} ${t('team.active')}`}
        action={<Button onClick={() => setShowInvite(true)}><UserPlus className="w-4 h-4" /> {t('team.invite')}</Button>}
      />

      {loading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-6 h-6 animate-spin text-[var(--color-primary)]" />
        </div>
      ) : users.length === 0 ? (
        <EmptyState
          icon={<Users className="w-8 h-8" />}
          title={t('team.noMembers')}
          description={t('team.noMembersDescription')}
          action={<Button onClick={() => setShowInvite(true)}><UserPlus className="w-4 h-4" /> {t('team.invite')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('team.name'), t('team.email'), t('team.role'), tCommon('common.status'), t('team.lastLogin'), tCommon('table.actions')]}>
            {users.map((u) => (
              <TableRow key={u.id}>
                <TableCell className="font-medium">{u.name}</TableCell>
                <TableCell className="text-sm">{u.email}</TableCell>
                <TableCell>
                  <Badge variant={u.role === 'admin' ? 'danger' : u.role === 'accountant' ? 'primary' : u.role === 'manager' ? 'success' : 'neutral'}>
                    {ROLE_LABELS[u.role]}
                  </Badge>
                </TableCell>
                <TableCell>
                  {u.status === 'active' && <Badge variant="success">{tCommon('status.active')}</Badge>}
                  {u.status === 'pending' && <Badge variant="warning">{tCommon('status.pending')}</Badge>}
                  {u.status === 'revoked' && <Badge variant="danger">{t('team.revoked')}</Badge>}
                </TableCell>
                <TableCell className="text-xs text-[var(--color-text-secondary)]">
                  {u.last_login ? new Date(u.last_login).toLocaleDateString('fr-FR') : t('team.never')}
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {u.status === 'pending' && (
                      <button onClick={() => handleReinvite(u)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('team.resendInvite')}>
                        <Send className="w-4 h-4" />
                      </button>
                    )}
                    {u.status === 'active' && u.role !== 'admin' && (
                      <>
                        <button onClick={() => setEditingUser(u)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" title={t('team.editRole')}>
                          <Shield className="w-4 h-4" />
                        </button>
                        <button onClick={() => handleRevoke(u)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={t('team.revoke')}>
                          <Ban className="w-4 h-4" />
                        </button>
                      </>
                    )}
                    {u.status === 'revoked' && (
                      <button onClick={() => handleReactivate(u)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('team.reactivate')}>
                        <RotateCcw className="w-4 h-4" />
                      </button>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showInvite && (
        <InviteModal
          tenantId={user!.tenantId!}
          invitedById={user!.id}
          onClose={() => setShowInvite(false)}
          onSaved={() => { setShowInvite(false); loadData() }}
        />
      )}

      {editingUser && (
        <EditRoleModal
          tenantUser={editingUser}
          onClose={() => setEditingUser(null)}
          onSaved={() => { setEditingUser(null); loadData() }}
        />
      )}
    </div>
  )

  async function handleRevoke(u: TenantUser) {
    if (!confirm(t('team.revokeConfirm', { name: u.name }))) return
    const result = await revokeUser(u.id)
    if (result.success) { toast('success', t('team.userRevoked'), t('team.userRevokedMsg', { name: u.name })); loadData() }
    else toast('error', tCommon('toast.error'), result.error!)
  }

  async function handleReactivate(u: TenantUser) {
    const result = await reactivateUser(u.id)
    if (result.success) { toast('success', t('team.userReactivated'), t('team.userReactivatedMsg', { name: u.name })); loadData() }
    else toast('error', tCommon('toast.error'), result.error!)
  }

  async function handleReinvite(u: TenantUser) {
    const result = await reinviteUser(u.id, u.email)
    if (result.success) { toast('success', t('team.inviteResent'), t('team.inviteResentMsg', { email: u.email })); loadData() }
    else toast('error', tCommon('toast.error'), result.error!)
  }
}

function InviteModal({ tenantId, invitedById, onClose, onSaved }: {
  tenantId: string
  invitedById: string
  onClose: () => void
  onSaved: () => void
}) {
  const [email, setEmail] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [role, setRole] = useState<TenantUser['role']>('viewer')
  const [permissions, setPermissions] = useState<Record<string, string[]>>({})
  const [saving, setSaving] = useState(false)

  const showCustom = role === 'custom'

  function togglePermission(table: string, action: string) {
    setPermissions(prev => {
      const next = { ...prev }
      if (!next[table]) next[table] = []
      if (next[table].includes(action)) {
        next[table] = next[table].filter(a => a !== action)
      } else {
        next[table] = [...next[table], action]
      }
      return next
    })
  }

  async function handleSubmit() {
    if (!email || !name) { toast('error', tCommon('toast.error'), t('team.missingFields')); return }
    if (password && password.length < 6) { toast('error', tCommon('toast.error'), t('team.passwordTooShort')); return }
    setSaving(true)
    try {
      const result = await inviteUser({ tenantId, email, password: password || undefined, name, role, permissions: showCustom ? permissions : undefined, invitedBy: invitedById })
      if (result.success) {
        toast('success', t('team.userCreated'), result.message || t('team.userCreatedMsg', { email }))
        onSaved()
      } else {
        toast('error', tCommon('toast.error'), result.error!)
      }
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="p-6">
          <h2 className="text-lg font-semibold mb-4">{t('team.inviteMember')}</h2>

          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium mb-1 block">{t('team.fullName')}</label>
              <Input value={name} onChange={e => setName(e.target.value)} placeholder="Jean Dupont" />
            </div>
            <div>
              <label className="text-sm font-medium mb-1 block">{tCommon('common.email')}</label>
              <Input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="jean@entreprise.com" />
            </div>
            <div>
              <label className="text-sm font-medium mb-1 block">{tCommon('common.password')} <span className="text-[var(--color-text-secondary)] text-xs">({t('team.passwordOptional')})</span></label>
              <div className="relative">
                <Input
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  placeholder={t('team.passwordMinLength')}
                  className="pr-10"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(s => !s)}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)]"
                >
                  {showPassword ? t('team.hide') : t('team.show')}
                </button>
              </div>
            </div>
            <div>
              <label className="text-sm font-medium mb-1 block">{t('team.role')}</label>
              <Select value={role} onChange={e => setRole(e.target.value as TenantUser['role'])} options={[
                { value: 'admin', label: t('team.roles.admin') },
                { value: 'accountant', label: t('team.roles.accountant') },
                { value: 'manager', label: t('team.roles.manager') },
                { value: 'viewer', label: t('team.roles.viewer') },
                { value: 'custom', label: t('team.roles.custom') },
              ]} />
              <p className="text-xs text-[var(--color-text-secondary)] mt-1">{ROLE_DESCRIPTIONS[role]}</p>
            </div>

            {showCustom && (
              <div className="border border-[var(--color-border)] rounded-lg p-3 max-h-64 overflow-y-auto">
                <p className="text-sm font-medium mb-2">{t('team.granularPermissions')}</p>
                <div className="space-y-2">
                  {PERMISSION_TABLES.map(table => (
                    <div key={table.name} className="flex items-center justify-between">
                      <span className="text-sm">{table.label}</span>
                      <div className="flex gap-1">
                        {PERMISSION_ACTIONS.map(action => {
                          const checked = permissions[table.name]?.includes(action.value) || false
                          return (
                            <button
                              key={action.value}
                              onClick={() => togglePermission(table.name, action.value)}
                              className={`px-2 py-1 text-xs rounded border transition-colors ${
                                checked
                                  ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]'
                                  : 'bg-transparent text-[var(--color-text-secondary)] border-[var(--color-border)]'
                              }`}
                            >
                              {action.label}
                            </button>
                          )
                        })}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          <div className="flex gap-3 mt-6">
            <Button onClick={handleSubmit} disabled={saving}>
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <UserPlus className="w-4 h-4" />}
              {t('team.createUser')}
            </Button>
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
          </div>
        </div>
      </div>
    </div>
  )
}

function EditRoleModal({ tenantUser, onClose, onSaved }: {
  tenantUser: TenantUser
  onClose: () => void
  onSaved: () => void
}) {
  const [role, setRole] = useState<TenantUser['role']>(tenantUser.role)
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const [permissions, setPermissions] = useState<Record<string, string[]>>(tenantUser.permissions || {})
  const [saving, setSaving] = useState(false)

  const showCustom = role === 'custom'

  function togglePermission(table: string, action: string) {
    setPermissions(prev => {
      const next = { ...prev }
      if (!next[table]) next[table] = []
      if (next[table].includes(action)) {
        next[table] = next[table].filter(a => a !== action)
      } else {
        next[table] = [...next[table], action]
      }
      return next
    })
  }

  async function handleSubmit() {
    setSaving(true)
    const result = await updateUserRole(tenantUser.id, role, showCustom ? permissions : undefined)
    if (result.success) { toast('success', t('team.roleUpdated'), t('team.roleUpdatedMsg', { role: ROLE_LABELS[role] })); onSaved() }
    else toast('error', tCommon('toast.error'), result.error!)
    setSaving(false)
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="p-6">
          <h2 className="text-lg font-semibold mb-1">{t('team.editRole')}</h2>
          <p className="text-sm text-[var(--color-text-secondary)] mb-4">{tenantUser.name} ({tenantUser.email})</p>

          <div>
            <label className="text-sm font-medium mb-1 block">{t('team.role')}</label>
            <Select value={role} onChange={e => setRole(e.target.value as TenantUser['role'])} options={[
              { value: 'admin', label: t('team.roles.admin') },
              { value: 'accountant', label: t('team.roles.accountant') },
              { value: 'manager', label: t('team.roles.manager') },
              { value: 'viewer', label: t('team.roles.viewer') },
              { value: 'custom', label: t('team.roles.custom') },
            ]} />
            <p className="text-xs text-[var(--color-text-secondary)] mt-1">{ROLE_DESCRIPTIONS[role]}</p>
          </div>

          {showCustom && (
            <div className="border border-[var(--color-border)] rounded-lg p-3 max-h-64 overflow-y-auto mt-4">
              <p className="text-sm font-medium mb-2">{t('team.granularPermissions')}</p>
              <div className="space-y-2">
                {PERMISSION_TABLES.map(table => (
                  <div key={table.name} className="flex items-center justify-between">
                    <span className="text-sm">{table.label}</span>
                    <div className="flex gap-1">
                      {PERMISSION_ACTIONS.map(action => {
                        const checked = permissions[table.name]?.includes(action.value) || false
                        return (
                          <button
                            key={action.value}
                            onClick={() => togglePermission(table.name, action.value)}
                            className={`px-2 py-1 text-xs rounded border transition-colors ${
                              checked
                                ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]'
                                : 'bg-transparent text-[var(--color-text-secondary)] border-[var(--color-border)]'
                            }`}
                          >
                            {action.label}
                          </button>
                        )
                      })}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="flex gap-3 mt-6">
            <Button onClick={handleSubmit} disabled={saving}>
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
              {tCommon('actions.save')}
            </Button>
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
          </div>
        </div>
      </div>
    </div>
  )
}
