import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Button, Card, Input, Select, Badge, EmptyState, SkeletonTable, PageHeader } from '@/components/ui'
import { getPosTerminals, createPosTerminal, openPosSession, closePosSession, getActiveSession, createPosTicket } from '@/lib/queries/posAdvanced'
import { getProducts } from '@/lib/queries/stock'
import { useToast } from '@/lib/toast'
import { formatCurrency } from '@/lib/utils'
import { Monitor, ShoppingCart, Trash2, Plus, Minus, CreditCard, Banknote, Lock } from 'lucide-react'
import type { PosTerminal, PosSession, Product } from '@/types'

type CartLine = {
  product_id: string
  description: string
  unit_price: number
  quantity: number
  vat_rate: number
  line_total: number
}

export function PosTerminalPage() {
  const { terminalId } = useParams<{ terminalId?: string }>()
  const navigate = useNavigate()
  const { t } = useTranslation('pos')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  const [terminals, setTerminals] = useState<PosTerminal[]>([])
  const [selectedTerminal, setSelectedTerminal] = useState<PosTerminal | null>(null)
  const [activeSession, setActiveSession] = useState<PosSession | null>(null)
  const [loading, setLoading] = useState(true)
  const [showOpenSession, setShowOpenSession] = useState(false)
  const [openingAmount, setOpeningAmount] = useState('0')
  const [showCloseSession, setShowCloseSession] = useState(false)
  const [closingAmount, setClosingAmount] = useState('0')
  const [cart, setCart] = useState<CartLine[]>([])
  const [search, setSearch] = useState('')
  const [products, setProducts] = useState<Product[]>([])

  useEffect(() => {
    (async () => {
      try {
        const prods = await getProducts()
        setProducts(prods as any)
      } catch (err: any) {
        toast('error', tCommon('toast.error'), err.message)
      }
    })()
  }, [toast, tCommon])
  const [showPayment, setShowPayment] = useState(false)
  const [paymentMethod, setPaymentMethod] = useState('cash')
  const [amountReceived, setAmountReceived] = useState('0')
  const [showNewTerminal, setShowNewTerminal] = useState(false)
  const [newTerminalName, setNewTerminalName] = useState('')
  const [newTerminalLocation, setNewTerminalLocation] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const terms = await getPosTerminals()
      setTerminals(terms)
      if (terminalId) {
        const term = terms.find(t => t.id === terminalId)
        if (term) {
          setSelectedTerminal(term)
          const session = await getActiveSession(term.id)
          setActiveSession(session)
        }
      } else if (terms.length > 0) {
        setSelectedTerminal(terms[0])
        const session = await getActiveSession(terms[0].id)
        setActiveSession(session)
      }
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [terminalId, toast, tCommon])

  useEffect(() => { load() }, [load])

  async function handleOpenSession() {
    if (!selectedTerminal) return
    try {
      const session = await openPosSession(selectedTerminal.id, Number(openingAmount))
      setActiveSession(session)
      setShowOpenSession(false)
      toast('success', tCommon('toast.success'), t('terminal.openSession'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleCloseSession() {
    if (!activeSession) return
    try {
      await closePosSession(activeSession.id, Number(closingAmount))
      setActiveSession(null)
      setShowCloseSession(false)
      setCart([])
      toast('success', tCommon('toast.success'), t('terminal.closeSession'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleCreateTerminal() {
    try {
      const term = await createPosTerminal({
        name: newTerminalName,
        warehouse_id: null,
        location: newTerminalLocation || null,
        active: true,
      } as any)
      setTerminals([...terminals, term])
      setSelectedTerminal(term)
      setShowNewTerminal(false)
      setNewTerminalName('')
      setNewTerminalLocation('')
      toast('success', tCommon('toast.success'), t('terminal.newTerminal'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function addToCart(product: Product) {
    const price = Number(product.sale_price || 0)
    const vatRate = Number(product.vat_rate || 0)
    const existing = cart.find(c => c.product_id === product.id)
    if (existing) {
      setCart(cart.map(c => c.product_id === product.id
        ? { ...c, quantity: c.quantity + 1, line_total: (c.quantity + 1) * c.unit_price }
        : c
      ))
    } else {
      setCart([...cart, {
        product_id: product.id,
        description: product.name,
        unit_price: price,
        quantity: 1,
        vat_rate: vatRate,
        line_total: price,
      }])
    }
  }

  function updateQty(productId: string, delta: number) {
    setCart(cart.map(c => {
      if (c.product_id !== productId) return c
      const newQty = Math.max(0, c.quantity + delta)
      return { ...c, quantity: newQty, line_total: newQty * c.unit_price }
    }).filter(c => c.quantity > 0))
  }

  function removeFromCart(productId: string) {
    setCart(cart.filter(c => c.product_id !== productId))
  }

  const subtotal = cart.reduce((sum, c) => sum + c.line_total, 0)
  const vatTotal = cart.reduce((sum, c) => sum + (c.line_total * c.vat_rate / 100), 0)
  const total = subtotal + vatTotal
  const change = Math.max(0, Number(amountReceived) - total)

  async function handlePayment() {
    if (!activeSession || !selectedTerminal) return
    if (Number(amountReceived) < total && paymentMethod === 'cash') {
      toast('error', tCommon('toast.error'), t('sale.insufficientAmount'))
      return
    }
    try {
      const ticketNumber = 'T-' + Date.now().toString().slice(-8)
      await createPosTicket({
        number: ticketNumber,
        session_id: activeSession.id,
        terminal_id: selectedTerminal.id,
        customer_id: null,
        date: new Date().toISOString(),
        subtotal,
        vat_total: vatTotal,
        total,
        payment_method: paymentMethod as any,
        amount_paid: Number(amountReceived),
        change_given: change,
        status: 'completed',
        invoice_id: null,
        notes: null,
      } as any, cart.map(c => ({
        product_id: c.product_id,
        description: c.description,
        quantity: c.quantity,
        unit_price: c.unit_price,
        vat_rate: c.vat_rate,
        line_total: c.line_total,
        tenant_id: null,
      }) as any))
      toast('success', tCommon('toast.success'), t('sale.ticketCreated'))
      setCart([])
      setShowPayment(false)
      setAmountReceived('0')
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  if (loading) {
    return (
      <div className="p-6">
        <PageHeader title={t('terminal.title')} />
        <SkeletonTable rows={5} cols={4} />
      </div>
    )
  }

  if (terminals.length === 0) {
    return (
      <div className="p-6">
        <PageHeader title={t('terminal.title')} action={
          <Button onClick={() => setShowNewTerminal(true)}><Plus className="w-4 h-4" /> {t('terminal.newTerminal')}</Button>
        } />
        <EmptyState icon={<Monitor className="w-8 h-8" />} title={t('terminal.noTerminals')} description={t('terminal.noTerminalsDescription')} />
        {showNewTerminal && (
          <Card title={t('terminal.newTerminal')}>
            <div className="space-y-4">
              <Input label={t('terminal.name')} value={newTerminalName} onChange={e => setNewTerminalName(e.target.value)} required />
              <Input label={t('terminal.location')} value={newTerminalLocation} onChange={e => setNewTerminalLocation(e.target.value)} />
              <div className="flex gap-2">
                <Button onClick={handleCreateTerminal}>{tCommon('actions.save')}</Button>
                <Button variant="secondary" onClick={() => setShowNewTerminal(false)}>{tCommon('actions.cancel')}</Button>
              </div>
            </div>
          </Card>
        )}
      </div>
    )
  }

  if (!selectedTerminal) {
    return (
      <div className="p-6">
        <PageHeader title={t('terminal.title')} />
        <Card>
          <div className="space-y-2">
            {terminals.map(term => (
              <button key={term.id} onClick={() => navigate(`/pos/terminal/${term.id}`)}
                className="w-full flex items-center justify-between p-4 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)] transition-colors">
                <div className="flex items-center gap-3">
                  <Monitor className="w-5 h-5 text-[var(--color-primary)]" />
                  <div className="text-left">
                    <p className="font-medium">{term.name}</p>
                    {term.location && <p className="text-sm text-[var(--color-text-secondary)]">{term.location}</p>}
                  </div>
                </div>
                {term.active ? <Badge variant="success">{t('terminal.active')}</Badge> : <Badge variant="neutral">—</Badge>}
              </button>
            ))}
          </div>
        </Card>
      </div>
    )
  }

  return (
    <div className="p-6">
      <PageHeader title={`${t('terminal.title')} — ${selectedTerminal.name}`}
        action={
          <div className="flex gap-2">
            <Select value={selectedTerminal.id} onChange={e => navigate(`/pos/terminal/${e.target.value}`)}
              options={terminals.map(t => ({ value: t.id, label: t.name }))} />
            <Button variant="secondary" onClick={() => setShowNewTerminal(true)}><Plus className="w-4 h-4" /></Button>
          </div>
        }
      />

      {!activeSession ? (
        <Card title={t('terminal.noActiveSession')}>
          <div className="space-y-4">
            <Input label={t('terminal.openingAmount')} type="number" step="0.01" value={openingAmount} onChange={e => setOpeningAmount(e.target.value)} />
            <Button onClick={() => setShowOpenSession(true)}><Lock className="w-4 h-4" /> {t('terminal.openSession')}</Button>
          </div>
          {showOpenSession && (
            <div className="mt-4 flex gap-2">
              <Button onClick={handleOpenSession}>{tCommon('actions.confirm')}</Button>
              <Button variant="secondary" onClick={() => setShowOpenSession(false)}>{tCommon('actions.cancel')}</Button>
            </div>
          )}
        </Card>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Left: Products */}
          <Card title={t('sale.title')}>
            <div className="mb-4">
              <input className="input" placeholder={t('sale.searchProduct')} value={search} onChange={e => setSearch(e.target.value)} />
            </div>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3 max-h-[500px] overflow-y-auto">
              {products.length === 0 ? (
                <p className="col-span-full text-center text-sm text-[var(--color-text-secondary)] py-8">{t('sale.noProducts')}</p>
              ) : (
                products
                  .filter(p => !search || p.name.toLowerCase().includes(search.toLowerCase()))
                  .map(product => (
                    <button key={product.id} onClick={() => addToCart(product)}
                      className="p-3 rounded-lg border border-[var(--color-border)] hover:border-[var(--color-primary)] hover:bg-[var(--color-neutral-50)] transition-colors text-left">
                      <p className="text-sm font-medium truncate">{product.name}</p>
                      <p className="text-xs text-[var(--color-text-secondary)]">{formatCurrency(Number(product.sale_price || 0))}</p>
                    </button>
                  ))
              )}
            </div>
          </Card>

          {/* Right: Cart */}
          <Card title={t('sale.cart')} action={
            <div className="flex gap-2">
              <Button variant="secondary" size="sm" onClick={() => setShowCloseSession(true)}><Lock className="w-4 h-4" /> {t('terminal.closeSession')}</Button>
            </div>
          }>
            {cart.length === 0 ? (
              <EmptyState icon={<ShoppingCart className="w-8 h-8" />} title={t('sale.cartEmpty')} description={t('sale.cartEmptyDescription')} />
            ) : (
              <>
                <div className="space-y-2 mb-4 max-h-[300px] overflow-y-auto">
                  {cart.map(line => (
                    <div key={line.product_id} className="flex items-center justify-between p-2 rounded-lg border border-[var(--color-border)]">
                      <div className="flex-1">
                        <p className="text-sm font-medium">{line.description}</p>
                        <p className="text-xs text-[var(--color-text-secondary)]">{formatCurrency(line.unit_price)} × {line.quantity}</p>
                      </div>
                      <div className="flex items-center gap-2">
                        <button onClick={() => updateQty(line.product_id, -1)} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><Minus className="w-4 h-4" /></button>
                        <span className="text-sm font-medium w-8 text-center">{line.quantity}</span>
                        <button onClick={() => updateQty(line.product_id, 1)} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><Plus className="w-4 h-4" /></button>
                        <span className="text-sm font-medium w-20 text-right">{formatCurrency(line.line_total)}</span>
                        <button onClick={() => removeFromCart(line.product_id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                      </div>
                    </div>
                  ))}
                </div>
                <div className="space-y-1 border-t border-[var(--color-border)] pt-4">
                  <div className="flex justify-between text-sm"><span>{t('sale.subtotal')}</span><span>{formatCurrency(subtotal)}</span></div>
                  <div className="flex justify-between text-sm"><span>{t('sale.vat')}</span><span>{formatCurrency(vatTotal)}</span></div>
                  <div className="flex justify-between text-lg font-bold"><span>{t('sale.total')}</span><span>{formatCurrency(total)}</span></div>
                </div>
                <Button className="w-full mt-4" onClick={() => setShowPayment(true)}><CreditCard className="w-4 h-4" /> {t('sale.pay')}</Button>
              </>
            )}
          </Card>
        </div>
      )}

      {/* Payment Modal */}
      {showPayment && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <Card title={t('sale.payment')} className="w-full max-w-md">
            <div className="space-y-4">
              <div className="text-center">
                <p className="text-3xl font-bold">{formatCurrency(total)}</p>
              </div>
              <Select label={t('sale.paymentMethod')} value={paymentMethod} onChange={e => setPaymentMethod(e.target.value)}
                options={[
                  { value: 'cash', label: t('sale.cash') },
                  { value: 'card', label: t('sale.card') },
                  { value: 'check', label: t('sale.check') },
                  { value: 'transfer', label: t('sale.transfer') },
                ]} />
              {paymentMethod === 'cash' && (
                <>
                  <Input label={t('sale.amountReceived')} type="number" step="0.01" value={amountReceived} onChange={e => setAmountReceived(e.target.value)} />
                  <div className="flex justify-between text-lg font-bold">
                    <span>{t('sale.change')}</span>
                    <span>{formatCurrency(change)}</span>
                  </div>
                </>
              )}
              <div className="flex gap-2">
                <Button className="flex-1" onClick={handlePayment}><Banknote className="w-4 h-4" /> {t('sale.pay')}</Button>
                <Button variant="secondary" onClick={() => setShowPayment(false)}>{t('sale.cancel')}</Button>
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* Close Session Modal */}
      {showCloseSession && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <Card title={t('terminal.closeSession')} className="w-full max-w-md">
            <div className="space-y-4">
              <Input label={t('terminal.closingAmount')} type="number" step="0.01" value={closingAmount} onChange={e => setClosingAmount(e.target.value)} />
              <div className="flex gap-2">
                <Button onClick={handleCloseSession}>{tCommon('actions.confirm')}</Button>
                <Button variant="secondary" onClick={() => setShowCloseSession(false)}>{tCommon('actions.cancel')}</Button>
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* New Terminal Modal */}
      {showNewTerminal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <Card title={t('terminal.newTerminal')} className="w-full max-w-md">
            <div className="space-y-4">
              <Input label={t('terminal.name')} value={newTerminalName} onChange={e => setNewTerminalName(e.target.value)} required />
              <Input label={t('terminal.location')} value={newTerminalLocation} onChange={e => setNewTerminalLocation(e.target.value)} />
              <div className="flex gap-2">
                <Button onClick={handleCreateTerminal}>{tCommon('actions.save')}</Button>
                <Button variant="secondary" onClick={() => setShowNewTerminal(false)}>{tCommon('actions.cancel')}</Button>
              </div>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
