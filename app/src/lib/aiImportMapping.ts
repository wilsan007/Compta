// Smart auto-mapping engine for Excel/CSV imports.
// Uses fuzzy string matching + a French/English synonym dictionary
// to automatically detect which source column maps to which target field,
// regardless of column order or naming conventions.

// ─── Types ────────────────────────────────────────────────────────────

export interface MappingSuggestion {
  fieldKey: string
  sourceColumn: string
  confidence: number // 0–1
  reason: string
}

export interface AutoMappingResult {
  mapping: Record<string, string> // fieldKey → sourceColumn
  confidence: number // overall confidence 0–1
  suggestions: MappingSuggestion[]
  unmappedFields: string[] // field keys with no match
  unmappedColumns: string[] // source columns not assigned to any field
}

// ─── Levenshtein distance (normalised similarity) ────────────────────

function levenshtein(a: string, b: string): number {
  const m = a.length
  const n = b.length
  if (m === 0) return n
  if (n === 0) return m
  const dp: number[][] = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0))
  for (let i = 0; i <= m; i++) dp[i][0] = i
  for (let j = 0; j <= n; j++) dp[0][j] = j
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
    }
  }
  return dp[m][n]
}

function similarity(a: string, b: string): number {
  if (!a || !b) return 0
  if (a === b) return 1
  const maxLen = Math.max(a.length, b.length)
  if (maxLen === 0) return 1
  return 1 - levenshtein(a, b) / maxLen
}

// ─── Normalisation ────────────────────────────────────────────────────

function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]/g, '')
}

// ─── Synonym dictionary (FR + EN) ────────────────────────────────────
// Each entry maps a set of synonyms to a canonical field key.
// The engine will match any synonym (or close fuzzy variant) to the field.

const SYNONYMS: Record<string, string[]> = {
  // ── chart_accounts ──────────────────────────────────────────────────
  code: [
    'code', 'compte', 'comptec', 'numero', 'numero', 'num', 'n', 'no', 'nos',
    'account', 'accountnumber', 'accountcode', 'accountnum', 'acct', 'acctnum', 'acctcode',
    'numerocompte', 'nocompte', 'comptegeneral', 'numerodecompte', 'compte general',
    'compte comptable', 'comptecomptable', 'numero compte', 'n de compte', 'ncpte',
    'glcode', 'glaccount', 'glaccountnumber', 'ledgercode', 'ledgeraccount',
    'codice', 'kontenplan', 'kontonr', 'kontonummer',
  ],
  name: [
    'nom', 'name', 'libelle', 'lib', 'label', 'designation', 'intitule', 'titre', 'title',
    'raisonsociale', 'raison sociale', 'rs', 'denomination', 'denominationsociale',
    'nomcomplet', 'fullname', 'displayname', 'accountname', 'accounttitle',
    'description', 'desc', 'intitulecompte', 'libellecompte', 'nomcompte',
    'companyname', 'nomentreprise', 'nomsociete', 'nom societe',
    'bezeichnung', 'bezeichnungkonto', 'contoname',
  ],
  type: [
    'type', 'categorie', 'category', 'classe', 'class', 'nature', 'kind', 'sorte',
    'typ', 'typedecompte', 'accounttype', 'comptetype', 'typecompte',
    'categorycode', 'categoriecompte', 'classededomaine', 'domaine',
    'accountclass', 'classecompte', 'plancomptable', 'pcg',
  ],
  vat_rate: [
    'tva', 'tvataux', 'tauxtva', 'vat', 'vatrate', 'vatpct', 'tx', 'taux', 'taxrate',
    'tax', 'pourcentagetva', 'pourcent tva', 'pcttva', 'tva pct', 'tva pourcentage',
    'tx tva', 'taux de tva', 'tauxde tva', 'codetva', 'tvacode', 'vatcode',
    'taxratepct', 'taxpercentage', 'pourcentage taxe', 'tva tx',
    'ust', 'mwst', 'ustsatz', 'mwstsatz', 'iva', 'iva tipo',
  ],
  description: [
    'description', 'desc', 'detail', 'details', 'commentaire', 'comment', 'note', 'notes',
    'remarque', 'observation', 'observations', 'remarques', 'commentaires',
    'memo', 'memorandum', 'noteinterne', 'internalnote', 'remarques internes',
    'info', 'information', 'informations', 'divers', 'diverse',
    'zusatzinfo', 'bemerkung', 'bemerkungen', 'nota',
  ],

  // ── customers / suppliers ──────────────────────────────────────────
  email: [
    'email', 'mail', 'courriel', 'emailaddress', 'adresseemail', 'mel', 'e',
    'e mail', 'e-mail', 'email1', 'email2', 'emailaddress1', 'emailaddress2',
    'mailaddress', 'mailaddress1', 'adresse mail', 'adresse electronique',
    'adresseemail1', 'courriel1', 'mail1', 'emailprincipal', 'email primaire',
    'emailcontact', 'email de contact', 'emailpro', 'email professionnel',
    'email1value', 'primaryemail', 'contactemail',
  ],
  phone: [
    'telephone', 'tel', 'phone', 'phonenumber', 'numero', 'numtel', 'portable',
    'mobile', 'fixe', 'telephoneportable', 'gsm', 'contactphone', 'phone1', 'phone2',
    'tel1', 'tel2', 'telephone1', 'telephone2', 'tel portable', 'tel mobile',
    'tel fixe', 'telephone fixe', 'telephone mobile', 'num telephone', 'num tel',
    'telephone principal', 'tel principal', 'telephonecontact', 'telephone contact',
    'telcontact', 'tel bureau', 'telephone bureau', 'telbureau', 'phoneoffice',
    'phoneoffice1', 'officephone', 'businessphone', 'workphone', 'homephone',
    'fax', 'telecopie', 'telecopieur', 'faxnumber', 'numfax', 'fax1',
    'handy', 'mobil', 'mobiltelefon', 'telefono', 'cellulare', 'cellphone',
  ],
  address: [
    'adresse', 'address', 'rue', 'street', 'streetaddress', 'adressepostale',
    'voie', 'addresse', 'adresse1', 'address1', 'addr', 'adresse2', 'address2',
    'adressepostale1', 'postaladdress', 'adressecomplete', 'fulladdress',
    'adresse rue', 'rue adresse', 'adresse physique', 'physicaladdress',
    'location', 'emplacement', 'lieu', 'place', 'adresse de livraison',
    'deliveryaddress', 'shippingaddress', 'adresse de facturation',
    'billingaddress', 'adresseclient', 'adresse fournisseur',
    'adresse1complete', 'adresse ligne1', 'addressline1', 'addressline2',
    'strasse', 'strasse1', 'indirizzo', 'via',
  ],
  city: [
    'ville', 'city', 'commune', 'localite', 'locality', 'town', 'burceau', 'bureau',
    'ville1', 'city1', 'villeclient', 'ville fournisseur', 'nom ville',
    'ville de livraison', 'deliverycity', 'shippingcity', 'ville de facturation',
    'billingcity', 'cityname', 'nomcommune', 'nomville',
    'stadt', 'ort', 'citta', 'comunecitta',
  ],
  postal_code: [
    'codepostal', 'cp', 'postalcode', 'zip', 'zipcode', 'zip', 'postcode',
    'cedex', 'code postal', 'code postal1', 'postalcode1', 'zip1', 'zip code',
    'codepostalclient', 'code postal client', 'cp client', 'cp1',
    'codepostal livr', 'code postal livraison', 'deliveryzip', 'deliverypostalcode',
    'code postal facturation', 'billingzip', 'billingpostalcode',
    'codepostal2', 'postalcode2', 'zip2', 'cp2',
    'plz', 'postleitzahl', 'cap', 'codicepostale',
  ],
  country: [
    'pays', 'country', 'nation', 'nationalite', 'codepays', 'countrycode',
    'pays1', 'country1', 'paysclient', 'pays fournisseur', 'nom pays',
    'pays de livraison', 'deliverycountry', 'shippingcountry',
    'pays de facturation', 'billingcountry', 'countryname', 'nompays',
    'payscode', 'countrypays', 'iso country', 'isocountry', 'isocode',
    'land', 'landcode', 'paese', 'nazionecode',
  ],
  vat_number: [
    'tva', 'numerotva', 'tvaintra', 'intracommunautaire', 'vatnumber', 'tin',
    'taxid', 'taxnumber', 'nuitva', 'nrtva', 'tvanumero', 'identifianttva',
    'vatregno', 'tva intra', 'tva intracommunautaire', 'numero tva intra',
    'num tva intra', 'num tvaintra', 'no tva', 'no tva intra', 'tva intra com',
    'tva intracom', 'vat intracomm', 'vat intra', 'vat no', 'vat num',
    'vatnumber1', 'vatregistration', 'vatregistrationnumber', 'taxidnumber',
    'taxid1', 'tax id', 'tax id number', 'tin number', 'european vat',
    'eu vat', 'eu vat number', 'eu vat no', 'uid', 'ust idnr', 'ust identifikationsnummer',
    'partita iva', 'p iva', 'piva', 'codicefiscale',
  ],
  contact_name: [
    'contact', 'contactname', 'nomcontact', 'personneacontacter', 'personne a contacter',
    'interlocuteur', 'representant', 'agent', 'commercial', 'vendeur', 'salesrep',
    'salesrepresentative', 'contact1', 'contactprincipal', 'contact principal',
    'nom du contact', 'nom contact', 'prenom contact', 'prenomcontact',
    'contact fullname', 'contactnom', 'contactprenom', 'contact first name',
    'contact last name', 'contactfirstname', 'contactlastname',
    'nom du commercial', 'nom commercial', 'commercial responsable',
    'accountmanager', 'account manager', 'gestionnaire', 'gestionnaire de compte',
    'ansprechpartner', 'kontaktperson', 'contatto', 'personadiriferimento',
  ],
  siret: [
    'siret', 'siren', 'rc', 'registrecommerce', 'companyreg', 'registrationnumber',
    'numerosiret', 'numerosiren', 'rcs', 'rcs numero', 'rcs num',
    'siret1', 'siren1', 'numero siret', 'numero siren', 'no siret', 'no siren',
    'num siret', 'num siren', 'n siret', 'n siren', 'siret numero',
    'siren numero', 'registre du commerce', 'registre commerce et societes',
    'company registration', 'company registration number', 'company reg number',
    'business registration', 'business id', 'businessid', 'companyid',
    'establishment number', 'etablissement numero', 'num etablissement',
    'handelsregister', 'hr nummer', 'registro imprese', 'rea',
  ],
  website: [
    'site', 'website', 'sitenet', 'siteweb', 'url', 'domaine', 'domain',
    'homepage', 'sitinternet', 'siteweb', 'site internet', 'site web',
    'site web url', 'web', 'webaddress', 'web address', 'site url',
    'siteinternet', 'siteinternet url', 'urlsite', 'url site',
    'homepageurl', 'homepage url', 'site1', 'website1',
    'webseite', 'internetadresse', 'sitoweb', 'sito internet',
  ],
  iban: [
    'iban', 'rib', 'accountiban', 'ibanaccount', 'bankaccount', 'comptebancaire',
    'iban1', 'iban numero', 'numero iban', 'num iban', 'no iban', 'n iban',
    'iban number', 'iban no', 'iban code', 'rib numero', 'numero rib',
    'num rib', 'no rib', 'n rib', 'rib complete', 'rib complet',
    'bank account number', 'bank account no', 'bankaccountnumber', 'bankaccountno',
    'account number', 'accountnumber', 'account no', 'accountno',
    'compte bancaire numero', 'numero compte bancaire', 'num compte bancaire',
    'bank details', 'bankdetails', 'coordonnees bancaires', 'coordbancaires',
    'iban bic', 'ibanbanque', 'iban bank',
    'iban code', 'ibanaccountnumber', 'internationalbankaccountnumber',
  ],
  bic: [
    'bic', 'swift', 'bankcode', 'codebanque', 'codeswift', 'swiftcode',
    'bic1', 'bic numero', 'numero bic', 'num bic', 'no bic', 'n bic',
    'bic code', 'bic number', 'bic no', 'swift bic', 'swiftbic',
    'swift number', 'swift no', 'swift address', 'bank identifier code',
    'bank identifier', 'bankbic', 'bic bank', 'bic banque',
    'bank bic code', 'bank swift code', 'swift code bank', 'swift bank code',
    'bankcodebic', 'code banque bic', 'code swift bic', 'swift bank',
    'bank routing number', 'routingnumber', 'routing number', 'ach routing',
    'blz', 'bankleitzahl', 'abi', 'cab', 'codiceabi', 'codicecab',
  ],
  bank_name: [
    'banque', 'bank', 'bankname', 'nombanque', 'nom banque', 'nom de la banque',
    'bank name', 'bank1', 'etablissement bancaire', 'etablissement',
    'nom banque1', 'bankname1', 'banktitle', 'bank title',
    'institut bancaire', 'institut', 'nom etablissement bancaire',
    'bank establishment', 'bank establishment name', 'bank entity',
    'bank entity name', 'bankentity', 'bank designation',
    'credit institution', 'institution de credit', 'institution',
    'bank full name', 'bank complete name', 'nom de banque',
    'denomination bancaire', 'nom etablissement', 'bank institute',
    'kreditinstitut', 'credit institut', 'istituto di credito',
    'banca', 'nome banca', 'nom de la banca',
  ],

  // ── products ────────────────────────────────────────────────────────
  sku: [
    'sku', 'reference', 'ref', 'referenceproduit', 'refproduit', 'codearticle',
    'articlecode', 'productcode', 'codeproduit', 'itemcode', 'skucode',
    'referenceinterne', 'ref interne', 'refinterne', 'code article',
    'code produit', 'code item', 'item number', 'itemnumber', 'itemno',
    'articlenumber', 'articleno', 'articleref', 'productref', 'prodref',
    'productnumber', 'productno', 'productid', 'articleid', 'itemid',
    'internalreference', 'internal reference', 'ref article', 'ref produit',
    'reference article', 'reference produit', 'codice articolo', 'artikelnummer',
    'artikelcode', 'produktnummer', 'produktcode',
  ],
  sale_price: [
    'prixvente', 'prix', 'price', 'saleprice', 'sellingprice', 'pv',
    'prixdevente', 'prix de vente', 'prixunitaire', 'unitprice', 'prixpublic',
    'tarif', 'tarifvente', 'tarif vente', 'prix vente', 'prix de vente ht',
    'prix ventettc', 'prix de vente ttc', 'pvht', 'pvttc', 'pvente',
    'selling price', 'sell price', 'sales price', 'salesprice', 'retailprice',
    'retail price', 'list price', 'listprice', 'grossprice', 'gross price',
    'preis', 'verkaufspreis', 'verkaufspreis netto', 'prezzo vendita',
    'prezzo di vendita', 'precio venta', 'precio de venta',
  ],
  purchase_price: [
    'prixachat', 'pa', 'purchaseprice', 'costprice', 'cost', 'prixrevient',
    'prix de revient', 'prixdeachat', 'prix d achat', 'cout', 'coutachat',
    'cout d achat', 'coutunitaire', 'cout unitaire', 'prix achat',
    'prix d achat ht', 'paht', 'patht', 'purchase price', 'purchase cost',
    'purchasecost', 'buying price', 'buyingprice', 'buy price', 'buyprice',
    'wholesale price', 'wholesaleprice', 'supplier price', 'supplierprice',
    'einstandspreis', 'einkaufspreis', 'einkaufspreis netto',
    'prezzo acquisto', 'prezzo di acquisto', 'precio compra',
    'precio de compra', 'costo acquisto',
  ],
  unit: [
    'unite', 'unit', 'unitevente', 'salesunit', 'unitemesure', 'measureunit',
    'um', 'uniteconditionnement', 'unite de vente', 'unite de mesure',
    'unite de conditionnement', 'unit of measure', 'unitofmeasure', 'uom',
    'unit code', 'unitcode', 'sales unit', 'measure unit', 'measuring unit',
    'conditioning unit', 'packaging unit', 'packagingunit', 'colisage',
    'colis', 'conditionnement', 'emballage', 'pack unit', 'packunit',
    'einheit', 'mengeneinheit', 'verkaufseinheit', 'unita vendita',
    'unita di vendita', 'unita di misura', 'unidad venta', 'unidad de venta',
  ],
  category: [
    'categorie', 'category', 'famille', 'family', 'groupe', 'group',
    'rubrique', 'section', 'typeproduit', 'producttype', 'classification',
    'categorie produit', 'categorie de produit', 'product category',
    'productcategory', 'product family', 'productfamily', 'product group',
    'productgroup', 'product class', 'productclass', 'product line',
    'productline', 'famille produit', 'famille de produit', 'groupe produit',
    'groupe de produit', 'rubrique produit', 'section produit',
    'sous categorie', 'souscategorie', 'subcategory', 'sub category',
    'sous famille', 'sousfamille', 'subfamily', 'sub family',
    'kategorie', 'produktkategorie', 'produktgruppe', 'produktfamilie',
    'categoria prodotto', 'categoria di prodotto', 'famiglia prodotto',
  ],

  // ── invoices / accounting ───────────────────────────────────────────
  date: [
    'date', 'datefacture', 'invoicedate', 'datedocument', 'datepiece',
    'dateemission', 'issuedate', 'datecreation', 'creationdate', 'jour',
    'dateoperation', 'operationdate', 'date facture', 'date de facture',
    'date document', 'date de document', 'date piece', 'date de piece',
    'date emission', 'date d emission', 'date de creation', 'date du jour',
    'date saisie', 'saisie date', 'date de saisie', 'entrydate', 'entry date',
    'postingdate', 'posting date', 'transactiondate', 'transaction date',
    'businessdate', 'business date', 'effectivedate', 'effective date',
    'datedoc', 'date doc', 'date ref', 'dateref', 'date de reference',
    'datum', 'rechnungsdatum', 'buchungsdatum', 'belegdatum',
    'data fattura', 'data documento', 'data emissione',
  ],
  due_date: [
    'echeance', 'duedate', 'dateecheance', 'date limite', 'datelimite',
    'paymentdue', 'duedate', 'echeancier', 'echeance facture', 'echeance de facture',
    'date d echeance', 'date d echeance facture', 'date limite paiement',
    'date limite de paiement', 'payment due date', 'paymentduedate',
    'due date', 'maturity date', 'maturitydate', 'settlement date',
    'settlementdate', 'date reglement', 'date de reglement', 'reglement',
    'date de paiement', 'payment date', 'paymentdate', 'date echu',
    'date d echu', 'echeance paiement', 'echeance de paiement',
    'zahlungsziel', 'faelligkeitsdatum', 'scadenza', 'data scadenza',
    'data di scadenza', 'fecha vencimiento', 'fecha de vencimiento',
  ],
  amount: [
    'montant', 'amount', 'total', 'totalht', 'amounttotal', 'montanttotal',
    'valeur', 'value', 'somme', 'mt', 'montant ht', 'montantht', 'montant ttc',
    'montantttc', 'montant total', 'montant total ht', 'montant total ttc',
    'total ttc', 'totalttc', 'total ht', 'totalht', 'montant facture',
    'montant de facture', 'invoice amount', 'invoiceamount', 'invoice total',
    'invoicetotal', 'gross amount', 'grossamount', 'net amount', 'netamount',
    'grand total', 'grandtotal', 'subtotal', 'sub total', 'sous total',
    'soustotal', 'montant brut', 'montantbrut', 'montant net', 'montantnet',
    'betrag', 'gesamtbetrag', 'nettobetrag', 'bruttobetrag', 'rechnungsbetrag',
    'importo', 'importo totale', 'importo fattura', 'totale fattura',
    'importe', 'importe total', 'importe factura',
  ],
  quantity: [
    'quantite', 'qty', 'quantity', 'qte', 'nombre', 'count', 'unites', 'units',
    'volume', 'nombreunites', 'nombre d unites', 'quantite unitaire',
    'quantite unit', 'quantite article', 'quantite de article', 'qte article',
    'qte de article', 'qty ordered', 'qtyordered', 'quantity ordered',
    'quantityordered', 'ordered quantity', 'orderedquantity', 'order qty',
    'orderqty', 'shipped qty', 'shippedqty', 'shipped quantity', 'shippedquantity',
    'delivered qty', 'deliveredqty', 'delivered quantity', 'deliveredquantity',
    'invoiced qty', 'invoicedqty', 'invoiced quantity', 'invoicedquantity',
    'menge', 'anzahl', 'quantita', 'quantita ordinata', 'cantidad',
    'cantidad pedida', 'numero unidades', 'numero de unidades',
  ],
  unit_price: [
    'prixunitaire', 'unitprice', 'pu', 'prixunit', 'unitcost', 'tarifunitaire',
    'prix unitaire', 'prix unit', 'prix unitaire ht', 'prix unitaire ttc',
    'puht', 'puttc', 'unit price', 'unit cost', 'unitpriceht', 'unitpricettc',
    'price per unit', 'priceperunit', 'cost per unit', 'costperunit',
    'tarif unitaire', 'tarif unit', 'tarif par unite', 'tarif par unit',
    'prix par unite', 'prix par unit', 'prix de l unite', 'prix de l unit',
    'preis pro einheit', 'stueckpreis', 'einzelpreis', 'prezzo unitario',
    'prezzo per unita', 'precio unitario', 'precio por unidad',
  ],
  discount: [
    'remise', 'discount', 'rabais', 'reduction', 'ristourne', 'escompte',
    'discountamount', 'remisepourcentage', 'remise montant', 'remise montant ht',
    'remise pct', 'remise pourcentage', 'remise %', 'pct remise',
    'pourcentage remise', 'taux remise', 'taux de remise', 'discount pct',
    'discount %', 'discount percentage', 'discount rate', 'discountrate',
    'rabatt', 'rabatt betrag', 'rabatt prozent', 'skonto', 'skontobetrag',
    'sconto', 'sconto importo', 'sconto percentuale', 'descuento',
    'descuento importe', 'descuento porcentaje',
  ],
  account_code: [
    'compte', 'comptegeneral', 'account', 'accountcode', 'numeroCompte',
    'imputation', 'imputationcomptable', 'compte general', 'compte comptable',
    'compte compta', 'comptecompta', 'compte imputation', 'compte d imputation',
    'compte de imputation', 'imputation compta', 'imputation comptable',
    'compte de charge', 'compte de produit', 'compte charge', 'compte produit',
    'compte client', 'compte fournisseur', 'compte de tiers', 'compte tiers',
    'compte de banque', 'compte banque', 'compte caisse', 'compte de caisse',
    'gl account', 'glaccount', 'general ledger account', 'ledger account',
    'ledgeraccount', 'chart of account', 'chartofaccount', 'coa',
    'hauptbuch konto', 'sachkonto', 'conto', 'conto generale', 'mastro',
  ],
  journal_code: [
    'journal', 'journalcode', 'codejournal', 'jnl', 'codjnl', 'code journal',
    'code jnl', 'journal jnl', 'journal code', 'journal de vente', 'journal vente',
    'journal d achat', 'journal achat', 'journal de banque', 'journal banque',
    'journal de caisse', 'journal caisse', 'journal d operations', 'journal operations',
    'journal des operations', 'journal od', 'journal divers', 'journal d od',
    'journal type', 'type journal', 'journal book', 'journalbook', 'book code',
    'bookcode', 'day book', 'daybook', 'journal entry code', 'journalentrycode',
    'journalbuch', 'journal code', 'giornale', 'codice giornale',
    'libro giornale', 'diario', 'codigo diario',
  ],
  debit: [
    'debit', 'db', 'd', 'montantdebit', 'montant debit', 'debit montant',
    'debit amount', 'debitamount', 'debit value', 'debitvalue', 'debit total',
    'debittotal', 'montant d', 'mtd', 'mt debit', 'mt d', 'd bit',
    'soll', 'sollbetrag', 'dare', 'importo dare', 'debe', 'importe debe',
  ],
  credit: [
    'credit', 'cr', 'c', 'montantcredit', 'montant credit', 'credit montant',
    'credit amount', 'creditamount', 'credit value', 'creditvalue', 'credit total',
    'credittotal', 'montant c', 'mtc', 'mt credit', 'mt c', 'c redit',
    'haben', 'habenbetrag', 'avere', 'importo avere', 'haber', 'importe haber',
  ],
  reference: [
    'reference', 'ref', 'referencepiece', 'refpiece', 'numpiece', 'piece',
    'document', 'docnumber', 'documentnumber', 'referencefacture', 'ref facture',
    'reference facture', 'reference de facture', 'num piece', 'numero piece',
    'numero de piece', 'no piece', 'n piece', 'num document', 'numero document',
    'numero de document', 'no document', 'n document', 'num doc', 'numero doc',
    'numero de doc', 'no doc', 'n doc', 'piece number', 'piecenumber',
    'piece no', 'pieceno', 'document no', 'documentno', 'doc no', 'docno',
    'piece ref', 'pieceref', 'document ref', 'documentref', 'doc ref', 'docref',
    'entry number', 'entrynumber', 'entry no', 'entryno', 'transaction number',
    'transactionnumber', 'transaction no', 'transactionno', 'batch number',
    'batchnumber', 'batch no', 'batchno', 'posting number', 'postingnumber',
    'belegnummer', 'belegnummer', 'beleg ref', 'numero documento',
    'riferimento', 'riferimento documento', 'numero riferimento',
    'referencia', 'numero referencia', 'numero documento',
  ],
  label: [
    'libelle', 'label', 'intitule', 'description', 'designation', 'objet',
    'nature', 'commentaire', 'libelle ecriture', 'libelle d ecriture',
    'libelle operation', 'libelle d operation', 'libelle de operation',
    'intitule ecriture', 'intitule d ecriture', 'intitule operation',
    'intitule d operation', 'intitule de operation', 'description ecriture',
    'description d ecriture', 'description operation', 'description d operation',
    'description de operation', 'objet ecriture', 'objet d ecriture',
    'objet operation', 'objet d operation', 'objet de operation',
    'nature ecriture', 'nature d ecriture', 'nature operation',
    'nature d operation', 'nature de operation', 'memo', 'narration',
    'narrative', 'entry description', 'entrydescription', 'line description',
    'linedescription', 'posting description', 'postingdescription',
    'buchungstext', 'bezeichnung', 'beschreibung', 'descrizione',
    'descrizione operazione', 'oggetto', 'natura', 'descripcion',
    'descripcion operacion',
  ],

  // ── additional fields ───────────────────────────────────────────────
  status: [
    'statut', 'status', 'etat', 'state', 'situation', 'statut facture',
    'statut de facture', 'etat facture', 'etat de facture', 'invoice status',
    'invoicestatus', 'payment status', 'paymentstatus', 'statut paiement',
    'statut de paiement', 'etat paiement', 'etat de paiement',
    'statut reglement', 'statut de reglement', 'etat reglement',
    'etat de reglement', 'document status', 'documentstatus',
    'statut document', 'statut de document', 'etat document',
    'etat de document', 'open', 'closed', 'paid', 'unpaid', 'partial',
    'status code', 'statuscode', 'statusCode', 'statut code', 'statutcode',
    'status value', 'statusvalue', 'statusValue',
    'status', 'rechnungsstatus', 'zahlungsstatus', 'stato', 'stato fattura',
    'stato pagamento', 'estado', 'estado factura', 'estado pago',
  ],
  payment_method: [
    'modepaiement', 'mode paiement', 'mode de paiement', 'paymentmethod',
    'payment method', 'payment type', 'paymenttype', 'payment mode',
    'paymentmode', 'moyen paiement', 'moyen de paiement', 'moyenpaiement',
    'mode reglement', 'mode de reglement', 'modereglement', 'reglement mode',
    'mode de payement', 'mode payement', 'modepayement', 'payment means',
    'paymentmeans', 'payment channel', 'paymentchannel',
    'zahlungsart', 'zahlungsmethode', 'zahlungsmittel', 'modalita pagamento',
    'modalita di pagamento', 'medio pago', 'medio de pago', 'forma pago',
    'forma de pago', 'forma de pago',
  ],
  currency: [
    'devise', 'currency', 'monnaie', 'code devise', 'code de devise',
    'currency code', 'currencycode', 'currency symbol', 'currencysymbol',
    'devise code', 'devisecode', 'devise symbole', 'devisesymbole',
    'monnaie code', 'monnaiecode', 'monnaie symbole', 'monnaiesymbole',
    'iso currency', 'isocurrency', 'iso code', 'isocode', 'iso devise',
    'isodevise', 'currency iso', 'currencyiso', 'devise iso', 'deviseiso',
    'waehrung', 'waehrungscode', 'iso waehrung', 'valuta', 'valuta codice',
    'codice valuta', 'moneda', 'codigo moneda', 'divisa', 'codigo divisa',
  ],
  notes: [
    'notes', 'note', 'remarques', 'remarque', 'commentaires', 'commentaire',
    'comment', 'comments', 'observations', 'observation', 'memo', 'memos',
    'memorandum', 'memorandums', 'note interne', 'note interne',
    'notes internes', 'notes interne', 'note privee', 'note privee',
    'notes privees', 'notes privee', 'private notes', 'privatenotes',
    'internal notes', 'internalnotes', 'internal note', 'internalnote',
    'additional notes', 'additionalnotes', 'additional note', 'additionalnote',
    'extra notes', 'extranotes', 'extra note', 'extranote', 'misc notes',
    'miscnotes', 'misc note', 'miscnote', 'divers', 'diverse', 'info',
    'information', 'informations', 'details', 'detail', 'annotation',
    'annotations', 'anmerkung', 'anmerkungen', 'bemerkung', 'bemerkungen',
    'nota', 'note interne', 'appunti', 'appunto', 'observaciones',
    'observacion', 'notas', 'nota',
  ],
  tax_amount: [
    'montanttva', 'montant tva', 'tva montant', 'tva amount', 'tvaamount',
    'tax amount', 'taxamount', 'vat amount', 'vatamount', 'montant taxe',
    'montant de taxe', 'montanttaxe', 'taxe montant', 'taxe amount',
    'taxeamount', 'montant tva ht', 'montant tva ttc', 'tva ht', 'tva ttc',
    'total tva', 'totaltva', 'total taxe', 'totaltaxe', 'total vat', 'totalvat',
    'tva collectee', 'tvacollectee', 'tva deduite', 'tvadeduite',
    'tva a payer', 'tva a payer', 'tva recuperable', 'tvarecuperable',
    'tax payable', 'taxpayable', 'vat payable', 'vatpayable',
    'tax recoverable', 'taxrecoverable', 'vat recoverable', 'vatrecoverable',
    'umsatzsteuer betrag', 'mwst betrag', 'ust betrag', 'iva importo',
    'importo iva', 'iva amount', 'iva importe', 'importe iva',
  ],
  subtotal: [
    'sous total', 'soustotal', 'sous-total', 'subtotal', 'sub total',
    'subtotal ht', 'subtotalht', 'sous total ht', 'sous total ht',
    'net subtotal', 'netsubtotal', 'sous total net', 'sous total net',
    'montant ht', 'montantht', 'montant ht', 'total ht', 'totalht',
    'total ht', 'net total', 'nettotal', 'montant net', 'montantnet',
    'pretax total', 'pretaxtotal', 'montant avant taxe', 'montant avant taxe',
    'avant taxe', 'avant taxe', 'before tax', 'beforetax', 'before tax total',
    'beforetaxtotal', 'ex tax', 'extax', 'ex tax total', 'extaxtotal',
    'zwischensumme', 'netto zwischensumme', 'subtotal neto', 'subtotal netto',
    'subtotale', 'subtotale netto', 'subtotal neto', 'subtotal neto',
  ],
  customer_name: [
    'nomclient', 'nom client', 'nom du client', 'client', 'clientname',
    'client name', 'customer', 'customername', 'customer name', 'nom de client',
    'raison sociale client', 'raisonsocialeclient', 'client raison sociale',
    'clientraisonsociale', 'nom client raison sociale', 'denomination client',
    'denominationclient', 'client denomination', 'clientdenomination',
    'nom du client raison sociale', 'client nom', 'clientnom',
    'customer company', 'customercompany', 'customer company name',
    'customercompanyname', 'client societe', 'clientsociete',
    'client societe nom', 'clientsocietenom', 'kunde', 'kundenname',
    'cliente', 'nome cliente', 'cliente nombre', 'nombre cliente',
  ],
  supplier_name: [
    'nomfournisseur', 'nom fournisseur', 'nom du fournisseur', 'fournisseur',
    'fournisseurname', 'fournisseur name', 'supplier', 'suppliername',
    'supplier name', 'nom de fournisseur', 'raison sociale fournisseur',
    'raisonsocialefournisseur', 'fournisseur raison sociale',
    'fournisseurrasonsociale', 'nom fournisseur raison sociale',
    'denomination fournisseur', 'denominationfournisseur',
    'fournisseur denomination', 'fournisseurdenomination',
    'nom du fournisseur raison sociale', 'fournisseur nom', 'fournisseurnom',
    'supplier company', 'suppliercompany', 'supplier company name',
    'suppliercompanyname', 'fournisseur societe', 'fournisseursociete',
    'fournisseur societe nom', 'fournisseursocietenom',
    'lieferant', 'lieferantenname', 'fornitore', 'nome fornitore',
    'proveedor', 'nombre proveedor',
  ],
  invoice_number: [
    'numerofacture', 'numero facture', 'numero de facture', 'num facture',
    'num de facture', 'no facture', 'no de facture', 'n facture',
    'n de facture', 'facture numero', 'facture num', 'facture no',
    'facture n', 'facturenumber', 'facture number', 'invoice number',
    'invoicenumber', 'invoice num', 'invoicenum', 'invoice no', 'invoiceno',
    'invoice n', 'invoicen', 'invoice id', 'invoiceid', 'invoice ref',
    'invoiceref', 'facture ref', 'factureref', 'facture reference',
    'facturereference', 'invoice reference', 'invoicereference',
    'bill number', 'billnumber', 'bill num', 'billnum', 'bill no', 'billno',
    'rechnungsnummer', 'rechnung nummer', 'rechnung nr', 'numero fattura',
    'fattura numero', 'numero di fattura', 'numero factura',
    'factura numero', 'numero de factura',
  ],
  order_number: [
    'numerocommande', 'numero commande', 'numero de commande', 'num commande',
    'num de commande', 'no commande', 'no de commande', 'n commande',
    'n de commande', 'commande numero', 'commande num', 'commande no',
    'commande n', 'commandenumber', 'commande number', 'order number',
    'ordernumber', 'order num', 'ordernum', 'order no', 'orderno',
    'order n', 'ordern', 'order id', 'orderid', 'order ref', 'orderref',
    'commande ref', 'commanderef', 'commande reference', 'commandereference',
    'order reference', 'orderreference', 'purchase order', 'purchaseorder',
    'purchase order number', 'purchaseordernumber', 'po number', 'ponumber',
    'po num', 'ponum', 'po no', 'pono', 'po n', 'pon', 'po id', 'poid',
    'sales order', 'salesorder', 'sales order number', 'salesordernumber',
    'so number', 'sonumber', 'bestellnummer', 'bestellung nummer',
    'bestellung nr', 'numero ordine', 'ordine numero', 'numero di ordine',
    'numero pedido', 'pedido numero', 'numero de pedido',
  ],
  barcode: [
    'codebarre', 'code barre', 'code a barre', 'codeabarre', 'barcode',
    'bar code', 'barcode', 'ean', 'ean13', 'ean8', 'upc', 'upca', 'upce',
    'gtin', 'gtin13', 'gtin14', 'gtin8', 'isbn', 'issn', 'asin', 'qrcode',
    'qr code', 'qrcode', 'code barres', 'codebarres', 'code a barres',
    'codeabarres', 'code barre ean', 'codebarre ean', 'ean code', 'eancode',
    'upc code', 'upccode', 'gtin code', 'gtincode', 'strichcode',
    'strichcodenummer', 'ean nummer', 'codice a barre', 'codiceabarre',
    'codice barre', 'codigo barras', 'codigobarras', 'codigo de barras',
  ],
  weight: [
    'poids', 'weight', 'poids net', 'poidsnet', 'poids brut', 'poidsbrut',
    'net weight', 'netweight', 'gross weight', 'grossweight', 'poids unitaire',
    'poidsunitaire', 'unit weight', 'unitweight', 'poids kg', 'poidskg',
    'weight kg', 'weightkg', 'poids en kg', 'poids en kg', 'masse', 'masse kg',
    'masse en kg', 'gewicht', 'nettogewicht', 'bruttogewicht', 'stueckgewicht',
    'peso', 'peso netto', 'peso lordo', 'peso unitario',
  ],
  stock_quantity: [
    'stock', 'quantitestock', 'quantite stock', 'quantite en stock',
    'quantiteenstock', 'qte stock', 'qte en stock', 'qteenstock',
    'stock quantity', 'stockquantity', 'stock qty', 'stockqty',
    'quantity in stock', 'quantityinstock', 'qty in stock', 'qtyinstock',
    'on hand', 'onhand', 'on hand quantity', 'onhandquantity',
    'on hand qty', 'onhandqty', 'available stock', 'availablestock',
    'available quantity', 'availablequantity', 'available qty', 'availableqty',
    'inventory', 'inventory quantity', 'inventoryquantity', 'inventory qty',
    'inventoryqty', 'stock actuel', 'stockactuel', 'current stock',
    'currentstock', 'stock disponible', 'stockdisponible',
    'bestand', 'lagerbestand', 'verfuegbarer bestand', 'bestand menge',
    'giacenza', 'quantita giacenza', 'scorta', 'quantita scorta',
    'existencias', 'cantidad existencias', 'stock disponible',
  ],
  min_stock: [
    'stockmin', 'stock min', 'stock minimum', 'stockminimum', 'quantite min',
    'quantitemin', 'qte min', 'qtemin', 'minimum stock', 'minimumstock',
    'min stock', 'minstock', 'reorder point', 'reorderpoint', 'reorder level',
    'reorderlevel', 'seuil de reappro', 'seuil de reapprovisionnement',
    'seuildereappro', 'seuildereapprovisionnement', 'seuil alerte',
    'seuil d alerte', 'seuildalerte', 'alerte stock', 'alertestock',
    'stock d alerte', 'stockdalerte', 'point de commande', 'pointdecommande',
    'mindestbestand', 'meldebestand', 'bestellpunkt', 'scorta minima',
    'punto riordino', 'livello riordino', 'stock minimo', 'punto pedido',
    'nivel reposicion',
  ],
  tax_rate: [
    'tauxtva', 'taux tva', 'taux de tva', 'taux tvataux', 'tvataux',
    'taux', 'tx', 'tx tva', 'taux de taxe', 'taux de taxe',
    'vat rate', 'vatrate', 'vat pct', 'vatpct', 'tax rate', 'taxrate',
    'tax pct', 'taxpct', 'tva taux', 'tva pct', 'tva pourcentage',
    'tvapourcentage', 'pourcentage tva', 'pourcentagetva', 'pct tva', 'pcttva',
    'tva %', 'vat %', 'tax %', 'codetva', 'tvacode', 'vatcode', 'taxcode',
    'code tva', 'code de tva', 'code taxe', 'code de taxe', 'code vat',
    'code de vat', 'tva code', 'taxe code', 'vat code', 'ust satz',
    'mwst satz', 'iva aliquota', 'aliquota iva', 'tipo iva', 'iva tipo',
    'tasa iva', 'tipo iva',
  ],
}

// ─── Matching engine ──────────────────────────────────────────────────

function matchScore(
  sourceHeader: string,
  fieldKey: string,
  fieldLabel: string,
  synonyms: string[],
): { score: number; reason: string } {
  const src = normalize(sourceHeader)
  const key = normalize(fieldKey)
  const lbl = normalize(fieldLabel)

  // Exact match on normalized field key
  if (src === key) return { score: 1.0, reason: 'match exact (clé)' }

  // Exact match on normalized label
  if (src === lbl) return { score: 1.0, reason: 'match exact (libellé)' }

  // Exact match on a synonym
  for (const syn of synonyms) {
    const nsyn = normalize(syn)
    if (src === nsyn) return { score: 0.98, reason: `synonyme: "${syn}"` }
  }

  // Partial containment (e.g. "Code postal" contains "cp")
  for (const syn of synonyms) {
    const nsyn = normalize(syn)
    if (nsyn.length >= 3 && src.includes(nsyn)) return { score: 0.9, reason: `contient: "${syn}"` }
    if (src.length >= 3 && nsyn.includes(src)) return { score: 0.85, reason: `inclus dans: "${syn}"` }
  }

  // Fuzzy match on label
  const simLabel = similarity(src, lbl)
  if (simLabel >= 0.8) return { score: simLabel * 0.92, reason: `similitude libellé (${Math.round(simLabel * 100)}%)` }

  // Fuzzy match on synonyms
  let bestSyn = 0
  let bestSynVal = ''
  for (const syn of synonyms) {
    const nsyn = normalize(syn)
    const s = similarity(src, nsyn)
    if (s > bestSyn) {
      bestSyn = s
      bestSynVal = syn
    }
  }
  if (bestSyn >= 0.75) return { score: bestSyn * 0.88, reason: `proche de "${bestSynVal}" (${Math.round(bestSyn * 100)}%)` }

  // Fuzzy match on field key
  const simKey = similarity(src, key)
  if (simKey >= 0.8) return { score: simKey * 0.85, reason: `similitude clé (${Math.round(simKey * 100)}%)` }

  return { score: 0, reason: '' }
}

// ─── Public API ───────────────────────────────────────────────────────

export interface TargetField {
  key: string
  label: string
  required?: boolean
  synonyms?: string[]
}

/**
 * Auto-map source columns to target fields using fuzzy matching + synonyms.
 * Returns a mapping, confidence score, and per-field suggestions.
 */
export function autoMapColumns(
  sourceHeaders: string[],
  sampleRows: Record<string, any>[],
  targetFields: TargetField[],
): AutoMappingResult {
  const suggestions: MappingSuggestion[] = []
  const usedColumns = new Set<string>()

  // For each target field, find the best matching source column
  for (const field of targetFields) {
    const synonyms = SYNONYMS[field.key] || field.synonyms || []
    let best: { col: string; score: number; reason: string } = { col: '', score: 0, reason: '' }

    for (const header of sourceHeaders) {
      const { score, reason } = matchScore(header, field.key, field.label, synonyms)
      if (score > best.score) {
        best = { col: header, score, reason }
      }
    }

    // If no header match, try matching based on sample data content
    if (best.score < 0.5 && sampleRows.length > 0) {
      best = matchByContent(field, sourceHeaders, sampleRows) ?? best
    }

    if (best.col && best.score >= 0.5) {
      suggestions.push({
        fieldKey: field.key,
        sourceColumn: best.col,
        confidence: best.score,
        reason: best.reason,
      })
      usedColumns.add(best.col)
    }
  }

  // Resolve conflicts: if two fields map to the same column, keep the highest score
  const colAssignments = new Map<string, MappingSuggestion>()
  for (const sug of suggestions) {
    const existing = colAssignments.get(sug.sourceColumn)
    if (!existing || sug.confidence > existing.confidence) {
      if (existing) {
        // Remove the losing field from suggestions
        const idx = suggestions.findIndex((s) => s === existing)
        if (idx >= 0) suggestions.splice(idx, 1)
      }
      colAssignments.set(sug.sourceColumn, sug)
    }
  }

  // Build final mapping
  const mapping: Record<string, string> = {}
  let totalConfidence = 0
  for (const sug of suggestions) {
    mapping[sug.fieldKey] = sug.sourceColumn
    totalConfidence += sug.confidence
  }

  const unmappedFields = targetFields
    .filter((f) => !mapping[f.key])
    .map((f) => f.key)

  const unmappedColumns = sourceHeaders.filter((h) => !usedColumns.has(h))

  const overallConfidence = targetFields.length > 0
    ? suggestions.length / targetFields.length
    : 0

  return {
    mapping,
    confidence: overallConfidence,
    suggestions,
    unmappedFields,
    unmappedColumns,
  }
}

// ─── Content-based matching (fallback) ────────────────────────────────
// When header names are ambiguous, inspect the actual data to guess the field.

function matchByContent(
  field: TargetField,
  headers: string[],
  rows: Record<string, any>[],
): { col: string; score: number; reason: string } | null {
  const samples = rows.slice(0, 10)

  for (const header of headers) {
    const values = samples.map((r) => String(r[header] ?? '').trim()).filter(Boolean)
    if (values.length === 0) continue

    const score = contentScore(field.key, values)
    if (score >= 0.6) {
      return { col: header, score, reason: 'détecté par analyse du contenu' }
    }
  }
  return null
}

function contentScore(fieldKey: string, values: string[]): number {
  const v = values.slice(0, 5)

  switch (fieldKey) {
    case 'email':
      return v.every((x) => /@/.test(x)) ? 0.85 : 0
    case 'phone':
      return v.every((x) => /^[\d\s+().-]{6,}$/.test(x)) ? 0.7 : 0
    case 'postal_code':
      return v.every((x) => /^\d{4,6}$/.test(x)) ? 0.75 : 0
    case 'vat_number':
      return v.every((x) => /^[A-Z]{2}\d/i.test(x)) ? 0.8 : 0
    case 'code':
      return v.every((x) => /^\d{3,8}$/.test(x)) ? 0.6 : 0
    case 'sale_price':
    case 'purchase_price':
    case 'amount':
    case 'unit_price':
    case 'debit':
    case 'credit':
      return v.every((x) => /^[\d\s.,]+$/.test(x)) ? 0.5 : 0
    case 'date':
    case 'due_date':
      return v.every((x) => /\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}/.test(x) || /^\d{4}-\d{2}-\d{2}/.test(x)) ? 0.75 : 0
    case 'quantity':
      return v.every((x) => /^\d+(\.\d+)?$/.test(x)) ? 0.55 : 0
    case 'website':
      return v.every((x) => /^https?:\/\//.test(x) || /^www\./.test(x)) ? 0.8 : 0
    case 'iban':
      return v.every((x) => /^[A-Z]{2}\d{2}/.test(x) && x.replace(/\s/g, '').length >= 14) ? 0.85 : 0
    case 'bic':
      return v.every((x) => /^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$/.test(x)) ? 0.85 : 0
    default:
      return 0
  }
}

// ─── AI fallback (Edge Function) ──────────────────────────────────────
// Called when heuristic confidence < 0.5. Sends headers + sample data
// to the Supabase Edge Function which calls OpenAI GPT-4o-mini.

export interface AIFallbackResult {
  mapping: Record<string, string>
  confidence: number
  reasoning: Record<string, string>
}

export async function aiFallbackMapping(
  sourceHeaders: string[],
  sampleRows: Record<string, any>[],
  targetFields: TargetField[],
  moduleName: string,
  edgeFunctionUrl: string,
): Promise<AIFallbackResult | null> {
  try {
    const response = await fetch(edgeFunctionUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sourceHeaders,
        sampleRows: sampleRows.slice(0, 5),
        targetFields: targetFields.map((f) => ({ key: f.key, label: f.label, required: f.required })),
        moduleName,
      }),
    })

    if (!response.ok) {
      console.error('AI fallback HTTP error:', response.status)
      return null
    }

    const data = await response.json()
    if (data.error) {
      console.error('AI fallback error:', data.error)
      return null
    }

    return {
      mapping: data.mapping || {},
      confidence: data.confidence || 0.5,
      reasoning: data.reasoning || {},
    }
  } catch (err) {
    console.error('AI fallback network error:', err)
    return null
  }
}

/**
 * Get human-readable French label for a confidence level.
 */
export function confidenceLabel(score: number): string {
  if (score >= 0.9) return 'Très fiable'
  if (score >= 0.75) return 'Fiable'
  if (score >= 0.6) return 'Probable'
  if (score >= 0.4) return 'Incertain'
  return 'Faible'
}

/**
 * Get color variant for confidence badge.
 */
export function confidenceVariant(score: number): 'success' | 'primary' | 'warning' | 'danger' {
  if (score >= 0.9) return 'success'
  if (score >= 0.75) return 'primary'
  if (score >= 0.5) return 'warning'
  return 'danger'
}
