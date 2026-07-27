import { useState, useRef } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Input, Select } from '@/components/ui'
import { Camera, Check, CloudOff, Cloud, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getTenantId } from '@/lib/queries/core'
import { useToast } from '@/lib/toast'

export function MobileExpenseCapture() {
  const { t } = useTranslation('employee')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [photo, setPhoto] = useState<string | null>(null)
  const [ocrProcessing, setOcrProcessing] = useState(false)
  const [synced, setSynced] = useState(true)
  const [amount, setAmount] = useState('')
  const [vatRate, setVatRate] = useState('20')
  const [description, setDescription] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (file) {
      const reader = new FileReader()
      reader.onload = ev => setPhoto(ev.target?.result as string)
      reader.readAsDataURL(file)
      setSynced(false)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSubmitting(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const userEmail = session?.user?.email
      if (!userEmail) throw new Error('Not authenticated')
      const { data: emp } = await supabase.from('employees').select('id').eq('email', userEmail).single()
      if (!emp?.id) throw new Error('Employee not found')
      const tid = await getTenantId()
      const amountNum = Number(amount)
      const vatNum = Number(vatRate)
      const ht = amountNum / (1 + vatNum / 100)
      const { data: report } = await supabase.from('expense_reports').select('id').eq('employee_id', emp.id).eq('status', 'draft').limit(1).maybeSingle()
      let reportId = report?.id
      if (!reportId) {
        const { data: newReport } = await supabase.from('expense_reports').insert({
          tenant_id: tid, employee_id: emp.id, number: `EXP-${Date.now()}`, total_amount: 0, total_vat: 0, status: 'draft',
        }).select().single()
        reportId = newReport.id
      }
      const { error } = await supabase.from('expense_report_lines').insert({
        tenant_id: tid, expense_report_id: reportId, category_id: categoryId || null,
        date: new Date().toISOString().split('T')[0], description, amount: amountNum,
        amount_ht: ht, amount_ttc: amountNum, vat_rate: vatNum, vat_amount: amountNum - ht,
      })
      if (error) throw error
      setSynced(true)
      setPhoto(null); setAmount(''); setDescription(''); setCategoryId('')
      toast('success', tCommon('common.success'), t('expenses.synced'))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSubmitting(false) }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm">
        {synced ? <Cloud className="w-4 h-4 text-[var(--color-success)]" /> : <CloudOff className="w-4 h-4 text-[var(--color-warning)]" />}
        <span className="text-[var(--color-text-secondary)]">{synced ? t('expenses.synced') : t('expenses.offlineMode')}</span>
      </div>

      <div>
        <input ref={fileRef} type="file" accept="image/*" capture="environment" onChange={handleFile} className="hidden" />
        <Button type="button" variant="ghost" onClick={() => fileRef.current?.click()} className="w-full">
          <Camera className="w-5 h-5" /> {t('expenses.capturePhoto')}
        </Button>
        {photo && <img src={photo} alt="Receipt" className="mt-2 rounded-lg w-full max-h-48 object-cover" />}
      </div>

      {ocrProcessing && (
        <div className="flex items-center gap-2 text-sm text-[var(--color-text-secondary)]">
          <Loader2 className="w-4 h-4 animate-spin" /> {t('expenses.ocrProcessing')}
        </div>
      )}

      <div>
        <label className="text-sm font-medium mb-1 block">{t('expenses.description')}</label>
        <Input value={description} onChange={e => setDescription(e.target.value)} required />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="text-sm font-medium mb-1 block">{t('expenses.amountTtc')}</label>
          <Input type="number" step="0.01" value={amount} onChange={e => setAmount(e.target.value)} required />
        </div>
        <div>
          <label className="text-sm font-medium mb-1 block">{t('expenses.vatRate')}</label>
          <Select value={vatRate} onChange={e => setVatRate(e.target.value)} options={[
            { value: '0', label: '0%' }, { value: '5.5', label: '5.5%' }, { value: '10', label: '10%' }, { value: '20', label: '20%' },
          ]} />
        </div>
      </div>
      <Button type="submit" disabled={submitting} className="w-full sticky bottom-4">
        <Check className="w-4 h-4" /> {tCommon('common.confirm')}
      </Button>
    </form>
  )
}
