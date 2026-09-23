-- ============================================================
-- check_tenant_guard.sql — une fonction qui agit au nom d'une société doit
--                          vérifier que l'appelant en est membre
--
-- Le défaut trouvé le 23/09 dans le versement de la paie (224) n'était pas une
-- ligne oubliée : c'était que RIEN ne dit quand elle est oubliée. La migration
-- 212 a vécu avec le trou, et la 220 est passée juste à côté en ajoutant une
-- garde de permission au même endroit. Ce contrôle ferme la classe entière.
--
-- LA RÈGLE. Une fonction qui réunit ces trois traits :
--     * SECURITY DEFINER            → elle s'exécute hors RLS ;
--     * exécutable par `authenticated` → elle est exposée en RPC PostgREST ;
--     * elle prend un `uuid` en paramètre → l'identifiant vient du client ;
--   doit vérifier l'appartenance de l'appelant à la société visée, c'est-à-dire
--   mentionner `current_tenant_id()`, ou interroger `tenant_users` avec
--   `auth.uid()` (la mise en service, où aucune société n'est encore active),
--   ou déléguer à une fonction qui le fait.
--
--   Une garde que l'appelant peut écraser n'en est pas une :
--   `COALESCE(p_tenant_id, current_tenant_id())` donne la priorité au paramètre
--   du client et ne compte donc PAS — quatre fonctions se cachaient derrière ce
--   motif, dont une qui insérait des écritures comptables (227). L'ordre inverse,
--   `COALESCE(current_tenant_id(), p_tenant_id)`, compte : l'appelant connecté
--   l'emporte, le paramètre ne sert qu'en l'absence de contexte.
--
-- CE QUE LE CONTRÔLE NE PROUVE PAS. Il lit le texte des fonctions : il repère
-- la FORME du défaut, pas son absence. Une fonction peut mentionner
-- `current_tenant_id()` pour écrire une ligne tout en relisant une autre par
-- son seul identifiant. C'est un fil tendu en travers du chemin, pas une preuve
-- de correction — et c'est pour cela que chaque exception est inscrite à la
-- main, avec sa raison, plutôt que déduite.
--
-- LE REGISTRE. Une ligne par exception justifiée. Tant qu'un nom y figure, son
-- absence de garde ne casse pas la CI. Dès qu'il est gardé — ou qu'il disparaît
-- — la CI échoue aussi : le registre doit être nettoyé dans le même commit,
-- sinon il pourrit et le contrôle ne veut plus rien dire. Même contrat que
-- ci/expected_failures.sql.
--
-- Les surcharges sont distinguées : une fonction peut exister en version sûre
-- et en version héritée, et c'est précisément ce qui cachait deux défauts
-- (fec_export, get_journal_entry_count — voir la 227).
-- ============================================================

CREATE TEMP TABLE tenant_guard_registre (nom text, args text, raison text);

-- ── Registre des exceptions justifiées ──────────────────────
-- Format : (nom, arguments exacts, raison). Les arguments valent signature :
-- une surcharge inscrite ne couvre pas les autres.
INSERT INTO tenant_guard_registre (nom, args, raison) VALUES
  ('assert_tenant_ready', 'p_tenant_id uuid',
   'Mise en service : vérifie qu''une société est complète, avant qu''elle soit active. Lecture seule.'),
  ('convert_uom', 'p_quantity numeric, p_from_uom_id uuid, p_to_uom_id uuid',
   'Conversion d''unités : lecture d''un référentiel, aucune donnée de société.'),
  ('explode_bom_recursive', 'p_tenant_id uuid, p_bom_id uuid, p_quantity numeric, p_max_level integer',
   'Éclatement de nomenclature : lecture seule, tout est filtré par p_tenant_id.'),
  ('get_legal_parameter', 'p_code text, p_country_code text, p_date date, p_tenant_id uuid',
   'Lecture d''un paramètre légal (barèmes, taux) : référentiel, pas de donnée comptable.'),
  ('resolve_stock_account', 'p_product_id uuid',
   'Rend un code de compte pour un article : lecture seule, aucun montant.'),
  ('resolve_variation_account', 'p_product_id uuid',
   'Rend un code de compte de variation : lecture seule, aucun montant.'),
  ('vat_account_class', 'p_tenant uuid, p_account text, OUT direction text, OUT reverse_charge boolean',
   'Classe un compte de TVA : lecture du plan de TVA, aucune écriture.'),
  ('vat_reverse_charge', 'p_tenant uuid, p_code text',
   'Dit si un code de TVA est autoliquidé : lecture du plan de TVA.'),
  ('vat_self_assessed', 'p_tenant uuid, p_code text, p_base numeric, p_rate numeric',
   'Calcule la TVA autoliquidée : fonction de calcul, ne lit aucune donnée de société.');

-- ── Analyse ─────────────────────────────────────────────────
CREATE TEMP TABLE tenant_guard_corpus AS
SELECT p.oid,
       p.proname AS nom,
       pg_get_function_identity_arguments(p.oid) AS args,
       -- Les commentaires ne gardent rien, et une garde que le paramètre du
       -- client écrase non plus : les deux sont retirés avant l'analyse.
       regexp_replace(
         regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g'),
         'COALESCE\s*\(\s*p_\w+\s*,\s*current_tenant_id\s*\(\s*\)\s*\)', '', 'gi') AS corps,
       p.prosecdef,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS expose,
       'uuid'::regtype = ANY (p.proargtypes::oid[]) AS prend_uuid
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f';

-- Gardées : par signature (une surcharge sûre ne couvre pas l'héritée)
CREATE TEMP TABLE tenant_guard_gardees AS
SELECT oid, nom FROM tenant_guard_corpus
WHERE corps ~ 'current_tenant_id\s*\('
   OR (corps ~ 'tenant_users' AND corps ~ 'auth\.uid\s*\(');

CREATE TEMP TABLE tenant_guard_verdicts AS
SELECT c.nom, c.args,
       EXISTS (SELECT 1 FROM tenant_guard_gardees g WHERE g.oid = c.oid) AS garde_directe,
       EXISTS (SELECT 1 FROM tenant_guard_gardees g
               WHERE g.oid <> c.oid AND c.corps ~ ('\m' || g.nom || '\s*\(')) AS delegue,
       EXISTS (SELECT 1 FROM tenant_guard_registre r WHERE r.nom = c.nom AND r.args = c.args) AS inscrite
FROM tenant_guard_corpus c
WHERE c.prosecdef AND c.expose AND c.prend_uuid;

DO $$
DECLARE
  v_total int; v_gardees int; v_inscrites int;
  v_manquantes text; v_perimees text; v_row record;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE garde_directe OR delegue), count(*) FILTER (WHERE inscrite)
    INTO v_total, v_gardees, v_inscrites FROM tenant_guard_verdicts;

  -- Un contrôle qui n'examine rien ne prouve rien (cf. B3, 18/09)
  IF v_total = 0 THEN
    RAISE EXCEPTION 'check_tenant_guard : aucune fonction examinée — le contrôle ne vérifie rien';
  END IF;

  FOR v_row IN SELECT * FROM tenant_guard_verdicts
               WHERE NOT (garde_directe OR delegue) ORDER BY nom, args LOOP
    RAISE NOTICE '% %(%)',
      CASE WHEN v_row.inscrite THEN '🟠 inscrite au registre :' ELSE '❌ sans garde de société :' END,
      v_row.nom, left(v_row.args, 70);
  END LOOP;

  SELECT string_agg(nom || '(' || left(args, 60) || ')', ', ' ORDER BY nom) INTO v_manquantes
  FROM tenant_guard_verdicts WHERE NOT (garde_directe OR delegue) AND NOT inscrite;

  -- Registre périmé : inscrite alors qu'elle est gardée, ou disparue
  SELECT string_agg(x, ', ' ORDER BY x) INTO v_perimees FROM (
    SELECT reg.nom || '(' || left(reg.args, 60) || ')' AS x
    FROM tenant_guard_registre reg
    LEFT JOIN tenant_guard_verdicts v ON v.nom = reg.nom AND v.args = reg.args
    WHERE v.nom IS NULL OR v.garde_directe OR v.delegue
  ) s;

  RAISE NOTICE 'check_tenant_guard : % fonction(s) SECURITY DEFINER exposées prenant un uuid — % gardée(s), % inscrite(s) au registre',
    v_total, v_gardees, v_inscrites;

  IF v_manquantes IS NOT NULL THEN
    RAISE EXCEPTION E'check_tenant_guard : % fonction(s) agissent au nom d''une société sans vérifier que l''appelant en est membre :\n  %\n'
      '  Ajoutez le contrôle (current_tenant_id()), ou inscrivez-la au registre de ci/check_tenant_guard.sql avec sa raison.',
      (SELECT count(*) FROM tenant_guard_verdicts WHERE NOT (garde_directe OR delegue) AND NOT inscrite), v_manquantes;
  END IF;
  IF v_perimees IS NOT NULL THEN
    RAISE EXCEPTION E'check_tenant_guard : registre périmé — ces lignes sont désormais gardées ou ont disparu :\n  %\n'
      '  Retirez-les de ci/check_tenant_guard.sql dans le même commit que le correctif.', v_perimees;
  END IF;

  RAISE NOTICE 'Garde de société : OK — % fonction(s) examinée(s), aucune exposée sans contrôle hors registre', v_total;
END;
$$;
