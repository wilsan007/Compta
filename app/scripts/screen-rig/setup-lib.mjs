// Outil partagé du banc « chemin de l'écran » : signature HS256 des jetons.
import crypto from 'node:crypto'

const b64u = (b) => Buffer.from(b).toString('base64url')
export function signJwt(payload, secret) {
  const h = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
  const p = b64u(JSON.stringify(payload))
  return `${h}.${p}.${crypto.createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url')}`
}
