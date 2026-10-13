import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Badge, Card, EmptyState, PageHeader, SkeletonTable, StatCard, Table, TableRow, TableCell } from '@/components/ui'
import { errorMessage, formatDate } from '@/lib/utils'
import { EPREUVES_BANC, getChainBanc, type BancMaillon, type BancVerdict } from '@/lib/queries/chainRobustness'

// ============================================================
// A2.3 — l'ÉCRAN du banc d'épreuves (L5, page « Robustesse »).
//
// Le référentiel (D.4) promet « une page qui indique, pour chaque chaîne, le
// résultat des huit épreuves ». Cette page le tient : une ligne par maillon,
// huit colonnes D1 → D8, chacune portant son DERNIER verdict.
//
// TROIS RÈGLES TENUES ICI.
//
// 1. **Aucun `tenu` par défaut.** Une épreuve jamais jouée s'affiche `non joué`
//    (gris), pas `tenu` : l'absence est publiée, elle ne peut pas passer pour
//    un succès — c'est la doctrine du banc (433).
// 2. **Trois teintes, trois sens.** `rompu` est la seule en rouge ; `non joué`
//    n'est PAS une alerte, c'est un instrument qui manque.
// 3. **Pas de journal console d'erreur** (plafond gelé) : une erreur de lecture
//    se dit à l'écran (`role="alert"`), comme dans `ChainTimeline`.

const VERDICT_VARIANT: Record<BancVerdict, 'success' | 'danger' | 'neutral'> = {
  tenu: 'success',
  rompu: 'danger',
  non_joue: 'neutral',
}

export function RobustessePage() {
  const { t } = useTranslation('crossModule')
  const [maillons, setMaillons] = useState<BancMaillon[]>([])
  const [chargement, setChargement] = useState(true)
  const [erreur, setErreur] = useState<string | null>(null)

  useEffect(() => {
    let annule = false
    setChargement(true)
    setErreur(null)
    getChainBanc()
      .then((m) => {
        if (!annule) setMaillons(m)
      })
      .catch((e: unknown) => !annule && setErreur(errorMessage(e)))
      .finally(() => !annule && setChargement(false))
    return () => {
      annule = true
    }
  }, [])

  const verdictLabel: Record<BancVerdict, string> = {
    tenu: t('robustesse.verdictTenu'),
    rompu: t('robustesse.verdictRompu'),
    non_joue: t('robustesse.verdictNonJoue'),
  }

  if (chargement) return <SkeletonTable rows={6} />

  const tenues = maillons.reduce((s, m) => s + m.tenues, 0)
  const rompues = maillons.reduce((s, m) => s + m.rompues, 0)
  const nonJouees = maillons.reduce((s, m) => s + m.nonJouees, 0)
  const dernier = maillons.reduce<string | null>(
    (acc, m) => (m.passe_le && (!acc || m.passe_le > acc) ? m.passe_le : acc),
    null,
  )

  return (
    <div>
      <PageHeader title={t('robustesse.title')} subtitle={t('robustesse.subtitle')} />

      {erreur && (
        <div className="text-sm text-[var(--color-danger)] mb-4" role="alert">
          {t('chain.error', { message: erreur })}
        </div>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
        <StatCard label={t('robustesse.maillons')} value={String(maillons.length)} color="primary" />
        <StatCard label={t('robustesse.tenues')} value={String(tenues)} color="success" />
        <StatCard label={t('robustesse.rompues')} value={String(rompues)} color="danger" />
        <StatCard label={t('robustesse.nonJouees')} value={String(nonJouees)} color="warning" />
      </div>

      <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('robustesse.legend')}</p>
      <p className="text-sm text-[var(--color-text-secondary)] mb-4">
        {dernier ? t('robustesse.passeLe', { date: formatDate(dernier) }) : t('robustesse.jamaisJoue')}
      </p>

      {maillons.length === 0 ? (
        <EmptyState title={t('robustesse.vide')} description={t('robustesse.videDescription')} />
      ) : (
        <Card>
          <Table headers={[t('robustesse.colMaillon'), ...EPREUVES_BANC, t('robustesse.colTenues')]}>
            <tbody>
              {maillons.map((m) => (
                <TableRow key={m.code}>
                  <TableCell>
                    <div className="font-medium">{m.libelle}</div>
                    <div className="font-mono text-xs text-[var(--color-text-secondary)]">{m.code}</div>
                  </TableCell>
                  {m.epreuves.map((ep) => (
                    <TableCell key={ep.epreuve}>
                      <Badge variant={VERDICT_VARIANT[ep.verdict]}>{verdictLabel[ep.verdict]}</Badge>
                    </TableCell>
                  ))}
                  <TableCell className="whitespace-nowrap">{m.tenues}/8</TableCell>
                </TableRow>
              ))}
            </tbody>
          </Table>
        </Card>
      )}
    </div>
  )
}
