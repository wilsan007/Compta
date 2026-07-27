import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { useNavigate } from 'react-router-dom'
import { Card, PageHeader, Button, EmptyState, SkeletonTable, Breadcrumb } from '@/components/ui'
import { Calendar, Receipt, MessageSquare, Plus, Clock, CheckCircle, XCircle, FileText, TrendingUp } from 'lucide-react'
import { getEmployeeDashboardData } from '@/lib/queries/sprintH'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'

export function EmployeeDashboardPage() {
  const { t } = useTranslation('employee')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const navigate = useNavigate()
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const d = await getEmployeeDashboardData()
      setData(d)
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  if (loading) return <SkeletonTable rows={6} cols={4} />

  const emp = data?.employee
  const balances = data?.leaveBalances || []
  const activity = data?.recentActivity || []

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('dashboard.title') }]} />
      <PageHeader
        title={t('dashboard.welcome', { name: `${emp?.first_name || ''} ${emp?.last_name || ''}` })}
        subtitle={t('dashboard.title')}
        action={
          <div className="flex gap-2">
            <Button variant="ghost" onClick={() => navigate('/employee/leaves')}><Plus className="w-4 h-4" /> {t('dashboard.newLeaveRequest')}</Button>
            <Button onClick={() => navigate('/employee/expenses')}><Plus className="w-4 h-4" /> {t('dashboard.newExpenseReport')}</Button>
          </div>
        }
      />

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <Calendar className="w-5 h-5 text-[var(--color-primary)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.myLeaves')}</p>
            </div>
            {balances.length > 0 ? balances.map((b: any) => (
              <div key={b.id} className="flex justify-between text-sm mb-1">
                <span>{b.leave_type}</span>
                <span className="font-mono font-bold">{b.current_balance}</span>
              </div>
            )) : <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.noActivity')}</p>}
          </div>
        </Card>

        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <Clock className="w-5 h-5 text-[var(--color-warning)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.pendingRequests')}</p>
            </div>
            <p className="text-2xl font-bold">{data?.pendingLeaveCount || 0}</p>
          </div>
        </Card>

        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <Receipt className="w-5 h-5 text-[var(--color-success)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.myExpenses')}</p>
            </div>
            <p className="text-2xl font-bold font-mono">{formatCurrency(data?.pendingExpenseAmount || 0)}</p>
          </div>
        </Card>

        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <MessageSquare className="w-5 h-5 text-[var(--color-info)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.upcomingInterviews')}</p>
            </div>
            {data?.upcomingInterview ? (
              <p className="text-sm font-medium">{formatDate(data.upcomingInterview.start_date)}</p>
            ) : (
              <p className="text-sm text-[var(--color-text-secondary)]">{t('interviews.noInterviews')}</p>
            )}
          </div>
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card>
          <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('dashboard.recentActivity')}</h3>
          {activity.length > 0 ? (
            <div className="p-4 space-y-3">
              {activity.map((a: any) => (
                <div key={a.id} className="flex items-start gap-3">
                  <div className="mt-0.5">
                    {a.activity_type.includes('approved') ? <CheckCircle className="w-4 h-4 text-[var(--color-success)]" /> :
                     a.activity_type.includes('rejected') ? <XCircle className="w-4 h-4 text-[var(--color-danger)]" /> :
                     <FileText className="w-4 h-4 text-[var(--color-text-secondary)]" />}
                  </div>
                  <div className="flex-1">
                    <p className="text-sm">{a.description || a.activity_type}</p>
                    <p className="text-xs text-[var(--color-text-secondary)]">{formatDate(a.created_at)}</p>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState icon={<TrendingUp className="w-8 h-8" />} title={t('dashboard.noActivity')} />
          )}
        </Card>

        <Card>
          <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('dashboard.leavePlanning')}</h3>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{formatDate(new Date())}</p>
          </div>
        </Card>
      </div>
    </div>
  )
}
