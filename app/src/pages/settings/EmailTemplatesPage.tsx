// @ts-nocheck
import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { PageHeader, Button, Table, TableRow, TableCell, Input, Select, Badge, EmptyState, Breadcrumb, SkeletonTable, Modal, Textarea } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/lib/toast'
import { Mail, Plus, Trash2, Edit, Eye, Code } from 'lucide-react'
import { confirmSync } from '@/lib/confirm'

interface EmailTemplate {
  id: string
  template_key: string
  subject: string
  body_html: string
  body_text: string | null
  variables: string[]
  locale: string
  active: boolean
  created_at: string
  updated_at: string
}

const TEMPLATE_KEYS = [
  { key: 'invoice.created', label: 'Facture créée', vars: ['invoice_number', 'amount', 'currency', 'due_date', 'customer_name'] },
  { key: 'payment.reminder', label: 'Rappel de paiement', vars: ['invoice_number', 'amount', 'currency', 'days_overdue', 'customer_name'] },
  { key: 'payslip.ready', label: 'Bulletin de paie disponible', vars: ['period', 'net_salary', 'employee_name'] },
  { key: 'purchase_invoice.received', label: 'Facture fournisseur reçue', vars: ['invoice_number', 'supplier_name', 'amount', 'due_date'] },
  { key: 'dsn.submitted', label: 'DSN transmise', vars: ['period', 'declaration_id', 'status'] },
  { key: 'vat_return.submitted', label: 'Déclaration TVA soumise', vars: ['period', 'amount', 'status'] },
  { key: 'leave_request.approved', label: 'Congé approuvé', vars: ['employee_name', 'start_date', 'end_date', 'days'] },
  { key: 'leave_request.rejected', label: 'Congé refusé', vars: ['employee_name', 'start_date', 'reason'] },
  { key: 'expense_report.approved', label: 'Note de frais approuvée', vars: ['employee_name', 'amount', 'currency'] },
  { key: 'expense_report.rejected', label: 'Note de frais refusée', vars: ['employee_name', 'amount', 'reason'] },
  { key: 'bank_reconciliation.complete', label: 'Rapprochement terminé', vars: ['account', 'period', 'matched_count'] },
  { key: 'fiscal_year.closed', label: 'Exercice clôturé', vars: ['fiscal_year', 'result', 'result_type'] },
]

export function EmailTemplatesPage() {
  const { t } = useTranslation()
  const { toast } = useToast()
  const [templates, setTemplates] = useState<EmailTemplate[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [editing, setEditing] = useState<EmailTemplate | null>(null)
  const [previewMode, setPreviewMode] = useState(false)
  const [form, setForm] = useState({
    template_key: 'invoice.created',
    subject: '',
    body_html: '',
    body_text: '',
    locale: 'fr',
  })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const { data, error } = await supabase.from('email_templates').select('*').order('template_key', { ascending: true })
      if (error) throw error
      setTemplates(data || [])
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    } finally {
      setLoading(false)
    }
  }, [toast])

  useEffect(() => { loadData() }, [loadData])

  function openCreate() {
    setEditing(null)
    const tpl = TEMPLATE_KEYS[0]
    setForm({
      template_key: tpl.key,
      subject: '',
      body_html: `<h1>${tpl.label}</h1>\n<p>Contenu du message...</p>`,
      body_text: '',
      locale: 'fr',
    })
    setPreviewMode(false)
    setShowModal(true)
  }

  function openEdit(tpl: EmailTemplate) {
    setEditing(tpl)
    setForm({
      template_key: tpl.template_key,
      subject: tpl.subject,
      body_html: tpl.body_html,
      body_text: tpl.body_text || '',
      locale: tpl.locale,
    })
    setPreviewMode(false)
    setShowModal(true)
  }

  async function handleSave() {
    try {
      if (editing) {
        const { error } = await supabase.from('email_templates').update({
          subject: form.subject,
          body_html: form.body_html,
          body_text: form.body_text || null,
          updated_at: new Date().toISOString(),
        }).eq('id', editing.id)
        if (error) throw error
        toast('success', 'Template mis à jour', '')
      } else {
        const tplDef = TEMPLATE_KEYS.find(t => t.key === form.template_key)
        const { error } = await supabase.from('email_templates').insert({
          template_key: form.template_key,
          subject: form.subject,
          body_html: form.body_html,
          body_text: form.body_text || null,
          variables: tplDef?.vars || [],
          locale: form.locale,
        })
        if (error) throw error
        toast('success', 'Template créé', '')
      }
      setShowModal(false)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync('Supprimer ce template ?')) return
    try {
      const { error } = await supabase.from('email_templates').delete().eq('id', id)
      if (error) throw error
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleToggle(tpl: EmailTemplate) {
    try {
      const { error } = await supabase.from('email_templates').update({ active: !tpl.active }).eq('id', tpl.id)
      if (error) throw error
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  const currentVars = TEMPLATE_KEYS.find(t => t.key === form.template_key)?.vars || []

  return (
    <div className="space-y-6">
      <Breadcrumb items={[{ label: t('nav.settings'), href: '/settings' }, { label: 'Templates Email' }]} />
      <PageHeader title="Templates Email" description="Personnalisez les emails envoyés par l'application" />

      <div className="flex justify-end">
        <Button onClick={openCreate}><Plus className="w-4 h-4 mr-1" /> Nouveau template</Button>
      </div>

      {loading ? <SkeletonTable rows={4} cols={5} /> : templates.length === 0 ? (
        <EmptyState icon={<Mail className="w-8 h-8" />} title="Aucun template" description="Créez des templates pour personnaliser vos emails." />
      ) : (
        <Table headers={['Clé', 'Sujet', 'Langue', 'Variables', 'Statut', 'Actions']}>
          {templates.map(tpl => (
            <TableRow key={tpl.id}>
              <TableCell className="font-mono text-xs">{tpl.template_key}</TableCell>
              <TableCell className="text-sm">{tpl.subject}</TableCell>
              <TableCell><Badge variant="info">{tpl.locale}</Badge></TableCell>
              <TableCell><div className="flex gap-1 flex-wrap">{(tpl.variables || []).slice(0, 3).map(v => <Badge key={v} variant="neutral">{'{{' + v + '}}'}</Badge>)}{(tpl.variables || []).length > 3 && <Badge variant="neutral">+{tpl.variables.length - 3}</Badge>}</div></TableCell>
              <TableCell><button onClick={() => handleToggle(tpl)}>{tpl.active ? <Badge variant="success">Actif</Badge> : <Badge variant="neutral">Inactif</Badge>}</button></TableCell>
              <TableCell>
                <div className="flex gap-1">
                  <button onClick={() => openEdit(tpl)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]"><Edit className="w-4 h-4" /></button>
                  <button onClick={() => handleDelete(tpl.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {showModal && (
        <Modal open={showModal} onClose={() => setShowModal(false)} title={editing ? 'Modifier le template' : 'Nouveau template'} size="lg">
          <div className="space-y-4">
            {!editing && (
              <div>
                <label className="text-sm font-medium">Type d'email</label>
                <Select value={form.template_key} onChange={(e) => setForm({ ...form, template_key: e.target.value })}>
                  {TEMPLATE_KEYS.map(t => <option key={t.key} value={t.key}>{t.label}</option>)}
                </Select>
              </div>
            )}
            <div>
              <label className="text-sm font-medium">Sujet</label>
              <Input value={form.subject} onChange={(e) => setForm({ ...form, subject: e.target.value })} placeholder="Sujet de l'email" />
            </div>
            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="text-sm font-medium">Contenu HTML</label>
                <div className="flex gap-1">
                  <button onClick={() => setPreviewMode(false)} className={`px-2 py-1 text-xs rounded ${!previewMode ? 'bg-[var(--color-primary)] text-white' : 'border border-[var(--color-border)]'}`}><Code className="w-3 h-3 inline mr-1" />Code</button>
                  <button onClick={() => setPreviewMode(true)} className={`px-2 py-1 text-xs rounded ${previewMode ? 'bg-[var(--color-primary)] text-white' : 'border border-[var(--color-border)]'}`}><Eye className="w-3 h-3 inline mr-1" />Aperçu</button>
                </div>
              </div>
              {previewMode ? (
                <div className="border border-[var(--color-border)] rounded p-4 min-h-[200px] bg-white" dangerouslySetInnerHTML={{ __html: form.body_html }} />
              ) : (
                <Textarea value={form.body_html} onChange={(e) => setForm({ ...form, body_html: e.target.value })} rows={10} className="font-mono text-xs" />
              )}
            </div>
            <div>
              <label className="text-sm font-medium">Version texte (optionnel)</label>
              <Textarea value={form.body_text} onChange={(e) => setForm({ ...form, body_text: e.target.value })} rows={4} />
            </div>
            <div>
              <label className="text-sm font-medium">Variables disponibles</label>
              <div className="flex gap-2 flex-wrap mt-1">
                {currentVars.map(v => (
                  <button key={v} onClick={() => setForm({ ...form, body_html: form.body_html + ` {{${v}}}` })} className="px-2 py-1 text-xs rounded border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)] font-mono">
                    {'{{' + v + '}}'}
                  </button>
                ))}
              </div>
            </div>
            <div className="flex gap-2 justify-end">
              <Button variant="outline" onClick={() => setShowModal(false)}>Annuler</Button>
              <Button onClick={handleSave} disabled={!form.subject.trim() || !form.body_html.trim()}>{editing ? 'Mettre à jour' : 'Créer'}</Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}
