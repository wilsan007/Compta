// Confronte les verdicts de chaque fichier au registre des échecs attendus (X0).
// Même contrat que `sql/ci/expected_failures.sql` : la clé est le couple
// (fichier, identifiant) ; un rouge hors registre casse la CI, un vert encore
// inscrit aussi (la ligne doit partir dans le commit du correctif), et un
// fichier sans aucun verdict ne vérifie rien.
import { afterAll, expect } from 'vitest'
import path from 'path'
import { findings, closeSql } from './rig'
import registry from './expected_failures.json'

afterAll(async () => {
  await closeSql()
  const file = path.basename(expect.getState().testPath ?? '').replace(/\.screen\.ts$/, '')
  if (file === '14_readsweep') return   // balayage des lectures : rapport, pas de verdicts
  const expected = new Set((registry as { file: string; id: string }[]).filter((r) => r.file === file).map((r) => r.id))
  const regressions = findings.filter((f) => !f.ok && !expected.has(f.id)).map((f) => `${f.id} (${f.label})`)
  const fixed = findings.filter((f) => f.ok && expected.has(f.id)).map((f) => f.id)
  const unknown = [...expected].filter((id) => !findings.some((f) => f.id === id))
  const red = findings.filter((f) => !f.ok && expected.has(f.id)).length
  console.log(`[${file}] ${findings.length} verdict(s) : ${findings.filter((f) => f.ok).length} vert(s), ${red} rouge(s) attendu(s) au registre`)
  const errors: string[] = []
  if (!findings.length) errors.push(`[${file}] aucun verdict — le fichier ne vérifie rien`)
  if (regressions.length) errors.push(`[${file}] échec(s) hors registre : ${regressions.join(' ; ')}`)
  if (fixed.length) errors.push(`[${file}] corrigé(s) mais encore au registre — retirer de expected_failures.json : ${fixed.join(', ')}`)
  if (unknown.length) errors.push(`[${file}] registre périmé — identifiant(s) jamais vérifié(s) : ${unknown.join(', ')}`)
  if (errors.length) throw new Error(errors.join('\n'))
})
