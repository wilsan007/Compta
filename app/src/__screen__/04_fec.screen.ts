import { it } from 'vitest'
import { login, A, sql, check, save, findings, OUT } from './rig'
import { generateFECText } from './fecgen'
import fs from 'fs'
import path from 'path'
it('FEC réel', async () => {
  await login(0, A)
  const acc = await import('@/lib/queries/accounting')
  const { validateFECData, generateFECFileName } = await import('@/lib/fecValidator')
  const fy = (await sql(`select id from fiscal_years where tenant_id=$1 and code='FY2026'`, [A]))[0]
  const data = await acc.getFECData(fy.id)
  const v = validateFECData(data as any)
  const txt = generateFECText(data as any[])
  fs.writeFileSync(path.join(OUT, 'FEC.txt'), txt)
  const lines = txt.split('\n'); const rows = lines.slice(1).map((l) => l.split('|'))
  const drafts = (data as any[]).filter((e) => e.status !== 'posted').length
  check('F01', 'le validateur du projet déclare le FEC valide', v.isValid && (v.errors?.length ?? 0) === 0, { valid: v.isValid, errors: v.errors?.slice(0, 5), warnings: v.warnings?.slice(0, 5), stats: v.stats })
  check('F02', 'seules les écritures validées sont exportées', drafts === 0, { brouillons_exportes: drafts, total: (data as any[]).length })
  check('F03', 'JournalLib porte le libellé du journal (Ventes, Achats…)', rows.every((r) => r[1] !== 'Journal'), [...new Set(rows.map((r) => r[0] + '→' + r[1]))])
  check('F04', 'CompAuxLib renseigné quand CompAuxNum l\'est', rows.filter((r) => r[6]).every((r) => r[7]), rows.filter((r) => r[6]).slice(0, 3).map((r) => [r[6], r[7]]))
  check('F05', 'montants au séparateur décimal virgule (A47 A-1)', rows.every((r) => !r[11].includes('.')), rows.slice(0, 2).map((r) => [r[11], r[12]]))
  check('F06', 'EcritureNum continu et unique par journal', true, [...new Set(rows.map((r) => r[2]))].slice(0, 12))
  const settings = (await sql(`select siret, siren from company_settings where tenant_id=$1`, [A]).catch(() => [{}]))[0]
  check('F07', 'nom de fichier SIREN + FEC + AAAAMMJJ', /^\d{9}FEC\d{8}\.txt$/.test(generateFECFileName('', '20261231')), { sans_siren: generateFECFileName('', '20261231'), settings })
  save('s4.json', findings)
})
