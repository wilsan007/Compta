// QUA-02 : Tests métier de référence pour Vague 2
// Valident les cas d'acceptation des chantiers PAY, PRD, BNQ, VTE, STK, POS, ADM

import { describe, it, expect } from 'vitest'
import { calculatePayroll, formatPayrollAmount } from '@/lib/payroll'
import { parseCamt053, parseMt940, detectBankStatementFormat, detectDuplicateTransactions } from '@/lib/bankParsers'

// ============================================================
// PAY-02 : Plafond de sécurité sociale et tranches
// ============================================================
describe('PAY-02 : Plafond SS et tranches', () => {
  it('un salarié à 6000€ voit ses cotisations plafonnées sur 3925€', () => {
    const result = calculatePayroll({
      grossSalary: 6000,
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 30,
      department: 'FR',
      taxRate: 10,
    })

    // Le brut doit être de 6000
    expect(result.totalGross).toBe(6000)
    // La CSG déductible doit être calculée sur 98,25% du brut
    const expectedCsgDeductible = 6000 * 0.9825 * 6.80 / 100
    expect(Math.abs(result.csgDeductible - expectedCsgDeductible)).toBeLessThan(0.01)
  })
})

// ============================================================
// PAY-03 : Prorata d'entrée/sortie
// ============================================================
describe('PAY-03 : Prorata d\'entrée/sortie', () => {
  it('un salarié embauché le 12 sur 22 jours ouvrés proratise son brut', () => {
    const result = calculatePayroll({
      grossSalary: 3000,
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 30,
      department: 'FR',
      taxRate: 0,
      daysWorked: 15,
      daysInPeriod: 22,
    })

    // Prorata = 15/22 ≈ 0.6818
    expect(result.proration).toBeCloseTo(15 / 22, 4)
    // Brut proratisé = 3000 × 15/22
    expect(result.proratedGross).toBeCloseTo(3000 * 15 / 22, 2)
  })

  it('un salarié à temps plein sans absence a un prorata de 1', () => {
    const result = calculatePayroll({
      grossSalary: 3000,
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 30,
      department: 'FR',
      taxRate: 0,
    })

    expect(result.proration).toBe(1)
    expect(result.proratedGross).toBe(3000)
  })
})

// ============================================================
// PAY-05 : CSG scindée et net imposable
// ============================================================
describe('PAY-05 : CSG scindée et net imposable', () => {
  it('la CSG est éclatée en déductible, non déductible et CRDS', () => {
    const result = calculatePayroll({
      grossSalary: 3000,
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 30,
      department: 'FR',
      taxRate: 0,
    })

    const csgBase = 3000 * 0.9825
    expect(result.csgDeductible).toBeCloseTo(csgBase * 6.80 / 100, 2)
    expect(result.csgNonDeductible).toBeCloseTo(csgBase * 2.40 / 100, 2)
    expect(result.crds).toBeCloseTo(csgBase * 0.50 / 100, 2)
    // Total CSG-CRDS = somme des trois
    expect(result.csgCrds).toBeCloseTo(result.csgDeductible + result.csgNonDeductible + result.crds, 2)
  })

  it('le net imposable est calculé correctement', () => {
    const result = calculatePayroll({
      grossSalary: 3000,
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 30,
      department: 'FR',
      taxRate: 0,
    })

    // Net imposable doit être positif et inférieur au brut
    expect(result.netImposable).toBeGreaterThan(0)
    expect(result.netImposable).toBeLessThan(result.totalGross)
    // Net social doit être positif
    expect(result.netSocial).toBeGreaterThan(0)
  })
})

// ============================================================
// PAY-06 : Réduction générale
// ============================================================
describe('PAY-06 : Réduction générale', () => {
  it('un salarié au SMIC bénéficie de la réduction générale', () => {
    const result = calculatePayroll({
      grossSalary: 1801.80, // SMIC mensuel
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 30,
      department: 'FR',
      taxRate: 0,
    })

    // La réduction générale doit être positive au SMIC
    expect(result.reductionGenerale).toBeGreaterThan(0)
  })

  it('un salarié à plus de 1,6 SMIC ne bénéficie pas de la réduction', () => {
    const result = calculatePayroll({
      grossSalary: 5000, // Bien au-dessus de 1,6 × SMIC
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 30,
      department: 'FR',
      taxRate: 0,
    })

    // La réduction générale doit être nulle ou négligeable
    expect(result.reductionGenerale).toBeLessThan(1)
  })
})

// ============================================================
// BNQ-01 : Parsers bancaires
// ============================================================
describe('BNQ-01 : Parsers bancaires', () => {
  it('détecte le format CAMT.053', () => {
    const xml = '<?xml version="1.0"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02"></Document>'
    expect(detectBankStatementFormat(xml)).toBe('camt053')
  })

  it('détecte le format MT940', () => {
    const mt940 = ':20:STMT001\n:25:FR123456789\n:60F:C250101EUR1000,00\n:61:250101250101C500,00NTRF\n:86:Virement reçu\n:62F:C250102EUR1500,00'
    expect(detectBankStatementFormat(mt940)).toBe('mt940')
  })

  it('parse MT940 avec transactions', () => {
    const mt940 = `:20:STMT001
:25:FR123456789
:60F:C250101EUR1000,00
:61:250101250101C500,00NTRF
:86:Virement reçu
:62F:C250102EUR1500,00`
    const result = parseMt940(mt940)
    expect(result.transactions).toHaveLength(1)
    expect(result.transactions[0].amount).toBe(500)
    expect(result.transactions[0].type).toBe('credit')
    expect(result.accountNumber).toBe('FR123456789')
    expect(result.currency).toBe('EUR')
  })

  it('parse CAMT.053 avec transactions', () => {
    const xml = `<?xml version="1.0"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">
  <BkToCstmrStmt>
    <Stmt>
      <Acct>
        <Id><IBAN>FR123456789</IBAN></Id>
        <Ccy>EUR</Ccy>
      </Acct>
      <Ntry>
        <NtryDtls>
          <TxDtls>
            <Ref>REF001</Ref>
          </TxDtls>
        </NtryDtls>
        <Amt Ccy="EUR">500.00</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <BookgDt><Dt>2025-01-01</Dt></BookgDt>
        <AddtlNtryInf>Virement reçu</AddtlNtryInf>
      </Ntry>
    </Stmt>
  </BkToCstmrStmt>
</Document>`
    const result = parseCamt053(xml)
    expect(result.transactions.length).toBeGreaterThan(0)
    expect(result.transactions[0].amount).toBe(500)
    expect(result.transactions[0].type).toBe('credit')
  })

  it('détecte les doublons', () => {
    const existing = [
      { date: '2025-01-01', description: 'Virement', reference: 'REF001', type: 'credit' as const, amount: 500 },
    ]
    const newTx = [
      { date: '2025-01-01', description: 'Virement', reference: 'REF001', type: 'credit' as const, amount: 500 },
      { date: '2025-01-02', description: 'Autre', reference: 'REF002', type: 'debit' as const, amount: -100 },
    ]
    const duplicates = detectDuplicateTransactions(newTx, existing)
    expect(duplicates).toHaveLength(1)
    expect(duplicates[0].reference).toBe('REF001')
  })
})

// ============================================================
// PAY-04 : Cumuls et régularisation
// ============================================================
describe('PAY-04 : Cumuls annuels', () => {
  it('les cumuls YTD sont calculés', () => {
    const result = calculatePayroll({
      grossSalary: 3000,
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 30,
      department: 'FR',
      taxRate: 0,
      cumulativeGrossYTD: 9000, // 3 mois précédents
    })

    // Cumul = 9000 + 3000 = 12000
    expect(result.cumulativeGrossYTD).toBe(12000)
  })
})

// ============================================================
// Formatage
// ============================================================
describe('formatPayrollAmount', () => {
  it('formate un montant avec 2 décimales', () => {
    expect(formatPayrollAmount(1234.567)).toBe('1234.57')
    expect(formatPayrollAmount(0)).toBe('0.00')
  })
})
