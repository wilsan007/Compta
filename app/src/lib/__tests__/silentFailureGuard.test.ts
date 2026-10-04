import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { silentFailureReporter, trackPromise } from '@/lib/silentFailureGuard'

describe('silentFailureGuard', () => {
  beforeEach(() => {
    // Force-enable the reporter for tests
    ;(silentFailureReporter as any).enabled = true
    silentFailureReporter.clear()
  })

  afterEach(() => {
    ;(silentFailureReporter as any).enabled = false
  })

  describe('SilentFailureReporter', () => {
    it('collects reported events', () => {
      silentFailureReporter.report({
        type: 'TEST',
        severity: 'error',
        message: 'test error',
      })
      const events = silentFailureReporter.getEvents()
      expect(events).toHaveLength(1)
      expect(events[0].type).toBe('TEST')
      expect(events[0].severity).toBe('error')
    })

    it('aggregates counts by type:severity', () => {
      silentFailureReporter.report({ type: 'A', severity: 'error', message: 'a1' })
      silentFailureReporter.report({ type: 'A', severity: 'error', message: 'a2' })
      silentFailureReporter.report({ type: 'B', severity: 'warning', message: 'b1' })
      const counts = silentFailureReporter.getCounts()
      expect(counts['A:error']).toBe(2)
      expect(counts['B:warning']).toBe(1)
    })

    it('does not collect when disabled', () => {
      ;(silentFailureReporter as any).enabled = false
      silentFailureReporter.report({ type: 'X', severity: 'error', message: 'x' })
      expect(silentFailureReporter.getEvents()).toHaveLength(0)
    })

    it('caps stored events at maxEvents', () => {
      for (let i = 0; i < 550; i++) {
        silentFailureReporter.report({ type: 'FLOOD', severity: 'info', message: `m${i}` })
      }
      expect(silentFailureReporter.getEvents().length).toBeLessThanOrEqual(500)
    })

    it('dumps events as JSON', () => {
      silentFailureReporter.report({ type: 'DUMP', severity: 'warning', message: 'd' })
      const json = silentFailureReporter.dump()
      expect(JSON.parse(json)).toBeInstanceOf(Array)
    })
  })

  describe('trackPromise', () => {
    it('passes through resolved value', async () => {
      const result = await trackPromise(Promise.resolve(42), 'test-resolve')
      expect(result).toBe(42)
    })

    it('reports on rejection and re-throws', async () => {
      const p = trackPromise(Promise.reject(new Error('boom')), 'test-reject')
      await expect(p).rejects.toThrow('boom')
      const events = silentFailureReporter.getEvents()
      expect(events.some((e) => e.type === 'PROMISE_REJECTED')).toBe(true)
    })

    it('reports floating promise via microtask', async () => {
      // Create a promise but don't await it
      trackPromise(new Promise(() => {}), 'test-floating')
      // Wait for microtasks to flush
      await new Promise((r) => setTimeout(r, 10))
      const events = silentFailureReporter.getEvents()
      expect(events.some((e) => e.type === 'FLOATING_PROMISE')).toBe(true)
    })
  })
})
