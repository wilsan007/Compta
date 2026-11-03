import { describe, it, expect } from 'vitest'
import {
  computeResourceUsage,
  hoursInPeriod,
  presetRange,
  usageStatus,
  type ResourceEmployee,
  type ResourceTask,
  type ResourceUsageInput,
} from '../resourceUsage'

// Octobre 2026 : le 1er est un jeudi → 22 jours ouvrés (du 1er au 31).
const FROM = '2026-10-01'
const TO = '2026-10-31'

const emp = (id: string, name: string, weekly: number | null = 35): ResourceEmployee => ({
  id,
  name,
  position: null,
  department: null,
  weekly_hours: weekly,
})

const task = (over: Partial<ResourceTask> & { id: string }): ResourceTask => ({
  project_id: 'P1',
  parent_id: null,
  title: over.id,
  status: 'doing',
  start_date: null,
  due_date: null,
  effort_estimate_h: 0,
  assignee: null,
  ...over,
})

function input(over: Partial<ResourceUsageInput> = {}): ResourceUsageInput {
  return {
    from: FROM,
    to: TO,
    today: '2026-10-15',
    employees: [emp('E1', 'Amina'), emp('E2', 'Bob')],
    tasks: [],
    assignments: [],
    timeEntries: [],
    absenceDays: [],
    projectNames: new Map([
      ['P1', 'Projet Un'],
      ['P2', 'Projet Deux'],
    ]),
    noProjectLabel: 'Sans projet',
    ...over,
  }
}

describe('hoursInPeriod', () => {
  it('une tâche entièrement dans la période compte pour toutes ses heures', () => {
    expect(hoursInPeriod(40, '2026-10-05', '2026-10-09', FROM, TO)).toBeCloseTo(40)
  })

  it('une tâche à cheval ne compte que la part qui tombe dans la période', () => {
    // du lun. 26/10 au ven. 6/11 : 10 jours ouvrés, dont 5 en octobre (26→30)
    expect(hoursInPeriod(100, '2026-10-26', '2026-11-06', FROM, TO)).toBeCloseTo(50)
  })

  it('hors période : zéro', () => {
    expect(hoursInPeriod(40, '2026-11-02', '2026-11-06', FROM, TO)).toBe(0)
    expect(hoursInPeriod(40, '2026-09-01', '2026-09-30', FROM, TO)).toBe(0)
  })

  it('une étendue qui ne couvre qu\'un week-end s\'étale sur les jours calendaires', () => {
    // samedi 3 et dimanche 4 octobre
    expect(hoursInPeriod(8, '2026-10-03', '2026-10-04', FROM, TO)).toBeCloseTo(8)
  })

  it('pas d\'heures, pas de charge', () => {
    expect(hoursInPeriod(0, '2026-10-05', '2026-10-09', FROM, TO)).toBe(0)
  })
})

describe('computeResourceUsage', () => {
  it('capacité = jours ouvrés × heures hebdomadaires ÷ 5', () => {
    const r = computeResourceUsage(
      input({ tasks: [task({ id: 'T', start_date: '2026-10-05', due_date: '2026-10-09' })], assignments: [{ task_id: 'T', employee_id: 'E1' }] })
    )
    expect(r.rows[0].capacityHours).toBe(154) // 22 j × 7 h
  })

  it('taux d\'utilisation = heures planifiées ÷ capacité', () => {
    const r = computeResourceUsage(
      input({
        tasks: [task({ id: 'T', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 77 })],
        assignments: [{ task_id: 'T', employee_id: 'E1' }],
      })
    )
    const row = r.rows[0]
    expect(row.plannedHours).toBe(77)
    expect(row.plannedRate).toBe(50)
    expect(row.status).toBe('balanced')
  })

  it('compte tâches, tâches ouvertes, projets distincts et retards', () => {
    const r = computeResourceUsage(
      input({
        tasks: [
          task({ id: 'T1', project_id: 'P1', start_date: '2026-10-01', due_date: '2026-10-10', effort_estimate_h: 10 }),
          task({ id: 'T2', project_id: 'P2', start_date: '2026-10-12', due_date: '2026-10-14', effort_estimate_h: 5, status: 'done' }),
          task({ id: 'T3', project_id: 'P2', start_date: '2026-10-20', due_date: '2026-10-28', effort_estimate_h: 5 }),
        ],
        assignments: ['T1', 'T2', 'T3'].map((task_id) => ({ task_id, employee_id: 'E1' })),
      })
    )
    const row = r.rows[0]
    expect(row.tasks).toBe(3)
    expect(row.openTasks).toBe(2)
    expect(row.overdueTasks).toBe(1) // T1 : échue le 10, aujourd'hui le 15, non terminée
    expect(row.projects).toBe(2)
    expect(row.byProject.map((l) => [l.name, l.tasks, l.plannedHours])).toEqual([
      ['Projet Un', 1, 10],
      ['Projet Deux', 2, 10],
    ])
  })

  it('surcharge au-dessus de 100 %, sous-utilisation en dessous de 50 %', () => {
    const r = computeResourceUsage(
      input({
        tasks: [
          task({ id: 'BIG', start_date: '2026-10-01', due_date: '2026-10-31', effort_estimate_h: 200 }),
          task({ id: 'SMALL', start_date: '2026-10-01', due_date: '2026-10-31', effort_estimate_h: 20 }),
        ],
        assignments: [
          { task_id: 'BIG', employee_id: 'E1' },
          { task_id: 'SMALL', employee_id: 'E2' },
        ],
      })
    )
    const byName = Object.fromEntries(r.rows.map((x) => [x.name, x]))
    expect(byName.Amina.status).toBe('overloaded')
    expect(byName.Amina.plannedRate).toBe(130)
    expect(byName.Bob.status).toBe('underloaded')
    expect(r.totals.overloaded).toBe(1)
    expect(r.totals.underloaded).toBe(1)
    expect(r.rows[0].name).toBe('Amina') // la plus chargée d'abord
  })

  it('une tâche à deux responsables partage ses heures', () => {
    const r = computeResourceUsage(
      input({
        tasks: [task({ id: 'T', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 30 })],
        assignments: [
          { task_id: 'T', employee_id: 'E1' },
          { task_id: 'T', employee_id: 'E2' },
        ],
      })
    )
    expect(r.rows.map((x) => x.plannedHours)).toEqual([15, 15])
  })

  it('une mère ne compte pas ce que ses sous-tâches estiment déjà', () => {
    const r = computeResourceUsage(
      input({
        tasks: [
          task({ id: 'M', start_date: '2026-10-05', due_date: '2026-10-30', effort_estimate_h: 40 }),
          task({ id: 'M1', parent_id: 'M', start_date: '2026-10-05', due_date: '2026-10-30', effort_estimate_h: 25 }),
          task({ id: 'M2', parent_id: 'M', start_date: '2026-10-05', due_date: '2026-10-30', effort_estimate_h: 15 }),
        ],
        assignments: ['M', 'M1', 'M2'].map((task_id) => ({ task_id, employee_id: 'E1' })),
      })
    )
    expect(r.rows[0].plannedHours).toBe(40) // 0 (mère) + 25 + 15
  })

  it('les absences réduisent la capacité (week-ends ignorés)', () => {
    const r = computeResourceUsage(
      input({
        tasks: [task({ id: 'T', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 10 })],
        assignments: [{ task_id: 'T', employee_id: 'E1' }],
        absenceDays: [
          { employee_id: 'E1', day: '2026-10-12' },
          { employee_id: 'E1', day: '2026-10-13' },
          { employee_id: 'E1', day: '2026-10-17' }, // samedi : sans effet
          { employee_id: 'E2', day: '2026-10-12' }, // une autre personne
        ],
      })
    )
    expect(r.rows[0].absenceDays).toBe(2)
    expect(r.rows[0].capacityHours).toBe(140) // 20 j × 7 h
  })

  it('le temps saisi est compté dans la période seulement, et par projet', () => {
    const r = computeResourceUsage(
      input({
        tasks: [task({ id: 'T', project_id: 'P1', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 10 })],
        assignments: [{ task_id: 'T', employee_id: 'E1' }],
        timeEntries: [
          { employee_id: 'E1', task_id: 'T', project_id: 'P1', start_time: '2026-10-06T08:00:00Z', duration_seconds: 7200 },
          { employee_id: 'E1', task_id: 'T', project_id: null, start_time: '2026-10-07T08:00:00Z', duration_seconds: 3600 },
          { employee_id: 'E1', task_id: 'T', project_id: 'P1', start_time: '2026-09-30T08:00:00Z', duration_seconds: 36000 },
          { employee_id: null, task_id: 'T', project_id: 'P1', start_time: '2026-10-06T08:00:00Z', duration_seconds: 36000 },
        ],
      })
    )
    const row = r.rows[0]
    expect(row.loggedHours).toBe(3)
    expect(row.byProject.find((l) => l.projectId === 'P1')?.loggedHours).toBe(3) // le temps sans projet suit sa tâche
    expect(row.loggedRate).toBe(2) // 3 / 154
  })

  it('le filtre projet ne garde que ce projet, la capacité restant entière', () => {
    const r = computeResourceUsage(
      input({
        projectId: 'P2',
        tasks: [
          task({ id: 'A', project_id: 'P1', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 30 }),
          task({ id: 'B', project_id: 'P2', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 14 }),
        ],
        assignments: [
          { task_id: 'A', employee_id: 'E1' },
          { task_id: 'B', employee_id: 'E1' },
        ],
      })
    )
    expect(r.rows[0].plannedHours).toBe(14)
    expect(r.rows[0].capacityHours).toBe(154)
    expect(r.rows[0].projects).toBe(1)
  })

  it('tâches sans responsable, sans date, annulées et hors période', () => {
    const r = computeResourceUsage(
      input({
        tasks: [
          task({ id: 'NOBODY', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 10 }),
          task({ id: 'UNDATED', effort_estimate_h: 10 }),
          task({ id: 'CANCELED', status: 'canceled', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 10 }),
          task({ id: 'LATER', start_date: '2026-12-01', due_date: '2026-12-05', effort_estimate_h: 10 }),
          task({ id: 'NOEST', start_date: '2026-10-05', due_date: '2026-10-09' }),
        ],
        assignments: ['UNDATED', 'CANCELED', 'LATER', 'NOEST'].map((task_id) => ({ task_id, employee_id: 'E1' })),
      })
    )
    expect(r.unassignedTasks).toBe(1)
    const row = r.rows[0]
    expect(row.tasks).toBe(1) // NOEST seulement
    expect(row.unscheduledTasks).toBe(1)
    expect(row.unestimatedTasks).toBe(1)
    expect(row.plannedHours).toBe(0)
  })

  it('à défaut de liaison, le nom saisi sur la tâche retrouve le salarié ; sinon une ligne « non référencée »', () => {
    const r = computeResourceUsage(
      input({
        tasks: [
          task({ id: 'T1', assignee: '  AMINA ', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 7 }),
          task({ id: 'T2', assignee: 'Inconnu', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 7 }),
        ],
      })
    )
    const linked = r.rows.find((x) => x.name === 'Amina')!
    const stranger = r.rows.find((x) => x.name === 'Inconnu')!
    expect(linked.employeeId).toBe('E1')
    expect(linked.unlinked).toBe(false)
    expect(stranger.unlinked).toBe(true)
    expect(stranger.weeklyHours).toBe(35)
  })

  it('un salarié sans heures hebdomadaires prend le défaut de 35 h', () => {
    const r = computeResourceUsage(
      input({
        employees: [emp('E1', 'Amina', null)],
        tasks: [task({ id: 'T', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 7 })],
        assignments: [{ task_id: 'T', employee_id: 'E1' }],
      })
    )
    expect(r.rows[0].weeklyHours).toBe(35)
  })

  it('une personne absente toute la période n\'a pas de taux (capacité nulle)', () => {
    const days = Array.from({ length: 31 }, (_, i) => ({
      employee_id: 'E1',
      day: `2026-10-${String(i + 1).padStart(2, '0')}`,
    }))
    const r = computeResourceUsage(
      input({
        tasks: [task({ id: 'T', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 7 })],
        assignments: [{ task_id: 'T', employee_id: 'E1' }],
        absenceDays: days,
      })
    )
    expect(r.rows[0].capacityHours).toBe(0)
    expect(r.rows[0].plannedRate).toBeNull()
    expect(r.rows[0].status).toBe('unknown')
  })

  it('les totaux agrègent la capacité et la charge de tout le monde', () => {
    const r = computeResourceUsage(
      input({
        tasks: [
          task({ id: 'A', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 77 }),
          task({ id: 'B', start_date: '2026-10-05', due_date: '2026-10-09', effort_estimate_h: 77 }),
        ],
        assignments: [
          { task_id: 'A', employee_id: 'E1' },
          { task_id: 'B', employee_id: 'E2' },
        ],
      })
    )
    expect(r.totals.people).toBe(2)
    expect(r.totals.capacityHours).toBe(308)
    expect(r.totals.plannedHours).toBe(154)
    expect(r.totals.plannedRate).toBe(50)
  })
})

describe('usageStatus / presetRange', () => {
  it('seuils', () => {
    expect(usageStatus(null)).toBe('unknown')
    expect(usageStatus(101)).toBe('overloaded')
    expect(usageStatus(100)).toBe('balanced')
    expect(usageStatus(50)).toBe('balanced')
    expect(usageStatus(49)).toBe('underloaded')
  })

  it('périodes proposées', () => {
    const now = new Date(2026, 9, 30) // vendredi 30 octobre 2026
    expect(presetRange('thisMonth', now)).toEqual({ from: '2026-10-01', to: '2026-10-31' })
    expect(presetRange('lastMonth', now)).toEqual({ from: '2026-09-01', to: '2026-09-30' })
    expect(presetRange('thisQuarter', now)).toEqual({ from: '2026-10-01', to: '2026-12-31' })
    expect(presetRange('thisYear', now)).toEqual({ from: '2026-01-01', to: '2026-12-31' })
    expect(presetRange('thisWeek', now)).toEqual({ from: '2026-10-26', to: '2026-11-01' })
  })
})
