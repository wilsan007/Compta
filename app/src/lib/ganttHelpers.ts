import type { ViewMode, GanttTask } from '@/types/projectManagement'

export interface ViewConfigInternal {
  viewMode: ViewMode
  yearBuffer: number
}

export const VIEW_MODE_CONFIG: Record<ViewMode, { label: string; daysPerUnit: number; pixelPerUnit: number }> = {
  day: { label: 'Day', daysPerUnit: 1, pixelPerUnit: 40 },
  week: { label: 'Week', daysPerUnit: 7, pixelPerUnit: 30 },
  month: { label: 'Month', daysPerUnit: 30, pixelPerUnit: 120 },
  quarter: { label: 'Quarter', daysPerUnit: 90, pixelPerUnit: 100 },
  year: { label: 'Year', daysPerUnit: 365, pixelPerUnit: 80 },
}

export function getTimelineRange(tasks: GanttTask[], yearBuffer: number = 1): { start: Date; end: Date } {
  if (tasks.length === 0) {
    const now = new Date()
    const start = new Date(now.getFullYear() - yearBuffer, 0, 1)
    const end = new Date(now.getFullYear() + yearBuffer, 11, 31)
    return { start, end }
  }

  let minDate = new Date(tasks[0].start_date || tasks[0].due_date || new Date())
  let maxDate = new Date(tasks[0].due_date || tasks[0].start_date || new Date())

  for (const task of tasks) {
    if (task.start_date) {
      const d = new Date(task.start_date)
      if (d < minDate) minDate = d
    }
    if (task.due_date) {
      const d = new Date(task.due_date)
      if (d > maxDate) maxDate = d
    }
  }

  minDate.setFullYear(minDate.getFullYear() - yearBuffer)
  maxDate.setFullYear(maxDate.getFullYear() + yearBuffer)

  return { start: minDate, end: maxDate }
}

export function getTaskPosition(
  task: GanttTask,
  timelineStart: Date,
  viewMode: ViewMode
): { left: number; width: number } {
  const config = VIEW_MODE_CONFIG[viewMode]
  const dayToPixel = config.pixelPerUnit / config.daysPerUnit

  const taskStart = new Date(task.start_date || task.due_date || new Date())
  const taskEnd = new Date(task.due_date || task.start_date || new Date())

  if (taskEnd < taskStart) taskEnd.setTime(taskStart.getTime())

  const diffStart = Math.max(0, (taskStart.getTime() - timelineStart.getTime()) / (1000 * 60 * 60 * 24))
  const diffEnd = Math.max(1, (taskEnd.getTime() - taskStart.getTime()) / (1000 * 60 * 60 * 24))

  const left = diffStart * dayToPixel
  const width = Math.max(20, diffEnd * dayToPixel)

  return { left, width }
}

export function getTimelineWidth(timelineStart: Date, timelineEnd: Date, viewMode: ViewMode): number {
  const config = VIEW_MODE_CONFIG[viewMode]
  const dayToPixel = config.pixelPerUnit / config.daysPerUnit
  const totalDays = (timelineEnd.getTime() - timelineStart.getTime()) / (1000 * 60 * 60 * 24)
  return totalDays * dayToPixel
}

export function getTimelineHeaders(
  timelineStart: Date,
  timelineEnd: Date,
  viewMode: ViewMode
): { label: string; position: number; width: number }[] {
  const config = VIEW_MODE_CONFIG[viewMode]
  const dayToPixel = config.pixelPerUnit / config.daysPerUnit
  const headers: { label: string; position: number; width: number }[] = []

  const current = new Date(timelineStart)

  if (viewMode === 'day') {
    while (current <= timelineEnd) {
      const pos = ((current.getTime() - timelineStart.getTime()) / (1000 * 60 * 60 * 24)) * dayToPixel
      headers.push({
        label: current.toLocaleDateString(undefined, { day: '2-digit', month: 'short' }),
        position: pos,
        width: config.pixelPerUnit,
      })
      current.setDate(current.getDate() + 1)
    }
  } else if (viewMode === 'week') {
    while (current <= timelineEnd) {
      const pos = ((current.getTime() - timelineStart.getTime()) / (1000 * 60 * 60 * 24)) * dayToPixel
      headers.push({
        label: `W${getWeekNumber(current)}`,
        position: pos,
        width: config.pixelPerUnit,
      })
      current.setDate(current.getDate() + 7)
    }
  } else if (viewMode === 'month') {
    while (current <= timelineEnd) {
      const pos = ((current.getTime() - timelineStart.getTime()) / (1000 * 60 * 60 * 24)) * dayToPixel
      headers.push({
        label: current.toLocaleDateString(undefined, { month: 'short', year: '2-digit' }),
        position: pos,
        width: config.pixelPerUnit,
      })
      current.setMonth(current.getMonth() + 1)
    }
  } else if (viewMode === 'quarter') {
    while (current <= timelineEnd) {
      const pos = ((current.getTime() - timelineStart.getTime()) / (1000 * 60 * 60 * 24)) * dayToPixel
      const q = Math.floor(current.getMonth() / 3) + 1
      headers.push({
        label: `Q${q} ${current.getFullYear()}`,
        position: pos,
        width: config.pixelPerUnit,
      })
      current.setMonth(current.getMonth() + 3)
    }
  } else {
    while (current <= timelineEnd) {
      const pos = ((current.getTime() - timelineStart.getTime()) / (1000 * 60 * 60 * 24)) * dayToPixel
      headers.push({
        label: String(current.getFullYear()),
        position: pos,
        width: config.pixelPerUnit,
      })
      current.setFullYear(current.getFullYear() + 1)
    }
  }

  return headers
}

function getWeekNumber(date: Date): number {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
  const dayNum = d.getUTCDay() || 7
  d.setUTCDate(d.getUTCDate() + 4 - dayNum)
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
  return Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)
}

export function formatDateForGantt(dateStr: string | null): string {
  if (!dateStr) return ''
  const d = new Date(dateStr)
  if (isNaN(d.getTime())) return dateStr
  return d.toISOString().split('T')[0]
}

export function snapDateToTimeline(date: Date, viewMode: ViewMode): Date {
  if (viewMode === 'week') {
    const day = date.getDay()
    date.setDate(date.getDate() - day)
  } else if (viewMode === 'month') {
    date.setDate(1)
  } else if (viewMode === 'quarter') {
    const month = date.getMonth()
    date.setMonth(Math.floor(month / 3) * 3)
    date.setDate(1)
  } else if (viewMode === 'year') {
    date.setMonth(0)
    date.setDate(1)
  }
  return date
}
