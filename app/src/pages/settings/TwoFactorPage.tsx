// @ts-nocheck
import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input,  Breadcrumb, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/lib/toast'
import { Secret, TOTP } from 'otpauth'
import { Shield, ShieldCheck, ShieldAlert, Key, Smartphone, Copy } from 'lucide-react'
import { confirmSync } from '@/lib/confirm'

export function TwoFactorPage() {
  const { t } = useTranslation()
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [enabled, setEnabled] = useState(false)
  const [loading, setLoading] = useState(true)
  const [setupMode, setSetupMode] = useState(false)
  const [qrUrl, setQrUrl] = useState('')
  const [secret, setSecret] = useState('')
  const [token, setToken] = useState('')
  const [backupCodes, setBackupCodes] = useState<string[]>([])
  const [showCodes, setShowCodes] = useState(false)

  const loadStatus = useCallback(async () => {
    setLoading(true)
    try {
      const { data, error } = await supabase.rpc('get_2fa_status')
      if (error) throw error
      setEnabled(data?.enabled || false)
    } catch {
      setEnabled(false)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadStatus() }, [loadStatus])

  async function handleStartSetup() {
    try {
      // Generate TOTP secret (client-side, will be stored encrypted server-side)
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
      let s = ''
      const bytes = new Uint8Array(20)
      crypto.getRandomValues(bytes)
      for (let i = 0; i < 20; i++) s += chars[(bytes[i] & 31)]
      setSecret(s)

      const { data: { user } } = await supabase.auth.getUser()
      const issuer = 'Onusuite'
      const label = `${issuer}:${user?.email || 'user'}`
      setQrUrl(`otpauth://totp/${encodeURIComponent(label)}?secret=${s}&issuer=${issuer}&algorithm=SHA1&digits=6&period=30`)
      setSetupMode(true)
      setToken('')
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleVerify() {
    if (token.length !== 6) {
      toast('error', 'Code invalide', 'Entrez un code à 6 chiffres')
      return
    }
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const totp = new TOTP({
        issuer: 'Onusuite',
        label: user?.email || 'user',
        algorithm: 'SHA1',
        digits: 6,
        period: 30,
        secret: Secret.fromBase32(secret),
      })
      const delta = totp.validate({ token, window: 1 })
      if (delta === null) {
        toast('error', 'Code invalide', 'Le code ne correspond pas')
        return
      }
      // Generate backup codes
      const codes: string[] = []
      for (let i = 0; i < 10; i++) {
        const bytes = new Uint8Array(8)
        crypto.getRandomValues(bytes)
        const code = Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 8).toUpperCase()
        codes.push(`${code.slice(0, 4)}-${code.slice(4, 8)}`)
      }
      setBackupCodes(codes)
      setShowCodes(true)

      const { error } = await supabase.rpc('enable_2fa', {
        p_secret: btoa(secret),
        p_backup_codes: codes.map(c => btoa(c)),
      })
      if (error) throw error

      setEnabled(true)
      setSetupMode(false)
      toast('success', '2FA activé', 'Conservez vos codes de récupération en lieu sûr.')
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleDisable() {
    if (!confirmSync("Désactiver l'authentification à deux facteurs ?")) return
    try {
      const { error } = await supabase.rpc('disable_2fa')
      if (error) throw error
      setEnabled(false)
      toast('success', '2FA désactivé', '')
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  if (loading) {
    return <div className="space-y-6"><Skeleton className="h-12 w-full" /><Skeleton className="h-64 w-full" /></div>
  }

  return (
    <div className="space-y-6">
      <Breadcrumb items={[{ label: t('nav:items.settings'), href: '/settings' }, { label: 'Sécurité 2FA' }]} />
      <PageHeader title="Authentification à deux facteurs" description="Renforcez la sécurité de votre compte avec TOTP" />

      <Card className="p-6">
        {enabled ? (
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <ShieldCheck className="w-8 h-8 text-[var(--color-success)]" />
              <div>
                <h3 className="font-semibold text-[var(--color-success)]">2FA activé</h3>
                <p className="text-sm text-[var(--color-text-secondary)]">Votre compte est protégé par une authentification à deux facteurs.</p>
              </div>
            </div>
            {showCodes && backupCodes.length > 0 && (
              <div className="p-4 border border-[var(--color-warning)] bg-[var(--color-warning-50)] rounded-lg space-y-3">
                <div className="flex items-center gap-2">
                  <ShieldAlert className="w-5 h-5 text-[var(--color-warning)]" />
                  <h4 className="font-semibold">Codes de récupération</h4>
                </div>
                <p className="text-sm">Conservez ces codes en lieu sûr. Chaque code ne peut être utilisé qu'une fois.</p>
                <div className="grid grid-cols-2 gap-2 font-mono text-sm">
                  {backupCodes.map((c, i) => (
                    <div key={i} className="flex items-center gap-2">
                      <span>{c}</span>
                      <button onClick={() => { navigator.clipboard.writeText(c); toast('success', 'Copié', '') }} className="text-xs" aria-label={tCommon('actions.copy')} title={tCommon('actions.copy')}><Copy className="w-3 h-3" aria-hidden="true" /></button>
                    </div>
                  ))}
                </div>
                <Button variant="outline" size="sm" onClick={() => setShowCodes(false)}>J'ai sauvegardé mes codes</Button>
              </div>
            )}
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setShowCodes(true)}><Key className="w-4 h-4 mr-1" /> Voir les codes</Button>
              <Button variant="danger" onClick={handleDisable}><ShieldAlert className="w-4 h-4 mr-1" /> Désactiver 2FA</Button>
            </div>
          </div>
        ) : setupMode ? (
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <Smartphone className="w-8 h-8 text-[var(--color-primary)]" />
              <div>
                <h3 className="font-semibold">Configuration</h3>
                <p className="text-sm text-[var(--color-text-secondary)]">Scannez le QR code avec votre application d'authentification (Google Authenticator, Authy, etc.)</p>
              </div>
            </div>
            <div className="flex flex-col md:flex-row gap-6">
              <div className="flex-shrink-0">
                <div className="p-4 bg-white rounded-lg border border-[var(--color-border)] inline-block">
                  <img src={`https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(qrUrl)}`} alt="QR Code" className="w-48 h-48" />
                </div>
              </div>
              <div className="space-y-3 flex-1">
                <div>
                  <label className="text-sm font-medium">Ou saisissez manuellement la clé :</label>
                  <div className="flex items-center gap-2 mt-1">
                    <Input value={secret} readOnly className="font-mono text-xs" />
                    <Button variant="outline" size="sm" onClick={() => { navigator.clipboard.writeText(secret); toast('success', 'Copié', '') }} ariaLabel={tCommon('actions.copy')}><Copy className="w-4 h-4" aria-hidden="true" /></Button>
                  </div>
                </div>
                <div>
                  <label className="text-sm font-medium">Code de vérification (6 chiffres)</label>
                  <Input value={token} onChange={(e) => setToken(e.target.value.replace(/\D/g, '').slice(0, 6))} placeholder="000000" className="font-mono text-center text-lg tracking-widest" maxLength={6} />
                </div>
                <div className="flex gap-2">
                  <Button variant="outline" onClick={() => setSetupMode(false)}>Annuler</Button>
                  <Button onClick={handleVerify} disabled={token.length !== 6}>Vérifier et activer</Button>
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <Shield className="w-8 h-8 text-[var(--color-text-secondary)]" />
              <div>
                <h3 className="font-semibold">2FA non activé</h3>
                <p className="text-sm text-[var(--color-text-secondary)]">Activez l'authentification à deux facteurs pour sécuriser votre compte.</p>
              </div>
            </div>
            <Button onClick={handleStartSetup}><Shield className="w-4 h-4 mr-1" /> Activer 2FA</Button>
          </div>
        )}
      </Card>
    </div>
  )
}
