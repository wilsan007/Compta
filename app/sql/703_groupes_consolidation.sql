-- 703 — groupes_consolidation
--
-- ============================================================
-- F.4 / GRP-03 : LA CONSOLIDATION DES COMPTES D'UN GROUPE
--
-- Ce que cette fonction rend, et ce qu'elle ne prétend PAS être. C'est une
-- consolidation de PREMIER NIVEAU, mesurée et bornée :
--   * elle agrège les lignes du grand livre des sociétés membres, par compte,
--     sur une période, en appliquant la MÉTHODE de chaque membre :
--       - `full`         → poids 1 (intégration globale) ;
--       - `proportional` → poids = détention (intégration proportionnelle) ;
--       - `equity` et `none` → EXCLUS de l'agrégat (voir les limites) ;
--   * elle rapporte, à part, les FLUX INTRA-GROUPE de la période — ce qu'il
--     faudra éliminer. Elle ne les élimine PAS elle-même : l'élimination
--     suppose de savoir à quel compte chaque flux correspond, et
--     `intra_group_transactions` porte le montant, pas l'écriture. Le faire à
--     l'aveugle serait un faux : on publie le total.
--
-- LIMITES DITES :
--   * la MISE EN ÉQUIVALENCE (`equity`) n'est pas calculée — elle vaut une ligne
--     de « titres mis en équivalence » qui n'existe pas encore ; les membres
--     `equity` sont listés mais hors agrégat ;
--   * pas d'élimination automatique des flux intra-groupe (ci-dessus) ;
--   * pas de conversion de devises : les montants sont additionnés tels quels.
--     Un groupe multi-devises ne lira un total homogène que si ses sociétés
--     partagent la même devise (limite écrite, pas tue).
--
-- LA GARDE. La fonction lit le grand livre d'AUTRES sociétés : c'est le seul
-- endroit du produit où c'est légitime, et il est réservé à un ADMINISTRATEUR
-- d'une société membre du groupe. Un membre non administrateur, ou une société
-- hors du groupe, sont refusés nommément.
-- ============================================================
-- Numéro pris le 2026-10-06T06:30:25.742Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).

CREATE OR REPLACE FUNCTION group_consolidated_balance(
  p_group_id uuid,
  p_from     date,
  p_to       date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Aucune société active';
  END IF;
  IF NOT _is_admin_of_current_tenant() THEN
    RAISE EXCEPTION 'GROUP_FORBIDDEN : seul un administrateur consolide un groupe';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = p_group_id AND tenant_id = v_tenant) THEN
    RAISE EXCEPTION 'GROUP_NOT_MEMBER : votre société n''appartient pas à ce groupe';
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
    RAISE EXCEPTION 'GROUP_PERIOD_INVALID : période absente ou inversée';
  END IF;

  RETURN jsonb_build_object(
    'group_id', p_group_id,
    'from', p_from,
    'to', p_to,
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'tenant_id', m.tenant_id,
        'name', t.name,
        'consolidation_method', m.consolidation_method,
        'ownership_pct', m.ownership_pct,
        'included', m.consolidation_method IN ('full', 'proportional')
      ) ORDER BY t.name)
      FROM group_members m JOIN tenants t ON t.id = m.tenant_id
      WHERE m.group_id = p_group_id
    ), '[]'::jsonb),
    'accounts', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'account', a.account_general,
        'debit', a.debit, 'credit', a.credit, 'balance', a.debit - a.credit
      ) ORDER BY a.account_general)
      FROM (
        SELECT jl.account_general,
               round(sum(jl.debit  * w.weight)::numeric, 2) AS debit,
               round(sum(jl.credit * w.weight)::numeric, 2) AS credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_id
        JOIN (
          SELECT tenant_id,
                 CASE consolidation_method
                   WHEN 'full'         THEN 1.0
                   WHEN 'proportional' THEN ownership_pct / 100.0
                   ELSE 0.0
                 END AS weight
          FROM group_members
          WHERE group_id = p_group_id
            AND consolidation_method IN ('full', 'proportional')
        ) w ON w.tenant_id = jl.tenant_id
        WHERE je.date >= p_from AND je.date <= p_to
          AND je.status = 'posted'
          AND jl.account_general IS NOT NULL
        GROUP BY jl.account_general
      ) a
    ), '[]'::jsonb),
    'intra_group', jsonb_build_object(
      'count', (SELECT count(*) FROM intra_group_transactions x
                 WHERE x.group_id = p_group_id
                   AND x.status <> 'cancelled'
                   AND x.transaction_date BETWEEN p_from AND p_to),
      'total_amount', COALESCE((SELECT sum(x.amount) FROM intra_group_transactions x
                 WHERE x.group_id = p_group_id
                   AND x.status <> 'cancelled'
                   AND x.transaction_date BETWEEN p_from AND p_to), 0)
    )
  );
END $$;

REVOKE ALL ON FUNCTION group_consolidated_balance(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION group_consolidated_balance(uuid, date, date) TO authenticated;

COMMENT ON FUNCTION group_consolidated_balance(uuid, date, date) IS
  'F.4/GRP-03 (703) : consolidation de premier niveau d''un groupe — agrégation '
  'du grand livre des membres par compte et par période, pondérée (full = 1, '
  'proportional = détention, equity/none exclus) ; les flux intra-groupe sont '
  'publiés pour élimination, pas éliminés. Réservée à un administrateur d''une '
  'société membre (seul cas légitime de lecture d''autres sociétés).';
