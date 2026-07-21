// SEPA XML generation for bank transfers (pain.001.001.03 schema).
// Supports SEPA Credit Transfer (SCT) for Euro payments.

export interface SEPAPaymentInfo {
  name: string
  iban: string
  bic: string
  amount: number
  reference: string
  description: string
}

export interface SEPAInitiator {
  name: string
  iban: string
  bic: string
  siret?: string
}

function xmlEscape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

function formatSEPAAmount(amount: number): string {
  return amount.toFixed(2)
}

function generateMsgId(): string {
  const ts = new Date().toISOString().replace(/[-:T]/g, '').substring(0, 14)
  const rand = Math.random().toString(36).substring(2, 8).toUpperCase()
  return `MSG-${ts}-${rand}`
}

function generatePmtInfId(): string {
  const ts = new Date().toISOString().replace(/[-:T]/g, '').substring(0, 14)
  return `PMT-${ts}`
}

export function generateSEPAXML(
  initiator: SEPAInitiator,
  payments: SEPAPaymentInfo[],
  executionDate?: string
): string {
  const msgId = generateMsgId()
  const pmtInfId = generatePmtInfId()
  const reqdExctnDt = executionDate || new Date().toISOString().split('T')[0]
  const ctrlSum = payments.reduce((s, p) => s + p.amount, 0)
  const nbOfTxs = payments.length

  const cdtTrfTxInfos = payments
    .map(
      (p, i) => {
        const endToEndId = `${pmtInfId}-${String(i + 1).padStart(4, '0')}`
        return `        <CdtTrfTxInf>
          <PmtId>
            <EndToEndId>${xmlEscape(endToEndId)}</EndToEndId>
          </PmtId>
          <Amt>
            <InstdAmt Ccy="EUR">${formatSEPAAmount(p.amount)}</InstdAmt>
          </Amt>
          <CdtrAgt>
            <FinInstnId>
              <BIC>${p.bic.replace(/\s/g, '')}</BIC>
            </FinInstnId>
          </CdtrAgt>
          <Cdtr>
            <Nm>${xmlEscape(p.name)}</Nm>
          </Cdtr>
          <CdtrAcct>
            <Id>
              <IBAN>${p.iban.replace(/\s/g, '')}</IBAN>
            </Id>
          </CdtrAcct>
          <RmtInf>
            <Ustrd>${xmlEscape(p.description || p.reference)}</Ustrd>
          </RmtInf>
        </CdtTrfTxInf>`
      }
    )
    .join('\n')

  return `<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <CstmrCdtTrfInitn>
    <GrpHdr>
      <MsgId>${xmlEscape(msgId)}</MsgId>
      <CreDtTm>${new Date().toISOString()}</CreDtTm>
      <NbOfTxs>${nbOfTxs}</NbOfTxs>
      <CtrlSum>${formatSEPAAmount(ctrlSum)}</CtrlSum>
      <InitgPty>
        <Nm>${xmlEscape(initiator.name)}</Nm>
        ${initiator.siret ? `<Id><OrgId><Othr><Id>${initiator.siret}</Id></Othr></OrgId></Id>` : ''}
      </InitgPty>
    </GrpHdr>
    <PmtInf>
      <PmtInfId>${xmlEscape(pmtInfId)}</PmtInfId>
      <PmtMtd>TRF</PmtMtd>
      <NbOfTxs>${nbOfTxs}</NbOfTxs>
      <CtrlSum>${formatSEPAAmount(ctrlSum)}</CtrlSum>
      <PmtTpInf>
        <SvcLvl>
          <Cd>SEPA</Cd>
        </SvcLvl>
      </PmtTpInf>
      <ReqdExctnDt>${reqdExctnDt}</ReqdExctnDt>
      <Dbtr>
        <Nm>${xmlEscape(initiator.name)}</Nm>
      </Dbtr>
      <DbtrAcct>
        <Id>
          <IBAN>${initiator.iban.replace(/\s/g, '')}</IBAN>
        </Id>
      </DbtrAcct>
      <DbtrAgt>
        <FinInstnId>
          <BIC>${initiator.bic.replace(/\s/g, '')}</BIC>
        </FinInstnId>
      </DbtrAgt>
      <ChrgBr>SLEV</ChrgBr>
${cdtTrfTxInfos}
    </PmtInf>
  </CstmrCdtTrfInitn>
</Document>`
}

export function downloadSEPAXML(xml: string, filename: string) {
  const blob = new Blob([xml], { type: 'application/xml;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
