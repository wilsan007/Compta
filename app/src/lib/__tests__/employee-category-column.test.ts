/**
 * Défaut corrigé le 2026-10-01 — `getSalaryAnalysis('category')` lisait
 * `emp.category` sur une ligne `employees`, une colonne **qui n'existe pas**
 * (la vraie est `payroll_category`, cf. EmployeesPage.tsx et le schéma). Le
 * regroupement « analyse des salaires par catégorie » retombait donc TOUJOURS
 * sur 'N/A' : il ne groupait rien.
 *
 * Le défaut a été trouvé en typant `emp` en `Row<'employees'>` (démarrage de la
 * réduction de la dette `any`) : le `any` précédent laissait lire une colonne
 * inexistante sans que ni `tsc` ni les tests ne le voient. Ce fichier tient le
 * fait des deux côtés : la fonction lit la bonne colonne, et la colonne
 * `category` n'existe pas sur `employees`.
 */
import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

const racine = path.resolve(__dirname, '../../..') // app/
const lire = (p: string) => fs.readFileSync(path.join(racine, p), 'utf8')

describe('sprintH — analyse des salaires par catégorie', () => {
  it('getSalaryAnalysis lit `payroll_category` (la colonne réelle), pas `category`', () => {
    const src = lire('src/lib/queries/sprintH.ts')
    const debut = src.indexOf('export async function getSalaryAnalysis')
    expect(debut).toBeGreaterThan(-1)
    const apres = src.indexOf('\nexport ', debut + 1)
    const corps = apres > 0 ? src.slice(debut, apres) : src.slice(debut)

    expect(corps).toContain('emp.payroll_category')
    // `emp.category` (colonne inexistante) est interdit — les commentaires qui
    // citent le défaut sont retirés avant de juger la ligne.
    const fautives = corps
      .split('\n')
      .filter((l) => !l.trim().startsWith('//'))
      .filter((l) => /emp\.category\b/.test(l))
    expect(fautives).toEqual([])
  })

  it("le schéma généré ne porte AUCUNE colonne `category` sur `employees`", () => {
    const gen = lire('src/types/database-generated.ts')
    const debut = gen.indexOf('    employees: {')
    const fin = gen.indexOf('    entry_templates: {', debut)
    expect(debut).toBeGreaterThan(-1)
    expect(fin).toBeGreaterThan(debut)
    const bloc = gen.slice(debut, fin)

    expect(bloc).toContain('payroll_category')
    // Une colonne littéralement nommée `category:` (≠ `payroll_category:`) serait
    // le retour du défaut.
    expect(bloc).not.toMatch(/^\s+category:/m)
  })
})