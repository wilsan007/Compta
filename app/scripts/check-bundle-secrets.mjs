#!/usr/bin/env node
/**
 * SEC-04: Vérifie que le bundle de production ne contient pas de secrets.
 *
 * Cherche dans dist/assets/ les motifs:
 *   - sb_secret_     (clé secrète Supabase)
 *   - sb_service_    (clé service role Supabase)
 *   - re_[a-zA-Z0-9]  (clé API Resend)
 *   - service_role
 *
 * À lancer après `vite build` et avant le déploiement.
 * Exit 1 si un secret est trouvé.
 */
import fs from 'fs'
import path from 'path'

const distDir = path.resolve(import.meta.dirname, '..', 'dist')
const patterns = [
  /sb_secret_[A-Za-z0-9_-]{10,}/,
  /sb_service_[A-Za-z0-9_-]{10,}/,
  /service_role/,
  /re_[a-zA-Z0-9]{20,}/,
  /SUPABASE_SECRET_KEY/,
  /RESEND_API_KEY/,
  /R2_SECRET_ACCESS_KEY/,
]

if (!fs.existsSync(distDir)) {
  console.error('❌ dist/ non trouvé — lancez `npm run build` d\'abord.')
  process.exit(1)
}

let found = false

function scanDir(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      scanDir(fullPath)
    } else if (/\.(js|css|html)$/.test(entry.name)) {
      const content = fs.readFileSync(fullPath, 'utf-8')
      for (const pattern of patterns) {
        const match = content.match(pattern)
        if (match) {
          console.error(`❌ SECRET DÉTECTÉ dans ${path.relative(distDir, fullPath)}: ${match[0].substring(0, 30)}…`)
          found = true
        }
      }
    }
  }
}

scanDir(distDir)

if (found) {
  console.error('\n❌ SEC-04: Le bundle contient des secrets. Vérifiez que aucune variable VITE_ ne contient de clé secrète.')
  process.exit(1)
} else {
  console.log('✅ SEC-04: Aucun secret détecté dans le bundle.')
  process.exit(0)
}
