import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, Badge, EmptyState, Breadcrumb, Skeleton } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import {
  getJobPostings,
  createJobPosting,
  getJobApplications,
  createJobApplication,
  updateJobApplicationStatus,
  APPLICATION_STATUSES,
  CONTRACT_TYPES,
  type JobPosting,
  type JobApplication,
} from '@/lib/queries/recruitment'
import { Briefcase, Plus } from 'lucide-react'

export function RecruitmentPage() {
  const { t } = useTranslation('hr')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [postings, setPostings] = useState<JobPosting[]>([])
  const [selected, setSelected] = useState('')
  const [applications, setApplications] = useState<JobApplication[]>([])
  const [loading, setLoading] = useState(true)

  const [title, setTitle] = useState('')
  const [department, setDepartment] = useState('')
  const [contractType, setContractType] = useState<string>('cdi')
  const [location, setLocation] = useState('')
  const [candName, setCandName] = useState('')
  const [candEmail, setCandEmail] = useState('')

  const loadPostings = useCallback(async () => {
    try {
      const list = await getJobPostings()
      setPostings(list)
      setSelected((cur) => (cur && list.some((p) => p.id === cur) ? cur : (list[0]?.id ?? '')))
    } catch (err) {
      toast('error', t('recruitment.title'), errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { loadPostings() }, [loadPostings])
  useEffect(() => {
    if (!selected) { setApplications([]); return }
    getJobApplications(selected)
      .then(setApplications)
      .catch((err) => toast('error', t('recruitment.title'), errorMessage(err)))
  }, [selected, toast, t])

  async function handleCreatePosting() {
    if (!title.trim()) return
    try {
      await createJobPosting({ title: title.trim(), department, contractType, location })
      setTitle(''); setDepartment(''); setLocation('')
      await loadPostings()
    } catch (err) {
      toast('error', t('recruitment.title'), errorMessage(err))
    }
  }

  async function handleCreateApplication() {
    if (!selected || !candName.trim()) return
    try {
      await createJobApplication({ postingId: selected, candidateName: candName.trim(), email: candEmail })
      setCandName(''); setCandEmail('')
      setApplications(await getJobApplications(selected))
    } catch (err) {
      toast('error', t('recruitment.title'), errorMessage(err))
    }
  }

  async function handleStatus(id: string, status: string) {
    try {
      await updateJobApplicationStatus(id, status)
      setApplications(await getJobApplications(selected))
    } catch (err) {
      toast('error', t('recruitment.title'), errorMessage(err))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('recruitment.title') }]} />
      <PageHeader title={t('recruitment.title')} subtitle={t('recruitment.subtitle')} />

      {loading ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-6">
          <Card>
            <h3 className="font-semibold mb-3">{t('recruitment.createPosting')}</h3>
            <div className="grid grid-cols-1 md:grid-cols-5 gap-2">
              <Input label={t('recruitment.postingTitle')} value={title} onChange={(e) => setTitle(e.target.value)} />
              <Input label={t('recruitment.department')} value={department} onChange={(e) => setDepartment(e.target.value)} />
              <Select label={t('recruitment.contractType')} value={contractType} onChange={(e) => setContractType(e.target.value)}>
                {CONTRACT_TYPES.map((c) => <option key={c} value={c}>{t(`recruitment.contractTypes.${c}`)}</option>)}
              </Select>
              <Input label={t('recruitment.location')} value={location} onChange={(e) => setLocation(e.target.value)} />
              <div className="flex items-end">
                <Button onClick={handleCreatePosting} disabled={!title.trim()}>
                  <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('recruitment.create')}
                </Button>
              </div>
            </div>
          </Card>

          {postings.length === 0 ? (
            <EmptyState icon={<Briefcase className="w-8 h-8" aria-hidden="true" />} title={t('recruitment.empty')} />
          ) : (
            <Card>
              <div className="mb-4 max-w-md">
                <Select label={t('recruitment.posting')} value={selected} onChange={(e) => setSelected(e.target.value)}>
                  {postings.map((p) => (
                    <option key={p.id} value={p.id}>{p.title} — {t(`recruitment.statuses.${p.status}`)}</option>
                  ))}
                </Select>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-2 mb-4">
                <Input label={t('recruitment.candidate')} value={candName} onChange={(e) => setCandName(e.target.value)} />
                <Input label={t('recruitment.email')} value={candEmail} onChange={(e) => setCandEmail(e.target.value)} />
                <div className="flex items-end">
                  <Button variant="secondary" onClick={handleCreateApplication} disabled={!candName.trim()}>
                    <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('recruitment.addApplication')}
                  </Button>
                </div>
              </div>

              <h4 className="font-medium mb-2">{t('recruitment.applications')}</h4>
              <ul className="divide-y divide-[var(--color-border)]">
                {applications.map((a) => (
                  <li key={a.id} className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 py-2">
                    <div>
                      <span className="font-medium">{a.candidate_name}</span>{' '}
                      <Badge variant="neutral">{t(`recruitment.statuses.${a.status}`)}</Badge>
                    </div>
                    <div className="w-full sm:w-[220px]">
                      <Select label={t('recruitment.moveTo')} value={a.status} onChange={(e) => handleStatus(a.id, e.target.value)}>
                        {APPLICATION_STATUSES.map((s) => <option key={s} value={s}>{t(`recruitment.statuses.${s}`)}</option>)}
                      </Select>
                    </div>
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}

