export const GANTT_COLOR_PALETTE: string[] = [
  '#0066cc', '#00875a', '#de350b', '#ff9900',
  '#6554c0', '#00b8d9', '#ff5630', '#36b37e',
  '#403294', '#0052cc', '#97a0af', '#172b4d',
  '#794bc4', '#e64980', '#1c7ed6', '#37b24d',
  '#f59f00', '#e03131', '#7048e8', '#1098ad',
  '#2b8a3e', '#c92a2a', '#5f3dc4', '#0c8599',
  '#94d82d', '#fa5252', '#6741d9', '#15aabf',
  '#f76707', '#d6336c', '#4263eb', '#74c0fc',
  '#69db7c', '#ffd43b', '#ffa8a8', '#b197fc',
  '#66d9e8', '#e9ecef', '#dee2e6', '#ced4da',
  '#adb5bd', '#868e96', '#495057', '#343a40',
  '#212529', '#000000',
]

export function getProjectColor(index: number): string {
  return GANTT_COLOR_PALETTE[index % GANTT_COLOR_PALETTE.length]
}

export function assignProjectColors(projectIds: string[]): Map<string, string> {
  const colorMap = new Map<string, string>()
  projectIds.forEach((id, i) => {
    colorMap.set(id, getProjectColor(i))
  })
  return colorMap
}

export function getTaskColor(
  projectId: string | null,
  projectColorMap: Map<string, string>,
  fallbackIndex: number = 0
): string {
  if (projectId && projectColorMap.has(projectId)) {
    return projectColorMap.get(projectId)!
  }
  return getProjectColor(fallbackIndex)
}

export function getStatusColor(status: string): string {
  const map: Record<string, string> = {
    todo: '#97a0af',
    doing: '#0066cc',
    blocked: '#de350b',
    done: '#00875a',
    canceled: '#6b7280',
    changes_requested: '#ff9900',
    approved: '#36b37e',
  }
  return map[status] || '#97a0af'
}

export function getPriorityColor(priority: string): string {
  const map: Record<string, string> = {
    low: '#97a0af',
    medium: '#ff9900',
    high: '#de350b',
    urgent: '#c92a2a',
  }
  return map[priority] || '#97a0af'
}
