// QUA-02 : Tests métier de référence pour Vague 2
// Valident les cas d'acceptation des chantiers PAY, PRD, BNQ, VTE, STK, POS, ADM

import { describe, it, expect } from 'vitest'
import { formatPayrollAmount } from '@/lib/payrollFormat'
import { parseCamt053, parseMt940, detectBankStatementFormat, detectDuplicateTransactions } from '@/lib/bankParsers'

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
// Formatage
// ============================================================
describe('formatPayrollAmount', () => {
  it('formate un montant avec 2 décimales', () => {
    expect(formatPayrollAmount(1234.567)).toBe('1234.57')
    expect(formatPayrollAmount(0)).toBe('0.00')
  })
})
