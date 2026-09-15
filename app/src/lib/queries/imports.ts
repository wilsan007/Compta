// IMP-02 + IMP-03 : Import générique fiable + reprise de données
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from './core'

// ============ IMP-02 : Modèles de correspondance ============

export interface ColumnMapping {
  id: string
  name: string
  target_table: string
  mapping: Record<string, string>
}

export async function getColumnMappings(targetTable?: string): Promise<ColumnMapping[]> {
  const tid = await getTenantId()
  let q = supabase.from('import_column_mappings').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  if (targetTable) q = q.eq('target_table', targetTable)
  const { data, error } = await q
  if (error) throw error
  return data as ColumnMapping[]
}

export async function saveColumnMapping(name: string, targetTable: string, mapping: Record<string, string>): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('import_column_mappings')
    .upsert(ti({ name, target_table: targetTable, mapping }, 'import_column_mappings', tid))
  if (error) throw error
}

// ============ IMP-02 : Lots d'import transactionnels ============

export interface ImportBatch {
  id: string
  target_table: string
  file_name: string
  total_rows: number
  valid_rows: number
  invalid_rows: number
  status: 'pending' | 'validated' | 'importing' | 'completed' | 'failed' | 'cancelled'
  error_report: ImportError[] | null
  created_at: string
  validated_at: string | null
  completed_at: string | null
}

export interface ImportError {
  row_number: number
  column: string
  error_message: string
}

export async function createImportBatch(targetTable: string, fileName: string, totalRows: number): Promise<ImportBatch> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('import_batches')
    .insert(ti({
      target_table: targetTable,
      file_name: fileName,
      total_rows: totalRows,
      status: 'pending',
    }, 'import_batches', tid))
    .select()
    .single()
  if (error) throw error
  return data as ImportBatch
}

export async function validateImportBatch(batchId: string): Promise<any> {
  const { data, error } = await supabase.rpc('validate_import_batch', { p_batch_id: batchId })
  if (error) throw error
  return data
}

export async function cancelImportBatch(batchId: string): Promise<any> {
  const { data, error } = await supabase.rpc('cancel_import_batch', { p_batch_id: batchId })
  if (error) throw error
  return data
}

export async function getImportBatches(): Promise<ImportBatch[]> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('import_batches')
    .select('*')
    .eq('tenant_id', tid)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data as ImportBatch[]
}

// ============ IMP-02 : Validation à blanc ============

export function validateRow(row: Record<string, any>, targetTable: string): ImportError[] {
  const errors: ImportError[] = []
  const rowNumber = row.__rowNumber || 0

  const requiredFields: Record<string, string[]> = {
    customers: ['name'],
    suppliers: ['name'],
    products: ['name', 'sku'],
    employees: ['first_name', 'last_name'],
    journal_entries: ['date', 'account_code', 'debit', 'credit'],
    stock_initial: ['product_id', 'quantity'],
  }

  const required = requiredFields[targetTable] || []
  for (const field of required) {
    if (!row[field] || row[field] === '') {
      errors.push({ row_number: rowNumber, column: field, error_message: `Champ obligatoire manquant: ${field}` })
    }
  }

  // Validation spécifique par table
  if (targetTable === 'journal_entries') {
    const debit = Number(row.debit || 0)
    const credit = Number(row.credit || 0)
    if (debit < 0 || credit < 0) {
      errors.push({ row_number: rowNumber, column: 'debit', error_message: 'Montant négatif interdit' })
    }
  }

  if (targetTable === 'products') {
    if (row.sku && row.sku.length > 50) {
      errors.push({ row_number: rowNumber, column: 'sku', error_message: 'SKU trop long (max 50 caractères)' })
    }
  }

  return errors
}

export function validateBatch(rows: Record<string, any>[], targetTable: string): { valid: any[], invalid: { row: any, errors: ImportError[] }[] } {
  const valid: any[] = []
  const invalid: { row: any, errors: ImportError[] }[] = []

  rows.forEach((row, idx) => {
    row.__rowNumber = idx + 2 // +2 car ligne 1 = en-têtes
    const errors = validateRow(row, targetTable)
    if (errors.length > 0) {
      invalid.push({ row, errors })
    } else {
      valid.push(row)
    }
  })

  return { valid, invalid }
}

// ============ IMP-03 : Déduplication ============

export async function findDuplicateCustomers(siret?: string, name?: string, email?: string) {
  const { data, error } = await supabase.rpc('find_duplicate_customers', {
    p_siret: siret || null,
    p_name: name || null,
    p_email: email || null,
  })
  if (error) throw error
  return data as any[]
}

// ============ IMP-03 : Import stock initial ============

export async function importInitialStock(stockData: any[]) {
  const { data, error } = await supabase.rpc('import_initial_stock', {
    p_stock_data: stockData,
  })
  if (error) throw error
  return data as any[]
}

// ============ IMP-03 : Import salarié avec cumuls ============

export async function importEmployeeWithCumuls(employee: any, cumuls?: any[]) {
  const { data, error } = await supabase.rpc('import_employee_with_cumuls', {
    p_employee: employee,
    p_cumuls: cumuls || null,
  })
  if (error) throw error
  return data
}
