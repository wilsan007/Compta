import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, Badge, EmptyState, Breadcrumb, Skeleton } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import {
  getCrmSequences,
  createCrmSequence,
  deleteCrmSequence,
  getCrmSequenceSteps,
  createCrmSequenceStep,
  deleteCrmSequenceStep,
  SEQUENCE_CHANNELS,
  type CrmSequence,
  type CrmSequenceStep,
} from '@/lib/queries/crmSequences'
import { Repeat, Plus, Trash2 } from 'lucide-react'

export function SequencesPage() {
  const { t } = useTranslation('crm')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [sequences, setSequences] = useState<CrmSequence[]>([])
  const [selected, setSelected] = useState('')
  const [steps, setSteps] = useState<CrmSequenceStep[]>([])
  const [loading, setLoading] = useState(true)

  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [stepOrder, setStepOrder] = useState('1')
  const [delayDays, setDelayDays] = useState('0')
  const [channel, setChannel] = useState<string>('email')
  const [subject, setSubject] = useState('')

  const loadSequences = useCallback(async () => {
    try {
      const list = await getCrmSequences()
      setSequences(list)
      setSelected((cur) => (cur && list.some((s) => s.id === cur) ? cur : (list[0]?.id ?? '')))
    } catch (err) {
      toast('error', t('sequences.title'), errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { loadSequences() }, [loadSequences])
  useEffect(() => {
    if (!selected) { setSteps([]); return }
    getCrmSequenceSteps(selected)
      .then(setSteps)
      .catch((err) => toast('error', t('sequences.title'), errorMessage(err)))
  }, [selected, toast, t])

  async function handleCreateSequence() {
    if (!name.trim()) return
    try {
      await createCrmSequence({ name: name.trim(), description })
      setName(''); setDescription('')
      await loadSequences()
    } catch (err) {
      toast('error', t('sequences.title'), errorMessage(err))
    }
  }

  async function handleDeleteSequence(id: string) {
    if (!confirmSync(t('sequences.confirmDelete'))) return
    try {
      await deleteCrmSequence(id)
      await loadSequences()
    } catch (err) {
      toast('error', t('sequences.title'), errorMessage(err))
    }
  }

  async function handleCreateStep() {
    if (!selected || !stepOrder) return
    try {
      await createCrmSequenceStep({
        sequenceId: selected,
        stepOrder: Number(stepOrder),
        delayDays: Number(delayDays) || 0,
        channel,
        subject,
      })
      setSubject('')
      setSteps(await getCrmSequenceSteps(selected))
    } catch (err) {
      toast('error', t('sequences.title'), errorMessage(err))
    }
  }

  async function handleDeleteStep(id: string) {
    try {
      await deleteCrmSequenceStep(id)
      setSteps(await getCrmSequenceSteps(selected))
    } catch (err) {
      toast('error', t('sequences.title'), errorMessage(err))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.commercial') }, { label: t('sequences.title') }]} />
      <PageHeader title={t('sequences.title')} subtitle={t('sequences.subtitle')} />

      {loading ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-6">
          <Card>
            <div className="flex items-center gap-2 mb-3">
              <Repeat className="w-5 h-5 text-[var(--color-primary)]" aria-hidden="true" />
              <h3 className="font-semibold">{t('sequences.createTitle')}</h3>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
              <Input label={t('sequences.name')} value={name} onChange={(e) => setName(e.target.value)} />
              <Input label={t('sequences.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
              <div className="flex items-end">
                <Button onClick={handleCreateSequence} disabled={!name.trim()}>
                  <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('sequences.create')}
                </Button>
              </div>
            </div>
          </Card>

          {sequences.length === 0 ? (
            <EmptyState icon={<Repeat className="w-8 h-8" aria-hidden="true" />} title={t('sequences.empty')} />
          ) : (
            <Card>
              <div className="flex flex-col sm:flex-row sm:items-end gap-2 mb-4 max-w-2xl">
                <div className="flex-1">
                  <Select label={t('sequences.select')} value={selected} onChange={(e) => setSelected(e.target.value)}>
                    {sequences.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </Select>
                </div>
                <Button variant="danger" onClick={() => handleDeleteSequence(selected)}>
                  <Trash2 className="w-4 h-4 mr-1" aria-hidden="true" />{t('sequences.remove')}
                </Button>
              </div>

              <h4 className="font-medium mb-2">{t('sequences.steps')}</h4>
              {steps.length === 0 ? (
                <p className="text-sm text-[var(--color-text-secondary)] mb-3">{t('sequences.noSteps')}</p>
              ) : (
                <ul className="divide-y divide-[var(--color-border)] mb-3">
                  {steps.map((s) => (
                    <li key={s.id} className="flex items-center justify-between py-2">
                      <div>
                        <span className="font-medium">#{s.step_order}</span>{' '}
                        <Badge variant="neutral">{t(`sequences.channels.${s.channel}`)}</Badge>{' '}
                        <span className="text-sm text-[var(--color-text-secondary)]">
                          {t('sequences.delay')} {s.delay_days} {t('sequences.days')}
                          {s.subject ? ` · ${s.subject}` : ''}
                        </span>
                      </div>
                      <button
                        type="button"
                        onClick={() => handleDeleteStep(s.id)}
                        aria-label={t('sequences.removeStep')}
                        title={t('sequences.removeStep')}
                        className="text-[var(--color-danger)] min-w-[24px] min-h-[24px]"
                      >
                        <Trash2 className="w-4 h-4" aria-hidden="true" />
                      </button>
                    </li>
                  ))}
                </ul>
              )}

              <div className="grid grid-cols-1 md:grid-cols-5 gap-2">
                <Input label={t('sequences.order')} type="number" value={stepOrder}
                  onChange={(e) => setStepOrder(e.target.value.replace(/[^0-9]/g, ''))} />
                <Input label={t('sequences.delayDays')} type="number" value={delayDays}
                  onChange={(e) => setDelayDays(e.target.value.replace(/[^0-9]/g, ''))} />
                <Select label={t('sequences.channel')} value={channel} onChange={(e) => setChannel(e.target.value)}>
                  {SEQUENCE_CHANNELS.map((c) => <option key={c} value={c}>{t(`sequences.channels.${c}`)}</option>)}
                </Select>
                <Input label={t('sequences.subject')} value={subject} onChange={(e) => setSubject(e.target.value)} />
                <div className="flex items-end">
                  <Button variant="secondary" onClick={handleCreateStep} disabled={!selected || !stepOrder}>
                    <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('sequences.addStep')}
                  </Button>
                </div>
              </div>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}

