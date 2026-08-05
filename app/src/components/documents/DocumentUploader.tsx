import { useState, useCallback, useRef } from 'react'
import { useTranslation } from 'react-i18next'
import { Upload, FileText, AlertCircle, X } from 'lucide-react'
import { useDocuments } from '@/hooks/useDocuments'
import type { ModuleName, Confidentiality, DocumentCreateInput } from '@/types/documents'

interface DocumentUploaderProps {
  module: ModuleName
  entityType?: string
  entityId?: string
  onUploaded?: () => void
}

const CONFIDENTIALITY_OPTIONS: { value: Confidentiality; labelKey: string }[] = [
  { value: 'public', labelKey: 'documents:confidentiality.public' },
  { value: 'restricted', labelKey: 'documents:confidentiality.restricted' },
  { value: 'confidential', labelKey: 'documents:confidentiality.confidential' },
  { value: 'private', labelKey: 'documents:confidentiality.private' },
]

export function DocumentUploader({
  module,
  entityType,
  entityId,
  onUploaded,
}: DocumentUploaderProps) {
  const { t } = useTranslation(['documents', 'common'])
  const { upload, canUpload } = useDocuments(module)
  const [isDragging, setIsDragging] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [confidentiality, setConfidentiality] = useState<Confidentiality>('restricted')
  const [documentType, setDocumentType] = useState('other')
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }, [])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
  }, [])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
    const files = Array.from(e.dataTransfer.files)
    if (files.length > 0) {
      setSelectedFile(files[0])
      if (!title) setTitle(files[0].name.replace(/\.[^.]+$/, ''))
    }
  }, [title])

  const handleFileSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setSelectedFile(file)
      if (!title) setTitle(file.name.replace(/\.[^.]+$/, ''))
    }
  }, [title])

  const handleUpload = useCallback(async () => {
    if (!selectedFile) return
    setUploading(true)
    setError(null)
    try {
      const input: DocumentCreateInput = {
        module,
        document_type: documentType,
        confidentiality,
        entity_type: entityType || null,
        entity_id: entityId || null,
        title,
        description: description || null,
      }
      await upload(selectedFile, input, entityId)
      setSelectedFile(null)
      setTitle('')
      setDescription('')
      setConfidentiality('restricted')
      setDocumentType('other')
      onUploaded?.()
    } catch (err: any) {
      setError(err.message || t('documents:errors.uploadFailed'))
    } finally {
      setUploading(false)
    }
  }, [selectedFile, module, documentType, confidentiality, entityType, entityId, title, description, upload, onUploaded, t])

  const handleCancel = useCallback(() => {
    setSelectedFile(null)
    setTitle('')
    setDescription('')
    setError(null)
  }, [])

  if (!canUpload) return null

  return (
    <div className="rounded-lg border border-border bg-card p-4 space-y-4">
      <div className="flex items-center gap-2">
        <Upload className="h-5 w-5 text-primary" />
        <h3 className="text-sm font-semibold">{t('documents:uploader.title')}</h3>
      </div>

      {/* Drop zone */}
      <div
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        onClick={() => fileInputRef.current?.click()}
        className={`border-2 border-dashed rounded-lg p-6 text-center cursor-pointer transition-colors ${
          isDragging
            ? 'border-primary bg-primary/5'
            : 'border-muted-foreground/30 hover:border-muted-foreground/50'
        }`}
      >
        <input
          ref={fileInputRef}
          type="file"
          className="hidden"
          onChange={handleFileSelect}
          accept=".pdf,.png,.jpg,.jpeg,.webp,.docx,.xlsx,.pptx,.doc,.xls,.txt,.csv,.zip"
        />
        {selectedFile ? (
          <div className="flex items-center justify-center gap-2">
            <FileText className="h-5 w-5 text-primary" />
            <span className="text-sm font-medium">{selectedFile.name}</span>
            <span className="text-xs text-muted-foreground">
              ({(selectedFile.size / 1024 / 1024).toFixed(2)} MB)
            </span>
            <button
              onClick={(e) => { e.stopPropagation(); handleCancel() }}
              className="ml-2 text-muted-foreground hover:text-destructive"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        ) : (
          <div className="space-y-1">
            <p className="text-sm text-muted-foreground">{t('documents:uploader.dropzone')}</p>
            <p className="text-xs text-muted-foreground/70">{t('documents:uploader.formats')}</p>
          </div>
        )}
      </div>

      {/* Metadata form */}
      {selectedFile && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground">
              {t('documents:uploader.titleLabel')}
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={t('documents:uploader.titlePlaceholder')}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground">
              {t('documents:uploader.typeLabel')}
            </label>
            <input
              type="text"
              value={documentType}
              onChange={(e) => setDocumentType(e.target.value)}
              placeholder={t('documents:uploader.typePlaceholder')}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            />
          </div>
          <div className="space-y-1 md:col-span-2">
            <label className="text-xs font-medium text-muted-foreground">
              {t('documents:uploader.descriptionLabel')}
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={t('documents:uploader.descriptionPlaceholder')}
              rows={2}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground">
              {t('documents:uploader.confidentialityLabel')}
            </label>
            <select
              value={confidentiality}
              onChange={(e) => setConfidentiality(e.target.value as Confidentiality)}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            >
              {CONFIDENTIALITY_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>
                  {t(opt.labelKey)}
                </option>
              ))}
            </select>
          </div>
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="flex items-center gap-2 rounded-md bg-destructive/10 p-2 text-sm text-destructive">
          <AlertCircle className="h-4 w-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* Actions */}
      {selectedFile && (
        <div className="flex justify-end gap-2">
          <button
            onClick={handleCancel}
            className="rounded-md border border-input px-4 py-2 text-sm font-medium hover:bg-accent"
          >
            {t('common:cancel')}
          </button>
          <button
            onClick={handleUpload}
            disabled={uploading || !title}
            className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
          >
            {uploading ? t('documents:uploader.uploading') : t('documents:uploader.upload')}
          </button>
        </div>
      )}
    </div>
  )
}
