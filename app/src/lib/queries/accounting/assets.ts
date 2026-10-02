// ============================================================================
// Comptabilite — assets.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Joined } from '@/types/dbRow'
import { getTenantId, ti, tud } from '../core'
import { type FixedAsset, type AssetDepreciation, type AssetDepreciationPlan } from '@/types'

// ============ Fixed Assets ============
export async function getFixedAssets() {
  const tid = await getTenantId()
  let q = supabase.from('fixed_assets').select('*').order('purchase_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as FixedAsset[]
}

export async function createFixedAsset(asset: Omit<FixedAsset, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('fixed_assets').insert(ti(asset, 'fixed_assets', tid)).select().single()
  if (error) throw error
  return data as FixedAsset
}

export async function updateFixedAsset(id: string, updates: Partial<FixedAsset>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('fixed_assets').update(updates), 'fixed_assets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as FixedAsset
}

export async function deleteFixedAsset(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('fixed_assets').delete(), 'fixed_assets', tid).eq('id', id)
  if (error) throw error
}

/**
 * Dotation aux amortissements d'un exercice (R-01) : écriture D 681x / C 28x
 * validée, historique `asset_depreciations` et valeur nette mis à jour.
 * Renvoie l'identifiant de l'écriture, ou `null` s'il n'y a rien à amortir.
 */
export async function generateDepreciationEntry(assetId: string, fiscalYearId: string) {
  const { data, error } = await supabase.rpc('generate_depreciation_entry', {
    p_fixed_asset_id: assetId,
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data as string | null
}

/**
 * W5 (IMMO-02, IMMO-05) : dotation de TOUTES les immobilisations actives d'un
 * exercice, par le moteur de la base. Le verdict est PAR immobilisation : les
 * échecs sont nommés (`echecs`), les immobilisations sans objet sont comptées.
 * L'écran affiche ce verdict — il ne compte plus les succès lui-même et ne
 * saute plus les échecs en silence.
 */
export type DepreciationRun = {
  exercice: string
  total: number
  comptabilisees: number
  sans_objet: number
  echecs: { asset_id: string; asset: string; message: string }[]
  entrees: Record<string, string>
}

export async function generateDepreciationEntries(fiscalYearId: string): Promise<DepreciationRun> {
  const { data, error } = await supabase.rpc('generate_depreciation_entries', {
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data as DepreciationRun
}



// ============ Sprint 5: Asset Depreciations ============
export async function getAssetDepreciations(assetId?: string) {
  const tid = await getTenantId()
  let query = supabase.from('asset_depreciations').select('*').order('created_at', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)
  if (assetId) query = query.eq('asset_id', assetId)
  const { data, error } = await query
  if (error) throw error
  return data as AssetDepreciation[]
}

export async function createAssetDepreciation(ad: Omit<AssetDepreciation, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_depreciations').insert(ti(ad, 'asset_depreciations', tid)).select().single()
  if (error) throw error
  return data as AssetDepreciation
}

export async function deleteAssetDepreciation(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('asset_depreciations').delete(), 'asset_depreciations', tid).eq('id', id)
  if (error) throw error
}

export async function disposeFixedAsset(assetId: string, disposalValue: number, disposalDate: string) {
  const tid = await getTenantId()
  let faQ = supabase.from('fixed_assets').select('*').eq('id', assetId)
  if (tid) faQ = faQ.eq('tenant_id', tid)
  const { data: asset, error: assetErr } = await faQ.single()
  if (assetErr) throw assetErr

  const { error: updateErr } = await tud(supabase
    .from('fixed_assets')
    .update({ status: 'disposed', current_value: 0, updated_at: new Date().toISOString() }), 'fixed_assets', tid)
    .eq('id', assetId)
  if (updateErr) throw updateErr

  const { error: depErr } = await supabase.from('asset_depreciations').insert(ti({
    asset_id: assetId,
    depreciation_type: 'disposal',
    period: new Date(disposalDate).getMonth() + 1,
    amount: Number(asset.current_value) - disposalValue,
    cumulative_amount: Number(asset.purchase_value) - disposalValue,
    net_book_value: 0,
  }, 'asset_depreciations', tid))
  if (depErr) throw depErr

  return { asset, disposalValue }
}



// ============ Phase 5: Asset Depreciation Plans ============
export async function getAssetDepreciationPlans(assetId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('asset_depreciation_plans').select('*, fixed_assets(name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (assetId) q = q.eq('asset_id', assetId)
  const { data, error } = await q
  if (error) throw error
  return data as (AssetDepreciationPlan & { fixed_assets: Joined<'fixed_assets', 'name'> })[]
}
export async function createAssetDepreciationPlan(p: Omit<AssetDepreciationPlan, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_depreciation_plans').insert(ti(p, 'asset_depreciation_plans', tid)).select().single()
  if (error) throw error
  return data as AssetDepreciationPlan
}
export async function updateAssetDepreciationPlan(id: string, updates: Partial<AssetDepreciationPlan>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('asset_depreciation_plans').update(updates), 'asset_depreciation_plans', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AssetDepreciationPlan
}
