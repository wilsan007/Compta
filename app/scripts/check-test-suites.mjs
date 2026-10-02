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
 * LA RÈGLE. Deux conditions, l'une sur le CÂBLAGE et l'autre sur le
 * VERDICT.
 *
 * 1. Pour chaque `app/sql/*_tests.sql` : au moins une référence
 *    `-f sql/<nom>` dans `.github/workflows/ci.yml`. Et réciproquement : une
 *    référence qui ne correspond à aucun fichier casse la CI — c'est le cas
 *    d'un renommage, où la CI appellerait un fantôme (et `psql` échouerait
 *    *après* avoir fait croire que la suite tournait).
 *
 * 2. Pour chaque `app/sql/*_tests.sql` : la suite doit produire un VERDICT,
 *    c'est-à-dire porter soit `_audit_assert('<id>')`, soit un `RAISE
 *    EXCEPTION`. C'est la seconde moitié de la règle du dépôt (« un défaut =
 *    un test rouge avant ») que rien ne gardait.
 *
 *    LE TROU MESURÉ LE 02/10/2026. `412_chain_l1_caisse_rpc_tests.sql`
 *    écrivait 8 scénarios via `_rec`, les lisait en base (8/8), et **ne
 *    relisait jamais** : ni `_audit_assert`, ni `RAISE EXCEPTION`. Rejouée
 *    après avoir mis T03 en échec à la main, la suite ressortait avec le
 *    code de sortie 0. Un « ✅ » de CI qui ne vérifiait rien — et c'est la
 *    suite de la CAISSE, l'un des maillons les plus sensibles du dépôt.
 *
 *    Les deux mécanismes sont acceptés parce que huit suites historiques
 *    (102, 105, 166, 168, 170, 173, 175, 177) ont été écrites avant
 *    `_audit_assert` et lèvent par `RAISE EXCEPTION` : elles font réellement
 *    échouer la CI, et les aligner serait du travail de fond sans rapport avec
 *    ce garde-fou. Une suite qui n'a NI l'un NI l'autre ne peut pas échouer,
 *    et c'est exactement ce que ce contrôle refuse.
 *
 * CE QUE LE CONTRÔLE NE PROUVE PAS. Il prouve que la suite est JOUÉE et
 * qu'elle peut EXPRIMER UN ÉCHEC, pas qu'elle vérifie ce qu'elle prétend
 * vérifier : une suite peut asserter une propriété triviale. C'est le rôle du
 * registre `ci/expected_failures.sql`, qui nomme les échecs attendus.
 *
 * Sortie : code 1 si une suite n'est pas branchée, si une référence ne
 * correspond à aucun fichier, ou si une suite ne peut pas échouer. Code 0
 * sinon.
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

// 3. Les suites QUI NE PEUVENT PAS ÉCHOUER : celles qui n'ont ni
//    `_audit_assert('…')`, ni de `RAISE EXCEPTION` **dans un bloc
//    EXCEPTION** (c'est-à-dire sur un chemin d'échec).
//    Écrire des scénarios, les lire en base et ne jamais les relire n'est pas
//    vérifier — c'est le faux vert de la 412 (voir l'en-tête).
//
//    LE PIÈGE DU `RAISE EXCEPTION` DE MONTAGE. La 412 en contient un, mais
//    c'est une PRÉCONDITION : `IF ua IS NULL OR ub IS NULL THEN RAISE EXCEPTION
//    'Contexte de société non établi…'` — il lève si le décor est faux, jamais
//    si un scénario est faux. Compter n'importe quel `RAISE EXCEPTION` laisserait
//    donc passer exactement la suite qu'on veut fermer.
//
//    LA LIGNE QUI FAIT LA DIFFÉRENCE. Un verdict teste **l'objet du test** ; un
//    montage teste **le décor**. `IF NOT has_permission('…') THEN RAISE
//    EXCEPTION '1. un admin doit…'` (166) et `IF is_allowed_webhook_url(v_url)
//    THEN RAISE EXCEPTION '…'` (168) interrogent la fonction vérifiée. Le
//    contrôle exige donc un `RAISE EXCEPTION` précédé d'un `IF … <appel>
//    THEN`, et EXCLUT la garde de contexte, dont le message dit ce qu'elle est.
//    Un garde-fou se reconnaît à son texte : « ne prouverait rien »,
//    « prérequis », « contexte » — c'est ainsi qu'on le distingue sans
//    inventer une liste d'appels.
//
//    Le commentaire de tête ne compte pas : `-- _audit_assert` ne vérifie rien,
//    seul l'appel le fait.
const GARDE_DE_MONTAGE = /ne prouverrait rien|pr[ée]-?requis|contexte (de soci[ée]t[eé]|non|[aà])/i

const sansVerdict = suites.filter((f) => {
  const src = fs
    .readFileSync(path.join(SQL, f), 'utf8')
    .split('\n')
    .filter((l) => !l.trim().startsWith('--'))
    .join('\n')
  if (/_audit_assert\s*\(/.test(src)) return false

  // On ne compte que les `RAISE EXCEPTION` dont le message porte un VERDICT,
  // et qui sont portés par une condition : `IF … THEN RAISE EXCEPTION` ou
  // `EXCEPTION WHEN … THEN RAISE EXCEPTION`.
  const verifs = [...src.matchAll(/(IF\b[\s\S]{0,400}?|EXCEPTION\s+WHEN\b[\s\S]{0,400}?)RAISE\s+EXCEPTION\s+'([^']*)'/gi)]
  return !verifs.some((m) => !GARDE_DE_MONTAGE.test(m[2]))
})

console.log(
  `Câblage des suites : ${suites.length} fichier(s) dans sql/, ${referenced.size} référence(s) dans ci.yml.`
)
console.log(`Non branchées     : ${notWired.length === 0 ? 'aucune' : notWired.join(', ')}`)
console.log(`Références fantômes : ${ghosts.length === 0 ? 'aucune' : ghosts.join(', ')}`)
console.log(
  `Sans verdict       : ${sansVerdict.length === 0 ? 'aucune' : sansVerdict.join(', ')}`
)

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

if (sansVerdict.length > 0) {
  console.error(
    `\n❌ ${sansVerdict.length} suite(s) ne peuvent JAMAIS échouer — ni \`_audit_assert\`, ni \`RAISE EXCEPTION\` :\n  ${sansVerdict.join('\n  ')}\n` +
      `  Une telle suite passe toujours, même quand tous ses scénarios sont faux : c'est\n` +
      `  exactement le faux vert de la 412, mesuré le 02/10/2026 (8 scénarios écrits,\n` +
      `  8 lus en base, T03 mis en échec à la main — code de sortie 0).\n\n` +
      `  Ajoutez \`SELECT _audit_assert('<id>');\` en fin de suite : elle relit les verdicts\n` +
      `  écrits par \`_rec\`, lève si l'un est faux, et n'affiche rien si la suite n'a rien\n` +
      `  écrit — c'est ce qui distingue « 8/8 verts » de « 8 verdicts jamais produits ».\n` +
      `  L'<id>' doit être le numéro de la MIGRATION (412), pas l'ancien numéro du fichier.`
  )
}

if (notWired.length > 0 || ghosts.length > 0 || sansVerdict.length > 0) process.exit(1)

console.log(
  `\n✅ Toutes les suites du dépôt (${suites.length}) sont jouées par la CI, aucune référence ne pointe un` +
    `\n   fichier absent, et chacune peut faire échouer la CI (verdict).\n`
)
