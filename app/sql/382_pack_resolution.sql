-- ═══════════════════════════════════════════════════════════════════════════
-- 382 — pack_resolution : la RÉSOLUTION HÉRITÉE d'un pack (LOT 1-A, LOC1-03)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. La `380` a posé la hiérarchie `secteur → pays → référentiel`,
-- la `381` a posé les tables de contenu. La `382` les fait PARLER : à partir
-- d'un code de pack, on remonte la lignée et on lit la valeur qu'il faut —
-- « le plus profond gagne » pour un rôle, « l'union » pour une liste. C'est le
-- même modèle que SAP (country chart sur operating chart, group chart au-dessus)
-- et qu'Odoo (une localisation pays hérite de la base générique par `parent_id`
-- et surcharge ligne à ligne). Cahier §5, tâche LOC1-03.
--
-- DEUX RÈGLES DE FUSION, ET ELLES NE SONT PAS INTERCHANGEABLES.
--   * valeur unique (rôle de compte, rôle de journal, format, capacité) : la
--     PLUS SPÉCIFIQUE gagne — on parcourt la lignée du pack vers la racine et on
--     prend la première définie ;
--   * ensemble (jours fériés, taux, autres taxes) : l'UNION de la lignée — un
--     férié du référentiel n'est pas « remplacé » par un férié du pays, il
--     s'ajoute.
--
-- REJOUABLE : `CREATE OR REPLACE` partout (fonction et vue).
--
-- Numéro pris le 2026-10-05T18:57:09.758Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. La lignée d'un pack — depth 0 = le pack lui-même, puis ses ancêtres
--    (bornée à la profondeur 3 : secteur → pays → référentiel).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION pack_lineage(p_pack_code text)
RETURNS TABLE (code text, depth int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH RECURSIVE l AS (
    SELECT lp.code, lp.parent_code, 0 AS depth
      FROM legislation_packs lp WHERE lp.code = p_pack_code
    UNION ALL
    SELECT lp.code, lp.parent_code, l.depth + 1
      FROM legislation_packs lp JOIN l ON lp.code = l.parent_code
     WHERE l.depth < 3
  )
  SELECT code, depth FROM l ORDER BY depth;
$$;

COMMENT ON FUNCTION pack_lineage(text) IS
  '382 (LOC1-03) : la lignée d''un pack, depth 0 = lui-même, puis parent, grand-parent (secteur → pays → référentiel). Base de toute résolution héritée.';

-- ─────────────────────────────────────────────────────────────
-- 2. Le pack effectif d'une société
--    ⚠️ SECURITY **INVOKER**, pas DEFINER : `tenants` est en RLS stricte
--    (`id = current_tenant_id()`) ET forcée. En INVOKER, un appelant ne peut donc
--    lire QUE sa propre société — la RLS fait la garde. En DEFINER, la fonction
--    agirait au nom de n''importe quelle société sans vérifier l''appartenance
--    (ce que refuserait `ci/check_tenant_guard.sql`).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tenant_pack_code(p_tenant_id uuid)
RETURNS text
LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  SELECT legislation_pack_code FROM tenants WHERE id = p_tenant_id;
$$;

-- ─────────────────────────────────────────────────────────────
-- 3. Une valeur de format résolue : le premier NON NULL en remontant la lignée
--    (la colonne est choisie dans une liste CLOSE — jamais un nom libre).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION pack_effective_value(p_pack_code text, p_column text)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v text;
BEGIN
  IF p_column NOT IN (
      'currency','currency_decimals','locale','date_format','fiscal_year_start',
      'tax_id_label','tax_id_secondary_label','number_system','ui_languages',
      'document_languages','week_start','weekend_days','price_decimals',
      'quantity_decimals','rounding_mode','rounding_level') THEN
    RAISE EXCEPTION 'COLONNE_NON_RESOLUBLE: %', p_column USING ERRCODE = 'P0001';
  END IF;

  EXECUTE format(
    'SELECT lp.%I::text FROM legislation_packs lp JOIN pack_lineage(%L) l ON l.code = lp.code '
    'WHERE lp.%I IS NOT NULL ORDER BY l.depth LIMIT 1', p_column, p_pack_code, p_column)
  INTO v;
  RETURN v;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 4. v_pack_effective — les colonnes de format RÉSOLUES, pack par pack
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_pack_effective AS
SELECT lp.code AS pack_code,
       lp.level,
       lp.parent_code,
       lp.status,
       lp.version,
       pack_effective_value(lp.code, 'currency')::text            AS currency,
       pack_effective_value(lp.code, 'currency_decimals')::int     AS currency_decimals,
       pack_effective_value(lp.code, 'price_decimals')::int        AS price_decimals,
       pack_effective_value(lp.code, 'quantity_decimals')::int     AS quantity_decimals,
       pack_effective_value(lp.code, 'locale')::text               AS locale,
       pack_effective_value(lp.code, 'date_format')::text          AS date_format,
       pack_effective_value(lp.code, 'fiscal_year_start')::text    AS fiscal_year_start,
       pack_effective_value(lp.code, 'number_system')::text        AS number_system,
       pack_effective_value(lp.code, 'ui_languages')::text[]       AS ui_languages,
       pack_effective_value(lp.code, 'document_languages')::text[] AS document_languages,
       pack_effective_value(lp.code, 'week_start')::int            AS week_start,
       pack_effective_value(lp.code, 'weekend_days')::int[]        AS weekend_days,
       pack_effective_value(lp.code, 'rounding_mode')::text        AS rounding_mode,
       pack_effective_value(lp.code, 'rounding_level')::text       AS rounding_level
  FROM legislation_packs lp
 WHERE lp.active;

COMMENT ON VIEW v_pack_effective IS
  '382 (LOC1-03) : pour chaque pack actif, les colonnes de format RÉSOLUES par la lignée (le plus spécifique gagne). Le front la lit une fois par getActiveLegislationPack().';

-- ─────────────────────────────────────────────────────────────
-- 5. Rôles portés par la lignée — LE PLUS PROFOND GAGNE
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION pack_account_role(p_pack_code text, p_role text)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT par.account_code
    FROM pack_lineage(p_pack_code) l
    JOIN pack_account_roles par ON par.pack_code = l.code AND par.role = p_role
   ORDER BY l.depth LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION pack_journal_role(p_pack_code text, p_role text)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT pjr.journal_code
    FROM pack_lineage(p_pack_code) l
    JOIN pack_journal_roles pjr ON pjr.pack_code = l.code AND pjr.role = p_role
   ORDER BY l.depth LIMIT 1;
$$;

-- ─────────────────────────────────────────────────────────────
-- 6. Jours fériés de la lignée — UNION (le pays AJOUTE au référentiel)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION pack_holidays_of(p_pack_code text)
RETURNS TABLE (holiday_date date, label text, label_ar text, is_variable boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT DISTINCT ON (h.holiday_date) h.holiday_date, h.label, h.label_ar, h.is_variable
    FROM pack_lineage(p_pack_code) l
    JOIN pack_holidays h ON h.pack_code = l.code
   ORDER BY h.holiday_date, l.depth;
$$;

-- ─────────────────────────────────────────────────────────────
-- 7. Droits : ce sont des LECTURES, réservées aux utilisateurs connectés
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION pack_lineage(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION tenant_pack_code(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION pack_effective_value(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION pack_account_role(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION pack_journal_role(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION pack_holidays_of(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION pack_lineage(text), tenant_pack_code(uuid), pack_effective_value(text, text),
  pack_account_role(text, text), pack_journal_role(text, text), pack_holidays_of(text)
  TO authenticated, service_role;
