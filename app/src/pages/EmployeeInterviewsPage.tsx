import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { getMyObjectives, getInterviewCampaigns } from '@/lib/queries/sprintDE'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Target, Users } from 'lucide-react'

export function EmployeeInterviewsPage() {
  const { t } = useTranslation('hr')
  const { t: tNav } = useTranslation('nav')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [objectives, setObjectives] = useState<any[]>([])
  const [campaigns, setCampaigns] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [objs, camps] = await Promise.all([getMyObjectives(), getInterviewCampaigns('active')])
      setObjectives(objs || [])
      setCampaigns(camps || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('interviews.title') }]} />
      <PageHeader title={t('interviews.title')} subtitle={t('interviews.subtitle')} />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : (
        <div className="space-y-6">
          <div>
            <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-3">{t('interviews.activeCampaigns')}</h3>
            {campaigns.length === 0 ? (
              <EmptyState icon={<Users className="w-8 h-8" />} title={t('interviews.noCampaigns')} description={t('interviews.noCampaignsDescription')} />
            ) : (
              <Card>
                <Table headers={[t('campaigns.name'), t('campaigns.campaignType'), t('campaigns.startDate'), t('campaigns.endDate')]}>
                  {campaigns.map((c) => (
                    <TableRow key={c.id}>
                      <TableCell className="text-sm font-medium">{c.name}</TableCell>
                      <TableCell className="text-sm">{t(`campaigns.types.${c.campaign_type}`)}</TableCell>
                      <TableCell className="text-xs">{formatDate(c.start_date)}</TableCell>
                      <TableCell className="text-xs">{c.end_date ? formatDate(c.end_date) : '—'}</TableCell>
                    </TableRow>
                  ))}
                </Table>
              </Card>
            )}
          </div>

          <div>
            <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-3">{t('interviews.myObjectives')}</h3>
            {objectives.length === 0 ? (
              <EmptyState icon={<Target className="w-8 h-8" />} title={t('interviews.noObjectives')} description={t('interviews.noObjectivesDescription')} />
            ) : (
              <Card>
                <Table headers={[t('interviews.objectiveLabel'), t('interviews.target'), t('interviews.current'), t('interviews.progress')]}>
                  {objectives.map((o) => {
                    const pct = o.target_value ? Math.round((o.current_value / o.target_value) * 100) : 0
                    return (
                      <TableRow key={o.id}>
                        <TableCell className="text-sm font-medium">{o.title}</TableCell>
                        <TableCell className="font-mono text-xs text-right">{o.target_value}</TableCell>
                        <TableCell className="font-mono text-xs text-right">{o.current_value || 0}</TableCell>
                        <TableCell>
                          <Badge variant={pct >= 100 ? 'success' : pct >= 50 ? 'warning' : 'neutral'}>{pct}%</Badge>
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </Table>
              </Card>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
