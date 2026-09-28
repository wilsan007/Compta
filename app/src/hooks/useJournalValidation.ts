import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { isSegregationEnforced, validateJournalEntries } from '@/lib/queries/accounting'

/**
 * X2/C4 (décision D-A) : valider des écritures saisies depuis n'importe quel
 * écran (écritures, saisie par journal, brouillard). La base rend un verdict
 * PAR écriture ; chaque refus est affiché avec sa pièce et sa raison.
 * `segregation` dit si « Enregistrer et valider » peut être offert.
 */
export function useJournalValidation(onDone: () => unknown) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [validating, setValidating] = useState(false)
  const [segregation, setSegregation] = useState(true)

  useEffect(() => {
    isSegregationEnforced().then(setSegregation).catch(() => setSegregation(true))
  }, [])

  const validate = useCallback(async (ids: string[]) => {
    if (!ids.length) return
    setValidating(true)
    try {
      const verdicts = await validateJournalEntries(ids)
      const refused = verdicts.filter((v) => !v.ok)
      const validated = verdicts.length - refused.length
      if (validated) toast('success', tCommon('toast.success'), t('entryValidation.validated', { count: validated }))
      for (const v of refused) {
        toast('error', tCommon('toast.error'), t('entryValidation.refused', { number: v.number ?? v.id, error: v.error }))
      }
      await onDone()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setValidating(false)
    }
  }, [onDone, t, tCommon, toast])

  return { validate, validating, segregation }
}
