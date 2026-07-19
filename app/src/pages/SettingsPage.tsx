import { useEffect, useState } from 'react'
import { useLocation } from 'react-router-dom'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Input, Select, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getCompanySettings, getChartAccounts, getUsers } from '@/lib/queries'
import { Building2, Users, BookOpen, Link2, Save } from 'lucide-react'
import type { CompanySettings, ChartAccount, User } from '@/types'

const routeToTab: Record<string, 'company' | 'accounts' | 'users' | 'integrations'> = {
  '/settings/company': 'company',
  '/settings/chart-accounts': 'accounts',
  '/settings/users': 'users',
  '/settings/integrations': 'integrations',
}

export function SettingsPage() {
  const location = useLocation()
  const [tab, setTab] = useState<'company' | 'accounts' | 'users' | 'integrations'>(routeToTab[location.pathname] || 'company')
  const [company, setCompany] = useState<CompanySettings | null>(null)
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [users, setUsers] = useState<User[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadData()
  }, [])

  useEffect(() => {
    const mapped = routeToTab[location.pathname]
    if (mapped) setTab(mapped)
  }, [location.pathname])

  async function loadData() {
    try {
      const [c, a, u] = await Promise.all([
        getCompanySettings().catch(() => null),
        getChartAccounts().catch(() => []),
        getUsers().catch(() => []),
      ])
      setCompany(c)
      setAccounts(a || [])
      setUsers(u || [])
    } catch (err) {
      console.error('Error loading settings:', err)
    } finally {
      setLoading(false)
    }
  }

  const tabs = [
    { id: 'company' as const, label: 'Entreprise', icon: Building2 },
    { id: 'accounts' as const, label: 'Plan comptable', icon: BookOpen },
    { id: 'users' as const, label: 'Utilisateurs', icon: Users },
    { id: 'integrations' as const, label: 'Intégrations', icon: Link2 },
  ]

  const accountTypeLabels: Record<string, string> = {
    asset: 'Actif',
    liability: 'Passif',
    equity: 'Capitaux propres',
    income: 'Produits',
    expense: 'Charges',
  }

  const accountTypeBadges: Record<string, 'primary' | 'warning' | 'success' | 'danger' | 'neutral'> = {
    asset: 'success',
    liability: 'danger',
    equity: 'primary',
    income: 'success',
    expense: 'warning',
  }

  return (
    <div className="animate-fade-in">
      <Breadcrumb items={[{ label: 'Paramètres' }]} />
      <PageHeader title="Paramètres" subtitle="Configuration de votre application" />

      {/* Tab navigation */}
      <div className="flex items-center gap-1 mb-6 border-b border-[var(--color-border)]">
        {tabs.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
              tab === t.id
                ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
            }`}
          >
            <t.icon className="w-4 h-4" />
            {t.label}
          </button>
        ))}
      </div>

      {loading ? (
        <Card><SkeletonTable rows={5} cols={4} /></Card>
      ) : (
        <>
          {/* Company tab */}
          {tab === 'company' && (
            <Card title="Informations de l'entreprise" subtitle="Ces informations apparaîtront sur vos documents">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <Input label="Nom de l'entreprise" value={company?.name || ''} />
                <Input label="Raison sociale" value={company?.legal_name || ''} />
                <Input label="N° TVA" value={company?.vat_number || ''} />
                <Input label="SIRET" value={company?.siret || ''} />
                <Input label="Adresse" value={company?.address || ''} />
                <Input label="Ville" value={company?.city || ''} />
                <Input label="Code postal" value={company?.postal_code || ''} />
                <Select
                  label="Pays"
                  value={company?.country || 'France'}
                  options={[
                    { value: 'France', label: 'France' },
                    { value: 'Belgique', label: 'Belgique' },
                    { value: 'Suisse', label: 'Suisse' },
                    { value: 'Maroc', label: 'Maroc' },
                    { value: 'Sénégal', label: 'Sénégal' },
                  ]}
                />
                <Input label="Email" type="email" value={company?.email || ''} />
                <Input label="Téléphone" value={company?.phone || ''} />
                <Input label="Site web" value={company?.website || ''} />
                <Select
                  label="Devise"
                  value={company?.currency || 'EUR'}
                  options={[
                    { value: 'EUR', label: 'Euro (€)' },
                    { value: 'USD', label: 'Dollar US ($)' },
                    { value: 'GBP', label: 'Livre (£)' },
                    { value: 'MAD', label: 'Dirham (DH)' },
                    { value: 'XOF', label: 'Franc CFA (FCFA)' },
                  ]}
                />
              </div>
              <div className="mt-6 flex justify-end">
                <Button variant="primary"><Save className="w-4 h-4" /> Enregistrer</Button>
              </div>
            </Card>
          )}

          {/* Chart of Accounts tab */}
          {tab === 'accounts' && (
            <Card
              title="Plan comptable"
              subtitle={`${accounts.length} compte(s)`}
              action={<Button variant="primary" size="sm">+ Nouveau compte</Button>}
            >
              {accounts.length > 0 ? (
                <Table headers={['Code', 'Nom', 'Type', 'Solde', 'TVA']}>
                  {accounts.map((a) => (
                    <TableRow key={a.id}>
                      <TableCell className="font-mono font-medium">{a.code}</TableCell>
                      <TableCell>{a.name}</TableCell>
                      <TableCell>
                        <Badge variant={accountTypeBadges[a.type] || 'neutral'}>
                          {accountTypeLabels[a.type] || a.type}
                        </Badge>
                      </TableCell>
                      <TableCell className="font-medium">{new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(a.balance) || 0)}</TableCell>
                      <TableCell className="text-[var(--color-text-secondary)]">{a.vat_rate || '—'}</TableCell>
                    </TableRow>
                  ))}
                </Table>
              ) : (
                <EmptyState
                  icon={<BookOpen className="w-8 h-8" />}
                  title="Aucun compte"
                  description="Configurez votre plan comptable pour commencer"
                  action={<Button variant="primary" size="sm">+ Créer un compte</Button>}
                />
              )}
            </Card>
          )}

          {/* Users tab */}
          {tab === 'users' && (
            <Card
              title="Utilisateurs"
              subtitle={`${users.length} utilisateur(s)`}
              action={<Button variant="primary" size="sm">+ Inviter un utilisateur</Button>}
            >
              {users.length > 0 ? (
                <Table headers={['Nom', 'Email', 'Rôle', 'Statut', 'Dernière connexion']}>
                  {users.map((u) => (
                    <TableRow key={u.id}>
                      <TableCell className="font-medium">{u.name}</TableCell>
                      <TableCell>{u.email}</TableCell>
                      <TableCell>
                        <Badge variant={u.role === 'admin' ? 'danger' : u.role === 'accountant' ? 'primary' : 'neutral'}>
                          {u.role}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <Badge variant={u.active ? 'success' : 'neutral'}>
                          {u.active ? 'Actif' : 'Inactif'}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-[var(--color-text-secondary)]">
                        {u.last_login ? new Date(u.last_login).toLocaleDateString('fr-FR') : 'Jamais'}
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              ) : (
                <EmptyState
                  icon={<Users className="w-8 h-8" />}
                  title="Aucun utilisateur"
                  description="Invitez des membres de votre équipe"
                  action={<Button variant="primary" size="sm">+ Inviter</Button>}
                />
              )}
            </Card>
          )}

          {/* Integrations tab */}
          {tab === 'integrations' && (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {[
                { name: 'Stripe', desc: 'Accepter les paiements par carte', connected: false, color: '#635bff' },
                { name: 'GoCardless', desc: 'Prélèvements automatiques', connected: false, color: '#f50057' },
                { name: 'PayPal', desc: 'Paiements en ligne', connected: false, color: '#003087' },
                { name: 'Bank Feeds', desc: 'Flux bancaires automatiques', connected: false, color: '#0066cc' },
                { name: 'Google Drive', desc: 'Sauvegarde des documents', connected: false, color: '#0f9d58' },
                { name: 'Slack', desc: 'Notifications dans Slack', connected: false, color: '#4a154b' },
              ].map((integration) => (
                <Card key={integration.name}>
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-lg flex items-center justify-center text-white text-sm font-bold" style={{ background: integration.color }}>
                        {integration.name[0]}
                      </div>
                      <div>
                        <p className="text-sm font-medium text-[var(--color-text)]">{integration.name}</p>
                        <p className="text-xs text-[var(--color-text-secondary)]">{integration.desc}</p>
                      </div>
                    </div>
                  </div>
                  <Button variant={integration.connected ? 'secondary' : 'primary'} size="sm" className="w-full">
                    {integration.connected ? 'Connecté ✓' : 'Connecter'}
                  </Button>
                </Card>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  )
}
