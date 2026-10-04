import { supabase } from '@/lib/supabase'
import { fetchAllRows, getTenantId, ti, tud } from './core'
import type { SavedFilter } from '@/types'

// ============ Saved Filters ============

export async function getSavedFilters(pageName: string): Promise<SavedFilter[]> {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email || ''
  let q = supabase
    .from('saved_filters')
    .select('*')
    .eq('user_email', userEmail)
    .eq('page_name', pageName)
    .order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as SavedFilter[]
}

export async function createSavedFilter(filter: Omit<SavedFilter, 'id' | 'created_at'>): Promise<SavedFilter> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('saved_filters')
    .insert(ti(filter, 'saved_filters', tid))
    .select()
    .single()
  if (error) throw error
  return data as SavedFilter
}

export async function deleteSavedFilter(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('saved_filters').delete(), 'saved_filters', tid).eq('id', id)
  if (error) throw error
}

export async function setDefaultFilter(id: string, pageName: string): Promise<void> {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email || ''
  // Unset previous default
  await tud(supabase.from('saved_filters').update({ is_default: false }), 'saved_filters', tid)
    .eq('user_email', userEmail)
    .eq('page_name', pageName)
    .eq('is_default', true)
  // Set new default
  await tud(supabase.from('saved_filters').update({ is_default: true }), 'saved_filters', tid).eq('id', id)
}

// ============ Revenue Simulation ============

export async function getRevenueSimulation(period: 'month' | 'quarter' | 'year', growthRate: number) {
  const tid = await getTenantId()
  const now = new Date()
  let startDate = new Date(now)
  if (period === 'month') startDate.setMonth(now.getMonth() - 11)
  else if (period === 'quarter') startDate.setMonth(now.getMonth() - 11)
  else if (period === 'year') startDate.setFullYear(now.getFullYear() - 2)

  let q = supabase
    .from('invoices')
    .select('date, total')
    .eq('status', 'paid')
    .gte('date', startDate.toISOString().split('T')[0])
    .order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : la simulation part du CA réalisé — tronqué, elle projette sur une base fausse.
  const invoices = await fetchAllRows<any>(q, { label: 'getRevenueSimulation/invoices' })
  const byMonth: Record<string, number> = {}
  for (const inv of invoices as any[]) {
    const d = new Date(inv.date).toISOString().slice(0, 7)
    byMonth[d] = (byMonth[d] || 0) + Number(inv.total || 0)
  }

  const months = Object.keys(byMonth).sort()
  const currentRevenue = months.reduce((s, m) => s + byMonth[m], 0)
  const projectedRevenue = currentRevenue * (1 + growthRate / 100)

  const projection: { month: string; current: number; projected: number }[] = []
  for (const m of months) {
    projection.push({
      month: m,
      current: byMonth[m],
      projected: byMonth[m] * (1 + growthRate / 100),
    })
  }

  return { currentRevenue, projectedRevenue, projection }
}

// ============ Margin Analysis ============

export async function getMarginAnalysis(
  period: 'month' | 'quarter' | 'year',
  dimension: 'product' | 'customer' | 'category'
) {
  const tid = await getTenantId()
  const now = new Date()
  let startDate = new Date(now)
  if (period === 'month') startDate.setMonth(now.getMonth() - 1)
  else if (period === 'quarter') startDate.setMonth(now.getMonth() - 3)
  else if (period === 'year') startDate.setFullYear(now.getFullYear() - 1)

  // I-08 : la formule est désormais une fonction SQL NOMMÉE
  // (`metric_pilotage_marge`, migrations 465 → 467). Elle reproduit à
  // l'identique l'agrégat JavaScript qui était ici — dont le correctif
  // M10 (le coût vient du coût de revient de l'article, jamais d'une
  // estimation à 70 % du prix qui rendait la marge égale à 30 % quoi
  // qu'il arrive), la fenêtre de dates, et le filtre sur les factures
  // PAYÉES.
  //
  // Pourquoi le déplacer : la formule était recalculée À L'AFFICHAGE, en
  // JavaScript. Trois conséquences, toutes supprimées ici :
  //   * deux écrans, deux résultats si l'un des deux evolve ;
  //   * le client ne peut pas savoir avec quelle formule on a calculé ;
  //   * la base ne peut ni le dater, ni le.versionner (dictionnaire 461).
  // Elle est maintenant nommée, datée, et unique — `pilotage.marge_pct`.
  //
  // ⚠️ Les trois paramètres traduisent l'exigence EXACTE du code
  // précédent : `p_fin` reste `null` parce que l'ancien aggregat n'avait
  // qu'une borne basse (`.gte`), et `p_statut` vaut `'paid'` parce que
  // l'ancien code filtrait sur `.eq('invoice.status', 'paid')`. Toute
  // divergence ici changerait les chiffres affichés en silence — c'est
  // exactement ce que les migrations 466 et 467 ont redressé.
  const { data, error } = await supabase.rpc('metric_pilotage_marge', {
    p_tenant: tid,
    p_dimension: dimension,
    p_debut: startDate.toISOString().split('T')[0],
    p_fin: null,
    p_statut: 'paid',
  })
  if (error) throw error

  // La base rend `cle / chiffre_affaires / cout / marge / marge_pct` ; le
  // tableau de bord attend `name / revenue / cost / margin / marginPercent`
  // et le TRI PAR CHIFFRE D'AFFAIRES DÉCROISSANT. On ne change ni les
  // noms, ni l'ordre : un tableau de bord qui se réordonne seul fait
  // croire aux utilisateurs que les chiffres ont bougé.
  // La forme que rend la fonction SQL. Déclarée ici, pas `any` : la porte
  // `check-any-ceiling` refuse de voir la dette d'`any` augmenter, et elle
  // a raison — un `any` ici ferait perdre à la compilation la seule chose
  // qui nous protège : que le nom des colonnes rendues par la fonction
  // reste le bon.
  type LigneMarge = {
    cle: string
    chiffre_affaires: number
    cout: number
    marge: number
    marge_pct: number
  }

  return ((data ?? []) as unknown as LigneMarge[])
    .map((r) => ({
      name: r.cle,
      revenue: Number(r.chiffre_affaires ?? 0),
      cost: Number(r.cout ?? 0),
      margin: Number(r.marge ?? 0),
      marginPercent: Number(r.marge_pct ?? 0),
    }))
    .sort((a, b) => b.revenue - a.revenue)
}
