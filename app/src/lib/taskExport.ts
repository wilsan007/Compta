// Export des tâches du tableau en Excel, PDF et CSV — mêmes colonnes, libellés
// et métadonnées que l'export de wadashaqayn. Les bibliothèques (xlsx, jsPDF)
// ne sont chargées qu'au moment d'exporter.
import type { ProjectTask, TaskFilters } from '@/types/projectManagement'

const STATUS_LABELS: Record<string, string> = {
  todo: 'À faire',
  doing: 'En cours',
  blocked: 'Bloqué',
  changes_requested: 'Modifications demandées',
  approved: 'Approuvé',
  done: 'Terminé',
  canceled: 'Annulé',
}
const PRIORITY_LABELS: Record<string, string> = { low: 'Basse', medium: 'Moyenne', high: 'Haute', urgent: 'Urgente' }

export interface ExportContext {
  projectNames: Map<string, string>
  parentTitles: Map<string, string>
  filters?: TaskFilters
}

const today = () => new Date().toISOString().split('T')[0]

function rows(tasks: ProjectTask[], ctx: ExportContext) {
  return tasks.map((t) => ({
    ID: t.id,
    Titre: t.title,
    Description: t.description || '',
    Statut: STATUS_LABELS[t.status] || t.status,
    Priorité: PRIORITY_LABELS[t.priority] || t.priority,
    'Assigné à': t.assignee || 'Non assigné',
    Projet: (t.project_id && ctx.projectNames.get(t.project_id)) || 'Aucun',
    'Date début': t.start_date || '',
    'Date fin': t.due_date || '',
    Progression: `${t.progress || 0}%`,
    'Effort estimé (h)': t.effort_estimate_h || 0,
    'Tâche parente': (t.parent_id && ctx.parentTitles.get(t.parent_id)) || '',
    'Créée le': t.created_at ? new Date(t.created_at).toLocaleDateString('fr-FR') : '',
  }))
}

function metadata(tasks: ProjectTask[], f?: TaskFilters): [string, string][] {
  const m: [string, string][] = [
    ['Date export', new Date().toLocaleString('fr-FR')],
    ['Nombre de tâches', String(tasks.length)],
    ['Filtres appliqués', f && hasFilters(f) ? 'Oui' : 'Non'],
  ]
  if (f?.search) m.push(['Recherche', f.search])
  if (f?.status.length) m.push(['Statuts', f.status.map((s) => STATUS_LABELS[s] || s).join(', ')])
  if (f?.priority.length) m.push(['Priorités', f.priority.map((p) => PRIORITY_LABELS[p] || p).join(', ')])
  if (f?.dateFrom) m.push(['Du', f.dateFrom])
  if (f?.dateTo) m.push(['Au', f.dateTo])
  return m
}

function hasFilters(f: TaskFilters): boolean {
  return !!(f.search || f.status.length || f.priority.length || f.assignee.length || f.project.length || f.dateFrom || f.dateTo)
}

function save(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

export async function exportTasksToExcel(tasks: ProjectTask[], ctx: ExportContext): Promise<string> {
  const XLSX = await import('xlsx')
  const data = rows(tasks, ctx)
  const ws = XLSX.utils.json_to_sheet(data)
  ws['!cols'] = [35, 40, 50, 14, 12, 20, 25, 12, 12, 12, 15, 30, 12].map((wch) => ({ wch }))
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, 'Tâches')
  const meta = XLSX.utils.aoa_to_sheet([['Propriété', 'Valeur'], ...metadata(tasks, ctx.filters)])
  meta['!cols'] = [{ wch: 20 }, { wch: 40 }]
  XLSX.utils.book_append_sheet(wb, meta, 'Métadonnées')
  const name = `taches_${today()}.xlsx`
  XLSX.writeFile(wb, name)
  return name
}

export async function exportTasksToPdf(tasks: ProjectTask[], ctx: ExportContext): Promise<string> {
  const [{ default: JsPDF }, { default: autoTable }] = await Promise.all([import('jspdf'), import('jspdf-autotable')])
  const doc = new JsPDF('l', 'mm', 'a4') // paysage, pour les colonnes
  doc.setFontSize(18)
  doc.setFont('helvetica', 'bold')
  doc.text('Export des Tâches', 14, 15)
  doc.setFontSize(10)
  doc.setFont('helvetica', 'normal')
  let y = 25
  for (const [k, v] of metadata(tasks, ctx.filters)) {
    doc.text(`${k} : ${v}`, 14, y)
    y += 5
  }
  const cut = (s: string, n: number) => (s.length > n ? `${s.slice(0, n)}...` : s)
  autoTable(doc, {
    head: [['Titre', 'Statut', 'Priorité', 'Assigné', 'Projet', 'Début', 'Fin', 'Prog.']],
    body: tasks.map((t) => [
      cut(t.title, 30),
      STATUS_LABELS[t.status] || t.status,
      PRIORITY_LABELS[t.priority] || t.priority,
      cut(t.assignee || 'N/A', 15),
      cut((t.project_id && ctx.projectNames.get(t.project_id)) || 'Aucun', 20),
      t.start_date || '',
      t.due_date || '',
      `${t.progress || 0}%`,
    ]),
    startY: y + 3,
    theme: 'grid',
    styles: { fontSize: 8, cellPadding: 2 },
    headStyles: { fillColor: [79, 70, 229], textColor: 255, fontStyle: 'bold' },
    alternateRowStyles: { fillColor: [245, 247, 250] },
  })
  const name = `taches_${today()}.pdf`
  save(doc.output('blob'), name)
  return name
}

export function exportTasksToCsv(tasks: ProjectTask[], ctx: ExportContext): string {
  const data = rows(tasks, ctx)
  const headers = Object.keys(data[0] || { Titre: '' })
  const esc = (v: unknown) => {
    const s = String(v ?? '')
    return /[",\n;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  const csv = [headers.join(','), ...data.map((r) => headers.map((h) => esc((r as Record<string, unknown>)[h])).join(','))].join('\n')
  const name = `taches_${today()}.csv`
  save(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' }), name)
  return name
}
