// Configuration for the Excel/CSV import wizard.
// Each module maps an importable file to a DB table with typed, validated fields.
// Modules are ordered by dependency (reference data first, then business data).

export type FieldType = 'string' | 'number' | 'boolean' | 'enum'

export interface ImportField {
  key: string
  label: string
  required?: boolean
  type: FieldType
  enumValues?: string[]
  default?: string | number | boolean
  sample: string | number | boolean
}

export interface ImportModule {
  id: string
  label: string
  table: string
  description: string
  order: number
  fields: ImportField[]
}

export const IMPORT_MODULES: ImportModule[] = [
  {
    id: 'chart_accounts',
    label: 'Plan comptable',
    table: 'chart_accounts',
    description: 'Comptes généraux (classe 1 à 7). À importer en premier.',
    order: 1,
    fields: [
      { key: 'code', label: 'Code', required: true, type: 'string', sample: '512000' },
      { key: 'name', label: 'Libellé', required: true, type: 'string', sample: 'Banque' },
      { key: 'type', label: 'Type', required: true, type: 'enum', enumValues: ['asset', 'liability', 'equity', 'income', 'expense'], sample: 'asset' },
      { key: 'vat_rate', label: 'Taux TVA', type: 'string', sample: '20' },
      { key: 'description', label: 'Description', type: 'string', sample: 'Compte bancaire principal' },
    ],
  },
  {
    id: 'customers',
    label: 'Clients',
    table: 'customers',
    description: 'Fiches clients.',
    order: 2,
    fields: [
      { key: 'name', label: 'Nom', required: true, type: 'string', sample: 'ACME SARL' },
      { key: 'email', label: 'Email', type: 'string', sample: 'contact@acme.fr' },
      { key: 'phone', label: 'Téléphone', type: 'string', sample: '0102030405' },
      { key: 'address', label: 'Adresse', type: 'string', sample: '12 rue de Paris' },
      { key: 'city', label: 'Ville', type: 'string', sample: 'Paris' },
      { key: 'postal_code', label: 'Code postal', type: 'string', sample: '75001' },
      { key: 'country', label: 'Pays', type: 'string', default: 'France', sample: 'France' },
      { key: 'vat_number', label: 'N° TVA', type: 'string', sample: 'FR12345678901' },
      { key: 'contact_name', label: 'Contact', type: 'string', sample: 'Jean Dupont' },
    ],
  },
  {
    id: 'suppliers',
    label: 'Fournisseurs',
    table: 'suppliers',
    description: 'Fiches fournisseurs.',
    order: 3,
    fields: [
      { key: 'name', label: 'Nom', required: true, type: 'string', sample: 'Fournitures Pro' },
      { key: 'email', label: 'Email', type: 'string', sample: 'vente@fournitures.fr' },
      { key: 'phone', label: 'Téléphone', type: 'string', sample: '0102030406' },
      { key: 'address', label: 'Adresse', type: 'string', sample: '5 avenue du Commerce' },
      { key: 'city', label: 'Ville', type: 'string', sample: 'Lyon' },
      { key: 'postal_code', label: 'Code postal', type: 'string', sample: '69001' },
      { key: 'country', label: 'Pays', type: 'string', default: 'France', sample: 'France' },
      { key: 'vat_number', label: 'N° TVA', type: 'string', sample: 'FR98765432109' },
      { key: 'contact_name', label: 'Contact', type: 'string', sample: 'Marie Martin' },
    ],
  },
  {
    id: 'products',
    label: 'Produits & Services',
    table: 'products',
    description: 'Articles vendus ou achetés.',
    order: 4,
    fields: [
      { key: 'name', label: 'Nom', required: true, type: 'string', sample: 'Prestation de conseil' },
      { key: 'sku', label: 'Référence (SKU)', type: 'string', sample: 'SRV-001' },
      { key: 'type', label: 'Type', required: true, type: 'enum', enumValues: ['stock', 'service'], sample: 'service' },
      { key: 'description', label: 'Description', type: 'string', sample: 'Conseil en gestion' },
      { key: 'sale_price', label: 'Prix de vente', type: 'number', default: 0, sample: 500 },
      { key: 'purchase_price', label: "Prix d'achat", type: 'number', default: 0, sample: 0 },
      { key: 'vat_rate', label: 'Taux TVA', type: 'number', default: 20, sample: 20 },
      { key: 'unit', label: 'Unité', type: 'string', default: 'unité', sample: 'heure' },
      { key: 'category', label: 'Catégorie', type: 'string', sample: 'Services' },
    ],
  },
]

export function getModule(id: string): ImportModule | undefined {
  return IMPORT_MODULES.find((m) => m.id === id)
}

// Coerce a raw cell value to the expected field type. Returns { value, error }.
export function coerceValue(field: ImportField, raw: any): { value: any; error?: string } {
  const isEmpty = raw === undefined || raw === null || String(raw).trim() === ''

  if (isEmpty) {
    if (field.required) return { value: null, error: `${field.label} est obligatoire` }
    return { value: field.default ?? null }
  }

  const str = String(raw).trim()

  switch (field.type) {
    case 'number': {
      const num = Number(str.replace(',', '.').replace(/\s/g, ''))
      if (Number.isNaN(num)) return { value: null, error: `${field.label}: "${str}" n'est pas un nombre` }
      return { value: num }
    }
    case 'boolean': {
      const truthy = ['1', 'true', 'vrai', 'oui', 'yes', 'x']
      return { value: truthy.includes(str.toLowerCase()) }
    }
    case 'enum': {
      if (field.enumValues && !field.enumValues.includes(str)) {
        return { value: null, error: `${field.label}: "${str}" doit être parmi ${field.enumValues.join(', ')}` }
      }
      return { value: str }
    }
    default:
      return { value: str }
  }
}
