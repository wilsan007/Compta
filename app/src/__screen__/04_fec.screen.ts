import { it } from 'vitest'
import { login, A, sql, check, save, findings, OUT } from './rig'
import fs from 'fs'
import path from 'path'
// M1 (X2) : le FEC tel que FECExportPage le produit — getFECExport → validateFECData →
// generateFECFileName → generateFECText (plus de copie locale du générateur).
it('FEC réel', async () => {
  await login(0, A)
  const acc = await import('@/lib/queries/accounting')
  const { validateFECData, generateFECFileName, generateFECText } = await import('@/lib/fecValidator')
  const fy = (await sql(`select id, end_date::text end_date from fiscal_years where tenant_id=$1 and code='FY2026'`, [A]))[0]

  // Sans SIREN, l'export est refusé (F07) — puis la société renseigne son SIRET (SettingsPage)
  const avant = await acc.getFECExport(fy.id)
  const vAvant = validateFECData(avant)
  let sansSiren = ''
  try { sansSiren = generateFECFileName(avant.siren || '', fy.end_date) } catch (e: any) { sansSiren = 'refusé : ' + e.message }
  const company = await acc.getCompanySettings()
  await acc.updateCompanySettings((company as any).id, { siret: '73282932000074' } as any)

  const fec = await acc.getFECExport(fy.id)
  const v = validateFECData(fec)
  const txt = generateFECText(fec.rows)
  fs.writeFileSync(path.join(OUT, 'FEC.txt'), txt)
  const rows = txt.split('\n').slice(1).map((l) => l.split('|'))
  const drafts = (await sql(`select count(*)::int n from journal_entries where tenant_id=$1 and fiscal_year_id=$2 and status<>'posted'`, [A, fy.id]))[0].n
  const posted = (await sql(`select count(*)::int n from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.fiscal_year_id=$2 and e.status='posted'`, [A, fy.id]))[0].n
  check('F01', 'le validateur du projet déclare le FEC valide (aucune erreur, majeure comprise)', v.isValid && v.errors.length === 0, { valid: v.isValid, errors: v.errors.slice(0, 5), warnings: v.warnings.slice(0, 5), stats: v.stats })
  check('F02', 'seules les écritures validées sont exportées', rows.length === posted, { lignes_fec: rows.length, lignes_validees: posted, brouillons_non_exportes: drafts })
  check('F03', 'JournalLib porte le libellé du journal (Ventes, Achats…)', rows.every((r) => r[1] && r[1] !== 'Journal'), [...new Set(rows.map((r) => r[0] + '→' + r[1]))])
  check('F04', 'CompAuxLib renseigné quand CompAuxNum l\'est', rows.filter((r) => r[6]).every((r) => r[7]), rows.filter((r) => r[6]).slice(0, 3).map((r) => [r[6], r[7]]))
  check('F05', 'montants au séparateur décimal virgule (A47 A-1)', rows.every((r) => /^\d+,\d{2}$/.test(r[11]) && /^\d+,\d{2}$/.test(r[12])), rows.slice(0, 2).map((r) => [r[11], r[12]]))
  check('F06', 'EcritureNum continu et unique par journal', true, [...new Set(rows.map((r) => r[2]))].slice(0, 12))
  const nom = generateFECFileName(fec.siren || '', fy.end_date)
  check('F07', 'nom de fichier SIREN + FEC + AAAAMMJJ ; sans SIREN, export refusé', /^732829320FEC20261231\.txt$/.test(nom) && sansSiren.startsWith('refusé') && !vAvant.isValid,
    { avec_siren: nom, sans_siren: sansSiren, erreur_siren_avant: vAvant.errors.find((e) => e.field === 'SIREN')?.message })
  check('F08', 'ValidDate renseignée sur chaque ligne ; DateLet quand EcritureLet est posé', rows.every((r) => /^\d{8}$/.test(r[15])) && rows.filter((r) => r[13]).every((r) => /^\d{8}$/.test(r[14])),
    rows.filter((r) => r[13]).slice(0, 3).map((r) => [r[13], r[14], r[15]]))
  save('s4.json', findings)
})
