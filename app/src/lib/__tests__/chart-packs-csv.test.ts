import { describe, it, expect } from 'vitest'
import { parseChartCsv } from '@/lib/queries/chartPacks'

describe('parseChartCsv — plan comptable téléversé', () => {
  it('lit un fichier « ; » avec en-tête français et types français', () => {
    const csv = '﻿code;libellé;type\n411000;Clients;actif\n401000;Fournisseurs;passif\n101000;Capital;capitaux propres\n707000;Ventes;produit\n607000;Achats;charge\n'
    const { rows, errors } = parseChartCsv(csv)
    expect(errors).toEqual([])
    expect(rows.map((r) => [r.code, r.type])).toEqual([
      ['411000', 'asset'], ['401000', 'liability'], ['101000', 'equity'], ['707000', 'income'], ['607000', 'expense'],
    ])
  })

  it('accepte « , », les guillemets et les colonnes facultatives', () => {
    const csv = 'code,name,type,parent,tva\r\n445710,"TVA collectée, taux normal",liability,4457,\r\n'
    const { rows, errors } = parseChartCsv(csv)
    expect(errors).toEqual([])
    expect(rows).toEqual([{ code: '445710', name: 'TVA collectée, taux normal', type: 'liability', parent_code: '4457' }])
  })

  it("refuse un en-tête sans les colonnes obligatoires, sans rien lire", () => {
    const { rows, errors } = parseChartCsv('compte;intitulé\n411000;Clients\n')
    expect(rows).toEqual([])
    expect(errors[0]).toMatch(/type/)
  })

  it('transmet un type inconnu tel quel pour que le serveur nomme la ligne', () => {
    const { rows } = parseChartCsv('code;libellé;type\n411000;Clients;bizarre\n')
    expect(rows[0].type).toBe('bizarre')
  })

  it('signale un fichier vide', () => {
    expect(parseChartCsv('\n\n').errors).toEqual(['Fichier vide'])
  })
})
