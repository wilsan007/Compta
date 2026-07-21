import { useState, useEffect, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, Badge } from '@/components/ui'
import {
  exportAllData, generateSqlDump, generateCsvForTable,
  preRegisterMirrorServer, getMirrorServerStatus,
  generateMacInstaller, generateWindowsInstaller,
  type ExportResult,
} from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { useAuth } from '@/lib/auth'
import { useTranslation } from 'react-i18next'
import { Download, Database, FileText, Loader2, CheckCircle, AlertTriangle, Monitor, Apple, Server, RefreshCw, XCircle } from 'lucide-react'

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.style.display = 'none'
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

export function DataExportPage() {
  const { t } = useTranslation('settings')
  const { toast } = useToast()
  const { user } = useAuth()
  const [loading, setLoading] = useState(false)
  const [results, setResults] = useState<ExportResult[] | null>(null)
  const [exportedAt, setExportedAt] = useState('')
  const [totalRows, setTotalRows] = useState(0)

  // Mirror server state
  const [mirrorStatus, setMirrorStatus] = useState<any>(null)
  const [mirrorLoading, setMirrorLoading] = useState(false)
  const [installing, setInstalling] = useState(false)

  const loadMirrorStatus = useCallback(async () => {
    if (!user?.tenantId) return
    setMirrorLoading(true)
    try {
      const status = await getMirrorServerStatus(user.tenantId)
      setMirrorStatus(status)
    } catch (err) {
      console.error('Error loading mirror status:', err)
    } finally {
      setMirrorLoading(false)
    }
  }, [user?.tenantId])

  useEffect(() => {
    loadMirrorStatus()
    const interval = setInterval(loadMirrorStatus, 10000)
    return () => clearInterval(interval)
  }, [loadMirrorStatus])

  async function handleInstallMirror(platform: 'mac' | 'windows') {
    if (!user?.tenantId) {
      toast('error', t('dataExport.loadError'), t('dataExport.noTenant'))
      return
    }
    setInstalling(true)
    try {
      const result = await preRegisterMirrorServer({
        tenant_id: user.tenantId,
        install_platform: platform,
      })
      if (!result.success) {
        toast('error', t('dataExport.loadError'), result.error || t('dataExport.loadError'))
        return
      }

      const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://ndtaedcgwnaopopugiql.supabase.co'
      const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_6WZDE3wBMwc5ildtfy19Nw_pxdPnAZK'

      const daemonResp = await fetch('/mirror-daemon.mjs')
      const daemonCode = await daemonResp.text()

      const installerCode = platform === 'mac'
        ? generateMacInstaller({
            supabaseUrl, supabaseKey, tenantId: user.tenantId, installToken: result.install_token!, daemonCode,
          })
        : generateWindowsInstaller({
            supabaseUrl, supabaseKey, tenantId: user.tenantId, installToken: result.install_token!, daemonCode,
          })

      const filename = platform === 'mac' ? 'install-compta-mirror.sh' : 'install-compta-mirror.ps1'
      const mime = platform === 'mac' ? 'text/x-shellscript;charset=utf-8' : 'text/plain;charset=utf-8'
      const blob = new Blob([installerCode], { type: mime })
      downloadBlob(blob, filename)

      toast('success', t('dataExport.installerDownloaded'), t('dataExport.executeOnServer', { filename, platform: platform === 'mac' ? 'Mac' : 'Windows' }))
      await loadMirrorStatus()
    } catch (err: any) {
      toast('error', t('dataExport.loadError'), err.message || t('dataExport.loadError'))
    } finally {
      setInstalling(false)
    }
  }

  async function handleExport() {
    setLoading(true)
    setResults(null)
    try {
      const { tables, exportedAt, totalRows } = await exportAllData()
      setResults(tables)
      setExportedAt(exportedAt)
      setTotalRows(totalRows)
      toast('success', t('dataExport.exportDone'), t('dataExport.rowsRetrieved', { rows: totalRows, tables: tables.filter(t => t.rowCount > 0).length }))
    } catch (err: any) {
      toast('error', t('dataExport.exportError'), err.message || t('dataExport.loadError'))
    } finally {
      setLoading(false)
    }
  }

  function downloadSql() {
    if (!results) return
    const sql = generateSqlDump(results, exportedAt)
    const blob = new Blob([sql], { type: 'application/sql;charset=utf-8' })
    downloadBlob(blob, `export-compta-${new Date().toISOString().split('T')[0]}.sql`)
    toast('info', t('dataExport.downloadTitle'), t('dataExport.sqlDownloaded'))
  }

  function downloadAllCsv() {
    if (!results) return
    const tablesWithData = results.filter(t => t.rowCount > 0)
    const parts: string[] = []
    for (const tbl of tablesWithData) {
      parts.push(`=== ${tbl.tableName} (${tbl.rowCount} ${t('dataExport.rows')}) ===`)
      parts.push(generateCsvForTable(tbl))
      parts.push('')
    }
    const csv = parts.join('\n')
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' })
    downloadBlob(blob, `export-compta-${new Date().toISOString().split('T')[0]}.csv`)
    toast('info', t('dataExport.downloadTitle'), t('dataExport.csvDownloaded'))
  }

  function downloadJson() {
    if (!results) return
    const payload = {
      exportedAt,
      totalRows,
      tables: results.map(t => ({
        tableName: t.tableName,
        rowCount: t.rowCount,
        columns: t.columns,
        rows: t.rows,
      })),
    }
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json;charset=utf-8' })
    downloadBlob(blob, `export-compta-${new Date().toISOString().split('T')[0]}.json`)
    toast('info', t('dataExport.downloadTitle'), t('dataExport.jsonDownloaded'))
  }

  function downloadTableCsv(table: ExportResult) {
    const csv = generateCsvForTable(table)
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' })
    downloadBlob(blob, `${table.tableName}.csv`)
  }

  const tablesWithData = results?.filter(t => t.rowCount > 0) || []
  const emptyTables = results?.filter(t => t.rowCount === 0) || []

  return (
    <div>
      <Breadcrumb items={[{ label: t('dataExport.breadcrumb') }, { label: t('dataExport.breadcrumb2') }]} />
      <PageHeader
        title={t('dataExport.titleFull')}
        subtitle={t('dataExport.subtitleFull')}
        action={
          <Button onClick={handleExport} disabled={loading}>
            {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Database className="w-4 h-4" />}
            {loading ? t('dataExport.exporting') : t('dataExport.startExport')}
          </Button>
        }
      />

      <div className="mb-6 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
        <div className="flex items-start gap-3">
          <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0 mt-0.5" />
          <div className="text-sm space-y-1">
            <p className="font-medium">{t('dataExport.sovereignty')}</p>
            <p className="text-[var(--color-text-secondary)]" dangerouslySetInnerHTML={{ __html: t('dataExport.sovereigntyDesc') }} />
          </div>
        </div>
      </div>

      {loading && (
        <Card>
          <div className="p-8 flex flex-col items-center gap-3">
            <Loader2 className="w-8 h-8 animate-spin text-[var(--color-primary)]" />
            <p className="text-sm text-[var(--color-text-secondary)]">{t('dataExport.retrievingData')}</p>
            <p className="text-xs text-[var(--color-text-secondary)]">{t('dataExport.retrievingDesc')}</p>
          </div>
        </Card>
      )}

      {results && !loading && (
        <div className="space-y-4">
          <div className="flex items-center gap-3 p-4 rounded-lg bg-green-50 border border-green-200">
            <CheckCircle className="w-5 h-5 text-green-600 flex-shrink-0" />
            <div className="flex-1">
              <p className="text-sm font-medium text-green-800">
                {t('dataExport.exportDone')} — {t('dataExport.exportDoneDesc', { rows: totalRows.toLocaleString(), tables: tablesWithData.length })}
              </p>
              <p className="text-xs text-green-700">{t('dataExport.exportDate')} : {new Date(exportedAt).toLocaleString('fr-FR')}</p>
            </div>
          </div>

          <div className="flex flex-wrap gap-3">
            <Button onClick={downloadSql}>
              <FileText className="w-4 h-4" />
              {t('dataExport.downloadSql')}
            </Button>
            <Button variant="secondary" onClick={downloadAllCsv}>
              <Download className="w-4 h-4" />
              {t('dataExport.downloadCsv')}
            </Button>
            <Button variant="secondary" onClick={downloadJson}>
              <Database className="w-4 h-4" />
              {t('dataExport.downloadJson')}
            </Button>
          </div>

          <Card>
            <div className="p-4 border-b border-[var(--color-border)]">
              <h3 className="font-semibold text-sm">{t('dataExport.tablesWithData', { count: tablesWithData.length })}</h3>
            </div>
            <Table headers={[t('dataExport.table'), t('dataExport.rows'), t('dataExport.columns'), t('dataExport.estimatedSize'), t('dataExport.action')]}>
              <tbody>
                {tablesWithData.map((tbl) => {
                  const sizeEstimate = Math.round(JSON.stringify(tbl.rows).length / 1024)
                  return (
                    <TableRow key={tbl.tableName}>
                      <TableCell className="font-mono text-sm">{tbl.tableName}</TableCell>
                      <TableCell className="text-right font-medium">{tbl.rowCount.toLocaleString()}</TableCell>
                      <TableCell className="text-right text-sm">{tbl.columns.length}</TableCell>
                      <TableCell className="text-right text-sm text-[var(--color-text-secondary)]">
                        {sizeEstimate > 1024 ? `${(sizeEstimate / 1024).toFixed(1)} ${t('dataExport.sizeUnitMB')}` : `${sizeEstimate} ${t('dataExport.sizeUnitKB')}`}
                      </TableCell>
                      <TableCell>
                        <button
                          onClick={() => downloadTableCsv(tbl)}
                          className="inline-flex items-center gap-1 text-xs text-[var(--color-primary)] hover:underline"
                        >
                          <Download className="w-3 h-3" /> CSV
                        </button>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </tbody>
            </Table>
          </Card>

          {emptyTables.length > 0 && (
            <Card>
              <div className="p-4 border-b border-[var(--color-border)]">
                <h3 className="font-semibold text-sm text-[var(--color-text-secondary)]">
                  {t('dataExport.emptyTables', { count: emptyTables.length })}
                </h3>
              </div>
              <div className="p-4 flex flex-wrap gap-2">
                {emptyTables.map(t => (
                  <Badge key={t.tableName} variant="neutral">{t.tableName}</Badge>
                ))}
              </div>
            </Card>
          )}
        </div>
      )}

      {!results && !loading && (
        <EmptyState
          icon={<Database className="w-8 h-8" />}
          title={t('dataExport.noExport')}
          description={t('dataExport.noExportDesc')}
          action={<Button onClick={handleExport}><Database className="w-4 h-4" /> {t('dataExport.startExport')}</Button>}
        />
      )}

      {/* Mirror Server Installation Section */}
      <div className="mt-8">
        <Card>
          <div className="p-6">
            <div className="flex items-center gap-3 mb-4">
              <Server className="w-6 h-6 text-[var(--color-primary)]" />
              <div>
                <h2 className="text-lg font-semibold">{t('dataExport.mirrorTitle')}</h2>
                <p className="text-sm text-[var(--color-text-secondary)]">
                  {t('dataExport.mirrorDesc')}
                </p>
              </div>
            </div>

            {mirrorLoading ? (
              <div className="flex items-center gap-2 text-sm text-[var(--color-text-secondary)]">
                <Loader2 className="w-4 h-4 animate-spin" /> {t('dataExport.checkingStatus')}
              </div>
            ) : mirrorStatus?.exists && mirrorStatus?.install_status === 'verified' ? (
              <div className="space-y-3">
                <div className="flex items-center gap-3 p-4 rounded-lg bg-green-50 border border-green-200">
                  <CheckCircle className="w-5 h-5 text-green-600 flex-shrink-0" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-green-800">{t('dataExport.mirrorActive')}</p>
                    <p className="text-xs text-green-700">
                      {t('dataExport.machine')}: {mirrorStatus.machine_name} • {t('dataExport.verifiedOn')}: {mirrorStatus.verified_at ? new Date(mirrorStatus.verified_at).toLocaleString('fr-FR') : 'N/A'}
                    </p>
                  </div>
                  <Button variant="secondary" onClick={loadMirrorStatus}>
                    <RefreshCw className="w-4 h-4" /> {t('dataExport.refresh')}
                  </Button>
                </div>
                {mirrorStatus.verification_data && (
                  <div className="text-xs text-[var(--color-text-secondary)] grid grid-cols-3 gap-4 p-3 rounded border border-[var(--color-border)]">
                    <div><strong>{mirrorStatus.verification_data.total_tables}</strong> {t('dataExport.tablesSynced')}</div>
                    <div><strong>{mirrorStatus.verification_data.total_rows}</strong> {t('dataExport.totalRows')}</div>
                    <div><strong>{mirrorStatus.verification_data.tables_with_data}</strong> {t('dataExport.tablesWithDataShort')}</div>
                  </div>
                )}
              </div>
            ) : mirrorStatus?.exists && mirrorStatus?.install_status === 'pending' ? (
              <div className="space-y-3">
                <div className="flex items-center gap-3 p-4 rounded-lg bg-yellow-50 border border-yellow-200">
                  <Loader2 className="w-5 h-5 text-yellow-600 flex-shrink-0 animate-spin" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-yellow-800">{t('dataExport.installPending')}</p>
                    <p className="text-xs text-yellow-700">
                      {t('dataExport.installPendingDesc')}
                    </p>
                  </div>
                  <Button variant="secondary" onClick={loadMirrorStatus}>
                    <RefreshCw className="w-4 h-4" /> {t('dataExport.refresh')}
                  </Button>
                </div>
              </div>
            ) : mirrorStatus?.exists && mirrorStatus?.install_status === 'failed' ? (
              <div className="space-y-3">
                <div className="flex items-center gap-3 p-4 rounded-lg bg-red-50 border border-red-200">
                  <XCircle className="w-5 h-5 text-red-600 flex-shrink-0" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-red-800">{t('dataExport.installFailed')}</p>
                    <p className="text-xs text-red-700">{t('dataExport.installFailedDesc')}</p>
                  </div>
                </div>
                <div className="flex gap-3">
                  <Button onClick={() => handleInstallMirror('mac')} disabled={installing}>
                    <Apple className="w-4 h-4" /> {t('dataExport.reinstallMac')}
                  </Button>
                  <Button variant="secondary" onClick={() => handleInstallMirror('windows')} disabled={installing}>
                    <Monitor className="w-4 h-4" /> {t('dataExport.reinstallWindows')}
                  </Button>
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                <div className="p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                  <p className="text-sm text-[var(--color-text-secondary)] mb-3">
                    {t('dataExport.chooseSystem')}
                  </p>
                  <div className="flex gap-3">
                    <Button onClick={() => handleInstallMirror('mac')} disabled={installing}>
                      {installing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Apple className="w-4 h-4" />}
                      {t('dataExport.installMac')}
                    </Button>
                    <Button variant="secondary" onClick={() => handleInstallMirror('windows')} disabled={installing}>
                      {installing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Monitor className="w-4 h-4" />}
                      {t('dataExport.installWindows')}
                    </Button>
                  </div>
                </div>
              </div>
            )}
          </div>
        </Card>
      </div>
    </div>
  )
}
