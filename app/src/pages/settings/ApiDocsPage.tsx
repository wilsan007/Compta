// @ts-nocheck
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, Badge, Breadcrumb, Tabs, TabsList, TabsTrigger, TabsContent, Table, TableRow, TableCell } from '@/components/ui'
import { BookOpen, Code, Terminal, Copy, ChevronDown, ChevronRight,  Globe } from 'lucide-react'
import { useToast } from '@/lib/toast'

interface Endpoint {
  method: 'GET' | 'POST' | 'PUT' | 'DELETE'
  path: string
  description: string
  params?: { name: string; type: string; required: boolean; description: string }[]
  bodyExample?: string
  responseExample: string
  scopes: string[]
}

const ENDPOINTS: Endpoint[] = [
  {
    method: 'GET', path: '/v1/health', description: 'Vérifier le statut de l\'API',
    responseExample: `{ "status": "ok", "version": "v1", "timestamp": "2025-01-15T..." }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/invoices', description: 'Liste des factures avec pagination',
    params: [
      { name: 'page', type: 'integer', required: false, description: 'Numéro de page (défaut: 1)' },
      { name: 'limit', type: 'integer', required: false, description: 'Items par page (max: 100, défaut: 50)' },
      { name: 'status', type: 'string', required: false, description: 'Filtrer par statut: draft, sent, paid, cancelled' },
    ],
    responseExample: `{ "data": [{ "id": "uuid", "number": "INV-001", "status": "sent", "total": 1200.00, ... }], "page": 1, "limit": 50 }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/invoices/:id', description: 'Détail d\'une facture avec ses lignes',
    params: [{ name: 'id', type: 'uuid', required: true, description: 'Identifiant de la facture' }],
    responseExample: `{ "data": { "id": "uuid", "number": "INV-001", "invoice_lines": [...] } }`,
    scopes: ['read'],
  },
  {
    method: 'POST', path: '/v1/invoices', description: 'Créer une nouvelle facture',
    bodyExample: `{ "number": "INV-002", "customer_id": "uuid", "invoice_date": "2025-01-15", "due_date": "2025-02-14", "lines": [{ "product_id": "uuid", "quantity": 2, "unit_price": 100 }] }`,
    responseExample: `{ "data": { "id": "uuid", "number": "INV-002", "status": "draft" } }`,
    scopes: ['write'],
  },
  {
    method: 'GET', path: '/v1/customers', description: 'Liste des clients',
    responseExample: `{ "data": [{ "id": "uuid", "name": "Acme Corp", "email": "contact@acme.com" }] }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/customers/:id', description: 'Détail d\'un client',
    params: [{ name: 'id', type: 'uuid', required: true, description: 'Identifiant du client' }],
    responseExample: `{ "data": { "id": "uuid", "name": "Acme Corp", "email": "contact@acme.com", "vat_number": "FR12345678901" } }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/suppliers', description: 'Liste des fournisseurs',
    responseExample: `{ "data": [{ "id": "uuid", "name": "Fournisseur SA" }] }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/products', description: 'Liste des produits',
    responseExample: `{ "data": [{ "id": "uuid", "name": "Produit A", "price": 99.99, "sku": "SKU-001" }] }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/journal-entries', description: 'Liste des écritures comptables avec lignes',
    params: [
      { name: 'page', type: 'integer', required: false, description: 'Numéro de page' },
      { name: 'limit', type: 'integer', required: false, description: 'Items par page (max: 100)' },
    ],
    responseExample: `{ "data": [{ "id": "uuid", "number": "EC-001", "journal_lines": [...] }], "page": 1, "limit": 50 }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/vat-returns', description: 'Liste des déclarations TVA',
    responseExample: `{ "data": [{ "id": "uuid", "period": "2025-01", "output_vat": 2000, "input_vat": 1500, "vat_due": 500 }] }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/pay-slips', description: 'Liste des bulletins de paie',
    responseExample: `{ "data": [{ "id": "uuid", "period": "2025-01", "net_salary": 2400, "total_gross": 3000 }] }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/balance-sheet', description: 'Bilan comptable',
    params: [{ name: 'fiscal_year_id', type: 'uuid', required: true, description: 'Identifiant de l\'exercice' }],
    responseExample: `{ "data": { "asset_total": 500000, "liability_total": 500000, "balanced": true } }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/profit-loss', description: 'Compte de résultat',
    params: [{ name: 'fiscal_year_id', type: 'uuid', required: true, description: 'Identifiant de l\'exercice' }],
    responseExample: `{ "data": { "revenue_total": 500000, "expense_total": 400000, "result": 100000 } }`,
    scopes: ['read'],
  },
  {
    method: 'GET', path: '/v1/trial-balance', description: 'Balance générale',
    params: [
      { name: 'from', type: 'date', required: false, description: 'Date de début (YYYY-MM-DD)' },
      { name: 'to', type: 'date', required: false, description: 'Date de fin (YYYY-MM-DD)' },
    ],
    responseExample: `{ "data": { "accounts": [...], "total_debit": 100000, "total_credit": 100000, "balanced": true } }`,
    scopes: ['read'],
  },
]

const WEBHOOK_EVENTS = [
  { event: 'invoice.created', description: 'Déclenché à la création d\'une facture', payload: `{ "event": "invoice.created", "invoice": { "id": "uuid", "number": "INV-001", "total": 1200.00 } }` },
  { event: 'invoice.paid', description: 'Déclenché au paiement d\'une facture', payload: `{ "event": "invoice.paid", "invoice": { "id": "uuid", "number": "INV-001", "paid_amount": 1200.00 } }` },
  { event: 'invoice.overdue', description: 'Déclenché quand une facture passe en retard', payload: `{ "event": "invoice.overdue", "invoice": { "id": "uuid", "number": "INV-001", "days_overdue": 5 } }` },
  { event: 'purchase_invoice.received', description: 'Facture fournisseur reçue', payload: `{ "event": "purchase_invoice.received", "invoice": { "id": "uuid", "supplier": "Fournisseur SA", "amount": 500.00 } }` },
  { event: 'payment.received', description: 'Paiement client reçu', payload: `{ "event": "payment.received", "payment": { "id": "uuid", "amount": 1200.00, "invoice_id": "uuid" } }` },
  { event: 'payslip.ready', description: 'Bulletin de paie généré', payload: `{ "event": "payslip.ready", "payslip": { "id": "uuid", "period": "2025-01", "net_salary": 2400.00 } }` },
  { event: 'dsn.submitted', description: 'DSN transmise', payload: `{ "event": "dsn.submitted", "dsn": { "id": "uuid", "period": "2025-01", "status": "submitted" } }` },
  { event: 'vat_return.submitted', description: 'Déclaration TVA soumise', payload: `{ "event": "vat_return.submitted", "vat_return": { "id": "uuid", "period": "2025-01", "vat_due": 500.00 } }` },
  { event: 'fiscal_year.closed', description: 'Exercice clôturé', payload: `{ "event": "fiscal_year.closed", "fiscal_year": { "id": "uuid", "code": "2024", "result": 100000 } }` },
]

const METHOD_COLORS: Record<string, string> = {
  GET: 'bg-[var(--color-primary)] text-white',
  POST: 'bg-[var(--color-success)] text-white',
  PUT: 'bg-[var(--color-warning)] text-white',
  DELETE: 'bg-[var(--color-danger)] text-white',
}

export function ApiDocsPage() {
  const { t } = useTranslation()
  const { toast } = useToast()
  const [expanded, setExpanded] = useState<string | null>(null)
  const [tryEndpoint, setTryEndpoint] = useState<Endpoint | null>(null)
  const [apiKey, setApiKey] = useState('')
  const [testResult, setTestResult] = useState<string | null>(null)
  const [testing, setTesting] = useState(false)
  const [baseUrl, setBaseUrl] = useState('https://your-project.supabase.co/functions/v1/public-api')

  function copyToClipboard(text: string) {
    navigator.clipboard.writeText(text)
    toast('success', 'Copié', '')
  }

  function generateCurl(ep: Endpoint): string {
    const url = `${baseUrl}${ep.path}`
    let cmd = `curl -X ${ep.method} "${url}"`
    cmd += ` \\\n  -H "X-API-Key: ${apiKey || 'YOUR_API_KEY'}"`
    cmd += ` \\\n  -H "Content-Type: application/json"`
    if (ep.bodyExample) {
      cmd += ` \\\n  -d '${ep.bodyExample}'`
    }
    return cmd
  }

  async function handleTest(ep: Endpoint) {
    setTesting(true)
    setTestResult(null)
    try {
      const url = `${baseUrl}${ep.path}`
      const opts: RequestInit = {
        method: ep.method,
        headers: {
          'X-API-Key': apiKey,
          'Content-Type': 'application/json',
        },
      }
      if (ep.bodyExample && ep.method !== 'GET') {
        opts.body = ep.bodyExample
      }
      const res = await fetch(url, opts)
      const data = await res.text()
      setTestResult(`Status: ${res.status}\n\n${JSON.stringify(JSON.parse(data), null, 2)}`)
    } catch (err: any) {
      setTestResult(`Error: ${err.message}`)
    } finally {
      setTesting(false)
    }
  }

  return (
    <div className="space-y-6">
      <Breadcrumb items={[{ label: t('nav.settings'), href: '/settings' }, { label: 'Documentation API' }]} />
      <PageHeader title="Documentation API" description="API REST publique pour intégrations tierces" />

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview"><BookOpen className="w-4 h-4 mr-1" /> Vue d'ensemble</TabsTrigger>
          <TabsTrigger value="endpoints"><Code className="w-4 h-4 mr-1" /> Endpoints</TabsTrigger>
          <TabsTrigger value="webhooks"><Globe className="w-4 h-4 mr-1" /> Webhooks</TabsTrigger>
          <TabsTrigger value="sandbox"><Terminal className="w-4 h-4 mr-1" /> Sandbox</TabsTrigger>
        </TabsList>

        {/* Vue d'ensemble */}
        <TabsContent value="overview" className="space-y-4">
          <Card className="p-6 space-y-4">
            <h2 className="text-lg font-semibold">Authentification</h2>
            <p className="text-sm text-[var(--color-text-secondary)]">
              Toutes les requêtes doivent inclure une clé API dans l'en-tête <code className="px-1 py-0.5 bg-[var(--color-neutral-100)] rounded font-mono text-xs">X-API-Key</code>.
              Créez une clé depuis la page <a href="/settings/api-webhooks" className="text-[var(--color-primary)] underline">API & Webhooks</a>.
            </p>
            <div className="bg-[var(--color-neutral-900)] text-[var(--color-neutral-50)] p-4 rounded-lg font-mono text-xs overflow-x-auto">
              <div className="flex items-center justify-between mb-2">
                <span className="text-[var(--color-neutral-400)]"># Exemple d'authentification</span>
                <button onClick={() => copyToClipboard('curl -H "X-API-Key: your_key_here" https://...')} className="text-[var(--color-neutral-400)] hover:text-white"><Copy className="w-3 h-3" /></button>
              </div>
              <pre>curl -X GET "https://your-project.supabase.co/functions/v1/public-api/v1/invoices" \
  -H "X-API-Key: your_api_key_here"</pre>
            </div>
          </Card>

          <Card className="p-6 space-y-4">
            <h2 className="text-lg font-semibold">Rate Limiting</h2>
            <div className="grid grid-cols-3 gap-4">
              <div className="text-center p-4 border border-[var(--color-border)] rounded-lg">
                <div className="text-2xl font-bold text-[var(--color-primary)]">100</div>
                <div className="text-xs text-[var(--color-text-secondary)]">req/min</div>
              </div>
              <div className="text-center p-4 border border-[var(--color-border)] rounded-lg">
                <div className="text-2xl font-bold text-[var(--color-primary)]">X-RateLimit</div>
                <div className="text-xs text-[var(--color-text-secondary)]">en-têtes inclus</div>
              </div>
              <div className="text-center p-4 border border-[var(--color-border)] rounded-lg">
                <div className="text-2xl font-bold text-[var(--color-danger)]">429</div>
                <div className="text-xs text-[var(--color-text-secondary)]">si dépassé</div>
              </div>
            </div>
          </Card>

          <Card className="p-6 space-y-4">
            <h2 className="text-lg font-semibold">Pagination</h2>
            <p className="text-sm text-[var(--color-text-secondary)]">
              Les endpoints de liste supportent la pagination via les paramètres <code className="px-1 py-0.5 bg-[var(--color-neutral-100)] rounded font-mono text-xs">page</code> et <code className="px-1 py-0.5 bg-[var(--color-neutral-100)] rounded font-mono text-xs">limit</code>.
              Maximum 100 items par page.
            </p>
          </Card>

          <Card className="p-6 space-y-4">
            <h2 className="text-lg font-semibold">Codes d'erreur</h2>
            <Table headers={['Code', 'Description']}>
              <TableRow><TableCell><Badge variant="success">200</Badge></TableCell><TableCell className="text-sm">Succès</TableCell></TableRow>
              <TableRow><TableCell><Badge variant="success">201</Badge></TableCell><TableCell className="text-sm">Créé avec succès</TableCell></TableRow>
              <TableRow><TableCell><Badge variant="warning">400</Badge></TableCell><TableCell className="text-sm">Requête invalide</TableCell></TableRow>
              <TableRow><TableCell><Badge variant="danger">401</Badge></TableCell><TableCell className="text-sm">Clé API manquante ou invalide</TableCell></TableRow>
              <TableRow><TableCell><Badge variant="danger">404</Badge></TableCell><TableCell className="text-sm">Ressource non trouvée</TableCell></TableRow>
              <TableRow><TableCell><Badge variant="danger">429</Badge></TableCell><TableCell className="text-sm">Rate limit dépassé</TableCell></TableRow>
              <TableRow><TableCell><Badge variant="danger">500</Badge></TableCell><TableCell className="text-sm">Erreur interne</TableCell></TableRow>
            </Table>
          </Card>
        </TabsContent>

        {/* Endpoints */}
        <TabsContent value="endpoints" className="space-y-3">
          {ENDPOINTS.map((ep) => {
            const key = `${ep.method}-${ep.path}`
            const isExpanded = expanded === key
            return (
              <Card key={key} className="overflow-hidden">
                <button
                  onClick={() => setExpanded(isExpanded ? null : key)}
                  className="w-full flex items-center gap-3 p-4 hover:bg-[var(--color-neutral-50)] text-left"
                >
                  {isExpanded ? <ChevronDown className="w-4 h-4 flex-shrink-0" /> : <ChevronRight className="w-4 h-4 flex-shrink-0" />}
                  <span className={`px-2 py-1 rounded text-xs font-bold font-mono ${METHOD_COLORS[ep.method]}`}>{ep.method}</span>
                  <code className="text-sm font-mono flex-1">{ep.path}</code>
                  <span className="text-xs text-[var(--color-text-secondary)] hidden md:block">{ep.description}</span>
                  <div className="flex gap-1">{ep.scopes.map(s => <Badge key={s} variant="neutral">{s}</Badge>)}</div>
                </button>
                {isExpanded && (
                  <div className="p-4 border-t border-[var(--color-border)] space-y-4">
                    <p className="text-sm">{ep.description}</p>
                    {ep.params && ep.params.length > 0 && (
                      <div>
                        <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">Paramètres</h4>
                        <div className="space-y-1">
                          {ep.params.map(p => (
                            <div key={p.name} className="flex items-start gap-2 text-sm">
                              <code className="font-mono text-xs bg-[var(--color-neutral-100)] px-1.5 py-0.5 rounded">{p.name}</code>
                              <Badge variant={p.required ? 'danger' : 'neutral'}>{p.required ? 'requis' : 'optionnel'}</Badge>
                              <span className="text-xs text-[var(--color-text-secondary)]">{p.type}</span>
                              <span className="text-xs flex-1">{p.description}</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                    {ep.bodyExample && (
                      <div>
                        <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">Corps de la requête</h4>
                        <div className="bg-[var(--color-neutral-900)] text-[var(--color-neutral-50)] p-3 rounded-lg font-mono text-xs overflow-x-auto">
                          <button onClick={() => copyToClipboard(ep.bodyExample!)} className="float-right text-[var(--color-neutral-400)] hover:text-white"><Copy className="w-3 h-3" /></button>
                          <pre>{ep.bodyExample}</pre>
                        </div>
                      </div>
                    )}
                    <div>
                      <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">Réponse</h4>
                      <div className="bg-[var(--color-neutral-900)] text-[var(--color-neutral-50)] p-3 rounded-lg font-mono text-xs overflow-x-auto">
                        <button onClick={() => copyToClipboard(ep.responseExample)} className="float-right text-[var(--color-neutral-400)] hover:text-white"><Copy className="w-3 h-3" /></button>
                        <pre>{ep.responseExample}</pre>
                      </div>
                    </div>
                    <div>
                      <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">cURL</h4>
                      <div className="bg-[var(--color-neutral-900)] text-[var(--color-neutral-50)] p-3 rounded-lg font-mono text-xs overflow-x-auto">
                        <button onClick={() => copyToClipboard(generateCurl(ep))} className="float-right text-[var(--color-neutral-400)] hover:text-white"><Copy className="w-3 h-3" /></button>
                        <pre>{generateCurl(ep)}</pre>
                      </div>
                    </div>
                    <Button size="sm" variant="outline" onClick={() => { setTryEndpoint(ep); setTestResult(null) }}>
                      <Terminal className="w-3 h-3 mr-1" /> Tester cet endpoint
                    </Button>
                  </div>
                )}
              </Card>
            )
          })}
        </TabsContent>

        {/* Webhooks */}
        <TabsContent value="webhooks" className="space-y-4">
          <Card className="p-6 space-y-4">
            <h2 className="text-lg font-semibold">Webhooks sortants</h2>
            <p className="text-sm text-[var(--color-text-secondary)]">
              Configurez des URLs de webhook pour recevoir des notifications en temps réel quand des événements se produisent.
              Chaque requête est signée avec HMAC-SHA256 dans l'en-tête <code className="px-1 py-0.5 bg-[var(--color-neutral-100)] rounded font-mono text-xs">X-Webhook-Signature</code>.
            </p>
            <div className="bg-[var(--color-neutral-900)] text-[var(--color-neutral-50)] p-4 rounded-lg font-mono text-xs overflow-x-auto">
              <pre>{`// Vérification de signature (Node.js)
const crypto = require('crypto')
const expected = crypto.createHmac('sha256', WEBHOOK_SECRET)
  .update(JSON.stringify(body))
  .digest('hex')
if (req.headers['x-webhook-signature'] !== expected) {
  return res.status(401).send('Invalid signature')
}`}</pre>
            </div>
          </Card>

          <Card className="p-6 space-y-3">
            <h3 className="font-semibold">Événements disponibles</h3>
            {WEBHOOK_EVENTS.map(we => (
              <div key={we.event} className="border border-[var(--color-border)] rounded-lg p-3">
                <div className="flex items-center gap-2 mb-2">
                  <code className="font-mono text-xs bg-[var(--color-primary)] text-white px-2 py-1 rounded">{we.event}</code>
                  <span className="text-sm text-[var(--color-text-secondary)]">{we.description}</span>
                </div>
                <div className="bg-[var(--color-neutral-900)] text-[var(--color-neutral-50)] p-2 rounded font-mono text-xs overflow-x-auto">
                  <button onClick={() => copyToClipboard(we.payload)} className="float-right text-[var(--color-neutral-400)] hover:text-white"><Copy className="w-3 h-3" /></button>
                  <pre>{we.payload}</pre>
                </div>
              </div>
            ))}
          </Card>

          <Card className="p-6 space-y-3">
            <h3 className="font-semibold">Comportement de livraison</h3>
            <ul className="text-sm space-y-2 text-[var(--color-text-secondary)]">
              <li>• Timeout : 30 secondes par requête</li>
              <li>• Retry : 3 tentatives avec backoff exponentiel (1s, 5s, 30s)</li>
              <li>• Méthode : POST avec corps JSON</li>
              <li>• En-têtes : <code className="font-mono text-xs">X-Webhook-Event</code>, <code className="font-mono text-xs">X-Webhook-Signature</code>, <code className="font-mono text-xs">X-Webhook-Delivery</code></li>
              <li>• Code de succès attendu : 2xx</li>
              <li>• Logs de livraison consultables dans l'onglet API & Webhooks → Logs</li>
            </ul>
          </Card>
        </TabsContent>

        {/* Sandbox */}
        <TabsContent value="sandbox" className="space-y-4">
          <Card className="p-6 space-y-4">
            <h2 className="text-lg font-semibold">Sandbox interactive</h2>
            <div className="space-y-3">
              <div>
                <label className="text-sm font-medium">URL de base</label>
                <Input value={baseUrl} onChange={(e) => setBaseUrl(e.target.value)} className="font-mono text-xs" />
              </div>
              <div>
                <label className="text-sm font-medium">Clé API</label>
                <Input type="password" value={apiKey} onChange={(e) => setApiKey(e.target.value)} placeholder="sk_live_..." className="font-mono text-xs" />
              </div>
              <div>
                <label className="text-sm font-medium">Endpoint</label>
                <Select value={tryEndpoint?.path || ''} onChange={(e) => {
                  const ep = ENDPOINTS.find(x => x.path === e.target.value)
                  setTryEndpoint(ep || null)
                  setTestResult(null)
                }}>
                  <option value="">Sélectionner un endpoint...</option>
                  {ENDPOINTS.map(ep => <option key={ep.path} value={ep.path}>{ep.method} {ep.path}</option>)}
                </Select>
              </div>
              {tryEndpoint && (
                <>
                  {tryEndpoint.params && tryEndpoint.params.length > 0 && (
                    <div className="space-y-2">
                      <label className="text-sm font-medium">Paramètres</label>
                      {tryEndpoint.params.map(p => (
                        <div key={p.name} className="flex items-center gap-2">
                          <code className="font-mono text-xs w-32">{p.name}</code>
                          <Input placeholder={p.type} className="flex-1" />
                        </div>
                      ))}
                    </div>
                  )}
                  <div className="flex gap-2">
                    <Button onClick={() => handleTest(tryEndpoint)} disabled={testing || !apiKey}>
                      {testing ? 'Test en cours...' : 'Envoyer la requête'}
                    </Button>
                    <Button variant="outline" onClick={() => copyToClipboard(generateCurl(tryEndpoint))}>
                      <Copy className="w-4 h-4 mr-1" /> Copier cURL
                    </Button>
                  </div>
                  {testResult && (
                    <div className="bg-[var(--color-neutral-900)] text-[var(--color-neutral-50)] p-4 rounded-lg font-mono text-xs overflow-x-auto">
                      <pre>{testResult}</pre>
                    </div>
                  )}
                </>
              )}
            </div>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
