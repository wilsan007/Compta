import { useState, useEffect, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, Badge, Select, Input } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { useToast } from '@/lib/toast'
import {
  getTenantUsers, inviteUser, updateUserRole, revokeUser, reactivateUser, reinviteUser,
  ROLE_LABELS, ROLE_DESCRIPTIONS, PERMISSION_TABLES, PERMISSION_ACTIONS,
  type TenantUser,
} from '@/lib/queries'
import { Users, UserPlus, Loader2, Mail, Ban, RotateCcw, Send, Shield, Check } from 'lucide-react'

export function TeamPage() {
  const { toast } = useToast()
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
      toast('error', 'Erreur', err.message)
    } finally {
      setLoading(false)
    }
  }, [user?.tenantId, toast])

  useEffect(() => { loadData() }, [loadData])

  const isAdmin = user?.role === 'admin'

  if (!isAdmin) {
    return (
      <div>
        <Breadcrumb items={[{ label: 'Parametres' }, { label: 'Equipe' }]} />
        <PageHeader title="Equipe" subtitle="Gestion des collaborateurs" />
        <EmptyState
          icon={<Shield className="w-8 h-8" />}
          title="Acces restreint"
          description="Seuls les administrateurs peuvent gerer l'equipe."
        />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Parametres' }, { label: 'Equipe' }]} />
      <PageHeader
        title="Equipe"
        subtitle={`${users.length} membre(s) - ${users.filter(u => u.status === 'active').length} actif(s)`}
        action={<Button onClick={() => setShowInvite(true)}><UserPlus className="w-4 h-4" /> Inviter</Button>}
      />

      {loading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-6 h-6 animate-spin text-[var(--color-primary)]" />
        </div>
      ) : users.length === 0 ? (
        <EmptyState
          icon={<Users className="w-8 h-8" />}
          title="Aucun membre"
          description="Invitez des collaborateurs a rejoindre votre entreprise."
          action={<Button onClick={() => setShowInvite(true)}><UserPlus className="w-4 h-4" /> Inviter</Button>}
        />
      ) : (
        <Card>
          <Table headers={['Nom', 'Email', 'Role', 'Statut', 'Derniere connexion', 'Actions']}>
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
                  {u.status === 'active' && <Badge variant="success">Actif</Badge>}
                  {u.status === 'pending' && <Badge variant="warning">En attente</Badge>}
                  {u.status === 'revoked' && <Badge variant="danger">Revoque</Badge>}
                </TableCell>
                <TableCell className="text-xs text-[var(--color-text-secondary)]">
                  {u.last_login ? new Date(u.last_login).toLocaleDateString('fr-FR') : 'Jamais'}
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {u.status === 'pending' && (
                      <button onClick={() => handleReinvite(u)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title="Renvoyer l'invitation">
                        <Send className="w-4 h-4" />
                      </button>
                    )}
                    {u.status === 'active' && u.role !== 'admin' && (
                      <>
                        <button onClick={() => setEditingUser(u)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" title="Modifier le role">
                          <Shield className="w-4 h-4" />
                        </button>
                        <button onClick={() => handleRevoke(u)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title="Revoquer">
                          <Ban className="w-4 h-4" />
                        </button>
                      </>
                    )}
                    {u.status === 'revoked' && (
                      <button onClick={() => handleReactivate(u)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title="Reactiver">
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
    if (!confirm(`Revoquer ${u.name} ? Il perdra immediatement l'acces.`)) return
    const result = await revokeUser(u.id)
    if (result.success) { toast('success', 'Utilisateur revoque', `${u.name} n'a plus acces`); loadData() }
    else toast('error', 'Erreur', result.error!)
  }

  async function handleReactivate(u: TenantUser) {
    const result = await reactivateUser(u.id)
    if (result.success) { toast('success', 'Utilisateur reactive', `${u.name} a de nouveau acces`); loadData() }
    else toast('error', 'Erreur', result.error!)
  }

  async function handleReinvite(u: TenantUser) {
    const result = await reinviteUser(u.id, u.email)
    if (result.success) { toast('success', 'Invitation renvoyee', `Email envoye a ${u.email}`); loadData() }
    else toast('error', 'Erreur', result.error!)
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
  const [name, setName] = useState('')
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
    if (!email || !name) { toast('error', 'Champs manquants', 'Email et nom requis'); return }
    setSaving(true)
    const result = await inviteUser({ tenantId, email, name, role, permissions: showCustom ? permissions : undefined, invitedBy: invitedById })
    if (result.success) { toast('success', 'Invitation envoyee', `Email envoye a ${email}`); onSaved() }
    else toast('error', 'Erreur', result.error!)
    setSaving(false)
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="p-6">
          <h2 className="text-lg font-semibold mb-4">Inviter un collaborateur</h2>

          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium mb-1 block">Nom complet</label>
              <Input value={name} onChange={e => setName(e.target.value)} placeholder="Jean Dupont" />
            </div>
            <div>
              <label className="text-sm font-medium mb-1 block">Email</label>
              <Input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="jean@entreprise.com" />
            </div>
            <div>
              <label className="text-sm font-medium mb-1 block">Role</label>
              <Select value={role} onChange={e => setRole(e.target.value as TenantUser['role'])} options={[
                { value: 'admin', label: 'Administrateur' },
                { value: 'accountant', label: 'Comptable' },
                { value: 'manager', label: 'Manager' },
                { value: 'viewer', label: 'Lecture seule' },
                { value: 'custom', label: 'Personnalise' },
              ]} />
              <p className="text-xs text-[var(--color-text-secondary)] mt-1">{ROLE_DESCRIPTIONS[role]}</p>
            </div>

            {showCustom && (
              <div className="border border-[var(--color-border)] rounded-lg p-3 max-h-64 overflow-y-auto">
                <p className="text-sm font-medium mb-2">Permissions granulaires</p>
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
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Mail className="w-4 h-4" />}
              Envoyer l'invitation
            </Button>
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
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
    if (result.success) { toast('success', 'Role modifie', `Nouveau role: ${ROLE_LABELS[role]}`); onSaved() }
    else toast('error', 'Erreur', result.error!)
    setSaving(false)
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="p-6">
          <h2 className="text-lg font-semibold mb-1">Modifier le role</h2>
          <p className="text-sm text-[var(--color-text-secondary)] mb-4">{tenantUser.name} ({tenantUser.email})</p>

          <div>
            <label className="text-sm font-medium mb-1 block">Role</label>
            <Select value={role} onChange={e => setRole(e.target.value as TenantUser['role'])} options={[
              { value: 'admin', label: 'Administrateur' },
              { value: 'accountant', label: 'Comptable' },
              { value: 'manager', label: 'Manager' },
              { value: 'viewer', label: 'Lecture seule' },
              { value: 'custom', label: 'Personnalise' },
            ]} />
            <p className="text-xs text-[var(--color-text-secondary)] mt-1">{ROLE_DESCRIPTIONS[role]}</p>
          </div>

          {showCustom && (
            <div className="border border-[var(--color-border)] rounded-lg p-3 max-h-64 overflow-y-auto mt-4">
              <p className="text-sm font-medium mb-2">Permissions granulaires</p>
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
              Enregistrer
            </Button>
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
          </div>
        </div>
      </div>
    </div>
  )
}
