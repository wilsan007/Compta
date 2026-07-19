import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell } from '@/components/ui'
import { getEmployees, getPayRuns, getTimesheets } from '@/lib/queries'
import { formatCurrency, formatDate, translateStatus } from '@/lib/utils'
import type { Employee, PayRun } from '@/types'
import { useToast } from '@/lib/toast'

export function HRDashboardPage() {
  const { toast } = useToast()
const [employees, setEmployees] = useState<Employee[]>([])
  const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [timesheets, setTimesheets] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [e, pr, ts] = await Promise.all([getEmployees(), getPayRuns(), getTimesheets()])
      setEmployees(e)
      setPayRuns(pr)
      setTimesheets(ts)
    } catch (err) { console.error(err); toast('error', 'Erreur', 'Erreur lors du chargement') } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const activeCount = employees.filter(e => e.status === 'active').length
  const totalPayroll = employees.filter(e => e.status === 'active').reduce((s, e) => s + Number(e.salary), 0)
  const pendingTimesheets = timesheets.filter((t: any) => t.status === 'pending').length
  const lastPayRun = payRuns[0]

  return (
    <div>
      <Breadcrumb items={[{ label: 'Tableaux de bord' }, { label: 'RH & Paie' }]} />
      <PageHeader title="Tableau de bord — RH & Paie" subtitle="Vue d'ensemble de vos ressources humaines" />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4 mb-6">
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Employés actifs</p><p className="text-2xl font-bold">{activeCount}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Masse salariale</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalPayroll)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Temps en attente</p><p className="text-2xl font-bold text-[var(--color-warning)]">{pendingTimesheets}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Bulletins de paie</p><p className="text-2xl font-bold">{payRuns.length}</p></div></Card>
          </div>

          <div className="grid grid-cols-2 gap-6">
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Employés par département</h3>
              <Table headers={['Département', 'Employés', 'Salaire total']}>
                {Object.entries(
                  employees.reduce((acc, e) => {
                    const dept = e.department || 'Non assigné'
                    if (!acc[dept]) acc[dept] = { count: 0, salary: 0 }
                    acc[dept].count++
                    acc[dept].salary += Number(e.salary)
                    return acc
                  }, {} as Record<string, { count: number; salary: number }>)
                ).map(([dept, info]) => (
                  <TableRow key={dept}>
                    <TableCell className="text-sm">{dept}</TableCell>
                    <TableCell className="font-mono text-xs">{info.count}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(info.salary)}</TableCell>
                  </TableRow>
                ))}
                {employees.length === 0 && <TableRow><TableCell colSpan={3} className="text-center text-[var(--color-text-secondary)] text-sm">Aucun employé</TableCell></TableRow>}
              </Table>
            </Card>

            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Derniers bulletins de paie</h3>
              <Table headers={['Numéro', 'Période', 'Net', 'Statut']}>
                {payRuns.slice(0, 5).map((pr) => (
                  <TableRow key={pr.id}>
                    <TableCell className="font-mono text-xs">{pr.number}</TableCell>
                    <TableCell className="text-xs">{formatDate(pr.period_start)} → {formatDate(pr.period_end)}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(pr.net_total))}</TableCell>
                    <TableCell className="text-xs">{translateStatus(pr.status)}</TableCell>
                  </TableRow>
                ))}
                {payRuns.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)] text-sm">Aucun bulletin</TableCell></TableRow>}
              </Table>
            </Card>
          </div>

          {lastPayRun && (
            <div className="mt-6">
              <Card>
                <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Dernier bulletin de paie</h3>
                <div className="p-4 grid grid-cols-3 gap-4 text-sm">
                  <div><span className="text-[var(--color-text-secondary)]">Brut total: </span><span className="font-mono font-bold">{formatCurrency(Number(lastPayRun.gross_total))}</span></div>
                  <div><span className="text-[var(--color-text-secondary)]">Charges: </span><span className="font-mono text-[var(--color-danger)]">{formatCurrency(Number(lastPayRun.tax_total))}</span></div>
                  <div><span className="text-[var(--color-text-secondary)]">Net total: </span><span className="font-mono font-bold text-[var(--color-success)]">{formatCurrency(Number(lastPayRun.net_total))}</span></div>
                </div>
              </Card>
            </div>
          )}
        </>
      )}
    </div>
  )
}
