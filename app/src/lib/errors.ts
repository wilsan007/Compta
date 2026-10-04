import i18n from 'i18next'

/**
 * F4 (cpt-003, rh-001) — le traducteur des erreurs de la base.
 *
 * PostgREST rend l'erreur PostgreSQL telle quelle : `{ code, message, details }`,
 * par exemple `23505` et « duplicate key value violates unique constraint
 * "chart_accounts_tenant_code_key" ». Les écrans l'affichaient brute.
 *
 * Ce module ne traduit QUE les messages techniques de PostgreSQL. Un message
 * RÉDIGÉ par la base (`RAISE EXCEPTION 'Date d''embauche invalide…'`) est déjà
 * une phrase pour l'utilisateur : il passe tel quel, même s'il porte un code
 * 23514. Rend `null` quand l'erreur n'est pas une erreur SQL brute.
 */

interface PgError { code?: unknown; message?: unknown; details?: unknown }

/** Contraintes connues → clé de message (`errors:db.constraints.<clé>`). */
const CONSTRAINTS: Record<string, string> = {
  chart_accounts_tenant_code_key: 'chartAccountExists',
  manufacturing_orders_tenant_number_key: 'documentNumberExists',
  employees_salary_nonneg: 'salaryNegative',
  employees_contract_type_check: 'contractTypeInvalid',
  employees_email_format_check: 'emailInvalid',
  products_sale_price_nonneg: 'priceNegative',
  products_purchase_price_nonneg: 'priceNegative',
  products_cost_price_nonneg: 'priceNegative',
  products_stock_quantity_nonneg: 'stockNegative',
  timesheets_hours_nonneg: 'hoursNegative',
  distribution_grills_account_fkey: 'grillAccountMissing',
  distribution_grill_lines_section_fkey: 'grillSectionMissing',
}

const t = (key: string, vars?: Record<string, unknown>) => i18n.t(`errors:db.${key}`, vars) as string

/** Le nom entre guillemets qui suit `mot` dans un message PostgreSQL. */
function quoted(message: string, after: string): string | null {
  const m = message.match(new RegExp(`${after} "([^"]+)"`))
  return m ? m[1] : null
}

/** La dernière valeur de « Key (a, b)=(x, y) already exists. » — celle que l'utilisateur a saisie. */
function duplicateValue(details: unknown): string {
  if (typeof details !== 'string') return ''
  const m = details.match(/=\((.*)\)\s/)
  if (!m) return ''
  const parts = m[1].split(',').map((p) => p.trim())
  return parts[parts.length - 1] ?? ''
}

export function sqlErrorMessage(err: unknown): string | null {
  if (!err || typeof err !== 'object') return null
  const e = err as PgError
  const code = typeof e.code === 'string' ? e.code : ''
  const message = typeof e.message === 'string' ? e.message : ''
  if (!code || !message) return null

  // Doublon
  if (code === '23505' && message.startsWith('duplicate key value')) {
    const constraint = quoted(message, 'unique constraint') ?? ''
    const value = duplicateValue(e.details)
    const key = CONSTRAINTS[constraint]
    // Un message qui NOMME la valeur n'a de sens que si on la connaît.
    return key && value ? t(`constraints.${key}`, { value }) : t(value ? 'duplicateValue' : 'duplicate', { value })
  }

  // Contrainte de valeur
  if (code === '23514' && message.includes('violates check constraint')) {
    const key = CONSTRAINTS[quoted(message, 'check constraint') ?? '']
    return key ? t(`constraints.${key}`, { value: '' }) : t('check')
  }

  // Champ obligatoire
  if (code === '23502' && message.includes('violates not-null constraint')) {
    return t('notNull', { column: quoted(message, 'column') ?? '' })
  }

  // Référence : élément encore utilisé, ou élément lié introuvable
  if (code === '23503' && message.includes('violates foreign key constraint')) {
    const fk = CONSTRAINTS[quoted(message, 'foreign key constraint') ?? '']
    if (fk) return t(`constraints.${fk}`, { value: '' })
    const detail = typeof e.details === 'string' ? e.details : ''
    return t(detail.includes('is still referenced') || message.startsWith('update or delete') ? 'stillReferenced' : 'referenceMissing')
  }

  // Droits
  if (code === '42501' && (message.startsWith('permission denied') || message.includes('row-level security'))) {
    return t('forbidden')
  }

  // Valeur illisible ou hors bornes
  if ((code === '22P02' && message.startsWith('invalid input syntax'))
      || (code === '22003' && message.includes('out of range'))) {
    return t('invalidValue')
  }

  return null
}

/**
 * Le même traducteur, pour un message reçu SANS son code — ce que font encore une
 * centaine d'écrans, qui passent `err.message` à la notification au lieu de
 * l'erreur. Le code est retrouvé d'après la forme du message PostgreSQL ; le
 * détail (la valeur en doublon) n'est plus là, le message est donc plus général.
 * Rend `null` pour tout message qui n'est pas un message SQL brut.
 */
export function sqlErrorTextMessage(text: string | null | undefined): string | null {
  if (!text) return null
  const code =
    text.startsWith('duplicate key value') ? '23505'
    : text.includes('violates check constraint') ? '23514'
    : text.includes('violates not-null constraint') ? '23502'
    : text.includes('violates foreign key constraint') ? '23503'
    : (text.startsWith('permission denied') || text.includes('row-level security')) ? '42501'
    : text.startsWith('invalid input syntax') ? '22P02'
    : ''
  return code ? sqlErrorMessage({ code, message: text }) : null
}
