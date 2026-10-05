import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Badge, Card, EmptyState, PageHeader, SkeletonTable, StatCard, Table, TableRow, TableCell } from '@/components/ui'
import { errorMessage, formatDate } from '@/lib/utils'
import { getChainCoherenceIndex, getChainInvariants, type ChainInvariant } from '@/lib/queries/chainCoherence'

// ============================================================
// A2.4 — l'ÉCRAN de l'indice de cohérence (L4/L5).
//
// Le module `chainCoherence.ts` rend l'indice lisible ; cette page le MONTRET :
// le score (tenu / rompu / non mesuré / total), la date du dernier relevé, et le
// détail par invariant. Elle NE mesure rien — c'est le job `audit_chains_nocturne`
// (base) — ni ne relance d'alerte.
//
// DEUX RÈGLES TENUES ICI, comme le composant de la frise.
//
// 1. **`rompu` et `non_mesure` ne se confondent pas.** Un invariant qu'on ne
//    sait pas mesurer n'est PAS une alerte : il est compté à part, et la page
//    ne le peint pas en rouge. C'est la doctrine du dépôt — « rien n'est annoncé
//    que la base ne l'ait confirmé ».
// 2. **Pas de journal console d'erreur.** La dette est gelée (plafond 488) ;
//    une erreur de lecture se dit à l'écran (`role="alert"`), comme dans
//    `ChainTimeline`.

type CoherenceIndex = Awaited<ReturnType<typeof getChainCoherenceIndex>>

const VERDICT_VARIANT: Record<ChainInvariant['verdict'], 'success' | 'danger' | 'neutral'> = {
  tenu: 'success',
  rompu: 'danger',
  non_mesure: 'neutral',
}

export function CoherencePage() {
  const { t } = useTranslation('crossModule')
  const [invariants, setInvariants] = useState<ChainInvariant[]>([])
  const [index, setIndex] = useState<CoherenceIndex | null>(null)
  const [chargement, setChargement] = useState(true)
  const [erreur, setErreur] = useState<string | null>(null)

  useEffect(() => {
    let annule = false
    setChargement(true)
    setErreur(null)
    Promise.all([getChainInvariants(), getChainCoherenceIndex()])
      .then(([inv, idx]) => {
        if (annule) return
        setInvariants(inv)
        setIndex(idx)
      })
      .catch((e: unknown) => !annule && setErreur(errorMessage(e)))
      .finally(() => !annule && setChargement(false))
    return () => {
      annule = true
    }
  }, [])

  const verdictLabel: Record<ChainInvariant['verdict'], string> = {
    tenu: t('coherence.verdictTenu'),
    rompu: t('coherence.verdictRompu'),
    non_mesure: t('coherence.verdictNonMesure'),
  }

  if (chargement) return <SkeletonTable rows={6} />

  return (
    <div>
      <PageHeader title={t('coherence.title')} subtitle={t('coherence.subtitle')} />

      {erreur && (
        <div className="text-sm text-[var(--color-danger)] mb-4" role="alert">
          {t('chain.error', { message: erreur })}
        </div>
      )}

      {index && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
          <StatCard label={t('coherence.tenu')} value={String(index.tenu)} color="success" />
          <StatCard label={t('coherence.rompu')} value={String(index.rompu)} color="danger" />
          <StatCard label={t('coherence.nonMesure')} value={String(index.non_mesure)} color="warning" />
          <StatCard label={t('coherence.total')} value={String(index.total)} color="primary" />
        </div>
      )}

      <p className="text-sm text-[var(--color-text-secondary)] mb-4">
        {index?.mesure_le
          ? t('coherence.mesureLe', { date: formatDate(index.mesure_le) })
          : t('coherence.jamaisMesure')}
      </p>

      {invariants.length === 0 ? (
        <EmptyState title={t('coherence.vide')} description={t('coherence.videDescription')} />
      ) : (
        <Card>
          <Table
            headers={[
              t('coherence.code'),
              t('coherence.libelle'),
              t('coherence.modules'),
              t('coherence.verdict'),
              t('coherence.ecart'),
              t('coherence.lignes'),
              t('coherence.releves'),
            ]}
          >
            <tbody>
              {invariants.map((inv) => (
                <TableRow key={inv.code}>
                  <TableCell className="font-mono text-xs">{inv.code}</TableCell>
                  <TableCell>{inv.libelle}</TableCell>
                  <TableCell className="font-mono text-xs">{inv.modules.join(', ') || '—'}</TableCell>
                  <TableCell>
                    <Badge variant={VERDICT_VARIANT[inv.verdict]}>{verdictLabel[inv.verdict]}</Badge>
                  </TableCell>
                  <TableCell>{inv.ecart === null ? '—' : inv.ecart}</TableCell>
                  <TableCell>{inv.lignes_en_ecart}</TableCell>
                  <TableCell>{inv.nb_releves}</TableCell>
                </TableRow>
              ))}
            </tbody>
          </Table>
        </Card>
      )}
    </div>
  )
}
