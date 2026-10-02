// Factur-X (Cross Industry Invoice) and UBL 2.1 electronic invoice generators.
// Factur-X is the French standard based on EN 16931 (CII XML schema).
// UBL is the alternative format used in some European countries.

import type { Invoice, InvoiceLine, Customer, CompanySettings } from '@/types'

function escapeXml(str: string | null | undefined): string {
  if (!str) return ''
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

function formatDateISO(date: string): string {
  if (!date) return new Date().toISOString().split('T')[0]
  return date.split('T')[0]
}

// ============ R-11 : un document provisoire n'est pas une facture ============
//
// Un brouillon peut être téléchargé (il porte alors la mention PRO FORMA), mais
// il ne peut pas devenir une facture électronique : Factur-X et UBL sont des
// pièces opposables, et l'écran ne suffisait pas à l'interdire — un appel direct
// produisait un XML au numéro BROUILLON-FAC-…. La garde est donc au niveau de la
// génération, pas seulement du bouton.
//
// `validation_status` absent (donnée ancienne) est traité comme provisoire : dans
// le doute, on refuse d'émettre une pièce, on n'en émet pas une douteuse.
// ============ B3 (ven-009) : opérations non taxées en France ============
//
// Un code TVA d'exonération ne dit pas à lui seul quelle catégorie EN 16931
// écrire, ni quel motif porter : pour la même opération non taxée, une
// **livraison intracommunautaire de biens** est `K` (art. 262 ter I CGI) et une
// **prestation autoliquidée par le preneur** est `AE` (art. 283-2 CGI). Un
// export hors UE est `G` (art. 262 I CGI). La distinction biens/services se lit
// sur l'article de la ligne (`products.type`), que l'appelant fournit.
//
// Les motifs sont des mentions **légales françaises** : elles ne se traduisent
// pas (même doctrine que les codes de compte 706000 / 707000 du dépôt).
export type EInvoiceOptions = {
  /** product_id → type d'article ('stock' = bien, sinon prestation) */
  productTypes?: Record<string, string>
}

/** Catégorie EN 16931 d'une ligne non taxée en France. */
export function exemptionCategory(vatCode: string | null | undefined, isGoods: boolean): string {
  const code = (vatCode || '').trim().toUpperCase()
  if (code === 'UE') return isGoods ? 'K' : 'AE'
  if (code === 'EXO') return 'G'
  return 'Z'
}

/** Motif légal porté par la catégorie (texte français, opposable). */
export function exemptionReason(category: string): string {
  switch (category) {
    case 'AE': return 'Autoliquidation par le preneur — art. 283-2 CGI'
    case 'K': return 'Exonération de TVA — livraison intracommunautaire, art. 262 ter I CGI'
    case 'G': return 'Exonération de TVA — exportation, art. 262 I CGI'
    default: return ''
  }
}

function isGoodsLine(line: { product_id?: string | null }, options?: EInvoiceOptions): boolean {
  if (!line.product_id || !options?.productTypes) return false
  return options.productTypes[line.product_id] === 'stock'
}

/** Motif légal d'une ligne, ou '' si elle est taxée normalement. */
export function lineExemptionReason(
  line: { vat_code?: string | null; product_id?: string | null },
  productTypes?: Record<string, string>,
): string {
  const isGoods = !!(line.product_id && productTypes?.[line.product_id] === 'stock')
  return exemptionReason(exemptionCategory(line.vat_code, isGoods))
}

export function isDraftDocument(doc: { validation_status?: string | null } | null | undefined): boolean {
  return doc?.validation_status !== 'validated'
}

function assertEInvoiceAllowed(doc: { validation_status?: string | null } | null | undefined): void {
  if (isDraftDocument(doc)) {
    throw new Error(
      'Document provisoire : une facture électronique (Factur-X, UBL) ne peut être générée que sur une facture validée.',
    )
  }
}

// ============ Factur-X (CII / EN 16931) ============

export function generateFacturX(
  invoice: Invoice,
  customer: Customer | null,
  company: CompanySettings | null,
  options?: EInvoiceOptions,
): string {
  assertEInvoiceAllowed(invoice)   // R-11 : jamais sur un brouillon
  const invDate = formatDateISO(invoice.date)
  const dueDate = formatDateISO(invoice.due_date)
  const invNumber = escapeXml(invoice.number)
  const currency = company?.currency || 'EUR'

  const sellerName = escapeXml(company?.legal_name || company?.name || 'Mon Entreprise')
  const sellerSiret = escapeXml(company?.siret || '')
  const sellerVat = escapeXml(company?.vat_number || '')
  const sellerAddress = escapeXml(company?.address || '')
  const sellerCity = escapeXml(company?.city || '')
  const sellerPostal = escapeXml(company?.postal_code || '')
  const sellerCountry = escapeXml(company?.country || 'FR')
  const sellerEmail = escapeXml(company?.email || '')

  const buyerName = escapeXml(customer?.name || invoice.customer_name || 'Client')
  const buyerVat = escapeXml(customer?.vat_number || '')
  const buyerAddress = escapeXml(customer?.address || '')
  const buyerCity = escapeXml(customer?.city || '')
  const buyerPostal = escapeXml(customer?.postal_code || '')
  const buyerCountry = escapeXml(customer?.country || 'FR')
  const buyerEmail = escapeXml(customer?.email || '')

  const lines = invoice.invoice_lines || []
  const subtotal = Number(invoice.subtotal || 0).toFixed(2)
  const vatTotal = Number(invoice.vat_total || 0).toFixed(2)
  const total = Number(invoice.total || 0).toFixed(2)
  const amountDue = Number(invoice.amount_due || 0).toFixed(2)

  const lineXml = lines.map((line: InvoiceLine, idx: number) => {
    const lineTotal = Number(line.total || 0).toFixed(2)
    const unitPrice = Number(line.unit_price || 0).toFixed(2)
    const vatRate = Number(line.vat_rate || 0).toFixed(2)
    // B3 (ven-009) : la catégorie et son motif portent l'opération non taxée
    const category = exemptionCategory(line.vat_code, isGoodsLine(line, options))
    const reason = exemptionReason(category)
    return `          <ram:IncludedSupplyChainTradeLineItem>
            <ram:AssociatedDocumentLineDocument>
              <ram:LineID>${idx + 1}</ram:LineID>
            </ram:AssociatedDocumentLineDocument>
            <ram:SpecifiedTradeProduct>
              <ram:Name>${escapeXml(line.description)}</ram:Name>
            </ram:SpecifiedTradeProduct>
            <ram:SpecifiedLineTradeAgreement>
              <ram:NetPriceProductTradePrice>
                <ram:ChargeAmount>${unitPrice}</ram:ChargeAmount>
              </ram:NetPriceProductTradePrice>
            </ram:SpecifiedLineTradeAgreement>
            <ram:SpecifiedLineTradeDelivery>
              <ram:BilledQuantity unitCode="C62">${Number(line.quantity || 0)}</ram:BilledQuantity>
            </ram:SpecifiedLineTradeDelivery>
            <ram:SpecifiedLineTradeSettlement>
              <ram:ApplicableTradeTax>
                <ram:TypeCode>VAT</ram:TypeCode>
                <ram:CategoryCode>${category}</ram:CategoryCode>
                <ram:RateApplicablePercent>${vatRate}</ram:RateApplicablePercent>${reason ? `
                <ram:ExemptionReason>${escapeXml(reason)}</ram:ExemptionReason>` : ''}
              </ram:ApplicableTradeTax>
              <ram:SpecifiedTradeSettlementLineMonetarySummation>
                <ram:LineTotalAmount>${lineTotal}</ram:LineTotalAmount>
              </ram:SpecifiedTradeSettlementLineMonetarySummation>
            </ram:SpecifiedLineTradeSettlement>
          </ram:IncludedSupplyChainTradeLineItem>`
  }).join('\n')

  return `<?xml version="1.0" encoding="UTF-8"?>
<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
  <rsm:ExchangedDocumentContext>
    <ram:BusinessProcessSpecifiedDocumentContextParameter>
      <ram:ID>urn:cen.eu:en16931:2017</ram:ID>
    </ram:BusinessProcessSpecifiedDocumentContextParameter>
  </rsm:ExchangedDocumentContext>
  <rsm:ExchangedDocument>
    <ram:ID>${invNumber}</ram:ID>
    <ram:TypeCode>380</ram:TypeCode>
    <ram:IssueDateTime>
      <udt:DateTimeString format="102">${invDate.replace(/-/g, '')}</udt:DateTimeString>
    </ram:IssueDateTime>
  </rsm:ExchangedDocument>
  <rsm:SupplyChainTradeTransaction>
${lineXml}
    <ram:ApplicableHeaderTradeAgreement>
      <ram:SellerTradeParty>
        <ram:Name>${sellerName}</ram:Name>
        <ram:DescriptionText>${sellerSiret}</ram:DescriptionText>
        <ram:SpecifiedLegalOrganization>
          <ram:ID>${sellerSiret}</ram:ID>
        </ram:SpecifiedLegalOrganization>
        <ram:SpecifiedTaxRegistration>
          <ram:ID schemeID="VA">${sellerVat}</ram:ID>
        </ram:SpecifiedTaxRegistration>
        <ram:PostalTradeAddress>
          <ram:PostcodeCode>${sellerPostal}</ram:PostcodeCode>
          <ram:LineOne>${sellerAddress}</ram:LineOne>
          <ram:CityName>${sellerCity}</ram:CityName>
          <ram:CountryID>${sellerCountry}</ram:CountryID>
        </ram:PostalTradeAddress>
        <ram:URIUniversalCommunication>
          <ram:URIID schemeID="EM">${sellerEmail}</ram:URIID>
        </ram:URIUniversalCommunication>
      </ram:SellerTradeParty>
      <ram:BuyerTradeParty>
        <ram:Name>${buyerName}</ram:Name>
        <ram:SpecifiedTaxRegistration>
          <ram:ID schemeID="VA">${buyerVat}</ram:ID>
        </ram:SpecifiedTaxRegistration>
        <ram:PostalTradeAddress>
          <ram:PostcodeCode>${buyerPostal}</ram:PostcodeCode>
          <ram:LineOne>${buyerAddress}</ram:LineOne>
          <ram:CityName>${buyerCity}</ram:CityName>
          <ram:CountryID>${buyerCountry}</ram:CountryID>
        </ram:PostalTradeAddress>
        <ram:URIUniversalCommunication>
          <ram:URIID schemeID="EM">${buyerEmail}</ram:URIID>
        </ram:URIUniversalCommunication>
      </ram:BuyerTradeParty>
    </ram:ApplicableHeaderTradeAgreement>
    <ram:ApplicableHeaderTradeDelivery>
      <ram:ActualDeliverySupplyChainEvent>
        <ram:OccurrenceDateTime>
          <udt:DateTimeString format="102">${invDate.replace(/-/g, '')}</udt:DateTimeString>
        </ram:OccurrenceDateTime>
      </ram:ActualDeliverySupplyChainEvent>
    </ram:ApplicableHeaderTradeDelivery>
    <ram:ApplicableHeaderTradeSettlement>
      <ram:PaymentReference>${invNumber}</ram:PaymentReference>
      <ram:SpecifiedTradeSettlementPaymentMeans>
        <ram:TypeCode>30</ram:TypeCode>
        <ram:Information>Virement</ram:Information>
      </ram:SpecifiedTradeSettlementPaymentMeans>
      <ram:SpecifiedTradePaymentTerms>
        <ram:DueDateDateTime>
          <udt:DateTimeString format="102">${dueDate.replace(/-/g, '')}</udt:DateTimeString>
        </ram:DueDateDateTime>
      </ram:SpecifiedTradePaymentTerms>
      <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        <ram:LineTotalAmount>${subtotal}</ram:LineTotalAmount>
        <ram:TaxBasisTotalAmount>${subtotal}</ram:TaxBasisTotalAmount>
        <ram:TaxTotalAmount currencyID="${currency}">${vatTotal}</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>${total}</ram:GrandTotalAmount>
        <ram:DuePayableAmount>${amountDue}</ram:DuePayableAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
    </ram:ApplicableHeaderTradeSettlement>
  </rsm:SupplyChainTradeTransaction>
</rsm:CrossIndustryInvoice>`
}

// ============ UBL 2.1 ============

export function generateUBL(
  invoice: Invoice,
  customer: Customer | null,
  company: CompanySettings | null,
  options?: EInvoiceOptions,
): string {
  assertEInvoiceAllowed(invoice)   // R-11 : jamais sur un brouillon
  const invDate = formatDateISO(invoice.date)
  const dueDate = formatDateISO(invoice.due_date)
  const invNumber = escapeXml(invoice.number)
  const currency = company?.currency || 'EUR'

  const sellerName = escapeXml(company?.legal_name || company?.name || 'Mon Entreprise')
  const sellerVat = escapeXml(company?.vat_number || '')
  const sellerAddress = escapeXml(company?.address || '')
  const sellerCity = escapeXml(company?.city || '')
  const sellerPostal = escapeXml(company?.postal_code || '')
  const sellerCountry = escapeXml(company?.country || 'FR')

  const buyerName = escapeXml(customer?.name || invoice.customer_name || 'Client')
  const buyerVat = escapeXml(customer?.vat_number || '')
  const buyerAddress = escapeXml(customer?.address || '')
  const buyerCity = escapeXml(customer?.city || '')
  const buyerPostal = escapeXml(customer?.postal_code || '')
  const buyerCountry = escapeXml(customer?.country || 'FR')

  const lines = invoice.invoice_lines || []
  const subtotal = Number(invoice.subtotal || 0).toFixed(2)
  const vatTotal = Number(invoice.vat_total || 0).toFixed(2)
  const total = Number(invoice.total || 0).toFixed(2)
  const amountDue = Number(invoice.amount_due || 0).toFixed(2)

  const lineXml = lines.map((line: InvoiceLine, idx: number) => {
    const lineTotal = Number(line.total || 0).toFixed(2)
    const unitPrice = Number(line.unit_price || 0).toFixed(2)
    const vatRate = Number(line.vat_rate || 0).toFixed(2)
    // B3 (ven-009) : même catégorie que Factur-X
    const category = exemptionCategory((line as { vat_code?: string | null }).vat_code, isGoodsLine(line, options))
    return `    <cac:InvoiceLine>
      <cbc:ID>${idx + 1}</cbc:ID>
      <cbc:InvoicedQuantity unitCode="C62">${Number(line.quantity || 0)}</cbc:InvoicedQuantity>
      <cbc:LineExtensionAmount currencyID="${currency}">${lineTotal}</cbc:LineExtensionAmount>
      <cac:Item>
        <cbc:Description>${escapeXml(line.description)}</cbc:Description>
        <cac:ClassifiedTaxCategory>
          <cbc:ID>${category}</cbc:ID>
          <cbc:Percent>${vatRate}</cbc:Percent>
          <cac:TaxScheme>
            <cbc:ID>VAT</cbc:ID>
          </cac:TaxScheme>
        </cac:ClassifiedTaxCategory>
      </cac:Item>
      <cac:Price>
        <cbc:PriceAmount currencyID="${currency}">${unitPrice}</cbc:PriceAmount>
      </cac:Price>
    </cac:InvoiceLine>`
  }).join('\n')

  return `<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <cbc:ID>${invNumber}</cbc:ID>
  <cbc:IssueDate>${invDate}</cbc:IssueDate>
  <cbc:DueDate>${dueDate}</cbc:DueDate>
  <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
  <cbc:DocumentCurrencyCode>${currency}</cbc:DocumentCurrencyCode>
  <cac:AccountingSupplierParty>
    <cac:Party>
      <cac:PartyName>
        <cbc:Name>${sellerName}</cbc:Name>
      </cac:PartyName>
      <cac:PostalAddress>
        <cbc:StreetName>${sellerAddress}</cbc:StreetName>
        <cbc:CityName>${sellerCity}</cbc:CityName>
        <cbc:PostalZone>${sellerPostal}</cbc:PostalZone>
        <cac:Country>
          <cbc:IdentificationCode>${sellerCountry}</cbc:IdentificationCode>
        </cac:Country>
      </cac:PostalAddress>
      <cac:PartyTaxScheme>
        <cbc:CompanyID>${sellerVat}</cbc:CompanyID>
        <cac:TaxScheme>
          <cbc:ID>VAT</cbc:ID>
        </cac:TaxScheme>
      </cac:PartyTaxScheme>
    </cac:Party>
  </cac:AccountingSupplierParty>
  <cac:AccountingCustomerParty>
    <cac:Party>
      <cac:PartyName>
        <cbc:Name>${buyerName}</cbc:Name>
      </cac:PartyName>
      <cac:PostalAddress>
        <cbc:StreetName>${buyerAddress}</cbc:StreetName>
        <cbc:CityName>${buyerCity}</cbc:CityName>
        <cbc:PostalZone>${buyerPostal}</cbc:PostalZone>
        <cac:Country>
          <cbc:IdentificationCode>${buyerCountry}</cbc:IdentificationCode>
        </cac:Country>
      </cac:PostalAddress>
      <cac:PartyTaxScheme>
        <cbc:CompanyID>${buyerVat}</cbc:CompanyID>
        <cac:TaxScheme>
          <cbc:ID>VAT</cbc:ID>
        </cac:TaxScheme>
      </cac:PartyTaxScheme>
    </cac:Party>
  </cac:AccountingCustomerParty>
  <cac:TaxTotal>
    <cbc:TaxAmount currencyID="${currency}">${vatTotal}</cbc:TaxAmount>
  </cac:TaxTotal>
  <cac:LegalMonetaryTotal>
    <cbc:LineExtensionAmount currencyID="${currency}">${subtotal}</cbc:LineExtensionAmount>
    <cbc:TaxInclusiveAmount currencyID="${currency}">${total}</cbc:TaxInclusiveAmount>
    <cbc:PayableAmount currencyID="${currency}">${amountDue}</cbc:PayableAmount>
  </cac:LegalMonetaryTotal>
${lineXml}
</Invoice>`
}

export function downloadXML(xml: string, filename: string) {
  const blob = new Blob([xml], { type: 'application/xml;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
