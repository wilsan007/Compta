import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor, fireEvent, act } from '@testing-library/react'
import { useState } from 'react'
import { Input, Select, Textarea, Modal, Button, SortableTable, TableRow, TableCell } from '@/components/ui'

// `src/test/setup.ts` remplace globalement `@/lib/toast` par un mock : on restaure le
// vrai module ici, puisque c'est précisément son rendu que ces tests vérifient.
vi.mock('@/lib/toast', async (importOriginal) => await importOriginal<object>())
import { ToastProvider, useToast } from '@/lib/toast'

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

// ============================================================
// LOT7-07 — navigation clavier dans les boîtes de dialogue
// ============================================================
describe('Modal — clavier', () => {
  it('donne le focus au premier élément à l\'ouverture', async () => {
    render(
      <Modal open title="T" onClose={() => {}}>
        <button>Premier</button><button>Second</button>
      </Modal>
    )
    // le 1er focusable est le bouton de fermeture de l'en-tête
    await waitFor(() => expect(document.activeElement).toHaveAccessibleName(/close|fermer/i))
  })

  it('ferme sur Échap', async () => {
    const onClose = vi.fn()
    render(<Modal open title="T" onClose={onClose}>contenu</Modal>)
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('retient le focus : Tab depuis le dernier élément revient au premier', async () => {
    render(
      <Modal open title="T" onClose={() => {}}>
        <button>Premier</button><button>Dernier</button>
      </Modal>
    )
    screen.getByRole('button', { name: 'Dernier' }).focus()
    fireEvent.keyDown(document, { key: 'Tab' })
    expect(document.activeElement).toHaveAccessibleName(/close|fermer/i)
  })

  it('retient le focus : Shift+Tab depuis le premier élément va au dernier', async () => {
    render(
      <Modal open title="T" onClose={() => {}}>
        <button>Premier</button><button>Dernier</button>
      </Modal>
    )
    screen.getByRole('button', { name: /close|fermer/i }).focus()
    fireEvent.keyDown(document, { key: 'Tab', shiftKey: true })
    expect(document.activeElement).toHaveAccessibleName('Dernier')
  })

  it('ignore les éléments désactivés dans le cycle du focus', async () => {
    render(
      <Modal open title="T" onClose={() => {}}>
        <button>Actif</button><button disabled>Inactif</button>
      </Modal>
    )
    screen.getByRole('button', { name: 'Actif' }).focus()
    fireEvent.keyDown(document, { key: 'Tab' })
    // « Inactif » est sauté : « Actif » est donc le dernier, on revient en tête du cycle
    expect(document.activeElement).toHaveAccessibleName(/close|fermer/i)
  })

  it('rend le focus à l\'élément qui l\'avait avant l\'ouverture', async () => {
    function Harness() {
      const [open, setOpen] = useState(false)
      return (
        <>
          <button onClick={() => setOpen(true)}>Ouvrir</button>
          <Modal open={open} title="T" onClose={() => setOpen(false)}>contenu</Modal>
        </>
      )
    }
    render(<Harness />)
    const ouvrir = screen.getByRole('button', { name: 'Ouvrir' })
    ouvrir.focus()
    await act(async () => { fireEvent.click(ouvrir) })
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    await act(async () => { fireEvent.keyDown(document, { key: 'Escape' }) })
    await waitFor(() => expect(document.activeElement).toBe(ouvrir))
  })

  it('bloque le défilement de la page tant qu\'elle est ouverte', () => {
    const { unmount } = render(<Modal open title="T" onClose={() => {}}>c</Modal>)
    expect(document.body.style.overflow).toBe('hidden')
    unmount()
    expect(document.body.style.overflow).not.toBe('hidden')
  })
})

// ============================================================
// LOT7-07 — les messages doivent être annoncés aux lecteurs d'écran
// ============================================================
describe('Toasts — régions live', () => {
  function Emetteur({ type, titre }: { type: 'success' | 'error'; titre: string }) {
    const { toast } = useToast()
    return <button onClick={() => toast(type, titre)}>émettre</button>
  }

  it('annonce un message ordinaire poliment (role="status")', async () => {
    render(<ToastProvider><Emetteur type="success" titre="Facture enregistrée" /></ToastProvider>)
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'émettre' })) })
    const region = screen.getByRole('status')
    expect(region).toHaveTextContent('Facture enregistrée')
    expect(region).toHaveAttribute('aria-live', 'polite')
  })

  it('annonce une erreur de façon assertive (role="alert")', async () => {
    render(<ToastProvider><Emetteur type="error" titre="Erreur de suppression" /></ToastProvider>)
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'émettre' })) })
    const region = screen.getByRole('alert')
    expect(region).toHaveTextContent('Erreur de suppression')
    expect(region).toHaveAttribute('aria-live', 'assertive')
  })
})

// ============================================================
// LOT7-07 — tri des tableaux : clavier et annonce de l'état
// ============================================================
describe('SortableTable — tri accessible', () => {
  const headers = [
    { label: 'Numéro', key: 'num', sortable: true },
    { label: 'Client', key: 'client', sortable: true },
    { label: 'Actions' },
  ]
  const data = [{ num: 'B', client: 'Zoé' }, { num: 'A', client: 'Ana' }]
  const renderRow = (r: { num: string; client: string }) => (
    <TableRow key={r.num}><TableCell>{r.num}</TableCell><TableCell>{r.client}</TableCell><TableCell>—</TableCell></TableRow>
  )

  function setup() {
    return render(<SortableTable headers={headers} data={data} renderRow={renderRow} />)
  }

  it('annonce chaque colonne triable comme non triée au départ', () => {
    setup()
    expect(screen.getByRole('columnheader', { name: /Numéro/ })).toHaveAttribute('aria-sort', 'none')
  })

  it('ne met pas aria-sort sur une colonne non triable', () => {
    setup()
    expect(screen.getByRole('columnheader', { name: 'Actions' })).not.toHaveAttribute('aria-sort')
  })

  it('rend chaque en-tête triable activable au clavier', () => {
    setup()
    // un <button> est focalisable et activable par Entrée/Espace, contrairement à un <th>
    expect(screen.getByRole('button', { name: /Numéro/ })).toBeInTheDocument()
  })

  it('annonce le sens du tri, et l\'inverse au second clic', () => {
    setup()
    const bouton = screen.getByRole('button', { name: /Numéro/ })
    fireEvent.click(bouton)
    expect(screen.getByRole('columnheader', { name: /Numéro/ })).toHaveAttribute('aria-sort', 'ascending')
    fireEvent.click(bouton)
    expect(screen.getByRole('columnheader', { name: /Numéro/ })).toHaveAttribute('aria-sort', 'descending')
  })

  it('remet la colonne précédente à « none » quand on trie sur une autre', () => {
    setup()
    fireEvent.click(screen.getByRole('button', { name: /Numéro/ }))
    fireEvent.click(screen.getByRole('button', { name: /Client/ }))
    expect(screen.getByRole('columnheader', { name: /Numéro/ })).toHaveAttribute('aria-sort', 'none')
    expect(screen.getByRole('columnheader', { name: /Client/ })).toHaveAttribute('aria-sort', 'ascending')
  })

  it('trie réellement les données', () => {
    setup()
    fireEvent.click(screen.getByRole('button', { name: /Numéro/ }))
    const lignes = screen.getAllByRole('row').slice(1) // hors en-tête
    expect(lignes[0]).toHaveTextContent('A')
  })

  it('rattache les cellules à leur en-tête (scope="col")', () => {
    setup()
    for (const th of screen.getAllByRole('columnheader')) {
      expect(th).toHaveAttribute('scope', 'col')
    }
  })
})
