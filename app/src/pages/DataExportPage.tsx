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
      toast('error', 'Erreur', 'Aucune entreprise associée à votre compte')
      return
    }
    setInstalling(true)
    try {
      const result = await preRegisterMirrorServer({
        tenant_id: user.tenantId,
        install_platform: platform,
      })
      if (!result.success) {
        toast('error', 'Erreur', result.error || 'Échec')
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

      toast('success', 'Installer téléchargé', `Exécutez ${filename} sur votre ${platform === 'mac' ? 'Mac' : 'PC Windows'} serveur.`)
      await loadMirrorStatus()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'Échec')
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
      toast('success', 'Export terminé', `${totalRows} lignes récupérées sur ${tables.filter(t => t.rowCount > 0).length} tables`)
    } catch (err: any) {
      toast('error', 'Erreur export', err.message || 'échec')
    } finally {
      setLoading(false)
    }
  }

  function downloadSql() {
    if (!results) return
    const sql = generateSqlDump(results, exportedAt)
    const blob = new Blob([sql], { type: 'application/sql;charset=utf-8' })
    downloadBlob(blob, `export-compta-${new Date().toISOString().split('T')[0]}.sql`)
    toast('info', 'Téléchargement', 'Fichier SQL téléchargé')
  }

  function downloadAllCsv() {
    if (!results) return
    const tablesWithData = results.filter(t => t.rowCount > 0)
    const parts: string[] = []
    for (const t of tablesWithData) {
      parts.push(`=== ${t.tableName} (${t.rowCount} lignes) ===`)
      parts.push(generateCsvForTable(t))
      parts.push('')
    }
    const csv = parts.join('\n')
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' })
    downloadBlob(blob, `export-compta-${new Date().toISOString().split('T')[0]}.csv`)
    toast('info', 'Téléchargement', 'Fichier CSV global téléchargé')
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
    toast('info', 'Téléchargement', 'Fichier JSON téléchargé')
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
      <Breadcrumb items={[{ label: 'Paramètres' }, { label: 'Export des données' }]} />
      <PageHeader
        title="Export complet des données"
        subtitle="Récupérez toutes vos données — souveraineté garantie"
        action={
          <Button onClick={handleExport} disabled={loading}>
            {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Database className="w-4 h-4" />}
            {loading ? 'Export en cours...' : 'Lancer l\'export'}
          </Button>
        }
      />

      <div className="mb-6 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
        <div className="flex items-start gap-3">
          <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0 mt-0.5" />
          <div className="text-sm space-y-1">
            <p className="font-medium">Souveraineté de vos données</p>
            <p className="text-[var(--color-text-secondary)]">
              Cet outil récupère <strong>toutes</strong> les données stockées sur Supabase et vous permet de les télécharger
              au format SQL (importable dans PostgreSQL) ou CSV (importable dans Excel).
              Vous pouvez faire cet export quand vous voulez, y compris après la fin de votre abonnement.
            </p>
          </div>
        </div>
      </div>

      {loading && (
        <Card>
          <div className="p-8 flex flex-col items-center gap-3">
            <Loader2 className="w-8 h-8 animate-spin text-[var(--color-primary)]" />
            <p className="text-sm text-[var(--color-text-secondary)]">Récupération des données en cours...</p>
            <p className="text-xs text-[var(--color-text-secondary)]">Cette opération peut prendre 30-60 secondes selon le volume.</p>
          </div>
        </Card>
      )}

      {results && !loading && (
        <div className="space-y-4">
          <div className="flex items-center gap-3 p-4 rounded-lg bg-green-50 border border-green-200">
            <CheckCircle className="w-5 h-5 text-green-600 flex-shrink-0" />
            <div className="flex-1">
              <p className="text-sm font-medium text-green-800">
                Export terminé — {totalRows.toLocaleString()} lignes sur {tablesWithData.length} tables
              </p>
              <p className="text-xs text-green-700">Date d'export : {new Date(exportedAt).toLocaleString('fr-FR')}</p>
            </div>
          </div>

          <div className="flex flex-wrap gap-3">
            <Button onClick={downloadSql}>
              <FileText className="w-4 h-4" />
              Télécharger SQL
            </Button>
            <Button variant="secondary" onClick={downloadAllCsv}>
              <Download className="w-4 h-4" />
              Télécharger CSV global
            </Button>
            <Button variant="secondary" onClick={downloadJson}>
              <Database className="w-4 h-4" />
              Télécharger JSON
            </Button>
          </div>

          <Card>
            <div className="p-4 border-b border-[var(--color-border)]">
              <h3 className="font-semibold text-sm">Tables avec données ({tablesWithData.length})</h3>
            </div>
            <Table headers={['Table', 'Lignes', 'Colonnes', 'Taille estimée', 'Action']}>
              <tbody>
                {tablesWithData.map((t) => {
                  const sizeEstimate = Math.round(JSON.stringify(t.rows).length / 1024)
                  return (
                    <TableRow key={t.tableName}>
                      <TableCell className="font-mono text-sm">{t.tableName}</TableCell>
                      <TableCell className="text-right font-medium">{t.rowCount.toLocaleString()}</TableCell>
                      <TableCell className="text-right text-sm">{t.columns.length}</TableCell>
                      <TableCell className="text-right text-sm text-[var(--color-text-secondary)]">
                        {sizeEstimate > 1024 ? `${(sizeEstimate / 1024).toFixed(1)} Mo` : `${sizeEstimate} Ko`}
                      </TableCell>
                      <TableCell>
                        <button
                          onClick={() => downloadTableCsv(t)}
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
                  Tables vides ({emptyTables.length})
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
          title="Aucun export effectué"
          description="Cliquez sur « Lancer l'export » pour récupérer toutes vos données depuis Supabase."
          action={<Button onClick={handleExport}><Database className="w-4 h-4" /> Lancer l'export</Button>}
        />
      )}

      {/* Mirror Server Installation Section */}
      <div className="mt-8">
        <Card>
          <div className="p-6">
            <div className="flex items-center gap-3 mb-4">
              <Server className="w-6 h-6 text-[var(--color-primary)]" />
              <div>
                <h2 className="text-lg font-semibold">Serveur miroir local</h2>
                <p className="text-sm text-[var(--color-text-secondary)]">
                  Installez un programme sur un ordinateur de votre entreprise pour répliquer automatiquement toutes vos données.
                </p>
              </div>
            </div>

            {mirrorLoading ? (
              <div className="flex items-center gap-2 text-sm text-[var(--color-text-secondary)]">
                <Loader2 className="w-4 h-4 animate-spin" /> Vérification du statut...
              </div>
            ) : mirrorStatus?.exists && mirrorStatus?.install_status === 'verified' ? (
              <div className="space-y-3">
                <div className="flex items-center gap-3 p-4 rounded-lg bg-green-50 border border-green-200">
                  <CheckCircle className="w-5 h-5 text-green-600 flex-shrink-0" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-green-800">Serveur miroir actif et vérifié</p>
                    <p className="text-xs text-green-700">
                      Machine: {mirrorStatus.machine_name} • Vérifié le: {mirrorStatus.verified_at ? new Date(mirrorStatus.verified_at).toLocaleString('fr-FR') : 'N/A'}
                    </p>
                  </div>
                  <Button variant="secondary" onClick={loadMirrorStatus}>
                    <RefreshCw className="w-4 h-4" /> Actualiser
                  </Button>
                </div>
                {mirrorStatus.verification_data && (
                  <div className="text-xs text-[var(--color-text-secondary)] grid grid-cols-3 gap-4 p-3 rounded border border-[var(--color-border)]">
                    <div><strong>{mirrorStatus.verification_data.total_tables}</strong> tables synchronisées</div>
                    <div><strong>{mirrorStatus.verification_data.total_rows}</strong> lignes au total</div>
                    <div><strong>{mirrorStatus.verification_data.tables_with_data}</strong> tables avec données</div>
                  </div>
                )}
              </div>
            ) : mirrorStatus?.exists && mirrorStatus?.install_status === 'pending' ? (
              <div className="space-y-3">
                <div className="flex items-center gap-3 p-4 rounded-lg bg-yellow-50 border border-yellow-200">
                  <Loader2 className="w-5 h-5 text-yellow-600 flex-shrink-0 animate-spin" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-yellow-800">Installation en cours...</p>
                    <p className="text-xs text-yellow-700">
                      En attente de la première synchronisation depuis le serveur local.
                      Le statut se met à jour automatiquement.
                    </p>
                  </div>
                  <Button variant="secondary" onClick={loadMirrorStatus}>
                    <RefreshCw className="w-4 h-4" /> Actualiser
                  </Button>
                </div>
              </div>
            ) : mirrorStatus?.exists && mirrorStatus?.install_status === 'failed' ? (
              <div className="space-y-3">
                <div className="flex items-center gap-3 p-4 rounded-lg bg-red-50 border border-red-200">
                  <XCircle className="w-5 h-5 text-red-600 flex-shrink-0" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-red-800">Échec de l'installation</p>
                    <p className="text-xs text-red-700">La vérification a échoué. Réinstallez le serveur miroir.</p>
                  </div>
                </div>
                <div className="flex gap-3">
                  <Button onClick={() => handleInstallMirror('mac')} disabled={installing}>
                    <Apple className="w-4 h-4" /> Réinstaller sur Mac
                  </Button>
                  <Button variant="secondary" onClick={() => handleInstallMirror('windows')} disabled={installing}>
                    <Monitor className="w-4 h-4" /> Réinstaller sur Windows
                  </Button>
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                <div className="p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                  <p className="text-sm text-[var(--color-text-secondary)] mb-3">
                    Choisissez votre système et téléchargez le programme d'installation.
                    Exécutez-le sur l'ordinateur qui servira de serveur miroir.
                    Un seul serveur miroir par entreprise est autorisé.
                  </p>
                  <div className="flex gap-3">
                    <Button onClick={() => handleInstallMirror('mac')} disabled={installing}>
                      {installing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Apple className="w-4 h-4" />}
                      Installer sur Mac
                    </Button>
                    <Button variant="secondary" onClick={() => handleInstallMirror('windows')} disabled={installing}>
                      {installing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Monitor className="w-4 h-4" />}
                      Installer sur Windows
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
