import { describe, it, expect, vi, beforeEach } from 'vitest'

const { getEmployees, getTenantId } = vi.hoisted(() => ({
  getEmployees: vi.fn(),
  getTenantId: vi.fn(),
}))
vi.mock('@/lib/queries/payroll', () => ({ getEmployees }))
vi.mock('@/lib/queries/core', () => ({ getTenantId }))

import { getEmployeesShared, resetEmployeesSharedCache } from '@/lib/employeesShared'

// Un tableau de 60 lignes montait 60 sélecteurs de responsable, donc 60 lectures
// identiques de la liste des employés.
describe('getEmployeesShared', () => {
  beforeEach(() => {
    resetEmployeesSharedCache()
    getEmployees.mockReset()
    getTenantId.mockReset()
    getTenantId.mockResolvedValue('t1')
    getEmployees.mockResolvedValue([{ id: 'e1', name: 'Awa' }])
  })

  it('60 lignes qui montent en même temps ne font qu’une lecture', async () => {
    const lists = await Promise.all(Array.from({ length: 60 }, () => getEmployeesShared()))
    expect(getEmployees).toHaveBeenCalledTimes(1)
    expect(lists.every((l) => l[0].id === 'e1')).toBe(true)
  })

  it('une autre société ne reçoit jamais la liste de la précédente', async () => {
    await getEmployeesShared()
    getTenantId.mockResolvedValue('t2')
    getEmployees.mockResolvedValue([{ id: 'e2', name: 'Moussa' }])
    const other = await getEmployeesShared()
    expect(getEmployees).toHaveBeenCalledTimes(2)
    expect(other[0].id).toBe('e2')
  })

  it('force relit (employé créé depuis le sélecteur)', async () => {
    await getEmployeesShared()
    await getEmployeesShared({ force: true })
    expect(getEmployees).toHaveBeenCalledTimes(2)
  })

  it('un échec n’est pas gardé : la ligne suivante réessaie', async () => {
    getEmployees.mockRejectedValueOnce(new Error('réseau'))
    await expect(getEmployeesShared()).rejects.toThrow('réseau')
    await getEmployeesShared()
    expect(getEmployees).toHaveBeenCalledTimes(2)
  })

  it('le cache expire', async () => {
    vi.useFakeTimers()
    try {
      await getEmployeesShared()
      vi.setSystemTime(Date.now() + 31_000)
      await getEmployeesShared()
      expect(getEmployees).toHaveBeenCalledTimes(2)
    } finally {
      vi.useRealTimers()
    }
  })
})
