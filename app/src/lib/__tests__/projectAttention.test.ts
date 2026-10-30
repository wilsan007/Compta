import { describe, it, expect } from 'vitest'
import { computeAttention } from '../projectAttention'
import type { FolderSources } from '../projectFolders'
import type { ResourceUsageResult } from '../resourceUsage'
import type { ProjectTask } from '@/types/projectManagement'

const TODAY = '2026-10-30'

const task = (over: Partial<ProjectTask> & { id: string }): ProjectTask =>
  ({
    tenant_id: 't',
    project_id: 'P1',
    parent_id: null,
    title: over.id,
    status: 'todo',
    assignee: null,
    start_date: null,
    due_date: null,
    effort_estimate_h: 0,
    progress: 0,
    budget: 0,
    ...over,
  }) as ProjectTask

function sources(over: Partial<FolderSources> = {}, project: Partial<FolderSources['projects'][number]> = {}): FolderSources {
  return {
    projects: [
      {
        id: 'P1',
        name: 'Projet Un',
        color: null,
        budget: 1000,
        actual_cost: 0,
        start_date: '2026-09-01',
        end_date: '2026-12-31',
        progress: 50,
        manager_id: null,
        status: 'active',
        ...project,
      },
    ],
    tasks: [],
    documents: [],
    peopleByTask: new Map(),
    timeCostByTask: new Map(),
    managerByProject: new Map(),
    membersByProject: new Map(),
    noProjectLabel: 'Sans projet',
    ...over,
  }
}

const kinds = (r: ReturnType<typeof computeAttention>) => r.items.map((i) => i.kind)

describe('computeAttention', () => {
  it('un projet sans souci est vert, sans point d\'attention', () => {
    const r = computeAttention({ sources: sources(), usage: null, today: TODAY })
    expect(r.items).toEqual([])
    expect(r.projects[0].health).toBe('green')
    expect(r.counts).toEqual({ red: 0, amber: 0, green: 1, items: 0, high: 0 })
  })

  it('un projet en retard est rouge', () => {
    const r = computeAttention({ sources: sources({}, { end_date: '2026-10-20' }), usage: null, today: TODAY })
    expect(kinds(r)).toEqual(['projectLate'])
    expect(r.items[0]).toMatchObject({ severity: 'high', days: 10 })
    expect(r.projects[0].health).toBe('red')
  })

  it('un projet terminé ou annulé n\'est pas suivi', () => {
    for (const status of ['completed', 'cancelled']) {
      const r = computeAttention({ sources: sources({}, { end_date: '2026-01-01', status }), usage: null, today: TODAY })
      expect(r.projects).toEqual([])
      expect(r.items).toEqual([])
    }
  })

  it('budget dépassé : rouge ; décaissement en avance sur l\'avancement : orange ; sinon rien', () => {
    const over = computeAttention({ sources: sources({}, { actual_cost: 1200 }), usage: null, today: TODAY })
    expect(kinds(over)).toEqual(['overBudget'])
    expect(over.projects[0].health).toBe('red')

    const burn = computeAttention({ sources: sources({}, { actual_cost: 800, progress: 40 }), usage: null, today: TODAY })
    expect(kinds(burn)).toEqual(['burnAhead'])
    expect(burn.items[0]).toMatchObject({ severity: 'medium', rate: 80, progress: 40 })
    expect(burn.projects[0].health).toBe('amber')

    // 60 % décaissé pour 40 % d'avancement : écart de 20 points, sous le seuil
    const fine = computeAttention({ sources: sources({}, { actual_cost: 600, progress: 40 }), usage: null, today: TODAY })
    expect(fine.items).toEqual([])
    // peu décaissé : un écart sur un petit taux ne dit rien
    const early = computeAttention({ sources: sources({}, { actual_cost: 250, progress: 0 }), usage: null, today: TODAY })
    expect(early.items).toEqual([])
  })

  it('sans budget, aucun signal de décaissement', () => {
    const r = computeAttention({ sources: sources({}, { budget: 0, actual_cost: 5000 }), usage: null, today: TODAY })
    expect(r.items).toEqual([])
  })

  it('une tâche en retard : orange, rouge au-delà de 14 jours ; une tâche terminée ne compte pas', () => {
    const r = computeAttention({
      sources: sources({
        tasks: [
          task({ id: 'A', due_date: '2026-10-25' }), // 5 j
          task({ id: 'B', due_date: '2026-10-10' }), // 20 j
          task({ id: 'C', due_date: '2026-10-01', status: 'done' }),
          task({ id: 'D', due_date: '2026-10-01', status: 'canceled' }),
          task({ id: 'E', due_date: '2026-11-05' }),
        ],
        peopleByTask: new Map(['A', 'B', 'E'].map((id) => [id, ['x']])),
      }),
      usage: null,
      today: TODAY,
    })
    expect(r.items.map((i) => [i.taskId, i.severity, i.days])).toEqual([
      ['B', 'high', 20],
      ['A', 'medium', 5],
    ])
    expect(r.projects[0].health).toBe('red')
  })

  it('une mère en retard n\'est pas répétée quand une de ses sous-tâches en retard porte déjà le signal', () => {
    const r = computeAttention({
      sources: sources({
        tasks: [
          task({ id: 'M', due_date: '2026-10-20' }),
          task({ id: 'M1', parent_id: 'M', due_date: '2026-10-15' }),
          task({ id: 'M2', parent_id: 'M', due_date: '2026-10-10', status: 'done' }),
        ],
        peopleByTask: new Map([['M1', ['x']]]),
      }),
      usage: null,
      today: TODAY,
    })
    expect(r.items.map((i) => i.taskId)).toEqual(['M1'])
  })

  it('bloquée ou en attente de corrections : à traiter', () => {
    const r = computeAttention({
      sources: sources({
        tasks: [task({ id: 'A', status: 'blocked' }), task({ id: 'B', status: 'changes_requested' })],
        peopleByTask: new Map([['A', ['x']], ['B', ['x']]]),
      }),
      usage: null,
      today: TODAY,
    })
    expect(kinds(r)).toEqual(['blocked', 'blocked'])
  })

  it('une feuille sans responsable qui démarre ou s\'achève sous 14 jours est signalée, pas une tâche lointaine ni une mère', () => {
    const r = computeAttention({
      sources: sources({
        tasks: [
          task({ id: 'NEAR', start_date: '2026-11-05', due_date: '2026-11-20' }),
          task({ id: 'FAR', start_date: '2027-02-01', due_date: '2027-02-20' }),
          task({ id: 'OWNED', start_date: '2026-11-05' }),
          task({ id: 'PARENT', start_date: '2026-11-05' }),
          task({ id: 'KID', parent_id: 'PARENT', start_date: '2026-11-05' }),
        ],
        peopleByTask: new Map([['OWNED', ['x']]]),
      }),
      usage: null,
      today: TODAY,
    })
    expect(r.items.filter((i) => i.kind === 'unassigned').map((i) => i.taskId).sort()).toEqual(['KID', 'NEAR'])
  })

  it('une personne surchargée est rattachée à chaque projet qu\'elle porte', () => {
    const usage = {
      rows: [
        {
          key: 'E1',
          name: 'Karim',
          status: 'overloaded',
          plannedRate: 130,
          byProject: [
            { projectId: 'P1', name: 'Projet Un', tasks: 2, plannedHours: 10, loggedHours: 0 },
            { projectId: null, name: 'Sans projet', tasks: 1, plannedHours: 1, loggedHours: 0 },
            { projectId: 'Pinconnu', name: 'x', tasks: 1, plannedHours: 1, loggedHours: 0 },
          ],
        },
        { key: 'E2', name: 'Bob', status: 'balanced', plannedRate: 80, byProject: [] },
      ],
    } as unknown as ResourceUsageResult
    const r = computeAttention({ sources: sources(), usage, today: TODAY })
    expect(r.items).toHaveLength(1)
    expect(r.items[0]).toMatchObject({ kind: 'overloaded', person: 'Karim', rate: 130, projectId: 'P1', projectName: 'Projet Un' })
    expect(r.projects[0].health).toBe('amber')
  })

  it('l\'ordre : urgents d\'abord, puis le plus en retard ; les projets : rouge, orange, vert', () => {
    const s = sources({
      projects: [
        { id: 'G', name: 'Vert', color: null, budget: 0, actual_cost: 0, start_date: null, end_date: '2027-01-01', progress: 0, manager_id: null, status: 'active' },
        { id: 'A', name: 'Orange', color: null, budget: 0, actual_cost: 0, start_date: null, end_date: '2027-01-01', progress: 0, manager_id: null, status: 'active' },
        { id: 'R', name: 'Rouge', color: null, budget: 0, actual_cost: 0, start_date: null, end_date: '2026-10-01', progress: 0, manager_id: null, status: 'active' },
      ],
      tasks: [task({ id: 'T', project_id: 'A', status: 'blocked' })],
      peopleByTask: new Map([['T', ['x']]]),
    })
    const r = computeAttention({ sources: s, usage: null, today: TODAY })
    expect(r.projects.map((p) => [p.name, p.health])).toEqual([
      ['Rouge', 'red'],
      ['Orange', 'amber'],
      ['Vert', 'green'],
    ])
    expect(r.items[0].severity).toBe('high')
  })

  it('les tâches sans projet sont signalées sous « Sans projet » mais n\'ont pas de feu', () => {
    const r = computeAttention({
      sources: sources({
        tasks: [task({ id: 'O', project_id: null, due_date: '2026-10-20' })],
        peopleByTask: new Map([['O', ['x']]]),
      }),
      usage: null,
      today: TODAY,
    })
    expect(r.items[0]).toMatchObject({ kind: 'taskLate', projectName: 'Sans projet', projectId: null })
    expect(r.projects).toHaveLength(1)
  })
})
