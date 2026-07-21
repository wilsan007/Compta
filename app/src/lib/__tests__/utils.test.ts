import { describe, it, expect } from 'vitest'
import { evaluateExpression, formatCurrency, formatDate, formatNumber, cn } from '@/lib/utils'

describe('evaluateExpression (Phase 1.3 — Calculator)', () => {
  it('evaluates simple addition', () => {
    expect(evaluateExpression('=100+50')).toBe(150)
  })

  it('evaluates subtraction', () => {
    expect(evaluateExpression('=100-30')).toBe(70)
  })

  it('evaluates multiplication', () => {
    expect(evaluateExpression('=25*4')).toBe(100)
  })

  it('evaluates division', () => {
    expect(evaluateExpression('=100/4')).toBe(25)
  })

  it('evaluates complex expressions with parentheses', () => {
    expect(evaluateExpression('=(100+50)*2')).toBe(300)
  })

  it('evaluates percentage', () => {
    expect(evaluateExpression('=1000*20%')).toBe(200)
  })

  it('evaluates comma as decimal separator', () => {
    expect(evaluateExpression('=10,5+20,5')).toBe(31)
  })

  it('rounds to 2 decimal places', () => {
    expect(evaluateExpression('=100/3')).toBe(33.33)
  })

  it('returns null for non-expression (no = prefix)', () => {
    expect(evaluateExpression('100+50')).toBeNull()
  })

  it('returns null for empty expression', () => {
    expect(evaluateExpression('=')).toBeNull()
  })

  it('returns null for whitespace-only expression', () => {
    expect(evaluateExpression('=   ')).toBeNull()
  })

  it('rejects expressions with letters (injection prevention)', () => {
    expect(evaluateExpression('=alert(1)')).toBeNull()
  })

  it('rejects expressions with semicolons (injection prevention)', () => {
    expect(evaluateExpression('=1;2')).toBeNull()
  })

  it('rejects expressions with backticks', () => {
    expect(evaluateExpression('=`hello`')).toBeNull()
  })

  it('handles negative numbers', () => {
    expect(evaluateExpression('=-100+200')).toBe(100)
  })

  it('handles decimal results', () => {
    expect(evaluateExpression('=10.5*2')).toBe(21)
  })
})

describe('formatCurrency', () => {
  it('formats EUR in French locale', () => {
    const result = formatCurrency(1234.56, 'EUR')
    expect(result).toContain('1')
    expect(result).toContain('234')
    expect(result).toContain('56')
  })

  it('handles zero', () => {
    const result = formatCurrency(0, 'EUR')
    expect(result).toContain('0')
  })

  it('handles negative amounts', () => {
    const result = formatCurrency(-500, 'EUR')
    expect(result).toContain('500')
  })
})

describe('formatDate', () => {
  it('formats ISO date string', () => {
    const result = formatDate('2024-06-15')
    expect(result).toMatch(/15/)
    expect(result).toMatch(/06/)
    expect(result).toMatch(/2024/)
  })

  it('formats Date object', () => {
    const result = formatDate(new Date(2024, 5, 15))
    expect(result).toMatch(/2024/)
  })
})

describe('formatNumber', () => {
  it('formats large numbers with separators', () => {
    const result = formatNumber(1234567.89)
    expect(result).toContain('1')
    expect(result).toContain('234')
  })
})

describe('cn (className merge)', () => {
  it('merges class names', () => {
    expect(cn('foo', 'bar')).toBe('foo bar')
  })

  it('handles conditional classes', () => {
    expect(cn('base', false && 'hidden', 'visible')).toBe('base visible')
  })

  it('deduplicates tailwind classes', () => {
    expect(cn('p-2', 'p-4')).toBe('p-4')
  })
})
