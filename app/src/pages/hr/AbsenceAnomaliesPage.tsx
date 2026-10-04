import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { errorMessage, formatDate } from '@/lib/utils'
import {
  getAbsenceConflicts, getAbsenceConflictLog,
  type AbsenceConflict, type AbsenceConflictEntry,
} from '@/lib/queries/leavesAbsences'
import { useToast } from '@/lib/toast'
import { AlertTriangle, RefreshCw, GitMerge } from 'lucide-react'

/**
 * W9 / TRV-16 — l'écran « Anomalies ».
 *
 * Il affiche ce que `check_absence_conflicts` (264) trouve : une journée qui
 * porte une absence ET un pointage, des heures supplémentaires, du temps projet
 * (facturable ou non) ou une ligne de frais.
 *
 * Le contrôle NOMME, il ne répare pas : la réparation est une décision (annuler
 * l'absence, corriger le pointage, déplacer la ligne de frais), et un écran qui
 * corrigerait tout seul effacerait la trace. C'est la même doctrine que le
 * journal NF-525 (250) et que la contrepassation d'une réception (251/253).
 *
 * L'écran LIT la base : il ne recompose pas la règle de priorité ni la
 * définition d'un conflit. Deux écrans qui la recomposeraient divergeraient au
 * premier changement de règle.
 */
const conflictVariant: Record<AbsenceConflict['conflict_type'], 'warning' | 'danger' | 'neutral'> = {
  pointage: 'danger',
  heures_supplementaires: 'danger',
  temps_facturable: 'danger',
  temps_projet: 'warning',
  frais: 'warning',
}

type Tab = 'anomalies' | 'arbitrages'

function firstDayOfMonth(offsetMonths = 0): string {
  const d = new Date()
  d.setMonth(d.getMonth() + offsetMonths, 1)
  return d.toISOString().slice(0, 10)
}

function lastDayOfMonth(): string {
  const d = new Date()
  return new Date(Date.UTC(d.getFullYear(), d.getMonth() + 1, 0)).toISOString().slice(0, 10)
}

export function AbsenceAnomaliesPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [conflicts, setConflicts] = useState<AbsenceConflict[]>([])
  const [arbitrations, setArbitrations] = useState<AbsenceConflictEntry[]>([])
  const [tab, setTab] = useState<Tab>('anomalies')
  const [loading, setLoading] = useState(true)
  const [from, setFrom] = useState(firstDayOfMonth())
  const [to, setTo] = useState(lastDayOfMonth())

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      // Le refus de la base (plage invalide, société absente) remonte ici : on
      // l'affiche, on ne le remplace pas par une liste vide.
      const [c, a] = await Promise.all([
        getAbsenceConflicts(from, to),
        getAbsenceConflictLog(from, to),
      ])
      setConflicts(c)
      setArbitrations(a)
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
    } finally { setLoading(false) }
  }, [from, to, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const tabs: Array<{ id: Tab; label: string; count: number }> = [
    { id: 'anomalies', label: t('absenceAnomalies.tabs.anomalies'), count: conflicts.length },
    { id: 'arbitrages', label: t('absenceAnomalies.tabs.arbitrages'), count: arbitrations.length },
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('absenceAnomalies.title') }]} />
      <PageHeader title={t('absenceAnomalies.title')} subtitle={t('absenceAnomalies.subtitle')} />

      <Card className="mb-4">
        <div className="flex flex-wrap gap-3 items-end">
          <div className="w-44">
            <Input label={t('absenceAnomalies.from')} type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div className="w-44">
            <Input label={t('absenceAnomalies.to')} type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <Button variant="secondary" onClick={loadData}><RefreshCw className="w-4 h-4" /> {t('absenceAnomalies.refresh')}</Button>
        </div>
        <div className="flex gap-2 mt-4">
          {tabs.map((tb) => (
            <button
              key={tb.id}
              type="button"
              onClick={() => setTab(tb.id)}
              className={`px-3 py-1.5 rounded text-sm font-medium flex items-center gap-2 ${
                tab === tb.id
                  ? 'bg-[var(--color-primary)] text-white'
                  : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]'
              }`}
            >
              {tb.label}
              {tb.count > 0 && <Badge variant={tb.id === 'anomalies' ? 'danger' : 'neutral'}>{tb.count}</Badge>}
            </button>
          ))}
        </div>
      </Card>

      {tab === 'anomalies' ? (
        loading ? <SkeletonTable rows={4} cols={5} /> : conflicts.length === 0 ? (
          <EmptyState
            icon={<AlertTriangle className="w-8 h-8" />}
            title={t('absenceAnomalies.empty')}
            description={t('absenceAnomalies.emptyDesc')}
          />
        ) : (
          <Card>
            <Table headers={[
              t('absenceAnomalies.employee'), t('absenceAnomalies.day'),
              t('absenceAnomalies.kind'), t('absenceAnomalies.conflict'),
              t('absenceAnomalies.detail'),
            ]}>
              {conflicts.map((c, i) => (
                <TableRow key={`${c.employee_id}-${c.day}-${c.conflict_type}-${i}`}>
                  <TableCell className="text-sm">{c.employee_name}</TableCell>
                  <TableCell className="font-mono text-xs">{formatDate(c.day)}</TableCell>
                  <TableCell className="text-xs">{t(`absenceAnomalies.kinds.${c.absence_kind}`) || c.absence_kind}</TableCell>
                  <TableCell>
                    <Badge variant={conflictVariant[c.conflict_type] ?? 'neutral'}>
                      {t(`absenceAnomalies.conflictTypes.${c.conflict_type}`) || c.conflict_type}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-xs text-[var(--color-text-secondary)]">{c.detail}</TableCell>
                </TableRow>
              ))}
            </Table>
          </Card>
        )
      ) : (
        loading ? <SkeletonTable rows={3} cols={5} /> : arbitrations.length === 0 ? (
          <EmptyState
            icon={<GitMerge className="w-8 h-8" />}
            title={t('absenceAnomalies.arbitrages.empty')}
            description={t('absenceAnomalies.arbitrages.emptyDesc')}
          />
        ) : (
          <Card>
            <Table headers={[
              t('absenceAnomalies.day'), t('absenceAnomalies.arbitrages.kept'),
              t('absenceAnomalies.arbitrages.dropped'), t('absenceAnomalies.arbitrages.origins'),
              t('absenceAnomalies.arbitrages.detectedAt'),
            ]}>
              {arbitrations.map((a) => (
                <TableRow key={a.id}>
                  <TableCell className="font-mono text-xs">{formatDate(a.day)}</TableCell>
                  <TableCell className="text-xs">
                    {t(`absenceAnomalies.kinds.${a.kept_kind}`) || a.kept_kind}
                  </TableCell>
                  <TableCell className="text-xs text-[var(--color-text-secondary)]">
                    {t(`absenceAnomalies.kinds.${a.dropped_kind}`) || a.dropped_kind}
                  </TableCell>
                  <TableCell className="font-mono text-xs">{a.kept_origin} / {a.dropped_origin}</TableCell>
                  <TableCell className="text-xs">{formatDate(a.detected_at.slice(0, 10))}</TableCell>
                </TableRow>
              ))}
            </Table>
          </Card>
        )
      )}
    </div>
  )
}

export default AbsenceAnomaliesPage
