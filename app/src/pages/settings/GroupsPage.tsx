import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, Badge, EmptyState, Breadcrumb, Skeleton } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import {
  getMyGroups,
  getGroupStructure,
  createGroup,
  addGroupMember,
  removeGroupMember,
  getIntraGroupTransactions,
  recordIntraGroupTransaction,
  getGroupConsolidation,
  type EntityGroup,
  type GroupStructure,
  type IntraGroupTransaction,
  type GroupConsolidation,
} from '@/lib/queries/groups'
import { Building2, Plus, Trash2, Network } from 'lucide-react'

const MEMBER_TYPES = ['subsidiary', 'branch', 'joint_venture'] as const
const CONSOLIDATION_METHODS = ['full', 'equity', 'proportional', 'none'] as const
const TX_TYPES = ['sale', 'purchase', 'loan', 'transfer', 'management_fee', 'dividend'] as const

export function GroupsPage() {
  const { t } = useTranslation('settings')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [groups, setGroups] = useState<EntityGroup[]>([])
  const [selected, setSelected] = useState<string>('')
  const [structure, setStructure] = useState<GroupStructure | null>(null)
  const [txs, setTxs] = useState<IntraGroupTransaction[]>([])
  const [loading, setLoading] = useState(true)

  const [newName, setNewName] = useState('')
  const [memberTenant, setMemberTenant] = useState('')
  const [memberType, setMemberType] = useState<string>('subsidiary')
  const [memberPct, setMemberPct] = useState('100')
  const [memberMethod, setMemberMethod] = useState<string>('full')

  const [txTo, setTxTo] = useState('')
  const [txType, setTxType] = useState<string>('sale')
  const [txAmount, setTxAmount] = useState('')
  const [txDate, setTxDate] = useState('')
  const [txRef, setTxRef] = useState('')
  const [consFrom, setConsFrom] = useState('')
  const [consTo, setConsTo] = useState('')
  const [consolidation, setConsolidation] = useState<GroupConsolidation | null>(null)

  const loadGroups = useCallback(async () => {
    try {
      const list = await getMyGroups()
      setGroups(list)
      setSelected((cur) => (cur && list.some((g) => g.id === cur) ? cur : (list[0]?.id ?? '')))
    } catch (err) {
      toast('error', t('groups.title'), errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  const loadDetail = useCallback(async (groupId: string) => {
    if (!groupId) { setStructure(null); setTxs([]); return }
    try {
      const [s, x] = await Promise.all([getGroupStructure(groupId), getIntraGroupTransactions(groupId)])
      setStructure(s)
      setTxs(x)
    } catch (err) {
      toast('error', t('groups.title'), errorMessage(err))
    }
  }, [toast, t])

  useEffect(() => { loadGroups() }, [loadGroups])
  useEffect(() => { loadDetail(selected) }, [selected, loadDetail])

  async function handleCreate() {
    if (!newName.trim()) return
    try {
      const id = await createGroup(newName.trim())
      setNewName('')
      toast('success', t('groups.created'), '')
      await loadGroups()
      setSelected(id)
    } catch (err) {
      toast('error', t('groups.title'), errorMessage(err))
    }
  }

  async function handleAddMember() {
    if (!selected || !memberTenant.trim()) return
    try {
      await addGroupMember(selected, memberTenant.trim(), memberType, Number(memberPct) || 100, memberMethod)
      setMemberTenant('')
      await loadDetail(selected)
    } catch (err) {
      toast('error', t('groups.title'), errorMessage(err))
    }
  }

  async function handleRemoveMember(tenantId: string) {
    if (!selected) return
    if (!confirmSync(t('groups.confirmRemove'))) return
    try {
      await removeGroupMember(selected, tenantId)
      await loadDetail(selected)
    } catch (err) {
      toast('error', t('groups.title'), errorMessage(err))
    }
  }

  async function handleRecordTx() {
    if (!selected || !txTo || !txAmount || !txDate) return
    try {
      await recordIntraGroupTransaction({
        groupId: selected,
        toTenantId: txTo,
        transactionType: txType,
        amount: Number(txAmount),
        transactionDate: txDate,
        reference: txRef || null,
      })
      setTxAmount(''); setTxRef('')
      await loadDetail(selected)
    } catch (err) {
      toast('error', t('groups.title'), errorMessage(err))
    }
  }

  async function handleConsolidate() {
    if (!selected || !consFrom || !consTo) return
    try {
      setConsolidation(await getGroupConsolidation(selected, consFrom, consTo))
    } catch (err) {
      toast('error', t('groups.title'), errorMessage(err))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.system') }, { label: t('groups.title') }]} />
      <PageHeader title={t('groups.title')} subtitle={t('groups.subtitle')} />

      {loading ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-6">
          {/* Créer un groupe */}
          <Card>
            <div className="flex items-center gap-2 mb-3">
              <Network className="w-5 h-5 text-[var(--color-primary)]" aria-hidden="true" />
              <h3 className="font-semibold">{t('groups.createTitle')}</h3>
            </div>
            <div className="flex flex-col sm:flex-row gap-2 sm:items-end">
              <div className="flex-1">
                <Input
                  label={t('groups.namePlaceholder')}
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder={t('groups.namePlaceholder')}
                />
              </div>
              <Button onClick={handleCreate} disabled={!newName.trim()}>
                <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('groups.create')}
              </Button>
            </div>
          </Card>

          {groups.length === 0 ? (
            <EmptyState icon={<Building2 className="w-8 h-8" aria-hidden="true" />} title={t('groups.empty')} />
          ) : (
            <Card>
              <div className="mb-4 max-w-md">
                <Select
                  label={t('groups.select')}
                  value={selected}
                  onChange={(e) => setSelected(e.target.value)}
                >
                  {groups.map((g) => (
                    <option key={g.id} value={g.id}>{g.name}</option>
                  ))}
                </Select>
              </div>

              {structure && (
                <>
                  <h4 className="font-medium mb-2">{t('groups.members')}</h4>
                  <ul className="divide-y divide-[var(--color-border)] mb-4">
                    {structure.members.map((m) => (
                      <li key={m.tenant_id} className="flex items-center justify-between py-2">
                        <div>
                          <span className="font-medium">{m.name}</span>{' '}
                          <Badge variant="neutral">{t(`groups.memberTypes.${m.member_type}`)}</Badge>
                        </div>
                        <div className="flex items-center gap-3">
                          <span className="text-sm text-[var(--color-text-secondary)]">
                            {m.ownership_pct}% · {t(`groups.methods.${m.consolidation_method}`)}
                          </span>
                          <button
                            type="button"
                            onClick={() => handleRemoveMember(m.tenant_id)}
                            aria-label={t('groups.remove')}
                            title={t('groups.remove')}
                            className="text-[var(--color-danger)] min-w-[24px] min-h-[24px]"
                          >
                            <Trash2 className="w-4 h-4" aria-hidden="true" />
                          </button>
                        </div>
                      </li>
                    ))}
                  </ul>

                  {/* Ajouter un membre */}
                  <div className="grid grid-cols-1 md:grid-cols-4 gap-2 mb-3">
                    <Input
                      label={t('groups.tenantId')}
                      value={memberTenant}
                      onChange={(e) => setMemberTenant(e.target.value)}
                      placeholder={t('groups.tenantIdPlaceholder')}
                    />
                    <Select label={t('groups.type')} value={memberType} onChange={(e) => setMemberType(e.target.value)}>
                      {MEMBER_TYPES.map((mt) => <option key={mt} value={mt}>{t(`groups.memberTypes.${mt}`)}</option>)}
                    </Select>
                    <Input
                      label={t('groups.pct')}
                      value={memberPct}
                      onChange={(e) => setMemberPct(e.target.value.replace(/[^0-9.]/g, ''))}
                    />
                    <Select label={t('groups.method')} value={memberMethod} onChange={(e) => setMemberMethod(e.target.value)}>
                      {CONSOLIDATION_METHODS.map((c) => <option key={c} value={c}>{t(`groups.methods.${c}`)}</option>)}
                    </Select>
                  </div>
                  <Button variant="secondary" onClick={handleAddMember} disabled={!memberTenant.trim()}>
                    <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('groups.addMember')}
                  </Button>

                  {/* Flux intra-groupe */}
                  <h4 className="font-medium mb-2 mt-6">{t('groups.transactions')}</h4>
                  <div className="grid grid-cols-1 md:grid-cols-5 gap-2 mb-3">
                    <Select label={t('groups.to')} value={txTo} onChange={(e) => setTxTo(e.target.value)}>
                      <option value="">{t('groups.to')}</option>
                      {structure.members.map((m) => <option key={m.tenant_id} value={m.tenant_id}>{m.name}</option>)}
                    </Select>
                    <Select label={t('groups.txType')} value={txType} onChange={(e) => setTxType(e.target.value)}>
                      {TX_TYPES.map((x) => <option key={x} value={x}>{t(`groups.txTypes.${x}`)}</option>)}
                    </Select>
                    <Input label={t('groups.amount')} value={txAmount}
                      onChange={(e) => setTxAmount(e.target.value.replace(/[^0-9.-]/g, ''))} />
                    <Input label={t('groups.date')} type="date" value={txDate} onChange={(e) => setTxDate(e.target.value)} />
                    <Input label={t('groups.reference')} value={txRef} onChange={(e) => setTxRef(e.target.value)} />
                  </div>
                  <Button variant="secondary" onClick={handleRecordTx} disabled={!txTo || !txAmount || !txDate}>
                    <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('groups.recordTx')}
                  </Button>

                  {txs.length > 0 && (
                    <ul className="divide-y divide-[var(--color-border)] mt-4">
                      {txs.map((x) => (
                        <li key={x.id} className="flex items-center justify-between py-2 text-sm">
                          <span>{t(`groups.txTypes.${x.transaction_type}`)} · {x.reference || t('groups.noRef')}</span>
                          <span>{Number(x.amount).toFixed(2)} {x.currency} · {x.transaction_date}</span>
                        </li>
                      ))}
                    </ul>
                  )}

                  {/* Consolidation (GRP-03) */}
                  <h4 className="font-medium mb-2 mt-6">{t('groups.consolidation')}</h4>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-2 mb-3">
                    <Input label={t('groups.from')} type="date" value={consFrom} onChange={(e) => setConsFrom(e.target.value)} />
                    <Input label={t('groups.to')} type="date" value={consTo} onChange={(e) => setConsTo(e.target.value)} />
                    <div className="flex items-end">
                      <Button variant="secondary" onClick={handleConsolidate} disabled={!consFrom || !consTo}>
                        {t('groups.consolidate')}
                      </Button>
                    </div>
                  </div>
                  {consolidation && (
                    <>
                      <p className="text-sm text-[var(--color-text-secondary)] mb-2">
                        {t('groups.intraGroup')} : {consolidation.intra_group.count} · {Number(consolidation.intra_group.total_amount).toFixed(2)}
                      </p>
                      <ul className="divide-y divide-[var(--color-border)]">
                        {consolidation.accounts.map((a) => (
                          <li key={a.account} className="flex items-center justify-between py-1.5 text-sm">
                            <span className="font-mono">{a.account}</span>
                            <span>
                              {Number(a.debit).toFixed(2)} / {Number(a.credit).toFixed(2)} · {Number(a.balance).toFixed(2)}
                            </span>
                          </li>
                        ))}
                      </ul>
                    </>
                  )}
                </>
              )}
            </Card>
          )}
        </div>
      )}
    </div>
  )
}


