#!/usr/bin/env node
/**
 * check-test-suites.mjs — G5 (lot L2, « tests et registre »)
 *
 * L'ANGLE MORT QUE CE CONTRÔLE FERME. La règle du dépôt est écrite dans
 * AGENTS.md : « un défaut = un test rouge avant, le câblage CI et la preuve dans
 * le même commit ». Deux moitiés de cette règle étaient déjà gardées — le
 * registre des échecs attendus sur le couple (fichier, test) par
 * `ci/audit_registry_selftest.sql` (AUD-X01), et le refus d'un fichier sans
 * verdict par `_audit_assert`. La troisième ne l'était pas : **l'oubli du
 * câblage**. Une suite `sql/NNN_…_tests.sql` peut exister, passer, décrire un
 * défaut corrigé… et n'être jouée par PERSONNE : la CI ne la connaît pas, donc
 * elle ne protège rien. Mesuré le 30/09/2026 : **89 suites, 89 branchées** —
 * l'écart est nul aujourd'hui, et rien ne le garantissait pour demain (le lot L2
 * vient d'ajouter la suite 312, et 25 lots suffisent à en perdre une).
 *
 * LA RÈGLE. Pour chaque `app/sql/*_tests.sql` : au moins une référence
 * `-f sql/<nom>` dans `.github/workflows/ci.yml`. Et réciproquement : une
 * référence qui ne correspond à aucun fichier casse la CI — c'est le cas d'un
 * renommage, où la CI appellerait un fantôme (et `psql` échouerait *après* avoir
 * fait croire que la suite tournait).
 *
 * CE QUE LE CONTRÔLE NE PROUVE PAS. Il prouve que la suite est JOUÉE, pas
 * qu'elle VÉRIFIE quelque chose : un fichier peut être branché et ne rien
 * asserter. C'est le rôle d'`_audit_assert` (un fichier sans verdict casse) et du
 * registre `ci/expected_failures.sql`.
 *
 * Sortie : code 1 si une suite n'est pas branchée ou si une référence ne
 * correspond à aucun fichier. Code 0 sinon.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const APP = path.join(__dirname, '..')
const SQL = path.join(APP, 'sql')
const CI = path.join(APP, '..', '.github', 'workflows', 'ci.yml')

if (!fs.existsSync(CI)) {
  console.error(`❌ ${CI} introuvable — le contrôle ne peut pas vérifier le câblage.`)
  process.exit(1)
}

// 1. Les suites qui existent sur le disque
const suites = fs
  .readdirSync(SQL)
  .filter((f) => f.endsWith('_tests.sql'))
  .sort()

// 2. Celles que la CI référence (`-f sql/<nom>`)
const ci = fs.readFileSync(CI, 'utf8')
const referenced = new Set(
  [...ci.matchAll(/-f\s+sql\/([0-9A-Za-z_]+_tests\.sql)/g)].map((m) => m[1])
)

const notWired = suites.filter((f) => !referenced.has(f))
const ghosts = [...referenced].filter((f) => !fs.existsSync(path.join(SQL, f))).sort()

console.log(
  `Câblage des suites : ${suites.length} fichier(s) dans sql/, ${referenced.size} référence(s) dans ci.yml.`
)
console.log(`Non branchées     : ${notWired.length === 0 ? 'aucune' : notWired.join(', ')}`)
console.log(`Références fantômes : ${ghosts.length === 0 ? 'aucune' : ghosts.join(', ')}`)

if (notWired.length > 0) {
  console.error(
    `\n❌ ${notWired.length} suite(s) ne sont jouées par aucune étape de la CI :\n  ${notWired.join('\n  ')}\n` +
      `  Ajoutez l'étape (\`psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/<nom>\`) dans le job\n` +
      `  « DB Integration Tests » de .github/workflows/ci.yml, avec le commentaire du défaut qu'elle ferme.`
  )
}

if (ghosts.length > 0) {
  console.error(
    `\n❌ ${ghosts.length} référence(s) de la CI ne correspondent à aucun fichier :\n  ${ghosts.join('\n  ')}\n` +
      `  Un renommage de suite doit mettre la CI à jour dans le même commit.`
  )
}

if (notWired.length > 0 || ghosts.length > 0) process.exit(1)

console.log(
  `\n✅ Toutes les suites du dépôt (${suites.length}) sont jouées par la CI, et aucune référence ne pointe un fichier absent.`
)
