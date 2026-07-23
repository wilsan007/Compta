import { useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Input, Select, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getCompanySettings, getChartAccounts, getTenantUsers, getLegislationPacks, updateCompanySettings, type TenantUser } from '@/lib/queries'
import { useLegislation } from '@/lib/legislation'
import { Building2, Users, BookOpen, Link2, Save, Scale, LayoutGrid, CheckCircle2, Lock } from 'lucide-react'
import type { CompanySettings, ChartAccount, LegislationPack } from '@/types'
import { useAuth } from '@/lib/auth'
import { useTenantModules } from '@/lib/useTenantModules'
import { useLocale } from '@/hooks/useLocale'

const routeToTab: Record<string, 'company' | 'accounts' | 'users' | 'integrations' | 'legislation' | 'modules'> = {
  '/settings/company': 'company',
  '/settings/chart-accounts': 'accounts',
  '/settings/users': 'users',
  '/settings/integrations': 'integrations',
  '/settings/legislation': 'legislation',
  '/settings/modules': 'modules',
}

export function SettingsPage() {
  const location = useLocation()
  const navigate = useNavigate()
  const { t } = useTranslation('settings')
  const { t: tCommon } = useTranslation('common')
  const { formatCurrency, formatDate } = useLocale()
  const { user } = useAuth()
  const [tab, setTab] = useState<'company' | 'accounts' | 'users' | 'integrations' | 'legislation' | 'modules'>(routeToTab[location.pathname] || 'company')
  const [company, setCompany] = useState<CompanySettings | null>(null)
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [users, setUsers] = useState<TenantUser[]>([])
  const [packs, setPacks] = useState<LegislationPack[]>([])
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
      const [c, a, u, p] = await Promise.all([
        getCompanySettings().catch(() => null),
        getChartAccounts().catch(() => []),
        user?.tenantId ? getTenantUsers(user.tenantId).catch(() => []) : Promise.resolve([]),
        getLegislationPacks().catch(() => []),
      ])
      setCompany(c)
      setAccounts(a || [])
      setUsers(u || [])
      setPacks(p || [])
    } catch (err) {
      console.error('Error loading settings:', err)
    } finally {
      setLoading(false)
    }
  }

  const tabs = [
    { id: 'company' as const, label: t('company.title'), icon: Building2 },
    { id: 'legislation' as const, label: t('legislation.title'), icon: Scale },
    { id: 'modules' as const, label: t('modules.title'), icon: LayoutGrid },
    { id: 'accounts' as const, label: t('tabs.chartAccounts'), icon: BookOpen },
    { id: 'users' as const, label: t('users.title'), icon: Users },
    { id: 'integrations' as const, label: t('integrations.title'), icon: Link2 },
  ]

  const accountTypeLabels: Record<string, string> = {
    asset: t('tabs.asset'),
    liability: t('tabs.liability'),
    equity: t('tabs.equity'),
    income: t('tabs.income'),
    expense: t('tabs.expense'),
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
      <Breadcrumb items={[{ label: t('title') }]} />
      <PageHeader title={t('title')} subtitle={t('subtitle')} />

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
            <Card title={t('company.title')} subtitle={t('company.subtitle')}>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <Input label={t('company.name')} value={company?.name || ''} />
                <Input label={t('company.legalName')} value={company?.legal_name || ''} />
                <Input label={t('company.vatNumber')} value={company?.vat_number || ''} />
                <Input label={t('company.siret')} value={company?.siret || ''} />
                <Input label={t('company.address')} value={company?.address || ''} />
                <Input label={t('company.city')} value={company?.city || ''} />
                <Input label={t('company.zipCode')} value={company?.postal_code || ''} />
                <Select
                  label={t('company.country')}
                  value={company?.country || 'France'}
                  options={[
                    { value: 'France', label: t('company.countries.France') },
                    { value: 'Belgique', label: t('company.countries.Belgique') },
                    { value: 'Suisse', label: t('company.countries.Suisse') },
                    { value: 'Maroc', label: t('company.countries.Maroc') },
                    { value: 'Sénégal', label: t('company.countries.Sénégal') },
                  ]}
                />
                <Input label={t('company.email')} type="email" value={company?.email || ''} />
                <Input label={t('company.phone')} value={company?.phone || ''} />
                <Input label={t('company.website')} value={company?.website || ''} />
                <Select
                  label={t('company.currency')}
                  value={company?.currency || 'EUR'}
                  options={[
                    { value: 'EUR', label: t('company.currencies.EUR') },
                    { value: 'USD', label: t('company.currencies.USD') },
                    { value: 'GBP', label: t('company.currencies.GBP') },
                    { value: 'MAD', label: t('company.currencies.MAD') },
                    { value: 'XOF', label: t('company.currencies.XOF') },
                  ]}
                />
              </div>
              <div className="mt-6 flex justify-end">
                <Button variant="primary"><Save className="w-4 h-4" /> {t('company.save')}</Button>
              </div>
            </Card>
          )}

          {/* Modules tab */}
          {tab === 'modules' && (
            <ModulesTab />
          )}

          {/* Legislation tab */}
          {tab === 'legislation' && (
            <LegislationTab
              company={company}
              packs={packs}
              onSaved={() => loadData()}
            />
          )}

          {/* Chart of Accounts tab */}
          {tab === 'accounts' && (
            <Card
              title={t('accounts.title')}
              subtitle={t('accounts.subtitle', { count: accounts.length })}
              action={<Button variant="primary" size="sm">+ {t('accounts.new')}</Button>}
            >
              {accounts.length > 0 ? (
                <Table headers={[t('accounts.code'), t('accounts.name'), t('accounts.type'), t('accounts.balance'), t('accounts.vat')]}>
                  {accounts.map((a) => (
                    <TableRow key={a.id}>
                      <TableCell className="font-mono font-medium">{a.code}</TableCell>
                      <TableCell>{a.name}</TableCell>
                      <TableCell>
                        <Badge variant={accountTypeBadges[a.type] || 'neutral'}>
                          {accountTypeLabels[a.type] || a.type}
                        </Badge>
                      </TableCell>
                      <TableCell className="font-medium">{formatCurrency(Number(a.balance) || 0)}</TableCell>
                      <TableCell className="text-[var(--color-text-secondary)]">{a.vat_rate || '—'}</TableCell>
                    </TableRow>
                  ))}
                </Table>
              ) : (
                <EmptyState
                  icon={<BookOpen className="w-8 h-8" />}
                  title={t('accounts.noAccounts')}
                  description={t('accounts.noAccountsDescription')}
                  action={<Button variant="primary" size="sm">+ {t('accounts.create')}</Button>}
                />
              )}
            </Card>
          )}

          {/* Users tab */}
          {tab === 'users' && (
            <Card
              title={t('users.title')}
              subtitle={t('users.subtitle')}
              action={<Button variant="primary" size="sm" onClick={() => navigate('/settings/team')}>+ {t('users.new')}</Button>}
            >
              {users.length > 0 ? (
                <Table headers={[t('users.name'), t('users.email'), t('users.role'), t('users.status'), t('users.lastActive')]}>
                  {users.map((u) => (
                    <TableRow key={u.id}>
                      <TableCell className="font-medium">{u.name}</TableCell>
                      <TableCell>{u.email}</TableCell>
                      <TableCell>
                        <Badge variant={u.role === 'admin' ? 'danger' : u.role === 'accountant' ? 'primary' : 'neutral'}>
                          {t(`users.roles.${u.role}`)}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <Badge variant={u.status === 'active' ? 'success' : u.status === 'pending' ? 'warning' : 'danger'}>
                          {u.status === 'active' ? tCommon('common.active') : u.status === 'pending' ? tCommon('common.pending') : tCommon('common.inactive')}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-[var(--color-text-secondary)]">
                        {u.last_login ? formatDate(u.last_login) : t('users.never')}
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              ) : (
                <EmptyState
                  icon={<Users className="w-8 h-8" />}
                  title={t('users.noUsers')}
                  description={t('users.noUsersDescription')}
                  action={<Button variant="primary" size="sm" onClick={() => navigate('/settings/team')}>+ {t('users.invite')}</Button>}
                />
              )}
            </Card>
          )}

          {/* Integrations tab */}
          {tab === 'integrations' && (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {[
                { name: 'Stripe', desc: t('integrations.descriptions.Stripe'), connected: false, color: '#635bff' },
                { name: 'GoCardless', desc: t('integrations.descriptions.GoCardless'), connected: false, color: '#f50057' },
                { name: 'PayPal', desc: t('integrations.descriptions.PayPal'), connected: false, color: '#003087' },
                { name: 'Bank Feeds', desc: t('integrations.descriptions.Bank Feeds'), connected: false, color: '#0066cc' },
                { name: 'Google Drive', desc: t('integrations.descriptions.Google Drive'), connected: false, color: '#0f9d58' },
                { name: 'Slack', desc: t('integrations.descriptions.Slack'), connected: false, color: '#4a154b' },
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
                    {integration.connected ? t('integrations.connectedBadge') : t('integrations.connect')}
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

function LegislationTab({ company, packs, onSaved }: { company: CompanySettings | null; packs: LegislationPack[]; onSaved: () => void }) {
  const { t } = useTranslation('settings')
  const { pack, vatRates, loading, refresh } = useLegislation()
  const [selectedPack, setSelectedPack] = useState(company?.legislation_pack_code || pack?.code || '')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    setSelectedPack(company?.legislation_pack_code || pack?.code || '')
  }, [company, pack])

  async function handleSave() {
    if (!company) return
    setSaving(true)
    try {
      await updateCompanySettings(company.id, {
        legislation_pack_code: selectedPack,
        country_code: packs.find(p => p.code === selectedPack)?.country_code || null,
      } as any)
      refresh()
      onSaved()
    } catch (err: any) {
      console.error('Failed to update legislation pack:', err)
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return <Card><SkeletonTable rows={4} cols={3} /></Card>
  }

  return (
    <div className="space-y-6">
      {/* Active pack info */}
      <Card title={t('legislation.activePack')} subtitle={pack ? pack.name : t('legislation.noPack')}>
        {pack && (
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <p className="text-[var(--color-text-secondary)] text-xs mb-1">{t('legislation.country')}</p>
              <p className="font-medium">{pack.country_name} ({pack.country_code})</p>
            </div>
            <div>
              <p className="text-[var(--color-text-secondary)] text-xs mb-1">{t('legislation.standard')}</p>
              <p className="font-medium">{pack.accounting_standard}</p>
            </div>
            <div>
              <p className="text-[var(--color-text-secondary)] text-xs mb-1">{t('legislation.currency')}</p>
              <p className="font-medium">{pack.currency} ({pack.currency_decimals} {t('legislation.decimals')})</p>
            </div>
            <div>
              <p className="text-[var(--color-text-secondary)] text-xs mb-1">{t('legislation.fiscalYearStart')}</p>
              <p className="font-medium">{pack.fiscal_year_start}</p>
            </div>
            <div>
              <p className="text-[var(--color-text-secondary)] text-xs mb-1">{t('legislation.taxIdLabel')}</p>
              <p className="font-medium">{pack.tax_id_label}</p>
            </div>
            {pack.tax_id_secondary_label && (
              <div>
                <p className="text-[var(--color-text-secondary)] text-xs mb-1">{t('legislation.taxIdSecondary')}</p>
                <p className="font-medium">{pack.tax_id_secondary_label}</p>
              </div>
            )}
            <div>
              <p className="text-[var(--color-text-secondary)] text-xs mb-1">{t('legislation.locale')}</p>
              <p className="font-medium">{pack.locale}</p>
            </div>
          </div>
        )}
      </Card>

      {/* VAT rates table */}
      {vatRates.length > 0 && (
        <Card title={t('legislation.vatRates')} subtitle={`${vatRates.length} taux`}>
          <Table headers={[t('legislation.rateName'), t('legislation.rateCategory'), t('legislation.rateValue'), t('legislation.rateEffective')]}>
            {vatRates.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="font-medium">{r.name}</TableCell>
                <TableCell>
                  <Badge variant={r.is_default ? 'primary' : 'neutral'}>
                    {t(`legislation.categories.${r.category}`)}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono">{r.rate.toFixed(3)} %{r.is_default && <span className="text-[var(--color-text-secondary)] text-xs ml-2">({t('legislation.rateDefault')})</span>}</TableCell>
                <TableCell className="text-[var(--color-text-secondary)]">{r.effective_from}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {/* Change pack */}
      <Card title={t('legislation.changePack')}>
        <div className="space-y-4">
          <Select
            label={t('legislation.activePack')}
            value={selectedPack}
            onChange={(e) => setSelectedPack(e.target.value)}
            options={packs.map(p => ({ value: p.code, label: `${p.name} (${p.country_code})` }))}
          />
          <div className="flex justify-end">
            <Button variant="primary" onClick={handleSave} disabled={saving || !company}>
              <Save className="w-4 h-4" /> {saving ? '...' : t('legislation.save')}
            </Button>
          </div>
        </div>
      </Card>
    </div>
  )
}

function ModulesTab() {
  const { t } = useTranslation('settings')
  const { t: tAuth } = useTranslation('auth')
  const { user } = useAuth()
  const { modules: enabledModules, saveModules, refresh } = useTenantModules()
  const [selected, setSelected] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const isAdmin = user?.role === 'admin'

  useEffect(() => {
    setSelected(enabledModules)
  }, [enabledModules])

  const selectableModules = [
    { id: 'accounting', icon: '📚', color: 'indigo' },
    { id: 'commercial', icon: '🛒', color: 'emerald' },
    { id: 'treasury', icon: '💰', color: 'amber' },
    { id: 'stock', icon: '📦', color: 'violet' },
    { id: 'production', icon: '🏭', color: 'rose' },
    { id: 'hr', icon: '👥', color: 'cyan' },
    { id: 'dashboards', icon: '📊', color: 'teal' },
    { id: 'reporting', icon: '📈', color: 'fuchsia' },
  ]

  function toggleModule(moduleId: string) {
    if (!isAdmin) return
    setSelected((prev) =>
      prev.includes(moduleId)
        ? prev.filter((m) => m !== moduleId)
        : [...prev, moduleId],
    )
    setSaved(false)
  }

  async function handleSave() {
    if (!user?.tenantId) return
    setSaving(true)
    setError(null)
    const finalModules = ['home', ...selected.filter((m) => m !== 'home' && m !== 'system'), 'system']
    const { success, error: saveError } = await saveModules(user.tenantId, finalModules)
    if (success) {
      setSaved(true)
      refresh()
    } else {
      setError(saveError || t('modules.saveError'))
    }
    setSaving(false)
  }

  return (
    <div className="space-y-6">
      <Card title={t('modules.title')} subtitle={t('modules.subtitle')}>
        {!isAdmin && (
          <div className="flex items-center gap-2 p-3 rounded-lg bg-[rgba(234,179,8,0.08)] border border-[var(--color-warning)] text-sm text-[var(--color-text-secondary)] mb-4">
            <Lock className="w-4 h-4 flex-shrink-0 text-[var(--color-warning)]" />
            <span>{t('modules.adminOnly')}</span>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {selectableModules.map((mod) => {
            const isSelected = selected.includes(mod.id)
            const modColorVar = `--mod-${mod.color}`
            const modColorBg = `--mod-${mod.color}-bg`
            return (
              <button
                key={mod.id}
                type="button"
                onClick={() => toggleModule(mod.id)}
                disabled={!isAdmin}
                className={`relative flex items-center gap-3 p-4 rounded-xl border transition-all duration-200 text-left overflow-hidden ${
                  isSelected
                    ? 'border-transparent shadow-md'
                    : 'border-[var(--color-border)] bg-[var(--color-surface)] hover:border-[var(--color-neutral-300)] hover:shadow-sm'
                } ${!isAdmin ? 'cursor-default opacity-70' : ''}`}
                style={isSelected ? { background: `var(${modColorBg})`, borderColor: `var(${modColorVar})` } : undefined}
              >
                <span className="text-2xl flex-shrink-0">{mod.icon}</span>
                <div className="flex-1 min-w-0">
                  <p
                    className="text-sm font-medium truncate"
                    style={isSelected ? { color: `var(${modColorVar})` } : undefined}
                  >
                    {tAuth(`onboarding.moduleNames.${mod.id}`)}
                  </p>
                  <p className="text-xs text-[var(--color-text-secondary)] truncate">
                    {tAuth(`onboarding.moduleDescriptions.${mod.id}`)}
                  </p>
                </div>
                <div
                  className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-all ${
                    isSelected ? 'border-transparent' : 'border-[var(--color-neutral-300)]'
                  }`}
                  style={isSelected ? { background: `var(${modColorVar})` } : undefined}
                >
                  {isSelected && <CheckCircle2 className="w-4 h-4 text-white" />}
                </div>
              </button>
            )
          })}
        </div>

        {error && (
          <div className="mt-4 p-3 rounded-lg bg-[rgba(222,53,11,0.08)] border border-[var(--color-danger)] text-sm text-[var(--color-danger)]">
            {error}
          </div>
        )}

        {saved && (
          <div className="mt-4 flex items-center gap-2 p-3 rounded-lg bg-[rgba(0,135,90,0.08)] border border-[var(--color-success)] text-sm text-[var(--color-success)]">
            <CheckCircle2 className="w-4 h-4 flex-shrink-0" />
            {t('modules.saved')}
          </div>
        )}

        {isAdmin && (
          <div className="mt-6 flex justify-end">
            <Button variant="primary" onClick={handleSave} disabled={saving}>
              <Save className="w-4 h-4" /> {saving ? '...' : t('modules.save')}
            </Button>
          </div>
        )}
      </Card>
    </div>
  )
}
