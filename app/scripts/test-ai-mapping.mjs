import { autoMapColumns, confidenceLabel, confidenceVariant } from '../src/lib/aiImportMapping.ts'

const customerFields = [
  { key: 'name', label: 'Nom', required: true },
  { key: 'email', label: 'Email' },
  { key: 'phone', label: 'Téléphone' },
  { key: 'postal_code', label: 'Code postal' },
  { key: 'country', label: 'Pays' },
  { key: 'city', label: 'Ville' },
]

// Test 1: En-têtes FR standards
const test1 = autoMapColumns(
  ['Nom du client', 'Email', 'Code postal', 'Téléphone portable', 'Pays', 'Ville'],
  [
    { 'Nom du client': 'Dupont SARL', 'Email': 'contact@dupont.fr', 'Code postal': '75001', 'Téléphone portable': '0612345678', 'Pays': 'France', 'Ville': 'Paris' },
    { 'Nom du client': 'Martin EURL', 'Email': 'info@martin.fr', 'Code postal': '69002', 'Téléphone portable': '0798765432', 'Pays': 'France', 'Ville': 'Lyon' },
  ],
  customerFields,
)
console.log('=== Test 1: En-têtes FR standards ===')
console.log('Confiance:', Math.round(test1.confidence * 100) + '%', confidenceLabel(test1.confidence))
test1.suggestions.forEach(s => console.log('  ' + s.fieldKey + ' -> ' + s.sourceColumn + ' (' + Math.round(s.confidence * 100) + '%) [' + s.reason + ']'))
console.log('Non mappés:', test1.unmappedFields)
console.log()

// Test 2: En-têtes EN + abréviations
const test2 = autoMapColumns(
  ['Customer Name', 'E-mail', 'ZIP', 'Mobile', 'Country', 'City'],
  [
    { 'Customer Name': 'Acme Corp', 'E-mail': 'hello@acme.com', 'ZIP': '10001', 'Mobile': '+12125551234', 'Country': 'USA', 'City': 'New York' },
  ],
  customerFields,
)
console.log('=== Test 2: En-têtes EN + abréviations ===')
console.log('Confiance:', Math.round(test2.confidence * 100) + '%', confidenceLabel(test2.confidence))
test2.suggestions.forEach(s => console.log('  ' + s.fieldKey + ' -> ' + s.sourceColumn + ' (' + Math.round(s.confidence * 100) + '%) [' + s.reason + ']'))
console.log()

// Test 3: En-têtes ambigus (devrait déclencher le fallback IA)
const test3 = autoMapColumns(
  ['Col1', 'Col2', 'Col3', 'Col4'],
  [
    { 'Col1': 'Dupont SARL', 'Col2': 'contact@dupont.fr', 'Col3': '75001', 'Col4': '0612345678' },
    { 'Col1': 'Martin EURL', 'Col2': 'info@martin.fr', 'Col3': '69002', 'Col4': '0798765432' },
  ],
  [
    { key: 'name', label: 'Nom', required: true },
    { key: 'email', label: 'Email' },
    { key: 'phone', label: 'Téléphone' },
    { key: 'postal_code', label: 'Code postal' },
  ],
)
console.log('=== Test 3: En-têtes ambigus (fallback IA requis) ===')
console.log('Confiance:', Math.round(test3.confidence * 100) + '%', confidenceLabel(test3.confidence))
test3.suggestions.forEach(s => console.log('  ' + s.fieldKey + ' -> ' + s.sourceColumn + ' (' + Math.round(s.confidence * 100) + '%) [' + s.reason + ']'))
console.log('Fallback IA nécessaire:', test3.confidence < 0.5 ? 'OUI' : 'NON')
console.log()

// Test 4: Produits avec en-têtes mixtes FR/EN
const test4 = autoMapColumns(
  ['Référence article', 'Désignation', 'PV HT', 'PA HT', 'Unité de vente', 'Famille', 'Code-barres'],
  [
    { 'Référence article': 'ART001', 'Désignation': 'Stylo bleu', 'PV HT': '2.50', 'PA HT': '1.20', 'Unité de vente': 'pièce', 'Famille': 'Papeterie', 'Code-barres': '3456789012345' },
  ],
  [
    { key: 'sku', label: 'Référence', required: true },
    { key: 'name', label: 'Nom' },
    { key: 'sale_price', label: 'Prix de vente' },
    { key: 'purchase_price', label: "Prix d'achat" },
    { key: 'unit', label: 'Unité' },
    { key: 'category', label: 'Catégorie' },
    { key: 'barcode', label: 'Code-barres' },
  ],
)
console.log('=== Test 4: Produits FR mixtes ===')
console.log('Confiance:', Math.round(test4.confidence * 100) + '%', confidenceLabel(test4.confidence))
test4.suggestions.forEach(s => console.log('  ' + s.fieldKey + ' -> ' + s.sourceColumn + ' (' + Math.round(s.confidence * 100) + '%) [' + s.reason + ']'))
console.log('Non mappés:', test4.unmappedFields)
console.log()

// Test 5: Comptabilité avec en-têtes Sage-like
const test5 = autoMapColumns(
  ['N° Pièce', 'Date écriture', 'Compte général', 'Libellé', 'Débit', 'Crédit', 'Journal'],
  [
    { 'N° Pièce': 'OD001', 'Date écriture': '15/01/2024', 'Compte général': '401000', 'Libellé': 'Achat fournisseur', 'Débit': '1500.00', 'Crédit': '', 'Journal': 'ACH' },
    { 'N° Pièce': 'OD002', 'Date écriture': '16/01/2024', 'Compte général': '411000', 'Libellé': 'Vente client', 'Débit': '', 'Crédit': '2500.00', 'Journal': 'VTE' },
  ],
  [
    { key: 'reference', label: 'N° Pièce', required: true },
    { key: 'date', label: 'Date' },
    { key: 'account_code', label: 'Compte' },
    { key: 'label', label: 'Libellé' },
    { key: 'debit', label: 'Débit' },
    { key: 'credit', label: 'Crédit' },
    { key: 'journal_code', label: 'Journal' },
  ],
)
console.log('=== Test 5: Comptabilité Sage-like ===')
console.log('Confiance:', Math.round(test5.confidence * 100) + '%', confidenceLabel(test5.confidence))
test5.suggestions.forEach(s => console.log('  ' + s.fieldKey + ' -> ' + s.sourceColumn + ' (' + Math.round(s.confidence * 100) + '%) [' + s.reason + ']'))
console.log('Non mappés:', test5.unmappedFields)

console.log()
console.log('=== Résumé Edge Function ===')
console.log('L Edge Function repond correctement (test curl OK)')
console.log('Erreur: insufficient_quota sur OpenAI -> il faut ajouter des credits sur platform.openai.com/billing')
