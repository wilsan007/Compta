// Document Management System Types
// Used across all modules: projectManagement, accounting, hr, commercial, treasury, stock, production, general

export type ModuleName =
  | 'projectManagement'
  | 'accounting'
  | 'hr'
  | 'commercial'
  | 'treasury'
  | 'stock'
  | 'production'
  | 'general'

export type Confidentiality = 'public' | 'restricted' | 'confidential' | 'private'

export type DocumentStatus = 'pending' | 'approved' | 'rejected' | 'archived'

export type DocumentAccessAction =
  | 'upload'
  | 'download'
  | 'preview'
  | 'approve'
  | 'reject'
  | 'archive'
  | 'delete'
  | 'share'

export type ModuleRole =
  // Project Management
  | 'project_director'
  | 'project_manager'
  | 'team_member'
  | 'consultant'
  | 'guest'
  // Accounting
  | 'accountant'
  | 'auditor'
  | 'custom'
  // HR
  | 'hr_director'
  | 'hr_manager'
  | 'hr_employee'
  // Commercial
  | 'sales_director'
  | 'sales_rep'
  | 'sales_employee'
  // Treasury
  | 'treasurer'
  | 'treasury_viewer'
  // Stock
  | 'warehouse_manager'
  | 'stock_clerk'
  // Production
  | 'production_manager'
  | 'production_operator'

export interface ModuleDocument {
  id: string
  tenant_id: string
  module: ModuleName
  document_type: string
  confidentiality: Confidentiality
  entity_type: string | null
  entity_id: string | null
  title: string
  description: string | null
  file_url: string
  file_name: string
  file_size: number | null
  mime_type: string | null
  file_hash: string | null
  status: DocumentStatus
  approved_by: string | null
  approved_at: string | null
  rejection_reason: string | null
  expires_at: string | null
  archived_at: string | null
  uploaded_by: string
  metadata: Record<string, any>
  download_count: number
  created_at: string
  updated_at: string
}

export interface DocumentAccessLog {
  id: string
  tenant_id: string
  document_id: string
  user_id: string
  action: DocumentAccessAction
  ip_address: string | null
  user_agent: string | null
  created_at: string
}

export interface DocumentShare {
  id: string
  tenant_id: string
  document_id: string
  share_token: string
  password_hash: string | null
  created_by: string
  expires_at: string | null
  max_downloads: number | null
  download_count: number
  created_at: string
}

export interface GuestPermissions {
  projectIds: string[]
  views: {
    table: boolean
    kanban: boolean
    gantt: boolean
    calendar: boolean
    timeline: boolean
    box: boolean
    mindmap: boolean
    graph: boolean
    pivot: boolean
    burndown: boolean
    workload: boolean
    activity: boolean
    documents: boolean
    chat: boolean
  }
  perProject: {
    tasks: boolean
    subtasks: boolean
    documents: boolean
    comments: boolean
    addComments: boolean
    addRemarks: boolean
    assignees: boolean
    dates: boolean
    budget: boolean
    progress: boolean
  }
}

export interface ModuleRoles {
  projectManagement?: ModuleRole
  accounting?: ModuleRole
  hr?: ModuleRole
  commercial?: ModuleRole
  treasury?: ModuleRole
  stock?: ModuleRole
  production?: ModuleRole
}

export interface DocumentCreateInput {
  module: ModuleName
  document_type: string
  confidentiality: Confidentiality
  entity_type?: string | null
  entity_id?: string | null
  title: string
  description?: string | null
  metadata?: Record<string, any>
  expires_at?: string | null
}

export interface DocumentUpdateInput {
  title?: string
  description?: string | null
  confidentiality?: Confidentiality
  status?: DocumentStatus
  rejection_reason?: string | null
  metadata?: Record<string, any>
}

export interface DocumentUploadResult {
  document: ModuleDocument
  file_url: string
}

export const BUCKET_BY_MODULE: Record<ModuleName, string> = {
  projectManagement: 'project-docs',
  accounting: 'accounting-docs',
  hr: 'hr-docs',
  commercial: 'commercial-docs',
  treasury: 'accounting-docs',
  stock: 'commercial-docs',
  production: 'project-docs',
  general: 'general-docs',
}

export const CONFIDENTIALITY_LEVELS: Confidentiality[] = [
  'public',
  'restricted',
  'confidential',
  'private',
]

export const DOCUMENT_STATUSES: DocumentStatus[] = [
  'pending',
  'approved',
  'rejected',
  'archived',
]

export const MODULE_LABELS: Record<ModuleName, string> = {
  projectManagement: 'projectManagement',
  accounting: 'accounting',
  hr: 'hr',
  commercial: 'commercial',
  treasury: 'treasury',
  stock: 'stock',
  production: 'production',
  general: 'general',
}
