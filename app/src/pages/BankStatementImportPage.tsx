import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getBankStatementImports } from '@/lib/queries/accounting'
import { getBankAccounts, importBankStatement } from '@/lib/queries/banking'
import type { BankStatementFormat } from '@/lib/bankParsers'
import { useLocale } from '@/hooks/useLocale'
import { validateFileUpload, FILE_PROFILES } from '@/lib/fileSecurity'
import { Upload, FileText } from 'lucide-react'
import type { BankStatementImport, BankAccount } from '@/types'
import { useToast } from '@/lib/toast'

export function BankStatementImportPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatDate } = useLocale()
  const [imports, setImports] = useState<BankStatementImport[]>([])
  const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedAccount, setSelectedAccount] = useState('')
  const [selectedFormat, setSelectedFormat] = useState<BankStatementFormat>('unknown')
  const [uploading, setUploading] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [imps, accs] = await Promise.all([getBankStatementImports(), getBankAccounts()])
      setImports(imps || [])
      setAccounts(accs || [])
    } catch (err: any) { console.error('Failed to load bank statement imports:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file || !selectedAccount) {
      toast('warning', tCommon('common.warning'), t('bankImport.selectAccount'))
      return
    }
    // SECURITY: Validate file before processing
    const validation = await validateFileUpload(file, FILE_PROFILES.bankStatement)
    if (!validation.ok) {
      toast('error', tCommon('common.error'), validation.error || 'Invalid file')
      e.target.value = ''
      return
    }
    setUploading(true)
    try {
      // AUD-G03 : le relevé est lu et ses opérations importées (avant : seul le nom
      // du fichier était enregistré, en « pending », et rien ne le traitait)
      const summary = await importBankStatement(selectedAccount, file.name, await file.text(), selectedFormat)
      if (summary.parsed === 0) {
        toast('error', tCommon('common.error'), summary.warnings.join(' ') || t('bankImport.nothingRead'))
      } else {
        toast('success', tCommon('common.success'), t('bankImport.importSummary', { imported: summary.imported, duplicates: summary.duplicates }))
      }
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setUploading(false)
      e.target.value = ''
    }
  }

  const tableHeaders = [t('bankImport.filename'), t('bankImport.format'), t('bankImport.account'), t('bankImport.status'), t('bankImport.count'), t('bankImport.date')]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('bankImport.breadcrumb') }]} />
      <PageHeader
        title={t('bankImport.title')}
        subtitle={t('bankImport.subtitle')}
      />

      <Card className="mb-4">
        <div className="p-4 flex items-end gap-4">
          <Select
            label={t('bankImport.account')}
            value={selectedAccount}
            onChange={(e) => setSelectedAccount(e.target.value)}
            options={[
              { value: '', label: t('bankImport.selectAccount') },
              ...accounts.map((a) => ({ value: a.id, label: a.name })),
            ]}
          />
          <Select
            label={t('bankImport.format')}
            value={selectedFormat}
            onChange={(e) => setSelectedFormat(e.target.value as BankStatementFormat)}
            options={[
              { value: 'unknown', label: t('bankImport.autoDetect') },
              { value: 'cfonb120', label: 'CFONB 120' },
              { value: 'mt940', label: 'MT940' },
              { value: 'camt053', label: 'CAMT.053' },
            ]}
          />
          <Button disabled={uploading || !selectedAccount}>
            <label className="flex items-center gap-2 cursor-pointer">
              <Upload className="w-4 h-4" />
              {uploading ? t('bankImport.uploading') : t('bankImport.upload')}
              <input type="file" className="hidden" onChange={handleFileUpload} accept=".xml,.txt,.sta,.940,.mt940,.cfonb,.dat" />
            </label>
          </Button>
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : imports.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title={t('bankImport.noImports')}
          description={t('bankImport.noImportsDescription')}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {imports.map((imp) => (
              <TableRow key={imp.id}>
                <TableCell className="font-mono text-xs">{imp.filename}</TableCell>
                <TableCell><Badge variant="neutral">{imp.format}</Badge></TableCell>
                <TableCell className="text-xs">{accounts.find(a => a.id === imp.bank_account_id)?.name || '—'}</TableCell>
                <TableCell>
                  <Badge variant={imp.status === 'completed' ? 'success' : imp.status === 'failed' ? 'danger' : 'warning'}>
                    {t(`bankImport.statuses.${imp.status}`)}
                  </Badge>
                </TableCell>
                <TableCell className="text-center text-xs">{imp.imported_count || 0}</TableCell>
                <TableCell className="text-xs">{formatDate(imp.imported_at)}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
