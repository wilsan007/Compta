-- 397 — roles_comptes_4
-- Numéro pris le 2026-10-11T09:32:25.895Z par migration-numero.mjs (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).

-- ═══════════════════════════════════════════════════════════════════════════
-- 397 — roles_comptes_4 : les DEUX derniers comptes en dur (LOC1-10, tranche 5)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Les deux occurrences que le garde-fou mesurait encore, et qu'on
-- avait laissées de côté parce que les réécrire **change les écritures**. Voici
-- l'arbitrage, avec sa preuve — le plan comptable de la base :
--
--   | code   | libellé (mesuré dans `chart_accounts`)                        |
--   |--------|---------------------------------------------------------------|
--   | 681100 | Dotations aux amortissements sur immobilisations INCORPORELLES |
--   | 681200 | Dotations aux amortissements sur immobilisations CORPORELLES   |
--   | 280000 | Amortissements des immobilisations incorporelles              |
--   | 281000 | Amortissements des immobilisations corporelles                |
--   | 511000 | Valeurs à l'encaissement                                      |
--   | 511200 | Dividendes à encaisser                                        |
--
-- 1. `ensure_pos_payment_methods` — 511200 pour la CARTE et le CHÈQUE. Le plan
--    dit « Dividendes à encaisser » : ce n'est pas un moyen de paiement. Le rôle
--    `MOYENS_PAIEMENT_A_ENCAISSER` vaut 511000 (« Valeurs à l'encaissement »),
--    qui EST le compte des moyens de paiement à encaisser. **Correction**, et
--    la carte et le chèque suivent désormais le pack. Les espèces (530000)
--    passent par `CAISSE` : écriture identique.
--
-- 2. `generate_depreciation_entry` — 681200 / 281000. La paire est COHÉRENTE
--    (corporelles des deux côtés), mais elle était en dur, et le rôle unique du
--    pack (`DOTATIONS_AMORTISSEMENTS` = 681100) aurait écrit une paire
--    INCOHÉRENTE : dotation d'incorporel contre amortissement de corporel.
--    D'où **quatre rôles par nature** (incorporel / corporel), mappés au PCG sur
--    exactement les numéros d'avant. La fiche de l'immobilisation reste
--    prioritaire ; à défaut, la nature vient de `category` / `asset_type`, et
--    **le corporel est le défaut** — la paire d'avant. **Aucune écriture ne
--    change** pour les fiches déjà saisies (`materiel` = corporel).
--
-- ⚠ Le catalogue fermé de la `383` passe de 67 à **71** rôles, et le référentiel
-- PCG de 65 à **69** mappings. Les deux suites qui les comptent sont ajustées
-- dans le même commit, avec la raison : le catalogue et le pack sont des
-- SUPER-ENSEMBLES datés, ils suivent les besoins réels — c'est déjà la règle
-- appliquée aux rôles de journaux (8 → 11 en 387/389).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 0. `resolve_account` : un drapeau pour les DÉFAUTS
--
-- Le trigger `tenant_default_pos_payment_methods` sème les moyens de paiement
-- À LA CRÉATION de la société — donc AVANT que son plan comptable existe. Sans
-- ce drapeau, résoudre l'espèce (CAISSE) y échouait en `COMPTE_ABSENT` et
-- **toute création de société tombait** (mesuré : 102, 211, 353… toutes rouges).
--
-- Le contrôle du plan garde tout son sens pour un compte qui va être ÉCRIT :
-- c'est lui qui garantit qu'une écriture ne part pas sur un compte inexistant.
-- Il n'en a aucun pour un DÉFAUT mémorisé, résolu plus tard, au moment de
-- l'écriture. `p_check_chart DEFAULT true` : aucun appelant existant ne change,
-- et celui qui veut un défaut le DIT (`false`) — le drapeau se lit à l'appel.
-- ─────────────────────────────────────────────────────────────
-- Un paramètre supplémentaire ne s'AJOUTE pas : il REMPLACE. Créer une surcharge
-- à 4 arguments laissait DEUX fonctions appelables avec 2 arguments, et
-- `resolve_account(uuid, 'CAISSE')` devenait ambigu (« function … is not
-- unique », mesuré sur 102/211/353). On retire donc l'ancienne signature.
DROP FUNCTION IF EXISTS resolve_account(uuid, text, jsonb);

CREATE OR REPLACE FUNCTION resolve_account(p_tenant_id uuid, p_role text, p_context jsonb DEFAULT '{}'::jsonb,
                                           p_check_chart boolean DEFAULT true)
RETURNS text
LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE v text;
BEGIN
  -- 1. surcharge objet métier
  v := resolve_account_from_context(p_tenant_id, p_role, p_context);

  -- 2. surcharge société
  IF v IS NULL THEN
    SELECT account_code INTO v FROM tenant_account_roles
     WHERE tenant_id = p_tenant_id AND role = p_role;
  END IF;

  -- 3. rôle du pack effectif (le plus spécifique gagne)
  IF v IS NULL THEN
    SELECT par.account_code INTO v
      FROM pack_lineage(tenant_pack_code(p_tenant_id)) l
      JOIN pack_account_roles par ON par.pack_code = l.code AND par.role = p_role
     ORDER BY l.depth LIMIT 1;
  END IF;

  -- 4. échec explicite — jamais de repli silencieux
  IF v IS NULL THEN
    RAISE EXCEPTION 'ROLE_NON_MAPPE: le rôle % n''a aucun compte pour la société %', p_role, p_tenant_id
      USING ERRCODE = 'P0001', HINT = 'Paramétrage > Comptes par défaut';
  END IF;

  -- 5. le compte doit exister dans le plan de la société
  --    (sauf pour un DÉFAUT : `p_check_chart = false`, voir la section 0)
  IF p_check_chart AND NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id AND code = v) THEN
    RAISE EXCEPTION 'COMPTE_ABSENT: le rôle % pointe vers % absent du plan', p_role, v
      USING ERRCODE = 'P0001';
  END IF;

  RETURN v;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 0 bis. `tenant_pack_code` : le PONT « société sans pack »
--
-- Une société n'a pas de pack au moment où elle est créée — ni plan comptable,
-- ni pack choisi. La résolution s'arrêtait donc à l'étape 3 et levait
-- `ROLE_NON_MAPPE`. Ce pont était écrit À LA MAIN dans chaque trigger de la
-- `386` (`IF v_pack IS NULL THEN SELECT code FROM legislation_packs WHERE
-- is_default…`) ; il vit désormais ICI, une fois pour toutes : une société sans
-- pack lit le pack MARQUÉ PAR DÉFAUT (`legislation_packs.is_default`, FR
-- aujourd'hui). C'est la règle de la PHASE 1 — et elle ne nomme aucun pays :
-- le jour où le pack par défaut change, c'est une ligne de données qui change.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tenant_pack_code(p_tenant_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(NULLIF(btrim(t.legislation_pack_code), ''),
                  (SELECT p.code FROM legislation_packs p
                    WHERE p.is_default AND p.active ORDER BY p.code LIMIT 1))
  FROM tenants t WHERE t.id = p_tenant_id;
$function$;

-- ─────────────────────────────────────────────────────────────
-- 1. Les quatre rôles d'amortissement, par NATURE (catalogue + pack PCG)
-- ─────────────────────────────────────────────────────────────
INSERT INTO account_role_catalog (role, family, normal_side, required_for) VALUES
  ('AMORTISSEMENTS_INCORPORELLES',            'immobilisations', 'credit', ARRAY['assets']),
  ('DOTATIONS_AMORTISSEMENTS_INCORPORELLES',  'immobilisations', 'debit',  ARRAY['assets']),
  ('AMORTISSEMENTS_CORPORELLES',              'immobilisations', 'credit', ARRAY['assets']),
  ('DOTATIONS_AMORTISSEMENTS_CORPORELLES',    'immobilisations', 'debit',  ARRAY['assets'])
ON CONFLICT (role) DO NOTHING;

INSERT INTO pack_account_roles (pack_code, role, account_code) VALUES
  ('PCG', 'AMORTISSEMENTS_INCORPORELLES',           '280000'),
  ('PCG', 'DOTATIONS_AMORTISSEMENTS_INCORPORELLES', '681100'),
  ('PCG', 'AMORTISSEMENTS_CORPORELLES',             '281000'),
  ('PCG', 'DOTATIONS_AMORTISSEMENTS_CORPORELLES',   '681200')
ON CONFLICT (pack_code, role) DO UPDATE SET account_code = EXCLUDED.account_code;

-- ─────────────────────────────────────────────────────────────
-- 2. Moyens de paiement du point de vente : les comptes des rôles
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_pos_payment_methods(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caisse text;
  v_encaissement text;
BEGIN
  IF p_tenant_id IS NULL THEN RETURN; END IF;
  -- LOC1-10 : les espèces passent par CAISSE (530000, identique), la carte et le
  -- chèque par MOYENS_PAIEMENT_A_ENCAISSER (511000). 511200 était écrit en clair
  -- et le plan y lit « Dividendes à encaisser » — ce n'est pas un moyen de
  -- paiement. Les deux résolutions se font AVANT l'insertion : une société dont
  -- le pack ne mappe pas ces rôles échoue ici, pas au milieu de ses moyens.
  -- `p_check_chart = false` : ce sont des DÉFAUTS semés à la création de la
  -- société, quand son plan n'existe pas encore (section 0) ; le compte est
  -- vérifié plus tard, au moment de l'écriture, par la clôture de caisse.
  v_caisse := resolve_account(p_tenant_id, 'CAISSE', '{}'::jsonb, false);
  v_encaissement := resolve_account(p_tenant_id, 'MOYENS_PAIEMENT_A_ENCAISSER', '{}'::jsonb, false);
  INSERT INTO pos_payment_methods (tenant_id, name, type, account_code, opens_cash_drawer, is_active, display_order)
  SELECT p_tenant_id, d.name, d.type, d.account_code, d.opens, true, d.ord
  FROM (VALUES ('Espèces', 'cash', v_caisse, true, 1),
               ('Carte bancaire', 'card', v_encaissement, false, 2),
               ('Chèque', 'check', v_encaissement, false, 3)) d(name, type, account_code, opens, ord)
  WHERE NOT EXISTS (SELECT 1 FROM pos_payment_methods m WHERE m.tenant_id = p_tenant_id AND m.type = d.type);
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 3. Dotation aux amortissements : la paire par NATURE
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_depreciation_entry(p_fixed_asset_id uuid, p_fiscal_year_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fa fixed_assets%ROWTYPE;
  v_fy fiscal_years%ROWTYPE;
  v_methode text;
  v_base numeric;
  v_annuel numeric;
  v_amount numeric;
  v_cumul numeric;
  v_total numeric;
  v_annees int;
  v_taux numeric;
  v_debit text;
  v_credit text;
  v_number text;
  v_ref text;
  v_je uuid;
  v_existe uuid;
  v_journal text;
  v_incorporel boolean;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fa FROM fixed_assets WHERE id = p_fixed_asset_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Immobilisation introuvable : %', p_fixed_asset_id; END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exercice introuvable : %', p_fiscal_year_id; END IF;

  -- IMMO-03 : une dotation d'exercice CLOS ne se recalcule pas. Le cumul vient
  -- de l'historique, l'exercice de la demande — jamais de la date du jour.
  IF v_fy.status <> 'open' THEN
    RAISE EXCEPTION 'Exercice % : statut % — une dotation d''exercice clos ne se recalcule pas', v_fy.code, v_fy.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotence : une dotation déjà comptabilisée est rendue telle quelle
  v_ref := 'AMORT:' || v_fa.id || ':' || v_fy.code;
  SELECT id INTO v_existe FROM journal_entries
  WHERE tenant_id = v_tid AND reference = v_ref LIMIT 1;
  IF v_existe IS NOT NULL THEN RETURN v_existe; END IF;

  IF v_fa.status <> 'active' THEN
    RAISE EXCEPTION 'Immobilisation % : statut % — aucune dotation à comptabiliser', v_fa.name, v_fa.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- IMMO-04 : la méthode est LUE. Les deux façons d'écrire le linéaire que le
  -- dépôt connaît (l'écran écrit `straight_line`, les reprises `linear`)
  -- désignent le MÊME moteur.
  v_methode := lower(COALESCE(NULLIF(btrim(v_fa.depreciation_method), ''), 'linear'));
  IF v_methode NOT IN ('linear', 'straight_line', 'declining', 'declining_balance') THEN
    IF v_methode = 'units_of_production' THEN
      RAISE EXCEPTION 'Immobilisation % : méthode « units_of_production » RETIRÉE — la fiche ne porte aucun compteur d''unités produites, une dotation par unité serait une donnée inventée ; utilisez linear ou declining_balance', v_fa.name
        USING ERRCODE = 'feature_not_supported';
    END IF;
    RAISE EXCEPTION 'Immobilisation % : méthode d''amortissement « % » inconnue (attendu : linear, straight_line, declining_balance)', v_fa.name, v_methode
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_base := GREATEST(COALESCE(v_fa.purchase_value, 0) - COALESCE(v_fa.residual_value, 0), 0);
  IF v_base = 0 OR COALESCE(v_fa.useful_life_years, 0) <= 0 THEN
    RETURN NULL;  -- rien à amortir
  END IF;

  -- Amortissements déjà dotés : l'historique fait foi, pas la valeur courante.
  -- `v_annees` compte les exercices déjà dotés (la bascule du dégressif en
  -- dépend) ; le cumul est plafonné à la base amortissable.
  SELECT COALESCE(sum(amount), 0), count(*) INTO v_cumul, v_annees
  FROM asset_depreciations
  WHERE tenant_id = v_tid AND asset_id = v_fa.id AND depreciation_type = 'dotation';
  v_cumul := LEAST(v_cumul, v_base);

  IF v_methode IN ('declining', 'declining_balance') THEN
    -- Taux dégressif = coefficient légal / durée, avec BASCULE sur le linéaire
    -- du restant dès que celui-ci devient plus favorable.
    v_taux := depreciation_coefficient(v_tid, v_fa.useful_life_years) / v_fa.useful_life_years;
    v_taux := GREATEST(v_taux, 1.0 / GREATEST(v_fa.useful_life_years - v_annees, 1));
    v_annuel := round(GREATEST(v_base - v_cumul, 0) * v_taux, 2);
  ELSE
    v_annuel := round(v_base / v_fa.useful_life_years, 2);
  END IF;
  v_amount := v_annuel;

  -- Prorata temporis en jours pour l'exercice d'acquisition
  IF v_fa.purchase_date > v_fy.start_date THEN
    v_amount := round(v_annuel * ((v_fy.end_date - v_fa.purchase_date) + 1)::numeric
                             / ((v_fy.end_date - v_fy.start_date) + 1), 2);
  END IF;

  -- Jamais plus que la base amortissable
  v_amount := LEAST(v_amount, round(v_base - v_cumul, 2));
  IF v_amount <= 0 THEN RETURN NULL; END IF;

  -- Comptes : ceux de l'IMMOBILISATION d'abord (la fiche fait foi), sinon les
  -- RÔLES — par NATURE. LOC1-10 : le plan sépare l'incorporel du corporel
  -- (681100 / 280000 contre 681200 / 281000), donc un rôle unique écrirait une
  -- paire INCOHÉRENTE. La nature se lit dans `category` / `asset_type` ; à
  -- défaut, CORPORELLE — la paire d'avant, et celle des fiches déjà saisies
  -- (`materiel`), donc aucune écriture existante ne change.
  v_incorporel := (COALESCE(v_fa.category, '') || ' ' || COALESCE(v_fa.asset_type, ''))
                  ~* 'incorporel|incorpore|intangible|immatériel';
  v_debit := COALESCE(NULLIF(btrim(v_fa.account_expense_depreciation_code), ''),
                      resolve_account(v_tid, CASE WHEN v_incorporel
                        THEN 'DOTATIONS_AMORTISSEMENTS_INCORPORELLES'
                        ELSE 'DOTATIONS_AMORTISSEMENTS_CORPORELLES' END));
  v_credit := COALESCE(NULLIF(btrim(v_fa.account_depreciation_code), ''),
                       resolve_account(v_tid, CASE WHEN v_incorporel
                         THEN 'AMORTISSEMENTS_INCORPORELLES'
                         ELSE 'AMORTISSEMENTS_CORPORELLES' END));
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_debit) THEN
    RAISE EXCEPTION 'Compte de dotation % absent du plan comptable de la société', v_debit
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_credit) THEN
    RAISE EXCEPTION 'Compte d''amortissement % absent du plan comptable de la société', v_credit
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- LOC1-09 : le journal vient du RÔLE (et il est garanti)
  PERFORM ensure_standard_journals(v_tid);
  v_journal := resolve_journal(v_tid, 'JOURNAL_OD');

  -- 1. en-tête en brouillard (AUD-C02)
  v_number := 'AMORT-' || COALESCE(NULLIF(btrim(v_fa.code), ''), NULLIF(btrim(v_fa.asset_number), ''),
                                   left(v_fa.id::text, 8)) || '-' || v_fy.code;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_tid, v_number, v_fy.end_date, v_journal, 'draft',
          'Dotation aux amortissements ' || v_fy.code || ' ('
            || CASE WHEN v_methode IN ('declining', 'declining_balance') THEN 'dégressif' ELSE 'linéaire' END
            || ') - ' || v_fa.name,
          v_ref, v_number)
  RETURNING id INTO v_je;

  -- 2. lignes
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
  VALUES
    (v_tid, v_je, v_debit,  'Dotations aux amortissements', v_amount, 0, 'Dotation ' || v_fy.code),
    (v_tid, v_je, v_credit, 'Amortissements', 0, v_amount, 'Dotation ' || v_fy.code);

  -- 3. validation : les triggers de la 187 vérifient équilibre, exercice, comptes
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  -- Historique de l'immobilisation + valeur nette.
  -- 226 : la VNC est la valeur d'ACQUISITION moins le cumul — la résiduelle est
  -- déjà hors de la base amortissable, la retrancher ici la déduirait deux fois.
  v_total := v_cumul + v_amount;
  INSERT INTO asset_depreciations (tenant_id, asset_id, fiscal_year_code, period, depreciation_type,
    amount, cumulative_amount, net_book_value, entry_number)
  VALUES (v_tid, v_fa.id, v_fy.code, 12, 'dotation', v_amount, v_total,
    round(GREATEST(COALESCE(v_fa.purchase_value, 0) - v_total, 0), 2), v_number);

  UPDATE fixed_assets
  SET current_value = GREATEST(COALESCE(purchase_value, 0) - v_total, 0),
      status = CASE WHEN v_total >= v_base THEN 'fully_depreciated' ELSE status END,
      updated_at = now()
  WHERE id = v_fa.id AND tenant_id = v_tid;

  RETURN v_je;
END $function$;

