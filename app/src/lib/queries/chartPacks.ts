import { supabase } from '@/lib/supabase'

// Plans comptables par pays (migration 201). Une société ne reçoit que le plan
// publié pour son pays ; Djibouti reçoit le PCG à titre provisoire tant que son
// plan n'est pas publié ; les autres pays sont refusés à l'inscription.

export interface SignupCountry {
  country_code: string
  country_name: string
  pack_code: string
  provisional: boolean
  currency: string
}

export interface ChartPackRow {
  code: string
  name: string
  type: ChartAccountType
  parent_code?: string
  vat_rate?: string
}

type ChartAccountType = 'asset' | 'liability' | 'equity' | 'income' | 'expense'

export interface ChartPackStatus {
  pack_code: string
  status: 'draft' | 'published'
  account_count: number
  uploaded_at: string | null
  published_at: string | null
  source: string
}

export interface UploadResult {
  success: boolean
  accounts?: number
  missing_required?: string[]
  errors?: { line: number; code: string | null; error: string }[]
}

export interface PublishResult {
  success: boolean
  pack: string
  country: string
  tenants: { tenant_id: string; switched: boolean; reason?: string; deleted?: number; closed?: string[] }[]
}

/** null : liste indisponible (serveur antérieur à la migration 201) — le serveur reste juge à l'inscription */
export async function getAvailableSignupCountries(): Promise<SignupCountry[] | null> {
  try {
    const { data, error } = await supabase.rpc('available_signup_countries')
    if (error) {
      console.warn('[chartPacks] available_signup_countries indisponible :', error.message)
      return null
    }
    return (data ?? []) as SignupCountry[]
  } catch (err) {
    console.warn('[chartPacks] available_signup_countries a échoué :', err)
    return null
  }
}

export async function isPlatformAdmin(): Promise<boolean> {
  const { data, error } = await supabase.rpc('is_platform_admin')
  if (error) {
    // Refus par défaut : une permission qui ne peut être prouvée n'est pas accordée.
    console.warn('[chartPacks] is_platform_admin indisponible, refus par défaut :', error.message)
    return false
  }
  return data === true
}

export async function listChartPackStatus(): Promise<ChartPackStatus[]> {
  const { data, error } = await supabase
    .from('chart_pack_status')
    .select('pack_code, status, account_count, uploaded_at, published_at, source')
    .order('pack_code', { ascending: true })
  if (error) throw new Error(error.message)
  return (data ?? []) as ChartPackStatus[]
}

export async function uploadChartPack(packCode: string, rows: ChartPackRow[]): Promise<UploadResult> {
  const { data, error } = await supabase.rpc('upload_chart_pack', { p_pack: packCode, p_rows: rows })
  if (error) throw new Error(error.message)
  return data as UploadResult
}

export async function publishChartPack(packCode: string): Promise<PublishResult> {
  const { data, error } = await supabase.rpc('publish_chart_pack', { p_pack: packCode })
  if (error) throw new Error(error.message)
  return data as PublishResult
}

// ------------------------------------------------------------
// Lecture du fichier CSV
// ------------------------------------------------------------

// Libellés de type acceptés dans le fichier (français ou valeurs de la base)
const TYPE_ALIASES: Record<string, ChartAccountType> = {
  asset: 'asset', actif: 'asset',
  liability: 'liability', passif: 'liability', dette: 'liability',
  equity: 'equity', 'capitaux propres': 'equity', capitaux: 'equity',
  income: 'income', produit: 'income', produits: 'income',
  expense: 'expense', charge: 'expense', charges: 'expense',
}

const COLUMN_ALIASES: Record<string, keyof ChartPackRow> = {
  code: 'code', compte: 'code', numero: 'code', 'numéro': 'code',
  name: 'name', libelle: 'name', 'libellé': 'name', intitule: 'name', 'intitulé': 'name',
  type: 'type', nature: 'type',
  parent: 'parent_code', parent_code: 'parent_code',
  tva: 'vat_rate', vat_rate: 'vat_rate',
}

export interface ParsedCsv {
  rows: ChartPackRow[]
  /** Erreurs de structure du fichier (en-tête, colonnes) ; les erreurs par ligne sont renvoyées par le serveur */
  errors: string[]
}

function splitLine(line: string, sep: string): string[] {
  const out: string[] = []
  let cur = ''
  let quoted = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++ }
      else if (ch === '"') quoted = false
      else cur += ch
    } else if (ch === '"') quoted = true
    else if (ch === sep) { out.push(cur); cur = '' }
    else cur += ch
  }
  out.push(cur)
  return out.map((c) => c.trim())
}

/**
 * Lit un plan comptable CSV. En-tête obligatoire : code ; libellé ; type
 * (colonnes facultatives : parent, tva). Séparateur « ; » ou « , ».
 * Le type accepte actif / passif / capitaux propres / produit / charge.
 * Un type inconnu est transmis tel quel : le serveur le refuse en nommant la ligne.
 */
export function parseChartCsv(text: string): ParsedCsv {
  const lines = text.replace(/^﻿/, '').split(/\r?\n/).filter((l) => l.trim() !== '')
  if (lines.length === 0) return { rows: [], errors: ['Fichier vide'] }

  const sep = (lines[0].match(/;/g)?.length ?? 0) >= (lines[0].match(/,/g)?.length ?? 0) ? ';' : ','
  const header = splitLine(lines[0], sep).map((h) => COLUMN_ALIASES[h.toLowerCase()])
  const missing = (['code', 'name', 'type'] as const).filter((c) => !header.includes(c))
  if (missing.length > 0) {
    return { rows: [], errors: [`Colonnes obligatoires absentes de l'en-tête : ${missing.join(', ')} (attendu : code;libellé;type)`] }
  }

  const rows = lines.slice(1).map((line) => {
    const cells = splitLine(line, sep)
    const row: Record<string, string> = {}
    header.forEach((key, i) => { if (key) row[key] = cells[i] ?? '' })
    const rawType = (row.type ?? '').toLowerCase()
    return {
      code: row.code ?? '',
      name: row.name ?? '',
      type: (TYPE_ALIASES[rawType] ?? row.type ?? '') as ChartAccountType,
      ...(row.parent_code ? { parent_code: row.parent_code } : {}),
      ...(row.vat_rate ? { vat_rate: row.vat_rate } : {}),
    }
  })
  return { rows, errors: [] }
}
