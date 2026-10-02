/**
 * Tâche 1.10 (AUD-I02) — le formulaire d'un compte ne montre que ce qu'il
 * ENREGISTRE.
 *
 * L'onglet « Complément » portait six contrôles qui ne s'enregistraient jamais :
 * « nombre de lignes », « saut de page », « regroupement » (aucune colonne en
 * base) et trois cases cochées d'office — « saisie analytique », « saisie
 * d'échéance », « saisie tiers ». Ces trois colonnes existent
 * (`chart_accounts.saisie_*`), mais AUCUN code ne les lit depuis la 152
 * (`auto_letter_accounts` a cessé de lire `saisie_tiers`) : les enregistrer
 * aurait promis une obligation de saisie que rien n'applique. Les six sont
 * retirés ; rendre ces obligations réelles est un chantier à part (la base
 * devrait refuser une ligne sans tiers ou sans section).
 *
 * Le signe d'un placebo, dans ce formulaire : un contrôle NON CONTRÔLÉ
 * (`defaultValue` / `defaultChecked`) — sa valeur n'atteint jamais l'état que
 * `handleSubmit` envoie. Miroir statique, comme `single-engine.test.ts`.
 */
import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

const SOURCE = fs.readFileSync(path.resolve(__dirname, '../../pages/ChartAccountsPage.tsx'), 'utf8')
const FORMULAIRE = SOURCE.slice(SOURCE.indexOf('function AccountForm('))

describe('1.10 — le formulaire d’un compte n’a aucun champ factice', () => {
  it('aucun contrôle non contrôlé (defaultValue / defaultChecked) dans AccountForm', () => {
    const lignes = FORMULAIRE.split('\n')
      .map((l, i) => ({ l, i }))
      // l'ATTRIBUT JSX seulement : `t(clé, { defaultValue })` est une option de traduction
      .filter(({ l }) => /\bdefault(?:Value|Checked)(?=[\s=/>])/.test(l))
      .map(({ l }) => l.trim())
    expect(lignes).toEqual([])
  })

  it('les six libellés des champs factices ont disparu de l’écran', () => {
    for (const cle of ['nbLines', 'pageBreak', 'regrouping', 'analyticEntry', 'echeanceEntry', 'tiersEntry']) {
      expect(SOURCE).not.toContain(`chartAccounts.${cle}`)
    }
  })
})
