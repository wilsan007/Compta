// F.5 / PRJ-04 — champs personnalisés : définitions par (module, entité), valeurs par enregistrement.
// Le TYPE de la valeur est tenu par la base (déclencheur de la 706) : l'écran
// envoie le bon type JSON, mais c'est la base qui refuse un nombre écrit en texte.
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from '@/lib/queries/core'

export interface CustomFieldDefinition {
  id: string
  module: string
  entity: string
  field_key: string
  label: string
  field_type: string
  options: string[]
  is_required: boolean
  position: number
  is_active: boolean
}

export interface CustomFieldValue {
  definition_id: string
  value: unknown
}

export interface ProjectOption {
  id: string
  name: string
}

export const FIELD_TYPES = ['text', 'number', 'date', 'boolean', 'select'] as const

export async function getCustomFieldDefinitions(module: string, entity: string): Promise<CustomFieldDefinition[]> {
  const { data, error } = await supabase
    .from('custom_field_definitions')
    .select('id, module, entity, field_key, label, field_type, options, is_required, position, is_active')
    .eq('module', module)
    .eq('entity', entity)
    .order('position')
  if (error) throw error
  return (data ?? []) as CustomFieldDefinition[]
}

export async function createCustomFieldDefinition(input: {
  module: string
  entity: string
  fieldKey: string
  label: string
  fieldType: string
  options?: string[]
  isRequired?: boolean
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('custom_field_definitions').insert(
    ti(
      {
        module: input.module,
        entity: input.entity,
        field_key: input.fieldKey,
        label: input.label,
        field_type: input.fieldType,
        options: input.options ?? [],
        is_required: input.isRequired ?? false,
      },
      'custom_field_definitions',
      tid,
    ),
  )
  if (error) throw error
}

export async function deleteCustomFieldDefinition(id: string): Promise<void> {
  const { error } = await supabase.from('custom_field_definitions').delete().eq('id', id)
  if (error) throw error
}

export async function getCustomFieldValues(recordId: string): Promise<CustomFieldValue[]> {
  const { data, error } = await supabase
    .from('custom_field_values')
    .select('definition_id, value')
    .eq('record_id', recordId)
  if (error) throw error
  return (data ?? []) as CustomFieldValue[]
}

/** Écrit (ou remplace) la valeur d'un champ pour un enregistrement. */
export async function setCustomFieldValue(definitionId: string, recordId: string, value: unknown): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('custom_field_values')
    .upsert(
      ti({ definition_id: definitionId, record_id: recordId, value }, 'custom_field_values', tid),
      { onConflict: 'tenant_id,definition_id,record_id' },
    )
  if (error) throw error
}

/** Les projets, pour choisir l'enregistrement dont on saisit les champs. */
export async function getProjectOptions(): Promise<ProjectOption[]> {
  const { data, error } = await supabase.from('projects').select('id, name').order('name')
  if (error) throw error
  return (data ?? []) as ProjectOption[]
}
