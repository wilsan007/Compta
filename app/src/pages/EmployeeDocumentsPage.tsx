import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getEmployeeDocuments, deleteEmployeeDocument, distributePaySlips } from '@/lib/queries/dematRh'
import { createEmployeeDocument, getEmployees, getPayRuns } from '@/lib/queries/payroll'
import { formatDate } from '@/lib/utils'
import { FileText, Plus, Trash2, X, Send } from 'lucide-react'
import type { Employee, EmployeeDocument } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

const docTypeColors: Record<string, string> = {
  payslip: 'var(--color-primary)',
  contract: 'var(--color-success)',
  dpae: 'var(--color-warning)',
  dsn: 'var(--color-info)',
  certificate: 'var(--color-neutral-500)',
  other: 'var(--color-text-secondary)',
}

export function EmployeeDocumentsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [documents, setDocuments] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [payRuns, setPayRuns] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [showDistribute, setShowDistribute] = useState(false)
  const [filterEmp, setFilterEmp] = useState('')
  const [filterType, setFilterType] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [docs, emps, prs] = await Promise.all([
        getEmployeeDocuments(''),
        getEmployees(),
        getPayRuns(),
      ])
      setDocuments(docs || [])
      setEmployees(emps || [])
      setPayRuns(prs || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteEmployeeDocument(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const filtered = documents.filter((d) => {
    if (filterEmp && d.employee_id !== filterEmp) return false
    if (filterType && d.document_type !== filterType) return false
    return true
  })

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('employeeDocuments.title') }]} />
      <PageHeader
        title={t('employeeDocuments.title')}
        subtitle={t('employeeDocuments.subtitle')}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => setShowDistribute(true)}><Send className="w-4 h-4" /> {t('employeeDocuments.distribute')}</Button>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('employeeDocuments.new')}</Button>
          </div>
        }
      />

      <div className="mb-4 flex items-end gap-3">
        <div className="w-64">
          <Select label={t('employeeDocuments.employee')} value={filterEmp} onChange={(e) => setFilterEmp(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
        </div>
        <div className="w-48">
          <Select label={t('employeeDocuments.type')} value={filterType} onChange={(e) => setFilterType(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            { value: 'payslip', label: t('employeeDocuments.types.payslip') },
            { value: 'contract', label: t('employeeDocuments.types.contract') },
            { value: 'dpae', label: t('employeeDocuments.types.dpae') },
            { value: 'dsn', label: t('employeeDocuments.types.dsn') },
            { value: 'certificate', label: t('employeeDocuments.types.certificate') },
            { value: 'other', label: t('employeeDocuments.types.other') },
          ]} />
        </div>
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} {t('employeeDocuments.title').toLowerCase()}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title={t('employeeDocuments.noDocuments')}
          description={t('employeeDocuments.noDocumentsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('employeeDocuments.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('employeeDocuments.employee'),
            t('employeeDocuments.type'),
            t('employeeDocuments.fileName'),
            t('employeeDocuments.distributedAt'),
            t('employeeDocuments.acknowledgedAt'),
            tCommon('table.actions'),
          ]}>
            {filtered.map((d) => (
              <TableRow key={d.id}>
                <TableCell className="text-sm font-medium">
                  {d.employees ? `${d.employees.first_name} ${d.employees.last_name}` : '—'}
                </TableCell>
                <TableCell>
                  <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium" style={{ color: docTypeColors[d.document_type] || 'var(--color-text-secondary)' }}>
                    {t(`employeeDocuments.types.${d.document_type}`)}
                  </span>
                </TableCell>
                <TableCell className="text-sm font-mono text-xs">{d.file_name || '—'}</TableCell>
                <TableCell className="text-xs">{d.distributed_at ? formatDate(d.distributed_at) : '—'}</TableCell>
                <TableCell className="text-xs">{d.acknowledged_at ? formatDate(d.acknowledged_at) : '—'}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    {d.file_url && (
                      <a href={d.file_url} target="_blank" rel="noopener noreferrer" className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('employeeDocuments.view')}>
                        <FileText className="w-4 h-4" />
                      </a>
                    )}
                    <button onClick={() => handleDelete(d.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                      <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <DocumentForm
          employees={employees}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}

      {showDistribute && (
        <DistributeForm
          payRuns={payRuns}
          onClose={() => setShowDistribute(false)}
          onSaved={() => { setShowDistribute(false); loadData() }}
        />
      )}
    </div>
  )
}

function DocumentForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [documentType, setDocumentType] = useState<EmployeeDocument['document_type']>('payslip')
  const [fileUrl, setFileUrl] = useState('')
  const [fileName, setFileName] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!employeeId) { toast('error', tCommon('common.error'), t('employeeDocuments.selectEmployee')); return }
    setSaving(true)
    try {
      await createEmployeeDocument({
        employee_id: employeeId,
        document_type: documentType,
        file_url: fileUrl,
        file_name: fileName || null,
        distributed_at: new Date().toISOString(),
        acknowledged_at: null,
      } as Omit<EmployeeDocument, 'id' | 'created_at'>)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('employeeDocuments.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('employeeDocuments.employee')}</label>
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
            </select>
          </div>
          <Select label={t('employeeDocuments.type')} value={documentType} onChange={(e) => setDocumentType(e.target.value as any)} options={[
            { value: 'payslip', label: t('employeeDocuments.types.payslip') },
            { value: 'contract', label: t('employeeDocuments.types.contract') },
            { value: 'dpae', label: t('employeeDocuments.types.dpae') },
            { value: 'dsn', label: t('employeeDocuments.types.dsn') },
            { value: 'certificate', label: t('employeeDocuments.types.certificate') },
            { value: 'other', label: t('employeeDocuments.types.other') },
          ]} />
          <Input label={t('employeeDocuments.fileUrl')} value={fileUrl} onChange={(e) => setFileUrl(e.target.value)} placeholder="https://..." />
          <Input label={t('employeeDocuments.fileName')} value={fileName} onChange={(e) => setFileName(e.target.value)} placeholder="document.pdf" />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function DistributeForm({ payRuns, onClose, onSaved }: { payRuns: any[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [payRunId, setPayRunId] = useState('')
  const [distributing, setDistributing] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!payRunId) { toast('error', tCommon('common.error'), t('employeeDocuments.selectPayRun')); return }
    setDistributing(true)
    try {
      const result = await distributePaySlips(payRunId)
      toast('success', tCommon('common.success'), t('employeeDocuments.distributed', { count: Array.isArray(result) ? result.length : 0 }))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setDistributing(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('employeeDocuments.distribute')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('employeeDocuments.payRun')}</label>
            <select className="input" value={payRunId} onChange={(e) => setPayRunId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {payRuns.map((pr) => <option key={pr.id} value={pr.id}>{pr.number} ({pr.period_start})</option>)}
            </select>
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={distributing}>{distributing ? '...' : t('employeeDocuments.distribute')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
