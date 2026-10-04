-- ============================================================
-- 325_vat_codes_ca3.sql — codes TVA de la saisie manuelle, cases de la CA3
--
-- Défauts repérés le 22/09/2026 après la 197 :
--   - la saisie manuelle (JournalSaisiePage, SaisieParPiecePage) proposait les
--     taux de tax_rates, tous pays confondus, et enregistrait le TAUX comme code
--     ('20', '5.5') ; les modèles d'écriture un troisième codage ('V20', 'V5.5').
--     Aucun ne correspond au paramétrage (FR20, FR055…) : la ligne sortait de la
--     synthèse par code avec un taux 0 et sans case CA3 ;
--   - ca3_box mélangeait le cadre A (A1, A2, B2) et le cadre B (08) du
--     formulaire 3310-CA3 : toute la TVA collectée tombait en « A1 », les taux
--     n'étaient pas distingués, l'exonéré était en « A2 » (opérations
--     imposables) et l'autoliquidation en « B2 » (acquisitions intracommunautaires).
--
-- Correctif :
--   1. vat_account_mapping : libellé du code (label), case de la base au
--      cadre A (ca3_base_box) et case de la taxe au cadre B (ca3_tax_box) ;
--      ca3_box est conservée (compatibilité) = case de la taxe, sinon de la base ;
--   2. vat_code_normalize : un taux saisi (20, 5.5, V20, « 10 % ») devient le
--      code du paramétrage ; appliquée à l'enregistrement des lignes d'écriture
--      et des modèles, et à la lecture des déclarations (les lignes validées
--      sont immuables : l'historique n'est pas réécrit) ;
--   3. get_vat_codes : la liste proposée à la saisie, avec les comptes ;
--   4. calculate_vat_ca3 ventile la TVA par case du cadre B (08, 9B, 09, T6,
--      16, 17, 19, 20, 23, 25, 28).
--
-- Cases retenues (3310-CA3) — À FAIRE VALIDER PAR L'EXPERT-COMPTABLE :
--   cadre A : A1 ventes et prestations, A2 autres opérations imposables
--   (autoliquidation interne, art. 283-2 nonies), B2 acquisitions
--   intracommunautaires, E2 autres opérations non imposables ;
--   cadre B : 08 taux normal 20 %, 9B taux 10 %, 09 taux 5,5 %, T6 taux 2,1 %
--   (métropole), 16 total TVA brute, 17 dont acquisitions intracommunautaires,
--   19 déductible sur immobilisations, 20 déductible sur autres biens et
--   services, 23 total déductible, 25 crédit, 28 TVA nette due.
--
-- Suite : sql/325_vat_codes_ca3_tests.sql (C01 à C06).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Paramétrage : libellé et cases
-- ------------------------------------------------------------
ALTER TABLE vat_account_mapping ADD COLUMN IF NOT EXISTS label text;
ALTER TABLE vat_account_mapping ADD COLUMN IF NOT EXISTS ca3_base_box text;
ALTER TABLE vat_account_mapping ADD COLUMN IF NOT EXISTS ca3_tax_box text;
COMMENT ON COLUMN vat_account_mapping.label IS '325 — libellé du code TVA proposé à la saisie';
COMMENT ON COLUMN vat_account_mapping.ca3_base_box IS '325 — case du cadre A de la 3310-CA3 où figure la base (ligne collectée)';
COMMENT ON COLUMN vat_account_mapping.ca3_tax_box IS '325 — case du cadre B de la 3310-CA3 où figure la taxe';
COMMENT ON COLUMN vat_account_mapping.ca3_box IS '325 — compatibilité : case de la taxe, sinon de la base';

UPDATE vat_account_mapping m
SET label = v.label, ca3_base_box = v.base_box, ca3_tax_box = v.tax_box,
    ca3_box = COALESCE(v.tax_box, v.base_box)
FROM (VALUES
  ('FR20',    'collected',  'TVA 20 %',                        'A1', '08'),
  ('FR10',    'collected',  'TVA 10 %',                        'A1', '9B'),
  ('FR055',   'collected',  'TVA 5,5 %',                       'A1', '09'),
  ('FR021',   'collected',  'TVA 2,1 %',                       'A1', 'T6'),
  ('FR0',     'collected',  'TVA 0 %',                         'E2', NULL),
  ('EXO',     'collected',  'Exonéré',                         'E2', NULL),
  ('UE',      'collected',  'Acquisition intracommunautaire',  'B2', '08'),
  ('AUTOLIQ', 'collected',  'Autoliquidation (art. 283 CGI)',  'A2', '08'),
  ('FR20',    'deductible', 'TVA 20 %',                        NULL, '20'),
  ('FR10',    'deductible', 'TVA 10 %',                        NULL, '20'),
  ('FR055',   'deductible', 'TVA 5,5 %',                       NULL, '20'),
  ('FR021',   'deductible', 'TVA 2,1 %',                       NULL, '20'),
  ('UE',      'deductible', 'Acquisition intracommunautaire',  NULL, '20'),
  ('AUTOLIQ', 'deductible', 'Autoliquidation (art. 283 CGI)',  NULL, '20')
) AS v(vat_code, direction, label, base_box, tax_box)
WHERE m.tenant_id = '00000000-0000-0000-0000-000000000000'
  AND m.vat_code = v.vat_code AND m.direction = v.direction;

-- Surcharges société : libellé et cases du code global quand elles n'en ont pas
UPDATE vat_account_mapping m
SET label = COALESCE(m.label, g.label), ca3_base_box = COALESCE(m.ca3_base_box, g.ca3_base_box),
    ca3_tax_box = COALESCE(m.ca3_tax_box, g.ca3_tax_box), ca3_box = COALESCE(m.ca3_tax_box, g.ca3_tax_box, m.ca3_base_box, g.ca3_base_box)
FROM vat_account_mapping g
WHERE g.tenant_id = '00000000-0000-0000-0000-000000000000' AND m.tenant_id <> g.tenant_id
  AND g.vat_code = m.vat_code AND g.direction = m.direction;

-- ------------------------------------------------------------
-- 2. Normalisation des codes
-- ------------------------------------------------------------
-- Un taux saisi (« 20 », « 5.5 », « 5,5 % », « V20 ») : code non autoliquidé de
-- même taux (société d'abord, codes FR d'abord). Code inconnu : conservé tel quel.
CREATE OR REPLACE FUNCTION vat_code_normalize(p_tenant uuid, p_code text)
RETURNS text
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v text := NULLIF(btrim(p_code), ''); v_rate numeric; v_found text;
BEGIN
  IF v IS NULL THEN RETURN NULL; END IF;
  SELECT m.vat_code INTO v_found FROM vat_account_mapping m
  WHERE m.tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000') AND upper(m.vat_code) = upper(v)
  ORDER BY (m.vat_code = v) DESC LIMIT 1;
  IF v_found IS NOT NULL THEN RETURN v_found; END IF;
  IF v ~* '^v?\s*[0-9]+([.,][0-9]+)?\s*%?$' THEN
    v_rate := replace(regexp_replace(v, '[^0-9.,]', '', 'g'), ',', '.')::numeric;
    SELECT m.vat_code INTO v_found FROM vat_account_mapping m
    WHERE m.tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000')
      AND m.direction = 'collected' AND NOT m.reverse_charge AND m.rate = v_rate
    ORDER BY (m.tenant_id = p_tenant) DESC, (m.vat_code LIKE 'FR%') DESC, m.vat_code LIMIT 1;
    RETURN COALESCE(v_found, v);
  END IF;
  RETURN v;
END $$;

-- Lignes de pièces (factures, avoirs) : même règle, sans société (paramétrage global)
CREATE OR REPLACE FUNCTION line_vat_code(p_code text, p_rate numeric)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE WHEN p_code IS NULL OR btrim(p_code) = '' OR (p_code = 'FR20' AND COALESCE(p_rate, 0) <> 20)
              THEN vat_code_for_rate(p_rate)
              -- taux saisi comme code : converti s'il est l'un des taux du paramétrage (sinon conservé)
              WHEN btrim(p_code) ~* '^v?\s*[0-9]+([.,][0-9]+)?\s*%?$'
                   AND replace(regexp_replace(p_code, '[^0-9.,]', '', 'g'), ',', '.')::numeric IN (20, 10, 5.5, 2.1, 0)
              THEN vat_code_for_rate(replace(regexp_replace(p_code, '[^0-9.,]', '', 'g'), ',', '.')::numeric)
              ELSE p_code END
$$;

-- Le trigger s'exécute à chaque ligne d'écriture (100 000 écritures au test de
-- propriété) : il ne consulte le paramétrage que si le code n'a pas déjà la forme
-- d'un code (majuscules), c'est-à-dire s'il ressemble à un taux ou à une variante
-- de casse. Une ligne sans code, ou déjà codée FR20, ne coûte qu'une expression
-- régulière.
CREATE OR REPLACE FUNCTION journal_line_vat_code_normalize()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP <> 'INSERT' AND NEW.vat_code IS NOT DISTINCT FROM OLD.vat_code THEN
    RETURN NEW;
  END IF;
  IF NEW.vat_code IS NULL THEN
    RETURN NEW;
  END IF;
  -- ⚠️ DÉFAUT 325, MESURÉ LE 02/10/2026 À SA PREMIÈRE EXÉCUTION.
  --
  -- Le test de normalisation d'origine était `NEW.vat_code ~ '^[A-Z][A-Z0-9]*$'` :
  -- il disait « si le code ressemble déjà à un code, n'y touche pas ».
  -- `V20` ressemble à un code — majuscule, alphanumérique — et c'est
  -- justement une SAISIE DE TAUX que l'utilisateur ne fallait pas laisser
  -- telle quelle. Le déclencheur sortait donc au pas, et la ligne restait
  -- `V20` en base : la vente disparaissait de la synthèse (base 0, taux 0,
  -- sans case), ce que le plan mesurait (« avec `20` : base 0, taux 0,
  -- sans case »).
  --
  -- On ne devine plus la FORME du code : on demande au paramétrage. La
  -- normalisation est sans effet sur un code déjà normalisé — `vat_code_normalize`
  -- retrouve le même code et le renvoie — donc l'appeler toujours est plus
  -- simple et ne peut pas se tromper de format.
  --
  -- Le garde de performance reste : une écriture qui MODIFIE un code déjà
  -- conforme ne refait rien (ligne 135-137).
  NEW.vat_code := vat_code_normalize(NEW.tenant_id, NEW.vat_code);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_journal_line_vat_code ON journal_lines;
CREATE TRIGGER tg_journal_line_vat_code
  BEFORE INSERT OR UPDATE OF vat_code ON journal_lines
  FOR EACH ROW EXECUTE FUNCTION journal_line_vat_code_normalize();

CREATE OR REPLACE FUNCTION entry_template_vat_code_normalize()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF jsonb_typeof(NEW.template_lines) = 'array' THEN
    NEW.template_lines := (
      SELECT COALESCE(jsonb_agg(CASE WHEN jsonb_typeof(x) = 'object' AND x ? 'vat_code' AND jsonb_typeof(x->'vat_code') = 'string'
                                     THEN jsonb_set(x, '{vat_code}', COALESCE(to_jsonb(vat_code_normalize(NEW.tenant_id, x->>'vat_code')), 'null'::jsonb))
                                     ELSE x END ORDER BY o), '[]'::jsonb)
      FROM jsonb_array_elements(NEW.template_lines) WITH ORDINALITY AS a(x, o));
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_entry_template_vat_code ON entry_templates;
CREATE TRIGGER tg_entry_template_vat_code
  BEFORE INSERT OR UPDATE OF template_lines ON entry_templates
  FOR EACH ROW EXECUTE FUNCTION entry_template_vat_code_normalize();

-- ------------------------------------------------------------
-- 3. Codes proposés à la saisie (le paramétrage global n'est pas lisible
--    d'un utilisateur : RLS de vat_account_mapping)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_vat_codes()
RETURNS TABLE(vat_code text, label text, rate numeric, reverse_charge boolean,
              collected_account text, deductible_account text, ca3_base_box text, ca3_tax_box text)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  WITH m AS (
    SELECT DISTINCT ON (x.vat_code, x.direction) x.*
    FROM vat_account_mapping x
    WHERE x.tenant_id IN (v_tid, '00000000-0000-0000-0000-000000000000')
    ORDER BY x.vat_code, x.direction, (x.tenant_id = v_tid) DESC
  ), c AS (SELECT * FROM m WHERE m.direction = 'collected'),
     d AS (SELECT * FROM m WHERE m.direction = 'deductible')
  SELECT COALESCE(c.vat_code, d.vat_code), COALESCE(c.label, d.label, c.vat_code, d.vat_code),
         COALESCE(c.rate, d.rate), COALESCE(c.reverse_charge, d.reverse_charge, false),
         c.account_code, d.account_code, c.ca3_base_box, COALESCE(c.ca3_tax_box, d.ca3_tax_box)
  FROM c FULL JOIN d ON d.vat_code = c.vat_code
  ORDER BY COALESCE(c.reverse_charge, d.reverse_charge, false), COALESCE(c.rate, d.rate) DESC, 1;
END $$;
REVOKE ALL ON FUNCTION get_vat_codes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_vat_codes() TO authenticated, service_role;

-- ⚠️ DROITS. `CREATE FUNCTION` rend EXECUTE à PUBLIC : sans ces REVOKE, les
-- quatre fonctions de cette migration seraient APPELABLES PAR UN VISITEUR NON
-- CONNECTÉ, comme 332 autres l'étaient avant la 228 (mesuré ce jour :
-- `check_anon_grants` les exposait toutes les quatre). Trois d'entre elles sont
-- des fonctions de DÉCLENCHEMENT : elles ne s'appellent pas depuis l'écran et
-- n'ont rien à faire d'un appel extérieur. On retire donc l'accès à `PUBLIC`,
-- `anon` et `authenticated` — même traitement que les fonctions de la 323 et de
-- la 324, qui l'étaient pour la même raison.
--
-- ⚠️ Chaque REVOKE suit la création de sa fonction : posée avant, la migration
-- échoue sur « function does not exist ». Celle de `vat_account_ca3` est donc
-- plus bas, après sa définition.
REVOKE ALL ON FUNCTION vat_code_normalize(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION journal_line_vat_code_normalize() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION entry_template_vat_code_normalize() FROM PUBLIC, anon, authenticated;

-- Cases CA3 d'un compte de TVA : paramétrage (société d'abord), sinon racine
CREATE OR REPLACE FUNCTION vat_account_ca3(p_tenant uuid, p_account text, OUT tax_box text, OUT base_box text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(m.ca3_tax_box, CASE WHEN p_account ~ '^44562' THEN '19' WHEN p_account ~ '^4456' THEN '20' END),
         COALESCE(m.ca3_base_box, CASE WHEN p_account ~ '^4452' THEN 'B2' END)
  FROM (SELECT 1) one
  LEFT JOIN LATERAL (SELECT x.ca3_tax_box, x.ca3_base_box FROM vat_account_mapping x
                     WHERE x.tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000') AND x.account_code = p_account
                     ORDER BY (x.tenant_id = p_tenant) DESC, (x.ca3_tax_box IS NULL), x.vat_code LIMIT 1) m ON true
$$;

REVOKE ALL ON FUNCTION vat_account_ca3(uuid, text, OUT text, OUT text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 4. Declaration par case — RETIREE VOLONTAIREMENT.
--
-- Ce bloc etait celui de la 197 : il ventilait la declaration par case
-- (08, 9B, 16, 17, 20, 23). La 300 l'a repris et l'a volontairement
-- remplacee : la ventilation par case demande les PIECES DE VENTE (le code
-- de TVA porte par la ligne), pas seulement le grand livre, et rien dans
-- l'application ne lit plus `ca3`.
--
-- Il est retire ici precisement parce que le 325 s'execute APRES le 300 :
-- redefinir la fonction ici l'aurait remise en service par le dessous, et
-- le test C05 aurait cru voir des cases que plus personne ne produit. La 300
-- reste la seule version de cette fonction.
-- ------------------------------------------------------------

-- Synthèse par code : code normalisé (l'historique saisi sous un taux retrouve son
-- code), case de la taxe du cadre B
CREATE OR REPLACE FUNCTION public.get_vat_summary_by_code(
  p_fiscal_year_id uuid,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL
)
RETURNS TABLE(vat_code text, direction text, account_code text, ca3_box text, base_ht numeric, vat_amount numeric, rate numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Les dates reçues priment : le formulaire passe toujours l'exercice courant
  -- (accounting.ts:172), et borner décembre à l'exercice suivant rendait zéro.
  -- L'exercice ne sert plus que de repli quand aucune date n'est donnée.
  WITH bornes AS (
    SELECT COALESCE(p_date_from, fy.start_date) AS d1, COALESCE(p_date_to, fy.end_date) AS d2
    FROM (SELECT start_date, end_date FROM fiscal_years
          WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()) fy
    RIGHT JOIN (SELECT 1) one ON true
  ), l AS (
    SELECT a.acc,
           -- une ligne saisie à la main n'a pas de code : le déduire du compte
           -- ET une ligne d'historique peut porter un taux brut (« 20 », « V20 »,
           -- « 10 % ») : on le normalise, sinon le code reste sans correspondance
           -- dans le paramétrage et la ligne disparaît de la synthèse — pas de
           -- case, pas de taux, base 0. Une ligne validée étant immuable, on ne
           -- peut pas la réécrire : la lecture doit être la repairsse.
           COALESCE(NULLIF(vat_code_normalize(jl.tenant_id, jl.vat_code), ''),
                    m0.vat_code, a.acc) AS vat_code,
           c.direction,
           CASE c.direction WHEN 'collected' THEN jl.credit - jl.debit
                            ELSE jl.debit - jl.credit END AS amount,
           jl.tenant_id
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    CROSS JOIN LATERAL (SELECT COALESCE(jl.account_general, jl.account_code) AS acc) a
    CROSS JOIN LATERAL vat_account_class(jl.tenant_id, a.acc) c
    LEFT JOIN LATERAL (SELECT x.vat_code FROM vat_account_mapping x
                       WHERE x.tenant_id IN (jl.tenant_id, '00000000-0000-0000-0000-000000000000')
                         AND x.account_code = a.acc AND x.direction = c.direction
                       ORDER BY (x.tenant_id = jl.tenant_id) DESC, x.rate DESC, x.vat_code LIMIT 1) m0 ON true
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date >= b.d1 AND je.date <= b.d2
      AND COALESCE(je.journal_code, '') NOT IN ('AN', 'CL')
      AND c.direction IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM journal_lines x
                      WHERE x.journal_id = je.id
                        AND COALESCE(x.account_general, x.account_code) ~ '^(4455|44567)')
  ), g AS (
    SELECT l.vat_code, l.direction, l.acc, l.tenant_id, round(sum(l.amount), 2) AS amount
    FROM l GROUP BY 1, 2, 3, 4
  )
  SELECT g.vat_code, g.direction, g.acc, m.ca3_box,
         CASE WHEN COALESCE(m.rate, 0) > 0 THEN round(g.amount / (m.rate / 100), 2) ELSE 0 END,
         g.amount,
         COALESCE(m.rate, 0)
  FROM g
  LEFT JOIN LATERAL (SELECT x.ca3_box, x.rate FROM vat_account_mapping x
                     WHERE x.tenant_id IN (g.tenant_id, '00000000-0000-0000-0000-000000000000')
                       AND x.vat_code = g.vat_code AND x.direction = g.direction
                     ORDER BY (x.tenant_id = g.tenant_id) DESC LIMIT 1) m ON true
  ORDER BY g.direction, g.vat_code;
$function$;

-- ------------------------------------------------------------
-- 5. Reprise : écritures en brouillon et modèles (les lignes validées restent
--    telles quelles et sont normalisées à la lecture)
-- ------------------------------------------------------------
UPDATE journal_lines jl SET vat_code = vat_code_normalize(jl.tenant_id, jl.vat_code)
FROM journal_entries je
WHERE je.id = jl.journal_id AND je.status IS DISTINCT FROM 'posted'
  AND jl.vat_code IS NOT NULL
  AND jl.vat_code IS DISTINCT FROM vat_code_normalize(jl.tenant_id, jl.vat_code);

UPDATE entry_templates t SET template_lines = t.template_lines
WHERE jsonb_typeof(t.template_lines) = 'array'
  AND EXISTS (SELECT 1 FROM jsonb_array_elements(t.template_lines) x
              WHERE jsonb_typeof(x) = 'object' AND jsonb_typeof(x->'vat_code') = 'string'
                AND x->>'vat_code' IS DISTINCT FROM vat_code_normalize(t.tenant_id, x->>'vat_code'));

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.status = 'posted' AND jl.vat_code IS NOT NULL
    AND jl.vat_code IS DISTINCT FROM vat_code_normalize(jl.tenant_id, jl.vat_code);
  RAISE NOTICE '325 : % ligne(s) validée(s) portent un taux comme code TVA (normalisées à la lecture des déclarations)', n;
END $$;
