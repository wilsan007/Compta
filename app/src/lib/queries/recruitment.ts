// F.7 / RH-03 — recrutement : postes et candidatures (RLS + 4 politiques par table).
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from '@/lib/queries/core'

export interface JobPosting {
  id: string
  title: string
  department: string | null
  contract_type: string
  location: string | null
  openings: number
  status: string
  published_at: string | null
  closing_at: string | null
  created_at: string
}

export interface JobApplication {
  id: string
  posting_id: string
  candidate_name: string
  candidate_email: string | null
  candidate_phone: string | null
  source: string | null
  status: string
  applied_at: string
  notes: string | null
}

export const APPLICATION_STATUSES = ['received', 'screening', 'interview', 'offer', 'hired', 'rejected'] as const
export const CONTRACT_TYPES = ['cdi', 'cdd', 'stage', 'alternance', 'interim', 'freelance'] as const

export async function getJobPostings(): Promise<JobPosting[]> {
  const { data, error } = await supabase
    .from('job_postings')
    .select('*')
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as JobPosting[]
}

export async function createJobPosting(input: {
  title: string
  department?: string | null
  contractType: string
  location?: string | null
  openings?: number
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('job_postings').insert(
    ti(
      {
        title: input.title,
        department: input.department || null,
        contract_type: input.contractType,
        location: input.location || null,
        openings: input.openings ?? 1,
        status: 'open',
        published_at: new Date().toISOString(),
      },
      'job_postings',
      tid,
    ),
  )
  if (error) throw error
}

export async function getJobApplications(postingId: string): Promise<JobApplication[]> {
  const { data, error } = await supabase
    .from('job_applications')
    .select('*')
    .eq('posting_id', postingId)
    .order('applied_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as JobApplication[]
}

export async function createJobApplication(input: {
  postingId: string
  candidateName: string
  email?: string | null
  phone?: string | null
  source?: string | null
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('job_applications').insert(
    ti(
      {
        posting_id: input.postingId,
        candidate_name: input.candidateName,
        candidate_email: input.email || null,
        candidate_phone: input.phone || null,
        source: input.source || null,
      },
      'job_applications',
      tid,
    ),
  )
  if (error) throw error
}

/** Fait avancer une candidature dans le pipeline (le statut est contraint par la base). */
export async function updateJobApplicationStatus(applicationId: string, status: string): Promise<void> {
  const { error } = await supabase.from('job_applications').update({ status }).eq('id', applicationId)
  if (error) throw error
}
