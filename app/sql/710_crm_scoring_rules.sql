-- 710 — crm_scoring_rules
-- Numéro pris le 2026-10-11T06:55:47.434Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.5 / CRM-02 (partie F du plan du 05/10) : LE SCORING DE LEAD
--
-- Le constat. La table d'un premier jet (`crm_scoring_rules`) a été SUPPRIMÉE le
-- 18/09 par la `164` (« nommée NULLE PART »). F.5 la rétablit : qualifier un
-- prospect, c'est une ADDITION — « vient d'une recommandation : +20 ; chiffre
-- d'affaires > 1 M€ : +30 ; secteur hors cible : −15 » — et le produit ne savait
-- pas la calculer.
--
-- Le modèle, et ce qui le tient :
--   * une RÈGLE dit : POUR UN FAIT (le champ), avec un OPÉRATEUR, une VALEUR,
--     elle ajoute des POINTS (positifs ou négatifs). Son nom est UNIQUE par
--     société, l'opérateur est CONTRAINT, et un opérateur de comparaison EXIGE
--     une valeur (un `greater_than` sans valeur n'est pas une règle) ;
--   * un MOTEUR (`crm_lead_score`) applique les règles ACTIVES de la société aux
--     FAITS fournis (un objet JSON : `{"source":"referral","revenue":"1500000"}`)
--     et rend le TOTAL et les RÈGLES QUI ONT COMPTÉ — jamais seulement un
--     chiffre : un score qui ne dit pas d'où il vient ne se discute pas.
--
-- CE QUI EST DROIT, ET PAS SEULEMENT ÉCRIT :
--   * un fait ABSENT ne matche JAMAIS une comparaison (seuls `is_set` /
--     `is_not_set` parlent de son absence) ;
--   * `greater_than` / `less_than` comparent en NOMBRE : un fait non numérique
--     ne matche pas (il ne devient pas 0 en silence) ;
--   * le moteur lit `tenant_id = current_tenant_id()` EXPLICITEMENT — pas
--     seulement par la RLS : un propriétaire qui contourne la RLS ne peut pas
--     additionner les règles d'une autre société.
--
-- RLS FORCÉE, index de société, QUATRE politiques sur la table. Le moteur, lui,
-- n'est PAS `SECURITY DEFINER` : il lit sous les droits de l'appelant, bornés par
-- la RLS *et* par son filtre de société.
-- ============================================================

CREATE TABLE IF NOT EXISTS crm_scoring_rules (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name       text NOT NULL,
  field      text NOT NULL,
  operator   text NOT NULL
    CHECK (operator IN ('equals', 'not_equals', 'contains', 'greater_than', 'less_than', 'is_set', 'is_not_set')),
  value      text,
  points     int NOT NULL,
  is_active  boolean NOT NULL DEFAULT true,
  position   int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name),
  -- Un opérateur de comparaison EXIGE une valeur ; `is_set`/`is_not_set` n'en veulent pas.
  CHECK (operator IN ('is_set', 'is_not_set') OR value IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_crm_scoring_rules_tenant ON crm_scoring_rules(tenant_id);

-- ============================================================
-- Le moteur : `crm_lead_score(p_facts)` — le total ET ses raisons
-- ============================================================
CREATE OR REPLACE FUNCTION crm_lead_score(p_facts jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  r         record;
  v_fact    text;
  v_match   boolean;
  v_total   int := 0;
  v_matched text[] := '{}';
  v_num     numeric;
  v_cmp     numeric;
BEGIN
  IF p_facts IS NULL THEN
    p_facts := '{}'::jsonb;
  END IF;

  FOR r IN
    SELECT name, field, operator, value, points
      FROM crm_scoring_rules
     WHERE tenant_id = current_tenant_id()   -- explicite : la RLS ne suffit pas au propriétaire
       AND is_active
     ORDER BY position, name
  LOOP
    v_fact  := p_facts ->> r.field;
    v_match := false;

    IF r.operator = 'is_set' THEN
      v_match := v_fact IS NOT NULL AND btrim(v_fact) <> '';
    ELSIF r.operator = 'is_not_set' THEN
      v_match := v_fact IS NULL OR btrim(v_fact) = '';
    ELSIF v_fact IS NULL THEN
      v_match := false;                        -- un fait absent ne matche pas une comparaison
    ELSIF r.operator = 'equals' THEN
      v_match := v_fact = r.value;
    ELSIF r.operator = 'not_equals' THEN
      v_match := v_fact <> r.value;
    ELSIF r.operator = 'contains' THEN
      v_match := v_fact ILIKE '%' || r.value || '%';
    ELSE
      -- greater_than / less_than : comparaison NUMÉRIQUE, gardée
      BEGIN
        v_num := v_fact::numeric;
        v_cmp := r.value::numeric;
      EXCEPTION WHEN OTHERS THEN
        v_num := NULL;                         -- non numérique : ne matche pas
      END;
      IF v_num IS NOT NULL AND v_cmp IS NOT NULL THEN
        IF r.operator = 'greater_than' THEN v_match := v_num > v_cmp;
        ELSIF r.operator = 'less_than' THEN v_match := v_num < v_cmp;
        END IF;
      END IF;
    END IF;

    IF v_match THEN
      v_total   := v_total + r.points;
      v_matched := v_matched || r.name;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('score', v_total, 'matched_rules', to_jsonb(v_matched));
END $$;

REVOKE ALL ON FUNCTION crm_lead_score(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm_lead_score(jsonb) TO authenticated;

-- ============================================================
-- RLS : forcée, quatre politiques (une par commande)
-- ============================================================
ALTER TABLE crm_scoring_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_scoring_rules FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS crm_scoring_rules_select ON crm_scoring_rules;
CREATE POLICY crm_scoring_rules_select ON crm_scoring_rules
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_scoring_rules_insert ON crm_scoring_rules;
CREATE POLICY crm_scoring_rules_insert ON crm_scoring_rules
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_scoring_rules_update ON crm_scoring_rules;
CREATE POLICY crm_scoring_rules_update ON crm_scoring_rules
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_scoring_rules_delete ON crm_scoring_rules;
CREATE POLICY crm_scoring_rules_delete ON crm_scoring_rules
  FOR DELETE USING (tenant_id = current_tenant_id());

-- Le visiteur n'écrit rien (défauts du schéma : `ALL` à `anon` sur toute table neuve).
REVOKE ALL ON crm_scoring_rules FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm_scoring_rules TO authenticated;
GRANT ALL ON crm_scoring_rules TO service_role;

