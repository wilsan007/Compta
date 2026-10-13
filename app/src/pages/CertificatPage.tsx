import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Badge, Card, EmptyState, PageHeader, SkeletonTable, StatCard, Table, TableRow, TableCell } from '@/components/ui'
import { errorMessage, formatDate } from '@/lib/utils'
import { getCertificatIntegrite, type Certificat } from '@/lib/queries/chainCertificat'

// ============================================================
// P1 — l'écran de l'ATTESTATION D'INTÉGRITÉ TECHNIQUE.
//
// Un artefact, DEUX LECTURES (décision Q2 du §6 bis) :
//   * page 1 — le DIRIGEANT : le score en clair, la date, « qui signe » ;
//   * annexe — l'EXPERT-COMPTABLE et la BANQUE : les écarts nommés, le banc,
//     l'empreinte NF-525 et le moyen de la re-vérifier.
//
// TROIS RÈGLES TENUES ICI.
//
// 1. **La mention est TOUJOURS visible**, jamais repliée : « attestation
//    d'intégrité technique — ne constitue ni un audit, ni une attestation de
//    l'expert-comptable, ni une certification légale » (Q1). Un lecteur qui ne
//    voit que la page 1 doit la lire.
// 2. **Aucun chiffre recalculé.** Tout vient de `chain_certificat_integrite` ;
//    l'écran ne mesure ni ne recompte rien.
// 3. **Pas de journal console d'erreur** (plafond gelé) : l'erreur se dit à
//    l'écran (`role="alert"`), comme dans `ChainTimeline`.

export function CertificatPage() {
  const { t } = useTranslation('crossModule')
  const [cert, setCert] = useState<Certificat | null>(null)
  const [chargement, setChargement] = useState(true)
  const [erreur, setErreur] = useState<string | null>(null)

  useEffect(() => {
    let annule = false
    setChargement(true)
    setErreur(null)
    getCertificatIntegrite()
      .then((c) => {
        if (!annule) setCert(c)
      })
      .catch((e: unknown) => !annule && setErreur(errorMessage(e)))
      .finally(() => !annule && setChargement(false))
    return () => {
      annule = true
    }
  }, [])

  if (chargement) return <SkeletonTable rows={6} />

  const bancDenominateur = cert ? cert.banc.maillons * cert.banc.epreuves_par_maillon : 0

  return (
    <div>
      <PageHeader title={t('certificat.title')} subtitle={t('certificat.subtitle')} />

      {/* ── LA MENTION — toujours visible (Q1) ─────────────────────────── */}
      <Card className="mb-4" title={t('certificat.mentionTitle')}>
        <p className="text-sm text-[var(--color-text-secondary)]" role="note">
          {t('certificat.mention')}
        </p>
      </Card>

      {erreur && (
        <div className="text-sm text-[var(--color-danger)] mb-4" role="alert">
          {t('chain.error', { message: erreur })}
        </div>
      )}

      {!cert && !erreur && (
        <EmptyState title={t('certificat.indisponible')} description={t('certificat.indisponibleDescription')} />
      )}

      {cert && (
        <>
          {/* ── PAGE 1 — LE DIRIGEANT ──────────────────────────────────── */}
          <Card className="mb-4" title={t('certificat.page1Title')}>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('certificat.emisLe')}</span><span>{formatDate(cert.emis_le)}</span></div>
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('certificat.version')}</span><span className="font-mono text-xs">{cert.version_migrations ?? '—'} ({cert.nb_migrations})</span></div>
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('certificat.signeQui')}</span><span>{t('certificat.signeSysteme')}</span></div>
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('certificat.endosse')}</span><span>{t('certificat.endosseTexte')}</span></div>
            </div>
          </Card>

          <div className="grid grid-cols-2 md:grid-cols-3 gap-4 mb-4">
            <StatCard label={t('certificat.tenu')} value={`${cert.invariants.tenu}/${cert.invariants.total}`} color="success" />
            <StatCard label={t('certificat.rompu')} value={String(cert.invariants.rompu)} color="danger" />
            <StatCard label={t('certificat.nonMesure')} value={String(cert.invariants.non_mesure)} color="warning" />
          </div>

          {/* ── ANNEXE — EXPERT-COMPTABLE, BANQUE ──────────────────────── */}
          <h2 className="text-lg font-semibold mb-2">{t('certificat.annexeTitle')}</h2>

          <Card className="mb-4" title={t('certificat.ecartsTitre')}>
            {cert.ecarts.length === 0 ? (
              <p className="text-sm text-[var(--color-text-secondary)]">{t('certificat.aucunEcart', { total: cert.invariants.total })}</p>
            ) : (
              <Table headers={[t('certificat.ecartCode'), t('certificat.ecartLibelle'), t('certificat.ecartLignes'), t('certificat.ecartMesure')]}>
                <tbody>
                  {cert.ecarts.map((e) => (
                    <TableRow key={e.code}>
                      <TableCell className="font-mono text-xs">{e.code}</TableCell>
                      <TableCell className="text-sm">{e.libelle}</TableCell>
                      <TableCell className="font-mono text-xs">{e.lignes_en_ecart}</TableCell>
                      <TableCell className="text-xs">{e.mesure_le ? formatDate(e.mesure_le) : '—'}</TableCell>
                    </TableRow>
                  ))}
                </tbody>
              </Table>
            )}
          </Card>

          <Card className="mb-4" title={t('certificat.bancTitre')}>
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <Badge variant="success">{t('certificat.bancTenues')} : {cert.banc.tenues}/{bancDenominateur}</Badge>
              <Badge variant="danger">{t('certificat.bancRompues')} : {cert.banc.rompues}</Badge>
              <Badge variant="neutral">{t('certificat.bancNonJouees')} : {cert.banc.non_jouees}</Badge>
            </div>
          </Card>

          <Card title={t('certificat.nf525Titre')}>
            <div className="space-y-1 text-sm">
              {cert.nf525.sans_objet ? (
                <p className="text-[var(--color-text-secondary)]">{t('certificat.nf525SansObjet')}</p>
              ) : cert.nf525.chain_valid ? (
                <p className="text-[var(--color-success)]">{t('certificat.nf525Valide', { total: cert.nf525.total_events ?? 0 })}</p>
              ) : (
                <p className="text-[var(--color-danger)]">{t('certificat.nf525Rompue', { ruptures: cert.nf525.broken_links ?? 0, total: cert.nf525.total_events ?? 0 })}</p>
              )}
              <p className="text-xs text-[var(--color-text-secondary)]">{t('certificat.nf525Reverif')}</p>
            </div>
          </Card>
        </>
      )}
    </div>
  )
}
