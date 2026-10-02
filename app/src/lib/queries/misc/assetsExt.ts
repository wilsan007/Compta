// ============================================================================
// misc — assetsExt.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Joined } from '@/types/dbRow'
import { getTenantId, ti, tud } from '../core'
import { type AssetFamily, type AssetRevaluation, type AssetDocument, type AssetFreeField, type AssetBatchDisposal, type AssetSplit } from '@/types'

// ============ Phase 5: Asset Families ============
export async function getAssetFamilies() {
  const tid = await getTenantId()
  let q = supabase.from('asset_families').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AssetFamily[]
}
export async function createAssetFamily(f: Omit<AssetFamily, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_families').insert(ti(f, 'asset_families', tid)).select().single()
  if (error) throw error
  return data as AssetFamily
}
export async function updateAssetFamily(id: string, updates: Partial<AssetFamily>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('asset_families').update(updates), 'asset_families', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AssetFamily
}
export async function deleteAssetFamily(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('asset_families').delete(), 'asset_families', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 5: Asset Revaluations ============
export async function getAssetRevaluations(assetId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('asset_revaluations').select('*, fixed_assets(name)').order('revaluation_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (assetId) q = q.eq('asset_id', assetId)
  const { data, error } = await q
  if (error) throw error
  return data as (AssetRevaluation & { fixed_assets: Joined<'fixed_assets', 'name'> })[]
}
export async function createAssetRevaluation(r: Omit<AssetRevaluation, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_revaluations').insert(ti(r, 'asset_revaluations', tid)).select().single()
  if (error) throw error
  return data as AssetRevaluation
}



// ============ Phase 5: Asset Documents ============
export async function getAssetDocuments(assetId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('asset_documents').select('*, fixed_assets(name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (assetId) q = q.eq('asset_id', assetId)
  const { data, error } = await q
  if (error) throw error
  return data as (AssetDocument & { fixed_assets: Joined<'fixed_assets', 'name'> })[]
}
export async function createAssetDocument(d: Omit<AssetDocument, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_documents').insert(ti(d, 'asset_documents', tid)).select().single()
  if (error) throw error
  return data as AssetDocument
}
export async function deleteAssetDocument(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('asset_documents').delete(), 'asset_documents', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 5: Asset Free Fields ============
export async function getAssetFreeFields(assetId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('asset_free_fields').select('*')
  if (tid) q = q.eq('tenant_id', tid)
  if (assetId) q = q.eq('asset_id', assetId)
  const { data, error } = await q
  if (error) throw error
  return data as AssetFreeField[]
}
export async function createAssetFreeField(f: Omit<AssetFreeField, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_free_fields').insert(ti(f, 'asset_free_fields', tid)).select().single()
  if (error) throw error
  return data as AssetFreeField
}



// ============ Phase 5: Asset Batch Disposals ============
export async function getAssetBatchDisposals() {
  const tid = await getTenantId()
  let q = supabase.from('asset_batch_disposals').select('*').order('disposal_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AssetBatchDisposal[]
}
export async function createAssetBatchDisposal(b: Omit<AssetBatchDisposal, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_batch_disposals').insert(ti(b, 'asset_batch_disposals', tid)).select().single()
  if (error) throw error
  return data as AssetBatchDisposal
}
export async function updateAssetBatchDisposal(id: string, updates: Partial<AssetBatchDisposal>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('asset_batch_disposals').update(updates), 'asset_batch_disposals', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AssetBatchDisposal
}



// ============ Phase 5: Asset Splits ============
export async function getAssetSplits() {
  const tid = await getTenantId()
  let q = supabase.from('asset_splits').select('*, fixed_assets(name)').order('split_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (AssetSplit & { fixed_assets: Joined<'fixed_assets', 'name'> })[]
}
export async function createAssetSplit(s: Omit<AssetSplit, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_splits').insert(ti(s, 'asset_splits', tid)).select().single()
  if (error) throw error
  return data as AssetSplit
}
