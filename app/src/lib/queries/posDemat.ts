import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from './core'
import type { ElectronicSignature, OnlinePayment, DocumentShare } from '@/types'

// ============ Sprint I: Electronic Signatures ============

export async function getElectronicSignatures(docType?: string, docId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('electronic_signatures').select('*').order('signed_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (docType) q = q.eq('document_type', docType)
  if (docId) q = q.eq('document_id', docId)
  const { data, error } = await q
  if (error) throw error
  return data as ElectronicSignature[]
}

export async function createElectronicSignature(sig: Omit<ElectronicSignature, 'id' | 'signed_at' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('electronic_signatures').insert(ti({ ...sig, signed_at: new Date().toISOString() }, 'electronic_signatures', tid)).select().single()
  if (error) throw error
  return data as ElectronicSignature
}

// ============ Sprint I: Online Payments ============

export async function getOnlinePayments(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('online_payments').select('*, invoice:invoices(number), customer:customers(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as (OnlinePayment & { invoice: { number: string } | null, customer: { name: string } | null })[]
}

// ============ Sprint I: Document Shares ============

export async function getDocumentShares(docType?: string) {
  const tid = await getTenantId()
  let q = supabase.from('document_shares').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (docType) q = q.eq('document_type', docType)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentShare[]
}

export async function createDocumentShare(share: Omit<DocumentShare, 'id' | 'created_at' | 'viewed' | 'viewed_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('document_shares').insert(ti({ ...share, viewed: false }, 'document_shares', tid)).select().single()
  if (error) throw error
  return data as DocumentShare
}

export async function deleteDocumentShare(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('document_shares').delete(), 'document_shares', tid).eq('id', id)
  if (error) throw error
}

export async function markDocumentShareViewed(token: string) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('document_shares').update({ viewed: true, viewed_at: new Date().toISOString() }).eq('share_token', token).eq('tenant_id', tid || '').select().single()
  if (error) throw error
  return data as DocumentShare
}
