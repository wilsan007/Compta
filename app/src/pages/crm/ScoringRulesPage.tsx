import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, Badge, EmptyState, Breadcrumb, Skeleton } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import {
  getCrmScoringRules,
  createCrmScoringRule,
  deleteCrmScoringRule,
  scoreLead,
  SCORING_OPERATORS,
  type CrmScoringRule,
  type LeadScore,
} from '@/lib/queries/crmScoring'
import { Gauge, Plus, Trash2 } from 'lucide-react'

export function ScoringRulesPage() {
  const { t } = useTranslation('crm')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [rules, setRules] = useState<CrmScoringRule[]>([])
  const [loading, setLoading] = useState(true)
  const [name, setName] = useState('')
  const [field, setField] = useState('')
  const [operator, setOperator] = useState<string>('equals')
  const [value, setValue] = useState('')
  const [points, setPoints] = useState('')
  const [facts, setFacts] = useState('{"source":"referral"}')
  const [result, setResult] = useState<LeadScore | null>(null)

  const loadRules = useCallback(async () => {
    try {
      setRules(await getCrmScoringRules())
    } catch (err) {
      toast('error', t('scoring.title'), errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { loadRules() }, [loadRules])

  async function handleCreate() {
    if (!name.trim() || !field.trim() || points === '') return
    try {
      await createCrmScoringRule({
        name: name.trim(),
        field: field.trim(),
        operator,
        value,
        points: Number(points),
      })
      setName(''); setField(''); setValue(''); setPoints('')
      await loadRules()
    } catch (err) {
      toast('error', t('scoring.title'), errorMessage(err))
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('scoring.confirmDelete'))) return
    try {
      await deleteCrmScoringRule(id)
      await loadRules()
    } catch (err) {
      toast('error', t('scoring.title'), errorMessage(err))
    }
  }

  async function handleScore() {
    try {
      const parsed = JSON.parse(facts || '{}')
      setResult(await scoreLead(parsed))
    } catch (err) {
      toast('error', t('scoring.title'), errorMessage(err))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.commercial') }, { label: t('scoring.title') }]} />
      <PageHeader title={t('scoring.title')} subtitle={t('scoring.subtitle')} />

      {loading ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-6">
          <Card>
            <div className="flex items-center gap-2 mb-3">
              <Gauge className="w-5 h-5 text-[var(--color-primary)]" aria-hidden="true" />
              <h3 className="font-semibold">{t('scoring.createTitle')}</h3>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-6 gap-2">
              <Input label={t('scoring.name')} value={name} onChange={(e) => setName(e.target.value)} />
              <Input label={t('scoring.field')} value={field} onChange={(e) => setField(e.target.value)} placeholder="source" />
              <Select label={t('scoring.operator')} value={operator} onChange={(e) => setOperator(e.target.value)}>
                {SCORING_OPERATORS.map((o) => <option key={o} value={o}>{t(`scoring.operators.${o}`)}</option>)}
              </Select>
              <Input label={t('scoring.value')} value={value} onChange={(e) => setValue(e.target.value)}
                disabled={operator === 'is_set' || operator === 'is_not_set'} />
              <Input label={t('scoring.points')} type="number" value={points} onChange={(e) => setPoints(e.target.value)} />
              <div className="flex items-end">
                <Button onClick={handleCreate} disabled={!name.trim() || !field.trim() || points === ''}>
                  <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('scoring.create')}
                </Button>
              </div>
            </div>
          </Card>

          {rules.length === 0 ? (
            <EmptyState icon={<Gauge className="w-8 h-8" aria-hidden="true" />} title={t('scoring.empty')} />
          ) : (
            <Card>
              <ul className="divide-y divide-[var(--color-border)]">
                {rules.map((r) => (
                  <li key={r.id} className="flex items-center justify-between py-2">
                    <div>
                      <span className="font-medium">{r.name}</span>{' '}
                      <span className="text-sm text-[var(--color-text-secondary)]">
                        {r.field} {t(`scoring.operators.${r.operator}`)} {r.value ?? ''}
                      </span>{' '}
                      <Badge variant={r.points >= 0 ? 'success' : 'danger'}>
                        {r.points >= 0 ? '+' : ''}{r.points}
                      </Badge>
                      {!r.is_active && <> <Badge variant="neutral">{t('scoring.inactive')}</Badge></>}
                    </div>
                    <button
                      type="button"
                      onClick={() => handleDelete(r.id)}
                      aria-label={t('scoring.remove')}
                      title={t('scoring.remove')}
                      className="text-[var(--color-danger)] min-w-[24px] min-h-[24px]"
                    >
                      <Trash2 className="w-4 h-4" aria-hidden="true" />
                    </button>
                  </li>
                ))}
              </ul>
            </Card>
          )}

          <Card>
            <h3 className="font-semibold mb-3">{t('scoring.simulator')}</h3>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1.5" htmlFor="scoring-facts">
              {t('scoring.facts')}
            </label>
            <textarea
              id="scoring-facts"
              className="input font-mono text-xs w-full"
              rows={3}
              value={facts}
              onChange={(e) => setFacts(e.target.value)}
            />
            <div className="flex items-center gap-3 mt-3">
              <Button onClick={handleScore}>{t('scoring.compute')}</Button>
              {result && (
                <span>
                  <Badge variant={result.score >= 0 ? 'success' : 'danger'}>
                    {t('scoring.score')} {result.score}
                  </Badge>{' '}
                  <span className="text-sm text-[var(--color-text-secondary)]">
                    {result.matched_rules.length ? result.matched_rules.join(' · ') : t('scoring.noRule')}
                  </span>
                </span>
              )}
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}

