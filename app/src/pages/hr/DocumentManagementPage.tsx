import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import { getEmployeeDocuments, uploadEmployeeDocument, deleteEmployeeDocument, distributePaySlips, controlBatchBeforeDiffusion, getDistributionLogs, sendDistributionReminders, signRhDocument, getDocumentStats } from '@/lib/queries/dematRh'
import { getEmployees, getPayRuns } from '@/lib/queries/payroll'
import type { EmployeeDocument, DocumentDistributionLog, Employee, PayRun } from '@/types'
import { useToast } from '@/lib/toast'
import { Upload, Trash2, Send, CheckCircle, PenTool, AlertTriangle, BarChart3 } from 'lucide-react'

type Tab = 'documents' | 'distribution' | 'pilotage' | 'esignature'

export function DocumentManagementPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [tab, setTab] = useState<Tab>('documents')
  const [loading, setLoading] = useState(true)
  const [documents, setDocuments] = useState<EmployeeDocument[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [logs, setLogs] = useState<DocumentDistributionLog[]>([])
  const [stats, setStats] = useState<any>(null)
  const [showUpload, setShowUpload] = useState(false)
  const [selectedPayRun, setSelectedPayRun] = useState('')
  const [batchControl, setBatchControl] = useState<{ ok: boolean; issues: string[]; recipientCount: number } | null>(null)
  const [uploadEmp, setUploadEmp] = useState('')
  const [uploadType, setUploadType] = useState('payslip')
  const [uploadTitle, setUploadTitle] = useState('')
  const [uploadPeriod, setUploadPeriod] = useState('')
  const [uploadAck, setUploadAck] = useState('false')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [emps, runs] = await Promise.all([getEmployees(), getPayRuns()])
      setEmployees(emps)
      setPayRuns(runs)
      if (tab === 'documents') {
        const allDocs: EmployeeDocument[] = []
        for (const emp of emps.slice(0, 50)) {
          try {
            const docs = await getEmployeeDocuments(emp.id)
            allDocs.push(...docs)
          } catch (e: any) { console.error('catch:', e); toast('error', tCommon('toast.error'), e.message || tCommon('toast.loadError')) }
        }
        setDocuments(allDocs)
      }
      if (tab === 'distribution') {
        const l = await getDistributionLogs()
        setLogs(l)
      }
      if (tab === 'pilotage') {
        const s = await getDocumentStats()
        setStats(s)
      }
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally {
      setLoading(false)
    }
  }, [tab, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const handleBatchControl = async () => {
    if (!selectedPayRun) return
    try {
      const result = await controlBatchBeforeDiffusion(selectedPayRun)
      setBatchControl(result)
      if (result.ok) toast('success', t('demat.batchOk'))
      else toast('warning', t('demat.batchIssues'), result.issues.join(', '))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleDistribute = async () => {
    if (!selectedPayRun) return
    try {
      await distributePaySlips(selectedPayRun)
      toast('success', t('demat.distributed'))
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleSign = async (docId: string) => {
    try {
      await signRhDocument(docId)
      toast('success', t('demat.signed'))
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const tabs: { key: Tab; label: string }[] = [
    { key: 'documents', label: t('demat.documents') },
    { key: 'distribution', label: t('demat.distribution') },
    { key: 'pilotage', label: t('demat.pilotage') },
    { key: 'esignature', label: t('demat.eSignature') },
  ]

  const docTypeBadge = (type: string) => {
    const variant: 'success' | 'primary' | 'neutral' = type === 'payslip' ? 'primary' : type === 'contract' ? 'success' : 'neutral'
    return <Badge variant={variant}>{t(`demat.types.${type}`)}</Badge>
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('demat.title') }]} />
      <PageHeader title={t('demat.title')} subtitle={t('demat.subtitle')} />

      <div className="flex flex-wrap gap-2 mb-4">
        {tabs.map(tabItem => (
          <Button key={tabItem.key} variant={tab === tabItem.key ? 'primary' : 'secondary'} onClick={() => setTab(tabItem.key)}>
            {tabItem.label}
          </Button>
        ))}
      </div>

      {loading ? <SkeletonTable /> : (
        <>
          {tab === 'documents' && (
            <Card>
              <div className="flex items-center justify-between mb-3">
                <h3 className="font-medium">{t('demat.documents')}</h3>
                <Button onClick={() => setShowUpload(true)}><Upload className="w-4 h-4 mr-2" />{t('demat.upload')}</Button>
              </div>
              {documents.length === 0 ? <EmptyState title={t('demat.noDocuments')} /> : (
                <Table headers={[t('demat.title'), t('demat.type'), t('demat.period'), t('demat.acknowledged'), t('demat.signed'), t('demat.date'), t('demat.actions')]}>
                  {documents.map(doc => (
                    <TableRow key={doc.id}>
                      <TableCell className="text-sm">{doc.title}</TableCell>
                      <TableCell>{docTypeBadge(doc.document_type)}</TableCell>
                      <TableCell className="text-xs">{doc.period || '-'}</TableCell>
                      <TableCell>{doc.acknowledged ? <CheckCircle className="w-4 h-4 text-green-600" /> : '-'}</TableCell>
                      <TableCell>{doc.e_signed ? <PenTool className="w-4 h-4 text-blue-600" /> : '-'}</TableCell>
                      <TableCell className="text-xs">{new Date(doc.created_at).toLocaleDateString()}</TableCell>
                      <TableCell>
                        <Button size="sm" variant="ghost" onClick={async () => { try { await deleteEmployeeDocument(doc.id); toast('success', tCommon('common.deleted')); loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }}><Trash2 className="w-4 h-4 text-red-500" /></Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              )}
            </Card>
          )}

          {tab === 'distribution' && (
            <Card>
              <div className="flex gap-3 mb-4 items-end">
                <Select label={t('demat.payRun')} value={selectedPayRun} onChange={(e) => setSelectedPayRun(e.target.value)} options={[{ value: '', label: tCommon('actions.select') }, ...payRuns.map(r => ({ value: r.id, label: `${r.number} - ${r.period_start}` }))]} />
                <Button variant="secondary" onClick={handleBatchControl}><AlertTriangle className="w-4 h-4 mr-2" />{t('demat.batchControl')}</Button>
                <Button onClick={handleDistribute} disabled={!batchControl?.ok}><Send className="w-4 h-4 mr-2" />{t('demat.distribute')}</Button>
              </div>
              {batchControl && (
                <div className={`mb-4 p-3 rounded ${batchControl.ok ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
                  <p className="text-sm font-medium">{batchControl.recipientCount} {t('demat.recipients')}</p>
                  {batchControl.issues.map((issue, i) => <p key={i} className="text-xs">- {issue}</p>)}
                </div>
              )}
              {logs.length === 0 ? <EmptyState title={t('demat.noDistributions')} /> : (
                <Table headers={[t('demat.employee'), t('demat.type'), t('demat.period'), t('demat.distributedAt'), t('demat.status'), t('demat.actions')]}>
                  {logs.map(log => (
                    <TableRow key={log.id}>
                      <TableCell className="text-sm">{(log as any).employees?.name || '-'}</TableCell>
                      <TableCell className="text-xs">{log.document_type}</TableCell>
                      <TableCell className="text-xs">{log.period || '-'}</TableCell>
                      <TableCell className="text-xs">{log.distributed_at ? new Date(log.distributed_at).toLocaleDateString() : '-'}</TableCell>
                      <TableCell><Badge variant={log.status === 'acknowledged' ? 'success' : log.status === 'bounced' || log.status === 'failed' ? 'danger' : 'neutral'}>{t(`demat.statuses.${log.status}`)}</Badge></TableCell>
                      <TableCell>
                        {log.status === 'distributed' && <Button size="sm" variant="ghost" onClick={async () => { try { await sendDistributionReminders(log.batch_id!); toast('success', t('demat.remindersSent')) } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }}>{t('demat.remind')}</Button>}
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              )}
            </Card>
          )}

          {tab === 'pilotage' && (
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <Card><div className="text-center"><BarChart3 className="w-8 h-8 mx-auto text-blue-600 mb-2" /><p className="text-2xl font-bold">{stats?.total || 0}</p><p className="text-xs text-gray-500">{t('demat.totalDocuments')}</p></div></Card>
              <Card><div className="text-center"><Send className="w-8 h-8 mx-auto text-green-600 mb-2" /><p className="text-2xl font-bold">{stats?.distributed || 0}</p><p className="text-xs text-gray-500">{t('demat.distributedPayslips')}</p></div></Card>
              <Card><div className="text-center"><CheckCircle className="w-8 h-8 mx-auto text-purple-600 mb-2" /><p className="text-2xl font-bold">{stats?.total ? Math.round(stats.acknowledged / stats.total * 100) : 0}%</p><p className="text-xs text-gray-500">{t('demat.acknowledgmentRate')}</p></div></Card>
              <Card><div className="text-center"><PenTool className="w-8 h-8 mx-auto text-orange-600 mb-2" /><p className="text-2xl font-bold">{stats?.signed || 0}</p><p className="text-xs text-gray-500">{t('demat.signatureRate')}</p></div></Card>
            </div>
          )}

          {tab === 'esignature' && (
            <Card>
              <h3 className="font-medium mb-3">{t('demat.eSignature')}</h3>
              {documents.filter(d => !d.e_signed).length === 0 ? <EmptyState title={t('demat.noPendingSignatures')} /> : (
                <Table headers={[t('demat.title'), t('demat.type'), t('demat.date'), t('demat.actions')]}>
                  {documents.filter(d => !d.e_signed).map(doc => (
                    <TableRow key={doc.id}>
                      <TableCell className="text-sm">{doc.title}</TableCell>
                      <TableCell>{docTypeBadge(doc.document_type)}</TableCell>
                      <TableCell className="text-xs">{new Date(doc.created_at).toLocaleDateString()}</TableCell>
                      <TableCell>
                        <Button size="sm" variant="secondary" onClick={() => handleSign(doc.id)}><PenTool className="w-4 h-4 mr-1" />{t('demat.sign')}</Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              )}
            </Card>
          )}
        </>
      )}

      {showUpload && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="w-full max-w-md p-6">
            <h3 className="font-medium mb-4">{t('demat.uploadDocument')}</h3>
            <div className="space-y-3">
              <Select label={t('demat.employee')} value={uploadEmp} onChange={(e) => setUploadEmp(e.target.value)} options={employees.map(emp => ({ value: emp.id, label: emp.name }))} required />
              <Select label={t('demat.type')} value={uploadType} onChange={(e) => setUploadType(e.target.value)} options={[
                { value: 'payslip', label: t('demat.types.payslip') },
                { value: 'contract', label: t('demat.types.contract') },
                { value: 'dpae', label: t('demat.types.dpae') },
                { value: 'certificate', label: t('demat.types.certificate') },
                { value: 'other', label: t('demat.types.other') },
              ]} />
              <Input label={t('demat.title')} value={uploadTitle} onChange={(e) => setUploadTitle(e.target.value)} />
              <Input label={t('demat.period')} value={uploadPeriod} onChange={(e) => setUploadPeriod(e.target.value)} placeholder="2024-01" />
              <Select label={t('demat.requiresAcknowledgment')} value={uploadAck} onChange={(e) => setUploadAck(e.target.value)} options={[{ value: 'false', label: tCommon('common.no') }, { value: 'true', label: tCommon('common.yes') }]} />
              <input id="file-upload" type="file" className="block w-full text-sm" />
            </div>
            <div className="flex gap-2 mt-4">
              <Button onClick={async () => {
                try {
                  const fileInput = document.getElementById('file-upload') as HTMLInputElement
                  if (fileInput.files?.[0]) {
                    await uploadEmployeeDocument(uploadEmp, fileInput.files[0], {
                      document_type: uploadType as any,
                      title: uploadTitle || fileInput.files[0].name,
                      period: uploadPeriod || null,
                      requires_acknowledgment: uploadAck === 'true',
                    })
                    toast('success', t('demat.uploaded'))
                    setShowUpload(false)
                    loadData().catch(err => console.error('loadData:', err))
                  }
                } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
              }} disabled={!uploadEmp}>{tCommon('actions.save')}</Button>
              <Button variant="secondary" onClick={() => setShowUpload(false)}>{tCommon('actions.cancel')}</Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
