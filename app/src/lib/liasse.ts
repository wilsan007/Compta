import type { TrialBalanceLine } from '@/lib/queries/accounting'

/**
 * 2.16 — le compte de résultat de la liasse fiscale, tiré de la balance générale.
 *
 * L'écran lisait `a.code`, `a.debit` et `a.credit` sur des lignes qui portent
 * `account_code`, `total_debit` et `total_credit` : aucun compte de classe 6 ou 7
 * n'était retenu, les produits, les charges et le résultat valaient toujours 0.
 */
export interface LiasseAccount { code: string; name: string; amount: number }

export function incomeFromTrialBalance(lines: TrialBalanceLine[]) {
  const pick = (classe: string, sens: 1 | -1): LiasseAccount[] => lines
    .filter((l) => l.account_code.startsWith(classe))
    .map((l) => ({ code: l.account_code, name: l.account_name, amount: sens * (l.total_credit - l.total_debit) }))
  const revenueAccounts = pick('7', 1)
  const expenseAccounts = pick('6', -1)
  const totalRevenue = revenueAccounts.reduce((s, a) => s + a.amount, 0)
  const totalExpenses = expenseAccounts.reduce((s, a) => s + a.amount, 0)
  return { revenueAccounts, expenseAccounts, totalRevenue, totalExpenses, netResult: totalRevenue - totalExpenses }
}
