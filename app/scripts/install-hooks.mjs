#!/usr/bin/env node
/**
 * Installe le crochet git `pre-commit` qui refuse un numéro de migration en
 * doublon ou jamais PRIS au registre (`scripts/migration-numero.mjs`).
 *
 * Le crochet vit dans le dossier git COMMUN : un seul crochet pour tous les
 * worktrees du dépôt — c'est là qu'il faut le poser, puisque les collisions
 * naissent entre worktrees. Il cherche le script dans le worktree qui commite,
 * à défaut dans la copie principale (une branche ancienne ne l'a pas encore),
 * et ne bloque jamais un commit s'il ne trouve ni l'un ni l'autre (il le dit).
 *
 * Un crochet pre-commit déjà présent et étranger est conservé et appelé après.
 *
 * Usage : node scripts/install-hooks.mjs   (ou npm run hooks:install)
 */
import { writeFileSync, readFileSync, existsSync, renameSync, chmodSync, mkdirSync } from 'node:fs'
import { join, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const repoRoot = resolve(join(dirname(fileURLToPath(import.meta.url)), '../..'))
const commonDir = resolve(repoRoot, execFileSync('git', ['rev-parse', '--git-common-dir'], { cwd: repoRoot, encoding: 'utf8' }).trim())
const mainCopy = dirname(commonDir)
const hooksDir = join(commonDir, 'hooks')
const hook = join(hooksDir, 'pre-commit')
const MARK = '# onusuite: numeros de migration'

const body = `#!/bin/sh
${MARK} — installé par app/scripts/install-hooks.mjs. Ne pas éditer ici.
top="$(git rev-parse --show-toplevel)"
script="$top/app/scripts/migration-numero.mjs"
[ -f "$script" ] || script="${mainCopy}/app/scripts/migration-numero.mjs"
if [ -f "$script" ] && command -v node >/dev/null 2>&1; then
  MIGRATION_REPO="$top" node "$script" verifier --staged || exit 1
else
  echo "⚠️  pre-commit : migration-numero.mjs introuvable — numéros de migration NON vérifiés." >&2
fi
[ -x "$(dirname "$0")/pre-commit.local" ] && exec "$(dirname "$0")/pre-commit.local" "$@"
exit 0
`

mkdirSync(hooksDir, { recursive: true })
if (existsSync(hook) && !readFileSync(hook, 'utf8').includes(MARK)) {
  renameSync(hook, join(hooksDir, 'pre-commit.local'))
  console.log('ℹ️  crochet pre-commit existant conservé sous pre-commit.local (appelé après le contrôle).')
}
writeFileSync(hook, body)
chmodSync(hook, 0o755)
console.log(`✅ crochet installé : ${hook} (tous les worktrees du dépôt).`)
