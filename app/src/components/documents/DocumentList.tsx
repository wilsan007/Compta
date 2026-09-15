import { useState, useMemo, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import {
  FileText, Download, Eye, CheckCircle, XCircle, Archive,
  Trash2, Search, Lock, Shield, Globe, ShieldAlert,
} from 'lucide-react'
import { useToast } from '@/lib/toast'
import { useDocuments } from '@/hooks/useDocuments'
import { useDocumentPermissions } from '@/hooks/useDocumentPermissions'
import type { ModuleName, ModuleDocument, Confidentiality, DocumentStatus } from '@/types/documents'
import { confirmSync } from '@/lib/confirm'

interface DocumentListProps {
  module: ModuleName
  entityType?: string
  entityId?: string
}

const CONFIDENTIALITY_ICONS: Record<Confidentiality, typeof Globe> = {
  public: Globe,
  restricted: Shield,
  confidential: Lock,
  private: ShieldAlert,
}

const CONFIDENTIALITY_COLORS: Record<Confidentiality, string> = {
  public: 'text-green-600 bg-green-50',
  restricted: 'text-blue-600 bg-blue-50',
  confidential: 'text-orange-600 bg-orange-50',
  private: 'text-red-600 bg-red-50',
}

const STATUS_ICONS: Record<DocumentStatus, typeof CheckCircle> = {
  pending: FileText,
  approved: CheckCircle,
  rejected: XCircle,
  archived: Archive,
}

const STATUS_COLORS: Record<DocumentStatus, string> = {
  pending: 'text-yellow-600 bg-yellow-50',
  approved: 'text-green-600 bg-green-50',
  rejected: 'text-red-600 bg-red-50',
  archived: 'text-gray-600 bg-gray-50',
}

function formatBytes(bytes: number | null): string {
  if (!bytes) return '—'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`
}

function formatDate(iso: string | null): string {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })
}

export function DocumentList({ module, entityType, entityId }: DocumentListProps) {
  const { t } = useTranslation(['documents', 'common'])
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const docs = useDocuments(module, { entityType, entityId })
  const perms = useDocumentPermissions(module)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<DocumentStatus | 'all'>('all')
  const [confFilter, setConfFilter] = useState<Confidentiality | 'all'>('all')
  const [rejectingId, setRejectingId] = useState<string | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [previewName, setPreviewName] = useState('')

  const filteredDocs = useMemo(() => {
    return docs.visibleDocuments.filter(doc => {
      if (statusFilter !== 'all' && doc.status !== statusFilter) return false
      if (confFilter !== 'all' && doc.confidentiality !== confFilter) return false
      if (search) {
        const q = search.toLowerCase()
        return (
          doc.title.toLowerCase().includes(q) ||
          doc.file_name.toLowerCase().includes(q) ||
          doc.document_type.toLowerCase().includes(q)
        )
      }
      return true
    })
  }, [docs.visibleDocuments, statusFilter, confFilter, search])

  const handleDownload = useCallback(async (doc: ModuleDocument) => {
    try {
      await docs.download(doc)
    } catch (err: any) {
      console.error('Download failed:', err.message)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [docs, toast, tCommon])

  const handlePreview = useCallback(async (doc: ModuleDocument) => {
    try {
      const url = await docs.preview(doc)
      setPreviewUrl(url)
      setPreviewName(doc.file_name)
    } catch (err: any) {
      console.error('Preview failed:', err.message)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [docs, tCommon, toast])

  const handleApprove = useCallback(async (id: string) => {
    try {
      await docs.approve(id)
    } catch (err: any) {
      console.error('Approve failed:', err.message)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [docs, tCommon, toast])

  const handleReject = useCallback(async () => {
    if (!rejectingId || !rejectReason) return
    try {
      await docs.reject(rejectingId, rejectReason)
      setRejectingId(null)
      setRejectReason('')
    } catch (err: any) {
      console.error('Reject failed:', err.message)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [docs, rejectingId, rejectReason, tCommon, toast])

  const handleArchive = useCallback(async (id: string) => {
    try {
      await docs.archive(id)
    } catch (err: any) {
      console.error('Archive failed:', err.message)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [docs, tCommon, toast])

  const handleDelete = useCallback(async (id: string) => {
    if (!confirmSync(t('documents:list.confirmDelete'))) return
    try {
      await docs.remove(id)
    } catch (err: any) {
      console.error('Delete failed:', err.message)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [docs, t, tCommon, toast])

  if (docs.loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    )
  }

  if (docs.error) {
    return (
      <div className="rounded-lg bg-destructive/10 p-4 text-sm text-destructive">
        {docs.error}
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-2 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t('documents:list.searchPlaceholder')}
            className="w-full rounded-md border border-input bg-background pl-8 pr-3 py-2 text-sm"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as DocumentStatus | 'all')}
          className="rounded-md border border-input bg-background px-3 py-2 text-sm"
        >
          <option value="all">{t('documents:list.allStatuses')}</option>
          <option value="pending">{t('documents:status.pending')}</option>
          <option value="approved">{t('documents:status.approved')}</option>
          <option value="rejected">{t('documents:status.rejected')}</option>
          <option value="archived">{t('documents:status.archived')}</option>
        </select>
        <select
          value={confFilter}
          onChange={(e) => setConfFilter(e.target.value as Confidentiality | 'all')}
          className="rounded-md border border-input bg-background px-3 py-2 text-sm"
        >
          <option value="all">{t('documents:list.allConfidentiality')}</option>
          <option value="public">{t('documents:confidentiality.public')}</option>
          <option value="restricted">{t('documents:confidentiality.restricted')}</option>
          <option value="confidential">{t('documents:confidentiality.confidential')}</option>
          <option value="private">{t('documents:confidentiality.private')}</option>
        </select>
      </div>

      {/* Empty state */}
      {filteredDocs.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-12 text-center">
          <FileText className="h-12 w-12 text-muted-foreground/40" />
          <p className="mt-2 text-sm text-muted-foreground">{t('documents:list.empty')}</p>
        </div>
      ) : (
        /* Document list */
        <div className="divide-y divide-border rounded-lg border border-border">
          {filteredDocs.map(doc => {
            const ConfIcon = CONFIDENTIALITY_ICONS[doc.confidentiality]
            const StatusIcon = STATUS_ICONS[doc.status]
            const canDownload = perms.canDownload(doc.confidentiality)
            return (
              <div key={doc.id} className="flex items-center gap-3 p-3 hover:bg-accent/30">
                {/* File icon */}
                <div className="shrink-0">
                  <FileText className="h-8 w-8 text-muted-foreground" />
                </div>

                {/* Info */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium truncate">{doc.title}</p>
                    <span className={`inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-xs font-medium ${CONFIDENTIALITY_COLORS[doc.confidentiality]}`}>
                      <ConfIcon className="h-3 w-3" />
                      {t(`documents:confidentiality.${doc.confidentiality}`)}
                    </span>
                    <span className={`inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-xs font-medium ${STATUS_COLORS[doc.status]}`}>
                      <StatusIcon className="h-3 w-3" />
                      {t(`documents:status.${doc.status}`)}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 mt-0.5 text-xs text-muted-foreground">
                    <span>{doc.file_name}</span>
                    <span>{formatBytes(doc.file_size)}</span>
                    <span>{formatDate(doc.created_at)}</span>
                    {doc.download_count > 0 && (
                      <span>{t('documents:list.downloads', { count: doc.download_count })}</span>
                    )}
                  </div>
                  {doc.rejection_reason && (
                    <p className="mt-1 text-xs text-destructive">
                      {t('documents:list.rejectedReason')}: {doc.rejection_reason}
                    </p>
                  )}
                </div>

                {/* Actions */}
                <div className="flex items-center gap-1 shrink-0">
                  {canDownload && (
                    <button
                      onClick={() => handlePreview(doc)}
                      className="rounded p-1.5 text-muted-foreground hover:bg-accent hover:text-foreground"
                      title={t('documents:list.preview')}
                    >
                      <Eye className="h-4 w-4" />
                    </button>
                  )}
                  {canDownload && (
                    <button
                      onClick={() => handleDownload(doc)}
                      className="rounded p-1.5 text-muted-foreground hover:bg-accent hover:text-foreground"
                      title={t('documents:list.download')}
                    >
                      <Download className="h-4 w-4" />
                    </button>
                  )}
                  {perms.canApprove && doc.status === 'pending' && (
                    <button
                      onClick={() => handleApprove(doc.id)}
                      className="rounded p-1.5 text-green-600 hover:bg-green-50"
                      title={t('documents:list.approve')}
                    >
                      <CheckCircle className="h-4 w-4" />
                    </button>
                  )}
                  {perms.canReject && doc.status === 'pending' && (
                    <button
                      onClick={() => { setRejectingId(doc.id); setRejectReason('') }}
                      className="rounded p-1.5 text-red-600 hover:bg-red-50"
                      title={t('documents:list.reject')}
                    >
                      <XCircle className="h-4 w-4" />
                    </button>
                  )}
                  {perms.canArchive && doc.status === 'approved' && (
                    <button
                      onClick={() => handleArchive(doc.id)}
                      className="rounded p-1.5 text-muted-foreground hover:bg-accent"
                      title={t('documents:list.archive')}
                    >
                      <Archive className="h-4 w-4" />
                    </button>
                  )}
                  {perms.canDelete && (
                    <button
                      onClick={() => handleDelete(doc.id)}
                      className="rounded p-1.5 text-destructive hover:bg-destructive/10"
                      title={t('documents:list.delete')}
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* Reject dialog */}
      {rejectingId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={() => setRejectingId(null)}>
          <div className="bg-card rounded-lg p-6 max-w-md w-full mx-4 space-y-4" onClick={e => e.stopPropagation()}>
            <h3 className="text-sm font-semibold">{t('documents:list.rejectTitle')}</h3>
            <textarea
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value)}
              placeholder={t('documents:list.rejectPlaceholder')}
              rows={3}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            />
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setRejectingId(null)}
                className="rounded-md border border-input px-4 py-2 text-sm font-medium hover:bg-accent"
              >
                {t('common:cancel')}
              </button>
              <button
                onClick={handleReject}
                disabled={!rejectReason}
                className="rounded-md bg-destructive px-4 py-2 text-sm font-medium text-destructive-foreground hover:bg-destructive/90 disabled:opacity-50"
              >
                {t('documents:list.confirmReject')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Preview modal */}
      {previewUrl && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={() => { setPreviewUrl(null); setPreviewName('') }}>
          <div className="bg-card rounded-lg p-4 max-w-4xl w-full mx-4 h-[80vh] flex flex-col" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-sm font-semibold truncate">{previewName}</h3>
              <button
                onClick={() => { setPreviewUrl(null); setPreviewName('') }}
                className="text-muted-foreground hover:text-foreground"
              >
                <XCircle className="h-5 w-5" />
              </button>
            </div>
            <iframe src={previewUrl} className="flex-1 w-full rounded-md border border-border" title={previewName} />
          </div>
        </div>
      )}
    </div>
  )
}
