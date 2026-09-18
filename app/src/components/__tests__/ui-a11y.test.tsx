import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { Input, Select, Textarea, Modal, Button } from '@/components/ui'

describe('LOT7-07 — accessibilité des composants de base', () => {
  it('lie le label au champ Input (htmlFor/id)', () => {
    render(<Input label="Numéro de facture" required />)
    const field = screen.getByLabelText(/Numéro de facture/)
    expect(field.tagName).toBe('INPUT')
    expect(field).toHaveAttribute('aria-required', 'true')
  })

  it('lie le label au Select', () => {
    render(<Select label="Journal" options={[{ value: 'VT', label: 'Ventes' }]} />)
    expect(screen.getByLabelText('Journal').tagName).toBe('SELECT')
  })

  it('lie le label au Textarea', () => {
    render(<Textarea label="Commentaire" />)
    expect(screen.getByLabelText('Commentaire').tagName).toBe('TEXTAREA')
  })

  it('donne deux identifiants distincts à deux champs de même libellé', () => {
    render(<><Input label="Montant" /><Input label="Montant" /></>)
    const [a, b] = screen.getAllByLabelText('Montant')
    expect(a.id).not.toBe(b.id)
    expect(a.id).toBeTruthy()
  })

  it('expose la Modal comme boîte de dialogue nommée', () => {
    render(<Modal open title="Nouvelle écriture" onClose={() => {}}>contenu</Modal>)
    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveAttribute('aria-modal', 'true')
    expect(dialog).toHaveAccessibleName('Nouvelle écriture')
  })

  it('libelle le bouton de fermeture de la Modal', () => {
    render(<Modal open title="T" onClose={() => {}}>c</Modal>)
    expect(screen.getByRole('button', { name: /close|fermer/i })).toBeInTheDocument()
  })

  it('donne un nom accessible à un Button qui n\'affiche qu\'une icône', () => {
    render(<Button ariaLabel="Supprimer"><span aria-hidden="true">🗑</span></Button>)
    expect(screen.getByRole('button', { name: 'Supprimer' })).toBeInTheDocument()
  })
})
