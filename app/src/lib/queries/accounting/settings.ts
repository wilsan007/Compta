// ============================================================================
// Comptabilite — settings.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { blankEmailToNull, getTenantId, tud } from '../core'
import { type CompanySettings, type LegislationPack, type TaxRate } from '@/types'

// ============ Company Settings ============
export async function getCompanySettings(): Promise<CompanySettings | null> {
  const tid = await getTenantId()
  let q = supabase.from('company_settings').select('*').limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  if (!data && tid) {
    // W-QA (29/09/2026) : cette création « de secours » partait avant que la
    // société active ne soit établie côté serveur. Or `current_tenant_id()` lit
    // l'en-tête `x-tenant-id`, et `can_perform()` en dérive : sans société
    // active, la RLS refuse l'insertion — une erreur console à CHAQUE chargement
    // d'écran, pour rien. Un refus de portée n'est plus une erreur : l'appelant
    // retombe sur le pack législatif par défaut, comme prévu.
    const { data: created, error: createErr } = await supabase
      .from('company_settings')
      .insert({ tenant_id: tid, name: 'Mon Entreprise', country: 'France', currency: 'EUR', fiscal_year_start: '01-01' })
      .select('*')
      .single()
    if (createErr) {
      if (String((createErr as { code?: string }).code ?? '') === '42501' || /row-level security/i.test(createErr.message ?? '')) return null
      throw createErr
    }
    return created as CompanySettings
  }
  return data as CompanySettings | null
}

export async function updateCompanySettings(id: string, updates: Partial<CompanySettings>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('company_settings').update(blankEmailToNull(updates)), 'company_settings', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CompanySettings
}



// ============ Legislation Packs (global reference, NOT tenant-scoped) ============
export async function getLegislationPacks() {
  const { data, error } = await supabase
    .from('legislation_packs')
    .select('*')
    .eq('active', true)
    .order('country_name', { ascending: true })
  if (error) throw error
  return data as LegislationPack[]
}

export async function getLegislationPack(code: string) {
  const { data, error } = await supabase.from('legislation_packs').select('*').eq('code', code).single()
  if (error) throw error
  return data as LegislationPack
}

// Resolve the pack that applies to the current tenant (from company_settings),
// falling back to the default pack when the tenant has none configured.
export async function getActiveLegislationPack() {
  try {
    const settings = await getCompanySettings()
    if (settings?.legislation_pack_code) {
      return await getLegislationPack(settings.legislation_pack_code)
    }
  } catch (e) {
    // no settings yet — fall through to default
    console.error('getActiveLegislationPack: settings lookup failed:', e)
  }
  const { data, error } = await supabase
    .from('legislation_packs')
    .select('*')
    .eq('is_default', true)
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return (data as LegislationPack) || null
}

// VAT rates in force for a pack at a given date (versioned by effective_from/to).
export async function getApplicableVatRates(packCode: string, atDate: string = new Date().toISOString().slice(0, 10)) {
  if (!/^[A-Za-z0-9_-]{1,20}$/.test(packCode)) throw new Error('Invalid pack code format')
  if (!/^\d{4}-\d{2}-\d{2}$/.test(atDate)) throw new Error('Invalid date format')
  const { data, error } = await supabase
    .from('tax_rates')
    .select('*')
    .eq('pack_code', packCode)
    .lte('effective_from', atDate)
    .or(`effective_to.is.null,effective_to.gte.${atDate}`)
    .order('rate', { ascending: false })
  if (error) throw error
  return data as TaxRate[]
}



// ============ Users ============
// Deprecated: use getTenantUsers(tenantId) instead. Kept for backward compat but now tenant-scoped.
export async function getUsers() {
  const tid = await getTenantId()
  if (!tid) return []
  const { data, error } = await supabase.from('tenant_users').select('*').eq('tenant_id', tid).order('created_at', { ascending: false })
  if (error) throw error
  return data as any[]
}
