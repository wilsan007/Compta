import { Button } from '@/components/ui'
import { CheckCircle2, ShieldCheck, AlertTriangle } from 'lucide-react'

// ============================================================
// W6 — la ligne de vérification d'un identifiant (SIRET, TVA, IBAN)
//
// Elle dit **ce qui a été vérifié** : « à la source » (INSEE SIRENE, VIES)
// seulement quand la fonction Edge le rapporte, sinon « format et clé de
// contrôle ». Un identifiant invalide est affiché comme tel, avec son motif —
// jamais présenté comme vérifié.
//
// Sans ce composant, les fonctions `verify-siret`, `verify-iban` et
// `validate-vat-vies` restaient déployées **sans aucun appelant**.
// ============================================================
export interface VerificationResult {
  valid: boolean
  api_source?: string
  error?: string
  message?: string
  company_name?: string | null
}

export interface VerificationLabels {
  check: string
  checking: string
  atSource: string
  formatOnly: string
  /** Contient `{{reason}}`, remplacé par le motif renvoyé par la fonction. */
  invalid: string
}

export function VerificationLine({ busy, disabled, onCheck, result, labels }: {
  busy: boolean
  disabled?: boolean
  onCheck: () => void
  result: VerificationResult | null
  labels: VerificationLabels
}) {
  const atSource = result?.api_source === 'INSEE SIRENE' || result?.api_source === 'VIES'
  const detail = result?.company_name ? ` — ${result.company_name}` : ''

  return (
    <div className="mt-1.5 flex items-center gap-2 flex-wrap">
      <Button variant="secondary" type="button" onClick={onCheck} disabled={busy || disabled}>
        <ShieldCheck className="w-3.5 h-3.5" /> {busy ? labels.checking : labels.check}
      </Button>
      {result && (result.valid ? (
        <span className="inline-flex items-center gap-1 text-xs text-[var(--color-success)]">
          <CheckCircle2 className="w-3.5 h-3.5" />
          {atSource ? labels.atSource : labels.formatOnly}{detail}
        </span>
      ) : (
        <span className="inline-flex items-center gap-1 text-xs text-[var(--color-danger)]">
          <AlertTriangle className="w-3.5 h-3.5" />
          {labels.invalid.replace('{{reason}}', result.error || result.message || '')}
        </span>
      ))}
    </div>
  )
}
