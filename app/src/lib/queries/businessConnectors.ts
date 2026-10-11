// F.6 / API-03 — connecteurs métier : où l'on parle (jamais le secret, seulement son nom).
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from '@/lib/queries/core'

export interface BusinessConnector {
  id: string
  name: string
  connector_type: string
  base_url: string
  auth_type: string
  auth_ref: string | null
  is_active: boolean
  created_at: string
}

export const CONNECTOR_TYPES = ['webhook', 'rest', 'odoo', 'sage', 'stripe', 'generic'] as const
export const AUTH_TYPES = ['none', 'api_key', 'basic', 'oauth2'] as const

export async function getBusinessConnectors(): Promise<BusinessConnector[]> {
  const { data, error } = await supabase
    .from('business_connectors')
    .select('id, name, connector_type, base_url, auth_type, auth_ref, is_active, created_at')
    .order('name')
  if (error) throw error
  return (data ?? []) as BusinessConnector[]
}

export async function createBusinessConnector(input: {
  name: string
  connectorType: string
  baseUrl: string
  authType: string
  authRef?: string | null
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('business_connectors').insert(
    ti(
      {
        name: input.name,
        connector_type: input.connectorType,
        base_url: input.baseUrl,
        auth_type: input.authType,
        // Jamais le secret : le NOM sous lequel il vit ailleurs.
        auth_ref: input.authType === 'none' ? null : (input.authRef || null),
      },
      'business_connectors',
      tid,
    ),
  )
  if (error) throw error
}

export async function deleteBusinessConnector(id: string): Promise<void> {
  const { error } = await supabase.from('business_connectors').delete().eq('id', id)
  if (error) throw error
}
