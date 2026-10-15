// F.4 — groupes de sociétés : lecture par RLS, écriture par les RPC de la 702.
//
// Pourquoi deux voies : la LECTURE peut passer par PostgREST — la RLS de la
// 702 ne rend que les groupes dont la société courante est membre ; l'ÉCRITURE,
// non : les tables n'ont AUCUNE politique d'écriture (un écran ne doit pas
// forger un groupe). Les RPC `create_group`, `add_group_member`,
// `remove_group_member` et `record_intra_group_transaction` (SECURITY DEFINER)
// vérifient, elles, que l'appelant est administrateur d'une société membre.
import { supabase } from '@/lib/supabase'

export interface EntityGroup {
  id: string
  name: string
  created_at: string
}

interface GroupStructureMember {
  tenant_id: string
  name: string
  member_type: string
  ownership_pct: number
  consolidation_method: string
}

export interface GroupStructure {
  group_id: string
  name: string
  members: GroupStructureMember[]
}

export interface IntraGroupTransaction {
  id: string
  group_id: string
  from_tenant_id: string
  to_tenant_id: string
  transaction_type: string
  amount: number
  currency: string
  reference: string | null
  label: string | null
  transaction_date: string
  status: string
}

interface RecordIntraGroupInput {
  groupId: string
  toTenantId: string
  transactionType: string
  amount: number
  transactionDate: string
  reference?: string | null
  label?: string | null
  currency?: string
}

/** Les groupes dont la société courante est membre (RLS : rien d'autre). */
export async function getMyGroups(): Promise<EntityGroup[]> {
  const { data, error } = await supabase
    .from('groups')
    .select('id, name, created_at')
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as EntityGroup[]
}

/** La structure d'un groupe : ses membres et leurs paramètres (RPC gardée). */
export async function getGroupStructure(groupId: string): Promise<GroupStructure | null> {
  const { data, error } = await supabase.rpc('group_structure', { p_group_id: groupId })
  if (error) throw error
  return (data as GroupStructure | null) ?? null
}

export async function createGroup(name: string): Promise<string> {
  const { data, error } = await supabase.rpc('create_group', { p_name: name })
  if (error) throw error
  if (!data?.success) throw new Error(data?.error || 'GROUP_CREATE_FAILED')
  return data.group_id as string
}

export async function addGroupMember(
  groupId: string,
  tenantId: string,
  memberType = 'subsidiary',
  ownershipPct = 100,
  consolidationMethod = 'full',
): Promise<void> {
  const { error } = await supabase.rpc('add_group_member', {
    p_group_id: groupId,
    p_tenant_id: tenantId,
    p_member_type: memberType,
    p_ownership_pct: ownershipPct,
    p_consolidation_method: consolidationMethod,
  })
  if (error) throw error
}

export async function removeGroupMember(groupId: string, tenantId: string): Promise<void> {
  const { error } = await supabase.rpc('remove_group_member', {
    p_group_id: groupId,
    p_tenant_id: tenantId,
  })
  if (error) throw error
}

/** Les flux intra-groupe d'un groupe — dont MA société est un côté (RLS). */
export async function getIntraGroupTransactions(groupId: string): Promise<IntraGroupTransaction[]> {
  const { data, error } = await supabase
    .from('intra_group_transactions')
    .select('*')
    .eq('group_id', groupId)
    .order('transaction_date', { ascending: false })
  if (error) throw error
  return (data ?? []) as IntraGroupTransaction[]
}

export async function recordIntraGroupTransaction(input: RecordIntraGroupInput): Promise<void> {
  const { error } = await supabase.rpc('record_intra_group_transaction', {
    p_group_id: input.groupId,
    p_to_tenant_id: input.toTenantId,
    p_transaction_type: input.transactionType,
    p_amount: input.amount,
    p_transaction_date: input.transactionDate,
    p_reference: input.reference ?? null,
    p_label: input.label ?? null,
    p_currency: input.currency ?? 'EUR',
  })
  if (error) throw error
}

interface ConsolidatedAccount {
  account: string
  debit: number
  credit: number
  balance: number
}

export interface GroupConsolidation {
  group_id: string
  from: string
  to: string
  members: { tenant_id: string; name: string; consolidation_method: string; ownership_pct: number; included: boolean }[]
  accounts: ConsolidatedAccount[]
  intra_group: { count: number; total_amount: number }
}

/** La consolidation d'un groupe sur une période (RPC gardée, GRP-03). */
export async function getGroupConsolidation(
  groupId: string,
  from: string,
  to: string,
): Promise<GroupConsolidation | null> {
  const { data, error } = await supabase.rpc('group_consolidated_balance', {
    p_group_id: groupId,
    p_from: from,
    p_to: to,
  })
  if (error) throw error
  return (data as GroupConsolidation | null) ?? null
}
