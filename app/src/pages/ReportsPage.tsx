import { Card, PageHeader, Button, Table, TableRow, TableCell, StatCard, Breadcrumb } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { TrendingUp, TrendingDown, DollarSign, FileText, Download } from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line, Legend } from 'recharts'

export function ReportsPage() {
  const plData = [
    { category: 'Revenus', amount: 85600 },
    { category: 'Coût des ventes', amount: -32000 },
    { category: 'Salaires', amount: -28000 },
    { category: 'Loyer', amount: -8400 },
    { category: 'Marketing', amount: -5200 },
    { category: 'Autres dépenses', amount: -3800 },
  ]

  const monthlyTrend = [
    { month: 'Jan', revenus: 12500, depenses: 8200, profit: 4300 },
    { month: 'Fév', revenus: 15200, depenses: 9100, profit: 6100 },
    { month: 'Mar', revenus: 18900, depenses: 11200, profit: 7700 },
    { month: 'Avr', revenus: 16500, depenses: 10500, profit: 6000 },
    { month: 'Mai', revenus: 22300, depenses: 13800, profit: 8500 },
    { month: 'Juin', revenus: 19800, depenses: 12500, profit: 7300 },
    { month: 'Juil', revenus: 25600, depenses: 14200, profit: 11400 },
  ]

  const totalRevenue = 85600
  const totalExpenses = 78400
  const netProfit = totalRevenue - totalExpenses

  return (
    <div className="animate-fade-in">
      <Breadcrumb items={[{ label: 'Rapports' }]} />
      <PageHeader
        title="Rapports financiers"
        subtitle="Analyse de la performance de votre entreprise"
        action={<Button variant="secondary"><Download className="w-4 h-4" /> Exporter</Button>}
      />

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <StatCard label="Revenus totaux" value={formatCurrency(totalRevenue)} icon={<TrendingUp className="w-5 h-5" />} color="success" />
        <StatCard label="Dépenses totales" value={formatCurrency(totalExpenses)} icon={<TrendingDown className="w-5 h-5" />} color="danger" />
        <StatCard label="Résultat net" value={formatCurrency(netProfit)} icon={<DollarSign className="w-5 h-5" />} color="primary" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <Card title="Compte de résultat" subtitle="Répartition par catégorie">
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={plData} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
              <XAxis type="number" stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} tickFormatter={(v) => `${v / 1000}k`} />
              <YAxis type="category" dataKey="category" stroke="var(--color-text-secondary)" style={{ fontSize: 11 }} width={100} />
              <Tooltip formatter={(value: number) => formatCurrency(value)} contentStyle={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: '8px', fontSize: 12 }} />
              <Bar dataKey="amount" fill="var(--color-primary)" radius={[0, 4, 4, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>

        <Card title="Tendance mensuelle" subtitle="Revenus, dépenses et profit">
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={monthlyTrend}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
              <XAxis dataKey="month" stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} />
              <YAxis stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} tickFormatter={(v) => `${v / 1000}k`} />
              <Tooltip formatter={(value: number) => formatCurrency(value)} contentStyle={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: '8px', fontSize: 12 }} />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              <Line type="monotone" dataKey="revenus" stroke="var(--color-primary)" strokeWidth={2} name="Revenus" />
              <Line type="monotone" dataKey="depenses" stroke="var(--color-danger)" strokeWidth={2} name="Dépenses" />
              <Line type="monotone" dataKey="profit" stroke="var(--color-success)" strokeWidth={2} name="Profit" />
            </LineChart>
          </ResponsiveContainer>
        </Card>
      </div>

      <Card title="Détail du compte de résultat">
        <Table headers={['Catégorie', 'Montant', '% du total']}>
          {plData.map((row) => (
            <TableRow key={row.category}>
              <TableCell className="font-medium">{row.category}</TableCell>
              <TableCell className={row.amount < 0 ? 'text-[var(--color-danger)] text-right' : 'text-[var(--color-success)] text-right'}>
                {formatCurrency(Math.abs(row.amount))}
              </TableCell>
              <TableCell className="text-[var(--color-text-secondary)]">
                {((Math.abs(row.amount) / totalRevenue) * 100).toFixed(1)}%
              </TableCell>
            </TableRow>
          ))}
          <TableRow key="total">
            <TableCell className="font-bold">Résultat net</TableCell>
            <TableCell className="font-bold text-[var(--color-primary)] text-right">{formatCurrency(netProfit)}</TableCell>
            <TableCell className="text-[var(--color-text-secondary)]">—</TableCell>
          </TableRow>
        </Table>
      </Card>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-6">
        {[
          { label: 'Bilan', icon: FileText, path: '/reports/balance-sheet' },
          { label: 'Balance générale', icon: FileText, path: '/reports/trial-balance' },
          { label: 'Flux de trésorerie', icon: FileText, path: '/reports/cash-flow' },
          { label: 'TVA', icon: FileText, path: '/reports/vat' },
        ].map((r) => (
          <Card key={r.path} className="p-4 hover:shadow-md transition-shadow cursor-pointer">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-[rgba(0,102,204,0.1)] flex items-center justify-center">
                <r.icon className="w-5 h-5 text-[var(--color-primary)]" />
              </div>
              <span className="text-sm font-medium text-[var(--color-text)]">{r.label}</span>
            </div>
          </Card>
        ))}
      </div>
    </div>
  )
}
