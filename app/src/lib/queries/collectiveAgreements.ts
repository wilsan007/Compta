// F.7 / PAY-08 — conventions collectives : lecture par RLS (PostgREST),
// affectation au salarié par la RPC gardée de la 704.
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from '@/lib/queries/core'

export interface CollectiveAgreement {
  id: string
  idcc_code: string
  name: string
  application_date: string
  is_active: boolean
}

export interface CollectiveClassification {
  id: string
  agreement_id: string
  coefficient: number
  minimum_monthly_salary: number
  category: string | null
  level: string | null
  echelon: string | null
}

export interface EmployeeOption {
  id: string
  name: string
  collective_agreement_id: string | null
  classification_id: string | null
}

export async function getCollectiveAgreements(): Promise<CollectiveAgreement[]> {
  const { data, error } = await supabase
    .from('collective_agreements')
    .select('id, idcc_code, name, application_date, is_active')
    .order('name')
  if (error) throw error
  return (data ?? []) as CollectiveAgreement[]
}

export async function createCollectiveAgreement(input: {
  idccCode: string
  name: string
  applicationDate: string
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('collective_agreements').insert(
    ti(
      { idcc_code: input.idccCode, name: input.name, application_date: input.applicationDate },
      'collective_agreements',
      tid,
    ),
  )
  if (error) throw error
}

export async function getCollectiveClassifications(agreementId: string): Promise<CollectiveClassification[]> {
  const { data, error } = await supabase
    .from('collective_classifications')
    .select('*')
    .eq('agreement_id', agreementId)
    .order('coefficient')
  if (error) throw error
  return (data ?? []) as CollectiveClassification[]
}

export async function createCollectiveClassification(input: {
  agreementId: string
  coefficient: number
  minimumMonthlySalary: number
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('collective_classifications').insert(
    ti(
      {
        agreement_id: input.agreementId,
        coefficient: input.coefficient,
        minimum_monthly_salary: input.minimumMonthlySalary,
      },
      'collective_classifications',
      tid,
    ),
  )
  if (error) throw error
}

export async function getEmployeeOptions(): Promise<EmployeeOption[]> {
  const { data, error } = await supabase
    .from('employees')
    .select('id, name, collective_agreement_id, classification_id')
    .order('name')
  if (error) throw error
  return (data ?? []) as EmployeeOption[]
}

/** Affecte (ou retire, avec des `null`) la convention et la classification d'un salarié (RPC gardée, 704). */
export async function setEmployeeCollectiveAgreement(
  employeeId: string,
  agreementId: string | null,
  classificationId: string | null,
): Promise<void> {
  const { error } = await supabase.rpc('set_employee_collective_agreement', {
    p_employee_id: employeeId,
    p_agreement_id: agreementId,
    p_classification_id: classificationId,
  })
  if (error) throw error
}
