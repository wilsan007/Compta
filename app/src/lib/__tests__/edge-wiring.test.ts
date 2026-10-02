/**
 * W6 — « l'écran et le backend disent la même chose »
 *
 * Ces tests tiennent l'autre moitié du contrat de W6 : les migrations 257 à 259
 * rendent la base capable de porter la vérité (colonnes réelles, idempotence,
 * porte contre un succès tamponné), et ces tests vérifient que **l'écran**
 * emprunte bien le chemin qui la produit.
 *
 * Trois écrans qui mentaient, et ce qui est vérifié ici :
 *   EF-03 `syncBankConnection`   tamponnait `last_sync_at` sans rien appeler ;
 *   EF-06 `EInvoicePage`         ne soumettait rien (génération + téléchargement) ;
 *   TVA-01 `submitEdiTva`        fabriquait un identifiant local `EDI-<Date.now()>`.
 * Chacun passe désormais par la fonction Edge, et **rien n'est annoncé** tant
 * qu'elle n'a pas confirmé.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

const invoke = vi.fn()
const getSession = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: {
    functions: { invoke: (...args: any[]) => invoke(...args) },
    auth: { getSession: (...args: any[]) => getSession(...args) },
    from: vi.fn(() => {
      throw new Error('Aucun écran ne doit écrire directement la trace d’une transmission')
    }),
    rpc: vi.fn(),
  },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

describe('W6 — les écrans passent par les fonctions Edge', () => {
  beforeEach(() => {
    invoke.mockReset()
  })

  it('EF-03 : syncBankConnection appelle sync-bank-transactions et rend le nombre d’opérations importées', async () => {
    invoke.mockResolvedValue({ data: { success: true, imported: 7, total: 7 }, error: null })
    const { syncBankConnection } = await import('@/lib/queries/banking')

    const result = await syncBankConnection('conn-1')

    expect(invoke).toHaveBeenCalledWith('sync-bank-transactions', {
      body: { action: 'sync', bank_connection_id: 'conn-1' },
    })
    expect(result).toEqual({ synced: 7, error: null })
  })

  it('EF-03 : une synchronisation non confirmée lève, elle n’affiche pas « terminée »', async () => {
    invoke.mockResolvedValue({
      data: { success: false, code: 'PROVIDER_ERROR', error: 'agrégateur indisponible' },
      error: null,
    })
    const { syncBankConnection } = await import('@/lib/queries/banking')

    await expect(syncBankConnection('conn-1')).rejects.toThrow('agrégateur indisponible')
  })

  it('EF-03 : une erreur d’invocation de la fonction Edge n’est jamais avalée', async () => {
    invoke.mockResolvedValue({ data: null, error: new Error('Function not found') })
    const { syncBankConnection } = await import('@/lib/queries/banking')

    await expect(syncBankConnection('conn-1')).rejects.toThrow('Function not found')
  })

  it('TVA-01 : submitEdiTva appelle submit-vat-return et n’écrit aucun identifiant fabriqué', async () => {
    invoke.mockResolvedValue({ data: { success: true, edi_tva_id: 'EDI-REEL-1', status: 'submitted' }, error: null })
    const { submitEdiTva } = await import('@/lib/queries/misc')

    const result: any = await submitEdiTva('vat-return-1')

    expect(invoke).toHaveBeenCalledWith('submit-vat-return', { body: { vat_return_id: 'vat-return-1' } })
    expect(result.edi_tva_id).toBe('EDI-REEL-1')
  })

  it('TVA-01 : une télédéclaration non confirmée lève (aucune donnée n’a été transmise)', async () => {
    invoke.mockResolvedValue({
      data: { success: false, code: 'NOT_CONFIGURED', error: 'API EFI non configuré' },
      error: null,
    })
    const { submitEdiTva } = await import('@/lib/queries/misc')

    await expect(submitEdiTva('vat-return-1')).rejects.toThrow('API EFI non configuré')
  })

  it('EF-06 : submitEInvoice appelle submit-e-invoice et rapporte le dépôt déjà effectué', async () => {
    invoke.mockResolvedValue({
      data: { success: true, already_submitted: true, transaction_id: 'CHORUS-1' },
      error: null,
    })
    const { submitEInvoice } = await import('@/lib/queries/misc')

    const result = await submitEInvoice('invoice-1', 'chorus_pro', 'factur-x')

    expect(invoke).toHaveBeenCalledWith('submit-e-invoice', {
      body: { invoice_id: 'invoice-1', platform: 'chorus_pro', format: 'factur-x', xml_content: undefined },
    })
    expect(result.already_submitted).toBe(true)
  })

  it('EF-06 : le XML validé dans l’aperçu est celui qui est déposé', async () => {
    invoke.mockResolvedValue({ data: { success: true, transaction_id: 'CHORUS-2' }, error: null })
    const { submitEInvoice } = await import('@/lib/queries/misc')

    await submitEInvoice('invoice-2', 'chorus_pro', 'factur-x', '<rsm:CrossIndustryInvoice/>')

    expect(invoke).toHaveBeenCalledWith('submit-e-invoice', {
      body: {
        invoice_id: 'invoice-2',
        platform: 'chorus_pro',
        format: 'factur-x',
        xml_content: '<rsm:CrossIndustryInvoice/>',
      },
    })
  })

  it('EF-06 : un dépôt non confirmé lève', async () => {
    invoke.mockResolvedValue({
      data: { success: false, code: 'NOT_CONFIGURED', error: 'Chorus Pro non configuré' },
      error: null,
    })
    const { submitEInvoice } = await import('@/lib/queries/misc')

    await expect(submitEInvoice('invoice-1')).rejects.toThrow('Chorus Pro non configuré')
  })

  // ── Les fonctions qui n'avaient AUCUN appelant ─────────────────────────
  it("verify-siret / validate-vat-vies : l'écran des paramètres peut vérifier le SIRET et la TVA", async () => {
    invoke.mockResolvedValue({ data: { valid: true, api_source: 'local_validation' }, error: null })
    const { verifySiret, validateVatVies } = await import('@/lib/queries/verifications')

    await verifySiret('73282932000074')
    await validateVatVies('FR12345678901', 'FR12345678901')

    expect(invoke).toHaveBeenNthCalledWith(1, 'verify-siret', { body: { siret: '73282932000074' } })
    expect(invoke).toHaveBeenNthCalledWith(2, 'validate-vat-vies', {
      body: { vat_number: 'FR12345678901', requester_vat: 'FR12345678901' },
    })
  })

  it("verify-iban : l'écran des comptes tiers peut vérifier l'IBAN", async () => {
    invoke.mockResolvedValue({ data: { valid: true, api_source: 'local_validation' }, error: null })
    const { verifyIban } = await import('@/lib/queries/verifications')

    await verifyIban('FR7630006000011234567890189')

    expect(invoke).toHaveBeenCalledWith('verify-iban', { body: { iban: 'FR7630006000011234567890189' } })
  })

  it('request-signature : la demande porte le document, ses signataires et la société', async () => {
    invoke.mockResolvedValue({ data: { success: true, signature_id: 'YSN-1', status: 'pending' }, error: null })
    const { requestSignature } = await import('@/lib/queries/verifications')

    const result = await requestSignature({
      documentType: 'employee_document',
      documentId: 'doc-1',
      documentUrl: 'https://exemple.test/contrat.pdf',
      signers: [{ first_name: 'Jean', last_name: 'Dupont', email: 'j@exemple.test' }],
      tenantId: 't-1',
    })

    expect(invoke).toHaveBeenCalledWith('request-signature', {
      body: {
        document_type: 'employee_document',
        document_id: 'doc-1',
        document_url: 'https://exemple.test/contrat.pdf',
        signers: [{ first_name: 'Jean', last_name: 'Dupont', email: 'j@exemple.test' }],
        provider: 'yousign',
        tenant_id: 't-1',
      },
    })
    expect(result.signature_id).toBe('YSN-1')
  })

  it("request-signature : une demande non enregistrée LÈVE (elle n'est pas annoncée comme envoyée)", async () => {
    invoke.mockResolvedValue({
      data: { success: false, code: 'NOT_RECORDED', error: 'procédure créée mais non enregistrée' },
      error: null,
    })
    const { requestSignature } = await import('@/lib/queries/verifications')

    await expect(requestSignature({
      documentType: 'employee_document', documentId: 'doc-1',
      documentUrl: 'https://exemple.test/c.pdf', signers: [], tenantId: 't-1',
    })).rejects.toThrow('procédure créée mais non enregistrée')
  })

  it('ai-import-mapping : le repli IA porte le JETON (il répondait 401 — la fonctionnalité ne marchait pas)', async () => {
    // La fonction exige un jeton ; ce test tient les DEUX moitiés du contrat :
    // le front en envoie un, et sans session il n'appelle rien du tout.
    const vraiFetch = globalThis.fetch
    let dernierInit: RequestInit | undefined
    const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
      dernierInit = init
      return new Response(
        JSON.stringify({ mapping: { a: 'Col A' }, confidence: 0.9, reasoning: {} }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    })
    globalThis.fetch = fetchMock as unknown as typeof fetch
    try {
      getSession.mockResolvedValue({ data: { session: { access_token: 'jeton-123' } } })
      const { aiFallbackMapping } = await import('@/lib/aiImportMapping')

      const result = await aiFallbackMapping(
        ['Col A'], [{ 'Col A': 'x' }], [{ key: 'a', label: 'A', required: false }],
        'Module', 'https://exemple.supabase.co/functions/v1/ai-import-mapping',
      )

      expect(fetchMock).toHaveBeenCalledTimes(1)
      expect((dernierInit?.headers || {}) as Record<string, string>).toMatchObject({ Authorization: 'Bearer jeton-123' })
      expect(result?.mapping).toEqual({ a: 'Col A' })

      // Sans session : aucun appel ne part (et surtout pas un appel anonyme).
      fetchMock.mockClear()
      getSession.mockResolvedValue({ data: { session: null } })
      const sansSession = await aiFallbackMapping(
        ['Col A'], [{ 'Col A': 'x' }], [{ key: 'a', label: 'A', required: false }],
        'Module', 'https://exemple.supabase.co/functions/v1/ai-import-mapping',
      )
      expect(fetchMock).not.toHaveBeenCalled()
      expect(sansSession).toBeNull()
    } finally {
      globalThis.fetch = vraiFetch
    }
  })

  // D-5 (tâche 1.11) : les deux fonctions qui parlent au prestataire d'IA lisent
  // le consentement de LA société désignée par `x-tenant-id`, et refusent (400)
  // de la deviner. Ces deux `fetch` directs ne passent pas par celui du client
  // Supabase : sans l'en-tête posé à la main, l'import ne marchait plus du tout.
  it('D-5 : le repli IA de l’import et l’analyse IA d’un relevé désignent la société (x-tenant-id)', async () => {
    const vraiFetch = globalThis.fetch
    const entetes: Record<string, string>[] = []
    const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
      entetes.push((init?.headers || {}) as Record<string, string>)
      return new Response(
        JSON.stringify({ mapping: {}, confidence: 0.5, reasoning: {}, transactions: [], template: {}, warnings: [] }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    })
    globalThis.fetch = fetchMock as unknown as typeof fetch
    try {
      getSession.mockResolvedValue({ data: { session: { access_token: 'jeton-123' } } })
      const { aiFallbackMapping } = await import('@/lib/aiImportMapping')
      const { parseWithAI } = await import('@/lib/pdfBankParser')

      await aiFallbackMapping(['A'], [{ A: 'x' }], [{ key: 'a', label: 'A', required: false }], 'M', 'https://e.test/functions/v1/ai-import-mapping')
      await parseWithAI('01/09/2026 VIREMENT 10,00', 'Banque')

      expect(fetchMock).toHaveBeenCalledTimes(2)
      for (const h of entetes) expect(h).toMatchObject({ 'x-tenant-id': 'test-tenant-id' })
    } finally {
      globalThis.fetch = vraiFetch
    }
  })

  it('D-5 : un refus de consentement (409) atteint l’écran avec sa phrase, pas « IA indisponible »', async () => {
    const vraiFetch = globalThis.fetch
    const phrase = "L'envoi à un prestataire d'IA n'est pas autorisé pour cette société."
    globalThis.fetch = vi.fn(async () => new Response(
      JSON.stringify({ error: phrase, code: 'OCR_CONSENT_REQUIRED' }),
      { status: 409, headers: { 'Content-Type': 'application/json' } },
    )) as unknown as typeof fetch
    try {
      getSession.mockResolvedValue({ data: { session: { access_token: 'jeton-123' } } })
      const { aiFallbackMapping } = await import('@/lib/aiImportMapping')
      const { parseWithAI } = await import('@/lib/pdfBankParser')

      await expect(aiFallbackMapping(['A'], [{ A: 'x' }], [{ key: 'a', label: 'A', required: false }], 'M', 'https://e.test/x'))
        .rejects.toThrow(phrase)
      await expect(parseWithAI('texte', 'Banque')).rejects.toThrow(phrase)
    } finally {
      globalThis.fetch = vraiFetch
    }
  })
})

describe('W6 — aucun écran n’écrit la trace d’une transmission', () => {
  // Miroir statique de la porte de la 259 : les trois colonnes de transmission
  // ne doivent plus être écrites par un écran (elles le sont par le service,
  // après un appel réel).
  const INTERDITES: Array<[string, RegExp, RegExp?]> = [
    ['edi_status', /edi_status\s*:/],
    ['e_invoice_status', /e_invoice_status\s*:/],
    // `last_sync_at: null` à la CRÉATION d'une connexion n'est pas un tampon :
    // c'est l'absence de synchronisation, et la porte de la 259 ne s'y oppose
    // pas (elle refuse le CHANGEMENT de la colonne).
    ['last_sync_at', /last_sync_at\s*:/, /last_sync_at\s*:\s*null\s*,?\s*$/],
  ]

  function fichiersSource(dir: string): string[] {
    const out: string[] = []
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name)
      if (e.isDirectory()) {
        if (/__tests__|node_modules|\/types$/.test(p)) continue
        out.push(...fichiersSource(p))
      } else if (/\.(ts|tsx)$/.test(p) && !/database-generated|\.test\./.test(p)) {
        out.push(p)
      }
    }
    return out
  }

  it('aucune écriture directe de edi_status / e_invoice_status / last_sync_at dans src/', () => {
    const racine = path.resolve(__dirname, '../../..') // app/
    const src = path.join(racine, 'src')
    const fautifs: string[] = []

    for (const f of fichiersSource(src)) {
      const lignes = fs.readFileSync(f, 'utf8').split('\n')
      for (let i = 0; i < lignes.length; i++) {
        for (const [nom, motif, exception] of INTERDITES) {
          if (exception && exception.test(lignes[i])) continue
          if (motif.test(lignes[i])) {
            fautifs.push(`${path.relative(racine, f)}:${i + 1} → ${nom}`)
          }
        }
      }
    }

    expect(fautifs).toEqual([])
  })
})
