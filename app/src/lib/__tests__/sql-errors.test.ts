import { describe, it, expect, beforeAll } from 'vitest'
import i18n from 'i18next'
import fr from '@/i18n/locales/fr/errors.json'
import { sqlErrorMessage, sqlErrorTextMessage } from '@/lib/errors'
import { errorMessage } from '@/lib/utils'

// F4 (cpt-003, rh-001) : un message SQL brut ne doit jamais atteindre l'écran.
describe('traducteur des erreurs de la base — F4', () => {
  beforeAll(async () => {
    await i18n.init({ lng: 'fr', ns: ['errors'], resources: { fr: { errors: fr } } })
  })

  it('doublon de compte : nomme le compte', () => {
    const m = sqlErrorMessage({ code: '23505',
      message: 'duplicate key value violates unique constraint "chart_accounts_tenant_code_key"',
      details: 'Key (tenant_id, code)=(7b1c0b3e-0000-0000-0000-000000000000, 606800) already exists.' })
    expect(m).toBe('Le compte 606800 existe déjà.')
  })

  it('salaire négatif (rh-001)', () => {
    expect(sqlErrorMessage({ code: '23514',
      message: 'new row for relation "employees" violates check constraint "employees_salary_nonneg"' }))
      .toBe('Le salaire ne peut pas être négatif.')
  })

  it('prix négatif, type de contrat, heures négatives : contraintes connues', () => {
    const check = (c: string) => sqlErrorMessage({ code: '23514', message: `new row for relation "x" violates check constraint "${c}"` })
    expect(check('products_sale_price_nonneg')).toBe('Un prix ne peut pas être négatif.')
    expect(check('employees_contract_type_check')).toBe('Ce type de contrat n\'est pas reconnu.')
    expect(check('timesheets_hours_nonneg')).toBe('Un nombre d\'heures ne peut pas être négatif.')
  })

  it('repli générique : doublon et contrainte inconnus', () => {
    expect(sqlErrorMessage({ code: '23505', message: 'duplicate key value violates unique constraint "autre_cle"',
      details: 'Key (tenant_id, sku)=(x, ABC-1) already exists.' })).toBe('« ABC-1 » existe déjà.')
    expect(sqlErrorMessage({ code: '23505', message: 'duplicate key value violates unique constraint "autre_cle"' }))
      .toBe('Cet élément existe déjà.')
    expect(sqlErrorMessage({ code: '23514', message: 'new row for relation "x" violates check constraint "inconnue"' }))
      .toContain('n\'est pas acceptée')
  })

  it('champ obligatoire, référence, droit, valeur invalide', () => {
    expect(sqlErrorMessage({ code: '23502', message: 'null value in column "name" of relation "customers" violates not-null constraint' }))
      .toContain('(name)')
    expect(sqlErrorMessage({ code: '23503', message: 'update or delete on table "customers" violates foreign key constraint "fk" on table "invoices"',
      details: 'Key (id)=(1) is still referenced from table "invoices".' })).toContain('encore utilisé')
    expect(sqlErrorMessage({ code: '23503', message: 'insert or update on table "invoices" violates foreign key constraint "fk"',
      details: 'Key (customer_id)=(1) is not present in table "customers".' })).toContain('introuvable')
    expect(sqlErrorMessage({ code: '42501', message: 'new row violates row-level security policy for table "invoices"' }))
      .toBe('Vous n\'avez pas le droit d\'effectuer cette action.')
    expect(sqlErrorMessage({ code: '22P02', message: 'invalid input syntax for type uuid: ""' })).toBe('Une valeur saisie est invalide.')
  })

  it('un message RÉDIGÉ par la base passe tel quel, même avec un code de contrainte', () => {
    const redige = { code: '23514', message: 'Date d\'embauche invalide (01/01/2099) : elle doit être comprise entre le 01/01/1950 et un an après aujourd\'hui.' }
    expect(sqlErrorMessage(redige)).toBeNull()
    expect(errorMessage(redige)).toBe(redige.message)
  })

  it('errorMessage, la porte de tous les écrans, traduit', () => {
    expect(errorMessage({ code: '23505',
      message: 'duplicate key value violates unique constraint "chart_accounts_tenant_code_key"',
      details: 'Key (tenant_id, code)=(x, 606800) already exists.' })).toBe('Le compte 606800 existe déjà.')
    expect(errorMessage(new Error('panne réseau'))).toBe('panne réseau')
  })
  it('sans son code (écran qui passe err.message) : le message est reconnu à sa forme', () => {
    expect(sqlErrorTextMessage('duplicate key value violates unique constraint "chart_accounts_tenant_code_key"'))
      .toBe('Cet élément existe déjà.')
    expect(sqlErrorTextMessage('new row for relation "employees" violates check constraint "employees_salary_nonneg"'))
      .toBe('Le salaire ne peut pas être négatif.')
    expect(sqlErrorTextMessage('new row violates row-level security policy for table "invoices"'))
      .toBe("Vous n'avez pas le droit d'effectuer cette action.")
    expect(sqlErrorTextMessage('Le lot est vide : aucun bulletin à approuver')).toBeNull()
    expect(sqlErrorTextMessage(undefined)).toBeNull()
  })
})
