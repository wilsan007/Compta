import { useState, useRef, useEffect } from 'react'
import { Sparkles, X, Send, TrendingUp, AlertCircle, Receipt, Wallet } from 'lucide-react'
import { cn } from '@/lib/utils'

interface Message {
  id: string
  role: 'user' | 'assistant'
  content: string
  suggestions?: { icon: React.ComponentType<{ className?: string }>; label: string; action?: () => void }[]
}

const initialMessages: Message[] = [
  {
    id: '1',
    role: 'assistant',
    content: 'Bonjour ! Je suis votre assistant comptable IA. Je peux vous aider avec :\n\n• Analyser vos finances\n• Créer des factures\n• Suivre les paiements\n• Optimiser votre trésorerie\n• Préparer votre TVA\n\nQue puis-je faire pour vous aujourd\'hui ?',
    suggestions: [
      { icon: TrendingUp, label: 'Analyser ma trésorerie' },
      { icon: AlertCircle, label: 'Factures en retard ?' },
      { icon: Receipt, label: 'Créer une facture' },
      { icon: Wallet, label: 'Réconcilier la banque' },
    ],
  },
]

export function AIAssistant({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [messages, setMessages] = useState<Message[]>(initialMessages)
  const [input, setInput] = useState('')
  const [isTyping, setIsTyping] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [messages, isTyping])

  function send(content: string) {
    if (!content.trim()) return
    const userMsg: Message = { id: Date.now().toString(), role: 'user', content }
    setMessages((m) => [...m, userMsg])
    setInput('')
    setIsTyping(true)

    setTimeout(() => {
      const responses: Record<string, string> = {
        'trésorerie': 'Votre trésorerie est saine. Solde bancaire: 45 200 €. Encaissements ce mois: +12 500 €. Décaissements: -8 300 €. Flux net positif de +4 200 €. 💡 Conseil: 3 factures sont en retard pour un total de 3 800 €, relancez-les pour améliorer votre cash.',
        'retard': '⚠️ Vous avez 3 factures en retard:\n\n• FAC-2024-042 - Client ABC - 1 200 € (15 jours)\n• FAC-2024-039 - Société XYZ - 1 800 € (8 jours)\n• FAC-2024-035 - Entreprise DEF - 800 € (22 jours)\n\nTotal: 3 800 €. Voulez-vous que je prépare des emails de relance ?',
        'facture': 'Pour créer une facture:\n1. Sélectionnez un client (ou créez-en un)\n2. Ajoutez vos lignes (produits/services)\n3. Vérifiez la TVA (20% par défaut)\n4. Envoyez par email ou téléchargez en PDF\n\nJe peux pré-remplir certaines informations si vous me donnez le nom du client et les prestations.',
        'réconcil': 'Rapprochement bancaire: 12 transactions en attente. 8 ont été auto-catégorisées par les règles bancaires. 4 nécessitent votre attention:\n\n• Virement reçu - 2 500 € → Client à identifier\n• Prélèvement - 180 € → Fournisseur inconnu\n• Frais bancaires - 15 € → Compte 627\n• Remboursement - 340 € → À catégoriser',
      }

      const lower = content.toLowerCase()
      let response = 'Je comprends votre demande. En tant qu\'assistant IA, je peux analyser vos données comptables et vous fournir des insights. Cette fonctionnalité sera connectée à votre base de données pour des réponses personnalisées.'

      for (const [key, val] of Object.entries(responses)) {
        if (lower.includes(key)) {
          response = val
          break
        }
      }

      const aiMsg: Message = { id: (Date.now() + 1).toString(), role: 'assistant', content: response }
      setMessages((m) => [...m, aiMsg])
      setIsTyping(false)
    }, 1200)
  }

  if (!open) return null

  return (
    <>
      <div className="fixed inset-0 bg-black/20 z-[8999]" onClick={onClose} />
      <div className="fixed right-0 top-0 bottom-0 w-[400px] max-w-[90vw] bg-[var(--color-surface)] border-l border-[var(--color-border)] z-[9000] flex flex-col animate-slide-in-right">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--color-border)]">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center">
              <Sparkles className="w-4 h-4 text-white" />
            </div>
            <div>
              <p className="text-sm font-semibold text-[var(--color-text)]">Assistant IA</p>
              <p className="text-xs text-[var(--color-success)] flex items-center gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-[var(--color-success)]"></span> En ligne
              </p>
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-md text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]">
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Messages */}
        <div ref={scrollRef} className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
          {messages.map((msg) => (
            <div key={msg.id} className={cn('flex', msg.role === 'user' ? 'justify-end' : 'justify-start')}>
              <div className={cn(
                'max-w-[85%] rounded-xl px-3.5 py-2.5 text-sm',
                msg.role === 'user'
                  ? 'bg-[var(--color-primary)] text-white'
                  : 'bg-[var(--color-neutral-100)] text-[var(--color-text)]'
              )}>
                <p className="whitespace-pre-line">{msg.content}</p>
                {msg.suggestions && (
                  <div className="mt-3 space-y-1.5">
                    {msg.suggestions.map((s, i) => (
                      <button
                        key={i}
                        onClick={() => send(s.label)}
                        className="w-full flex items-center gap-2 px-3 py-2 rounded-lg bg-[var(--color-surface)] border border-[var(--color-border)] text-xs font-medium text-[var(--color-text)] hover:border-[var(--color-primary)] hover:bg-[rgba(0,102,204,0.05)] transition-colors"
                      >
                        <s.icon className="w-3.5 h-3.5 text-[var(--color-primary)]" />
                        {s.label}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
          ))}
          {isTyping && (
            <div className="flex items-center gap-2 text-[var(--color-text-secondary)]">
              <div className="flex gap-1">
                <span className="w-2 h-2 rounded-full bg-[var(--color-text-secondary)] animate-bounce" style={{ animationDelay: '0ms' }}></span>
                <span className="w-2 h-2 rounded-full bg-[var(--color-text-secondary)] animate-bounce" style={{ animationDelay: '150ms' }}></span>
                <span className="w-2 h-2 rounded-full bg-[var(--color-text-secondary)] animate-bounce" style={{ animationDelay: '300ms' }}></span>
              </div>
              <span className="text-xs">L'assistant réfléchit...</span>
            </div>
          )}
        </div>

        {/* Input */}
        <div className="border-t border-[var(--color-border)] p-3">
          <div className="flex items-end gap-2">
            <textarea
              className="flex-1 resize-none rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm text-[var(--color-text)] outline-none focus:border-[var(--color-primary)] min-h-[40px] max-h-[120px]"
              placeholder="Posez votre question..."
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault()
                  send(input)
                }
              }}
              rows={1}
            />
            <button
              onClick={() => send(input)}
              disabled={!input.trim()}
              className="p-2 rounded-lg bg-[var(--color-primary)] text-white disabled:opacity-40 hover:bg-[var(--color-primary-dark)] transition-colors"
            >
              <Send className="w-4 h-4" />
            </button>
          </div>
          <p className="text-xs text-[var(--color-text-secondary)] mt-2 text-center">
            L'IA peut faire des erreurs. Vérifiez les informations importantes.
          </p>
        </div>
      </div>
    </>
  )
}
