import { describe, it, expect } from 'vitest'
import fs from 'fs'
import path from 'path'
import {
  detectBankStatementFormat,
  parseBankStatement,
  parseOfx,
  parseOfxDate,
  parseCfonbAmount,
  parseCfonbDate,
  type BankStatementFormat,
} from '@/lib/bankParsers'

// R-10 / AUD-G03 : relevés réels anonymisés, un par format (fixtures/README.md).
// Ces fichiers ont été écrits d'après la structure des extraits bancaires réels —
// c'est ce qui manquait : les chaînes fabriquées dans les tests précédents
// respectaient les positions que le lecteur attendait, pas celles de la norme.

const fixture = (name: string) => fs.readFileSync(path.resolve(process.cwd(), 'src/lib/__tests__/fixtures', name), 'utf8')

const FICHIERS: Array<{ fichier: string; format: BankStatementFormat }> = [
  { fichier: 'releve-cfonb120.txt', format: 'cfonb120' },
  { fichier: 'releve-mt940.sta', format: 'mt940' },
  { fichier: 'releve-camt053.xml', format: 'camt053' },
  { fichier: 'releve-ofx1-sgml.ofx', format: 'ofx' },
  { fichier: 'releve-ofx2-xml.ofx', format: 'ofx' },
]

// Les trois opérations communes à tous les fichiers (README de fixtures)
const OPERATIONS = [
  { date: '2025-01-01', type: 'credit', amount: 500, description: 'VIREMENT RECU CLIENT EXEMPLE', reference: 'REF-2025-0001' },
  { date: '2025-01-02', type: 'debit', amount: -120, description: 'FRAIS BANCAIRES TENUE DE COMPTE', reference: 'FRAIS-2025-01' },
  { date: '2025-01-03', type: 'debit', amount: -273, description: 'PRLV FOURNISSEUR EXEMPLE', reference: 'PRLV-2025-0001' },
]

describe('R-10 — relevés réels : détection du format', () => {
  for (const { fichier, format } of FICHIERS) {
    it(`${fichier} est reconnu comme ${format}`, () => {
      expect(detectBankStatementFormat(fixture(fichier))).toBe(format)
    })
  }

  it('un relevé OFX SGML (en-tête OFXHEADER) n’est pas pris pour du MT940', () => {
    expect(detectBankStatementFormat('OFXHEADER:100\nDATA:OFXSGML\n\n<OFX>\n<CURDEF>EUR\n</OFX>')).toBe('ofx')
  })
})

describe('R-10 — relevés réels : les cinq formats donnent les mêmes opérations', () => {
  for (const { fichier, format } of FICHIERS) {
    it(`${fichier} → 3 opérations, soldes et devise`, () => {
      const r = parseBankStatement(fixture(fichier))
      expect(r.warnings).toEqual([])
      expect(r.transactions).toHaveLength(3)
      expect(r.currency).toBe('EUR')
      expect(r.currencyFromFile).toBe(true)
      expect(r.accountNumber).toBe(format === 'cfonb120' ? '00000000123' : 'FR7630004000030000000000123')
      expect(r.closingBalance).toBe(1107)
      expect(r.periodEnd).toBe('2025-01-03')

      r.transactions.forEach((t, i) => {
        const attendu = OPERATIONS[i]
        expect(t.date).toBe(attendu.date)
        expect(t.type).toBe(attendu.type)
        expect(t.amount).toBe(attendu.amount)
        expect(t.description).toContain(attendu.description)
        expect(t.reference).toBe(attendu.reference)
      })

      // Le solde d'ouverture : OFX ne le publie pas dans ce relevé (LEDGERBAL = clôture)
      if (format !== 'ofx') expect(r.openingBalance).toBe(1000)
    })
  }

  it('le format déclaré force le lecteur, même si la détection dit autre chose', () => {
    const r = parseBankStatement(fixture('releve-mt940.sta'), 'mt940')
    expect(r.transactions).toHaveLength(3)
  })
})


describe('R-10 — OFX', () => {
  it('lit les deux générations (SGML non fermé et XML bien formé)', () => {
    for (const fichier of ['releve-ofx1-sgml.ofx', 'releve-ofx2-xml.ofx']) {
      const r = parseOfx(fixture(fichier))
      expect(r.warnings, fichier).toEqual([])
      expect(r.transactions, fichier).toHaveLength(3)
      expect(r.transactions.map(t => t.amount), fichier).toEqual([500, -120, -273])
      expect(r.closingBalance, fichier).toBe(1107)
      // `DTASOF` date le solde de clôture : c'est cette date que l'import écrit
      expect(r.periodEnd, fichier).toBe('2025-01-03')
      expect(r.periodStart, fichier).toBe('2025-01-01')
    }
  })

  it('le signe du montant fait foi ; `TRNTYPE` ne tranche que s’il est positif', () => {
    const r = parseOfx(fixture('releve-ofx1-sgml.ofx'))
    // TRNAMT positif + TRNTYPE FEE → débit ; TRNAMT négatif → débit quoi qu'il arrive
    expect(r.transactions[1]).toMatchObject({ type: 'debit', amount: -120 })
    expect(r.transactions[2]).toMatchObject({ type: 'debit', amount: -273 })
    expect(r.transactions[0]).toMatchObject({ type: 'credit', amount: 500 })
  })

  it('date OFX : les 8 premiers chiffres, heure et fuseau ignorés', () => {
    expect(parseOfxDate('20250103')).toBe('2025-01-03')
    expect(parseOfxDate('20250103180000')).toBe('2025-01-03')
    expect(parseOfxDate('20250103180000.000[-3:EST]')).toBe('2025-01-03')
    expect(parseOfxDate('20251303')).toBeNull()
    expect(parseOfxDate('')).toBeNull()
  })

  it('une opération sans date exploitable est écartée avec un avertissement, pas datée du jour', () => {
    const sgml = 'OFXHEADER:100\n\n<OFX>\n<CURDEF>EUR\n<BANKTRANLIST>\n<STMTTRN>\n<TRNTYPE>CREDIT\n<TRNAMT>10.00\n<FITID>SANS-DATE\n</STMTTRN>\n</BANKTRANLIST>\n</OFX>'
    const r = parseOfx(sgml)
    expect(r.transactions).toHaveLength(0)
    expect(r.warnings.join(' ')).toContain('SANS-DATE')
    expect(r.warnings.join(' ')).toContain('sans date exploitable')
  })

  it('un relevé OFX sans `CURDEF` ne prétend pas avoir lu la devise', () => {
    const r = parseOfx('<OFX>\n<BANKTRANLIST>\n<STMTTRN>\n<TRNTYPE>CREDIT\n<DTPOSTED>20250101\n<TRNAMT>10.00\n<FITID>X1\n</STMTTRN>\n</BANKTRANLIST>\n</OFX>')
    expect(r.transactions).toHaveLength(1)
    expect(r.currencyFromFile).toBe(false)
  })
})

describe('R-10 — CFONB 120 : montant signé et dates JJMMAA', () => {
  it('le 14e caractère porte le signe ET le chiffre des unités', () => {
    expect(parseCfonbAmount('0000000001904{', 2)).toBe(190.4)
    expect(parseCfonbAmount('0000000001904}', 2)).toBe(-190.4)
    expect(parseCfonbAmount('0000000001904I', 2)).toBe(190.49)
    expect(parseCfonbAmount('0000000001904R', 2)).toBe(-190.49)
    expect(parseCfonbAmount('0000000001904}', 0)).toBe(-19040)
  })

  it('un champ vide ou illisible ne vaut pas zéro', () => {
    expect(parseCfonbAmount('              ', 2)).toBeNull()
    expect(parseCfonbAmount('0000000001904 ', 2)).toBeNull()
  })

  it('les dates sont JJMMAA et basculent à 60', () => {
    expect(parseCfonbDate('010125')).toBe('2025-01-01')
    expect(parseCfonbDate('311299')).toBe('1999-12-31')
    expect(parseCfonbDate('010160')).toBe('2060-01-01')
    expect(parseCfonbDate('010161')).toBe('1961-01-01')
    expect(parseCfonbDate('320125')).toBeNull()
    expect(parseCfonbDate('')).toBeNull()
  })

  it('le libellé vient de la zone 49-80 et non du numéro d’écriture', () => {
    const r = parseBankStatement(fixture('releve-cfonb120.txt'))
    expect(r.transactions[0].description).toBe('VIREMENT RECU CLIENT EXEMPLE VIR SEPA RECU')
    expect(r.transactions[1].description).toBe('FRAIS BANCAIRES TENUE DE COMPTE')
  })
})

describe('R-10 — MT940 : date de valeur MMDD', () => {
  it('« 0102D120,00 » vaut 120 au débit (et non 102, comme le lisait le lecteur précédent)', () => {
    const mt = ':20:X\n:25:FR76\n:60F:C250101EUR0,00\n:61:2501010102D120,00NCHGFRAIS\n:86:FRAIS\n:62F:C250102EUR120,00'
    const r = parseBankStatement(mt)
    expect(r.transactions).toHaveLength(1)
    expect(r.transactions[0]).toMatchObject({ date: '2025-01-01', type: 'debit', amount: -120, reference: 'FRAIS' })
  })

  it('un solde écrit sans devise ne fait pas croire à une devise « 100 »', () => {
    const mt = ':20:X\n:25:FR76\n:60F:C2501011000,00\n:61:250101C10,00NTRFREF1\n:86:RECU\n:62F:C250101EUR1010,00'
    const r = parseBankStatement(mt)
    expect(r.currencyFromFile).toBe(false)
    expect(r.openingBalance).toBe(1000)
    expect(r.transactions[0]).toMatchObject({ type: 'credit', amount: 10, reference: 'REF1' })
  })
})
