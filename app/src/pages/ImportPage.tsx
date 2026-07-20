import { useState, useMemo, useRef } from 'react'
import * as XLSX from 'xlsx'
import { Card, PageHeader, Button, Breadcrumb, Badge, Select } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { useToast } from '@/lib/toast'
import { supabase } from '@/lib/supabase'
import {
  IMPORT_MODULES, coerceValue, type ImportModule,
} from '@/lib/importConfig'
import {
  autoMapColumns, aiFallbackMapping, confidenceLabel, confidenceVariant,
  type AutoMappingResult,
} from '@/lib/aiImportMapping'
import {
  Upload, Download, FileSpreadsheet, ArrowRight, ArrowLeft, CheckCircle2,
  AlertCircle, Loader2, ListOrdered, Sparkles, Eye, Columns3, Brain,
} from 'lucide-react'

type Step = 'select' | 'upload' | 'map' | 'result'

interface ParsedRow {
  [key: string]: any
}

interface ImportResult {
  inserted: number
  failed: number
  errors: string[]
}

export function ImportPage() {
  const { user } = useAuth()
  const { toast } = useToast()
  const [step, setStep] = useState<Step>('select')
  const [activeModule, setActiveModule] = useState<ImportModule | null>(null)
  const [headers, setHeaders] = useState<string[]>([])
  const [rows, setRows] = useState<ParsedRow[]>([])
  const [mapping, setMapping] = useState<Record<string, string>>({})
  const [autoMapping, setAutoMapping] = useState<AutoMappingResult | null>(null)
  const [importing, setImporting] = useState(false)
  const [result, setResult] = useState<ImportResult | null>(null)
  const [showPreview, setShowPreview] = useState(false)
  const [aiLoading, setAiLoading] = useState(false)
  const [aiReasoning, setAiReasoning] = useState<Record<string, string> | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const sortedModules = useMemo(
    () => [...IMPORT_MODULES].sort((a, b) => a.order - b.order),
    []
  )

  function reset() {
    setActiveModule(null)
    setHeaders([])
    setRows([])
    setMapping({})
    setAutoMapping(null)
    setResult(null)
    setShowPreview(false)
    setAiLoading(false)
    setAiReasoning(null)
    setStep('select')
  }

  function startModule(mod: ImportModule) {
    setActiveModule(mod)
    setStep('upload')
  }

  function downloadTemplate(mod: ImportModule) {
    const headerRow = mod.fields.map((f) => f.label + (f.required ? ' *' : ''))
    const sampleRow = mod.fields.map((f) => f.sample)
    const ws = XLSX.utils.aoa_to_sheet([headerRow, sampleRow])
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, ws, mod.label.slice(0, 31))
    XLSX.writeFile(wb, `modele_${mod.id}.xlsx`)
  }

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file || !activeModule) return
    const reader = new FileReader()
    reader.onload = (evt) => {
      try {
        const data = new Uint8Array(evt.target!.result as ArrayBuffer)
        const wb = XLSX.read(data, { type: 'array' })
        const ws = wb.Sheets[wb.SheetNames[0]]
        const json = XLSX.utils.sheet_to_json<ParsedRow>(ws, { defval: '' })
        if (json.length === 0) {
          toast('error', 'Fichier vide', 'Aucune ligne détectée dans le fichier.')
          return
        }
        const fileHeaders = Object.keys(json[0])
        setHeaders(fileHeaders)
        setRows(json)
        // Smart auto-mapping: fuzzy matching + synonyms + content analysis
        const result = autoMapColumns(
          fileHeaders,
          json.slice(0, 20),
          activeModule.fields.map((f) => ({ key: f.key, label: f.label, required: f.required })),
        )
        setAutoMapping(result)
        setMapping(result.mapping)
        if (result.confidence >= 0.8) {
          toast('success', 'Colonnes détectées', `${result.suggestions.length}/${activeModule.fields.length} champs mappés automatiquement.`)
        } else if (result.confidence >= 0.5) {
          toast('info', 'Mapping partiel', `${result.suggestions.length}/${activeModule.fields.length} champs détectés. Vérifiez les colonnes manquantes.`)
        } else {
          toast('warning', 'Mapping manuel requis', 'Peu de colonnes reconnues. Associez manuellement les champs.')
        }
        setStep('map')
      } catch (err: any) {
        toast('error', 'Erreur de lecture', err.message || 'Fichier illisible')
      }
    }
    reader.readAsArrayBuffer(file)
    e.target.value = ''
  }

  async function handleImport() {
    if (!activeModule || !user?.tenantId) return
    setImporting(true)
    const payload: ParsedRow[] = []
    const errors: string[] = []

    rows.forEach((row, idx) => {
      const record: ParsedRow = { tenant_id: user.tenantId }
      let rowHasError = false
      for (const field of activeModule.fields) {
        const sourceCol = mapping[field.key]
        const raw = sourceCol ? row[sourceCol] : undefined
        const { value, error } = coerceValue(field, raw)
        if (error) {
          errors.push(`Ligne ${idx + 2}: ${error}`)
          rowHasError = true
        } else if (value !== null && value !== undefined) {
          record[field.key] = value
        }
      }
      if (!rowHasError) payload.push(record)
    })

    if (payload.length === 0) {
      setResult({ inserted: 0, failed: rows.length, errors: errors.slice(0, 50) })
      setStep('result')
      setImporting(false)
      return
    }

    // Insert in batches of 200
    let inserted = 0
    for (let i = 0; i < payload.length; i += 200) {
      const batch = payload.slice(i, i + 200)
      const { error } = await supabase.from(activeModule.table).insert(batch)
      if (error) {
        errors.push(`Lot ${i / 200 + 1}: ${error.message}`)
      } else {
        inserted += batch.length
      }
    }

    setResult({
      inserted,
      failed: rows.length - inserted,
      errors: errors.slice(0, 50),
    })
    setStep('result')
    setImporting(false)
    if (inserted > 0) toast('success', 'Import terminé', `${inserted} ligne(s) importée(s)`)
  }

  async function handleAIFallback() {
    if (!activeModule || !autoMapping) return
    setAiLoading(true)
    try {
      const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || ''
      const edgeUrl = `${supabaseUrl}/functions/v1/ai-import-mapping`
      const result = await aiFallbackMapping(
        headers,
        rows.slice(0, 20),
        activeModule.fields.map((f) => ({ key: f.key, label: f.label, required: f.required })),
        activeModule.label,
        edgeUrl,
      )
      if (!result) {
        toast('error', 'IA indisponible', "Le service d'auto-détection IA n'est pas accessible. Associez les colonnes manuellement.")
        setAiLoading(false)
        return
      }
      // Merge AI mapping with existing heuristic mapping (AI takes priority for new fields)
      const mergedMapping = { ...mapping, ...result.mapping }
      setMapping(mergedMapping)
      setAiReasoning(result.reasoning)
      // Update auto-mapping confidence
      const mappedCount = Object.values(mergedMapping).filter(Boolean).length
      const newConfidence = mappedCount / activeModule.fields.length
      setAutoMapping({
        ...autoMapping,
        mapping: mergedMapping,
        confidence: newConfidence,
        suggestions: [
          ...autoMapping.suggestions,
          ...Object.entries(result.mapping)
            .filter(([key]) => !autoMapping.suggestions.find((s) => s.fieldKey === key))
            .map(([key, col]) => ({
              fieldKey: key,
              sourceColumn: col,
              confidence: result.confidence,
              reason: result.reasoning[key] || 'détecté par IA',
            })),
        ],
        unmappedFields: activeModule.fields
          .filter((f) => !mergedMapping[f.key])
          .map((f) => f.key),
        unmappedColumns: headers.filter((h) => !Object.values(mergedMapping).includes(h)),
      })
      toast('success', 'Détection IA terminée', `${Object.keys(result.mapping).length} champ(s) détecté(s) par l'IA.`)
    } catch (err: any) {
      toast('error', 'Erreur IA', err.message || "Erreur lors de l'analyse IA")
    }
    setAiLoading(false)
  }

  const canImport = user?.role === 'admin' || user?.role === 'accountant'

  return (
    <div>
      <Breadcrumb items={[{ label: 'Paramètres' }, { label: 'Import de données' }]} />
      <PageHeader
        title="Import de données"
        subtitle="Importez vos données existantes depuis Excel ou CSV, module par module"
      />

      {!canImport && (
        <Card>
          <div className="p-6 flex items-center gap-3 text-[var(--color-text-secondary)]">
            <AlertCircle className="w-5 h-5 text-[var(--color-danger)]" />
            <span>Seuls les administrateurs et comptables peuvent importer des données.</span>
          </div>
        </Card>
      )}

      {canImport && step === 'select' && (
        <>
          <Card className="mb-4">
            <div className="p-4 flex items-start gap-3">
              <ListOrdered className="w-5 h-5 text-[var(--color-primary)] flex-shrink-0 mt-0.5" />
              <div className="text-sm text-[var(--color-text-secondary)]">
                <strong className="text-[var(--color-text)]">Ordre d'import recommandé.</strong> Importez
                dans l'ordre affiché : le plan comptable d'abord, puis les tiers (clients/fournisseurs),
                puis les produits. Les factures et écritures s'appuient sur ces référentiels.
              </div>
            </div>
          </Card>

          <div className="grid gap-3 md:grid-cols-2">
            {sortedModules.map((mod) => (
              <Card key={mod.id}>
                <div className="p-5">
                  <div className="flex items-center gap-2 mb-1">
                    <Badge variant="primary">Étape {mod.order}</Badge>
                    <h3 className="font-semibold text-[var(--color-text)]">{mod.label}</h3>
                  </div>
                  <p className="text-sm text-[var(--color-text-secondary)] mb-4">{mod.description}</p>
                  <div className="flex gap-2">
                    <Button onClick={() => startModule(mod)}>
                      <Upload className="w-4 h-4" /> Importer
                    </Button>
                    <Button variant="secondary" onClick={() => downloadTemplate(mod)}>
                      <Download className="w-4 h-4" /> Modèle Excel
                    </Button>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        </>
      )}

      {canImport && step === 'upload' && activeModule && (
        <Card>
          <div className="p-6">
            <h3 className="font-semibold text-[var(--color-text)] mb-1">
              Importer : {activeModule.label}
            </h3>
            <p className="text-sm text-[var(--color-text-secondary)] mb-6">
              Téléchargez le modèle, remplissez-le, puis chargez votre fichier (.xlsx ou .csv).
            </p>

            <div
              className="border-2 border-dashed border-[var(--color-border)] rounded-xl p-10 text-center cursor-pointer hover:border-[var(--color-primary)] transition-colors"
              onClick={() => fileInputRef.current?.click()}
            >
              <FileSpreadsheet className="w-10 h-10 mx-auto text-[var(--color-text-secondary)] mb-3" />
              <p className="text-sm font-medium text-[var(--color-text)]">Cliquez pour choisir un fichier</p>
              <p className="text-xs text-[var(--color-text-secondary)] mt-1">Formats acceptés : .xlsx, .xls, .csv</p>
              <input
                ref={fileInputRef}
                type="file"
                accept=".xlsx,.xls,.csv"
                className="hidden"
                onChange={handleFile}
              />
            </div>

            <div className="flex gap-2 mt-6">
              <Button variant="secondary" onClick={reset}>
                <ArrowLeft className="w-4 h-4" /> Retour
              </Button>
              <Button variant="secondary" onClick={() => downloadTemplate(activeModule)}>
                <Download className="w-4 h-4" /> Télécharger le modèle
              </Button>
            </div>
          </div>
        </Card>
      )}

      {canImport && step === 'map' && activeModule && autoMapping && (
        <>
          {/* Confidence summary banner */}
          <Card className="mb-4">
            <div className="p-4 flex items-center gap-4">
              <Sparkles className="w-6 h-6 text-[var(--color-primary)] flex-shrink-0" />
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-sm font-semibold text-[var(--color-text)]">
                    Détection automatique
                  </span>
                  <Badge variant={confidenceVariant(autoMapping.confidence)}>
                    {Math.round(autoMapping.confidence * 100)}% — {confidenceLabel(autoMapping.confidence)}
                  </Badge>
                </div>
                <p className="text-xs text-[var(--color-text-secondary)]">
                  {autoMapping.suggestions.length}/{activeModule.fields.length} champs mappés automatiquement.
                  {autoMapping.unmappedFields.length > 0 && (
                    <> {autoMapping.unmappedFields.length} champ(s) à associer manuellement.</>
                  )}
                  {autoMapping.unmappedColumns.length > 0 && (
                    <> {autoMapping.unmappedColumns.length} colonne(s) non assignée(s).</>
                  )}
                </p>
              </div>
              <div className="flex gap-2">
                {autoMapping.confidence < 0.5 && (
                  <Button
                    onClick={handleAIFallback}
                    disabled={aiLoading}
                  >
                    {aiLoading ? (
                      <><Loader2 className="w-4 h-4 animate-spin" /> Analyse IA...</>
                    ) : (
                      <><Brain className="w-4 h-4" /> Auto-détection IA</>
                    )}
                  </Button>
                )}
                <Button
                  variant="secondary"
                  onClick={() => setShowPreview((v) => !v)}
                >
                  <Eye className="w-4 h-4" /> {showPreview ? 'Masquer' : 'Aperçu'}
                </Button>
              </div>
            </div>
          </Card>

          {/* Data preview table */}
          {showPreview && (
            <Card className="mb-4">
              <div className="p-4">
                <h4 className="text-sm font-semibold text-[var(--color-text)] mb-3">
                  Aperçu des 5 premières lignes
                </h4>
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-[var(--color-border)]">
                        <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">#</th>
                        {headers.map((h) => (
                          <th
                            key={h}
                            className={`text-left p-2 font-medium ${
                              autoMapping.unmappedColumns.includes(h)
                                ? 'text-[var(--color-text-secondary)] italic'
                                : 'text-[var(--color-text)]'
                            }`}
                          >
                            {h}
                            {autoMapping.unmappedColumns.includes(h) && (
                              <span className="block text-[9px] text-[var(--color-text-secondary)]">non assignée</span>
                            )}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {rows.slice(0, 5).map((row, i) => (
                        <tr key={i} className="border-b border-[var(--color-border)] last:border-0">
                          <td className="p-2 text-[var(--color-text-secondary)]">{i + 1}</td>
                          {headers.map((h) => (
                            <td key={h} className="p-2 text-[var(--color-text)] max-w-[180px] truncate">
                              {String(row[h] ?? '')}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </Card>
          )}

          {/* Unmapped columns warning */}
          {autoMapping.unmappedColumns.length > 0 && (
            <Card className="mb-4">
              <div className="p-4 flex items-start gap-3">
                <Columns3 className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0 mt-0.5" />
                <div className="text-sm">
                  <span className="font-medium text-[var(--color-text)]">Colonnes non reconnues : </span>
                  <span className="text-[var(--color-text-secondary)]">
                    {autoMapping.unmappedColumns.join(', ')}
                  </span>
                  <p className="text-xs text-[var(--color-text-secondary)] mt-1">
                    Ces colonnes de votre fichier n'ont été associées à aucun champ. Si elles contiennent des données utiles, associez-les manuellement ci-dessous.
                  </p>
                </div>
              </div>
            </Card>
          )}

          {/* Field mapping table */}
          <Card>
            <div className="p-6">
              <h3 className="font-semibold text-[var(--color-text)] mb-1">
                Correspondance des colonnes — {rows.length} ligne(s)
              </h3>
              <p className="text-sm text-[var(--color-text-secondary)] mb-6">
                Vérifiez l'auto-détection et ajustez si nécessaire. Les champs marqués * sont obligatoires.
              </p>

              <div className="space-y-3">
                {activeModule.fields.map((field) => {
                  const sug = autoMapping.suggestions.find((s) => s.fieldKey === field.key)
                  const isMapped = !!mapping[field.key]
                  const score = sug?.confidence ?? 0
                  return (
                    <div
                      key={field.key}
                      className={`flex items-center gap-4 rounded-lg p-2 transition-colors ${
                        !isMapped && field.required
                          ? 'bg-[var(--color-danger-bg,rgba(220,38,38,0.05))]'
                          : isMapped && score < 0.6
                            ? 'bg-[var(--color-warning-bg,rgba(245,158,11,0.05))]'
                            : ''
                      }`}
                    >
                      <div className="w-48 flex-shrink-0">
                        <span className="text-sm font-medium text-[var(--color-text)]">{field.label}</span>
                        {field.required && <span className="text-[var(--color-danger)] ml-0.5">*</span>}
                        {field.type === 'enum' && (
                          <p className="text-[10px] text-[var(--color-text-secondary)]">{field.enumValues?.join(' / ')}</p>
                        )}
                      </div>
                      <div className="flex-1">
                        <Select
                          value={mapping[field.key] || ''}
                          onChange={(e) => setMapping((prev) => ({ ...prev, [field.key]: e.target.value }))}
                          options={[
                            { value: '', label: '— Ignorer —' },
                            ...headers.map((h) => ({ value: h, label: h })),
                          ]}
                        />
                      </div>
                      <div className="w-32 flex-shrink-0 text-right">
                        {isMapped ? (
                          <div className="flex items-center justify-end gap-1.5">
                            <Badge variant={confidenceVariant(score)}>
                              {confidenceLabel(score)}
                            </Badge>
                          </div>
                        ) : (
                          <span className="text-xs text-[var(--color-text-secondary)] italic">non détecté</span>
                        )}
                      </div>
                      {sug && sug.reason && isMapped && (
                        <div className="w-40 flex-shrink-0 text-[10px] text-[var(--color-text-secondary)] truncate flex items-center gap-1" title={sug.reason}>
                          {aiReasoning?.[field.key] && <Brain className="w-3 h-3 flex-shrink-0 text-[var(--color-primary)]" />}
                          {sug.reason}
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>

              <div className="flex gap-2 mt-6">
                <Button variant="secondary" onClick={() => setStep('upload')}>
                  <ArrowLeft className="w-4 h-4" /> Retour
                </Button>
                <Button onClick={handleImport} disabled={importing}>
                  {importing ? <Loader2 className="w-4 h-4 animate-spin" /> : <ArrowRight className="w-4 h-4" />}
                  Importer {rows.length} ligne(s)
                </Button>
              </div>
            </div>
          </Card>
        </>
      )}

      {canImport && step === 'result' && result && (
        <Card>
          <div className="p-6">
            <div className="flex items-center gap-3 mb-4">
              {result.inserted > 0 ? (
                <CheckCircle2 className="w-8 h-8 text-[var(--color-success)]" />
              ) : (
                <AlertCircle className="w-8 h-8 text-[var(--color-danger)]" />
              )}
              <div>
                <h3 className="font-semibold text-[var(--color-text)]">Import terminé</h3>
                <p className="text-sm text-[var(--color-text-secondary)]">
                  {result.inserted} ligne(s) importée(s), {result.failed} en échec.
                </p>
              </div>
            </div>

            {result.errors.length > 0 && (
              <div className="border border-[var(--color-border)] rounded-lg p-3 max-h-64 overflow-y-auto bg-[var(--color-neutral-50)]">
                <p className="text-sm font-medium text-[var(--color-danger)] mb-2">
                  Erreurs ({result.errors.length}) :
                </p>
                <ul className="text-xs text-[var(--color-text-secondary)] space-y-1">
                  {result.errors.map((err, i) => (
                    <li key={i}>{err}</li>
                  ))}
                </ul>
              </div>
            )}

            <div className="flex gap-2 mt-6">
              <Button onClick={reset}>Importer un autre module</Button>
            </div>
          </div>
        </Card>
      )}
    </div>
  )
}

