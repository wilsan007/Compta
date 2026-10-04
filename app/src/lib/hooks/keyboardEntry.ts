// UX-05 : Saisie comptable au clavier
// Permet une saisie entièrement au clavier dans JournalSaisiePage
import { useState, useCallback, type KeyboardEvent } from 'react'

export interface JournalLine {
  id?: string
  account_code: string
  account_name: string
  debit: number
  credit: number
  description?: string
}

export function useKeyboardEntry(
  initialLines: JournalLine[] = [],
  onAllLinesComplete?: (lines: JournalLine[]) => void
) {
  const [lines, setLines] = useState<JournalLine[]>(initialLines.length > 0 ? initialLines : [
    { account_code: '', account_name: '', debit: 0, credit: 0 },
  ])
  const [activeRowIndex, setActiveRowIndex] = useState(0)
  const [activeField, setActiveField] = useState<'account_code' | 'debit' | 'credit' | 'description'>('account_code')

  // Entrée = valider et passer à la ligne suivante
  const handleKeyDown = useCallback((e: KeyboardEvent<HTMLInputElement | HTMLSelectElement>, rowIndex: number, field: string) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      const currentLine = lines[rowIndex]

      // Si on est sur le dernier champ et qu'il y a un compte, créer une nouvelle ligne
      if (field === 'credit' || (field === 'debit' && currentLine.credit > 0)) {
        // Vérifier l'équilibre
        const totalDebit = lines.reduce((s, l) => s + Number(l.debit || 0), 0)
        const totalCredit = lines.reduce((s, l) => s + Number(l.credit || 0), 0)

        // Auto-équilibrer la dernière ligne si possible
        if (Math.abs(totalDebit - totalCredit) > 0.01 && rowIndex === lines.length - 1) {
          const diff = totalDebit - totalCredit
          if (diff > 0) {
            currentLine.credit = diff
          } else {
            currentLine.debit = Math.abs(diff)
          }
          setLines([...lines])
        }

        // Si équilibré, créer une nouvelle ligne
        const newTotalDebit = lines.reduce((s, l) => s + Number(l.debit || 0), 0)
        const newTotalCredit = lines.reduce((s, l) => s + Number(l.credit || 0), 0)
        if (Math.abs(newTotalDebit - newTotalCredit) < 0.01) {
          onAllLinesComplete?.(lines)
        }

        // Ajouter une nouvelle ligne vide
        setLines([...lines, { account_code: '', account_name: '', debit: 0, credit: 0 }])
        setActiveRowIndex(rowIndex + 1)
        setActiveField('account_code')
      } else {
        // Passer au champ suivant
        const fieldOrder = ['account_code', 'description', 'debit', 'credit'] as const
        const currentIdx = fieldOrder.indexOf(field as any)
        if (currentIdx < fieldOrder.length - 1) {
          setActiveField(fieldOrder[currentIdx + 1])
        }
      }
    }

    // Tab = champ suivant (comportement natif, mais on gère le retour à la ligne)
    if (e.key === 'Tab' && !e.shiftKey) {
      const currentLine = lines[rowIndex]
      if (field === 'credit' && rowIndex === lines.length - 1 && currentLine.account_code) {
        e.preventDefault()
        setLines([...lines, { account_code: '', account_name: '', debit: 0, credit: 0 }])
        setActiveRowIndex(rowIndex + 1)
        setActiveField('account_code')
      }
    }

    // F2 = dupliquer la ligne courante
    if (e.key === 'F2') {
      e.preventDefault()
      const currentLine = lines[rowIndex]
      const newLine = { ...currentLine, id: undefined }
      const newLines = [...lines]
      newLines.splice(rowIndex + 1, 0, newLine)
      setLines(newLines)
      setActiveRowIndex(rowIndex + 1)
    }

    // Ctrl+D = supprimer la ligne courante
    if (e.key === 'd' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault()
      if (lines.length > 1) {
        const newLines = lines.filter((_, i) => i !== rowIndex)
        setLines(newLines)
        setActiveRowIndex(Math.max(0, rowIndex - 1))
      }
    }
  }, [lines, onAllLinesComplete])

  // Mémoriser la dernière écriture (écritures types)
  const saveAsTemplate = useCallback((name: string) => {
    const template = { name, lines }
    const existing = JSON.parse(localStorage.getItem('journal_templates') || '[]')
    existing.push(template)
    localStorage.setItem('journal_templates', JSON.stringify(existing))
  }, [lines])

  const loadTemplate = useCallback((name: string): JournalLine[] | null => {
    const existing = JSON.parse(localStorage.getItem('journal_templates') || '[]')
    const template = existing.find((t: any) => t.name === name)
    if (template) {
      setLines(template.lines)
      return template.lines
    }
    return null
  }, [])

  const getTemplates = useCallback(() => {
    return JSON.parse(localStorage.getItem('journal_templates') || '[]')
  }, [])

  // Complétion automatique du compte
  const [accountSuggestions, setAccountSuggestions] = useState<any[]>([])
  const searchAccounts = useCallback(async (query: string) => {
    if (query.length < 1) {
      setAccountSuggestions([])
      return
    }
    // La recherche sera branchée sur la fonction existante
    setAccountSuggestions([])
  }, [])

  return {
    lines,
    setLines,
    activeRowIndex,
    activeField,
    setActiveField,
    handleKeyDown,
    saveAsTemplate,
    loadTemplate,
    getTemplates,
    accountSuggestions,
    searchAccounts,
  }
}
