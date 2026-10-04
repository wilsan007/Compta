import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'
import { incomeFromTrialBalance } from '@/lib/liasse'
import type { TrialBalanceLine } from '@/lib/queries/accounting'

const ligne = (account_code: string, total_debit: number, total_credit: number): TrialBalanceLine => ({
  account_code, account_name: `Compte ${account_code}`, opening_debit: 0, opening_credit: 0,
  total_debit, total_credit, closing_debit: total_debit, closing_credit: total_credit,
})

// 2.16 — défaut révélé en typant `getTrialBalance` : la liasse fiscale lisait des
// propriétés que la balance ne porte pas, son compte de résultat valait toujours 0.
describe('liasse fiscale — le compte de résultat se lit sur la balance réelle', () => {
  const balance = [ligne('411000', 1200, 0), ligne('706000', 0, 1000), ligne('606400', 400, 0), ligne('445710', 0, 200)]

  it('1 000 de produits, 400 de charges : résultat 600', () => {
    const r = incomeFromTrialBalance(balance)
    expect(r.totalRevenue).toBe(1000)
    expect(r.totalExpenses).toBe(400)
    expect(r.netResult).toBe(600)
    expect(r.revenueAccounts).toEqual([{ code: '706000', name: 'Compte 706000', amount: 1000 }])
    expect(r.expenseAccounts).toEqual([{ code: '606400', name: 'Compte 606400', amount: 400 }])
  })

  it("l'ancienne lecture de l'écran (code, debit, credit) ne retenait AUCUN compte", () => {
    // Ce que faisait la page avant le correctif, rejoué sur la même balance : la mesure du rouge.
    const lignes = balance as unknown as { code?: string }[]
    expect(lignes.filter((a) => a.code?.startsWith('7'))).toEqual([])
  })

  it("l'écran passe par cette fonction, et son état est typé", () => {
    const src = fs.readFileSync(path.resolve(__dirname, '../../pages/LiasseFiscalePage.tsx'), 'utf8')
    expect(src).toMatch(/incomeFromTrialBalance\(trialBalance\)/)
    expect(src).not.toMatch(/a\.code\?\.startsWith/)
  })
})
