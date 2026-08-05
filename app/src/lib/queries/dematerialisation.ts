import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from './core'
import type { ElectronicSignature, OnlinePayment, DocumentShare } from '@/types'

// ============ Electronic Signatures ============

export async function signDocument(
  docType: string,
  docId: string,
  signerName: string,
  signerEmail: string
): Promise<ElectronicSignature> {
  const tid = await getTenantId()
  const hash = `${docType}:${docId}:${signerName}:${Date.now()}`
  const { data, error } = await supabase
    .from('electronic_signatures')
    .insert(ti({
      document_type: docType,
      document_id: docId,
      signer_name: signerName,
      signer_email: signerEmail,
      signature_hash: hash,
      signed_at: new Date().toISOString(),
    }, 'electronic_signatures', tid))
    .select()
    .single()
  if (error) throw error
  return data as ElectronicSignature
}

export async function getSignatures(docType: string, docId: string): Promise<ElectronicSignature[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('electronic_signatures')
    .select('*')
    .eq('document_type', docType)
    .eq('document_id', docId)
    .order('signed_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as ElectronicSignature[]
}

// ============ Online Payments ============

export async function createOnlinePayment(
  invoiceId: string,
  amount: number,
  provider: string
): Promise<OnlinePayment> {
  const tid = await getTenantId()
  const token = crypto.randomUUID()
  const paymentUrl = `${window.location.origin}/pay/${token}`
  const { data, error } = await supabase
    .from('online_payments')
    .insert(ti({
      invoice_id: invoiceId,
      payment_provider: provider,
      amount,
      status: 'pending',
      payment_url: paymentUrl,
    }, 'online_payments', tid))
    .select()
    .single()
  if (error) throw error
  return data as OnlinePayment
}

export async function getOnlinePaymentByToken(token: string): Promise<OnlinePayment | null> {
  const tid = await getTenantId()
  let q = supabase
    .from('online_payments')
    .select('*, invoice:invoices(number, total, customer_id)')
    .eq('payment_url', `${window.location.origin}/pay/${token}`)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return data as OnlinePayment | null
}

export async function updateOnlinePaymentStatus(
  id: string,
  status: 'pending' | 'completed' | 'failed' | 'refunded'
): Promise<void> {
  const tid = await getTenantId()
  const updates: Record<string, any> = { status }
  if (status === 'completed') updates.paid_at = new Date().toISOString()
  const { error } = await supabase
    .from('online_payments')
    .update(updates)
    .eq('id', id)
    .eq('tenant_id', tid || '')
  if (error) throw error
}

// ============ Document Shares ============

export async function shareDocument(
  docType: string,
  docId: string,
  email: string,
  expiresInDays?: number
): Promise<DocumentShare> {
  const tid = await getTenantId()
  const token = crypto.randomUUID()
  const shareUrl = `${window.location.origin}/shared/${token}`
  const expiresAt = expiresInDays
    ? new Date(Date.now() + expiresInDays * 86400000).toISOString()
    : null
  const { data, error } = await supabase
    .from('document_shares')
    .insert(ti({
      document_type: docType,
      document_id: docId,
      shared_with_email: email,
      share_token: token,
      share_url: shareUrl,
      expires_at: expiresAt,
    }, 'document_shares', tid))
    .select()
    .single()
  if (error) throw error
  return data as DocumentShare
}

export async function getDocumentShare(token: string): Promise<DocumentShare | null> {
  const { data, error } = await supabase
    .from('document_shares')
    .select('*')
    .eq('share_token', token)
    .maybeSingle()
  if (error) throw error
  if (data) {
    const { error: updateError } = await supabase
      .from('document_shares')
      .update({ viewed: true, viewed_at: new Date().toISOString() })
      .eq('id', (data as any).id)
    if (updateError) console.error('Failed to mark share as viewed:', updateError.message)
  }
  return data as DocumentShare | null
}

// ============ Factur-X ============

export async function generateFacturX(invoiceId: string): Promise<string> {
  const tid = await getTenantId()
  let q = supabase
    .from('invoices')
    .select('*, invoice_lines(*), customer:customers(name, email, address)')
    .eq('id', invoiceId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  if (!data) throw new Error('Invoice not found')
  return JSON.stringify(data)
}
