import { describe, it, expect } from 'vitest'
import {
  NO_PROJECT_FOLDER,
  buildPeopleByTask,
  buildTimeCostByTask,
  deadlineState,
  documentsOf,
  filterFolders,
  folderTrail,
  listFolders,
  summarizeFolder,
  type FolderDocument,
  type FolderSources,
} from '../projectFolders'
import type { ProjectTask } from '@/types/projectManagement'

const TODAY = '2026-10-30'

const task = (over: Partial<ProjectTask> & { id: string }): ProjectTask =>
  ({
    tenant_id: 't',
    project_id: 'P1',
    parent_id: null,
    title: over.id,
    description: null,
    status: 'todo',
    priority: 'medium',
    assignee: null,
    assignee_id: null,
    start_date: null,
    due_date: null,
    effort_estimate_h: 0,
    effort_spent_h: 0,
    progress: 0,
    display_order: '0',
    task_level: 0,
    budget: 0,
    color: 0,
    acceptance_criteria: null,
    recurring_task: false,
    recurring_interval: 1,
    recurring_rule_type: 'weekly',
    is_closed: false,
    linked_action_id: null,
    created_at: '2026-01-01',
    updated_at: '2026-01-01',
    ...over,
  }) as ProjectTask

const doc = (id: string, task_id: string, kind: FolderDocument['kind'] = 'document'): FolderDocument => ({
  id,
  task_id,
  file_name: `${id}.pdf`,
  file_path: `t/${id}`,
  file_size: 10,
  mime_type: 'application/pdf',
  created_at: '2026-10-01',
  kind,
})

function sources(over: Partial<FolderSources> = {}): FolderSources {
  return {
    projects: [
      {
        id: 'P1',
        name: 'Projet Un',
        color: '#112233',
        budget: 1000,
        actual_cost: 200,
        start_date: '2026-09-01',
        end_date: '2026-11-30',
        progress: 40,
        manager_id: 'E1',
        status: 'active',
      },
    ],
    tasks: [
      task({ id: 'A', start_date: '2026-09-01', due_date: '2026-10-10', budget: 300, progress: 100, status: 'done' }),
      task({ id: 'B', start_date: '2026-10-01', due_date: '2026-12-15', progress: 20 }),
      task({ id: 'B1', parent_id: 'B', budget: 100, due_date: '2026-11-15' }),
      task({ id: 'B2', parent_id: 'B', budget: 150, due_date: '2026-12-15' }),
    ],
    documents: [doc('d1', 'A'), doc('d2', 'B1'), doc('d3', 'B1', 'proof'), doc('d4', 'B2')],
    peopleByTask: new Map([
      ['A', ['Amina']],
      ['B1', ['Bob', 'amina']],
    ]),
    timeCostByTask: new Map([
      ['B1', 50],
      ['B2', 25],
    ]),
    managerByProject: new Map([['P1', 'Chef Projet']]),
    membersByProject: new Map([['P1', ['Dina']]]),
    noProjectLabel: 'Sans projet',
    ...over,
  }
}

describe('deadlineState', () => {
  it('distingue terminé, en retard, proche, dans les temps et sans échéance', () => {
    expect(deadlineState('2026-10-01', true, TODAY).state).toBe('done')
    expect(deadlineState(null, false, TODAY).state).toBe('none')
    expect(deadlineState('2026-10-25', false, TODAY)).toEqual({ state: 'late', daysLeft: -5 })
    expect(deadlineState('2026-11-02', false, TODAY)).toEqual({ state: 'soon', daysLeft: 3 })
    expect(deadlineState('2026-10-30', false, TODAY)).toEqual({ state: 'soon', daysLeft: 0 })
    expect(deadlineState('2026-12-01', false, TODAY).state).toBe('ontrack')
  })
})

describe('summarizeFolder — projet', () => {
  const s = summarizeFolder(sources(), { kind: 'project', id: 'P1' }, TODAY)!

  it('compte le contenu : sous-dossiers directs, tâches de tous niveaux, documents de tout le dossier', () => {
    expect(s.subfolders).toBe(2) // A et B
    expect(s.tasks).toBe(4)
    expect(s.documents).toBe(4)
  })

  it('met le responsable d\'abord, puis les membres, puis les affectés, sans doublon de casse', () => {
    expect(s.people).toEqual(['Chef Projet', 'Dina', 'Amina', 'Bob'])
  })

  it('chiffre le décaissement : coût imputé + temps passé, contre le budget du projet', () => {
    expect(s.budget).toBe(1000)
    expect(s.spentMaterial).toBe(200)
    expect(s.spentTime).toBe(75)
    expect(s.spent).toBe(275)
    expect(s.disbursementRate).toBe(28) // 27,5 arrondi
  })

  it('porte le délai et l\'avancement du projet', () => {
    expect(s.start).toBe('2026-09-01')
    expect(s.end).toBe('2026-11-30')
    expect(s.deadline).toBe('ontrack')
    expect(s.progress).toBe(40)
  })

  it('sans budget propre, le budget est la somme de ses tâches — sans double compte parent/enfants', () => {
    const src = sources()
    src.projects[0].budget = 0
    const r = summarizeFolder(src, { kind: 'project', id: 'P1' }, TODAY)!
    // A = 300 ; B n'a pas de budget → B1 100 + B2 150
    expect(r.budget).toBe(550)
  })

  it('un projet sans budget n\'a pas de taux de décaissement', () => {
    const src = sources({ tasks: [task({ id: 'X' })] })
    src.projects[0].budget = 0
    const r = summarizeFolder(src, { kind: 'project', id: 'P1' }, TODAY)!
    expect(r.budget).toBe(0)
    expect(r.disbursementRate).toBeNull()
  })

  it('un projet terminé est « terminé », pas « en retard »', () => {
    const src = sources()
    src.projects[0].end_date = '2026-10-01'
    src.projects[0].status = 'completed'
    expect(summarizeFolder(src, { kind: 'project', id: 'P1' }, TODAY)!.deadline).toBe('done')
  })
})

describe('summarizeFolder — tâche', () => {
  it('une tâche mère résume ses sous-tâches : budget, temps, documents, personnes', () => {
    const s = summarizeFolder(sources(), { kind: 'task', id: 'B' }, TODAY)!
    expect(s.subfolders).toBe(2)
    expect(s.tasks).toBe(2)
    expect(s.documents).toBe(3)
    expect(s.directDocuments).toBe(0)
    expect(s.budget).toBe(250) // B n'a pas de budget : B1 + B2
    expect(s.spent).toBe(75)
    expect(s.disbursementRate).toBe(30)
    expect(s.people).toEqual(['Bob', 'amina'])
  })

  it('le budget propre d\'une mère l\'emporte sur la somme de ses filles', () => {
    const src = sources()
    src.tasks = src.tasks.map((t) => (t.id === 'B' ? { ...t, budget: 400 } : t))
    expect(summarizeFolder(src, { kind: 'task', id: 'B' }, TODAY)!.budget).toBe(400)
  })

  it('une tâche terminée n\'est jamais en retard', () => {
    const s = summarizeFolder(sources(), { kind: 'task', id: 'A' }, TODAY)!
    expect(s.deadline).toBe('done')
    expect(s.directDocuments).toBe(1)
  })

  it('à défaut de dates propres, le délai vient des sous-tâches', () => {
    const src = sources({
      tasks: [
        task({ id: 'M' }),
        task({ id: 'M1', parent_id: 'M', start_date: '2026-10-05', due_date: '2026-10-20' }),
        task({ id: 'M2', parent_id: 'M', start_date: '2026-10-01', due_date: '2026-10-25' }),
      ],
      documents: [],
    })
    const s = summarizeFolder(src, { kind: 'task', id: 'M' }, TODAY)!
    expect(s.start).toBe('2026-10-01')
    expect(s.end).toBe('2026-10-25')
    expect(s.deadline).toBe('late')
    expect(s.daysLeft).toBe(-5)
  })

  it('un dossier inconnu ne produit rien', () => {
    expect(summarizeFolder(sources(), { kind: 'task', id: 'nope' }, TODAY)).toBeNull()
    expect(summarizeFolder(sources(), { kind: 'project', id: 'nope' }, TODAY)).toBeNull()
  })

  it('une boucle de parenté ne fige pas le calcul', () => {
    const src = sources({
      tasks: [task({ id: 'L1', parent_id: 'L2' }), task({ id: 'L2', parent_id: 'L1' })],
      documents: [],
    })
    expect(() => summarizeFolder(src, { kind: 'task', id: 'L1' }, TODAY)).not.toThrow()
  })
})

describe('listFolders', () => {
  it('à la racine : un dossier par projet', () => {
    const list = listFolders(sources(), null, TODAY)
    expect(list.map((f) => f.id)).toEqual(['P1'])
    expect(list[0].kind).toBe('project')
  })

  it('ouvrir un projet : ses tâches de premier niveau', () => {
    const list = listFolders(sources(), { kind: 'project', id: 'P1' }, TODAY)
    expect(list.map((f) => f.id).sort()).toEqual(['A', 'B'])
  })

  it('ouvrir une tâche : ses sous-tâches', () => {
    const list = listFolders(sources(), { kind: 'task', id: 'B' }, TODAY)
    expect(list.map((f) => f.id).sort()).toEqual(['B1', 'B2'])
  })

  it('les tâches sans projet forment un dossier « Sans projet »', () => {
    const src = sources({ tasks: [task({ id: 'O', project_id: null })], documents: [doc('o1', 'O')] })
    const list = listFolders(src, null, TODAY)
    const orphan = list.find((f) => f.id === NO_PROJECT_FOLDER)!
    expect(orphan.name).toBe('Sans projet')
    expect(orphan.documents).toBe(1)
    expect(listFolders(src, { kind: 'project', id: NO_PROJECT_FOLDER }, TODAY).map((f) => f.id)).toEqual(['O'])
  })

  it('pas de dossier « Sans projet » quand aucune tâche n\'est orpheline', () => {
    expect(listFolders(sources(), null, TODAY).some((f) => f.id === NO_PROJECT_FOLDER)).toBe(false)
  })

  it('une sous-tâche dont la mère est filtrée devient une racine', () => {
    const src = sources({ tasks: [task({ id: 'C1', parent_id: 'absente' })], documents: [] })
    expect(listFolders(src, { kind: 'project', id: 'P1' }, TODAY).map((f) => f.id)).toEqual(['C1'])
  })
})

describe('chemin, documents, recherche', () => {
  it('folderTrail remonte de la sous-tâche au projet', () => {
    expect(folderTrail(sources(), { kind: 'task', id: 'B1' })).toEqual([
      { kind: 'project', id: 'P1' },
      { kind: 'task', id: 'B' },
      { kind: 'task', id: 'B1' },
    ])
    expect(folderTrail(sources(), null)).toEqual([])
  })

  it('documentsOf ne rend que les documents posés sur la tâche, du plus récent au plus ancien', () => {
    const src = sources()
    src.documents = [
      { ...doc('old', 'B1'), created_at: '2026-01-01' },
      { ...doc('new', 'B1'), created_at: '2026-10-01' },
      doc('other', 'A'),
    ]
    expect(documentsOf(src, { kind: 'task', id: 'B1' }).map((d) => d.id)).toEqual(['new', 'old'])
    expect(documentsOf(src, { kind: 'project', id: 'P1' })).toEqual([])
  })

  it('filterFolders cherche dans le nom et dans les personnes, sans tenir compte de la casse', () => {
    const list = listFolders(sources(), { kind: 'project', id: 'P1' }, TODAY)
    expect(filterFolders(list, 'bob').map((f) => f.id)).toEqual(['B'])
    expect(filterFolders(list, '').length).toBe(2)
    expect(filterFolders(list, 'zzz')).toEqual([])
  })
})

describe('buildPeopleByTask / buildTimeCostByTask', () => {
  it('fusionne la table de liaison et le nom saisi, sans doublon', () => {
    const names = new Map([
      ['e1', 'Amina'],
      ['e2', 'Bob'],
    ])
    const m = buildPeopleByTask(
      [
        { id: 't1', assignee: 'amina' },
        { id: 't2', assignee: 'Carl' },
        { id: 't3', assignee: null },
      ],
      [
        { task_id: 't1', employee_id: 'e1' },
        { task_id: 't1', employee_id: 'e2' },
        { task_id: 't3', employee_id: 'inconnu' },
      ],
      names
    )
    expect(m.get('t1')).toEqual(['Amina', 'Bob'])
    expect(m.get('t2')).toEqual(['Carl'])
    expect(m.has('t3')).toBe(false)
  })

  it('valorise le temps : heures × taux, par tâche, en ignorant les temps sans tâche ou sans taux', () => {
    const m = buildTimeCostByTask([
      { task_id: 'a', duration_seconds: 7200, hourly_rate: 25 },
      { task_id: 'a', duration_seconds: 1800, hourly_rate: 40 },
      { task_id: null, duration_seconds: 3600, hourly_rate: 100 },
      { task_id: 'b', duration_seconds: 3600, hourly_rate: 0 },
    ])
    expect(m.get('a')).toBe(70)
    expect(m.has('b')).toBe(false)
    expect(m.size).toBe(1)
  })
})
