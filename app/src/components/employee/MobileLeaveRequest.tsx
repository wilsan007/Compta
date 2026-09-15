import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Input } from '@/components/ui'
import { Calendar, Check } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getTenantId } from '@/lib/queries/core'
import { useToast } from '@/lib/toast'

export function MobileLeaveRequest() {
  const { t } = useTranslation('employee')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [leaveType, setLeaveType] = useState('')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [success, setSuccess] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSubmitting(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const userEmail = session?.user?.email
      if (!userEmail) throw new Error('Not authenticated')
      const { data: emp, error: empError } = await supabase.from('employees').select('id').eq('email', userEmail).single()
      if (empError) throw empError
      if (!emp?.id) throw new Error('Employee not found')
      const tid = await getTenantId()
      const { error } = await supabase.from('leave_requests').insert({
        tenant_id: tid, employee_id: emp.id, leave_type: leaveType,
        start_date: startDate, end_date: endDate, status: 'pending',
      })
      if (error) throw error
      setSuccess(true)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      setTimeout(() => { setSuccess(false); setLeaveType(''); setStartDate(''); setEndDate('') }, 2000)
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSubmitting(false) }
  }

  if (success) {
    return (
      <div className="flex flex-col items-center justify-center p-8 gap-3">
        <Check className="w-12 h-12 text-[var(--color-success)]" />
        <p className="text-sm font-medium">{tCommon('common.saved')}</p>
      </div>
    )
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4 p-4">
      <div>
        <label className="text-sm font-medium mb-2 block">{t('leaves.leaveType')}</label>
        <div className="grid grid-cols-2 gap-2">
          {['annual', 'rtt', 'recovery', 'sick', 'unpaid', 'special'].map(type => (
            <button
              key={type}
              type="button"
              onClick={() => setLeaveType(type)}
              className={`p-3 rounded-lg text-sm font-medium border-2 transition-colors ${
                leaveType === type
                  ? 'border-[var(--color-primary)] bg-[var(--color-primary)] text-white'
                  : 'border-[var(--color-border)] text-[var(--color-text-secondary)]'
              }`}
            >
              {t(`leaves.types.${type}`)}
            </button>
          ))}
        </div>
      </div>
      <div>
        <label className="text-sm font-medium mb-1 block">{t('leaves.startDate')}</label>
        <Input type="date" value={startDate} onChange={e => setStartDate(e.target.value)} required />
      </div>
      <div>
        <label className="text-sm font-medium mb-1 block">{t('leaves.endDate')}</label>
        <Input type="date" value={endDate} onChange={e => setEndDate(e.target.value)} required />
      </div>
      <Button type="submit" disabled={submitting} className="w-full sticky bottom-4">
        <Calendar className="w-4 h-4" /> {t('leaves.newRequest')}
      </Button>
    </form>
  )
}
